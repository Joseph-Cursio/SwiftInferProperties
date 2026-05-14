# v1.70 Calibration Cycle 67 — Findings (roadmap cleanup: the last two open items close)

Captured: 2026-05-14. swift-infer at v1.70.

## Headline

**Roadmap-completion cycle, not a measurement cycle.** v1.70 closes the
last two items on the v1.68/v1.69 "what's next" list — the `metrics`
per-corpus evidence join and V1.42.C.5 implicit reindex on demand. With
these landed, the documented roadmap is **empty**: the verify-evidence
consumer arc (v1.64–v1.68), the monotonicity-measurement arc (v1.69),
and the long-tail polish items (v1.70) are all done.

Cycle-66's **52/103 = 50.5% measured-execution** carries forward
unchanged — v1.70 touches no emitter, resolver, or carrier path.

## What shipped

### V1.70.A — `metrics --decisions` joins per-corpus verify evidence

V1.64.D's §17.2 verify-evidence cross-reference worked only in default
walk-up mode; explicit `--decisions <path>...` aggregation hard-coded
`evidence: .empty`, so the cross-reference table vanished whenever
`metrics` spanned multiple corpora (the calibration use case).

`loadExplicitPaths` now loads each `--decisions` file's sibling
`verify-evidence.json` — the on-disk `.swiftinfer/` layout pairs them —
and folds them via the new `VerifyEvidenceLog.merge`: identity-keyed,
later `capturedAt` wins, order-deterministic output, mirroring
`Decisions.merge`. A corpus with decisions but no verify run is normal,
so a missing sibling is skipped silently; a present-but-malformed
sibling still warns.

### V1.70.B — `verify` reindexes the SemanticIndex on demand (V1.42.C.5)

V1.42.C.5 — deferred since v1.42, **27 cycles** — was the implicit
reindex the `verify` help text had always promised but never wired:
`verify` threw `.indexMissing` on a cold checkout and only *warned* on
a stale index. The deferred blocker was hoisting `IndexCommand.run`'s
discover → project → upsert → save pipeline into a callable static.

Done: `IndexInputs` + `Index.performIndex` (returns the merged index +
a summary string; the caller picks the sink — `index` → stdout,
`verify` → stderr). `Verify.reindexIfNeeded` drives it before both
verify modes when the conventional `.swiftinfer/index.json` is missing
or stale.

Scope decisions (the design fork that kept C.5 deferred — "reindex
*what*?", given `verify`'s `--target` option was dead code and a
missing index gives nothing to infer from):

- **Whole-`Sources/` scan.** Sidesteps the `--target` chicken-and-egg
  entirely — `collectVisibleSuggestions` takes a directory, not a
  target. The index becomes a complete catalog of the package.
- **Explicit `--index-path` is used as-is** — never auto-rebuilt. The
  user pointed at a specific file.
- **A package with no `Sources/` is left alone** — the pre-V1.42.C.5
  `.indexMissing` / `.indexEmpty` path still applies. (This guard is
  also what preserves the existing no-index `VerifyCommandTests` case.)

## Why V1.42.C.5 sat for 27 cycles — and why now

It was never blocked or risky in principle — just lower-ROI than every
cycle's headline work (evidence persistence, tier promotion, grading,
consumer completion, the monotonicity rework) *and* it carried a real
design fork (the `--target` resolution problem) that no cycle had
budgeted the decision for. v1.70 is the first cycle with no
higher-value pick-closing or evidence-flow work competing for it: the
pick-closing surface is near-exhausted and the verify-evidence arc is
consumer-complete, so the long-tail item finally rose to the top of an
empty-ish queue. The fork resolved cleanly once stated plainly:
whole-`Sources/` scan, explicit-path-as-is.

## Test count

**2498 → 2512 (+14)** — `VerifyEvidenceLogMergeTests` (6),
`MetricsExplicitDecisionsEvidenceTests` (2, the first end-to-end
coverage of the previously-untested `loadExplicitPaths` path),
`VerifyReindexOnDemandTests` (6, covering `performIndex` + the four
`reindexIfNeeded` branches: missing → rebuild, fresh → no-op,
explicit-path → skip, no-`Sources/` → skip). §13 budgets unchanged.

## What's next (post-v1.70)

**The documented roadmap is empty.** The verify-evidence arc
(v1.64–v1.68) is consumer-complete; the monotonicity-measurement arc
(v1.69) lifted measured-execution past 50%; v1.70 closed the long-tail
polish. Candidate future directions, none currently scoped:

- **PRD §17.2's missing two metrics** — time-to-adoption and
  post-acceptance failure rate need new `DecisionRecord` fields (a
  schema-v3 bump), flagged as "v1.5+" since V1.4.1.
- **Kit-side deferrals** — `Ring` / `CommutativeGroup` / `Group acting
  on T`, still parked per `CLAUDE.md` "Kit-side coordination".
- **Incremental index analysis** — `swift-infer index` rebuilds from a
  full discover each run; PRD §20.1 mentions incremental as a future
  optimization, deferred until profiling shows it's needed.

## Artifacts

- v1.70 source: `Sources/SwiftInferCore/VerifyEvidence.swift`
  (`VerifyEvidenceLog.merge`), `Sources/SwiftInferCLI/MetricsCommand.swift`
  (per-corpus join), `Sources/SwiftInferCLI/IndexCommand.swift`
  (`performIndex` extraction), `Sources/SwiftInferCLI/VerifyCommand+Reindex.swift`
  (`reindexIfNeeded`).
- Prior cycle: `docs/calibration-cycle-66-findings.md` (v1.69
  monotonicity-emitter rework).
