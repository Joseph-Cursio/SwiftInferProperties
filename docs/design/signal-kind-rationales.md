# Signal-kind rationales — the overflow file

> **Status:** `shipped` · **As of:** 2026-08-04


`Signal.Kind` is one enum, and Swift will not let its cases be split across files, so
`Sources/SwiftInferCore/Signal+Kind.swift` grows monotonically with the catalogue and
hit its 400-line SwiftLint cap on 2026-08-01.

**This file is the pressure valve, and it is deliberately narrow.** Only the three
longest rationales moved — they were 99 of the file's 327 doc lines between them. The
other 40 cases keep their reasoning inline, because this repo's standing norm is that
the rationale travels with the decision (`GeneratorRecipe.rationale` exists for exactly
that reason). Moving prose out is a cost, taken here only where the alternative was a
lint failure landing on somebody else's unrelated change.

**If you add a signal and the file will not fit, move the next-longest rationale here
rather than trimming a new one.** The doc comments that remain are load-bearing: every
one records a measurement or a corpus finding, and several are the only surviving record
of why a veto exists.

---

## `unsupportedComparatorShape`

Fires on a `comparator` candidate that matched on the `(T, T) -> Bool`
**shape alone**, with no ordering name to corroborate that this relation is
meant to *order* its operands.

The inconsistency this fixes was visible in the catalog: the sibling
`equivalence-relation` template, which makes the *weaker* claim, was already
name-gated. `comparator` asserted a strict weak ordering from shape alone.

Measured on this repo: of 22 shape matches, **11 were false** — and the three
already on the default surface (`areComplementary`, `isCanonicalInversePair`,
`initializerPairAdmissible`, all internal or public) were false at `Likely`, so
this was shipping rather than latent. Two failure modes, neither visible to a
shape test:

- **symmetric relations** — `sameType(_ lhs:, _ rhs:)` is
  `lhs.trimmed == rhs.trimmed`; `areComplementary`'s docstring says
  *"Order-insensitive"*. A **correct** implementation fails asymmetry.
- **role-carrying operands** — `matches(_ name:, _ stem:)` is positional but not
  interchangeable. The label test claims to catch this and does not; `_ x: T,
  _ y: T` has no labels. That hole is **not** closed by this signal.

Weight `-25` drops 40 → 15, below the `.possible` floor, so a shape-only
candidate is suppressed rather than downgraded. Any ordering name prevents it.

**A suppressed candidate earns NO law, not a weaker one** —
`PredicateTemplate.isPredicate` excludes anything matching `isComparator`, and
that gate reads the shape, which still matches. Whether these should become
predicates is a separate calibration decision.

---

## `endomorphismRoundTripPair`

Fires on a `round-trip` pair where **both halves are endomorphisms** —
`T -> T` paired with `T -> T` — and no inverse *name* corroborates them.

Two endomorphisms are not an inverse pair. A round-trip needs opposite
directions, `A -> B` against `B -> A`; same-type-both-sides is just two
functions over one type, and the `g(f(x)) == x` law is false for almost
every such couple. The bare type-symmetry signal cannot tell them apart,
which makes it combinatorial: every `(String) -> String` helper in a corpus
pairs with every other.

Measured as an outcome, per corpus, with a systematic sample read at each
step:

| corpus | round-trip before → after |
|---|---|
| SwiftInferProperties, private seeded | 438 → **92** |
| SwiftInferProperties, baseline | 53 → **1** |
| FoundationEssentials | 142 → **53**, keeping all 5 Strong + 5 Likely |

Every same-type pair sampled was false, on **both** corpora —
`sanitizeForFileName` × `stripGenericParameters` here;
`index(afterUnicodeScalar:)` × `index(afterRun:)` (both *after*) and
`deletingLastPathComponent()` × `deletingPathExtension()` (both *deleting*) on
Foundation, 14 of 14 in the dropped sample. Every surviving Foundation
Strong/Likely claim was real:
`Date(timeIntervalSinceReferenceDate: t).timeIntervalSinceReferenceDate == t`
and `Locale(identifier: s).identifier == s`, where canonicalisation is exactly
the bug the law would find. So this raises precision on the corpus where
round-trip already worked, not only on the one where it did not.

*Method note.* A first pass tabulated same-type-vs-opposite-type shares by
regex over rendered signatures and got them wrong, reading `() -> TimeInterval`
as opposite-typed. A zero-parameter instance method's domain is its
**receiver** — `FunctionPairing.transformationDomain`, which this signal uses
and that script did not. The counts above are outcomes of the shipped code
instead, which cannot drift from it.

