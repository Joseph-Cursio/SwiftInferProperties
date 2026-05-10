# Cycle-17 Triage Rubric

Methodology document for v1.20's empirical Possible-tier sampling pass on the post-v1.19 335-surface. Defines accept/reject/unknown criteria per template, what counts as evidence in single-runner triage, and how the rubric handles edge cases.

**Scope:** v1.20 / cycle 17 — the **third empirical-only cycle** in the calibration loop (after cycle 6 = v1.9 on the 349-surface and cycle 14 = v1.17 on the 229-surface). Carries cycle-14's per-template criteria verbatim; adds a "Post-cycle-14 mechanism context" section documenting the suppression layers (cycles 15 + 16) a v1.19 survivor has cleared, plus new per-template sections for the **two new template families** introduced post-cycle-14: `dual-style-consistency` (V1.18.C) and `composition` (V1.19.C); and new per-sub-template sections for the **lifted-suggestion class** introduced by V1.19.B's mutating-method lift admission (`idempotence-lifted`, `identity-element-lifted`, `inverse-pair-lifted`).

**Companion to `docs/cycle-14-triage-rubric.md` and `docs/cycle-6-triage-rubric.md`, not a replacement.** The cycle-6 + cycle-14 rubrics stay unchanged for forensic comparability with their respective samples. Resolves v1.20 plan §"Open decisions" #5 in favor of (b): carry-forward verbatim with cycle-17 supplement.

## What we're measuring

Each triaged suggestion is a *claim* SwiftInfer makes — "this code looks like it satisfies a `<template-name>` property." The triage decision answers: **does the property actually hold?**

- **Accept** — yes, the property holds for the function(s) as written. A property test stub written from this suggestion would pass on plausible inputs. The user would ship it.
- **Reject** — no, the property doesn't hold. The functions are *related* but not in the way the template claims. A property test stub would fail or be misleading.
- **Unknown** — the rater can't determine the answer from public-API + commit-history evidence alone.

The §19 acceptance-rate target ("≥ 70% acceptance after 6 months of dogfooding") is computed as `accept / (accept + reject)` — `unknown` is excluded from the denominator.

## Single-runner triage caveat

This rubric documents what *one* rater can determine from public surfaces + git log. It deliberately excludes:

- **Running the code.** Triage decisions don't compile-and-execute the suggested property.
- **Internal implementation details.** Public APIs only — file paths, function signatures, doc comments, public type contracts.
- **Multi-rater consensus.** Single rater.
- **Domain expertise the rater lacks.**

When the evidence is genuinely ambiguous, the rubric mandates `unknown` — *not* a forced binary call.

## Post-cycle-14 mechanism context

The cycle-17 sample is drawn from the **v1.19 335-surface**, which has *expanded* from cycle 14's 229-surface (+106 = +46.3%) — the **first reversal of the descending trend** since the loop began. Three mechanism cycles ship between cycles 14 and 17:

- **Cycle 15 / v1.18 Workstream A** — Carrier-kind structural counter/positive signal. Score-only effect (+5 on value-semantic carriers, -10 on reference-type carriers); no surface-count change. Affects Idempotence + RoundTrip + InversePair + IdentityElement scoring.
- **Cycle 15 / v1.18 Workstream C** — Dual-style consistency template + DualStylePairing. **NEW template family** (class 11 in the mechanism-class taxonomy). +22 candidates at v1.19, all on OrderedCollections.
- **Cycle 16 / v1.19 Workstream B** — Mutating-method lift admission via `LiftedTransformation` + four template fan-out sites. **NEW candidate class** introducing 45 lifted suggestions at v1.19 (44 idempotence-lifted + 1 composition-lifted; `identity-element-lifted` and `inverse-pair-lifted` had zero surface).

The rater should know which gates each surviving candidate has already passed AND should be aware that **the new candidate classes have no cycle-14 baseline** — cycle-17 is their first measurement. Surviving false positives in the *existing* templates are by construction in *novel* failure modes (not direction-labeled, not domain-marker-labeled, not SetAlgebra-shaped, not reference-type-carriered).

