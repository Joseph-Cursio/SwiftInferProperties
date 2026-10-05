import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `discover --docstring-advice` end to end, on the shapes the first version of the reworked
/// reference oracle still printed and the compiler rejected:
///
/// - a parameter or result naming a type nested BESIDE the owner (`Library.Book` used in
///   `Library.Shelf`), which `extension Library.Shelf` cannot see unqualified;
/// - a typealias nested in the receiver's type, which the `@Test`'s `(args: (A, B))` binding could
///   not see;
/// - a member of `extension [Bead]`, whose test was named `[Bead]_totalWeight_…`;
/// - a static member of a constrained `extension Array`, whose reference sits in a plain one;
/// - an existential or opaque result, and a static member of a protocol extension.
///
/// Each was checked with `swiftc -typecheck` against the printed text before and after.
@Suite("Discover — the reference oracle spells nested names and owners so they resolve, or declines")
struct DiscoverReferenceOracleSpellingTests {

    private struct SilentDiagnostics: DiagnosticOutput {
        func writeDiagnostic(_: String) { /* no-op */ }
    }

    static let source = """
    enum Library {
        struct Book: Equatable {
            let pages: Int
        }

        enum Shelf {
            /// Returns the book with its page count doubled.
            static func thickened(_ book: Book) -> Book { Book(pages: book.pages * 2) }
        }
    }

    struct Account {
        typealias OwnerID = Int

        let owner: Int

        /// Returns whether the id owns the account, exactly when the two match.
        func isOwned(by id: OwnerID) -> Bool { owner == id }
    }

    struct Bead {
        let weight: Int
    }

    extension [Bead] {
        /// Returns the total weight plus the bonus.
        func totalWeight(plus bonus: Int) -> Int { reduce(bonus) { $0 + $1.weight } }
    }

    extension Array where Element == Int {
        /// Returns as many zeros as the count asks for.
        static func zeros(count: Int) -> [Int] { Array(repeating: 0, count: Swift.max(count, 0)) }

        /// Returns the sum of the elements plus the bonus.
        func total(plus bonus: Int) -> Int { reduce(bonus, +) }
    }

    protocol Shape {}

    struct Square: Shape {
        let side: Int
    }

    enum Shapes {
        /// Returns a square with the side length.
        static func square(side: Int) -> any Shape { Square(side: side) }

        /// Returns the even numbers below the count, in order.
        static func evens(count: Int) -> some Collection { Array(stride(from: 0, to: count, by: 2)) }

        /// Returns a square with the side length, as the protocol.
        static func plain(side: Int) -> Shape { Square(side: side) }

        /// Returns the failure the code stands for.
        static func failure(code: Int) -> Error { CocoaError(.fileNoSuchFile) }
    }

    extension Shape {
        /// Returns the factor squared.
        static func squared(_ factor: Int) -> Int { factor * factor }
    }

    enum Spans {
        /// Returns the number of positions in the range.
        static func width(of range: Range<Int>) -> Int { range.count }
    }
    """

    static let symbols = [
        "thickened", "isOwned", "totalWeight", "zeros", "total", "square", "evens", "plain", "failure", "squared",
        "width"
    ]

    /// One function's entry in the advisory block, every fixture function seeded.
    static func entry(_ displayName: String) throws -> String {
        let directory = try writeDPFixture(name: "DocAdviceReferenceOracleSpelling", contents: source)
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
        let block = DiscoverDocstringAdviceSeedFocusTests.mainBlock(of: recording.text)
        return DiscoverReferenceOracleTests.entry(displayName, in: block)
    }