**Name evidence overrides it.** A base64 `encode: String -> String` /
`decode: String -> String` IS a same-type round-trip, and the curated
inverse-name pair earns +40 on its own — so this fires only when *nothing
but the shape* matched, mirroring `unsupportedAlgebraicShape`.

---

## `preconditionElidingVariant`

Fires on a `differential-equivalence` pair whose variant only
**elides a precondition** (`load`/`unsafeLoad`,
`append`/`uncheckedAppend`) rather than being a second
implementation of the same computation.

Vetoed on **unrefutability**, not falsity. The law is true — that is
the contract — but nothing can execute it: where the precondition
holds the two agree trivially, because the reference is normally the
checked wrapper around the variant or both bottom out in the same
builtin; where it does not, the variant traps or is UB, and a trap is
not a refutation. So no generator can reject any plausible
implementation, which is what "score refutability, not suggestion
count" forbids shipping.

Measured, and the reason this is a veto rather than a penalty: the
subclass has produced **zero** true positives on every corpus tried.
9 `unchecked*` pairs on swift-collections were rejected only
incidentally (`mutating`/`Void` on unsafe-handle carriers), and
`stdlib/public/core` — where the same shape returns a value on a
resolvable carrier, so the incidental gates do not fire — produced
**57 Likely-tier claims, all of this class** (32 ×
`loadUnaligned`/`unsafeLoadUnaligned`, 24 × `load`/`unsafeLoad`,
1 × `bitCast`/`unsafeBitCast`) and none of the law the family exists
for. The incidental gates were hiding a wrong marker class, which is
the "a refuter that fires first hides every refuter behind it"
hazard read from the other side.

Scored-then-filtered rather than dropped at the pairing stage, on the
`protocolCoveredProperty` precedent, so `metrics` can still answer
"how many pairs did this veto suppress?".

## `kitEqualityOracleRefuted`

**Fires when PropertyLawKit has *measured* the carrier's `==` to be broken, and the
suggestion's law is stated with it.**

Almost every property `discover` proposes is an `==` between two expressions —
`f(f(x)) == f(x)`, `a • b == b • a`, `decode(encode(x)) == x`. All of them use the carrier's
`==` as the oracle. When the kit has executed the Equatable/Hashable laws and one of them
**failed at `Strict` tier**, those proposals are not so much wrong as **unusable**: they
will be checked with a comparison that does not work, and a green run means nothing.

**Why this signal exists at all.** Before it, the toolchain was one-way — `discover`
proposed, a human wrote tests, the kit ran them, and nothing came back. The kit's verdicts
are the only *executed* evidence anywhere in the pipeline and they influenced no later
inference. That is the same quarantine as two other findings from 2026-08-01: the curated
catalog contributes zero to scoring, and `ProtocolCoverageMap` vetoes a template on the
*assumption* the kit covers a law without checking whether the kit ever ran.

**Why it demotes rather than vetoes.** The law may be perfectly true and worth stating; what
is broken is the ability to check it. The useful output is a diagnosis with a prerequisite —
*fix `==`, then these become checkable* — not silence. `ProtocolCoverageMap`'s full veto is
the wrong precedent: it fires on **coverage**, this fires on **refutation**, and a reader
whose equality is broken needs to be told, not to be shown an empty run.

**Three exclusions, each measured rather than argued.**

- **`Heuristic`-tier failures do not fire it.** `fixtures/toolchain-coverage` measured a
  *correct* type failing `Hashable.distribution` purely because the generator had been
  narrowed to hunt a collision bug — the projection bug needs collisions to be visible and
  the distribution law needs their absence, and one generator cannot serve both. Demoting on
  that basis would punish a reader for aiming their generator well.
- **`.expectedViolation` does not fire it.** The author used the kit's own
  `.intentionalViolation` suppression to say the failure is the documented design.
- **`Comparable.totalOrder` is not in the trigger set.** A broken `<` invalidates *ordering*
  laws, not equality-shaped ones. Conflating them would suppress far more than the evidence
  supports.

The witness is `fixtures/toolchain-coverage`: a projecting `==` beside a synthesized
`hash(into:)`, rejected by the kit at `Strict` in 17 trials, while all four Equatable laws
pass — because a projection *is* an equivalence relation. A tool that kept proposing
`==`-shaped laws for that type after the kit said so would be ignoring the best evidence it
has.

