# Cycle-14 Triage Rubric

Methodology document for v1.17's empirical Possible-tier sampling pass on the post-v1.16 229-surface. Defines accept/reject/unknown criteria per template, what counts as evidence in single-runner triage, and how the rubric handles edge cases.

**Scope:** v1.17 / cycle 14 — the **second empirical-only cycle** in the calibration loop (after cycle 6 = v1.9 on the 349-surface). Carries cycle-6's per-template criteria verbatim; adds a "Post-cycle-6 mechanism context" section documenting the suppression layers (cycles 7-13) a v1.16 survivor has cleared, so the rater can frame each pick against the gates it has already passed.

**Companion to `docs/cycle-6-triage-rubric.md`, not a replacement.** The cycle-6 rubric stays unchanged for forensic comparability with the cycle-6 sample. Resolves v1.17 plan §"Open decisions" #5 in favor of (b): carry-forward verbatim with cycle-14 supplement.

## What we're measuring

Each triaged suggestion is a *claim* SwiftInfer makes — "this code looks like it satisfies a `<template-name>` property." The triage decision answers: **does the property actually hold?**

- **Accept** — yes, the property holds for the function(s) as written. A property test stub written from this suggestion would pass on plausible inputs. The user would ship it.
- **Reject** — no, the property doesn't hold. The functions are *related* but not in the way the template claims (e.g., the named pair isn't actually inverses; the operation isn't actually commutative; etc.). A property test stub would fail or be misleading.
- **Unknown** — the rater can't determine the answer from public-API + commit-history evidence alone. The property *might* hold but verifying requires reading internal implementation, running tests, or consulting domain experts.

The §19 acceptance-rate target ("≥ 70% acceptance after 6 months of dogfooding") is computed as `accept / (accept + reject)` — `unknown` is excluded from the denominator. A separate "triage uncertainty rate" tracks `unknown / total` as a methodology-quality metric.

## Single-runner triage caveat

This rubric documents what *one* rater can determine from public surfaces + git log. It deliberately excludes:

- **Running the code.** Triage decisions don't compile-and-execute the suggested property. Multi-rater + automated property-test verification is the natural next step (out of scope for v1.17, same as v1.9).
- **Internal implementation details.** Public APIs only — file paths, function signatures, doc comments, public type contracts. Internal semantics (e.g., whether `_HashTable._bucketContents(for:)` actually round-trips with `_value(forBucketContents:)`) are read-only-via-source-code.
- **Multi-rater consensus.** Single rater. A second rater might call differently on the ambiguous edges.
- **Domain expertise the rater lacks.** I've worked with Swift collections / numerics / algorithms public APIs but I'm not a swift-collections / swift-numerics / swift-algorithms maintainer. Calls on tricky semantic edges should be read with that limitation in mind.

When the evidence is genuinely ambiguous, the rubric mandates `unknown` — *not* a forced binary call.

## Post-cycle-6 mechanism context

The cycle-14 sample is drawn from the **v1.16 229-surface**, which has been suppressed 349 → 229 (−34.4%) across six mechanism cycles since cycle 6. A v1.16 survivor on **round-trip / idempotence / inverse-pair** has cleared 2-3 distinct mechanism classes that didn't exist at cycle 6. The rater should know which gates each surviving candidate has already passed — surviving false positives are by construction in *novel* failure modes (not direction-labeled, not domain-marker-labeled, not SetAlgebra-shaped on the templates where those gates fire).

This context **does not change the verdict thresholds**. The accept/reject criteria stay as written below. It does change what the rater should *expect* to see in the surviving pool, and what kinds of new rejection patterns are signal-of-interest for cycle-15 priority rotation.

### Per-template suppression layers cleared at v1.16

**Round-trip** (139 v1.16 candidates) — three post-cycle-6 mechanism layers cleared:

| Cycle | Release | Mechanism | Suppression weight | Suppression criterion |
|---|---|---|---:|---|
| 9 | V1.12.1 | direction-label counter | −15 | either pair-side's first-param label ∈ `DirectionLabels.curated` |
| 12 | V1.15.1 | domain-marker counter | −15 | both pair-sides' first-param label ∈ `DomainMarkerLabels.curated` |
| 13 | V1.16.1 | SetAlgebra-shape veto | −25 | both pair-sides have `(Self) -> Self` shape AND both names ∈ `SetAlgebraShape.binaryOps` |

