# v1.4 Calibration Cycle 1 — Findings

Captured: 2026-05-08. swift-infer at `10135fa` (after V1.4.3 + V1.4.3a + V1.4.3b + minimum-scope triage). The first execution of PRD §17.3's empirical-tuning loop.

This document is the cycle-1 record: what we ran, what we learned, what shipped, what's deferred. Cycle 2 reads this + the committed decisions data to decide where to perturb next.

## Headline

**Cycle 1 shipped two structural rules and one explainability extension.** All three were derivable from the cycle-1 surface data **before any user triage** — they didn't require empirical accept/reject decisions to validate. The 6-decision minimum-scope triage that did happen confirmed a third hypothesis (operator-aware identity-element pairing) that's earmarked for cycle 2.

| Tuning | Type | Where | Empirical effect |
|---|---|---|---|
| FP-storage counter-signal (-10) | weight | Associativity, Commutativity, Inverse-pair templates | 12 of 16 commutativity+associativity ComplexModule hits drop Score 30 → 20 |
| Cross-type round-trip counter-signal (-25) | structural | Round-trip template | round-trip Possible 990 → 181 (-81.7%) across 4 cycle-1 corpora |
| Type-aware FP advisory pointing at PropertyLawKit | explainability | Associativity, Commutativity, Inverse-pair templates | n/a (text-only); reframes "noise" → "valid w/ finite-only generator" |

After the two counter-signals: total `--include-possible` surface across the 4 corpora went **1167 → 358** (-69.3%). The FP-related share is small (16 hits) because only ComplexModule has FP-storage types; the round-trip cross-type rule is the dominant driver.

## Corpus selection

PRD §19 calls for ≥3 packages, "one of which should be a sufficiently algebraic library." Cycle 1 picked four:

| Corpus | Target | Rationale |
|---|---|---|
| swift-collections | OrderedCollections | Set/dictionary algebra; `BidirectionalCollection` round-trips. |
| swift-numerics | ComplexModule | Complex arithmetic — textbook commutative ring; only corpus with default-tier-visible suggestions. |
| swift-algorithms | Algorithms | Combinatorics + folds; high round-trip / idempotence candidate volume (the 728-suggestion corpus). |
| SwiftPropertyLaws | PropertyLawKit | Sibling kit; the algebraic-property-test library SwiftInfer was designed against. |

Each corpus's pre-tune `discover --include-possible` output is captured at `docs/calibration-cycle-1-data/<corpus>-<target>.discover.txt`; post-tune captures land at `post-tune-<corpus>-<target>.discover.txt`.

## Pre-triage observations (the high-leverage findings)

Before any user accept/reject decisions, the cycle-1 surface map was already actionable:

### 1. The default-tier engine is conservatively-biased on test-free corpora

| Corpus | Default-tier visible | Total surfaced (`--include-possible`) |
|---|---:|---:|
| swift-numerics/ComplexModule | 6 | 175 |
| swift-collections/OrderedCollections | 0 | 257 |
| swift-algorithms/Algorithms | 0 | 728 |
| SwiftPropertyLaws/PropertyLawKit | 0 | 7 |

Only 6 of 1167 (0.5%) surfaced suggestions reach the default visibility threshold (Likely / Score ≥ 40). All six are `identity-element` on ComplexModule — the curated identity-constant signal (+40) is the only mechanism that lifts a signature-only match above the Likely cliff without test-body cross-validation.

This validates PRD §3.5's "high precision, low recall" philosophy: the default surface is genuinely sparse on real test-free corpora. **Users running `swift-infer discover` against a typical Swift module won't be flooded.** Whether the engine misses too much (the recall side) requires cycle-2 scoping.

### 2. Round-trip's signature-only matching dominates Possible-tier noise

| Template | `--include-possible` total |
|---|---:|
| round-trip | 990 (84.8%) |
| idempotence | 89 |
| monotonicity | 29 |
| commutativity | 19 |
| associativity | 19 |
| inverse-pair | 15 |
| identity-element | 6 |

990 round-trip Possible-tier hits all sit at exactly Score 30 — the type-symmetry-signature signal alone, no cross-validation. 673 of those came from swift-algorithms, where the textual `(Index) -> Index ↔ Index -> Index` matcher couldn't distinguish `AdjacentPairsCollection.Index` from `Chain2Sequence.Index` (etc.).

