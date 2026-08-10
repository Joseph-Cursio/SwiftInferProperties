import Foundation

/// The catalogue of signal kinds the §4 scoring engine recognises.
///
/// Extracted from `Signal.swift`, which crossed SwiftLint's 400-line file cap. The seam
/// is the natural one rather than an arithmetic split: this file is a *documented
/// vocabulary* — every case carries the measurement or the corpus finding that justifies
/// its weight — while `Signal.swift` keeps the value type, the veto sentinel, and the
/// rendering. Additions land here and cost one case plus a row in the PRD weight table.
extension Signal {

    public enum Kind: String, Sendable, Equatable, CaseIterable {

        // Positive
        case exactNameMatch
        case typeSymmetrySignature
        case orderedCodomainSignature
        case algebraicStructureCluster
        case reduceFoldUsage
        case discoverableAnnotation
        case testBodyPattern
        case crossValidation
        case samplingPass
        case selfComposition
        /// The function was supplied as a lint seed (external evidence of
        /// purity), which justifies the generic determinism law `f(x) == f(x)`.
        /// Seed-driven rather than inferred from the signature.
        case deterministicPurity

        /// The function's own docstring independently asserts the property a
        /// template has already matched by *shape* — a documented `idempotent`,
        /// `self-inverse`, etc. **Corroborate-only** (`DocstringPropertyCorroborator`):
        /// emitted at +15 to *raise the tier* of a shape-matched candidate
        /// (typically Possible 30 → Likely 45, surfacing a documented-but-not-
        /// curated-name law by default), never to surface a law the shape did not
        /// match. Weaker than an exact curated-verb name (+40) — prose can be
        /// aspirational — but stronger than a fuzzy fixed-point name (+10), since
        /// an explicit assertion is direct evidence. Negation-gated at the source
        /// so "not idempotent" never corroborates.
        case docstringCorroboration

        /// B3 — a member of shape `(Int) -> Range<Int>`: give me a part index,
        /// get the slice of the whole it covers. That signature is a *partition*,
        /// and essentially nothing else has it by accident, so it carries a
        /// primary-evidence weight (+40).
        ///
        /// Deliberately a **signature** signal rather than a name one. The
        /// road-test's type calls this `byteRange(ofChunk:)`, but another author
        /// writes `slice(at:)`, and a template keyed on vocabulary would find one
        /// and miss the other — which is the mistake the effect lattice made when
        /// it graded `createRequest` by its prefix.
        case indexToRangeSignature

        /// B3 — a member of shape `(Int) -> Double` over the same index domain as
        /// an `indexToRangeSignature` member: a progress fraction. Corroborating
        /// evidence (+20), and the place the real bugs live — an empty whole whose
        /// progress never reaches 1.0 is a bar that hangs forever.
        case progressFractionSignature

        /// B3 — `(T, T) -> Bool` with **both operands positional**: a comparator,
        /// the thing you hand to `sorted(by:)`. It owes a *strict weak ordering*,
        /// which is not a stylistic nicety — a comparator that is not one can crash
        /// `sorted(by:)`, and no example test tells you which triple broke it (+40).
        ///
        /// The positional-operand requirement is what separates a comparator from a
        /// binary *predicate* of the same shape: `isImmediateChild(_ path:, of:)`
        /// is also `(String, String) -> Bool`, but its second operand carries a
        /// distinguished role. In Swift the argument label is part of the signature,
        /// so this remains a signature test rather than a name test.
        case comparatorSignature

        /// B3 — a `Bool`-returning function that is not a comparator: a predicate.
        /// Weak evidence (+20) *on purpose* — see `PredicateTemplate`, which is the
        /// one role in this catalogue that carries **no free law**.
        case predicateSignature

        /// B3 — two void-returning mutators on one type whose names are a
        /// direction pair (`navigateToFolder` / `navigateUp`): a state machine with
        /// an inverse. It owes `up ∘ down == id` plus an invariant that survives any
        /// action sequence (+35).
        case inverseMutatorPair

        /// A unary `(T) -> T` whose name is an involution verb (`reversed`,
        /// `negated`, `inverted`, `transposed`, …): applying it twice returns the
        /// original, so it owes `f(f(x)) == x`. The name is the load-bearing
        /// signal (+40) — required to fire — paired with the `(T) -> T`
        /// type-symmetry shape. Distinct from idempotence (`f(f(x)) == f(x)`),
        /// which is exactly why these names are vetoed FROM idempotence.
        case involutionSignature

