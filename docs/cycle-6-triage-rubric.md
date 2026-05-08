# Cycle-6 Triage Rubric

Methodology document for v1.9's empirical Possible-tier sampling pass. Defines accept/reject/unknown criteria per template, what counts as evidence in single-runner triage, and how the rubric handles edge cases.

**Scope:** v1.9 / cycle 6 — the first empirical Possible-tier triage round. Reusable for cycle 7+ if the methodology proves out.

## What we're measuring

Each triaged suggestion is a *claim* SwiftInfer makes — "this code looks like it satisfies a `<template-name>` property." The triage decision answers: **does the property actually hold?**

- **Accept** — yes, the property holds for the function(s) as written. A property test stub written from this suggestion would pass on plausible inputs. The user would ship it.
- **Reject** — no, the property doesn't hold. The functions are *related* but not in the way the template claims (e.g., the named pair isn't actually inverses; the operation isn't actually commutative; etc.). A property test stub would fail or be misleading.
- **Unknown** — the rater can't determine the answer from public-API + commit-history evidence alone. The property *might* hold but verifying requires reading internal implementation, running tests, or consulting domain experts.

The §19 acceptance-rate target ("≥ 70% acceptance after 6 months of dogfooding") is computed as `accept / (accept + reject)` — `unknown` is excluded from the denominator. A separate "triage uncertainty rate" tracks `unknown / total` as a methodology-quality metric.

## Single-runner triage caveat

This rubric documents what *one* rater can determine from public surfaces + git log. It deliberately excludes:

- **Running the code.** Triage decisions don't compile-and-execute the suggested property. Multi-rater + automated property-test verification is the natural next step (out of scope for v1.9).
- **Internal implementation details.** Public APIs only — file paths, function signatures, doc comments, public type contracts. Internal semantics (e.g., whether `_HashTable._bucketContents(for:)` actually round-trips with `_value(forBucketContents:)`) are read-only-via-source-code.
- **Multi-rater consensus.** Single rater. A second rater might call differently on the ambiguous edges.
- **Domain expertise the rater lacks.** I've worked with Swift collections / numerics / algorithms public APIs but I'm not a swift-collections / swift-numerics / swift-algorithms maintainer. Calls on tricky semantic edges should be read with that limitation in mind.

When the evidence is genuinely ambiguous, the rubric mandates `unknown` — *not* a forced binary call.

## Per-template criteria

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

Decisions are committed to `docs/calibration-cycle-6-data/triage-decisions.json`. Schema mirrors `.swiftinfer/decisions.json`'s shape so cycle-6 data is in principle replayable against the v1.8 binary:

```json
{
  "version": "cycle-6",
  "raters": ["Claude/single-runner"],
  "captured_at": "2026-05-08",
  "swift_infer_commit": "<v1.8.0 tag commit>",
  "decisions": [
    {
      "id": "<sha256 of canonical signature>",
      "template": "round-trip",
      "corpus": "swift-collections/OrderedCollections",
      "primary_site": "Sources/OrderedCollections/HashTable/_HashTable+Constants.swift:58",
      "secondary_site": "Sources/OrderedCollections/HashTable/_HashTable+Constants.swift:67",
      "score": 30,
      "tier": "Possible",
      "decision": "reject" | "accept" | "unknown",
      "rationale": "string with rubric citation"
    }
  ]
}
```

## Acceptance-rate computation

Per-template (and per-corpus) rates:

```
acceptance_rate(t) = accept_count(t) / (accept_count(t) + reject_count(t))
uncertainty_rate(t) = unknown_count(t) / total_count(t)
```

The §19 long-term target compares against `acceptance_rate(t)`. The cycle-6 sample's per-template rate is a noisy estimate (small-sample); cycle-7+ samples will refine.

Single-runner triage produces *one* rater's view; cross-rater agreement is its own quality metric (deferred to multi-rater cycle).
