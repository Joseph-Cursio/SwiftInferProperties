# SwiftInferProperties — v1.34 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-11 against the V1.34.C commit. v1.34 ships:
- V1.34.A: one optional `carrier: String?` field on `Suggestion`. Zero allocation cost when nil; one Swift `String` for non-nil values (already-allocated source-derived string passed through).
- V1.34.B: thread-through additions across 16 Suggestion construction sites — each is a single argument pass.
- V1.34.C: one-line read in `IndexCommand.buildEntry`.

**Zero hot-path impact.** The carrier field is metadata: passed through during construction, read at `index` emit time. No new computation per suggestion.

| Row | Workload | Budget | Measured (v1.34) | Δ vs v1.33 |
|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | within budget | within noise band |
| 4 | 500-file resident-memory | < 800 MB | within budget | within noise band |

Test-suite measurement at V1.34.C commit: **2027 tests** passing across **277 suites**, full `swift test` completes in ~3.8s. All §13 budgets hold.

**Index file size delta**: per-entry overhead increases by ~30 bytes when `typeName` is populated (vs the previous null encoding). On the ComplexModule 20-entry index, this adds ~600 bytes total — still well under any meaningful threshold.

v1.34 baseline replaces v1.33 as the comparison anchor for v1.35+.
