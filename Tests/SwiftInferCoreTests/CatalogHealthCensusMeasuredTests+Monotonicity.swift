import Foundation
import SwiftInferTemplates
import Testing

@testable import SwiftInferCore

/// **What are `monotonicity`'s 339 subjects, across every corpus rather than a third of
/// them?**
///
/// `open-threads.md` row **69** ends with *the next step is the full census, not a
/// filter*, and this is that step. Two questions, and they are not the same question:
///
/// 1. **Does the DECLINED gate's premise hold at full scope?** Row 69 proposed gating the
///    definitionally non-monotonic families — trigonometric functions, and hashes, which
///    cannot preserve order without being broken hashes — and declined it because a
///    sample of **109 of the 339 rows across 10 of the 20 corpora** contained zero of
///    either. **A decline taken on 32% of a population is a decline taken on a sample**,
///    and the missing half included `swiftlang-swift` and `swift-collections`, the two
///    corpora most likely to hold them. This asks it over all 339.
///
/// 2. **What IS in the population?** The sample's answer was that `monotonicity` fires on
///    `Comparable -> Comparable` and almost nothing in that population is about order —
///    `decode(_:)` 18, `fetchCount(_:)` 7, `deleteAll(_:)` 3 against `index(after:)` 9
///    and `index(before:)` 7. That is row 69's own thesis at 339 rows instead of 5, and it
///    is a claim about a distribution, so this reading PRINTS the distribution.
///
/// ## Why this is a reading and not a script
///
/// The 109 was produced by an ad-hoc census script that is not committed, so its
/// classification cannot be reproduced — only its total can, because **339 comes from
/// `CatalogHealthCensusMeasuredTests`' own catalog-health table and was never the sampled
/// figure**. That script also indexed each manifest corpus and then ran `rm -rf
/// .swiftinfer` to leave the subject clean, which **deleted two tracked fixture files**,
/// because four of the twenty corpora are this repository (`open-threads.md`, *Four of the
/// twenty corpora are THIS REPO*).
///
/// This reading scans in process through `FunctionScanner` and `TemplateRegistry`, writes
/// nothing, and has no teardown to get wrong. It is a second reading of the scan
/// `CatalogHealthCensusMeasuredTests` already performs, for the reason that file states:
/// a separate census would re-derive identical rows and double a nine-minute cost.
///
/// ## Three counts for every probe, because the first two were both wrong
///
/// A name probe can fail in two directions and the first run of this census hit both in
/// one pass, which is why all three readings are printed rather than one being chosen:
///
/// - **exact** whole-name match reads **0 trigonometric and 4 hash** — and misses
///   `_cos(_:)`, `_rawHashValue(seed:)` and `_hashValue(for:)`, because the stdlib spells
///   its internals with a leading underscore and a prefix.
/// - **substring** match reads **17 trigonometric** and every one is FALSE:
///   `dis`**`tan`**`ce(to:)`, `edit`**`Tan`**… no — `editDistance`, `second`**`sIn`**`Day`,
///   `numWeek`**`sIn`**`Year`. *`distance` contains `tan` and `secondsInDay` contains
///   `sin`.*
/// - **token** match splits the bare name on `_` and camelCase boundaries and tests
///   membership. `_rawHashValue` → `raw` · `hash` · `value` matches; `distance` →
///   `distance` does not.
///
/// **The token count is the one asserted on.** The other two are printed beside it so the
/// spread is visible: where exact and token disagree the exact probe is too narrow, and
/// where substring and token disagree the substring probe is scoring a coincidence.
extension CatalogHealthCensusMeasuredTests {

    /// Bare names of the trigonometric family. Matched EXACTLY against the name with its
    /// argument labels stripped — `sin`, never `contains("sin")`.
    static let trigNames: Set<String> = [
        "sin", "cos", "tan", "asin", "acos", "atan", "atan2",
        "sinh", "cosh", "tanh", "asinh", "acosh", "atanh"
    ]

    /// Bare names that ARE a hash. `hashValue` and `hash(into:)` are the protocol
    /// requirements; the rest are the conventional spellings.
    static let hashNames: Set<String> = ["hash", "hashValue", "hashed", "hashes"]

    /// The `Collection` index family — the rows the sample identified as **genuinely**
    /// monotonic, and the positive control for this census. If these vanish, the probe is
    /// broken rather than the population being pure.
    static let indexFamilyNames: Set<String> = [
        "index", "formIndex", "distance", "advanced", "successor", "predecessor"
    ]

