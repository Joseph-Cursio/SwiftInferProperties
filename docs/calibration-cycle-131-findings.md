# Calibration cycle 131 — C2 corpus widening (8 reducers / 16 identities)

> **STATUS: SHIPPED (no version bump — fixtures + durable test).** Widens the
> verify-ready real-TCA corpus from 6 → 8 reducers (13 → 16 idempotence
> identities), adding the two `.tca` *mechanisms* not yet exercised: the
> method-reference body form and an effect-bearing body. With these the
> corpus now spans the distinct verify mechanisms — further widening is
> volume, not new coverage. Captured 2026-06-15.

## What was added

- **`MethodRefFeature`** — body is `Reduce(handle)` (the method-REFERENCE
  form, "Finding I" / the kitlangton/Hex idiom) rather than the inline
  closure every other fixture uses. Exercises the second `.tca` discovery
  path (`emitCandidateForMethodRef`) end-to-end. `dismiss` witness → `bothPass`.
- **`EffectFeature`** — body returns real `Effect`s (`.run { … }`), not just
  `.none`. Exercises the verifier's effect-discard posture (PRD §16 #1): the
  Effect is captured and thrown away; only State is checked. Yields two
  witnesses — `close` (returns `.none`) and `refresh` (returns `.run`, state
  reset to a fixed value) — both `bothPass`, confirming idempotence is judged
  on State while the Effect is discarded.

(`refresh` is in the witness vocabulary — a detail the survey surfaced; the
corpus didn't have a `refresh`-named witness before, so it's incidental added
coverage of that verb.)

## Result

The detector now surfaces **16 idempotence identities → 14 `measured-bothPass`
+ 2 `measured-defaultFails`** (`setBadge`, `ToggleFeature.hide` — unchanged).

## Mechanism coverage is now broad — further widening is volume

The corpus now exercises the distinct verify mechanisms end-to-end on real
`@Reducer` shapes:

- **Discovery forms:** inline-closure `Reduce { … }` *and* method-reference
  `Reduce(handle)`.
- **Body effects:** `.none` *and* effect-bearing `.run { … }` (discarded).
- **Exploration:** Phase A (all-payload-free, full) *and* Phase B (mixed,
  partial) with 1- and 2-excluded disclosures.
- **Raw payloads in exploration:** `Int`, `String`.
- **Witness outcomes:** true positives; false positives caught by execution
  across *both* witness categories (`set*` prefix + exact).

Additional reducers from here would repeat these mechanisms with different
names/shapes — useful as regression breadth, but not new capability coverage.
Per the project's conservative posture, that's a deliberate stopping point:
widen further only when a genuinely new shape appears (e.g. a new raw payload
type, a composed `Scope`/`CombineReducers` body emitting multiple candidates,
or a new interaction family beyond idempotence).

## Verification

`TCAVerifyCorpusMeasuredTests` green (16 identities → 14/2; method-ref +
effect-bearing reducers verify; full reducers carry no disclosure; evidence
16/14/2; discover renders `(Verified)`). ~110s — amortized over the warm
shared workdir (cycle 129). `swiftlint` clean; fast suite unaffected.

## What's next

The `.tca` epic stays complete and its corpus now covers the mechanism
surface. Remaining genuinely-optional: C1's literal discovery-corpus
extractor (only if that number is ever required). Default idempotence stays
`.likely`; the other four interaction families stay `.possible` behind
`--include-possible`.
