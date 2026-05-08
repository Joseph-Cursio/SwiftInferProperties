# v1.8 Calibration Cycle 5 — Findings

Captured: 2026-05-08. swift-infer at `416d619` (V1.8.1 — shape-gated Codable veto). The fifth execution of PRD §17.3's empirical-tuning loop and the **first non-monotonic cycle** in the calibration trajectory.

This document is the cycle-5 record: what we ran, what we learned, what shipped, what's deferred. Cycle 6 reads this to decide where to perturb next.

## Headline

**Cycle 5 shipped one structural rule: shape-gated Codable veto on the round-trip template.** V1.8.1 narrows V1.5.2's `RoundTripTemplate.protocolCoverageVeto(...)` to fire only when the pair's forward/reverse signatures actually match a Codable encoder/decoder shape (`(T) -> Codec` ↔ `(Codec) -> T` for `Codec ∈ {Data, String}`, with `T` not itself a codec). User-defined inverse pairs on Codable carriers (`(Int) -> Int`, `(Double) -> Double`, `(UInt64) -> Int?`) fall through unsuppressed because they're *not* Codable round-trips by intent.

| Tuning | Type | Where | Empirical effect |
|---|---|---|---|
| `RoundTripTemplate.codableRoundTrippedType(for:)` shape gate (V1.8.1) | structural narrowing | `RoundTripTemplate.protocolCoverageVeto(...)` | **+23 re-emergences** (22 OrderedCollections + 1 Algorithms); 0 ComplexModule + 0 PropertyLawKit |

After v1.8: total `--include-possible` surface across the 4 corpora went **326 → 349** (+23, +7.0%). All 23 re-emergences are on the round-trip template; the 22 OrderedCollections re-emergences match the V1.7.1 suppression set exactly (21 `(Int) -> Int` HashTable / OrderedDictionary index pairs + 1 `(UInt64) -> Int?` _value/_bucketContents pair); the 1 Algorithms re-emergence is the `(Double) -> Double` pair V1.7.1's `Double: Codable` bake-in had suppressed.

**Cycle 5 is the first cycle to *increase* the surface count** — every prior cycle decreased it (1167 → 326 over cycles 1–4). The trajectory framing isn't "more is bad" — V1.7.1 unintentionally over-suppressed, V1.8.1 corrects that. The cumulative reduction across cycles 1–5 stands at **1167 → 349 (−70.1%)** over four calibration cycles.

## Corpus selection

Same four cycle-1+2+3+4 targets — re-running on the cycle-4 baseline gives clean V1.8.1 attribution (only one structural change between captures):

| Corpus | Target | Cycle-4 post-bakein total | Cycle-5 post-tightening total | Δ |
|---|---|---:|---:|---:|
| swift-collections | OrderedCollections | 79 | 101 | **+22** |
| swift-algorithms | Algorithms | 74 | 75 | **+1** |
| swift-numerics | ComplexModule | 166 | 166 | 0 |
| SwiftPropertyLaws | PropertyLawKit | 7 | 7 | 0 |
| **Total** | | **326** | **349** | **+23 (+7.0%)** |

Per-corpus pre/post snapshots committed to `docs/calibration-cycle-5-data/post-tightening-*.discover.txt`. Diff target is `docs/calibration-cycle-4-data/post-bakein-*.discover.txt`.

## What v1.8 ships (the mechanism)

One piece, in `Sources/SwiftInferTemplates/RoundTripCodableShapeGate.swift`:

- **A `RoundTripTemplate.codableRoundTrippedType(for:)` private static helper.** Returns the round-tripped type `T` when the pair has shape `(T) -> Codec` ↔ `(Codec) -> T` for `Codec ∈ {Data, String}`, AND `T` is itself a non-codec type. Returns `nil` otherwise — `(T) -> T` user-inverse pairs and `(T) -> U` non-codec pairs both fall through.
- **A 2-element curated `codableCodecFormats: Set<String>` set.** Just `{Data, String}` — the two formats Swift's `JSONEncoder` / `PropertyListEncoder` / `JSONDecoder` family produces and consumes. `[UInt8]` (raw byte array), custom typealiases, tuple wire formats deferred until cycle-6 sampling reveals a corpus example.
- **`RoundTripTemplate.protocolCoverageVeto(...)` gates the existing `coverageVetoSignal(...)` call on the helper.** When the gate returns `nil`, the veto is skipped entirely. No other template-side scoring changes.

