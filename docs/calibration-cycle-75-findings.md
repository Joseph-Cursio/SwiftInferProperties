# v1.78 Calibration Cycle 75 — Findings (V2.0.M3.E: workdir + build/run loop)

Captured: 2026-05-15. swift-infer at v1.78. SwiftPropertyLaws at v2.2.0 (local, still unpushed).

## Headline

**M3 is consumer-complete.** v1.77 shipped M3.0's orchestration +
stub emission; v1.78 ships **M3.E** — the workdir / build / run /
parse / render layer that turns M3.B's emitted Swift source into a
v1.42-shape five-category outcome.

Three sub-cycles deliver the layer:

- **M3.E.2** — `VerifierWorkdir` gains a `WorkdirMode` (`.algebraic` /
  `.interaction`) and branches the `Package.swift` dep blocks
  accordingly. `.interaction` mode declares v2.2.0 kit + PropertyLawKit;
  `.algebraic` mode preserves v1.42's existing shape unchanged.
- **M3.E.3** — `InteractionVerifyOutcomeParser` scans the verifier
  subprocess's exit code + stdout into a `VerifyEvidenceOutcome`:
  `bothPass` (clean exit + marker line), `defaultFails` (non-zero
  exit from the verifier — a reducer trap), `measuredError` (clean
  exit, no marker), `architecturalCoveragePending` (build failure).
- **M3.E.4** — Pipeline split into pure `resolveAndEmit` (used by
  unit tests) and full `runPipeline` (used by CLI). The CLI now
  invokes the workdir/build/run loop directly; the M3.C "pending
  harness" rendering is gone.

Cycle-66's **52/103 = 50.5% measured-execution** carries forward
unchanged — v1.78 still touches no v1 emitter / resolver / carrier
path.

## The remaining gate: kit-tag publication

The repo's `Package.swift` pin **still stays at `from: "2.1.0"`**
this cycle. SwiftPM resolves dependencies from the remote
`github.com/Joseph-Cursio/SwiftPropertyLaws`, where v2.2.0 has not
yet been pushed (confirmed via `git ls-remote --tags`). Bumping
the pin now would break the build.

What this means for M3.E in practice:

- **All code paths compile and execute through `swift build` /
  `swift run swift-infer verify-interaction`.** The user CLI works.
- **The synthesized workdir's own `swift build` step fails** when
  the user actually runs verify-interaction against a real target,
  because the workdir's `Package.swift` declares
  `SwiftPropertyLaws@2.2.0` and SwiftPM can't fetch a tag that
  doesn't exist on remote.
- **The outcome rendering** surfaces this as
  `.architecturalCoveragePending` with the swift-build stderr in the
  detail — the user sees a clear "couldn't fetch kit version 2.2.0"
  error and the next-action is obvious.

**Next-action (carried from cycles 73 + 74):**

```bash
cd ../SwiftPropertyLaws
git push origin main
git push origin v2.2.0
```

After the push, no repo-side code change is needed for users to
get working interaction verify — the workdir's pin is at v2.2.0
already; SwiftPM will resolve the now-published tag the next time
the user runs `verify-interaction`.

The repo's own `Package.swift` pin bump to v2.2.0 is a separate
ship (purely additive; can land any time post-publication). It's
not strictly required for M3.E to function — the repo itself
doesn't import the new ActionSequenceFactory / PropertyLawKit
surface; only the synthesized workdir does.

## What M3.E adds to the verify-interaction flow

```
swift-infer verify-interaction --target MyApp [--reducer Inbox.body]
  │
  ├─ ReducerDiscoverer.discover(directory: Sources/MyApp)       (M1)
  ├─ ReducerPin.parse + filter                                  (M1.C)
  ├─ ActionSequenceStubEmitter.emit                             (M3.B)
  │
  │   v1.78 (M3.E) adds everything below this line
  │
  ├─ VerifierWorkdir.synthesize(mode: .interaction)             (M3.E.2)
  ├─ VerifierSubprocess.runSwiftBuild
  │     └─ if exit ≠ 0 → InteractionVerifyOutcomeParser
  │         .parseBuildFailure → .architecturalCoveragePending
  ├─ VerifierSubprocess.runVerifierBinary
  │     └─ InteractionVerifyOutcomeParser.parseRunOutput          (M3.E.3)
  └─ renderOutcome in v1.42 five-category format                (M3.E.4)
```

The synthesized workdir lives at
`<packageRoot>/.swiftinfer/verify-interaction-workdir/<reducer-id>/`
— sibling to v1.42's `.swiftinfer/verify-workdir/<hash>/`. Each
reducer gets its own subdirectory keyed on the qualified name with
`.` → `_` (filename-safe).

## Outcome-mapping table (final)

| Subprocess result | Outcome | When this fires |
|---|---|---|
| exit 0 + `INTERACTION-VERIFY-OUTCOME: bothPass totalRuns=N clean=N` | `.measuredBothPass` | Happy path — every sequence ran without trapping |
| exit ≠ 0 from verifier binary | `.measuredDefaultFails` | A sequence triggered a Swift trap (force-unwrap, array-out-of-bounds, fatalError) |
| exit 0 but no marker line | `.measuredError` | Stub ran but didn't emit the expected outcome — version skew or stub bug |
| exit ≠ 0 from `swift build` | `.architecturalCoveragePending` | Couldn't compile the synthesized stub — typically missing State `init()`, non-`CaseIterable` Action, OR the kit pin v2.2.0 can't be resolved (current gate) |

