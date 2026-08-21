/// The canonical vocabulary of property-template names.
///
/// The template name is persisted as a plain `String` on `SemanticIndexEntry` /
/// `Suggestion` and in the verify-evidence JSON, and it is `switch`ed on in the
/// per-template dispatch and rendering paths — those stay string-keyed, because
/// the wire format and the exhaustive dispatch are their own concerns. What this
/// type centralizes is the **vocabulary and its subsets**: the several curated
/// lists ("the verifiable templates", "the ones whose regression test
/// auto-derives", "the v1.46 hardcoded set", …) that had each re-spelled the
/// template-name string literals and could silently drift apart.
///
/// With the names living here once, every subset is expressed as typed cases —
/// a misspelling is a compile error, a removed template breaks each subset that
/// named it, and the subset *relationships* (auto-derivable = v1.46 set plus
/// monotonicity; the strategist's algebraic laws = verifiable minus the two
/// specially-routed ones) are written structurally instead of maintained by
/// hand across files.
///
/// Interaction-invariant families (`conservation`, `cardinality`, …) are a
/// separate vocabulary and live in `InteractionInvariantFamily`.
public enum TemplateName: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    // Verify-measurable algebraic / structural templates — the `supportedTemplates` set.
    case roundTrip = "round-trip"
    case codableRoundTrip = "codable-round-trip"
    case idempotence
    case commutativity
    case associativity
    case idempotenceLifted = "idempotence-lifted"
    case dualStyleConsistency = "dual-style-consistency"
    case monotonicity
    case involution
    case binaryIdempotence = "binary-idempotence"
    case homomorphism
    case multiplicativeHomomorphism = "multiplicative-homomorphism"
    case measureNonNegativity = "measure-non-negativity"

    /// The **role postcondition** law — a function whose NAME names an operation with a
    /// known guarantee owes that guarantee of its output.
    ///
    /// `docs/measurements/postcondition-law-declined.md` measured the postcondition at
    /// **4 of 4 real bugs killed** on a normaliser where **idempotence killed 1 of 4**,
    /// then declined two routes that try to *discover* the predicate and measured a third
    /// — the catalogue supplying it from a recognised role — at **~33 sites, ~97%
    /// precision** across the 17 corpora. `measureNonNegativity` is the same pattern
    /// already shipping at 401 rows; this widens it past `>= 0`.
    case rolePostcondition = "role-postcondition"

    /// Differential / oracle equivalence: two implementations of one
    /// specification must agree on every input — `reference(x) == variant(x)`.
    ///
    /// **Verifiable since 2026-08-08, and the delay was not a design decision.**
    /// The law is the simplest two-call shape there is (one generated value,
    /// two calls, compare), simpler than `round-trip`, which nests them. What
    /// blocked it was that `IndexCommand+Projection` persisted
    /// `secondaryFunctionName` for `round-trip` only, so the variant half of the
    /// pair was computed by `DifferentialTemplate` and then discarded — the
    /// verify path declined `unsupported-template` for want of data the
    /// discover path already had.
    case differentialEquivalence = "differential-equivalence"

    /// Totality: the predicate returns a value for **every** input its type
    /// admits — never traps, never diverges.
    ///
    /// Verifiable, but not like the others, and the difference is why it took
    /// until 2026-08-03 to become so. Every law above fails by **assertion**,
    /// which is catchable and prints a counterexample. Totality fails by
    /// **trap**, which is not: the process dies, no result marker is printed,
    /// and `VerifyResult.parse` rule 4 would file the single most valuable
    /// outcome under `.error` — the same bucket as a broken build.
    ///
    /// `composePredicatePass` therefore prints each input **before the call**,
    /// and `parse`'s trap branch recovers that marker and reports a refutation.
    /// It survives the crash only because `SeededStubEmitter`'s preamble sets
    /// `setvbuf(stdout, nil, _IONBF, 0)`.
    case predicate

    // Additional discovery / pack template names — surfaced by discovery and
    // grouped into `TemplatePack`s, but not members of the verifiable set above
    // (they are witnessed or routed differently).
    case inversePair = "inverse-pair"
    case identityElement = "identity-element"
    case composition
    /// Invariant preservation — `inv(f(x))` whenever `inv(x)`.
    ///
    /// **Not in `verifiable`, and unlike `replay-idempotence` the obstacle is
    /// this repo's own plumbing rather than the law.** The oracle is already
    /// written and shipping: `LiftedTestEmitter.invariantPreserving` emits
    /// `!value[keyPath: kp] || f(value)[keyPath: kp]`. A verify composer would
    /// state the same thing.
    ///
    /// What is missing is `kp`. The keypath is scanned into
    /// `FunctionSummary.invariantKeypath`, carried through `Evidence`, and
    /// recovered downstream by *parsing the signature back out*
    /// (`InteractiveTriage+Accept.swift:298`). `SemanticIndexEntry` carries
    /// neither the keypath nor the signature, so verify — which sees only the
    /// entry — cannot reconstruct which invariant to check. It is the same
    /// shape as the `differential-equivalence` gap fixed on 2026-08-08 (data
    /// computed at discover time and dropped before the index), but the remedy
    /// is larger: differential's second half already had a field waiting for it,
    /// and this needs a new one.
    ///
    /// Two things to settle before building it, neither of which is cost:
    /// 1. The keypath is **opaque source text** by design (M7 open decision
    ///    #5(a)). `LiftedTestEmitter` can accept that because a non-resolving
    ///    keypath becomes a compile error in the user's own test target, which
    ///    they are reviewing. In verify the same failure becomes
    ///    `measured-error: build-failed` — an instrument-failure bucket — for a
    ///    law that may be perfectly true but names a non-public member.
    /// 2. This repo currently has **no annotated subject at all**: every
    ///    `preservesInvariant` occurrence is a test expectation. Shipping the
    ///    path would mean shipping a composer nothing exercises.
    ///
    /// Deferred rather than declined — the law is verifiable in principle and
    /// the oracle exists. The falsifier is registered in CLAUDE.md rather than
    /// here, because `DeferralFalsifierTests` scans `CLAUDE.md` and `docs/` and
    /// **not `Sources/`**: an annotation written here would read as guarded
    /// while nothing checked it.
    case invariantPreservation = "invariant-preservation"

    /// Replay-idempotency: a side-effecting handler that is safe to run *twice*
    /// (its observable effects happen once), stated over effects rather than a
    /// return value. Discovered by `ReplayIdempotenceTemplate` and rendered as an
    /// `assertIdempotentEffects` accept-flow scaffold. **Deliberately NOT in
    /// `verifiable`:** the effect boundary (a recorder observing the real
    /// side effect) cannot be synthesized, so `swift-infer verify` has nothing to
    /// run — the property is completed by the author, not measured by the tool.
    case replayIdempotence = "replay-idempotence"
}