**Idempotence** (25 v1.16 candidates) — three post-cycle-6 mechanism layers cleared:

| Cycle | Release | Mechanism | Suppression weight | Suppression criterion |
|---|---|---|---:|---|
| 7 | V1.10.1 | direction-label counter | −15 | first-param label ∈ `DirectionLabels.curated` |
| 12 | V1.15.1 | domain-marker counter | −15 | first-param label ∈ `DomainMarkerLabels.curated` |
| 13 | V1.16.1 | SetAlgebra-shape veto | −25 | `(Self) -> Self` shape AND function name ∈ `SetAlgebraShape.binaryOps` |

**Inverse-pair** (1 v1.16 candidate) — three post-cycle-6 mechanism layers cleared:

| Cycle | Release | Mechanism | Suppression weight | Suppression criterion |
|---|---|---|---:|---|
| 8 | V1.11.1 | direction-label counter | −10 | either pair-side's first-param label ∈ `DirectionLabels.curated` |
| 11 | V1.14.1 | SetAlgebra-shape veto | −25 | both sides `(Self) -> Self` AND both names ∈ `SetAlgebraShape.binaryOps` |
| 12 | V1.15.1 | domain-marker counter | −15 | both pair-sides' first-param label ∈ `DomainMarkerLabels.curated` |

**Monotonicity / commutativity / associativity / identity-element** (29 / 17 / 17 / 1 v1.16 candidates) — **no new per-template mechanisms post-cycle-6.** The cycle-6 rubric's verdict thresholds for these four templates apply to v1.16 survivors without modification. Cycle-14 picks on these templates measure the same surface that cycle 6 measured (modulo the cycle-1...5 structural-rule cycles that ran before cycle 6 and shape the v1.16 surface uniformly).

### Curated suppression sets (for rationale-writing reference)

These are the curated sets the cycle-7–13 mechanisms consult. The rater shouldn't need to memorize them — they're listed here so a triage-notes citation can disambiguate why a candidate is *not* a duplicate of a prior-cycle suppression target:

- `DirectionLabels.curated` (V1.10.1, hoisted in V1.13): `{after, before, next, prev, previous, advance, succ, pred, successor, predecessor}`. Spatial-sequence iteration labels.
- `DomainMarkerLabels.curated` (V1.15.1): `{forScale, forCapacity, forBucketContents}`. Semantic-intent named-domain markers.
- `SetAlgebraShape.binaryOps` (V1.14.1, hoisted in V1.16.1): `{union, intersection, symmetricDifference, subtracting}`. SetAlgebra binary-op function names.

### Cycle-6 → cycle-14 picks-status framing