    static var monotonicityRows: [Row] { rows.filter { $0.template == "monotonicity" } }

    /// Lowercased tokens of a bare declaration name, split on `_` and camelCase
    /// boundaries. `_rawHashValue` → `["raw", "hash", "value"]`.
    ///
    /// **This exists because both simpler probes were measurably wrong.** Whole-name
    /// equality misses the stdlib's `_`-prefixed spellings; `contains` scores `distance`
    /// as trigonometric on the `tan` inside it. Tokens are what a reader means by "is this
    /// function a hash".
    static func nameTokens(_ displayName: String) -> Set<String> {
        var tokens: [String] = []
        var current = ""
        for character in Self.baseName(displayName) {
            if character == "_" {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if character.isUppercase {
                if !current.isEmpty { tokens.append(current) }
                current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return Set(tokens.map { $0.lowercased() })
    }

    @Test("census — what monotonicity's subjects ARE, across every manifest corpus")
    func monotonicitySubjectCensus() {
        let subject = Self.monotonicityRows
        var lines: [String] = ["", "MONOTONICITY SUBJECTS — ALL MANIFEST CORPORA", ""]
        lines.append("rows \(subject.count) of \(Self.rows.count) total discovery rows"
            + " · corpora \(CorpusManifest.available.count)")
        lines += Self.corpusBreakdown(subject)
        lines += Self.nameDistribution(subject)
        lines += Self.declinedGatePopulation(subject)
        lines += Self.reachabilityOfReopenedPopulation(subject)

        let indexFamily = subject.filter { Self.indexFamilyNames.contains(Self.baseName($0.subject)) }
        lines.append("")
        lines.append("POSITIVE CONTROL — the Collection index family: \(indexFamily.count) rows")
        let indexByName = Dictionary(grouping: indexFamily) { $0.subject }.mapValues(\.count)
        for (name, count) in indexByName.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }) {
            lines.append("  \(count)  \(name)")
        }
        print(lines.joined(separator: "\n"))

        // **The load-bearing assertions.** Everything above is a distribution and a
        // distribution is read, not asserted. These two are the falsifiable half: row 69
        // declined the trig/hash gate because a 32% sample held none of either, and the
        // population it actually has is what reopened that decline.
        // **These read 26 until the gate shipped, and they read ZERO now — that is the
        // gate's post-condition, not a change in the corpus.** The population measured
        // 2026-08-29 was trigonometric 4 (`_cos(_:)`, `_sin(_:)`, twice each) and hash 22
        // (`_rawHashValue` 14, `_hashValue`/`hashValue` 7, `Hashable_hashValue_indirect` 1),
        // all of it in `swiftlang-swift` and `swift-collections`. It is recorded in
        // `monotonicity-subject-census.md` because a census that can no longer see its own
        // subject cannot report it.
        let stillProposed = subject.filter {
            NonMonotonicSubjects.isDefinitionallyNonMonotonic($0.subject)
        }
        #expect(stillProposed.isEmpty, """
        `applyNonMonotonicSubjectExclusion` let \(stillProposed.count) definitionally-false \
        row(s) through: \(stillProposed.map(\.subject)). A hash that preserves order is a \
        broken hash, so these are laws that cannot hold — the gate regressed, or a spelling \
        the tokenizer does not reach has appeared.
        """)

        // **The census must not go blind on the population just because the gate removes
        // it.** Counting the classifier's hits across EVERY template keeps the subject
        // visible: the declarations are still in the corpora, and a future reader can see
        // that the zero above is a gate rather than an absence.
        let acrossAllTemplates = Self.rows.filter {
            NonMonotonicSubjects.isDefinitionallyNonMonotonic($0.subject)
        }
        print("""

        NON-MONOTONIC SUBJECTS STILL IN THE CORPORA (all templates): \(acrossAllTemplates.count)
          by template: \(Dictionary(grouping: acrossAllTemplates) { $0.template }.mapValues(\.count))
          monotonicity rows among them: \(stillProposed.count) — gated
        """)

        // The positive control must not be empty, or the probes above are measuring a
        // broken join rather than a pure population — this repo's confident zero.
        #expect(!indexFamily.isEmpty, """
        The Collection index family is empty, which the 109-row sample contradicts \
        (index(after:) 9, index(before:) 7). The subject join is broken, so the zeros \
        above are the instrument and not the population.
        """)
    }

    /// Per-corpus denominators. Row 69's warning was that the sample missed
    /// `swiftlang-swift` and `swift-collections`; pooling would hide exactly that, which is
    /// the failure `refutation-hand-check.md` names when two subjects disagree.
    static func corpusBreakdown(_ subject: [Row]) -> [String] {
        var lines = ["", "by corpus (monotonicity rows / that corpus's total rows):"]
        let byCorpus = Dictionary(grouping: subject) { $0.corpus }.mapValues(\.count)
        let totalsByCorpus = Dictionary(grouping: rows) { $0.corpus }.mapValues(\.count)
        for (corpus, count) in byCorpus.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }) {
            let label = corpus.padding(toLength: 26, withPad: " ", startingAt: 0)
            lines.append("  \(label)\(count) / \(totalsByCorpus[corpus] ?? 0)")
        }
        let silent = CorpusManifest.available.map(\.id).filter { byCorpus[$0] == nil }.sorted()
        lines.append("  corpora with ZERO monotonicity rows: \(silent.count) — "
            + silent.joined(separator: ", "))
        return lines
    }

    /// The whole distribution, ranked. Truncated for printing and **never** for counting —
    /// pinning a total read off a truncated listing is how the trigonometric figure was
    /// first recorded as 2 when it is 4.
    static func nameDistribution(_ subject: [Row]) -> [String] {
        var lines = ["", "subjects by name (all \(subject.count) rows):"]
        let byName = Dictionary(grouping: subject) { $0.subject }.mapValues(\.count)
        let ranked = byName.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        for (name, count) in ranked.prefix(30) {
            lines.append("  \(String(count).padding(toLength: 5, withPad: " ", startingAt: 0))\(name)")
        }
        let tail = ranked.dropFirst(30)
        lines.append("  … \(tail.count) further distinct names, \(tail.map(\.value).reduce(0, +)) rows")
        lines.append("  distinct names: \(byName.count)")
        return lines
    }

    /// The declined gate's premise, re-asked at 20 corpora — with all three probes printed.
    static func declinedGatePopulation(_ subject: [Row]) -> [String] {
        var lines = ["", "THE DECLINED GATE'S POPULATION, at 20 corpora rather than 10:"]
        for (label, names) in [("trigonometric", trigNames), ("hash", hashNames)] {
            let exact = subject.filter { names.contains(baseName($0.subject)) }
            let token = subject.filter { !nameTokens($0.subject).isDisjoint(with: names) }
            let substring = subject.filter { row in
                let bare = baseName(row.subject).lowercased()
                return names.contains { bare.contains($0.lowercased()) }
            }
            lines.append("  \(label): exact \(exact.count) · TOKEN \(token.count)"
                + " · substring \(substring.count)")
            let tokenNames = Dictionary(grouping: token) { $0.subject }.mapValues(\.count)
            for (name, count) in tokenNames.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }) {
                lines.append("      \(count)  \(name)")
            }
            let coincidence = Set(substring.map(\.subject)).subtracting(token.map(\.subject))
            if !coincidence.isEmpty {
                lines.append("      substring-only (COINCIDENCES, not members):"
                    + " \(coincidence.sorted().prefix(6).joined(separator: ", "))")
            }
        }
        return lines
    }

    /// **Is the reopened population REACHABLE?** A row behind a visibility wall costs
    /// nothing to leave alone, and `visibility-widenability.md` measured that
    /// `internalOrSPI` inflates a lever 2.7x because `@testable import` reaches it. Every
    /// name in both probes is `_`-prefixed stdlib internals, so this is the reading that
    /// decides whether the reopening is worth acting on.
    static func reachabilityOfReopenedPopulation(_ subject: [Row]) -> [String] {
        var lines = ["", "REACHABILITY of the reopened population:"]
        let reopened = subject.filter { row in
            let tokens = nameTokens(row.subject)
            return !tokens.isDisjoint(with: trigNames) || !tokens.isDisjoint(with: hashNames)
        }
        var byRestriction: [String: Int] = [:]
        for row in reopened {
            byRestriction[row.restriction.map { "\($0)" } ?? "none (reachable)", default: 0] += 1
        }
        for (label, count) in byRestriction.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }) {
            lines.append("  \(count)  \(label)")
        }
        lines.append("  corpora: \(Set(reopened.map(\.corpus)).sorted().joined(separator: ", "))")
        lines.append("  underscored names: "
            + "\(reopened.filter { baseName($0.subject).hasPrefix("_") }.count) of \(reopened.count)")
        return lines
    }
}