## `crossTypeRoundTripPair`

Moved out of `Signal+Kind.swift` on 2026-08-04, when three signals for the
idempotency-vocabulary work took the file past its 400-line cap. Per the standing
rule in `CLAUDE.md`: when a new signal will not fit, relocate the next-longest
*existing* rationale rather than trimming the new one. This was the longest that
was not itself new.

V1.4.3b — fires on `RoundTripTemplate` pairs whose forward and reverse functions
have **different** `containingTypeName` values (excluding the both-nil
free-function case, which is a valid module-scope round-trip). Emitted with
weight `-25` — drops Score 30 → Score 5 (well into Suppressed) so cross-type
pairs are filtered from both default-tier and `--include-possible` output.
Calibration record preserved (the suggestion still scores; it just lands in
Suppressed and gets filtered) so future cycles can introspect "how many
cross-type pairs did this rule reject."

Empirical motivation (V1.4.2 cycle-1 baseline): swift-algorithms surfaced 673
round-trip Possible-tier hits, the vast majority signature-only matches across
distinct `Index` member types (`AdjacentPairsCollection.Index` /
`Chain2Sequence.Index` etc.). SemanticIndex would catch this via type
resolution; this rule is a cheap pre-SemanticIndex approximation using the
textual `containingTypeName` field already on `FunctionSummary`.

## `valueSemanticCarrier`

Moved out of `Signal+Kind.swift` on 2026-08-04, the second relocation that day —
four signals for the idempotency-vocabulary and false-positive work took the file
past its 400-line cap twice. Per the standing rule: relocate the next-longest
*existing* rationale rather than trim a new one.

V1.18.A — fires when the candidate's containing-type carrier resolves via
`CarrierKindResolver` to `.valueSemantic` (`kind == .struct || .enum` AND every
stored member is recursively value-typed per the curated allow-list +
same-corpus `TypeDecl` lookup, depth-bounded 3 levels). Emitted with weight `+5`
— small positive bump that confirms the algebraic property's structural
soundness. Magnitude is intentionally smaller than `referenceTypeCarrier`'s
`-10` because false positives on reference types are sharper bugs than missed
value-semantic positives.

Mixed carriers (struct with a class-typed or closure-typed stored property) emit
no signal — conservative; the bug shapes in `docs/archive/valuesemantic-build-plan.md`
§2.1 (broken CoW / closure-captured state) are bugs that look value-semantic
structurally and would falsely score positive otherwise.


## `declaredIdempotentEffect`

*Relocated from `Signal+Kind.swift` on 2026-08-09, when adding `subjectNotVisibleToTests` took that file past its 400-line cap. Relocated rather than trimmed, per the rule this document exists to serve.*

The author *declared* idempotence, in SwiftIdempotency's vocabulary —
    `@Idempotent`, or the dependency-free `/// @lint.effect idempotent`.

    **+15, and the weight is the whole finding.** It first shipped at +40,
    on the strength of `SwiftEffectInference.Effect`'s doc for that tier:
    *"`f(f(x))` is semantically equivalent to `f(x)`"* — this template's law
    verbatim. Dogfooding on 2026-08-04 sent me to the **owning** package,
    where `@Idempotent` is defined as *"re-invocation with the same
    arguments produces the same observable result and the same external
    effects"*. That is **re-invocation stability**, not composition: `f(x)`
    twice, never `f` fed its own output. SEI's paraphrase asserts a
    strictly stronger property than the macro it paraphrases promises, and
    +40 was keyed to the paraphrase.

    The gap is not academic. `quoted(_:)` in this repo is pure and
    deterministic, so it satisfies the owner's definition and could be
    truthfully annotated — and `verify` refutes its composition law at
    **trial 0**. At +40 (35 → 75) that false law would have surfaced at
    `Strong` by default; at +15 (35 → 50) it reaches `Likely`, which is
    where an unverified claim of the adjacent property belongs. Parity with
    `docstringCorroboration` is the right anchor: an annotation is more
    *deliberate* than prose but says less than it appears to.

    **Corroborate-only, by construction** — the template's `appliesTo` gate
    is the type-symmetry shape, so this can only raise a candidate the
    shape already matched, never surface a law from an annotation alone.

---

## `returnExtendsInput`

Moved here 2026-08-10 to make room for `verifyEvidenceStale`, per this file's own rule.
It is the longest rationale in `Signal+Kind.swift` and the one this file exists to hold;
none of it is trimmed.

