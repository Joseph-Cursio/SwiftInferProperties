@testable import SwiftInferCore
import SwiftParser
import SwiftSyntax
import Testing

/// Reading the order a function's result is sorted in, from the comparator it sorts with
/// (SwiftInferProperties#647).
@Suite("SortedOutputReader")
struct SortedOutputReaderTests {

    private func read(_ source: String) -> SortedOutput? {
        let finder = Finder(viewMode: .sourceAccurate)
        finder.walk(Parser.parse(source: source))
        return finder.found.flatMap(SortedOutputReader.read)
    }

    final class Finder: SyntaxVisitor {
        var found: FunctionDeclSyntax?

        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            if found == nil { found = node }
            return .visitChildren
        }
    }

    /// The motivating case, from `SwiftFormatRuleStudio`'s `ImpactReport.from(findings:)`: the
    /// sorted array is bound to a local and returned as a member of the constructed value.
    @Test func aSortedLocalReturnedAsAMember() throws {
        let ordering = try #require(read("""
        static func from(findings: [LintFinding]) -> Self {
            let impacts = Dictionary(grouping: findings, by: \\.ruleID).map { RuleImpact($0) }
                .sorted { lhs, rhs in
                    if lhs.fileCount != rhs.fileCount { return lhs.fileCount > rhs.fileCount }
                    if lhs.findingCount != rhs.findingCount { return lhs.findingCount > rhs.findingCount }
                    return lhs.ruleID < rhs.ruleID
                }
            return Self(totalFindings: findings.count, ruleImpacts: impacts)
        }
        """))
        #expect(ordering.member == "ruleImpacts")
        #expect(ordering.keys == [
            SortKey(path: "fileCount", ascending: false),
            SortKey(path: "findingCount", ascending: false),
            SortKey(path: "ruleID", ascending: true)
        ])
    }

    @Test func aSortedArrayReturnedDirectly() throws {
        let ordering = try #require(read("""
        func churn() -> [RuleImpact] {
            return results.filter { $0.findingCount > 0 }.sorted { lhs, rhs in
                if lhs.fileCount != rhs.fileCount { return lhs.fileCount > rhs.fileCount }
                return lhs.ruleID < rhs.ruleID
            }
        }
        """))
        #expect(ordering.member == nil)
        #expect(ordering.keys.map(\.path) == ["fileCount", "ruleID"])
    }

    /// A single-expression body returns implicitly, and an unnamed closure compares `$0` and `$1`.
    @Test func anImplicitReturnWithAnonymousOperands() throws {
        let ordering = try #require(read("""
        func byName(_ rules: [Rule]) -> [Rule] {
            rules.sorted { $0.name < $1.name }
        }
        """))
        #expect(ordering.keys == [SortKey(path: "name", ascending: true)])
    }

    /// **Swapped operands invert the direction.** `$1.count < $0.count` puts the larger first, and
    /// reading it as ascending would state the reverse of the order the code produces.
    @Test func swappedOperandsSortDescending() throws {
        let ordering = try #require(read("""
        func biggestFirst(_ groups: [Group]) -> [Group] {
            groups.sorted { $1.count < $0.count }
        }
        """))
        #expect(ordering.keys == [SortKey(path: "count", ascending: false)])
    }

    @Test func theByLabelledClosureAndADottedKey() throws {
        let ordering = try #require(read("""
        func ordered(_ items: [Item]) -> [Item] {
            items.sorted(by: { a, b in a.location.line > b.location.line })
        }
        """))
        #expect(ordering.keys == [SortKey(path: "location.line", ascending: false)])
    }

    // MARK: - Declined: anything the reader could not restate exactly

    @Test("a comparator the reader cannot restate is declined", arguments: [
        // A call in the comparison: the key is computed, not a member.
        "func f(_ xs: [R]) -> [R] { xs.sorted { $0.name.lowercased() < $1.name.lowercased() } }",
        // The tie-break tests one key and returns another.
        """
        func f(_ xs: [R]) -> [R] {
            xs.sorted { a, b in
                if a.size != b.size { return a.name < b.name }
                return a.name < b.name
            }
        }
        """,
        // `sorted()` and `sorted(by: <)` carry no key to read.
        "func f(_ xs: [Int]) -> [Int] { xs.sorted() }",
        "func f(_ xs: [Int]) -> [Int] { xs.sorted(by: <) }",
        // An equality is not an order.
        "func f(_ xs: [R]) -> [R] { xs.sorted { $0.size == $1.size } }",
        // The sorted array is not what the function returns.
        """
        func f(_ xs: [R]) -> Int {
            let ordered = xs.sorted { $0.size < $1.size }
            return ordered.count
        }
        """
    ])
    func declinesWhatItCannotRestate(source: String) {
        #expect(read(source) == nil)
    }

    /// Two sorted members would be two laws, and a suggestion carries one.
    @Test func twoSortedMembersAreDeclined() {
        #expect(read("""
        func f(_ xs: [R]) -> Pair {
            let bySize = xs.sorted { $0.size < $1.size }
            let byName = xs.sorted { $0.name < $1.name }
            return Pair(bySize: bySize, byName: byName)
        }
        """) == nil)
    }
}