This context **does not change the verdict thresholds** for cycle-14-baseline templates. The accept/reject criteria carry forward verbatim. New-template sections below define new criteria.

### Per-template suppression layers cleared at v1.19

**Round-trip** (156 v1.19 candidates) — four post-cycle-6 mechanism layers cleared (cycle-14 had three):

| Cycle | Release | Mechanism | Suppression weight | Suppression criterion |
|---|---|---|---:|---|
| 9 | V1.12.1 | direction-label counter | −15 | either pair-side's first-param label ∈ `DirectionLabels.curated` |
| 12 | V1.15.1 | domain-marker counter | −15 | both pair-sides' first-param label ∈ `DomainMarkerLabels.curated` |
| 13 | V1.16.1 | SetAlgebra-shape veto | −25 | both pair-sides have `(Self) -> Self` shape AND both names ∈ `SetAlgebraShape.binaryOps` |
| 15 | V1.18.A | reference-type carrier counter | −10 | either pair-side's containing type classifies as `.referenceType` |

**Idempotence** (88 v1.19 candidates: 44 non-lifted + 44 lifted) — four post-cycle-6 mechanism layers cleared (cycle-14 had three):

| Cycle | Release | Mechanism | Suppression weight | Suppression criterion |
|---|---|---|---:|---|
| 7 | V1.10.1 | direction-label counter | −15 | first-param label ∈ `DirectionLabels.curated` |
| 12 | V1.15.1 | domain-marker counter | −15 | first-param label ∈ `DomainMarkerLabels.curated` |
| 13 | V1.16.1 | SetAlgebra-shape veto | −25 | `(Self) -> Self` shape AND function name ∈ `SetAlgebraShape.binaryOps` |
| 15 | V1.18.A | reference-type carrier counter | −10 | containing type classifies as `.referenceType` |

**Inverse-pair** (4 v1.19 candidates: all non-lifted) — four post-cycle-6 mechanism layers cleared:

| Cycle | Release | Mechanism | Suppression weight | Suppression criterion |
|---|---|---|---:|---|
| 8 | V1.11.1 | direction-label counter | −10 | either pair-side's first-param label ∈ `DirectionLabels.curated` |
| 11 | V1.14.1 | SetAlgebra-shape veto | −25 | both sides `(Self) -> Self` AND both names ∈ `SetAlgebraShape.binaryOps` |
| 12 | V1.15.1 | domain-marker counter | −15 | both pair-sides' first-param label ∈ `DomainMarkerLabels.curated` |
| 15 | V1.18.A | reference-type carrier counter | −10 | either pair-side's containing type classifies as `.referenceType` |

**Identity-element** (1 v1.19 candidate; non-lifted) — one post-cycle-6 mechanism layer cleared:

| Cycle | Release | Mechanism | Suppression weight | Suppression criterion |
|---|---|---|---:|---|
| 15 | V1.18.A | reference-type carrier counter | −10 | containing type classifies as `.referenceType` |

**Monotonicity / commutativity / associativity** (29 / 17 / 17 v1.19 candidates) — **no new per-template mechanisms post-cycle-14.** The cycle-6/cycle-14 rubric verdict thresholds apply to v1.19 survivors without modification.

**Dual-style-consistency** (22 v1.19 candidates) — **NEW template family at V1.18.C**, no prior baseline. See "Per-template criteria" below.

**Idempotence-lifted** (44 v1.19 candidates) — **NEW sub-template at V1.19.B**, no prior baseline. Inherits non-lifted Idempotence's suppression layers (the lifted-suggest path runs the same `protocolCoverageVeto`, `setAlgebraShapeVeto`, `directionLabelCounterSignal`, `domainMarkerCounterSignal`, and `nonDeterministicVeto` against the original mutating summary). Strict admission gate (`isMutating && containingType != nil && carrierKind == .valueSemantic`) is the structural precondition.

**Composition** (1 v1.19 candidate) — **NEW template family at V1.19.C**, no prior baseline. Numeric-only by curated additive-monoid type gate.

