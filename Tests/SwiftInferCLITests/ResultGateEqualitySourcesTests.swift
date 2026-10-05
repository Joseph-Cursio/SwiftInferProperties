import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `==` the scan sees arrive without an inheritance clause — a hand-written operator, or an
/// attribute that may be a macro — keeps `UnequatableResultGate` from declining, on the result and
/// on any link of its conformance chain. `DeterminismResultEqualityDiscoverTests` carries the same
/// evidence end to end through `discover`.
@Suite("UnequatableResultGate — `==` from outside an inheritance clause")
struct ResultGateEqualitySourcesTests {

    static func outside(_ source: String) -> Set<String> {
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Probe.swift")
        return UnequatableResultGate.equalityOutsideInheritance(
            typeDecls: corpus.typeDecls, summaries: corpus.summaries
        )
    }

    static func reason(_ result: String, in source: String) -> String? {
        let scan = UnequatableResultGateTests.scan(["Probe.swift": source])
        return UnequatableResultGate.declineReason(
            display: "fix(_:)",
            returnTypeText: result,
            owner: "Fixer",
            typeShapesByName: scan.shapes,
            inheritedTypesByName: scan.inherited,
            equalityOutsideInheritance: outside(source)
        )
    }

    // MARK: - What is collected

    @Test func aMemberOperatorNamesItsOwnerUnderBothSpellings() {
        let names = Self.outside("""
            enum Ledger {
                struct Entry {
                    static func == (lhs: Entry, rhs: Entry) -> Bool { true }
                }
            }
            """)
        #expect(names.isSuperset(of: ["Entry", "Ledger.Entry"]))
    }

    @Test func anOperatorInAnExtensionOrAtFileScopeIsCollected() {
        let names = Self.outside("""
            struct Reading { let value: Int }
            extension Reading { static func == (lhs: Reading, rhs: Reading) -> Bool { true } }
            struct Grade { let value: Int }
            func == (lhs: Grade, rhs: Grade) -> Bool { true }
            protocol Measured {}
            extension Measured { static func == (lhs: Self, rhs: Self) -> Bool { true } }
            """)
        #expect(names.isSuperset(of: ["Reading", "Grade", "Measured"]))
    }

    /// Only `==` counts: `<` and `!=` do not give a type `==`.
    @Test func anotherOperatorIsNotCollected() {
        #expect(Self.outside("""
            struct Plain { let value: Int }
            extension Plain { static func < (lhs: Plain, rhs: Plain) -> Bool { true } }
            """).isEmpty)
    }

    @Test("an attribute that may be a macro is collected; the compiler's own are not", arguments: [
        ("@Model\nfinal class Item {}", true),
        ("@SwiftData.Model\nfinal class Item {}", true),
        ("@MainActor @Observable\nfinal class Item {}", false),
        ("@available(macOS 14, *)\nstruct Item {}", false),
        ("@frozen public struct Item {}", false)
    ])
    func anAttributeThatMayBeAMacroIsCollected(source: String, collected: Bool) {
        #expect(Self.outside(source).contains("Item") == collected)
    }

    // MARK: - What the gate does with it

    @Test func aResultWithAHandWrittenOperatorIsLetThrough() {
        let source = """
            struct Reading {
                let value: Int
                static func == (lhs: Reading, rhs: Reading) -> Bool { true }
            }
            """
        #expect(Self.reason("Reading", in: source) == nil)
        #expect(Self.reason("[Reading]?", in: source) == nil)
    }

    /// A link counts as much as the result: a superclass's `==`, or a protocol extension's, is found
    /// by operator lookup for every subclass or conformer. Each chain otherwise ends in names known
    /// to stop short of `Equatable`, so without the operator it declines (the control below).
    @Test("a chain link with a hand-written operator lets the result through", arguments: [
        "class Base { static func == (lhs: Base, rhs: Base) -> Bool { true } }\nfinal class Result: Base {}",
        "protocol Measured: CustomStringConvertible {}\n"
            + "extension Measured { static func == (lhs: Self, rhs: Self) -> Bool { true } }\n"
            + "struct Result: Measured { var description: String }"
    ])
    func aChainLinkWithAHandWrittenOperatorLetsTheResultThrough(source: String) {
        #expect(Self.reason("Result", in: source) == nil)
    }

    /// The control: the same shapes with no `==` anywhere still decline.
    @Test("with no operator the chain still declines", arguments: [
        "class Base {}\nfinal class Result: Base {}",
        "protocol Measured: CustomStringConvertible {}\nstruct Result: Measured { var description: String }"
    ])
    func withNoOperatorTheChainStillDeclines(source: String) {
        #expect(Self.reason("Result", in: source)?.contains("makes Result Equatable") == true)
    }

    // MARK: - What the scanner records

    @Test func theScannerRecordsEachAttributeByName() throws {
        let corpus = FunctionScanner.scanCorpus(source: """
            @MainActor @SwiftData.Model
            final class Item {}
            @available(macOS 14, *)
            extension Item {}
            #if DEBUG
            @frozen
            #endif
            struct Plain {}
            """, file: "Probe.swift")
        let item = try #require(corpus.typeDecls.first { $0.name == "Item" && $0.kind == .class })
        #expect(item.attributeNames == ["MainActor", "SwiftData.Model"])
        let extended = try #require(corpus.typeDecls.first { $0.name == "Item" && $0.kind == .extension })
        #expect(extended.attributeNames == ["available"])
        let plain = try #require(corpus.typeDecls.first { $0.name == "Plain" })
        #expect(plain.attributeNames == ["#if"])
    }
}