**Cycle-1 tuning: `crossTypeRoundTripPair` counter-signal (-25)** when `forward.containingTypeName != reverse.containingTypeName` (with `nil == nil` free-function exemption + shared `@Discoverable(group:)` exemption). Drops Score 30 → 5 = Suppressed = filtered. Empirical effect: round-trip Possible 990 → 181, with the biggest cuts on swift-algorithms (728 → 75) and swift-collections (257 → 101).

**Why this is good calibration data:** the rule is structural, not curated. It uses `containingTypeName` (textual SwiftSyntax output), so future stdlib changes don't degrade it. SemanticIndex would catch the same case via type resolution; this is the cheap pre-SemanticIndex approximation.

### 3. Score distribution is highly compressed

Most templates produce a single score with no variance: round-trip = 30, idempotence = 30, commutativity = 30, associativity = 30, monotonicity = 25 (1 outlier at 35), inverse-pair = 25, identity-element = 70. The PRD §4.1 +20 cross-validation signal (test-body match) is the design's primary "escape from Possible" mechanism — but real corpora often don't have matching XCTest bodies for TestLifter to lift.

This isn't a tuning hypothesis on its own — it's a recall observation. Cycle 2 might explore: **should production-only structural signals exist at +10 or +15 to break the score-30 floor?** That's a bigger calibration question than cycle 1 supports.

### 4. FP storage is a real algebraic-candidate class, not noise

The first cut of cycle 1's FP rule framed FP-storage suggestions as suppression candidates ("v1.5+ approximate-equality template arm"). After re-reading PropertyLawKit's `FloatingPointLaws.swift` posture —

> "A type spelled `: FloatingPoint` emits only `checkFloatingPointPropertyLaws`; users wanting algebraic coverage on a finite-only generator opt in by calling the inherited check directly."

— the framing changed: FP candidates aren't false positives, they're real algebraic intent that needs verification-mode adjustment (finite-only generator). The cycle-1 advisory (V1.4.3a) reframes accordingly:

> "T = Complex has IEEE 754 floating-point storage. Associativity holds in principle; exact-equality auto-sampling fails on rounding. Verify via a finite-only generator (e.g. `Gen<Double>.double(in: -1e6...1e6)` lifted into Complex) per PropertyLawKit's `FloatingPointLaws.swift` tolerance posture. v1.5+ will surface the generator override automatically."

The Score 30 → 20 floor stays (-10 counter-signal); the counter-signal is what reduces confidence-in-auto-sampling, not what hides the algebraic claim. The kit-pointer is what makes the suggestion useful.

**This is the most important calibration nuance from cycle 1.** Without the user's framing ("if we were to test for Equatable via propertylaws, this would be valuable information"), the FP rule would have shipped as suppression. The user's domain context shifted it to an opt-in escape hatch, which is more useful and more correct.

## Triage findings (minimum-scope)

User-driven triage on the 6 default-tier identity-element suggestions on ComplexModule:

| # | Function | Decision | Reasoning |
|---|---|---:|---|
| 1 | `+(z:w:)` | **A** | True bilateral additive identity (`z + 0 == z` and `0 + z == z`). |
| 2 | `-(z:w:)` | **n** | Right-identity only; left fails (`0 - z == -z`). |
| 3 | `/(z:w:)` | **n** | Wrong constant; identity for `/` is `1`, not `0`. Plus division by zero is undefined. |
| 4 | `rescaledDivide(_:_:)` | **n** | Same as `/` — division semantics. |
| 5 | `pow(_:_:)` | **n** | Wrong constant; identity for `pow` is `1`. |
| 6 | `*(z:w:)` | **n** | Wrong constant; identity for `*` is `Complex.one`, not `Complex.zero`. |

**Per-template metric:** identity-element acceptance rate **16.7%** (1 of 6). Below the PRD §17.2 50% retirement-candidate cliff — but the count is < 20, so the metrics command flags this advisory-only:

```
note: identity-element — fewer than 20 decisions; rates are advisory.
```