        /// An in-place **reorder-partition**: a `mutating` method named like a
        /// partition (`partition`, `stablePartition`) that takes a predicate
        /// `(Element) -> Bool` and returns the pivot index. Distinct from the
        /// *tiling* partition (`partitionSignature` / `indexToRangeSignature`,
        /// whose parts reassemble a whole): this one rearranges the elements
        /// around the pivot so the predicate splits them, and owes a two-sided
        /// split + permutation law. Name-gated to avoid flooding on every
        /// mutating method that happens to take a closure.
        case reorderPartitionSignature

        /// A named **equivalence relation** — a `(T, T) -> Bool` (or instance
        /// `(self, T) -> Bool`) method named like an equality (`equals(to:)`,
        /// `isEqual(to:)`, `isEquivalent(to:)`, `isEqualSet(to:)`) over two
        /// operands of the SAME type. Owes reflexivity + symmetry + transitivity,
        /// the `==` analog of the comparator's strict weak ordering — laws an
        /// example test cannot make (they quantify over pairs and triples).
        /// Name-gated so it never fires on an arbitrary `Bool`-returning binary
        /// method (that is the weaker predicate). Operators are excluded — `==`
        /// is `Equatable`'s and the kit already runs its law.
        case equivalenceRelationSignature

    /// Rationale relocated to `docs/design/signal-kind-rationales.md` on 2026-08-09,
    /// when adding `subjectNotVisibleToTests` took this file past its 400-line cap.
    /// Relocate, do not trim — every comment here records a measurement.
        /// The subject is `private`/`fileprivate`, or sits inside a type that is — so **no test
    /// can name it**, whatever generator exists for its carrier.
    ///
    /// Score-neutral by construction (`weight: 0`). This is not a judgement about whether the
    /// law is true; §2 of `docs/measurements/roadtest-self-dogfood-2026-08-08.md` argues the
    /// law is usually right and the remedy is to LIFT it to the nearest reachable caller, not
    /// to widen the helper's access. Demoting the row would suppress the advice.
    ///
    /// **It exists so `StructuralBlocker` can see what the caveat already says.** `discover`
    /// has emitted *"NO TEST CAN RUN THIS LAW AS WRITTEN"* on these rows since the caveat
    /// post-processing landed — as PROSE, which nothing downstream can key on. `verify` then
    /// built the stub anyway and reported `cannot find 'X' in scope`, filed as `build-failed`:
    /// an instrument-failure bucket for a fact the tool knew before it started.
    /// Measured on `SwiftInferCore` (§9.2): `NonDeterministicAPIs.matches(_:)`.
    ///
    /// **Two of the four restrictions only.** `.internalOrSPI` is genuinely reached by
    /// `@testable`, and blocking it would suppress rows that verify today. `.nestedLocal` is
    /// also unreachable but is left out until measured, on the same conservative footing.
    case subjectNotVisibleToTests

    case declaredIdempotentEffect

        // Negative (non-veto)
        case sideEffectPenalty
        case generatorQualityPenalty
        case asymmetricAssertion
        case antiCommutativityNaming
        case partialFunction
        /// B24 — fires on an associativity / commutativity candidate that
        /// matched only on the bare `(T, T) -> T` type shape, with nothing to
        /// corroborate that this particular operation is a genuine monoid /
        /// commutative op: no curated / vocabulary name, no reduce-fold usage,
        /// and (for associativity) not a concatenation-family name. The shape is
        /// necessary but not sufficient — a correct `backoffDelay` / `weighted` /
        /// `scaleQuantity` matches it and need not be associative or commutative,
        /// so a shape-only proposal cries wolf. Weight `-20` drops Score 30 → 10
        /// (below the Possible floor of 20), suppressing the shape-only candidate;
        /// any real corroboration keeps the counter from firing at all.
        case unsupportedAlgebraicShape

