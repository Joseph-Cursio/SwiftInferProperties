import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `UnequatableResultGate` judges only the types whose `==` comparing two results actually needs —
/// and follows a conformance through every link, however the link is spelled.
///
/// Each "left alone" row below is a result whose `f(x) == f(x)` compiles (checked with `swiftc`,
/// Swift 6.4), and which the gate used to decline by reading every identifier in the spelling:
/// `KeyPath<Row, String>` is `Hashable` whatever `Row` is, and so is a phantom-tagged wrapper. A
/// decline there withdraws a stub that compiled, which is the one thing the gate must not do.
@Suite("UnequatableResultGate — only the operands `==` needs, through every link")
struct UnequatableResultGateOperandTests {

    static let source = """
        struct FixResult { let text: String }
        struct ProbeUser {}
        struct ProbeTagged<Tag, Raw: Hashable>: Hashable { let raw: Raw }
        struct Handle<T>: Equatable { let id: Int }
        struct Box<T> { let item: T }
        enum Ledger {
            class Entry: Equatable {
                static func == (lhs: Entry, rhs: Entry) -> Bool { true }
            }
        }
        final class Credit: Ledger.Entry {}
        final class Debit: Ledger.Entry, CustomStringConvertible { var description: String { "debit" } }
        struct Item: Sendable {}
        final class Row: SomeKit.Item {}
        """

    static let scan = UnequatableResultGateTests.scan(["Probe.swift": source])

    // MARK: - Left alone: `==` does not need the argument

    @Test("a scanned type that only a non-wrapping generic names is not judged", arguments: [
        "KeyPath<FixResult, String>",
        "WritableKeyPath<FixResult, String>?",
        "UnsafePointer<FixResult>",
        "ProbeTagged<ProbeUser, Int>",
        "Handle<FixResult>",
        "[Handle<FixResult>]"
    ])
    func aNonWrappingGenericArgumentIsNotJudged(result: String) {
        #expect(UnequatableResultGateTests.reason(result, in: Self.scan) == nil)
    }

    /// `==` over a standard wrapper needs its elements', so these still decline — the old stub
    /// never compiled.
    @Test("an argument a standard wrapper compares is still judged", arguments: [
        "[String: FixResult]",
        "Set<FixResult>",
        "Swift.Optional<FixResult>",
        "Result<FixResult, Never>",
        "[[FixResult]]?",
        "(label: FixResult, count: Int)",
        "ContiguousArray<FixResult>"
    ])
    func aWrappedArgumentIsStillJudged(result: String) throws {
        let reason = try #require(UnequatableResultGateTests.reason(result, in: Self.scan))
        #expect(reason.contains("makes FixResult Equatable"))
    }

    /// A scanned generic is judged by its own conformance, whatever its arguments.
    @Test func aScannedGenericIsJudgedByItsOwnName() throws {
        let reason = try #require(UnequatableResultGateTests.reason("Box<Int>", in: Self.scan))
        #expect(reason == "fix(_:) returns Box<Int>, and no scanned declaration makes Box Equatable, "
            + "so `==` cannot compare two results")
        #expect(UnequatableResultGateTests.reason("ProbeTagged<FixResult, Int>", in: Self.scan) == nil)
    }

    // MARK: - Every link of a chain

    /// `Credit`'s clause names `Ledger.Entry`; the index keys that declaration by its bare name,
    /// `Entry`, and the shape by its qualified one. The gate used to look the link up under the
    /// spelling alone, miss, and count a scanned superclass as *not Equatable*.
    @Test("a superclass spelled with its qualified, nested name is followed", arguments: ["Credit", "Debit"])
    func aQualifiedNestedSuperclassIsFollowed(result: String) {
        #expect(Self.scan.inherited["Ledger.Entry"] == nil, "the index holds the bare key only")
        #expect(UnequatableResultGateTests.reason(result, in: Self.scan) == nil)
    }

    /// The other half of reading a link under its bare name: a link the scan never saw is not read
    /// through a scanned type that happens to share its last component. `SomeKit.Item` may supply
    /// `==`; the scanned `Item: Sendable` says nothing about it.
    @Test func aForeignLinkIsNotReadThroughASameNamedScannedType() {
        #expect(Self.scan.inherited["Item"] == ["Sendable"])
        #expect(UnequatableResultGateTests.reason("Row", in: Self.scan) == nil)
    }

    // MARK: - An enum the scan shows no cases for

    /// The scan reads an enum's direct members only, so cases inside `#if` are not captured — and
    /// an enum whose cases are all payload-free is `Equatable` (`swiftc`). Declining an enum with
    /// no captured case would withdraw this stub, which compiles.
    @Test func anEnumWhoseCasesSitInsideAnIfConfigIsLetThrough() throws {
        let scan = UnequatableResultGateTests.scan([
            "Platform.swift": "enum Platform {\n#if os(macOS)\n    case mac\n#else\n    case other\n#endif\n}"
        ])
        let shape = try #require(scan.shapes["Platform"])
        #expect(shape.enumCases.isEmpty, "the scan cannot see the cases")
        #expect(UnequatableResultGateTests.reason("Platform", in: scan) == nil)
    }

    /// So a caseless enum is let through too, though Swift gives it no `==`: the scan cannot tell it
    /// from the one above, and a function returning an uninhabited type never returns, so there is
    /// no real subject to lose.
    @Test func aCaselessEnumIsLetThroughBecauseItLooksTheSame() {
        let scan = UnequatableResultGateTests.scan(["Namespace.swift": "enum Namespace {}"])
        #expect(UnequatableResultGateTests.reason("Namespace?", in: scan) == nil)
    }
}