The mechanism reuses V1.5.2's `coverageVetoSignal(...)` directly. No new `Signal.Kind`, no new `KnownProperty`, no template-side scoring changes outside `RoundTripTemplate`.

## Per-corpus re-emergence breakdown

### swift-collections / OrderedCollections — the headline

| Template | Cycle-4 | Cycle-5 | Δ | Notes |
|---|---:|---:|---:|---|
| **round-trip** | **3** | **25** | **+22** | All re-emergences on stdlib-typed `(Int) -> Int` / `(UInt64) -> Int?` pairs; matches V1.7.1 suppression set exactly. |
| idempotence | 27 | 27 | 0 | Unaffected — different template. |
| monotonicity | 20 | 20 | 0 | Unaffected. |
| commutativity | 10 | 10 | 0 | Unaffected. |
| associativity | 10 | 10 | 0 | Unaffected. |
| inverse-pair | 9 | 9 | 0 | Unaffected. |

Concrete re-emerged pairs (sample):

```
[Cycle-5] (Int) -> Int round-trip pairs (all 21 surfaced):
  minimumCapacity(forScale:) ↔ maximumCapacity(forScale:)
  minimumCapacity(forScale:) ↔ scale(forCapacity:)
  minimumCapacity(forScale:) ↔ wordCount(forScale:)
  ...12 more HashTable+Constants / OrderedDictionary / OrderedSet pairs...
  word(after:) ↔ word(before:)
  index(after:) ↔ index(before:)  [7 distinct sites]

[Cycle-5] (UInt64) -> Int? round-trip pair (surfaced):
  _value(forBucketContents:) ↔ _bucketContents(for:)
```

Each lands at Score 30 (Possible tier — type-symmetry alone, no curated name bonus). They're available for `--include-possible` triage.

The 3 cycle-4 surviving round-trips on user types (`(Bucket) -> Bucket`, 2× `(Self) -> Self`) carry through unchanged.

### swift-algorithms / Algorithms

| Template | Cycle-4 | Cycle-5 | Δ | Notes |
|---|---:|---:|---:|---|
| **round-trip** | **19** | **20** | **+1** | The cycle-4 V1.7.1-suppressed `(Double) -> Double` pair re-emerged; 19 cycle-4 surviving `(Index) -> Index` / `(Base.Index) -> Base.Index` carry through. |
| idempotence | 44 | 44 | 0 | |
| inverse-pair | 6 | 6 | 0 | |
| monotonicity | 3 | 3 | 0 | |
| commutativity | 1 | 1 | 0 | |
| associativity | 1 | 1 | 0 | |

### swift-numerics / ComplexModule

Byte-identical to cycle-4. Confirmed via `diff` of cycle-4 vs cycle-5 snapshots — both produce the same 166 suggestions in the same order. ComplexModule's 136 round-trip pairs are on user / generic types whose textual signatures don't fit V1.5.2's old per-type lookup *or* V1.8.1's new shape gate. The mechanisms target different cause-of-noise classes.

### SwiftPropertyLaws / PropertyLawKit

Byte-identical to cycle-4. PropertyLawKit's 7-suggestion floor reflects monotonicity + idempotence on kit-internal types; no round-trip suggestions in either cycle.

## Trajectory across all 5 cycles — the calibration arc

| Cycle | Mechanism | Surface | Δ from prior | Cumulative Δ |
|---|---|---:|---:|---:|
| 1 (pre-tune) | none | 1167 | — | — |
| 1 (post-tune) | V1.4.3 FP-storage + cross-type counter-signals | 358 | −809 | −69.3% |
| 2 (V1.5.2) | textual-only protocol-coverage suppression | 353 | −5 | −69.7% |
| 3 (V1.6.1) | identity-element pair-formation skip-list | 350 | −3 | −70.0% |
| 4 (V1.7.1) | stdlib-conformance bake-in | 326 | −24 | −72.1% |
| 5 (V1.8.1) | shape-gated Codable veto on round-trip | **349** | **+23** | −70.1% |

V1.8.1 is intentionally an *un-suppression* — it narrows V1.5.2's existing rule to fire only when the kit law actually applies. The surface count goes up because V1.7.1's bake-in had unintentionally widened V1.5.2's reach to suppress 23 user-defined inverse pairs that the kit's `checkCodablePropertyLaws` doesn't verify. V1.8.1 hands those 23 back to the user as Possible-tier surface for triage.

This framing matters for the §17.3 calibration loop: **monotonic surface reduction isn't the goal** — *appropriate* suppression is. Cycle-5's positive delta closes a known design issue cleanly. The five mechanisms compose:

