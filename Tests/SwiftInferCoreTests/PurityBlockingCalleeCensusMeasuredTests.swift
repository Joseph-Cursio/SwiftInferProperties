import Foundation
import SwiftEffectInference
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **Census with a standing verdict — read this header before building the
/// blocking-callee index, the leverage ranking, or the channel that would carry
/// either.** Open item 31, measured the way items 29 and 30 were: the artifact
/// is prototyped here first so its population and its *output tier* can be sized
/// before anything ships.
///
/// ## The question
///
/// At the point `throwsOnlyItsOwnErrors` gives up, it knows **which** callee it
/// gave up on. `PurityVerdict.refuted` has no room to say so, so the fact never
/// leaves the inferrer — the fourth recorded instance of *the consumer keeps
/// asking the producer, in English*. Item 31 proposes inverting it: key by
/// blocking callee, list the functions whose verdict rests on it.
///
/// Item 29 sized the population at 152 and item 41 shrank it to 135. This census
/// asks the two questions that sizing does not answer:
///
/// 1. **Does the index have leverage?** How many of the 135 would a
///    within-package join actually free — at one hop, and at fixpoint?
/// 2. **Does the leverage have a reader?** What verdict do the freed rows land
///    on, and does anything consume it?
///
/// The second question is the one `docs/design-internal/open-threads.md` →
/// *The bucket is a channel, not a report* insists on: *"If the ranking has no
/// consumer, it is a third instance rather than a fix."* That trap was expected to arrive through item 35 — the `pure`
/// advisory is outbound-only, so nobody reads a recommended annotation back. It
/// arrives here from a different direction entirely, and much earlier.
///
/// ## The finding, stated up front because it re-orders the work
///
/// **Every row in this population `throws`** — `propagatedTry` is defined as
/// `throwsClause != nil` *and* a `try` in the body, so it cannot be otherwise.
/// A function that throws can never reach `.pure`; the best a resolved callee
/// can do for it is `.pureButPartial`.
///
/// **Nothing consumes `.pureButPartial`.** It appears in `Sources/` only inside
/// doc comments; no code branches on it, and `isInferredPure` — the field the
/// one live consumer reads — is `purityVerdict == .pure` by definition.
///
/// So resolving **every** blocking callee in the package moves **zero** advisory
/// rows. Item 31 is buildable and correctly sized, and its entire output lands
/// in a tier item 34 records as unconsumed. **Item 34 is the precondition, not
/// item 29** — and that dependency is not written down anywhere the sequencing
/// would have caught it.
@Suite("Census — what blocks a verdict, and who would read the answer?")
struct PurityBlockingCalleeCensusMeasuredTests {

    // Extraction and the join simulation are in
    // `PurityBlockingCalleeCensusMeasuredTests+Support.swift`.

    // MARK: - The population

    static var corpus: [Subject] { PurityRefutationCensusMeasuredTests.corpus }
    static var verdicts: [PurityVerdict] { PurityRefutationCensusMeasuredTests.verdicts }

    /// The ignorance-only half of the item 29 bucket, each row carrying the
    /// callees its verdict rests on. Derived from that census's own `refuted`
    /// static so the two populations cannot drift apart.
    static let blocked: [BlockedRow] = PurityRefutationCensusMeasuredTests.refuted
        .filter { !$0.causes.contains(where: \.isWitness) }
        .compactMap { entry in
            guard let body = entry.subject.function.body else { return nil }
            let collector = CensusBlockingCalleeCollector(viewMode: .sourceAccurate)
            collector.walk(body)
            return BlockedRow(
                subject: entry.subject,
                allUnderTry: collector.all,
                outermostUnderTry: collector.outermost
            )
        }

    /// Every function name in the package, with how its declarations stand.
    static let nameStatus: [String: NameStatus] = {
        var byName: [String: [PurityVerdict]] = [:]
        for (subject, verdict) in zip(corpus, verdicts) {
            byName[subject.name, default: []].append(verdict)
        }
        return byName.mapValues { $0.allSatisfy { $0 != .refuted } ? .settled : .blocked }
    }()

    /// **Item 31's artifact.** Blocking callee → the rows whose verdict rests on
    /// it, most-blocking first. This is the inverse index the item asks for; it
    /// exists here so it can be measured before it is shipped.
    static let inverseIndex: [(callee: Callee, rows: [String])] = {
        var index: [Callee: [String]] = [:]
        for row in blocked {
            for callee in row.allUnderTry {
                index[callee, default: []].append("\(row.subject.file):\(row.subject.name)")
            }
        }
        return index
            .map { (callee: $0.key, rows: $0.value.sorted()) }
            .sorted { ($0.rows.count, $1.callee) > ($1.rows.count, $0.callee) }
    }()