        /// This function **calls** something declared retry-hostile, so
        /// `EffectResolver` inferred `nonIdempotent` / `externallyIdempotent`
        /// upward from its body. Opt-in (`--resolve-effects`); never fires on a
        /// default-path run.
        ///
        /// **−45, a demotion, where the same effect DECLARED on the function is a
        /// full veto** — and the split is the same directness axis `KitEvidence`
        /// uses, applied one layer out. A declaration denies *this law about this
        /// function*; an inference says *something this function calls is
        /// retry-hostile*, which is one step removed from the law's own subject.
        /// The template's law is over **return values**, and a function may call a
        /// side-effecting callee and still return the same value for the same
        /// input — so this is evidence, not refutation, and vetoing on it would
        /// suppress true laws.
        ///
        /// The magnitude is borrowed from `KitEvidence`'s −45 deliberately, and it
        /// lands where it should: a shape-only candidate (35) drops to −10 and
        /// disappears, while one carrying a curated verb or an author's own
        /// `@Idempotent` (75) lands at 30 and stays visible as `Possible` with the
        /// reason attached. The weak ones go; the corroborated ones are demoted,
        /// not silenced.
        case inferredRetryHostileCallee
        /// A `comparator` candidate matched on the `(T, T) -> Bool` **shape alone**, with
        /// no ordering name to corroborate that the relation is meant to *order* its
        /// operands. Measured 11 of 22 false on this repo, three already shipping at
        /// `Likely`; the sibling `equivalence-relation` template makes the weaker claim and
        /// was already name-gated. Full rationale: `docs/design/signal-kind-rationales.md`.
        case unsupportedComparatorShape
        /// A round-trip pair that is `T -> T` × `T -> T` with **nothing but the shape** —
        /// no curated name, no docstring, no `@Discoverable` group, no canonical inverse.
        /// Measured 432 of 438 on this repo, and every one sampled was false. The counter is
        /// not "same type is suspicious" but "same type AND nobody has said otherwise", and
        /// four channels can vouch. Full rationale: `docs/design/signal-kind-rationales.md`.
        case endomorphismRoundTripPair
        /// V1.4.3 — fires on candidates whose parameter type is a curated
        /// IEEE 754 floating-point-storage type (Float / Double / Float16 /
        /// Float32 / Float64 / Float80 / CGFloat / Complex / Decimal). Emitted
        /// by associativity / commutativity / inverse-pair templates with
        /// weight `-10` (PRD §17.3 step-2 magnitude). Drops Score 30 →
        /// Score 20 (Possible-tier floor) so the suggestion stays surfaced
        /// under `--include-possible` and the explainability block can point
        /// users at PropertyLawKit's `checkFloatingPointPropertyLaws` (kit-
        /// supported types) or document the cycle-2-deferred approximate-
        /// equality template arm (non-kit-supported types). Identity-element
        /// is intentionally exempt — exact identity on FP is reliably true
        /// (`x + 0.0 == x` modulo NaN).
        case floatingPointStorage
        /// A `RoundTripTemplate` pair whose two halves live on **different** types.
        /// Weight `-25`, scored-then-filtered. Full rationale, including the 673-hit
        /// swift-algorithms measurement that motivated it:
        /// `docs/design/signal-kind-rationales.md`.
        case crossTypeRoundTripPair
        /// V1.10.1 — fires on `IdempotenceTemplate` candidates whose first
        /// parameter argument label is in a curated direction-label set
        /// (`{after, before, next, prev, previous, advance, succ, pred,
        /// successor, predecessor}`). Emitted with weight `-15` — drops
        /// Score 30 → Score 15 (Suppressed tier, < 20) so Collection-
        /// protocol-style `(T) -> T` increment / decrement ops are filtered
        /// from `--include-possible` output. Curated-verb matches override
        /// (`normalize` etc. produce +40, net +55 → Likely tier preserved).
        ///
        /// **Cycle-6 motivation.** The cycle-6 single-runner triage (50
        /// decisions on the 349-surface) showed idempotence acceptance at
        /// 0/10 = 0%; all 10 rejected idempotence claims were directional
        /// `(T) -> T` ops. Per-decision rationale in
        /// `git show 8d5281b:docs/calibration-cycle-6-data/triage-notes.md`.
        /// The counter-signal closes the dominant 5-of-10 sub-pattern
        /// (direction-labeled args); the remaining 3-of-10 domain-mismatch
        /// sub-pattern (HashTable scale-vs-capacity) is a cycle-8 concern.
        case directionLabel
        /// V1.18.A — fires when the candidate's containing-type carrier
        /// resolves via `CarrierKindResolver` to `.referenceType` (i.e.
        /// `TypeDecl.kind == .class || .actor`). Emitted with weight `-10`
        /// — drops Score 30 → 20 (Possible-tier floor) so reference-type
        /// candidates still earn `--include-possible` surface but are
        /// demoted out of the Likely tier. Algebraic and round-trip
        /// properties are *aliasing-sensitive* on reference types: shared
        /// state through stored references means `var copy = x; copy.op();
        /// x == before(x)` doesn't hold the way it does on value types.
        ///
        /// **Cycle-15 motivation.** Carried forward four cycles
        /// (post-v1.13 priority #5 → post-v1.16 #3 → cycle-14 priority #3)
        /// as a small-projected-effect precision tweak. The v1.18 plan
        /// reframes this as the *necessary structural precondition* for
        /// the workstream-B mutating-method lift (v1.19). See
        /// `git show a585284:'docs/v1.18 Calibration Plan.md'` workstream A.
        case referenceTypeCarrier
        /// The carrier is a value type all the way down (`CarrierKindResolver`
        /// `.valueSemantic`), so the algebraic property is well-defined under
        /// aliasing. `+5`, deliberately smaller than `referenceTypeCarrier`'s `-10`.
        /// Full rationale, including why mixed carriers stay silent:
        /// `docs/design/signal-kind-rationales.md`.
        case valueSemanticCarrier
        /// V1.19.B — fires on suggestions emitted against a
        /// `LiftedTransformation` (a mutating method exposed in its
        /// pure-shadow `(T) -> T` form). Emitted with weight `+10`
        /// per the v1.19 plan open decision #5 lean — modest positive
        /// rewarding the structural soundness check that admitting the
        /// lift requires (strict admission gate filters most noise).
        ///
        /// **Decoupled from `valueSemanticCarrier`.** The `+5`
        /// `valueSemanticCarrier` signal also fires (always — it's the
        /// admission gate); the two contribute independently. A lifted
        /// suggestion's score baseline is therefore the non-lifted
        /// template's baseline + 5 (carrier) + 10 (lift admission), so
        /// the canonical Strong-tier baseline `30 + 40 + 5 + 10 = 85`
        /// for the new `CompositionTemplate` matches the v1.18-plan
        /// suggestion-rendering specification.
        case liftedFromMutation
        /// V1.22.C — fires on `IdempotenceTemplate.suggest(for:)` when
        /// the function name is in `FixedPointNames.curated` — names
        /// like `dedupe` / `simplify` / `clamp` / `truncate` /
        /// `standardize` that signal "transform input into a canonical
        /// form whose application is idempotent" but aren't in the
        /// V1.4.1 `IdempotenceTemplate.curatedVerbs` set. Emitted at
        /// `+10` weight per the v1.22 plan §"Workstream A" lean —
        /// modest recall-positive boost (smaller than curatedVerbs's
        /// `+40` because fixed-point names are lower-confidence
        /// idempotence indicators; clamp/truncate can be parameterized
        /// non-idempotently).
        ///
        /// **First recall-positive signal in the post-V1.4.3 era.** All
        /// prior cycles (V1.4.3 onward) shipped suppression-only
        /// mechanisms; V1.22.C is the first cycle to introduce a
        /// positive signal class. Mechanism class 14 in the cycle-19
        /// taxonomy.
        case fixedPointName

