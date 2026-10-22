@testable import SwiftInferCore
import SwiftParser
import SwiftSyntax
import Testing

/// Reading which member of a sorted result holds the key of the dictionary it was mapped from
/// (SwiftInferProperties#647, law 2) — `SortedOutput.dictionaryKeyMember`.
@Suite("DictionaryKeyReader")
struct DictionaryKeyReaderTests {

    private func read(_ source: String) -> SortedOutput? {
        let finder = SortedOutputReaderTests.Finder(viewMode: .sourceAccurate)
        finder.walk(Parser.parse(source: source))
        return finder.found.flatMap(SortedOutputReader.read)
    }

    /// The motivating case, `ImpactReport.from`: a multi-statement `map` closure over an inline
    /// `Dictionary(grouping:)` local, its key bound by name, returned as a member.
    @Test func aGroupedDictionaryMappedByNameAndReturnedAsAMember() throws {
        let ordering = try #require(read("""
        static func from(findings: [LintFinding]) -> Self {
            let byRule = Dictionary(grouping: findings, by: \\.ruleID)
            let impacts = byRule.map { ruleID, group in
                let byFile = Dictionary(grouping: group, by: \\.filePath)
                return RuleImpact(ruleID: ruleID, fileCount: byFile.count, findingCount: group.count)
            }
            .sorted { lhs, rhs in
                if lhs.fileCount != rhs.fileCount { return lhs.fileCount > rhs.fileCount }
                return lhs.ruleID < rhs.ruleID
            }
            return Self(totalFindings: findings.count, ruleImpacts: impacts)
        }
        """))
        #expect(ordering.member == "ruleImpacts")
        #expect(ordering.dictionaryKeyMember == "ruleID")
        #expect(ordering.comparatorReachesDictionaryKey)
    }

    /// The defect the law exists for, `SwiftLintRuleStudioTeam`'s `ruleHotspots`: a `[K: V]` local
    /// filled in a loop, mapped through `$0.key`, sorted on a count that ties.
    @Test func aTypedLocalMappedThroughDollarZeroKey() throws {
        let ordering = try #require(read("""
        func ruleHotspots(_ repos: [FleetRepo]) -> [RuleHotspot] {
            var totals: [String: (violations: Int, repos: Int)] = [:]
            for repo in repos { totals[repo.rule, default: (0, 0)].violations += repo.count }
            return totals
                .map { RuleHotspot(rule: $0.key, violations: $0.value.violations, repoCount: $0.value.repos) }
                .sorted { $0.violations > $1.violations }
        }
        """))
        #expect(ordering.dictionaryKeyMember == "rule")
        #expect(ordering.comparatorReachesDictionaryKey == false)
    }

    /// `fleetBurndown`: the comparator sorts on the key itself.
    @Test func aComparatorOnTheKeyItself() throws {
        let ordering = try #require(read("""
        func fleetBurndown(_ baselines: [RuleBaseline]) -> [BaselineMeasurement] {
            var byDate: [Date: Int] = [:]
            for baseline in baselines {
                for measurement in baseline.measurements {
                    byDate[measurement.date, default: 0] += measurement.remaining
                }
            }
            return byDate
                .map { BaselineMeasurement(date: $0.key, remaining: $0.value) }
                .sorted { $0.date < $1.date }
        }
        """))
        #expect(ordering.dictionaryKeyMember == "date")
        #expect(ordering.comparatorReachesDictionaryKey)
    }

    /// Each case is `func f(_ xs: [R]) -> [S] { <body> }`, its body sorted by `{ $0.n < $1.n }`.
    @Test("every spelling of a dictionary and of its key is read", arguments: [
        "return Dictionary(grouping: xs, by: \\.k).map { S(k: $0.key, n: $0.value.count) }",
        "let d = [String: Int](); return d.map { (key, value) in S(k: key, n: value) }",
        "var d = Dictionary<String, Int>(); return d.map { entry in S(k: entry.key, n: entry.value) }",
        "var d: Dictionary<String, Int> = .init(); return d.compactMap { S(k: $0.key, n: $0.value) }",
        "let d: [String: Int] = [:]; return d.map { (k: $0.key, n: $0.value) }"
    ])
    func everySpelling(body: String) throws {
        let ordering = try #require(read("func f(_ xs: [R]) -> [S] { \(body).sorted { $0.n < $1.n } }"))
        #expect(ordering.dictionaryKeyMember == "k")
    }

    /// Same frame: `func f(_ xs: [R]) -> [S] { <body>.sorted { $0.n < $1.n } }`.
    @Test("a shape that does not say which member holds the key is not read", arguments: [
        // `.values` carries no key at all.
        "let d: [String: S] = [:]; return d.values",
        // Not a dictionary: an array local mapped the same way.
        "let d = xs; return d.map { S(k: $0.key, n: 1) }",
        // The key reaches two arguments, so which one is its member is a guess.
        "let d: [String: Int] = [:]; return d.map { S(k: $0.key, j: $0.key, n: $0.value) }",
        // The key reaches an unlabelled argument.
        "let d: [String: Int] = [:]; return d.map { S($0.key, n: $0.value) }",
        // A computed key, not the key.
        "let d: [String: Int] = [:]; return d.map { S(k: $0.key.lowercased(), n: $0.value) }"
    ])
    func declined(body: String) throws {
        let ordering = try #require(read("func f(_ xs: [R]) -> [S] { \(body).sorted { $0.n < $1.n } }"))
        #expect(ordering.dictionaryKeyMember == nil)
    }
}
