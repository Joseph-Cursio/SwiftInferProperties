# SwiftInferProperties — v1.50 Performance Baseline (Phase 2 opening)

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-12 against the V1.50.G commit. **v1.50 opens
Phase 2** — first full-coverage verify measurement against the
cycle-27 109-pick surface. The cycle pivots from architecture-building
(v1.42–v1.49) to measurement-instrumentation. No new emitter,
template, strategy, or resolver.

**Discover-pipeline impact: none.** v1.50 introduces zero discover-
side changes. The §13 discover budgets (1s / 2s / 6s for the 10 /
50 / 100 test-file synthetic corpora; 800 MB peak-delta for the
500-file corpus) are unchanged from v1.41–v1.49.

**Test-suite measurement (non-subprocess fast path):** **2363 tests**
passing across **325 suites** in **~4 seconds** when running
`swift test --skip VerifyPipelineIntegrationTests` (the CI command
pattern v1.49.D established). v1.49's 21 subprocess integration
tests are still always-on under the default `swift test`, so the
full default suite still runs ~210s.

New tests since v1.49: +7 in `VerifyAllFromIndexTests` (V1.50.E) +
1 V1.42.B test reworked (`suggestionOptionalAtParseTime` updated
from `suggestionRequired` after V1.50.B made `--suggestion`
optional). Test count 2393 → 2400 (+7 net).

**Per-survey-run cost (V1.50.B):** **~3 minutes** wall-clock for
the full 109-pick survey via `swift-infer verify --all-from-index
--max-parallel 4` against the V1.50.A fixture. Every pick errors
at carrier/pair/template resolution before reaching `swift build`,
so the measured cost is the in-process parse + classify time, not
the SwiftPM-resolve cost. **Future cycles' surveys with closed
measurement-tooling gaps** (v1.51+) will see the cost climb to
~30-60 minutes as picks reach `swift build` — that's the expected
cycle-48 cost trajectory.

**Per-verify-call cost (single suggestion):** **~13s cold**
(unchanged from v1.43–v1.49). The new `--all-from-index` flag is
orthogonal to the single-suggestion path; `verify --suggestion
<hash>` continues to operate exactly as in v1.49.

**§13 budget compliance:** all v1.41–v1.49 measurements hold.
v1.50 added no new subprocess integration tests; the V1.50.E unit
tests are pure-Swift parse-and-encode coverage that runs in
microseconds.

**Survey wall-clock model:**
- `--max-parallel 4` (default): ~3 min for the 109-pick cycle-27
  fixture when all picks fail at resolution time.
- Projected v1.51+ scaling: when picks reach `swift build`, expect
  ~15s × (picks / parallelism) wall-clock. 109 picks at 4-parallel
  = ~7 minutes per full-surface survey.
- macOS file-descriptor soft limit (256) caps practical parallelism
  at ~8 concurrent SwiftPM builds. Higher --max-parallel surfaces
  build-time FD-limit errors before saturating cores.

**Phase 2 opening summary**: 109-pick cycle-27 surface reconstructed
from 4 source packages via the V1.50.A fixture; `verify
--all-from-index` lands as the canonical survey driver with a
5-category classification scheme; first measurement at 0/109
measured-execution honestly records the measurement-tooling gap
between discover-side carrier names and verify-side expectations.
v1.51+ closes the gap with bare→qualified carrier normalization +
dual-style curated-list expansion + monotonicity-on-Double routing.

v1.50 baseline is the Phase 2 opening reference point.