**The cycle-2 hypothesis this generates** (don't ship in cycle 1; needs more data):

The identity-element template currently fires the curated `Complex.zero` constant against **every** binary op signature `(T, T) -> T` it finds. That's a cross-product match. The cycle-2 fix would be **operator-aware constant pairing**: `.zero` is paired only with additive ops (`+`, `-`-name family), `.one` with multiplicative ops (`*`, `/`-name family), and `pow` exempt entirely (no `T -> T -> T` identity element exists for non-monoid ops).

Implementation outline (cycle 2):
- Curated additive ops: `+`, `add`, `combine`, `merge`, `union`, `concat`, `append`, …
- Curated multiplicative ops: `*`, `multiply`, `times`, `apply`, `compose`, …
- Identity-element template's signal collection adds an `operatorClassMismatch` counter-signal (-25) when the curated constant's "kind" doesn't match the op's "kind."
- Expected effect on the cycle-1 baseline: 5 of 6 ComplexModule identity-element suggestions drop to Suppressed (#2 — `-` paired with `.zero` is the borderline case; arguably `-` is in the additive family but the property only holds one-sided so it should still be filtered for a different reason).

**Cycle 2 needs more triage data** to confirm this hypothesis on a non-Complex corpus. swift-collections / swift-algorithms didn't produce default-tier identity-element hits in cycle 1; an expanded corpus (swift-numerics RealModule, swift-collections OrderedSet, etc.) would surface more.

## What's not in cycle 1's triage corpus

Possible-tier sampling was scoped out of cycle 1 per the V1.4.0 plan's minimum-scope option. After the V1.4.3b cross-type rule cut round-trip Possible from 990 → 181, the remaining surface is finally tractable for sampling — but that's cycle-2 work. Specifically deferred:

- **Same-type same-op round-trip false positives** (e.g., `index(after:) ↔ index(after:)` within one type — does the cycle-1 rule still over-fire? Need triage).
- **idempotence acceptance rate** (89 hits, none triaged in cycle 1).
- **monotonicity acceptance rate** (29 hits, mostly OrderedCollections).
- **commutativity acceptance rate at Score 20** (the 6 ComplexModule survivors after the FP counter-signal — would the user accept these given the kit-pointer advisory? Cycle-2 sampling would close the loop on the FP framing).

## Methodology gaps to address

**Missing PRD §17.2 metrics.** The metrics command ships three of five §17.2 rows; the remaining two require new fields on `DecisionRecord`:

- **Time-to-adoption.** Needs `surfacedAt: Date` field + plumbing through `Discover.run`'s suggestion-surfacing path. Deferred to v1.5+.
- **Post-acceptance failure rate.** Needs `firstCommitPasses: Bool?` + a CI hook to set it after the accept-flow stub runs. Deferred — depends on UX design for the hook.

**Triage-volume floor.** The 6-decision minimum-scope is below PRD §17.2's 20-decision statistical-significance cliff for every template. Findings here are directional, not statistically significant. Cycle 2 should aim for ≥ 20 decisions per active template before drawing retirement conclusions.

**Single-runner triage.** All cycle-1 decisions are from one user. PRD §17.3 step 1 is "aggregate decisions from a corpus of opt-in projects." Cycle 2 might solicit decisions from invited closed-source pilots per PRD §17.3 OD #2.

**Default-tier sparsity.** Real corpora produce 0–6 default-tier suggestions across the 4 cycle-1 corpora combined. The 20-decisions cliff is unreachable from default-tier triage alone on test-free corpora. Cycle-2 widening must include `--include-possible` sampling to accumulate enough decisions per template.

**Protocol-conformance blindness.** The cycle-1 engine consumes `TypeDecl.inheritedTypes` from the SwiftSyntax scan in three places: (a) `EquatableResolver` (negative gate on `InversePairTemplate` only), (b) `GeneratorSelection` (post-score generator strategy selection), (c) `TypeShapeBuilder` (cross-extension merging). It does *not* consume conformances as a *positive signal* during property scoring — no template branches on "T conforms to `Numeric` / `AdditiveArithmetic` / `SetAlgebra`" to bump the score or refine which structural elements pair with which ops. The `Signal.Kind.algebraicStructureCluster` enum case from PRD §5.4 exists in the catalog but is emitted nowhere. This is the underlying reason cycle-1's identity-element template fired `Complex.zero` against `*` and `pow` (the ops have no protocol-mandated `.zero` identity but the template doesn't know that). Cycle-2's operator-aware-pairing refinement (priority #1) should use protocol-conformance reading as its primary mechanism, with curated op-name lists as a fallback for non-conforming types. The same posture extends to `Numeric` / `AdditiveArithmetic` / `SignedNumeric` / `SetAlgebra` / kit-defined `Monoid` / `Group` / `Semilattice` / `CommutativeMonoid` — each carries documented laws that the engine could leverage as positive signals before falling back to signature-only matching.

## Cycle-2 priority list (in expected impact order)

1. **Operator-aware identity-element pairing.** Cycle 1 found 16.7% acceptance — 5 of 6 false positives are wrong-constant cases. The fix is structural — but post-cycle-1 review sharpens *how* it should be structured.

   **Refinement (added post-cycle-1).** When I first framed this fix I proposed "curated additive-vs-multiplicative op-name lists" — a hand-maintained allowlist parallel to the FP-storage one. That's worse than necessary. The cycle-1 engine ignores protocol conformances *as positive signals* almost entirely: `EquatableResolver` reads `inheritedTypes` only as a *negative gate* on `InversePairTemplate`; `GeneratorSelection` reads `inheritedTypes` only *after* scoring for generator selection; `Signal.Kind.algebraicStructureCluster` exists in the catalog but is never emitted by any template. The protocol info that `TypeDecl.inheritedTypes` already captures from SwiftSyntax is sitting there unused for property scoring. The cycle-2 fix should use it as the primary mechanism:

   - If `T: AdditiveArithmetic` / `: Numeric` / `: SignedNumeric`: `T.zero` is the documented *additive* identity. Pair only with `+` / `add`-verb-family ops. The protocol's own laws guarantee both-sided identity, so the IdentityElement template's two-sided caveat is also automatically satisfied for these types.
   - If `T: Numeric`: `T.one` is the documented *multiplicative* identity. Pair only with `*` / `multiply`-verb-family ops.
   - If `T: SetAlgebra`: pair `.empty` with `union` (the SetAlgebra additive analogue); intersection's identity (the universal set) has no Swift name and is skipped.
   - If T conforms to none of the above: fall back to a small curated op-class list as the cycle-2 secondary path, not the primary one.

   This is sharper than a curated allowlist because it uses authoritative source-of-truth that's already in the scan. It also generalizes — types like `BigInt` or `Decimal` that conform to `Numeric` get the same treatment automatically without requiring new curation. Estimated scope: read `TypeDecl.inheritedTypes` in `IdentityElementTemplate.suggest`, gate the curated-identity-constant signal on the protocol match, fall back to the verb-family list. Tests exercise the protocol-match path on `Complex` (`: Numeric`) plus the fallback path on user-types-without-conformance. ~half a day of code.
2. **Approximate-equality template arm for FP types.** Cycle 1 surfaces FP candidates with the kit-pointer advisory; cycle 2 could ship a real `KitFloatingPointTemplate` that emits `checkFloatingPointPropertyLaws(for: T.self, using: gen)` stubs directly. Already designed; ~1 day of code.
3. **Possible-tier sampling on the remaining ~358 surface.** Triage 20-30 round-trips + 20 idempotence + the FP commutativity/associativity survivors. With acceptance/rejection data, cycle 2 can confirm or reject the cycle-1 hypotheses about which templates over-fire.
4. **`surfacedAt` plumbing.** Unblocks PRD §17.2's time-to-adoption metric. ~half a day.
5. **Cross-target enum coverage** (M14 deferred bit) and **multi-predicate equivalence classes** (M13 axis 3) — both still SemanticIndex-blocked.

## Summary

Cycle 1 validated the calibration loop end-to-end and shipped two structural tunings + one explainability extension that drop the `--include-possible` surface by 69.3%. The minimum-scope triage data corroborates one cycle-2 hypothesis (operator-aware identity-element pairing). The most important narrative shift was reframing FP-storage suggestions from "noise to suppress" to "valid-given-finite-only-generator" — a calibration nuance that came from user domain context, not from data alone.

Cycle 2 has a clear priority list. Time to next cycle: aim for the v1.5 cut (~2-3 months).
