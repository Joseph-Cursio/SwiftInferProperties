import Foundation
import SwiftEffectInference
import SwiftSyntax
import Testing

@testable import SwiftInferCore
@testable import SwiftInferTemplates

/// **What the construction table moves across the manifest corpora — rows moved, join applied.**
///
/// Per scan root: the summaries `FunctionScanner.scanCorpus(directory:)` emits under the root's
/// project purity, against the same scan under `withoutConstructionFacts` — one parse, one
/// universe, the same tree nodes, so the difference is the table and nothing else. A row MOVES
/// when the unconfigured arm advises it pure and the configured arm does not. Each moved row is
/// split into **direct** (its own per-file verdict moved — its body or a default constructs a
/// refuted type) and **via the join** (only the one-hop `PackagePurityJoin` moved it, because a
/// callee it names is now settled impure). The join AMPLIFIES: one refuted helper retracts every
/// pure caller, so the second column can dwarf the first, and it is reported apart for that reason.
///
/// "Rows moved", never "laws gained" (CLAUDE.md). What a moved row costs downstream is the
/// `/// @lint.effect pure` advice it no longer gets, printed beside it.
extension PackagePurityJoinMeasuredTests {

    struct ConstructionArm {
        let corpus: String
        let scanPath: String
        let universeFiles: Int
        let refutedTypes: Int
        let summaries: Int
        let movedDirect: [String]
        let movedViaJoin: [String]
        let promoted: [String]
        let adviceBefore: Int
        let adviceAfter: Int
        var moved: Int { movedDirect.count + movedViaJoin.count }
    }

    /// Every available root's arm, or why it has none. Kept as a `Result`, never `try?`-dropped:
    /// `MisalignedArms` is the guard that makes the row-by-row comparison sound, and a root it
    /// rejected — or whose scan threw — used to vanish from the census and from
    /// `constructionFactsNeverPromote` alike, shrinking the population with no signal.
    static let constructionResults: [(label: String, result: Result<ConstructionArm, any Error>)] =
        CorpusManifest.available.flatMap { corpus in
            corpus.roots.map { root in
                let label = "\(corpus.id)/\(root.lastPathComponent)"
                return (label, Result { try constructionArm(corpus: corpus.id, root: root) })
            }
        }

    static var constructionArms: [ConstructionArm] {
        constructionResults.compactMap { try? $0.result.get() }
    }

    /// The roots the A/B could not compare, with the reason — `failed.isEmpty` is asserted.
    static var constructionFailures: [String] {
        constructionResults.compactMap { entry in
            guard case let .failure(error) = entry.result else { return nil }
            return "\(entry.label): \(error)"
        }
    }

    static func constructionArm(corpus: String, root: URL) throws -> ConstructionArm {
        let purity = CensusPurity.purity(forScanOf: root)
        let without = purity.withoutConstructionFacts
        let after = try FunctionScanner.scanCorpus(directory: root, purity: purity).summaries
        let before = try FunctionScanner.scanCorpus(directory: root, purity: without).summaries
        let unjoinedAfter = try unjoined(root, purity: purity)
        let unjoinedBefore = try unjoined(root, purity: without)
        // The arms are compared row by row, which is sound only because the table changes
        // verdicts and never which declarations are summarised.
        guard Set([after.count, before.count, unjoinedAfter.count, unjoinedBefore.count]).count == 1 else {
            throw MisalignedArms(corpus: corpus, root: root.path)
        }
        var direct: [String] = []
        var viaJoin: [String] = []
        var promoted: [String] = []
        for index in after.indices {
            let label = "\(after[index].name) @ \(URL(fileURLWithPath: after[index].location.file).lastPathComponent)"
                + (after[index].isComputedProperty ? " (getter)" : "")
            if before[index].isInferredPure, !after[index].isInferredPure {
                let ownMoved = unjoinedBefore[index].isInferredPure && !unjoinedAfter[index].isInferredPure
                if ownMoved {
                    direct.append("\(label) — \(witness(of: after[index], in: purity))")
                } else {
                    viaJoin.append(label)
                }
            } else if !before[index].isInferredPure, after[index].isInferredPure {
                promoted.append(label)
            }
        }
        return ConstructionArm(
            corpus: corpus,
            scanPath: root.lastPathComponent,
            universeFiles: purity.universe.count,
            refutedTypes: purity.refutedTypes.count,
            summaries: after.count,
            movedDirect: direct,
            movedViaJoin: viaJoin,
            promoted: promoted,
            adviceBefore: EffectAnnotationAdvice.adviceList(from: before).count,
            adviceAfter: EffectAnnotationAdvice.adviceList(from: after).count
        )
    }