        /// V1.66 — `swift-infer verify` ran the synthesized property and
        /// it held across both the default and edge-case-biased passes
        /// (`VerifyEvidenceOutcome.measuredBothPass`). A heavy positive
        /// signal: execution evidence outranks any single heuristic
        /// signal. Applied by `VerifyEvidenceScoring` as a post-pass,
        /// after the persisted `verify-evidence.json` is loaded.
        case verifyBothPass

        // Veto (collapses score to suppressed)
        case nonDeterministicBody
        case nonEquatableOutput
        /// V1.66 — `swift-infer verify` ran the synthesized property and
        /// it failed on the default pass (`measuredDefaultFails`): the
        /// property is disproven by an executed counterexample. Full
        /// veto — unlike the heuristic vetoes, this is not inference but
        /// a measured falsification, so a disproven suggestion is
        /// genuinely wrong, not merely low-confidence. v1.66 overturns
        /// the cycle-61/62 "defaultFails does not demote" decision on exactly
        /// this ground — `git show 31a347a:docs/calibration-cycle-63-findings.md`.
        case verifyDisproven

        /// v1.149 — persisted verify evidence exists for this pick but was measured against
        /// a DIFFERENT body, so it is not applied in either direction. Weight 0: this is a
        /// statement about the evidence, not about the law. Rationale in
        /// `docs/design/signal-kind-rationales.md`.
        case verifyEvidenceStale
        /// The kit measured this carrier's `==` to be broken, so any law
        /// stated with it cannot be checked. See `docs/design/signal-kind-rationales.md`
        /// — the rationale is long and the file is at its cap.
        case kitEqualityOracleRefuted
        /// V1.5.1 — fires when the candidate's primary type already
        /// conforms to a protocol whose published laws cover the
        /// `KnownProperty` the template would emit (looked up via
        /// `ProtocolCoverageMap.covers(_:_:)`). The kit's
        /// `check<Protocol>PropertyLaws` is authoritative when a textual
        /// conformance match exists, so the suggestion is genuinely
        /// redundant — full veto rather than a heavy counter-signal.
        /// Calibration record preserved (the suggestion still scores;
        /// it just lands in Suppressed and gets filtered) so cycle-3
        /// metrics can introspect "how many suggestions did
        /// `: AdditiveArithmetic` suppress?". Detail names the matching
        /// conformance + the kit check, e.g. `"Property already covered
        /// by conformance to 'AdditiveArithmetic' — checked by
        /// PropertyLawKit's checkAdditiveArithmeticPropertyLaws"`.
        case protocolCoveredProperty
        /// B29 — fires when a set-combination commutativity suggestion
        /// (`union` / `intersection` / …) lands on an order-sensitive carrier
        /// (`OrderedSet`, `Array`, …), whose `==` compares element order. The
        /// semilattice commutativity law is FALSE under that `==` — `a.union(b)`
        /// and `b.union(a)` differ in order — and true only under an
        /// order-insensitive comparison such as `isEqualSet`. So the suggestion
        /// is genuinely wrong, not merely low-confidence: full veto. The curated
        /// `OrderSensitiveCarrierNames` denylist stands in for structural
        /// order-sensitivity detection pre-SemanticIndex.
        case orderSensitiveCarrier
        /// A `differential-equivalence` pair whose variant only **elides a precondition**
        /// (`load`/`unsafeLoad`) rather than being a second implementation. Vetoed on
        /// **unrefutability**, not falsity: where the precondition holds the two agree
        /// trivially, and where it does not the variant traps — and a trap is not a
        /// refutation. Measured zero true positives on every corpus tried; `stdlib` produced
        /// 57 Likely-tier claims, all of this class. Scored-then-filtered so `metrics` can
        /// still count it. Full rationale: `docs/design/signal-kind-rationales.md`.
        case preconditionElidingVariant
        /// A sequence-view law on a carrier whose `==` already IS that comparison, so it
        /// restates its own result expression. Penalty not veto — see `EqualityBodyShape`.
        case tautologicalEqualityBody