**Identity-element-lifted** (0 v1.19 candidates) — surfaced no candidates on the four cycle-1..14 corpora; rubric included for completeness in case a future corpus surfaces one.

**Inverse-pair-lifted** (0 v1.19 candidates) — surfaced no candidates on the four cycle-1..14 corpora; rubric included for completeness.

### Curated suppression sets (for rationale-writing reference)

These are the curated sets the cycle-7–16 mechanisms consult. The rater shouldn't need to memorize them — they're listed here so a triage-notes citation can disambiguate why a candidate is *not* a duplicate of a prior-cycle suppression target:

- `DirectionLabels.curated` (V1.10.1, hoisted in V1.13): `{after, before, next, prev, previous, advance, succ, pred, successor, predecessor}`. Spatial-sequence iteration labels.
- `DomainMarkerLabels.curated` (V1.15.1): `{forScale, forCapacity, forBucketContents}`. Semantic-intent named-domain markers.
- `SetAlgebraShape.binaryOps` (V1.14.1, hoisted in V1.16.1): `{union, intersection, symmetricDifference, subtracting}`. SetAlgebra binary-op function names.
- `CarrierKindResolver` value-type allow-list (V1.18.A): stdlib value types — `Int`, `Double`, `String`, `Array`, `Dictionary`, `Set`, `Optional`, `Result`, `Range`, `Date`, `URL`, `UUID`, `Decimal`, `Duration`, `OrderedSet`, `Deque`, `Tuple`-syntax, etc.
- `Vocabulary.dualStyleNamePairs` curated rules (V1.18.C): three rule families — `X` ↔ `Xing` (`add`/`adding`, `append`/`appending`, `insert`/`inserting`), `X` ↔ `Xed` (`sort`/`sorted`, `reverse`/`reversed`, `normalize`/`normalized`), `formX` ↔ `X` (`formUnion`/`union`, `formIntersection`/`intersection`, `formSymmetricDifference`/`symmetricDifference`).
- `CompositionTemplate.curatedAdditiveTypes` (V1.19.C): stdlib `AdditiveArithmetic` conformers + `Decimal` + `Duration`.
- `CompositionTemplate.curatedVerbs` (V1.19.C): `{increment, add, accumulate, accrue, advance, step, extend, expand, shift, offset, bump, grow, augment, append, push, pop, deposit, withdraw}`. Additive-action verbs.
- `InverseLiftedPairing.curatedPairs` (V1.19.D): `{(add, remove), (insert, remove), (push, pop), (attach, detach), (link, unlink), (activate, deactivate), (subscribe, unsubscribe), (register, deregister), (enable, disable)}`. Curated state-mutation inverse pairs.
- `IdentityNames.curated` (V1.19.C; promoted to public): `{zero, empty, identity, none, default}`. Curated identity-element names.

### Cycle-14 → cycle-17 picks-status framing

Cycle-15 + cycle-16 findings have already documented Workstream A's per-corpus precision contribution (deferred to v1.20 empirical capture per `docs/calibration-cycle-15-findings.md`). Cycle 17 is **fresh stratified sampling**, not cycle-14 picks reuse (v1.20 plan §"Open decisions" #4). The rater should *not* attempt to re-triage cycle-14 picks; they'll appear in the cycle-17 findings writeup's "Cycle-14 picks status" rollup, which is methodology-comparable but not sample-overlapping.

## Per-template criteria

The following criteria for the **seven existing template classes** (round-trip, idempotence, commutativity, associativity, inverse-pair, monotonicity, identity-element) are carried forward verbatim from `docs/cycle-14-triage-rubric.md` (which itself carries forward from `docs/cycle-6-triage-rubric.md`). Edits would compromise cycle-6/cycle-14 ↔ cycle-17 rate-shift comparability. The new-template sections below extend the rubric for cycles 15 + 16 mechanism additions.

### Round-trip — `g(f(x)) == x` for all `x` in the function's effective domain

