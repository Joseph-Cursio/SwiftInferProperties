# v1.98 Calibration Cycle 95 — Findings (Interactive triage)

Captured: 2026-05-17. swift-infer at v1.98.

## Headline

**First post-detector-arc cycle ships — interactive triage UI for
interaction-invariant suggestions.** v1.98 closes the sibling
thread queued since v1.88 — the N-arm interactive triage prompt
(PRD §9.4). New `swift-infer discover-interaction --interactive`
walks the user through each suggestion one at a time, prompts
`[A/C/s/n/?]`, records the chosen `InteractionDecision` to
`.swiftinfer/interaction-decisions.json` via the existing
`InteractionDecisionsLoader`.

**No corpus delta this cycle** — interactive triage is UI work,
not a detector change. Cycle-7 baseline (92 reducers, 76
interactions) carries forward unchanged. The unlock is mechanical:
the calibration loop now has a usable gesture for collecting
decisions, instead of the prior workflow (run `accept-interaction`
once per identity hash with hand-typed args).

**The scoped form ships, not the full N-arm form.** PRD §9.4's
prompt sketch was `[A/B/B'/B''/.../s/n/?]` for M9's bridge-level
peer proposals — multiple conformance-option arms per bridge.
v1.98 ships the simpler per-suggestion form (`[A/C/s/n/?]`) which
covers the immediate cycle-7 corpus and unblocks the
calibration loop. Bridge-level peer triage stays queued; would
reuse `readChoice`'s arm-driver shape when picked up.

## What landed

### A — `InteractionInteractiveTriage` namespace

New `Sources/SwiftInferCLI/InteractionInteractiveTriage.swift`.
Public API surface:

- `Choice` enum: `accept` / `acceptAsConformance` / `skip` /
  `reject`. Distinct from the persisted `InteractionDecision`
  because the UI surface includes `.skip` (which records no
  persistence — matches v1's `InteractiveTriage` posture).
- `Inputs` struct: `prompt` (any PromptInput), `output` (any
  DiscoverOutput), `diagnostics` (any DiagnosticOutput), `dryRun`,
  `now`. Tests inject scripted prompts via
  `TriageRecordingPromptInput` (reused from v1's existing test
  stubs).
- `run(suggestions:packageRoot:explicitDecisionsPath:inputs:)`
  static entry. Loads existing decisions via
  `InteractionDecisionsLoader.load`, walks each suggestion through
  `readChoice`, upserts a new `InteractionDecisionRecord`,
  persists (unless `dryRun`). Returns the updated
  `InteractionDecisions` for testability.
- `readChoice(prompt:output:)` — the per-suggestion prompt loop.
  Loops on `?` / `help` until valid input; falls through on
  unrecognized input with a diagnostic line; returns `.skip` on
  EOF (piped-input safety, matches v1).
- `decisionFor(_:) -> InteractionDecision?` maps Choice → the
  persisted enum. `.skip` returns `nil` — no record is written
  for skipped suggestions (re-surfaces in future `--interactive`
  runs).

Prompt format: `[N/Total] Accept (A) / Conformance (C) / Skip
(s) / Reject (n) / Help (?)`. Mirrors v1's spacing + per-arm
naming convention.

### B — `discover-interaction --interactive` + `--dry-run`

Two new `@Flag` decorations on `DiscoverInteraction`:

- `--interactive` — walks surviving suggestions through the
  prompt loop. Mutex with `--update-baseline` (the orchestrator
  emits a warning and ignores `--update-baseline` if both are
  set).
- `--dry-run` — pre-existing flag, now also gates the
  `--interactive` decisions write (matches v1's `Discover` flag
  semantics).

`DiscoverInteraction.run` grows a `promptInput` parameter
(defaulted to `StdinPromptInput()`) and a `diagnostics` parameter
(defaulted to `PrintDiagnosticOutput()`). The two-flag dispatch
(`updateBaseline` / `interactive`) routes through
`runUpdateBaseline` or the new `runInteractiveBranch` helper,
respectively. Both branches are additive — the suggestion-stream
render still runs after either gesture.

### C — File split

`DiscoverInteractionCommand.swift`'s struct body crossed
SwiftLint's 250-line `type_body_length` cap after the
`--interactive` branch landed. Moved `runUpdateBaseline`,
`runInteractiveBranch`, and the shared `findPackageRoot` helper
to a new `DiscoverInteractionCommand+SideOrchestrators.swift`
sibling extension. The main file's struct body drops back under
the cap; the side helpers stay close to the orchestrator they
serve.

### D — 9 new tests

In new `Tests/SwiftInferCLITests/InteractionInteractiveTriageTests.swift`:

**Prompt-arm classification (5)**:
- `readChoice` maps each arm to the right Choice (A / C / s /
  n + case-insensitive variants).
- `readChoice` loops on `?` (help) then accepts the next valid
  input.
- `readChoice` falls through on unrecognized input then accepts
  the next valid one.
- `readChoice` returns `.skip` on EOF (script exhausted).

**Decision mapping (1)**:
- `decisionFor` maps Choice → InteractionDecision except `.skip`
  → nil (skipped suggestions don't persist).

**End-to-end run (4)**:
- 3-suggestion fixture with scripted `["a", "s", "n"]` records
  accepted + rejected (no record for skipped).
- Conformance arm (`"c"`) records `acceptedAsConformance`.
- `dryRun: true` walks the loop but skips persistence (file
  doesn't exist after run; in-memory return value still has
  the record).
- Pre-seeded `.skipped` decision is upserted to `.accepted` on
  re-triage; one record total (not duplicated).

Test count: 3049 → 3058 (+9). Reuses
`TriageRecordingPromptInput` / `TriageRecordingOutput` /
`TriageRecordingDiagnosticOutput` from the existing v1
`InteractiveTriageTestStubs`.

## What's next

The detector-fix queue is empty + the interactive triage UI is
in place. The calibration loop proper is now fully unblocked:

1. **Run `discover-interaction --interactive` against the corpus**
   to record decisions on the 76 cycle-7 suggestions. The
   gesture is fully self-contained — no per-identity-hash
   typing needed.
2. **Three cycles of stable acceptance rate per family** —
   measure via `swift-infer metrics --decisions` on the
   accumulated decisions. PRD §3.5 corollary: ≥ 70% rate in a
   narrow band across three cycles → family promotes from
   default-`.possible` to `.likely`.
3. **`accept-check-interaction`** (v1.88, already shipped) for
   regression detection on accepted invariants after kit /
   reducer changes.

One sibling thread still queued:

- **Kit-side `checkInteractionInvariantPropertyLaws` harness**
  (cross-repo) — third cross-repo cycle after M2 and M9. Wires
  v2.3.0 conformances to auto-run on every CI invocation.

Plus the bridge-level N-arm form (deferred from this cycle's
scope) — would extend `readChoice` with `B / B' / B''` etc. arms
when per-bridge peer proposals need triage.
