# Calibration cycle 113 — CLI corpus packaging (the campaign loop closes end-to-end)

> **STATUS: SHIPPED (v1.120.0).** The last A1-campaign infrastructure
> item. New `CorpusPackager` wraps loose reducer sources into a standalone,
> module-named SwiftPM package so `verify-interaction` can build + run a
> measured survey over them. Capstone proof: a packaged idempotence corpus
> runs the **full loop** — package → discover (`.likely`) → verify
> (`measured-bothPass`) → evidence → discover (`.verified`) — proving an
> idempotence identity promoted by *executed* evidence, not re-triage.
> Captured 2026-06-14.

## Context

Cycles 110/111/112 made interaction measured execution run from the CLI,
persist its outcome, and consume it (`.likely → .verified` on bothPass).
The one remaining A1 item (named since cycle 110): the discovery corpora
are loose `Sources/<Module>/` directories with no manifest, so
`verify-interaction` — which references the user corpus as a SwiftPM
**path dependency** and builds it — couldn't run over them.

## Key finding — packaging is necessary but not sufficient; the corpora aren't verify-ready

While scoping, two constraints surfaced that shape what "packaging" means:

1. **Path-dep identity = directory name.** SwiftPM derives a path
   dependency's package identity from the root directory's last path
   component, *not* the manifest `name:`. The synthesized verifier
   references the corpus by module name, so the package-root dir must be
   named after the module (the same wrinkle the cycle-110 IDemo test hit).
2. **The verify stub requires a specific reducer shape.** It builds the
   action generator via `forCaseIterable: Action.self` and the idempotence
   check asserts `reduce(reduce(s, a), a) == reduce(s, a)` — so a
   verifiable reducer needs a **`CaseIterable` `Action`** (no associated
   values), an **`Equatable`, zero-arg-constructible `State`**, and a
   genuinely idempotent witnessed action. Most existing corpus reducers
   (e.g. `SettingsReducer.Action` carries `setColor(String)`) don't satisfy
   this — which is why measured execution sits at 50.5%. "Packaging the
   corpus" therefore pairs a package-synthesis step with a verify-ready
   source shape.

## What shipped

**1. `CorpusPackager` (SwiftInferCLI).** `package(moduleName:sourceFiles:into:)`
scaffolds `<destinationParent>/<moduleName>/` with:
- a module-named root directory (path-dep identity invariant),
- a `Package.swift` exposing `library(name: <module>, targets: [<module>])`
  → `target(name: <module>)` (so the workdir's path dep resolves a
  product), and
- the sources under `Sources/<module>/`.

A `fromSourcesDirectory:` convenience reads a loose corpus dir's top-level
`.swift` files (sorted, `.swift`-only — nested asset / plist dirs the TCA
corpora carry are skipped, not copied). Dependency-free corpora only this
cycle; a `dependencies:` thread for the TCA corpora is a noted follow-up.

**2. A verify-ready idempotence corpus + the capstone proof.** The
integration test packages two verify-ready reducers (`CounterReducer`,
`SettingsReducer` — `CaseIterable` actions, zero-arg `State` inits) and
drives the whole campaign loop.

## Verification

- **Unit (`CorpusPackagerTests`, 3, fast):** module-named root +
  library-product manifest; `fromSourcesDirectory` filters to `.swift`
  (skips `Info.plist`); empty module / empty source list rejected.
- **End-to-end (`IdempotenceCorpusMeasuredTests`, 1, `.subprocess`, ~20s):**
  package → `discover-interaction` surfaces the `CounterReducer .refresh`
  idempotence identity at `.likely` → `verify-interaction` returns
  `measured-bothPass` (and records evidence) → `discover-interaction`
  re-reads the evidence and renders the identity `(Verified)` with the
  `bothPass` why-line. This single test exercises cycles 110+111+112+113
  together.
- **Suites:** full fast suite green (3182 tests; only the known §13
  perf-budget timing flakes under load). SwiftLint clean.
- **Fast-path note updated** — `IdempotenceCorpusMeasuredTests` joins the
  documented `--skip` list (it spawns a real build).

## What's next — the measured idempotence survey

The infrastructure is complete: corpora can be packaged, verified,
recorded, and consumed. The campaign itself is now mechanical:

1. **Make the verify-ready subset real.** Either curate / shape-normalize
   the ~39 idempotence identities into `CaseIterable`-action form, or run
   over the reducers that already satisfy the shape and log the rest as
   `architectural-coverage-pending` (no silent drop).
2. **Survey.** `verify-interaction` over the packaged idempotence corpus,
   harvesting `.measuredBothPass` / `.measuredDefaultFails` into
   `verify-evidence.json`.
3. **Promote on execution.** `discover-interaction` surfaces survivors at
   `.verified`, drops the disproven — `.strong`/`.verified` gated on
   measured execution, across the documented three calibration cycles.

A natural follow-up mechanism is a `verify-interaction --all` survey mode
(batch over every discovered idempotence identity in a target) so the
survey is one command, not 39. **Default (no-evidence) idempotence stays
`.likely`** until the measured run lands.
