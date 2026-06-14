# Design — Blocker B: verifier can't load `Testing.framework` from a CLI run

> **Scope deliverable for cycle 110.** Diagnoses cycle-108 Blocker B to
> ground, **overturns** the earlier "architectural / likely kit-side"
> framing, and specifies a small, proven SInferP-side fix. Drafted
> 2026-06-14 after the cycle-109 build-leg fix (`562787d`).

## TL;DR

Blocker B is **not** architectural and **not** kit-side. The active
toolchain migrated swift-testing from `libTesting.dylib` (gone) to
`Testing.framework` (now under the macOS platform's framework dir). The
verifier binary links `@rpath/Testing.framework`; the V1.53.A runtime fix
only injects `DYLD_LIBRARY_PATH` (which resolves *dylibs*, not
*frameworks*), so it's now a no-op and the binary fails to launch from a
plain CLI run. **Proven fix:** also inject `DYLD_FRAMEWORK_PATH` pointing
at the toolchain's `Testing.framework` directory. With it, the interaction
verifier runs clean (`INTERACTION-VERIFY-OUTCOME: bothPass totalRuns=1024
clean=1024`).

## How the diagnosis was reached (and what it corrects)

The cycle-108 spike concluded Blocker B was architectural — "a plain
`@main` executable can't host swift-testing." Verifying the algebraic path
disproved that:

- **The v1 algebraic verify integration suite passes today** (`swift test
  --filter VerifyPipelineIntegrationTests`: "round-trip passes both
  passes", real subprocess build+run, ~51s). So an executable verifier
  linking swift-testing *can* run.
- **Why it passes:** the integration test runs **under `swift test`** — a
  swift-testing host. The spawned verifier subprocess inherits the host's
  framework-resolution context, so `Testing.framework` loads. Run the
  *same* algebraic verify from a plain `swift-infer verify` shell and it
  would fail identically — the "52/103 measured, frozen since cycle 66"
  figure was produced under a test host and never re-run from the CLI,
  masking the regression.
- **The toolchain change:** `find` shows **no `libTesting.dylib`** in the
  toolchain, but `Testing.framework` exists at
  `…/Platforms/MacOSX.platform/Developer/Library/Frameworks/` (and
  `Xcode.app/Contents/SharedFrameworks/`). swift-testing moved from a
  dylib to a framework. `VerifierSubprocess.environmentWithTestingLibrary
  Path` (V1.53.A, cycle 49) sets `DYLD_LIBRARY_PATH` → `…/macosx/testing`
  for the *dylib* — that directory no longer exists, so
  `cachedTestingLibraryDirectory` is now `nil` and the injection is a
  no-op.

**Corrections to prior docs:** cycle-108 / cycle-109 findings + CLAUDE.md
call Blocker B "architectural" and "likely kit-side." Both are wrong —
PropertyLawKit is Testing-free; the issue is a CLI-only runtime framework-
path gap. Those lines should be amended (see "Doc fixes" below).

## Proven fix

Setting `DYLD_FRAMEWORK_PATH` to the toolchain's `Testing.framework`
directory makes the interaction verifier launch and complete cleanly —
verified directly on the standalone `Demo` reducer:

```
DYLD_FRAMEWORK_PATH="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/Library/Frameworks" \
  ./SwiftInferVerifier
# → INTERACTION-VERIFY-OUTCOME: bothPass totalRuns=1024 clean=1024
```

### Change 1 — `VerifierSubprocess`: inject `DYLD_FRAMEWORK_PATH`

The framework analog of the V1.53.A dylib fix. In
`environmentWithTestingLibraryPath()` (rename → `…TestingRuntimePaths`):

- Add `cachedTestingFrameworkDirectory` — locate the dir containing
  `Testing.framework`. Primary locator: `$(xcode-select -p)/Platforms/
  MacOSX.platform/Developer/Library/Frameworks` (canonical, mirrors the
  existing `swift -print-target-info` approach for the dylib); fallback:
  `$(dirname $(xcode-select -p))/SharedFrameworks`. Both confirmed to
  contain `Testing.framework` and to launch the binary.
- Prepend it to `DYLD_FRAMEWORK_PATH` (preserve any inherited value, our
  entry first — same posture as the existing `DYLD_LIBRARY_PATH` logic).
- Keep the `DYLD_LIBRARY_PATH` injection (harmless no-op now; cheap
  forward-compat if a toolchain ships the dylib again).
- Cache via a `static let` like `cachedTestingLibraryDirectory` (survey
  scale: don't shell out per pick).

~25 lines + a locator. Benefits **both** verify paths (the algebraic CLI
path has the same latent gap).

### Change 2 — parser hardening (safety net)

Today a non-zero exit with no outcome marker is classified by
`InteractionVerifyOutcomeParser` as `.measuredDefaultFails` ("trap in
reducer body") — which is how the dyld launch failure surfaced as a
*false* reducer trap (exit "code 6"). Even with Change 1, a future
runtime-load failure must not masquerade as a real property failure:

- A non-zero exit **without** the clean marker **and without** a
  `TRACE-CURRENT-SEQ` progression (or with a `dyld:`/`Library not loaded`
  stderr signature) → `.measuredError` / `.architecturalCoveragePending`,
  not `.measuredDefaultFails`.
- Mirror the same guard in the algebraic `VerifyResultParser`.

This prevents silent poisoning of a measured-evidence run (a launch
failure scored as "property fails" would wrongly suppress a valid
suggestion and corrupt the A1 acceptance rate).

## Test plan

- **Unit:** `VerifierSubprocess` locator returns a dir containing
  `Testing.framework`; `DYLD_FRAMEWORK_PATH` present in the built env.
  Parser: a dyld-signature stderr + non-zero exit → `.measuredError`
  (not `.measuredDefaultFails`).
- **Integration (the real proof):** a `verify-interaction` integration
  test that builds+runs a standalone nested-State/Action reducer from a
  **plain process** (not under a swift-testing host) and asserts
  `.measuredBothPass`. This is the test the M3.E milestone deferred
  "pending kit tag" — now unblocked. Gate it behind the same
  slow-subprocess exclusion as `VerifyPipelineIntegrationTests`.
- **Regression:** re-confirm `VerifyPipelineIntegrationTests` (algebraic)
  still green.

## Effort + sequencing

| Step | Effort | Notes |
|---|---|---|
| Change 2 (parser hardening) | ~½ cycle | Standalone safety fix; land first |
| Change 1 (`DYLD_FRAMEWORK_PATH`) | ~½ cycle | The actual unblock; small + proven |
| Integration test (plain-process measured) | ~½ cycle | The durable proof; slow-suite gated |
| Doc fixes | trivial | Amend the cycle-108/109 + CLAUDE.md "architectural/kit-side" lines |

Total ≈ 1 cycle. Far smaller than the "kit-side redesign" the cycle-108
spike feared.

## After Blocker B lands — the A1 `.likely → .strong` campaign reopens

With measured execution runnable from the CLI, A1 becomes real: run
`verify-interaction` (or a batch mode) over the 39 idempotence identities,
harvest `.measuredBothPass` as empirical evidence, and wire interaction
verify-evidence persistence (the still-unbuilt "M9" join: outcome →
`verify-evidence.json` → `Tier.promoted(byVerifyOutcome:)`). Only then does
a three-cycle `.likely → .strong` run rest on execution, not re-triage.

Open follow-ups beyond Blocker B (own items):
- **Interaction verify-evidence persistence** — `VerifyInteractionPipeline`
  still doesn't call `VerifyEvidenceRecorder` (deferred to "M9"). Required
  before measured outcomes can promote tier.
- **CLI corpus packaging** — the HandRolled/TCA corpora aren't standalone
  SwiftPM packages exposing their target as a product; a measured run over
  them needs a package-synthesis step (or per-reducer scaffolding).

## Doc fixes (bundle with Change 1)

- `docs/calibration-cycle-108-findings.md` — Blocker B "architectural" →
  amend: CLI-only `DYLD_FRAMEWORK_PATH` gap from the dylib→framework
  toolchain migration; not architectural, not kit-side.
- `docs/calibration-cycle-109-findings.md` — same amendment to the
  "Blocker B still open" section.
- `CLAUDE.md` — "what's next" Blocker B line: drop "likely kit-side,"
  point at this design doc.