**Accept** when:
- Function names + signatures suggest the pair is by-design inverses (e.g., `encode` ↔ `decode`, `parse` ↔ `format`, curated inverse-pair list).
- The pair operates on the same `T` carrier; type signatures align (`(T) -> U` ↔ `(U) -> T`).
- Domain coverage: the suggestion is plausible without restricting `x`.
- No textual evidence of asymmetric postconditions.

**Reject** when:
- The pair is *related* but semantically not inverses.
- Functions have asymmetric domains.
- The "round-trip" is identity-on-the-codec only.

**Unknown** when:
- Function names are non-diagnostic.
- Internal logic determines whether the pair commutes (rater can't read it).
- Documentation is silent on round-trip intent.

### Idempotence — `f(f(x)) == f(x)` (non-lifted)

**Accept** when:
- Function name suggests idempotence (`normalize`, `canonicalize`, `dedupe`, `simplify`, `clamped`, `flattened`).
- Signature is single-arg `(T) -> T` and the doc comment / function purpose makes clear that applying twice yields the same result.
- Examples: `String.lowercased()`, `Array.sorted()`, `Set.union(_)`-on-itself.

**Reject** when:
- The function's purpose is to *change* state per call (counter increment, RNG step).
- Signature is `(T) -> T` but the operation is monotonic / accumulative.
- The function is *partially* idempotent (idempotent on some subdomain but not all of `T`).

**Unknown** when:
- The function name + signature don't disambiguate.
- Internal state determines the answer.

### Commutativity — `f(a, b) == f(b, a)`

**Accept** when:
- Standard math operators (`+`, `*`) on Numeric types — but should already be suppressed by V1.5.2 + V1.7.1.
- Set operations on SetAlgebra (`union`, `intersection`).
- Function name explicitly suggests symmetric semantics (`merge`, `combine`, `meet`, `join`).

**Reject** when:
- The op is naturally directional: `a - b ≠ b - a`, `a / b ≠ b / a`, `a.appending(b) ≠ b.appending(a)`.
- Function name suggests directionality (`from:to:`, `applyTo:`, `into:`).

**Unknown** when:
- Function name is ambiguous.

### Associativity — `(a · b) · c == a · (b · c)`

**Accept** when:
- Standard math operators on Numeric / set algebra.
- Function name suggests free-form combination (`merge`, `concatenate`).

**Reject** when:
- The operation is non-associative by design.

**Unknown** when:
- Function name + signature don't disambiguate.

### Inverse-pair — `f(g(x)) == x` AND `g(f(y)) == y` (non-lifted)

**Accept** when:
- Function-pair names are explicit additive-inverse-style.
- Strong type signal: `(T, T) -> T` ↔ `(T, T) -> T` with shared free variable.

**Reject** when:
- The pair is related but not inverses.

### Monotonicity — `a ≤ b ⇒ f(a) ≤ f(b)`

**Accept** when:
- Function takes a single Comparable input and returns Comparable; doc / name suggests order-preservation.
- Function is naturally a counting / sizing op.

**Reject** when:
- The function's purpose is to *invert* order.
- The output type is not comparable in a way that aligns with the input ordering.

### Identity-element — `f(x, ε) == x` AND/OR `f(ε, x) == x` (non-lifted)

**Accept** when:
- The op + element pair maps to a kit-published identity law not already suppressed.
- Function name + element suggest standard monoid identity.

**Reject** when:
- The op-name + element doesn't match any kit-published law and isn't textually a stdlib operator.

**Unknown** when:
- The user-defined op + element is novel to the rater.

## New per-template criteria (cycles 15 + 16 additions)

The following criteria are **new for cycle 17**; they have no cycle-6 or cycle-14 baseline. The acceptance rate measured on these picks is the *first* per-template rate for the new template family.

### Dual-style-consistency — `var c = a; c.<mut>(args); return c == a.<nonMut>(args)`

V1.18.C asserts that a mutating method's effect equals its non-mutating sibling's return value, where the pair is matched by one of three curated naming rules (`X`/`Xing`, `X`/`Xed`, `formX`/`X`) on the same containing type with matching parameter shape.

**Accept** when:
- The curated pair name describes a real dual-style sibling: the mutating method's documented effect is to apply the non-mutating sibling's transform in-place (e.g., `OrderedSet.formUnion(_:)` ↔ `OrderedSet.union(_:)` — `formUnion` mutates `self` to be `self.union(other)`).
- Both methods are documented as semantically equivalent modulo mutation/return-value style (the canonical Swift "form-prefix convention" pattern).
- Type signatures align: same parameter list, non-mutating returns the carrier type or `Self`.

**Reject** when:
- Name match without semantic correspondence — a developer reused one of the curated names for a non-paired purpose. Example: a `mutating func sort()` that sorts in-place + a `func sorted() -> Self` that returns sorted accept; but a `mutating func add(_:)` that *appends* + a `func adding(_:)` that *prepends* would reject (same name family, different semantics).
- The non-mutating sibling has a non-trivial post-condition the mutating version doesn't (e.g., one validates input, the other doesn't).
- One method is documented as deprecated relative to the other.