    struct MisalignedArms: Error {
        let corpus: String
        let root: String
    }

    /// SEI's first witness for a directly moved function, read on the scan's own tree.
    static func witness(of summary: FunctionSummary, in purity: PackagePurity) -> String {
        guard !summary.isComputedProperty,
              let tree = CensusPurity.tree(for: URL(fileURLWithPath: summary.location.file), in: purity)
        else { return "getter" }
        let converter = SourceLocationConverter(fileName: summary.location.file, tree: tree)
        let decl = CensusFunctionCollector.functions(in: tree).first {
            $0.name.text == summary.name
                && converter.location(for: $0.funcKeyword.positionAfterSkippingLeadingTrivia).line
                    == summary.location.line
        }
        return decl.flatMap { purity.oracle.inferrerRefutation(for: $0)?.description } ?? "?"
    }

    /// **The table only refutes**, on every corpus and through the join.
    @Test("construction facts never promote a row on any manifest corpus")
    func constructionFactsNeverPromote() {
        #expect(!Self.constructionArms.isEmpty, "no manifest corpus scanned — every figure here is vacuous")
        let failed = Self.constructionFailures
        #expect(failed.isEmpty, "roots dropped from the A/B; every figure is over a smaller population: \(failed)")
        for arm in Self.constructionArms {
            #expect(arm.promoted.isEmpty, "\(arm.corpus)/\(arm.scanPath): promoted \(arm.promoted)")
        }
    }

    /// **The motivating case.** SwiftLintRuleStudio's `analyze` constructs a `ConfigHealthReport`
    /// whose `id` mints a `UUID` — direct; `generateRecommendations` constructs nothing and is
    /// moved by the join, through four `inout` helpers that each construct a
    /// `HealthRecommendation`. Before the wiring, `discover --effect-annotations` advised both
    /// pure. Skipped when the checkout is absent; a moved checkout that no longer has either
    /// function fails here loudly rather than passing on nothing.
    @Test(
        "SwiftLintRuleStudio's generateRecommendations and analyze are no longer advised pure",
        .enabled(if: CorpusManifest.available.contains { $0.id == "swiftlint-rule-studio" })
    )
    func motivatingRowsMove() {
        let core = Self.constructionArms.filter {
            $0.corpus == "swiftlint-rule-studio" && $0.scanPath == "SwiftLintRuleStudioCore"
        }
        let direct = core.flatMap(\.movedDirect)
        let joined = core.flatMap(\.movedViaJoin)
        #expect(direct.contains { $0.hasPrefix("analyze @") }, "direct: \(direct)")
        #expect(joined.contains { $0.hasPrefix("generateRecommendations @") }, "via the join: \(joined)")
    }

    @Test("census — rows the construction table moves, per manifest corpus")
    func constructionCensus() {
        var lines: [String] = []
        for arm in Self.constructionArms {
            lines.append("""
            \(arm.corpus)/\(arm.scanPath): universe \(arm.universeFiles) files · refuted types \(arm.refutedTypes) · \
            \(arm.summaries) summaries · moved \(arm.moved) (direct \(arm.movedDirect.count), via join \
            \(arm.movedViaJoin.count)) · advice \(arm.adviceBefore) → \(arm.adviceAfter)
            """)
            lines += arm.movedDirect.map { "    direct: \($0)" }
            lines += arm.movedViaJoin.prefix(12).map { "    join:   \($0)" }
            if arm.movedViaJoin.count > 12 { lines.append("    join:   … and \(arm.movedViaJoin.count - 12) more") }
        }
        lines += Self.constructionFailures.map { "NOT COMPARED: \($0)" }
        let total = Self.constructionArms.reduce(0) { $0 + $1.moved }
        lines.append("total moved: \(total) over \(Self.constructionArms.count) scan roots")
        print(lines.joined(separator: "\n"))
    }
}