Cycle-12 and cycle-13 findings have already documented which cycle-6 picks were suppressed by which subsequent mechanism. Cycle 14 is **fresh stratified sampling**, not cycle-6 picks reuse (v1.17 plan §"Open decisions" #4). The rater should *not* attempt to re-triage cycle-6 picks; they'll appear in the cycle-14 findings writeup's "Cycle-6 picks status" rollup, which is methodology-comparable but not sample-overlapping.

## Per-template criteria

The following criteria are carried forward verbatim from `docs/cycle-6-triage-rubric.md`. Edits would compromise cycle-6 ↔ cycle-14 rate-shift comparability. The Post-cycle-6 mechanism context above is the only methodologically-meaningful supplement.

### Round-trip — `g(f(x)) == x` for all `x` in the function's effective domain

**Accept** when:
- Function names + signatures suggest the pair is by-design inverses (e.g., `encode` ↔ `decode`, `parse` ↔ `format`, curated inverse-pair list).
- The pair operates on the same `T` carrier; type signatures align (`(T) -> U` ↔ `(U) -> T`).
- Domain coverage: the suggestion is plausible without restricting `x` (or has a clear convention for the legitimate domain — e.g., `URL.init(string:)` succeeds on a documented subset).
- No textual evidence of asymmetric postconditions (e.g., `func decode` documented as throwing on malformed input but `encode` doesn't have a corresponding survivable subset).

**Reject** when:
- The pair is *related* but semantically not inverses (e.g., `minimumCapacity(forScale:)` and `maximumCapacity(forScale:)` both take `scale` and return capacity but yield *different* capacities — `min(scale(c)) == c` doesn't hold across the cross-product).
- Functions have asymmetric domains (e.g., one accepts negative numbers, the other rejects them — round-trip fails on the asymmetric subset).
- The "round-trip" is identity-on-the-codec only (e.g., `compress` ↔ `decompress` round-trips on `Data` regardless of source type, but `(Data) -> Data` ↔ `(Data) -> Data` doesn't claim a meaningful round-trip about the pre-compressed source).

**Unknown** when:
- Function names are non-diagnostic (numeric or generic placeholders that don't suggest inverse intent).
- Internal logic determines whether the pair commutes (rater can't read it).
- Documentation is silent on round-trip intent.

### Idempotence — `f(f(x)) == f(x)`

**Accept** when:
- Function name suggests idempotence (`normalize`, `canonicalize`, `dedupe`, `simplify`, `clamped`, `flattened`).
- Signature is single-arg `(T) -> T` and the doc comment / function purpose makes clear that applying twice yields the same result.
- Examples: `String.lowercased()`, `Array.sorted()`, `Set.union(_)`-on-itself.

**Reject** when:
- The function's purpose is to *change* state per call (counter increment, RNG step).
- Signature is `(T) -> T` but the operation is monotonic / accumulative (e.g., `appended(_:)` is not idempotent on the same argument unless the collection guarantees uniqueness).
- The function is *partially* idempotent (idempotent on some subdomain but not all of `T`).

**Unknown** when:
- The function name + signature don't disambiguate (e.g., a pure `(Int) -> Int` with no doc comment).
- Internal state determines the answer.

### Commutativity — `f(a, b) == f(b, a)`

**Accept** when:
- Standard math operators (`+`, `*`) on Numeric types — but these should already be suppressed by V1.5.2 + V1.7.1; if they reach the triage, something is novel about the type.
- Set operations on SetAlgebra (`union`, `intersection`).
- Function name explicitly suggests symmetric semantics (`merge`, `combine`, `meet`, `join`).

**Reject** when:
- The op is naturally directional: `a - b ≠ b - a`, `a / b ≠ b / a`, `a.appending(b) ≠ b.appending(a)`, `a.compose(b) ≠ b.compose(a)`.
- Function name suggests directionality (`from:to:`, `applyTo:`, `into:`).

**Unknown** when:
- Function name is ambiguous (`process(a:, b:)`, generic helper).
- The operation depends on ordering of side-effects.

### Associativity — `(a · b) · c == a · (b · c)`

**Accept** when:
- Standard math operators on Numeric / set algebra (already mostly suppressed at V1.5.2).
- Function name suggests free-form combination (`merge`, `concatenate`).

**Reject** when:
- The operation is non-associative by design (subtraction-like, function composition modulo ordering).

**Unknown** when:
- Function name + signature don't disambiguate.

### Inverse-pair — `f(g(x)) == x` AND `g(f(y)) == y`

**Accept** when:
- Function-pair names are explicit additive-inverse-style (`add` ↔ `subtract` on the same type, `push` ↔ `pop` from the same stack invariant).
- Strong type signal: `(T, T) -> T` ↔ `(T, T) -> T` with shared free variable.

**Reject** when:
- The pair is related but not inverses (e.g., `formUnion(_:)` ↔ `formIntersection(_:)` are not inverses of each other).

### Monotonicity — `a ≤ b ⇒ f(a) ≤ f(b)`

**Accept** when:
- Function takes a single Comparable input and returns Comparable; doc / name suggests order-preservation (`mapping`, `transform` of a sortable key).
- Function is naturally a counting / sizing op (`count`, `size`, `length`).

**Reject** when:
- The function's purpose is to *invert* order (`reversed()`, `negated`).
- The output type is not comparable in a way that aligns with the input ordering.

### Identity-element — `f(x, ε) == x` AND/OR `f(ε, x) == x`

**Accept** when:
- The op + element pair maps to a kit-published identity law not already suppressed by V1.5.2 + V1.6.1.
- Function name + element suggest standard monoid identity (`combine` + `.empty`, `add` + `.zero`).

**Reject** when:
- The op-name + element doesn't match any kit-published law and isn't textually a stdlib operator (V1.6.1 should have caught these but the curated list isn't exhaustive).

**Unknown** when:
- The user-defined op + element is novel to the rater (e.g., a domain-specific `pow` ↔ `Complex.zero` — does the math work out?).

## Evidence sources

Per-decision rationale should cite at least one of:

- **The function signature** as it appears in `discover` output (`(forScale: Int) -> Int`).
- **The file path + line number** so a future re-triage run can find the same site.
- **Curated rubric reasoning** ("the names `minimumCapacity` and `scale` aren't inverse-pair-shaped per the curated list; they're related-but-not-inverse").
- **Public documentation snippets** if accessible without checkout.
- **Commit history** for the suggestion's source file (e.g., "this function was added in commit X with intent Y").
- **Type-shape patterns** that strongly suggest one verdict (e.g., a `(T) -> Bool` signature on the round-trip template should reject — the reverse would have to be `(Bool) -> T`, which is not what the second function is).

## Decision JSON schema

Decisions are committed to `docs/calibration-cycle-14-data/triage-decisions.json`. Schema mirrors cycle-6's verbatim (which itself mirrors `.swiftinfer/decisions.json`'s shape) so cycle-14 data is in principle replayable against the v1.16 binary and programmatically comparable with cycle 6:

```json
{
  "version": "cycle-14",
  "raters": ["Claude/single-runner"],
  "captured_at": "2026-05-09",
  "swift_infer_commit": "9e36efd",
  "swift_infer_tag": "v1.16.0",
  "rubric_path": "docs/cycle-14-triage-rubric.md",
  "manifest_path": "docs/calibration-cycle-14-data/sample-manifest.md",
  "notes_path": "docs/calibration-cycle-14-data/triage-notes.md",
  "single_runner_caveat": "Single rater (Claude). Public API + commit history evidence only — no test execution, no internal-implementation reading, no multi-rater consensus. See triage-rubric.md for full caveats.",
  "decisions": [
    {
      "id": 1,
      "template": "round-trip",
      "corpus": "OC",
      "decision": "reject" | "accept" | "unknown",
      "site": "Sources/<path>:<line>[/<line>]",
      "summary": "<short rubric-citation rationale>"
    }
  ]
}
```

The `id` field is a 1-indexed integer (cycle-6 convention; sortable by stratification order). The `corpus` field uses the cycle-6 abbreviations: `OC` (OrderedCollections), `CM` (ComplexModule), `Algo` (Algorithms), `PLK` (PropertyLawKit). The `site` field is single-site for single-function templates (idempotence, monotonicity, commutativity, associativity), or `<file>:<line1>/<line2>` for pair-based templates (round-trip, inverse-pair, identity-element).

## Acceptance-rate computation

Per-template (and per-corpus) rates:

```
acceptance_rate(t) = accept_count(t) / (accept_count(t) + reject_count(t))
uncertainty_rate(t) = unknown_count(t) / total_count(t)
```

The §19 long-term target compares against `acceptance_rate(t)`. The cycle-14 sample's per-template rate is a noisy estimate (small-sample); the cycle-6 vs cycle-14 rate-shift on each template is **the headline cycle-14 finding** and feeds directly into the cycle-15 priority rotation.

Single-runner triage produces *one* rater's view; cross-rater agreement is its own quality metric (deferred to multi-rater cycle, same posture as cycle 6).

## Cycle-14 vs cycle-6 methodology delta

| Aspect | Cycle 6 (v1.9) | Cycle 14 (v1.17) |
|---|---|---|
| Surface measured | post-V1.8.1 349-surface | post-V1.16.1 229-surface |
| Sample size | 50 | 50 (matches; v1.17 plan §"Open decisions" #1) |
| Stratification | per-template + per-corpus | per-template + per-corpus (cycle-6-matching weights; v1.17 plan §"Open decisions" #3) |
| Rater | Claude/single-runner | Claude/single-runner (matches; v1.17 plan §"Open decisions" #2) |
| Tier mix | Possible + 1 Likely (identity-element outlier) | Possible + 1 Likely (identity-element outlier; v1.17 plan §"Open decisions" #6) |
| Picks reuse | n/a (first cycle) | fresh stratified sampling (v1.17 plan §"Open decisions" #4) |
| Per-template criteria | this rubric | **verbatim** carry-forward (v1.17 plan §"Open decisions" #5) |
| Post-cycle-6 mechanism context | n/a | new section above |

The methodology delta is intentionally minimal so that per-template rate-shifts between cycles 6 and 14 are attributable to the cycle-7–13 mechanism work, not to triage methodology drift.