The function's returned expression **builds around its input** rather than projecting out
of it — wraps it in delimiters, concatenates onto it, extends a path. `f(f(x))` wraps
twice, so the idempotence law is **false**, not merely unlikely: full veto, on the same
ground `orderSensitiveCarrier` gives.

Measured: a 2026-08-04 survey ran every `idempotence` candidate on this repo — **55
executed, 13 refuted, a 24% false-law rate**, every refutation at the score-35 shape-only
floor. A prototype frozen to disk *before* the verdicts scored **5/5** on the rows that
ran, keyed on the return expression alone.

**It reads the RETURN expression and nothing else**, and that is the finding rather than
an implementation detail. A body-wide scan calls `quoted(_:)` a normalizer — it runs
`replacingOccurrences` and *then* wraps — and calls a dedup an extender, because `.append`
appears while it filters. Both readings are wrong, and both come from looking in the wrong
place.

Deliberately does NOT cover **domain transfer**: `T -> T` where the output is a different
*kind* of thing (a hash, a rendered name), so `f(f(x))` is meaningless though it
type-checks. That was 6 of the 13 and is exactly what the `_description` and
capacity-from-scale vetoes have been chasing by NAME for several cycles. It is not
characterised well enough to veto on, and a veto that fires on a guess suppresses true
laws. See also `docs/measurements/domain-transfer-signal` — the candidate rule was scored
and declined at 4/12 precision.

---

## `verifyEvidenceStale`

Persisted verify evidence exists for a pick, but the subject's body has changed since the
measurement was taken (or the evidence predates fingerprinting, or this run could not
fingerprint the subject). The outcome is **not applied in either direction** and the row
falls back to its static tier carrying this caveat.

**Why the signal is weight 0.** It says something about the *evidence*, not about the law.
A stale `bothPass` is not counter-evidence — the property may well still hold — so
demoting would assert more than is known. The correct effect is simply that an
unvalidatable measurement stops counting, which is what withholding the `+50` already
does; the signal exists to make that visible rather than to move the score.

**Why it applies to `defaultFails` too.** The premise is *evidence taken against a
different body is not evidence about this body*. Honouring that for promotions but not
vetoes would be incoherent — and a stale refutation is exactly as likely to be about
deleted code as a stale pass. The caveat still names the refutation, so the reader keeps
the warning even though the score effect is withdrawn.

**Why a missing fingerprint counts as stale.** Records written before v1.149 carry no
fingerprint, so nothing can establish what they measured. Treating "unknown" as "valid"
would preserve the defect on precisely the records most likely to be stale — the 349 in
this repo's own store at the time of the fix were spread over three days, with all 28 of
`SwiftInferCLI`'s promoted rows five days old. The cost is that those records stop
promoting until re-verified, and that cost is the point.

Road test §10.2 (`docs/measurements/roadtest-self-dogfood-2026-08-08.md`) is the
measurement that produced it: because `SuggestionIdentity` is `(template, canonical
signature)` and deliberately blind to the body, a body-only edit that falsified the law
left the identity unchanged and `discover` reported the now-false law as `Verified`.

## `subjectNotVisibleToTests`

Relocated 2026-08-18, when `impureSubject` took `Signal+Kind.swift` past its 400-line
cap. It was the longest remaining rationale in that file.

The subject is `private`/`fileprivate`, or sits inside a type that is — so **no test
can name it**, whatever generator exists for its carrier.

Score-neutral by construction (`weight: 0`). This is not a judgement about whether the
law is true; §2 of `docs/measurements/roadtest-self-dogfood-2026-08-08.md` argues the
law is usually right and the remedy is to LIFT it to the nearest reachable caller, not
to widen the helper's access. Demoting the row would suppress the advice.

**It exists so `StructuralBlocker` can see what the caveat already says.** `discover`
has emitted *"NO TEST CAN RUN THIS LAW AS WRITTEN"* on these rows since the caveat
post-processing landed — as PROSE, which nothing downstream can key on. `verify` then
built the stub anyway and reported `cannot find 'X' in scope`, filed as `build-failed`:
an instrument-failure bucket for a fact the tool knew before it started.
Measured on `SwiftInferCore` (§9.2): `NonDeterministicAPIs.matches(_:)`.

**Two of the four restrictions only.** `.internalOrSPI` is genuinely reached by
`@testable`, and blocking it would suppress rows that verify today. `.nestedLocal` is
also unreachable but is left out until measured, on the same conservative footing.