    /// The decline line in an entry, without its marker, or `nil` when the entry has none.
    static func decline(_ displayName: String) throws -> String? {
        let entry = try entry(displayName)
        #expect(
            entry.contains("runnable reference oracle (fill the stub") == false, "\(displayName) printed a scaffold"
        )
        let marker = DiscoverReferenceOracleTests.declineMarker
        return entry.split(separator: "\n").first { $0.hasPrefix(marker) }.map { String($0.dropFirst(marker.count)) }
    }

    @Test func aTypeNestedBesideTheOwnerIsQualifiedInTheReference() throws {
        let entry = try Self.entry("thickened(_:)")
        #expect(entry.contains(
            "extension Library.Shelf {\n        static func thickened_reference(_ book: Library.Book) -> Library.Book {"
        ))
        #expect(entry.contains(
            "{ value in Library.Shelf.thickened(value) == Library.Shelf.thickened_reference(value) }"
        ))
    }

    @Test func aTypealiasNestedInTheReceiverIsQualifiedInTheBinding() throws {
        let entry = try Self.entry("isOwned(by:)")
        #expect(entry.contains(
            "{ (args: (Account, Account.OwnerID)) in args.0.isOwned(by: args.1) == "
                + "args.0.isOwned_reference(by: args.1) }"
        ))
        #expect(entry.contains("let arg1 = (Gen<Int>.int()).run(using: &rng)"))
    }

    @Test func aSugaredOwnerGivesTheTestAnIdentifierForAName() throws {
        let entry = try Self.entry("totalWeight(plus:)")
        #expect(entry.contains("@Test func Bead_totalWeight_matchesReferenceDefinition() async {"))
        #expect(entry.contains("extension [Bead] {\n        func totalWeight_reference(plus bonus: Int) -> Int {"))
    }

    @Test func aStaticMemberOfAConstrainedStandardLibraryExtensionDeclines() throws {
        let reason = try #require(try Self.decline("zeros(count:)"))
        #expect(reason == "`Array.zeros(count:)` is a static member of an extension of the generic type `Array`, "
            + "and its reference's extension cannot repeat that extension's `where` clause, so a call through "
            + "`Array` cannot infer its type arguments")
    }

    /// An instance member of the same extension is not the static decline's: its receiver, the bare
    /// `Array`, is what no generator draws, and the scan declares no `Array` to give a `gen()`.
    @Test func anInstanceMemberOfAConstrainedStandardLibraryExtensionDeclinesOnItsReceiver() throws {
        let reason = try #require(try Self.decline("total(plus:)"))
        #expect(reason.hasPrefix("no generator derives for `Array` ("))
        #expect(reason.hasSuffix(
            "so the oracle cannot draw its receiver — `Array` is not a concrete type the scanned sources declare, "
                + "so there is no declaration to give a `static func gen()`; write this check by hand"
        ))
    }

    @Test func anExistentialResultDeclines() throws {
        let reason = try #require(try Self.decline("square(side:)"))
        #expect(reason == "square(side:) returns `any Shape`, an existential, and `==` cannot compare two existentials")
    }

    @Test func anOpaqueResultDeclines() throws {
        let reason = try #require(try Self.decline("evens(count:)"))
        #expect(reason == "evens(count:) returns `some Collection`, an opaque result: the reference's would be a "
            + "different type from the subject's, so `==` cannot compare them")
    }

    /// A protocol written bare as a result is an existential too — a scanned one, and the standard
    /// library's `Error`.
    @Test func aProtocolNamedBareAsTheResultDeclines() throws {
        let scanned = try #require(try Self.decline("plain(side:)"))
        #expect(scanned == "plain(side:) returns `Shape`, and `Shape` is a protocol, so the result is an existential "
            + "`==` cannot compare")
        let foreign = try #require(try Self.decline("failure(code:)"))
        #expect(foreign.hasPrefix("failure(code:) returns `Error`, and `Error` is a protocol"))
    }

    @Test func aStaticMemberOfAProtocolExtensionDeclines() throws {
        let reason = try #require(try Self.decline("squared(_:)"))
        #expect(reason == "`Shape.squared(_:)` is a static member of the protocol `Shape`, and a static member "
            + "cannot be called on a protocol, only on a type conforming to it")
    }

    /// `static func gen()` is offered only where there is a declaration to put it on.
    @Test func aForeignArgumentTypeIsNotOfferedAGenRemedy() throws {
        let reason = try #require(try Self.decline("width(of:)"))
        #expect(reason.hasPrefix("no generator derives for `Range<Int>` ("))
        #expect(reason.hasSuffix(
            "so the oracle cannot draw its `of:` argument — `Range<Int>` is not a concrete type the scanned sources "
                + "declare, so there is no declaration to give a `static func gen()`; write this check by hand"
        ))
    }
}
