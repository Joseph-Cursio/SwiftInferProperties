# Calibration cycle 133 — composed-body verify (dedup fix) + corpus widening

> **STATUS: SHIPPED (no version bump — fixtures + a small fix + durable
> test).** Closes the cycle-132 correctness gap: composed TCA bodies are now
> verifiable. The verify pin path dedups duplicate same-`qualifiedName`
> candidates before resolution (mirroring the discover path), so a composed
> `var body` (multiple `Reduce {}` closures, or `Reduce` + `Scope`) resolves
> instead of throwing `ambiguousPin`. Demonstrated end-to-end by three new
> corpus reducers. Captured 2026-06-15.

## The fix

`VerifyInteractionPipeline.resolveAndEmit` now collapses composed-body
duplicates before pin resolution:

```swift
let candidates = try ReducerDiscoverer.discover(directory: directory)
let deduped = SwiftInferCommand.DiscoverInteraction.dedupedByStateAndAction(candidates)
let matched = try resolveCandidate(candidates: deduped, pinRaw: pinRaw)
```

A composed body emits one candidate per `Reduce` closure (PRD §6.3), all
with the same `qualifiedName` / State / Action. Pre-133 the verify path
re-discovered without dedup → `resolveCandidate` saw ≥2 `Feature.body`
matches → `ambiguousPin` → the error-tolerant survey recorded
`measured-error`. The fix reuses the discover path's existing
`dedupedByStateAndAction` (first-seen wins; safe because the duplicates
share enclosing type / State / Action — all the verify invocation needs).
The deduped candidate verifies the *whole* composed body via
`Feature().reduce(into:&s, action:)`, the correct idempotence semantic.

## Corpus widening (8 → 11 reducers, 16 → 19 identities)

Three reducers added to `Tests/Fixtures/tca-verify-corpus/`:

- **`MultiReduceFeature`** — two `Reduce {}` closures (the isowords
  `Settings.body` shape). The end-to-end proof of the dedup fix:
  `.dismiss` → `bothPass` (pre-133 this was `measured-error`).
- **`ParentFeature`** — a `Scope(state:\.child, action:\.child) { ChildFeature() }`
  composition + its own `Reduce`. `.dismiss` → `bothPass` over the *whole*
  composed body; the `child(ChildFeature.Action)` case is Phase B
  non-derivable → excluded (`explored 2 of 3 action types (excluded: child)`).
- **`ChildFeature`** — the composed child, surveyed independently
  (`.close` → `bothPass`).

Survey now: **19 idempotence identities → 17 `measured-bothPass` + 2
`measured-defaultFails`** (`setBadge`, `ToggleFeature.hide` unchanged). All
three new witnesses pass.

## Verification

- **Fast:** `VerifyInteractionPipelineTests` +1 — `resolveAndEmit` on a
  two-`Reduce`-closure body resolves to the one composed reducer (no
  `ambiguousPin`) and emits a `Feature()` instance stub.
- **Measured (`.subprocess`):** `TCAVerifyCorpusMeasuredTests` green (19 →
  17/2; MultiReduce/Parent/Child verify; ParentFeature discloses
  `excluded: child`; evidence 19/17/2; discover renders `(Verified)`).
  ~130s, amortized over the cycle-129 warm shared workdir.
- `swiftlint` clean on the new files. (Known pre-existing: the
  `VerifyInteractionPipelineTests` struct is over `type_body_length` — it
  was before this cycle too; a file split is deferred as disproportionate.)

## What's next

The `.tca` epic now covers composed bodies. Remaining genuinely-optional:
C1's literal discovery-corpus extractor (only if that number is ever
required). Default idempotence stays `.likely`; the other four interaction
families stay `.possible` behind `--include-possible`.
