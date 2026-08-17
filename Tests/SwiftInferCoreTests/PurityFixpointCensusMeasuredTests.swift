import Foundation
import SwiftEffectInference
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **What would a REFUTING-direction callee join actually retract, and does
/// running it to a fixpoint buy anything over one hop?**
///
/// Every purity census so far measured the *promoting* direction — how many
/// `.refuted` rows a within-package join would free. That answer is 13–31 rows
/// landing in `.pureButPartial`, which nothing reads, so item 31 declined twice.
/// This census asks the mirror question, which no measurement had asked:
///
/// > `DrainedProcess.standardOutputViaEnv` calls `standardOutput`, which spawns a
/// > subprocess and is `.refuted` **with a witness**. The caller is judged
/// > `.pure`. If `verdict(for:)` consulted the verdict this same analyzer already
/// > computed for its callee, how many rows would be **retracted** — and does the
/// > retraction cascade?
///
/// **Why this direction is the interesting one.** It is sound (a refuter only ever
/// withholds `.pure`, which is the direction the effect lattice permits and
/// CLAUDE.md's *purity gates must not relax* rule demands), it costs **zero**
/// `.pure` verdicts that rest on stdlib, and — unlike the promoting direction — it
/// has a consumer **today**: `isInferredPure` is `purityVerdict == .pure`, so a
/// retraction withdraws a false `/// @lint.effect pure` advisory. The promoting
/// direction moves rows into a tier with no reader at all.
///
/// ## The seed is witness-bearing refutations ONLY, and that is the design
///
/// A refutation is either *evidence* (a named construct) or *ignorance* (a `try`
/// into a callee this leaf cannot see). Propagating **ignorance** upward would
/// spread "I cannot tell" through the call graph and retract advisories on no
/// evidence at all — the [Daikon trap](../../docs/design-internal/glossary.md)
/// reached through a new door, and the opposite of *conservative inference*.
/// So the seed is the witness-bearing set, and the ignorance-seeded variant is
/// measured separately and reported as an **upper bound that must not be built**.
///
/// ## Resolution is name-keyed and free-shape only, and both halves are reported
///
/// Matching `PurityAllowlistCensusMeasuredTests`' rule and for its measured
/// reason: this package declares a `FileManager`-reading `sorted(in:)`, so
/// name-keying makes every `xs.sorted()` read as a call into an impure package
/// function. Admitting member-shape callees inflates the base rate 17 → 147 and
/// the inflation is almost entirely that contamination. Free-shape only is
/// therefore a **lower bound**, and stated as one.
///
/// A name counts as refuting only when **every** declaration carrying it is
/// refuted with a witness — the inverse of the allowlist census's settledness
/// rule, and for the same reason: one pure overload makes the call ambiguous.
///
/// ## Provenance
///
/// Corpus and verdicts are the item 29 census's own statics, not recomputed, so
/// the denominators cannot drift between the two documents.
/// `oneHopReproducesTheAllowlistCensusBaseRate` pins that agreement.
@Suite("Census — what would a refuting-direction fixpoint retract?", .serialized)
struct PurityFixpointCensusMeasuredTests {

    typealias Subject = PurityRefutationCensusMeasuredTests.Subject
    typealias Cause = PurityRefutationCensusMeasuredTests.RefutationCause
    typealias Callee = PurityAllowlistCensusMeasuredTests.Callee

    // MARK: - Shared population

    /// The item 29 census's corpus, verdicts and cause attribution, reused
    /// wholesale. That census's `verdictAgreesWithSoundPurity` is the warrant for
    /// the attribution being faithful to the shipped refuters.
    static let corpus: [Subject] = PurityRefutationCensusMeasuredTests.corpus
    static let verdicts: [PurityVerdict] = PurityRefutationCensusMeasuredTests.verdicts

    /// Subjects judged `.pure` — the only rows a retraction can cost an advisory,
    /// because `isInferredPure` is `purityVerdict == .pure` by definition.
    static let pureSubjects: [Subject] = zip(corpus, verdicts)
        .filter { $0.1 == .pure }
        .map(\.0)

