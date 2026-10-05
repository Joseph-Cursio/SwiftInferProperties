import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `discover --docstring-advice` end to end: the reference oracle spells its call the way
/// `accept` spells the determinism law, or prints one line saying why it cannot.
///
/// Before this, every scaffold here was printed and none compiled: `isValidQuantity(value)` for a
/// static member, `scaled(value)` with no receiver, an underived `[Item].gen()`, a bare call to a
/// `throws` function, a `private` member no test can reach, `[T].gen()` for a generic function, a
/// drawn `let` passed `inout`, `(Int) -> Int.gen()`, `==` over a struct with no `Equatable`, and
/// `any Shape.gen()`. Each fixture function is seeded, so each has the synthesized determinism law
/// to take its seed and generators from.
@Suite("Discover — the reference oracle compiles, or says why it cannot")
struct DiscoverReferenceOracleTests {

    private struct SilentDiagnostics: DiagnosticOutput {
        func writeDiagnostic(_: String) { /* no-op */ }
    }

    static let source = """
    struct Inventory {
        /// The quantity is valid when it is finite and not negative.
        static func isValidQuantity(_ quantity: Double) -> Bool { quantity.isFinite && quantity >= 0 }
    }

    struct Ruler {
        let unit: Int

        /// The scaled length is the length times the unit, never negative.
        func scaled(_ length: Int) -> Int { max(length * unit, 0) }
    }

    struct Item {
        let weight: Int
    }

    enum Scale {
        /// The total is the sum of every item's weight.
        static func total(of items: [Item]) -> Int { items.reduce(0) { $0 + $1.weight } }
    }

    actor Ledger {
        let name: String

        static func gen() -> Gen<Ledger> { Gen.always(Ledger(name: "")) }

        /// Returns the number of characters in the entry.
        func count(of entry: String) -> Int { entry.count }

        /// Returns the entry in lower case, and never reads the ledger.
        nonisolated func normalized(_ entry: String) -> String { entry.lowercased() }
    }

    enum Parser {
        /// Returns the decimal number the text spells.
        static func parse(_ text: String) throws -> Int { Int(text) ?? 0 }
    }

    enum Labels {
        /// Returns the name in upper case.
        private static func label(_ name: String) -> String { name.uppercased() }
    }

    enum Picks {
        /// Returns the smallest element, or nil when there is none.
        static func smallest<T: Comparable>(_ items: [T]) -> T? { items.min() }
    }

    enum Counter {
        /// Returns the current value plus one, and stores it.
        static func advance(_ value: inout Int) -> Int { value += 1; return value }
    }

    enum Apply {
        /// Returns the transform applied to the value twice.
        static func twice(_ transform: (Int) -> Int, to value: Int) -> Int { transform(transform(value)) }
    }

    struct Report {
        let lines: [String]
    }

    enum Builder {
        /// Returns a report with one line per name, in order.
        static func report(for names: [String]) -> Report { Report(lines: names) }
    }

    protocol Shape {
        var area: Double { get }
    }

    enum Geometry {
        /// Returns twice the shape's area.
        static func doubledArea(of shape: any Shape) -> Double { shape.area * 2 }
    }

    enum Log {
        /// Records the message in the shared log, exactly once.
        static func record(_ message: String) { print(message) }
    }

    private struct Vault {
        let code: Int
    }

    final class Handle {
        private init() {}
    }

    enum Handles {
        /// Returns the number of handles, never negative.
        static func tally(_ handles: [Handle]) -> Int { handles.count }
    }

    extension Vault {
        /// Returns the code doubled, never negative.
        static func doubled(_ code: Int) -> Int { abs(code * 2) }
    }
    """

    static let symbols = [
        "isValidQuantity", "scaled", "total", "count", "parse", "label", "smallest", "advance", "twice",
        "report", "doubledArea", "record", "doubled", "tally", "normalized"
    ]

    /// The full advisory block for the fixture, every function seeded.
    static func advice() throws -> (text: String, directory: URL) {
        let directory = try writeDPFixture(name: "DocAdviceReferenceOracle", contents: source)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            docstringAdvice: true,
            seedManifest: SeedManifest(seeds: symbols.map { .init(file: "Source.swift", line: 1, symbol: $0) }),
            output: recording,
            diagnostics: SilentDiagnostics()
        )
        return (DiscoverDocstringAdviceSeedFocusTests.mainBlock(of: recording.text), directory)
    }

    /// One function's entry: from its bullet to the next bullet or the end of the block.
    static func entry(_ displayName: String, in block: String) -> String {
        guard let start = block.range(of: "  • \(displayName)  ")?.lowerBound else { return "" }
        let rest = block[start...]
        let next = rest.dropFirst().range(of: "\n  • ")?.lowerBound ?? rest.endIndex
        return String(rest[..<next])
    }

    static func scaffold(_ displayName: String) throws -> String {
        entry(displayName, in: try advice().text)
    }

    @Test func aStaticMemberIsQualified() throws {
        let entry = try Self.scaffold("isValidQuantity(_:)")
        #expect(entry.contains(
            "extension Inventory {\n        static func isValidQuantity_reference(_ quantity: Double) -> Bool {"
        ))
        #expect(entry.contains(
            "{ value in Inventory.isValidQuantity(value) == Inventory.isValidQuantity_reference(value) }"
        ))
    }

    @Test func anInstanceMemberDrawsItsReceiverFromTheResolver() throws {
        let entry = try Self.scaffold("scaled(_:)")
        #expect(entry.contains("let arg0 = (Gen<Int>.int().map { Ruler(unit: $0) }).run(using: &rng)"))
        #expect(entry.contains("{ (args: (Ruler, Int)) in args.0.scaled(args.1) == args.0.scaled_reference(args.1) }"))
        #expect(entry.contains("no generator derived") == false)
        #expect(entry.contains(".todo") == false)
    }

    @Test func anArrayOfAProjectTypeIsComposedByTheResolver() throws {
        let entry = try Self.scaffold("total(of:)")
        #expect(entry.contains(
            "sample: { rng in (Gen<Int>.int().map { Item(weight: $0) }.array(of: 0...8)).run(using: &rng) }"
        ))
        #expect(entry.contains("{ value in Scale.total(of: value) == Scale.total_reference(of: value) }"))
    }

    @Test func anActorMethodIsAwaited() throws {
        let entry = try Self.scaffold("count(of:)")
        #expect(entry.contains("let arg0 = (Ledger.gen()).run(using: &rng)"))
        #expect(entry.contains(
            "{ (args: (Ledger, String)) in await args.0.count(of: args.1) == args.0.count_reference(of: args.1) }"
        ))
    }

    /// A `nonisolated` actor member is called with no `await`, so its reference must be
    /// `nonisolated` too: an isolated one cannot be called synchronously from the property.
    @Test func aNonisolatedActorMemberIsNotAwaitedAndItsReferenceIsNonisolated() throws {
        let entry = try Self.scaffold("normalized(_:)")
        #expect(entry.contains("        nonisolated func normalized_reference(_ entry: String) -> String {"))
        #expect(entry.contains(
            "{ (args: (Ledger, String)) in args.0.normalized(args.1) == args.0.normalized_reference(args.1) }"
        ))
    }

    @Test func aThrowingStaticComparesTryOnBothSides() throws {
        let entry = try Self.scaffold("parse(_:)")
        #expect(entry.contains("    static func parse_reference(_ text: String) throws -> Int {"))
        #expect(entry.contains("{ value in (try? Parser.parse(value)) == (try? Parser.parse_reference(value)) }"))
    }
}