    // MARK: - The verdict

    /// **The whole population throws, so its whole leverage lands in
    /// `.pureButPartial`.** Structural, not incidental: `propagatedTry` is
    /// defined as a `throwsClause` plus a `try`, and `verdict(for:)` returns
    /// `.pure` only when there is no `throwsClause`.
    ///
    /// Asserted rather than argued because it is the load-bearing step of the
    /// re-ordering below. If a non-throwing row ever appears here, the taxonomy
    /// has changed underneath this census and the conclusion needs re-taking.
    @Test("every blocked row throws, so none of them can be freed to .pure")
    func theWholePopulationThrows() {
        let nonThrowing = Self.blocked.filter {
            $0.subject.function.signature.effectSpecifiers?.throwsClause == nil
        }
        #expect(
            nonThrowing.isEmpty,
            "\(nonThrowing.count) blocked rows do not throw: \(nonThrowing.prefix(5).map(\.subject.name))"
        )
    }

    /// **And nothing reads that tier.** `.pureButPartial` occurs in `Sources/`
    /// only inside doc comments — no `case`, no `if`, no filter. Measured over
    /// the shipped sources rather than asserted from memory, because the whole
    /// point of the claim is that it can change without anyone noticing.
    ///
    /// The day a consumer appears, this test fails and item 31's verdict should
    /// be re-taken — that is the intended notification, not a maintenance cost.
    @Test("no shipped code branches on .pureButPartial")
    func thePartialTierHasNoConsumer() {
        let sources = SwiftSourceFiles.sorted(in: PurityRefutationCensusMeasuredTests.packageSourcesRoot)
        var branching: [String] = []
        for file in sources {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (offset, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains("pureButPartial") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("///"), !trimmed.hasPrefix("//") else { continue }
                branching.append("\(file.lastPathComponent):\(offset + 1)")
            }
        }
        #expect(
            branching.isEmpty,
            """
            \(branching) branch on .pureButPartial. A consumer has appeared, so item 31's \
            leverage now has a reader — re-take the verdict in \
            docs/measurements/purity-blocking-callee-census.md.
            """
        )
    }

    /// Rows blocked by at least one callee declared **nowhere in this package** —
    /// stdlib, Foundation, a sibling repo. A within-package join can never move
    /// them, whatever it resolves.
    static let blockedByForeign: [BlockedRow] = blocked.filter { row in
        row.allUnderTry.contains { nameStatus[$0.name] == nil }
    }

    /// **The leverage ceiling is not the population, and the gap is 4–10×.**
    /// Measured: 135 rows blocked, and a within-package join at fixpoint frees
    /// **27** reading the blockers conservatively, **31** reading them
    /// optimistically. Item 31's row says *quote the 135*; the 135 is the
    /// population, and the leverage is a fifth of it.
    ///
    /// **Where the other 104 go is the finding.** Only 36 depend on a callee
    /// declared nowhere in this package. The remaining 68 resolve perfectly well
    /// — to package functions that are **themselves correctly refuted**. `write`,
    /// `encode`, `emit`, `discover`, `resolve`: the join runs, names the callee,
    /// and the answer is still `.refuted`. Most of this "ignorance" is accurate.
    ///
    /// **And the head of the index is unreachable in the other way.** The single
    /// most-blocking callee is `String` at 14 rows, and every `try String(…)` in
    /// this corpus is `String(contentsOf:)` — a **file read**. `Data` follows at
    /// 6, likewise `Data(contentsOf:)`. A leverage report built on this index
    /// ranks *"resolve `String`"* first, and nothing can resolve it, because it
    /// is not pure.
    ///
    /// So the ranking's top entries are unmovable and its population is mostly
    /// correctly refuted. That is the decline, and it is a stronger one than the
    /// unconsumed-tier finding above, which would merely have deferred the build.
    @Test("a within-package join frees a small fraction of the blocked population")
    func theLeverageIsAFractionOfThePopulation() {
        let best = Self.simulateJoin(
            rows: Self.blocked,
            blockers: \.outermostUnderTry,
            status: Self.nameStatus,
            maxHops: 20
        )
        #expect(
            best.freed.count * 3 < Self.blocked.count,
            """
            \(best.freed.count) of \(Self.blocked.count) freed at fixpoint under the most \
            generous reading. If a join now reaches a third of the population, item 31's \
            decline is worth re-opening — re-take \
            docs/measurements/purity-blocking-callee-census.md.
            """
        )
        #expect(
            Self.blockedByForeign.count < Self.blocked.count - best.freed.count,
            """
            \(Self.blockedByForeign.count) foreign-blocked of \(Self.blocked.count - best.freed.count) \
            unfreed. The claim that most unfreed rows resolve to a correctly-refuted PACKAGE \
            callee is what makes this ignorance accurate rather than merely unread.
            """
        )
    }

    /// The index is not empty and not a singleton — a ranking over one callee is
    /// not a ranking. Without this, the leverage numbers below could be reporting
    /// on an extraction that silently found nothing.
    @Test("the blocking callee is recoverable for the whole population")
    func everyBlockedRowNamesACallee() {
        #expect(Self.blocked.count > 100, "\(Self.blocked.count) blocked rows")
        let nameless = Self.blocked.filter(\.allUnderTry.isEmpty)
        #expect(
            nameless.isEmpty,
            "\(nameless.count) rows `try` into nothing nameable: \(nameless.prefix(5).map(\.subject.name))"
        )
    }

    // MARK: - The census

    /// Prints the whole census, including item 31's inverse index. The
    /// assertions are above; this is what gets transcribed into the
    /// measurements doc, with the tree SHA.
    @Test("census — the blocking-callee index and what a join would free")
    func census() {
        var lines = ["blocked (ignorance-only) rows: \(Self.blocked.count)"]
        let allThrow = Self.blocked.allSatisfy {
            $0.subject.function.signature.effectSpecifiers?.throwsClause != nil
        }
        lines.append("  all of them throw: \(allThrow)")
        lines.append("  distinct blocking callees (conservative): "
            + "\(Set(Self.blocked.flatMap(\.allUnderTry)).count)")
        lines.append("  rows with a nameable outermost callee: "
            + "\(Self.blocked.filter { !$0.outermostUnderTry.isEmpty }.count)")

        lines.append("blockers per row (conservative):")
        let counts = Dictionary(grouping: Self.blocked) { min($0.allUnderTry.count, 5) }
        for bucket in counts.keys.sorted() {
            lines.append("  \(bucket == 5 ? "5+" : "\(bucket)"): \(counts[bucket]?.count ?? 0)")
        }

        lines.append("what a within-package join would free:")
        for (label, blockers) in [
            ("conservative (every callee under try)", \BlockedRow.allUnderTry),
            ("optimistic (outermost callee only)", \BlockedRow.outermostUnderTry)
        ] {
            for (hopLabel, hops) in [("one hop", 1), ("fixpoint", 20)] {
                let result = Self.simulateJoin(
                    rows: Self.blocked, blockers: blockers, status: Self.nameStatus, maxHops: hops
                )
                lines.append("  \(label), \(hopLabel): \(result.freed.count) of \(Self.blocked.count)"
                    + " (hops used: \(result.hops))")
            }
        }
        lines.append("  ...and every freed row lands on .pureButPartial, which nothing reads.")
        lines.append("  advisory rows moved by freeing ALL of them: 0")

        lines.append("why the rest are unreachable:")
        lines.append("  blocked by >=1 FOREIGN callee (no within-package join can help): "
            + "\(Self.blockedByForeign.count)")
        let foreignOnly = Self.blocked.filter { row in
            !row.allUnderTry.isEmpty && row.allUnderTry.allSatisfy { Self.nameStatus[$0.name] == nil }
        }
        lines.append("  blocked ONLY by foreign callees: \(foreignOnly.count)")
        let foreignBlockers = Set(Self.blocked.flatMap(\.allUnderTry))
            .filter { Self.nameStatus[$0.name] == nil }
        lines.append("  distinct foreign blockers: \(foreignBlockers.count)")

        lines.append("item 31's inverse index — blocking callee -> rows blocked (top 25):")
        for entry in Self.inverseIndex.prefix(25) {
            let status = Self.nameStatus[entry.callee.name] ?? .foreign
            lines.append("  \(entry.callee.name) [\(entry.callee.shape.rawValue)/\(status)]: \(entry.rows.count)")
        }
        print(lines.joined(separator: "\n"))
    }
}