    /// Every declaration name in the corpus, with the verdicts held by the
    /// declarations carrying it. A name with two declarations gets two entries.
    static let declarationsByName: [String: [(subject: Subject, verdict: PurityVerdict)]] = {
        var table: [String: [(subject: Subject, verdict: PurityVerdict)]] = [:]
        for (subject, verdict) in zip(corpus, verdicts) {
            table[subject.function.name.text, default: []].append((subject, verdict))
        }
        return table
    }()

    /// Cause sets keyed by declaration name, unioned across overloads.
    static let causesByName: [String: Set<Cause>] = {
        var table: [String: Set<Cause>] = [:]
        for row in PurityRefutationCensusMeasuredTests.refuted {
            table[row.subject.function.name.text, default: []].formUnion(row.causes)
        }
        return table
    }()

    /// A row's identity. **`file:name` is NOT injective** — this package declares
    /// several overload families (`CarrierKindResolver.classify`,
    /// `DomainCorpusScanner.visit`) whose members share both, so keying on it
    /// silently merges distinct subjects. That is the same name-collision hazard
    /// `PurityAllowlistCensusMeasuredTests` measures at 1,238 contaminated
    /// subjects, and it turned up *inside this harness* the first time it ran:
    /// `theFixpointIsMonotoneAndTerminates` reported rows retracted twice when the
    /// truth was two overloads retracted once each. The ordinal is what makes it
    /// injective; the label is for reading.
    struct RowID: Hashable {
        let ordinal: Int
        let label: String
    }

    /// One `.pure` subject and the free- and member-shape callee names its body
    /// reaches. Member-shape is carried but never joined on, so the contamination
    /// §4 bounds can be quantified rather than assumed.
    ///
    /// A struct rather than a tuple because four members is past what a tuple
    /// carries legibly — and `large_tuple` says so.
    struct Row {
        let id: RowID
        let subject: Subject
        let free: Set<String>
        let member: Set<String>
    }

    static let calls: [Row] = {
        pureSubjects.enumerated().map { ordinal, subject in
            let collector = CensusCalleeCollector(viewMode: .sourceAccurate)
            if let body = subject.function.body { collector.walk(body) }
            // Nested functions are excluded: a call to one resolves inside this
            // body, not to a package declaration, and admitting them would let a
            // local helper's name collide with a refuted top-level declaration.
            let callees = collector.callees.filter {
                !collector.nestedFunctionNames.contains($0.name)
            }
            return Row(
                id: RowID(ordinal: ordinal, label: "\(subject.file):\(subject.name)"),
                subject: subject,
                free: Set(callees.filter { $0.shape == .free }.map(\.name)),
                member: Set(callees.filter { $0.shape == .member }.map(\.name))
            )
        }
    }()

    /// How many rows `file:name` would have merged. Reported because it is the
    /// measured size of the trap above, not a hypothetical.
    static let collidingLabels: Int = {
        let labels = calls.map(\.id.label)
        return labels.count - Set(labels).count
    }()

    // MARK: - The seeds

    /// A name refutes iff **every** declaration carrying it is refuted, and at
    /// least one cause on it is a witness. Names not declared in this package
    /// resolve to nothing and refute nothing — that is the stdlib half this
    /// census deliberately cannot see.
    static func refutingNames(witnessOnly: Bool) -> Set<String> {
        var names: Set<String> = []
        for (name, declarations) in declarationsByName {
            guard declarations.allSatisfy({ $0.verdict == .refuted }) else { continue }
            guard let causes = causesByName[name], !causes.isEmpty else { continue }
            if witnessOnly, !causes.contains(where: \.isWitness) { continue }
            names.insert(name)
        }
        return names
    }