public extension TemplateName {
    /// The templates `swift-infer verify` can measure directly — the canonical
    /// "supported templates" list, in dispatch/display order.
    static let verifiable: [TemplateName] = [
        .roundTrip, .codableRoundTrip, .idempotence, .commutativity, .associativity,
        .idempotenceLifted, .dualStyleConsistency, .monotonicity,
        .involution, .binaryIdempotence, .homomorphism, .multiplicativeHomomorphism,
        .measureNonNegativity, .predicate, .differentialEquivalence
    ]

    // swiftprojectlint:disable:next parallel-list-drift
    /// The four templates the v1.46 hardcoded per-carrier emitters support.
    ///
    /// (Coincidentally shares three algebraic names with the unrelated
    /// `TemplateSignal` axiom-signal enum — see the note there; not drift.)
    static let v146Hardcoded: [TemplateName] = [
        .roundTrip, .idempotence, .commutativity, .associativity
    ]

    /// Templates whose default-fail regression test can be auto-derived: the
    /// v1.46 hardcoded set plus `monotonicity`. Written as that relationship so
    /// the two lists cannot drift apart — which is exactly what they had begun to.
    static let regressionAutoDerivable: [TemplateName] = v146Hardcoded + [.monotonicity]

    /// The algebraic-law templates the strategist routes: everything verifiable
    /// except the three that dispatch elsewhere (`codable-round-trip` has its own
    /// Codable path; `measure-non-negativity` is a measure template; `predicate`
    /// is a totality check and not an algebraic law at all). Derived from
    /// `verifiable` so it stays in step by construction.
    ///
    /// **`predicate` must stay excluded.** `defaultPassSection` falls through to
    /// `algebraicLawPass` for anything in this list, so leaving it in would route
    /// totality into a switch that cannot compose it — and the error message
    /// naming this set would then list a template it cannot actually handle.
    static let strategistAlgebraicLaws: [TemplateName] =
        verifiable.filter {
            $0 != .codableRoundTrip && $0 != .measureNonNegativity && $0 != .predicate
        }
}

public extension Sequence where Element == TemplateName {
    /// The wire/string spellings of these template names, for the many APIs that
    /// still key on the persisted `String`.
    var rawValues: [String] { map(\.rawValue) }
}
