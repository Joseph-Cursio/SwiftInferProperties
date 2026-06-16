# Calibration cycle 145 — code-health cleanup (zero SwiftLint warnings)

**Captured 2026-06-16.** No binary change — test-only refactor + rename.
Sweeps the two outstanding SwiftLint warnings (one deferred since cycle 133)
so `swiftlint lint --quiet` is silent across the whole project.

## What shipped

1. **`type_body_length` — `VerifyInteractionPipelineTests` (deferred c133).**
   The struct body was 316 lines (cap 250). Split by closing the struct
   after the `resolveCandidate` tests and reopening the end-to-end
   `resolveAndEmit` group (6 `@Test`s + the `makeFixtureDirectory` /
   `writeFile` fixture helpers they exclusively use) as a **same-file
   `extension VerifyInteractionPipelineTests`**. `@Test` methods in an
   extension of the `@Suite` type stay in the suite, and SwiftLint's
   `type_body_length` exempts extension bodies — so the fix needs no new
   file, no visibility change (the `private` helpers travel with their only
   users), and no behavior change. Confirmed: the suite still reports **16
   tests** in one suite.

2. **`type_name` — `MeasuredPromotionDeterminismMeasuredTests` (41 > 40).**
   Renamed to **`PromotionDeterminismMeasuredTests`** (33 chars), dropping
   the redundant leading `Measured` while keeping the load-bearing
   `…MeasuredTests` suffix (the fast-path skip regex + Makefile batch
   filters key on it). Updated: the file name, the struct, `Makefile`
   `BATCH4`, and the two doc cross-references (the sibling fast suite's
   doc-comment + the cycle-118 entry in CLAUDE.md). Confirmed: runs green
   under the new name and is still skipped by the fast path / matched by
   `make batch4`.

## Verification

- `swiftlint lint --quiet` — **silent** (whole project; was 2 warnings).
- `make test-fast` — 3200 tests / 429 suites pass (~6s); compiles the
  renamed file and exercises the split suite + the fast determinism tests.
- `swift test --filter 'PromotionDeterminismMeasuredTests'` — green under
  the new name (~91s subprocess).

## What's next

Unchanged and off the critical path: the frozen 50.5% measured-execution
rate (blocked by non-promotable nested-action composition + non-compilable
discovery corpora — scoped c119/121/126), the shelved value-generator
(c119), and the `.tca` C1 reducer-slice-extractor (c126). The
measured-verify epic remains complete; this cycle was pure hygiene.