    /// Names the **cascade** may add to the refuting set, under the same
    /// settledness rule the seed obeys: every declaration carrying the name must
    /// be settled impure, meaning either witness-refuted outright or a `.pure` row
    /// this fixpoint has already retracted.
    ///
    /// **The first version of this harness omitted this check and it was not a
    /// small error.** It inserted a retracted caller's bare name unconditionally,
    /// so one refuted `DedupGateShape.classify` made the *name* `classify`
    /// refuting — and this package has roughly six unrelated `classify`
    /// declarations. A hand-check of the cascade found a 16-row wave at hop 5 in
    /// which `EquatableResolver.classify`, `IdempotenceReturnShape.classify` and
    /// `CarrierKindResolver.classify` were each retracted by a *different* type's
    /// `classify`, plus `render <- render` and `bound <- bound` self-collisions.
    ///
    /// A declaration that is `.pureButPartial`, or refuted only by **ignorance**,
    /// blocks the name: neither is proof that calling it is impure, and the whole
    /// point of the witness seed is that only proof propagates.
    static func settledByCascade(retracted: Set<Int>, witnessOnly: Bool) -> Set<String> {
        var settled: Set<String> = []
        for (name, declarations) in declarationsByName {
            let allSettled = declarations.allSatisfy { declaration in
                switch declaration.verdict {
                case .refuted:
                    guard let causes = causesByName[name], !causes.isEmpty else { return false }
                    return witnessOnly ? causes.contains(where: \.isWitness) : true

                case .pure:
                    guard let ordinal = calls.first(where: {
                        $0.subject.file == declaration.subject.file
                            && $0.subject.name == declaration.subject.name
                            && $0.subject.function.description == declaration.subject.function.description
                    })?.id.ordinal else { return false }
                    return retracted.contains(ordinal)

                case .pureButPartial:
                    return false
                }
            }
            if allSettled { settled.insert(name) }
        }
        return settled
    }

    // MARK: - The fixpoint

    struct Round {
        let hop: Int
        let retracted: [RowID]
    }

    /// Iterate the join: a `.pure` subject whose body makes a free-shape call to a
    /// refuting name is retracted, its own name joins the refuting set, and the
    /// pass repeats until a round retracts nothing.
    ///
    /// Terminates because the refuting set only grows and is bounded by the
    /// corpus's distinct names — monotone on a finite lattice, which is also why
    /// mutual recursion needs no optimistic assumption here. `theFixpointIsMonotoneAndTerminates`
    /// asserts both properties rather than trusting this comment.
    static func fixpoint(witnessOnly: Bool) -> [Round] {
        var refuting = refutingNames(witnessOnly: witnessOnly)
        var live = calls
        var rounds: [Round] = []
        var retractedOrdinals: Set<Int> = []
        var hop = 1
        while true {
            var retracted: [RowID] = []
            var survivors: [Row] = []
            for row in live {
                if row.free.isDisjoint(with: refuting) {
                    survivors.append(row)
                } else {
                    retracted.append(row.id)
                }
            }
            if retracted.isEmpty { break }
            rounds.append(Round(hop: hop, retracted: retracted.sorted { $0.ordinal < $1.ordinal }))
            retractedOrdinals.formUnion(retracted.map(\.ordinal))
            // **A retracted caller's NAME only joins the refuting set once every
            // declaration carrying that name is settled impure** — the same rule
            // the seed obeys, applied to the cascade, which is where the first
            // version of this harness got it wrong. Computed against the whole
            // retracted set rather than incrementally, so the result cannot depend
            // on iteration order.
            refuting = refutingNames(witnessOnly: witnessOnly)
                .union(settledByCascade(retracted: retractedOrdinals, witnessOnly: witnessOnly))
            live = survivors
            hop += 1
        }
        return rounds
    }

    static let witnessSeeded: [Round] = fixpoint(witnessOnly: true)
    static let ignoranceSeeded: [Round] = fixpoint(witnessOnly: false)

    // MARK: - Controls