**Unknown** when:
- Public API has both methods but no doc comment establishes the equivalence claim.
- One method is internal (rater can read public signature only).

### Idempotence-lifted (V1.19.B no-param + x-curried)

V1.19.B asserts that a mutating method's lifted shadow form is idempotent. Two admissible shapes:

- **No-param mutator** lifted to `(T) -> T`: `op'(op'(s)) == op'(s)`. Examples: `Set.removeAll()` lifted is idempotent (calling `removeAll` twice equals once).
- **Param-matches-carrier mutator** lifted to `(T, T) -> T`: x-curried idempotence `op'(op'(s, x), x) == op'(s, x)`. Examples: `Set.formUnion(_:Self)` lifted is idempotent on the same `x` (canonical SetAlgebra idempotent-union).

**Accept** when:
- The underlying `mutating func` is documented or by-construction idempotent in its lifted form. `removeAll`, `clear`, `reset` no-param mutators are typical accepts. `formUnion(_:Self)` x-curried is a canonical accept (SetAlgebra law).
- The mutating method's effect is *terminal* (reaches a fixed-point after one call) rather than incremental (each call advances state).

**Reject** when:
- The mutating method is **stateful-incremental**: `Iterator.next()` advances state; calling twice ≠ calling once. **All `IteratorProtocol.next()` candidates predicted-reject** per the V1.20.A surface-counts analysis (20 of 20 Algorithms lifted-idempotence picks are Iterator-shaped).
- The mutating method is accumulative without the SetAlgebra-shape veto firing (e.g., a domain-specific `formAdd(_:)` that genuinely accumulates and is not idempotent on the same argument).
- The carrier passed the value-semantic admission gate but the operation has hidden side-effects via captured reference-typed properties (rater can read this only via documentation; otherwise → unknown).

**Unknown** when:
- Function name + signature don't disambiguate fixed-point vs incremental semantics.
- Doc comment is silent on the mutation's terminal-vs-incremental nature.

### Composition-lifted (V1.19.C)

V1.19.C asserts that two sequential calls to a mutating additive-action method equal one call with the combined argument:

```swift
var c1 = s; c1.<op>(by: a); c1.<op>(by: b)
var c2 = s; c2.<op>(by: a + b)
return c1 == c2
```

Numeric-only by curated additive-monoid type gate (param X ∈ `curatedAdditiveTypes`). Curated additive-action verbs apply at +40.

**Accept** when:
- The mutating method is genuinely additive on its parameter: `Counter.increment(by: 5).increment(by: 3) == Counter.increment(by: 8)`.
- The mutating method is named per `curatedVerbs` (`increment`, `add`, `accumulate`, etc.) AND has no clamping / saturation / non-linear transform.
- Doc comment confirms additive semantics or the implementation is a single-line `value += by`.

**Reject** when:
- The mutating method **clamps**: `BoundedCounter.increment(by:)` that saturates at a maximum violates compositionality (`increment(by: 5) → increment(by: 5)` may not equal `increment(by: 10)` if clamping fires).
- The mutating method applies a **non-linear transform** of its parameter (e.g., `multiplyBy(_:)` is multiplicative, not additive in the asserted form).
- The carrier has hidden state (`Counter` with a `lastUpdate: Date`) that breaks `==` even when the numeric field composes correctly.