- **V1.4.3** — cross-type round-trip noise suppressed at scoring (counter-signal).
- **V1.5.2** — kit-covered properties suppressed at scoring (full veto).
- **V1.6.1** — identity-element cross-product mismatches suppressed at pair-formation.
- **V1.7.1** — V1.5.2's reach extended to stdlib carriers.
- **V1.8.1** — V1.5.2's round-trip arm narrowed to fire only on Codable encoder/decoder shapes (correcting V1.7.1's over-reach).

## What v1.8 demonstrates

The cycle-4 findings doc framed V1.8.1 as the closure of an inherited V1.5.2 design question. Cycle 5 confirms this empirically:

- **The over-suppression hypothesis bore out exactly.** The cycle-4 findings predicted "most of the 23 V1.7.1 suppressions become surfaced again." The actual re-emergence is **exactly 23** — 22 OrderedCollections + 1 Algorithms — matching the cycle-4 V1.7.1 suppression count precisely.
- **The shape gate's specificity bore out.** ComplexModule's existing 136 round-trip suggestions stayed at 136, and `(Doc) -> Data` ↔ `(Data) -> Doc` Codable shapes still get suppressed in the test fixtures. The gate fires specifically on (T)→Codec / (Codec)→T patterns, leaving everything else alone.
- **The compositional-mechanism story holds.** V1.8.1 doesn't undo V1.7.1's bake-in; it narrows V1.5.2's veto so the bake-in only fires when the kit law applies. Both rules are still in-tree and still fire — V1.7.1 still resolves stdlib types' conformances; V1.5.2 still covers kit-shaped properties. V1.8.1 just adds a precondition on the round-trip arm.

## Plan-vs-actual: the projection landed

The v1.8 plan f-bullet predicted: "OrderedCollections re-emerges 22 round-trip suggestions (79 → ~101); Algorithms re-emerges 1 (74 → ~75); ComplexModule + PropertyLawKit unchanged."

**Actual outcome (point-for-point):**
- OrderedCollections: 79 → **101** (+22). ✓ exact.
- Algorithms: 74 → **75** (+1). ✓ exact.
- ComplexModule: 166 → 166 (0). ✓ exact.
- PropertyLawKit: 7 → 7 (0). ✓ exact.

This is the first calibration cycle where the plan's projection landed exactly as written. Methodology lesson: when the prior cycle has clean attribution data (V1.7.1's −24 split into −1 V1.6.1.1 + −23 V1.7.1, with named per-corpus targets), the next cycle's projection has a tight prior to build on. Earlier cycles' projections were aspirational; cycle-5's was design-bound.

## Methodology gaps

**SuggestionIdentity continuity question.** The 23 re-emerged suggestions land at the same M1.4 SuggestionIdentity hash as their cycle-3 (pre-V1.7.1) appearance — same canonical signatures sorted lexicographically, same template name `round-trip`. So any pre-V1.7.1 user Decision (accept/reject) on these 23 *should* still match. But cycle-5 didn't run a Decisions-replay verification because no published .swiftinfer/decisions.json corpus has cycle-5-relevant entries. Cycle-6 priority candidate (small): synthesize a 23-entry Decisions fixture at the cycle-3 commit and confirm the cycle-5 binary applies them correctly.

**Possible-tier sampling on the post-V1.8 surface (349 across 4 corpora) still pending.** Carries forward from cycles 2+3+4. With cycle-5's V1.8.1 having corrected the V1.7.1 over-suppression, the 349-surface is now genuinely tractable for sampling — the pairs in the surface are claims SwiftInfer would surface to a user, with no known false-suppression bug. Cycle-6 priority territory.

**`surfacedAt` plumbing still pending.** Carries forward from cycle-1.

**Single-runner triage carryover.** Same gap from cycles 1–4 carries forward unchanged. v1.8 ships zero new triage decisions (mechanism-only change).

**Curated codec set narrowness.** v1.8 includes only `{Data, String}`. Real-world Swift Codable codepaths sometimes wrap to `[UInt8]` or domain-specific types. Cycle-6 sampling on the 349-surface should reveal whether any over-suppressed-by-narrowness cases need a broader set; the v1.8 plan open-decision #2 explicitly defers broadening until cycle-6 has empirical evidence.

## Cycle-6 priority list (in expected impact order)