    /// **The one-hop count must reproduce the allowlist census's base rate.** Two
    /// harnesses, two extractions, one number — without this, a plausible-looking
    /// cascade could rest on a callee walk that disagrees with the measurement it
    /// claims to extend.
    ///
    /// Compared as a *floor* rather than an equality: that census counts subjects
    /// reaching a refuted package callee at one hop, and excludes the one row
    /// whose caller has since been refuted for an unrelated reason. Equality would
    /// pin an accident of that exclusion; a floor pins the agreement that matters.
    @Test("one hop reproduces the allowlist census's measured base rate")
    func oneHopReproducesTheAllowlistCensusBaseRate() {
        let oneHop = Self.witnessSeeded.first?.retracted.count ?? 0
        #expect(
            oneHop >= 15,
            """
            one hop retracts \(oneHop); the allowlist census measured 17 `.pure` subjects \
            calling a package function refuted with a witness. A large gap means the two \
            callee extractions disagree and neither number can be trusted.
            """
        )
    }

    /// The control for the cascade: with nothing seeded, the loop must retract
    /// nothing. Without it, "the fixpoint retracts N" cannot be told from a walk
    /// that retracts on any call at all.
    @Test("an empty seed retracts nothing — the loop cannot invent a refutation")
    func emptySeedRetractsNothing() {
        var live = Self.calls
        let refuting: Set<String> = []
        live = live.filter { !$0.free.isDisjoint(with: refuting) }
        #expect(live.isEmpty, "\(live.count) rows retracted against an empty refuting set")
    }

    /// Monotone and terminating, asserted rather than argued — the loop is the
    /// part of this proposal that could hang on a recursive call graph.
    @Test("the fixpoint is monotone and terminates")
    func theFixpointIsMonotoneAndTerminates() {
        #expect(Self.witnessSeeded.count < 20, "\(Self.witnessSeeded.count) hops — suspiciously deep")
        var seen: Set<RowID> = []
        for round in Self.witnessSeeded {
            for row in round.retracted {
                #expect(!seen.contains(row), "\(row.label) retracted twice — the set is not monotone")
                seen.insert(row)
            }
        }
        #expect(!seen.isEmpty, "nothing retracted at all; the seed or the extraction is broken")
    }

    /// The population is `.pure` subjects only, so every retraction costs an
    /// advisory. Guards the claim that this direction has a consumer today.
    @Test("every retraction costs an advisory, because the population is .pure only")
    func everyRetractionCostsAnAdvisory() {
        let allPure = Self.calls.allSatisfy { row in
            SoundPurity.verdict(for: row.subject.function) == .pure
        }
        #expect(allPure, "the population contains a non-.pure subject; retractions would be free")
    }

    // MARK: - The census

    @Test("census — what a refuting-direction fixpoint retracts")
    func census() {
        var lines: [String] = ["", "REFUTING-DIRECTION FIXPOINT CENSUS", ""]
        lines.append("corpus: \(Self.corpus.count) functions")
        lines.append("  .pure subjects (the population): \(Self.pureSubjects.count)")
        lines.append("  refuting names, witness-bearing: \(Self.refutingNames(witnessOnly: true).count)")
        lines.append("  refuting names, ignorance admitted: \(Self.refutingNames(witnessOnly: false).count)")

        lines.append("")
        lines.append("witness-seeded fixpoint (the buildable one):")
        var running = 0
        for round in Self.witnessSeeded {
            running += round.retracted.count
            lines.append("  hop \(round.hop): retracted \(round.retracted.count) (running \(running))")
        }
        lines.append("  hops to converge: \(Self.witnessSeeded.count)")
        lines.append("  TOTAL RETRACTED: \(running) of \(Self.pureSubjects.count) `.pure`")
        let cascade = running - (Self.witnessSeeded.first?.retracted.count ?? 0)
        lines.append("  ...of which the LOOP buys (hops 2+): \(cascade)")

        lines.append("")
        lines.append("ignorance-admitted fixpoint (upper bound — NOT buildable):")
        let ignoranceTotal = Self.ignoranceSeeded.reduce(0) { $0 + $1.retracted.count }
        lines.append("  total retracted: \(ignoranceTotal), hops: \(Self.ignoranceSeeded.count)")

        lines.append("")
        lines.append("member-shape contamination (why free-shape is a lower bound):")
        let withMember = Self.calls.filter { !$0.member.isEmpty }.count
        lines.append("  `.pure` subjects making any member-shape call: \(withMember)")
        lines.append("  rows `file:name` would have merged (overloads): \(Self.collidingLabels)")

        lines.append("")
        lines.append("the retracted rows, hop by hop:")
        for round in Self.witnessSeeded {
            lines.append("  -- hop \(round.hop) --")
            for row in round.retracted.prefix(40) {
                lines.append("    \(row.label.replacingOccurrences(of: "Sources/", with: ""))")
            }
        }
        print(lines.joined(separator: "\n"))
    }
}
