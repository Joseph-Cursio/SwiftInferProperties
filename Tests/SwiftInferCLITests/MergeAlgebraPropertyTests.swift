import Foundation
import PropertyLawKit
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// Self-dogfood road test (`docs/roadtest-self-dogfood.md`) — the laws
// `swift-infer discover --target SwiftInferCore` proposed against this repo's
// own persistence layer, executed rather than read.
//
// The tool surfaced `merge(_:)` on four logs — `Decisions`,
// `InteractionDecisions`, `PostAcceptanceOutcomeLog`, `VerifyEvidenceLog` — as
// **both** associativity and commutativity candidates, at the same default
// (`Likely`) tier. That pairing is the whole point of running them: the four
// folds were structurally identical last-write-wins merges, associativity held,
// and **commutativity did not**. Reading the code does not tell you which of
// the two equal-confidence proposals is the real one. Executing them does.
//
// **Both laws now hold (2026-08-05).** The four folds were replaced by one
// shared `IdentityKeyedFold` that breaks a timestamp tie by the records'
// canonical encoding instead of by argument position, which makes the merge
// commutative *and* leaves associativity intact — see that type's doc for why
// `>=` → `>` would not have been a fix. The re-measurement that prompted it was
// the whole-corpus verify survey: `commutativity` ran four laws on this repo,
// all four were one of these merges, and all four refuted.
//
// **This suite is now clock-driven, and that is the second half of the story.**
// The first version built `DecisionRecord`s and `VerifyEvidence`s by hand at
// literal instants, because the production code stamped them with an
// un-injectable `Date()` and there was no other way to reach a tie. That is a
// test-side workaround for a source-side problem, and SwiftProjectLint had
// already said so — its `Non-Injected Nondeterminism` rule fired on those exact
// stamps: *"`Date()` makes this code unpredictable, so a property-based test
// can't pin the value or reproduce a failure."* (§12.)
//
// With the clock injected, every record below is built by the **production
// builder** at an instant this suite chooses:
//
//   * `InteractiveTriage.makeRecord(for:decision:timestamp:)` → `DecisionRecord`
//   * `ViewModelVerifyEvidence.evidence(for:outcome:now:)`    → `VerifyEvidence`
//
// Two things follow. The laws now cover the builders, not just the folds — a
// builder that dropped a field or mis-stamped would fail here. And the tie that
// refutes commutativity is produced by *the clock reading twice the same*,
// which is what actually happens in production when two records are written
// inside one whole second and persisted at `.iso8601` resolution — rather than
// by a literal chosen to make the point.
//
// Two of the four docstrings used to claim the aggregate is "order-deterministic
// regardless of input ordering." The *sort* was; which record survived to be
// sorted was not — the claim was true of the rows and false of their contents.
// That is now true as written, and the four docstrings say which half is which.
// These tests pin the laws (associativity, commutativity, normalizer
// idempotence, identity); there is no longer a drift arm.
@Suite("Road test — merge fold algebra, driven by an injected clock")
struct MergeAlgebraPropertyTests {

    // MARK: - A controllable clock
    //
    // Three whole-second readings. Whole seconds because that is the resolution
    // `.iso8601` persistence actually round-trips (see
    // `iso8601PersistenceTruncatesToWholeSeconds`); only three of them because
    // collisions are the subject — a clock that never reads the same value twice
    // would leave the tie-break path unexercised and the suite green for the
    // wrong reason.

    static let readings = [
        Date(timeIntervalSince1970: 1_000_000),
        Date(timeIntervalSince1970: 1_000_001),
        Date(timeIntervalSince1970: 1_000_002)
    ]

    /// Three identities, so a merge has something to collide on.
    static let identities = ["alpha", "beta", "gamma"].map {
        SuggestionIdentity(canonicalInput: "merge-law::\($0)")
    }

