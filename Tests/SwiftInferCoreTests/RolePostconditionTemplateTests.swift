import Foundation
import SwiftInferTemplates
import Testing

@testable import SwiftInferCore

/// **The role-postcondition template, and the two false positives that shaped it.**
///
/// Every gate here was measured on real corpora rather than argued
/// (`docs/measurements/postcondition-law-declined.md` §4, and a hand-check of all 38
/// exact-name declarations across the 17 corpora).
@Suite("Role postcondition — the catalogue supplies the predicate")
struct RolePostconditionTemplateTests {

    static func rows(in source: String) throws -> [Suggestion] {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("role-postcondition-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try source.write(
            to: directory.appendingPathComponent("S.swift"), atomically: true, encoding: .utf8
        )
        let scanned = try FunctionScanner.scanCorpus(directory: directory)
        let all = TemplateRegistry.discover(
            in: scanned.summaries, identities: scanned.identities, typeDecls: scanned.typeDecls
        )
        return all.filter { $0.templateName == "role-postcondition" }
    }

    /// The canonical case: `Sequence.sorted()`, the most common site in the population.
    @Test("a nullary sorted() carries the role")
    func sortedFires() throws {
        let rows = try Self.rows(in: """
        public struct Deck {
            public func sorted() -> [Int] { [] }
        }
        """)
        #expect(rows.count == 1, "got \(rows.count)")
    }

    /// **The one false positive found in a hand-check of all 38 declarations.**
    ///
    /// `SyntaxProtocol.trimmed(matching filter:)` is an exact name match that trims
    /// *trivia a caller selects*, not whitespace. Supplying "no leading or trailing
    /// whitespace" there is a **false law refuting correct code**, which is the worst
    /// failure this tool has.
    @Test("a parameterised exact match is NOT the role")
    func parameterisedMatchIsRejected() throws {
        let rows = try Self.rows(in: """
        public struct Node {
            public func trimmed(matching filter: (Int) -> Bool) -> Node { self }
        }
        """)
        #expect(rows.isEmpty, "trimmed(matching:) was admitted — that law is false of it")
    }

    /// **`normalized` supplies no checkable predicate**, so it is absent from the role
    /// table. Both corpus sites confirm it: one establishes a fingerprint convention,
    /// the other returns a tuple. A role that reads like a law and supplies none is worse
    /// than an absent role, because it looks like coverage.
    @Test("normalized is not a role, because normal form is not checkable")
    func normalizedIsNotARole() throws {
        let rows = try Self.rows(in: """
        public struct Fingerprint {
            public static func normalized(_ text: String) -> String { text }
        }
        """)
        #expect(rows.isEmpty, "`normalized` was admitted — what predicate would be asserted?")
    }

    /// A prefix match is a different operation whose suffix narrows the law. Measured:
    /// 14 of the 16 trim-family sites across the corpora were prefix matches.
    @Test("a prefix match is not the role")
    func prefixMatchIsRejected() throws {
        let rows = try Self.rows(in: """
        public struct Text {
            public func trimmingLeadingWhitespace() -> Text { self }
        }
        """)
        #expect(rows.isEmpty, "a leading-only trim does not owe the trailing half")
    }

    /// A label that leaves the role intact IS admitted — `sorted(by:)` is still sorting,
    /// and rejecting it would trade the false-positive gate for a false-negative one.
    @Test("a role-preserving label is still the role")
    func rolePreservingLabelIsAdmitted() throws {
        let rows = try Self.rows(in: """
        public struct Deck {
            public func sorted(by areInIncreasingOrder: (Int, Int) -> Bool) -> [Int] { [] }
        }
        """)
        #expect(rows.count == 1, "sorted(by:) is still sorting; got \(rows.count)")
    }

    /// No output, no postcondition.
    @Test("a Void-returning mutation carries no postcondition")
    func voidReturnIsRejected() throws {
        let rows = try Self.rows(in: """
        public struct Deck {
            public mutating func sorted() {}
        }
        """)
        #expect(rows.isEmpty)
    }

    /// **The weak roles are surfaced and marked, not dropped.** `reversed` pins count and
    /// not content, so a wrong-but-same-size result satisfies it — the reader is told.
    @Test("a weak role fires but discloses that its law is weak")
    func weakRoleDisclosesItself() throws {
        let rows = try Self.rows(in: """
        public struct Tape {
            public func reversed() -> [Int] { [] }
        }
        """)
        let row = try #require(rows.first)
        let disclosed = row.explainability.whyMightBeWrong.contains { $0.contains("LAW IS WEAK") }
        #expect(disclosed, "the weak-law caveat is missing: \(row.explainability.whyMightBeWrong)")
    }

    /// The law reaches the reader. A postcondition nobody can read is a suggestion with
    /// no content — the failure `predicate`'s own template doc warns about.
    @Test("the supplied law is stated in the suggestion")
    func lawIsStated() throws {
        let rows = try Self.rows(in: """
        public struct Box {
            public func clamped(to limits: Range<Int>) -> Box { self }
        }
        """)
        let row = try #require(rows.first)
        let stated = row.explainability.whyMightBeWrong.contains { $0.contains("within the given bounds") }
        #expect(stated, "the law is not stated: \(row.explainability.whyMightBeWrong)")
    }
}