`.measuredEdgeCaseAdvisory` is intentionally unused at M3 — curated
edge-case action sequences ship at M5+.

## Architectural choices baked into M3.E

**1. Workdir refactor approach: parametrize rather than fork.**
`VerifierWorkdir` gained a `WorkdirMode` enum + a `mode` field on
`Inputs` (defaulting to `.algebraic`). The two dep-block helpers
branch on the mode. v1.42 callers don't change — they get the
default. Trade-off: the two branches embed slightly duplicated
dependency lists, but extracting a shared abstraction would obscure
the fact that algebraic and interaction modes deliberately import
different kit surfaces.

**2. Pipeline split: `resolveAndEmit` + `runPipeline`.** Existing
M3.C orchestration tests don't want to spin up subprocess builds.
Split: `resolveAndEmit` (no I/O beyond the source-tree walk) +
`runPipeline` (full subprocess loop). The unit-test suite covers
the pure leg; an integration test would cover the full path —
deferred until the kit publishes (no point running it against the
gated kit pin).

**3. UserPackageReference convention.** M3.E uses the simplest
shape: `packageDeclaredName == userModuleName` (default: `--target`)
and `productNames == [userModuleName]`. Matches the most common
case (one library product named the same as the package). If
calibration shows mismatches, a `--user-package-name` /
`--user-product` flag joins later.

## What's deferred (still out of M3.E)

- **Integration test against a real fixture user-package.** Would
  exercise the full subprocess loop end-to-end. Pointless until the
  kit publishes — even then, slow and probably belongs in
  `SwiftInferIntegrationTests` (the skip-targeted suite).
- **Performance regression test** for PRD §15's "1k action
  sequences in <100ms" budget. The 100ms target is amortized over
  the warm-cache `swift build` + run; first-invocation cold builds
  will be 1–5s. Calibrate against a real corpus reducer before
  enforcing.
- **Trace shrinking + replay-file persistence** (PRD §7.5). Needs
  failing traces to shrink against, which means M4+ invariants
  first.
- **`.measuredEdgeCaseAdvisory`** outcome path — curated edge-case
  sequences ship at M5+.
- **Verify-evidence persistence** (PRD §17 schema v4 for
  interaction outcomes) — defer to M9+ when `metrics --interaction`
  ships. M3.E renders to stdout only.
- **Invariant checking.** Still the M3.0 framing: outcome is "ran
  cleanly / trapped." M4 attaches the first real invariant.
- **`.tca` carrier** — TCA `Reduce { state, action in ... }` closures
  need closure-relative state init; M3.B's `validate(_:)` rejects
  them with a clear "deferred to M3.future" message.
- **Effect-bearing reducers** route to the still-unbuilt M8
  subprocess path.

## Test count

**2675 → 2691 (+16):**

- M3.E.2 (+4) — `WorkdirMode` rawValues + `.interaction` dep block /
  target deps / user-package interaction.
- M3.E.3 (+8) — five-category mapping + marker extraction edge
  cases (in-noise, missing fields, empty input).
- M3.E.4 (+3) — `renderOutcome` shape + workdir-segment filename
  safety. The main `VerifyInteractionPipelineTests` got renamed
  from `runPipeline` to `resolveAndEmit` (no net test count change
  on that suite; the file just got split because adding 3 render
  tests pushed it over SwiftLint's `type_body_length` cap).

§13 budgets unchanged.

## What's next — M4 (and the kit-tag push)

**Immediate next-action (user)**: push the kit tag so M3.E's
synthesized workdir can actually resolve v2.2.0.

**M4 — Conservation + Idempotence templates lifted from v1**. The
first interaction-template families. PRD §5.2 + §5.3 specify the
witnesses; both are lifted-from-v1 so calibration starts from a
known acceptance-rate baseline. M4 introduces the first real
*invariant* the M3 verifier can check — extending M3.B's stub
emitter to include a `#expect(predicate(state))` step per generated
action.

M4 is structurally bigger than any single M3.x because it ships:
- The template engine surface (§5)
- Per-family `Score` weights (§4.1 reducer-shape signals)
- Predicate emission in the M3.B stub
- The first calibration cycle against a (still-skeleton) corpus

Worth a scope conversation when the kit tag publishes and the M3
end-to-end path becomes testable.

## Artifacts

- v1.78 sources:
  - `Sources/SwiftInferCLI/VerifierWorkdir.swift` (M3.E.2 mode
    parametrization)
  - `Sources/SwiftInferCLI/InteractionVerifyOutcomeParser.swift` (M3.E.3)
  - `Sources/SwiftInferCLI/VerifyInteractionPipeline.swift` (M3.E.4
    full pipeline)
- Prior cycle: `docs/calibration-cycle-74-findings.md` (M3.0 skeleton).
- v2.0 PRD: `docs/SwiftInferProperties PRD v2.0.md`.