1. **Possible-tier sampling on the post-v1.8 surface (349 across 4 corpora).** *(NEW priority #1; previously deferred from cycles 2-3-4 priority #4.)* The headline cycle-6 item. Triage 20-30 round-trips (the re-emerged ones plus some ComplexModule pairs) + 10-20 idempotence + 10 monotonicity / inverse-pair survivors. **Now empirically tractable** because cycle-5 closed the V1.5.2 over-suppression — the 349-surface no longer contains a known false-suppression bug. Closes the loop on cycles 1-2-3-4-5 hypotheses with accept/reject data. Expected outcome: per-template acceptance rates that inform cycle-6+ scoring weight tuning.

2. **Approximate-equality template arm for FP types.** *(Carried forward from cycle-2+3+4 priority #2/#3.)* Real `KitFloatingPointTemplate` emitting `checkFloatingPointPropertyLaws(for: T.self, using: gen)` stubs. Synergy with v1.8: now that `Float`/`Double` are in V1.7.1's bake-in with full conformance set AND V1.8.1's gate spares user-defined `(Double) -> Double` inverse pairs, FP-conforming-but-not-kit-checked types are the natural template-arm target. ~1 day.

3. **Curated math-library op-name extension to round-trip / inverse-pair.** *(Carried forward from cycle-4 priority #5.)* Closes the cycle-3 ComplexModule survivor (`(zero, rescaledDivide)` × `Complex.zero`) and similar user-named-op patterns. ~1 hour.

4. **`surfacedAt` plumbing.** *(Carried forward from cycle-1 priority #4.)* Unblocks PRD §17.2's time-to-adoption metric. ~half a day.

5. **Codec set broadening (cycle-6 sampling-driven).** If cycle-6 sampling reveals over-suppressed-by-narrowness cases, broaden V1.8.1's `codableCodecFormats: {Data, String}` set to include `[UInt8]` and/or the corpus-specific codec types. ~30 min once the sampling provides evidence. Leave at narrow for now.

6. **SuggestionIdentity continuity verification fixture.** *(NEW from cycle-5 methodology gap.)* Synthesize a 23-entry Decisions JSON at the cycle-3 commit and confirm the cycle-5 binary's identity hash matches for each re-emerged suggestion. ~1 hour. Forensic confidence-builder for downstream Decisions-replay scenarios.

7. **SemanticIndex.** *(Carried forward; multi-cycle effort. PRD §20 v1.1+.)* Resolves type conformances authoritatively. v1.8's shape gate is a textual approximation; SemanticIndex would validate `T: Codable` against the actual conformance graph, dispense with the curated codec set, and lift the textual-only-coverage limit on user types whose Codable conformance comes from typealias or conditional-conformance routes.

## Summary

Cycle 5 shipped one structural rule: a shape-gated `RoundTripTemplate.protocolCoverageVeto(...)` (V1.8.1). The empirical effect was +23 of 326 surfaced suggestions (+7.0% aggregate; the first non-monotonic cycle in the calibration trajectory), with the +23 split as +22 OrderedCollections + +1 Algorithms — exactly matching the cycle-4 V1.7.1 suppression set.

The cycle-5 outcome closes the inherited V1.5.2 design question that cycle-4's V1.7.1 bake-in had surfaced: V1.5.2's unconditional `[codableRoundTrip]` veto on round-trip pairs was over-broad; V1.8.1 narrows it to fire only on Codable encoder/decoder shapes. The 23 user-defined inverse pairs the kit doesn't verify (HashTable index pairs, OrderedDictionary capacity-cross-product, the swift-algorithms Double pair) are now correctly surfaced for human triage at Possible tier.

The cumulative trajectory across cycles 1–5 stands at **1167 → 349 (−70.1%)** over four calibration cycles with five compositional mechanisms (V1.4.3 cross-type counter-signals, V1.5.2 coverage veto, V1.6.1 pair-formation filter, V1.7.1 stdlib bake-in, V1.8.1 shape-gated round-trip veto). The non-monotonic dip from −72.1% (cycle-4) to −70.1% (cycle-5) is the calibration loop *correcting itself* — and is the right outcome.

Cycle 6 has a concrete priority list with one ~1-day empirical sampling item (post-V1.8 Possible-tier triage, the headline cycle-6 deliverable now that the surface is tractable), one ~1-day FP-template-arm item, and three small mechanical items (math-library op extension to non-identity templates, surfacedAt plumbing, SuggestionIdentity continuity fixture). After cycle 6, the §19 acceptance-rate target should be measurable on a meaningfully-narrowed *and validated* surface.
