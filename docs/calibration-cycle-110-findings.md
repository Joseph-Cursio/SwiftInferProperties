# Calibration cycle 110 — Blocker B fixed (interaction measured-execution runs from the CLI)

> **STATUS: SHIPPED (v1.117.0).** Implements the
> `docs/blocker-b-verifier-testing-framework-design.md` fix. The
> interaction verify path now builds **and runs from a plain CLI process**
> and reports `measured-bothPass` — the measured-execution leg that was
> blocked since the swift-testing framework migration. Empirical evidence
> for the A1 `.likely → .strong` campaign is now obtainable. Captured
> 2026-06-14.

## Root cause (recap from the design doc)

The toolchain migrated swift-testing `libTesting.dylib` → `Testing.framework`.
The verifier links `@rpath/Testing.framework` (transitively via
swift-property-based). The V1.53.A runtime fix (cycle 49) only injects
`DYLD_LIBRARY_PATH`, which resolves *dylibs*, not *frameworks* — so it
became a no-op and the verifier failed to launch from a plain CLI run. The
v1 **algebraic** integration suite passed only because it runs under a
`swift test` host that already provides the framework; the same verify from
the CLI shared the gap. Not architectural, not kit-side.

## What shipped

**1. `VerifierSubprocess` — inject `DYLD_FRAMEWORK_PATH`.** New
`cachedTestingFrameworkDirectory` locator finds the dir containing
`Testing.framework` via `xcode-select -p` (macOS platform framework dir,
with a `SharedFrameworks` fallback). `environmentWithTestingLibraryPath`
→ renamed `environmentWithTestingRuntimePaths`, now sets **both**
`DYLD_LIBRARY_PATH` (dylib form, kept as a forward-compat no-op) and
`DYLD_FRAMEWORK_PATH` (framework form). Cached `static let` like its
sibling so a survey doesn't shell out per pick. Benefits **both** the
interaction and algebraic CLI verify paths.

**2. Parser hardening — launch failure ≠ reducer trap.**
`InteractionVerifyOutcomeParser.parseRunOutput` now distinguishes a
dynamic-loader launch failure from a genuine trap: a non-zero exit with
**no** `TRACE-CURRENT-SEQ` line (no sequence ran) **and** a dyld signature
on stderr → `.measuredError` ("failed to launch … not a reducer trap"),
instead of the previous `.measuredDefaultFails`. A real trap (which always
leaves at least one trace line) still maps to `.measuredDefaultFails`. This
prevents a load failure from silently "failing" a valid property and
poisoning a measured-evidence run.

## Verification

- **End-to-end (the proof):** `verify-interaction --target IDemo` on a
  standalone nested-State/Action identity reducer, run from a plain CLI
  shell, now reports:
  `Outcome: measured-bothPass / Total runs: 1024 / Clean runs: 1024`.
- **Durable regression test:** `InteractionVerifyMeasuredExecutionTests`
  (in `SwiftInferIntegrationTests`, `.tags(.subprocess)`) synthesizes a
  user package, runs the full build+run leg from the test *process*
  (not relying on a swift-testing host), and asserts `measured-bothPass`
  + the Blocker-A `IDemo.State` qualification. Passes in ~19s. This is the
  M3.E integration test that was deferred "pending kit tag."
- **Unit:** parser — dyld-signature + no-sequence → `.measuredError`;
  dyld text but a sequence ran → `.measuredDefaultFails` (trap wins).
  `VerifierSubprocess` — `cachedTestingFrameworkDirectory`, when non-nil,
  contains `Testing.framework`.
- **Suites:** full fast suite green (3164 tests; perf-budget timing flakes
  only). SwiftLint clean.

## Fast-path note

A second subprocess integration suite now exists, so the documented fast
path is `swift test --skip VerifyPipelineIntegrationTests --skip
InteractionVerifyMeasuredExecutionTests`.

## A side gotcha worth recording

SwiftPM derives a **path dependency's package identity from the directory's
last path component**, not the `name:` in its `Package.swift`. The
synthesized verifier workdir references the user package by *module name*,
so the user package's root directory must be named after the module (e.g.
`…/IDemo/Package.swift`). A UUID-named temp dir fails with "unknown package
'IDemo' … valid packages are '<uuid>'". This bit the integration test and
is the same wrinkle the eventual CLI corpus-packaging step must handle.

## What's next — A1 campaign reopens (two items remain)

Measured execution runs, but a measured `.likely → .strong` run still needs:

1. **Interaction verify-evidence persistence** — `VerifyInteractionPipeline`
   does not call `VerifyEvidenceRecorder`; the outcome →
   `verify-evidence.json` → `Tier.promoted(byVerifyOutcome:)` join (the
   deferred "M9" work) must land so measured `.measuredBothPass` outcomes
   can actually promote idempotence toward `.verified`/`.strong`.
2. **CLI corpus packaging** — synthesize/scaffold standalone packages for
   the HandRolled + TCA corpora (module-named dirs) so `verify-interaction`
   can run over the 39 idempotence identities at corpus scale.

Then: run measured verify over the idempotence corpus, harvest evidence,
and gate `.strong` on execution rather than re-triage. **Idempotence stays
`.likely` (v1.117.0)** until that lands.