        /// The returned expression **builds around its input** rather than projecting out
        /// of it, so `f(f(x))` wraps twice and the idempotence law is false, not merely
        /// unlikely — a full veto. Measured 24% false-law rate; reads the RETURN expression
        /// and nothing else. Rationale in `docs/design/signal-kind-rationales.md`.
        case returnExtendsInput

        /// The author declared the **opposite** — `@NonIdempotent`, or
        /// `@ExternallyIdempotent(by:)`, in either spelling. Full veto.
        ///
        /// **Why veto where measured evidence only demotes.** `KitEvidence` refutes
        /// a *prerequisite* at −45 (leaving the law worth showing beside the warning);
        /// this denies *this law, about this function*, typed by the reader — restating
        /// it back is noise. `externallyIdempotent` vetoes for a sharper reason: it
        /// asserts idempotence ONLY through a caller-supplied dedup key, so the
        /// unconditional `f(f(x)) == f(x)` this template emits is *false* as written.
        /// (`observational` and `pure` are NOT here — neither implies non-idempotence.)
        case declaredNonIdempotentEffect

        /// V-ReplayM1 — the author's `@ExternallyIdempotent(by:)` claim; the positive
        /// mirror of `declaredNonIdempotentEffect`. The strongest replay signal.
        case replayExternallyIdempotentAnnotation

        /// V-ReplayM1 — an `IdempotencyKey` parameter: a keyed handler, even unannotated.
        case replayIdempotencyKeyParameter

        /// V-ReplayM2/M5 — a dedup gate in the body (early-return / fetch-then-insert /
        /// state-flag / guard-form): Branch C's structural signal.
        case replayDedupGate

        /// V-ReplayM6 — the body builds an `IdempotencyKey(…)`; property = built value stable.
        case replayKeyBuilder

        /// V-ReplayM10 — the body calls an idempotent-write primitive (`upsert`, …): idempotent by guarantee.
        case replayIdempotentWrite
    }
}