    static func suggestion(_ identity: SuggestionIdentity) -> Suggestion {
        Suggestion(
            templateName: "idempotence",
            evidence: [
                Evidence(
                    displayName: "normalize",
                    signature: "(T) -> T",
                    location: SourceLocation(file: "Carrier.swift", line: 1, column: 1)
                )
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 80, detail: "curated verb")]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: identity
        )
    }

    static func interactionSuggestion(
        _ identity: SuggestionIdentity
    ) -> InteractionInvariantSuggestion {
        InteractionInvariantSuggestion(
            identity: identity,
            family: .idempotence,
            reducerQualifiedName: "Feature.reduce",
            reducerLocation: "Feature.swift:1",
            stateTypeName: "State",
            actionTypeName: "Action",
            predicate: "p",
            score: 40,
            tier: .likely,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - Generators
    //
    // A log is generated as one choice **per identity**: `0` omits that
    // identity, otherwise the choice selects a `(clock reading, payload)` pair
    // and the record is built by the production builder at that reading. One
    // record per identity, because that is the invariant the logs actually
    // maintain — see `wellFormedLogsHoldOneRecordPerIdentity`.

    private static let decisionChoices: [(Date, Decision)] = readings.flatMap { reading in
        Decision.allCases.map { (reading, $0) }
    }

    private static let evidenceChoices: [(Date, VerifyOutcome)] = readings.flatMap { reading in
        [
            VerifyOutcome.bothPass(defaultTrials: 100, edgeTrials: 0, edgeSampled: 0),
            .defaultFails(DefaultFailDetail(trial: 1, input: "x", forwardResult: "a", inverseResult: "b"))
        ].map { (reading, $0) }
    }

    private static let decisionsGen = Gen<Int>.int(in: 0...decisionChoices.count)
        .array(of: identities.count)
        .map { choices in
            Decisions(
                records: zip(identities, choices).compactMap { identity, choice in
                    guard choice > 0 else { return nil }
                    let (reading, decision) = decisionChoices[choice - 1]
                    // Built by the production builder, stamped by our clock.
                    return InteractiveTriage.makeRecord(
                        for: suggestion(identity),
                        decision: decision,
                        timestamp: reading
                    )
                }
            )
        }

    private static let evidenceGen = Gen<Int>.int(in: 0...evidenceChoices.count)
        .array(of: identities.count)
        .map { choices in
            VerifyEvidenceLog(
                records: zip(identities, choices).compactMap { identity, choice in
                    guard choice > 0 else { return nil }
                    let (reading, outcome) = evidenceChoices[choice - 1]
                    return ViewModelVerifyEvidence.evidence(
                        for: interactionSuggestion(identity),
                        outcome: outcome,
                        now: reading
                    )
                }
            )
        }

    // MARK: - The laws that hold

    /// Associativity — the law `discover` proposed that is genuinely true.
    ///
    /// Refutable, and not vacuously so: the fold's winner is "max timestamp,
    /// with ties broken by iteration order," and it is not obvious from reading
    /// that re-associating cannot move the tie-break. It cannot, because
    /// re-association preserves the left-to-right order in which equal-timestamp
    /// records are first seen. A fold that broke ties the other way ("last seen
    /// wins") would still look fine on hand-picked examples and would fail here.
    @Test("Decisions.merge is associative")
    func decisionsMergeIsAssociative() async {
        await propertyCheck(
            input: Self.decisionsGen,
            Self.decisionsGen,
            Self.decisionsGen
        ) { left, mid, right in
            #expect(left.merge(mid).merge(right) == left.merge(mid.merge(right)))
        }
    }

    @Test("VerifyEvidenceLog.merge is associative")
    func evidenceMergeIsAssociative() async {
        await propertyCheck(
            input: Self.evidenceGen,
            Self.evidenceGen,
            Self.evidenceGen
        ) { left, mid, right in
            #expect(left.merge(mid).merge(right) == left.merge(mid.merge(right)))
        }
    }

    /// **Idempotence, correctly scoped: `merge` is a normalizer, and it is
    /// idempotent on its own image — not on an arbitrary log.**
    ///
    /// The naive statement `a.merge(a) == a` is false, and finding out *why*
    /// took executing it. `merge` returns its records sorted by
    /// `(timestamp, identityHash)`, but `upserting(_:)` — the canonical mutator
    /// that actually builds these logs — **appends**. So a log assembled the
    /// normal way is in insertion order, and merging it with itself reorders it.
    @Test("merge is idempotent on its own image — it is a normalizer")
    func mergeIsIdempotentOnItsOwnImage() async {
        await propertyCheck(input: Self.decisionsGen, Self.decisionsGen) { left, right in
            let normalized = left.merge(right)
            #expect(normalized.merge(normalized) == normalized)
        }
        await propertyCheck(input: Self.evidenceGen, Self.evidenceGen) { left, right in
            let normalized = left.merge(right)
            #expect(normalized.merge(normalized) == normalized)
        }
    }

    /// The empty log is a right identity on the record set, modulo the
    /// normalization above — the comparison is on records rather than the whole
    /// value because `merge` also takes `max` of the two `schemaVersion`s.
    @Test("the empty log is a right identity on the record set")
    func emptyIsRightIdentityOnRecordSet() async {
        await propertyCheck(input: Self.decisionsGen) { log in
            let merged = log.merge(Decisions())
            #expect(merged.records.count == log.records.count)
            #expect(merged.records == log.records.sorted { lhs, rhs in
                lhs.timestamp != rhs.timestamp
                    ? lhs.timestamp < rhs.timestamp
                    : lhs.identityHash < rhs.identityHash
            })
        }
        await propertyCheck(input: Self.evidenceGen) { log in
            let merged = log.merge(VerifyEvidenceLog())
            #expect(merged.records.count == log.records.count)
            #expect(merged.records == log.records.sorted { lhs, rhs in
                lhs.capturedAt != rhs.capturedAt
                    ? lhs.capturedAt < rhs.capturedAt
                    : lhs.identityHash < rhs.identityHash
            })
        }
    }

    /// `schemaVersion` folds as a commutative, associative, idempotent `max` —
    /// the one genuinely semilattice-shaped part of the merge. Worth pinning
    /// separately precisely *because* the record fold is not commutative: it
    /// localises the asymmetry to the record side.
    @Test("schemaVersion folds as max — commutative and associative")
    func schemaVersionFoldsAsMax() async {
        await propertyCheck(input: Self.decisionsGen, Self.decisionsGen) { left, right in
            #expect(left.merge(right).schemaVersion == right.merge(left).schemaVersion)
            #expect(left.merge(right).schemaVersion == max(left.schemaVersion, right.schemaVersion))
        }
    }

    /// Every surviving record came from one of the two inputs, and no identity
    /// appears twice. The fold is a *selection*, never a synthesis.
    @Test("merge selects — output records are input records, one per identity")
    func mergeSelectsWithoutDuplicatingIdentities() async {
        await propertyCheck(input: Self.decisionsGen, Self.decisionsGen) { left, right in
            let merged = left.merge(right)
            let inputs = left.records + right.records
            for record in merged.records {
                #expect(inputs.contains(record), "merge invented a record")
            }
            let hashes = merged.records.map(\.identityHash)
            #expect(Set(hashes).count == hashes.count, "merge duplicated an identity")
            #expect(Set(hashes) == Set(inputs.map(\.identityHash)), "merge dropped an identity")
        }
    }

    /// **The unenforced uniqueness invariant these laws are stated over.**
    ///
    /// `upserting(_:)` is the canonical mutator and keeps one record per
    /// identity, but the public memberwise `init(records:)` accepts any array,
    /// so a duplicate-identity log is representable and `DecisionsLoader` will
    /// decode one from a hand-edited JSON file. The first version of this suite
    /// failed all eight of its tests on exactly this, and the shrinker named the
    /// cause in one line.
    ///
    /// That is a *representable illegal state* — the smell this repo's own
    /// cardinality and biconditional families exist to flag in other people's
    /// code. Recorded rather than fixed: narrowing the initializer is an API
    /// change across the loaders.
    @Test("well-formed logs hold one record per identity — an unenforced invariant")
    func wellFormedLogsHoldOneRecordPerIdentity() {
        let record = InteractiveTriage.makeRecord(
            for: Self.suggestion(Self.identities[0]),
            decision: .accepted,
            timestamp: Self.readings[0]
        )

        let illFormed = Decisions(records: [record, record])
        #expect(illFormed.records.count == 2)
        #expect(illFormed.merge(illFormed).records.count == 1)
        #expect(illFormed.merge(illFormed) != illFormed)

        let wellFormed = Decisions().upserting(record).upserting(record)
        #expect(wellFormed.records.count == 1)
        #expect(wellFormed.merge(wellFormed) == wellFormed)
    }

    /// `upserting` appends and `merge` sorts, so merging an ordinary log with
    /// itself reorders it — the concrete case behind the normalizer law above.
    @Test("upserting appends, merge sorts — so merge reorders an ordinary log")
    func upsertingAppendsWhileMergeSorts() {
        let later = InteractiveTriage.makeRecord(
            for: Self.suggestion(Self.identities[0]),
            decision: .accepted,
            timestamp: Self.readings[2]
        )
        let earlier = InteractiveTriage.makeRecord(
            for: Self.suggestion(Self.identities[1]),
            decision: .rejected,
            timestamp: Self.readings[0]
        )
        let log = Decisions().upserting(later).upserting(earlier)

        #expect(log.records == [later, earlier], "upserting preserves insertion order")
        #expect(log.merge(log).records == [earlier, later], "merge imposes timestamp order")
        #expect(log.merge(log) != log)
        #expect(log.merge(log).merge(log.merge(log)) == log.merge(log))
    }

    /// The mechanism that makes a clock tie reachable in production even when
    /// the wall clock never actually repeats: the persistence date strategy is
    /// whole-second, so a sub-second distinction that exists in memory is gone
    /// by the time two files are merged.
    ///
    /// This is why the clock-driven laws above are stated over whole-second
    /// readings rather than arbitrary instants — the tie is not a contrivance,
    /// it is what the on-disk format produces.
    @Test("ISO8601 persistence truncates to whole seconds — the tie's mechanism")
    func iso8601PersistenceTruncatesToWholeSeconds() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let first = Date(timeIntervalSince1970: 1_000_000.1)
        let second = Date(timeIntervalSince1970: 1_000_000.5)
        #expect(first != second)

        let roundTripped = try [first, second].map { instant -> Date in
            try decoder.decode([Date].self, from: encoder.encode([instant]))[0]
        }
        #expect(
            roundTripped[0] == roundTripped[1],
            "distinct in memory, identical on disk — this is what makes the tie reachable"
        )
    }
}