**Unknown** when:
- Curated verb match but no doc comment / single-line implementation to confirm purely-additive semantics.

### Identity-element-lifted (V1.19.C, zero v1.19 surface)

V1.19.C pairs a `LiftedTransformation` of shape `(T, X) -> T` (X != T) with an `IdentityCandidate` of type X. Asserts `op'(s, e) == s` for all `s: T` where `e` is the identity-shaped value of type X.

**Note: zero candidates surfaced on the v1.19 cycle-1..14 corpora.** Rubric included for completeness; first surface measurement deferred to a future corpus. Future-rater criteria:

**Accept** when:
- The mutating method's parameter type `X` has a canonical identity element (e.g., `Int.zero`) that is genuinely a no-op for the method's operation: `Counter.increment(by: 0) == c` is the canonical accept.
- The identity name pair maps to an algebraic identity for the parameter type (not just a name match — the constant must actually be the identity).

**Reject** when:
- Name-matching constant with non-identity semantics (e.g., a `static let zero` that is not the additive identity but a sentinel).

**Unknown** when:
- Identity-shaped name without doc comment or default-value documentation establishing the identity-element claim.

### Inverse-pair-lifted (V1.19.D, zero v1.19 surface)

V1.19.D pairs two `LiftedTransformation`s on the same carrier whose names form a curated state-mutation inverse pair (`add`/`remove`, `insert`/`remove`, `push`/`pop`, etc.) and asserts `add(remove(s, x), x) == s` (and the symmetric form) over the lifted shadows.

**Note: zero candidates surfaced on the v1.19 cycle-1..14 corpora.** Rubric included for completeness; first surface measurement deferred to a future corpus. Future-rater criteria:

**Accept** when:
- The curated mutating-pair name describes a real functional-inverse pair: `Set.insert(_:)` ↔ `Set.remove(_:)` accept (removing the just-added `x` undoes the addition, modulo Set's pre-existence semantics).
- Both methods are documented as semantically inverse on the lifted shadows.

**Reject** when:
- Name match without inverse semantics (e.g., `Stack.push` ↔ `Queue.pop` reused names; or `register`/`deregister` where deregistration leaves state side-effects).
- The pair has multiset semantics (insertion of an already-present element is a no-op; removal still removes — not an inverse).
- Capacity-bounded carrier where the inverse depends on capacity state.

**Unknown** when:
- Curated pair name match but doc comment doesn't establish full functional-inverse equivalence on the lifted forms.

## Evidence sources

Per-decision rationale should cite at least one of:

- **The function signature** as it appears in `discover` output.
- **The file path + line number** so a future re-triage run can find the same site.
- **Curated rubric reasoning** (which gate the candidate cleared, why it's not a duplicate of a prior-cycle suppression target).
- **Public documentation snippets** if accessible without checkout.
- **Commit history** for the suggestion's source file.
- **Type-shape patterns** that strongly suggest one verdict.
- **For lifted-suggestion picks**: the *underlying* `mutating func`'s semantic class (terminal vs incremental for idempotence; additive vs clamping/saturating for composition; functional-inverse vs multiset for inverse-pair).

## Decision JSON schema

Decisions are committed to `docs/calibration-cycle-17-data/triage-decisions.json`. Schema mirrors cycle-14's verbatim with one extension: the `template` field admits the new template names (`dual-style-consistency`, `composition`) and a new optional `lifted` boolean field for the lifted-suggestion class:

```json
{
  "version": "cycle-17",
  "raters": ["Claude/single-runner"],
  "captured_at": "2026-05-10",
  "swift_infer_commit": "3e773fe",
  "swift_infer_tag": "v1.19.0",
  "rubric_path": "docs/cycle-17-triage-rubric.md",
  "manifest_path": "docs/calibration-cycle-17-data/sample-manifest.md",
  "notes_path": "docs/calibration-cycle-17-data/triage-notes.md",
  "single_runner_caveat": "Single rater (Claude). Public API + commit history evidence only — no test execution, no internal-implementation reading, no multi-rater consensus. See triage-rubric.md for full caveats.",
  "decisions": [
    {
      "id": 1,
      "template": "round-trip" | "idempotence" | "commutativity" | "associativity" | "inverse-pair" | "monotonicity" | "identity-element" | "dual-style-consistency" | "composition",
      "lifted": true | false,
      "corpus": "OC" | "CM" | "Algo" | "PLK",
      "decision": "reject" | "accept" | "unknown",
      "site": "Sources/<path>:<line>[/<line>]",
      "summary": "<short rubric-citation rationale>"
    }
  ]
}
```

The `lifted` field defaults to `false` (omitted in non-lifted decisions per JSON convention); it is `true` for the V1.19.B–D lifted-suggestion picks (`idempotence-lifted`, `composition-lifted`, `identity-element-lifted`, `inverse-pair-lifted`). The `template` field for lifted picks uses the **base template name** (e.g., `idempotence`, not `idempotence-lifted`) so cycle-17 can compute combined acceptance rates on the lifted-class composite, with `lifted` as the discriminator.

## Acceptance-rate computation

Per-template (and per-corpus) rates:

```
acceptance_rate(t) = accept_count(t) / (accept_count(t) + reject_count(t))
uncertainty_rate(t) = unknown_count(t) / total_count(t)
```

Cycle-17 reports:

- **Aggregate acceptance rate** vs cycle-6 (26.7%) and cycle-14 (34.8%).
- **Per-template rate** for each cycle-14-baseline template (round-trip, idempotence-non-lifted, commutativity, associativity, monotonicity, inverse-pair-non-lifted, identity-element-non-lifted).
- **First per-template rate** for the two new template families (dual-style-consistency, composition-lifted).
- **First per-template rate for the lifted sub-class** (idempotence-lifted aggregated across its 6 picks; sub-corpus rates for the Algo Iterator-dominated 3 picks vs OC SetAlgebra-shape 3 picks).

Single-runner triage produces *one* rater's view; cross-rater agreement is its own quality metric (deferred to multi-rater cycle).

## Cycle-17 vs cycle-14 vs cycle-6 methodology delta

| Aspect | Cycle 6 (v1.9) | Cycle 14 (v1.17) | Cycle 17 (v1.20) |
|---|---|---|---|
| Surface measured | post-V1.8.1 349-surface | post-V1.16.1 229-surface | post-V1.19.0 335-surface |
| Sample size | 50 | 50 | 46 (rebased per V1.20.A; 4 picks freed by zero-surface lifted sub-templates not redistributed) |
| Stratification | per-template + per-corpus | per-template + per-corpus (cycle-6-matching weights) | new-class-weighted (35 existing + 11 new); rebased at V1.20.A |
| Rater | Claude/single-runner | Claude/single-runner | Claude/single-runner |
| Tier mix | Possible + 1 Likely (identity-element outlier) | Possible + 1 Likely | Possible + cycle-14 carry-forwards (lone identity-element + lone inverse-pair Likely-tier) |
| Picks reuse | n/a | fresh stratified | fresh stratified |
| Per-template criteria — existing 7 | this rubric | verbatim carry-forward | **verbatim** carry-forward (cycle-14 → cycle-17) |
| Per-template criteria — new 2 (dual-style + composition) | n/a | n/a | **new** sections above |
| Per-template criteria — lifted sub-class | n/a | n/a | **new** sections above (idempotence-lifted; future-only for identity-element-lifted + inverse-pair-lifted) |
| Post-cycle-N mechanism context | n/a | post-cycle-6 (cycles 7–13) | post-cycle-14 (cycles 15 + 16) |

The methodology delta is intentionally minimal **on the existing 7 templates** so that per-template rate-shifts between cycles 14 and 17 are attributable to the cycle-15 + cycle-16 mechanism work, not to triage methodology drift. The **new 2 templates + lifted sub-class** have no prior baseline; their cycle-17 rates establish the baseline for cycle-18+ comparisons.
