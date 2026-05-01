# M6 Execution Plan

Working doc for the M6 milestone defined in `SwiftInferProperties PRD v0.4.md` §5.8. Decomposes M6 into six sub-milestones so progress is checkable session-by-session. **Ephemeral** — archive to `docs/archive/M6 Plan.md` once M6 ships and the §5.8 acceptance bar is met (mirroring M1–M5).

> **M6 is the largest TemplateEngine milestone to date.** It introduces the workflow operationalization layer that turns the discover pipeline into an interactive triage → adoption → drift-monitoring loop. Four user-visible features, one shared-infrastructure layer underneath all of them. The plan groups them so the dependencies are clear (M6.1 + M6.2 + M6.3 are pure infrastructure / value types; M6.4 + M6.5 wire those into CLI subcommands).

## What M6 ships (PRD v0.4 §5.8)

> **Workflow operationalization (NEW in v0.4).** `swift-infer discover --interactive` triage mode (§8) walking suggestions with `[A/B/s/n/?]` prompts; the §3.6 step 3 writeout — accepted suggestions emit property-test stubs to `Tests/Generated/SwiftInfer/`; `swift-infer drift` mode (§9) with `.swiftinfer/baseline.json` baseline + non-fatal drift warnings; `.swiftinfer/decisions.json` infrastructure (read + write + schema). The `// swiftinfer: skip` honoring + suggestion-identity hashing the v0.3 TestLifter §7.9 M6 row also listed are already in the TemplateEngine M1.5 ship; this M6 picks up the persistence half.

Four concrete user-visible deliverables, plus the shared infrastructure they all sit on:

1. **`swift-infer discover --interactive`** — triage mode walking suggestions one-at-a-time with `[A/B/s/n/?]` prompts (PRD §8). Each decision logged to `.swiftinfer/decisions.json`.
2. **Lifted-test stub writeout** — accepted suggestions emit property-test files to `Tests/Generated/SwiftInfer/` (PRD §3.6 step 3 + §16 #1 hard guarantee).
3. **`swift-infer drift`** — compares against `.swiftinfer/baseline.json`, warns (non-fatally per §3 non-goals) on new Strong-tier suggestions added since baseline that lack a recorded decision (PRD §9).
4. **`.swiftinfer/decisions.json` infrastructure** — schema + read + write. Consumed by both `--interactive` (writes accepts/rejects) and `drift` (reads to know what's already triaged). The TestLifter side will also consume the same file when it eventually starts (PRD v0.4 §5.9 cross-ref table notes this ownership move from v0.3's TestLifter M6 to v0.4's TemplateEngine M6).

### Important scope clarifications

- **Option B in the `[A/B/s/n/?]` prompt is M7 territory.** PRD §6 RefactorBridge specifies Options A and B per suggestion: A is a one-off property test (M6 ships this writeout); B is a protocol-conformance suggestion (M7's RefactorBridge writeout to `Tests/Generated/SwiftInferRefactors/`). M6's interactive prompt is `[A/s/n/?]` only — `B` is added when M7 lands. Open decision #1 below picks this default.
- **`--dry-run` (M5.5 placeholder) flips meaningful in M6.** When set during `--interactive`, accept gestures don't actually write files but DO show the file path that *would* have been written + don't update decisions.json. The M5.5 placeholder-status diagnostic gets removed in M6.4 in favour of the real suppression behavior.
- **TestLifter cross-validation +20 still gated** on TestLifter M1 in this repo (PRD §7.9). M3.5's `crossValidationFromTestLifter` parameter remains dormant under M6.
- **`apply` subcommand stays v1.1+** (PRD §20.6) — `--interactive`'s per-prompt accept is the v1 path; `apply --suggestion <hash>` automates the same writeout for non-interactive flows in v1.1+.

## Sub-milestone breakdown

| Sub | Scope | Why this order |
|---|---|---|
| **M6.1** | `Decisions` data model + `.swiftinfer/decisions.json` JSON I/O. New `Sources/SwiftInferCore/Decisions.swift`: `DecisionRecord` per-entry value type (identity-hash, decision enum {`accepted`, `rejected`, `skipped`}, template, score-at-decision-time, timestamp, signal-weights snapshot per PRD §17.1) + `Decisions` collection wrapper with `Codable` round-trip. New `Sources/SwiftInferCLI/DecisionsLoader.swift`: walk-up reader matching the M2 `ConfigLoader` pattern, atomic writer that preserves the JSON shape across re-saves. CRUD tests cover empty / append / update-existing / corrupt-file recovery. | Pure value type + I/O — no orchestration. Sits below both M6.4 (interactive accept writes here) and M6.5 (drift reads here). Doing it first lets M6.4/M6.5 mock against a stable schema. |
| **M6.2** | `Baseline` data model + `.swiftinfer/baseline.json` JSON I/O. New `Sources/SwiftInferCore/Baseline.swift`: `BaselineEntry` (identity-hash, tier, template, score) + `Baseline` collection. New `Sources/SwiftInferCLI/BaselineLoader.swift` matching the M6.1 pattern. CRUD tests + a fixture-corpus test that snapshots a real `discover` output as a baseline. | Same shape as M6.1 — pure value type. Independent of M6.1 schema-wise but shares the loader pattern. M6.5 (drift) depends on this. |
| **M6.3** | `LiftedTestEmitter` — pure-function emission of an `@Test func` source string from a `Suggestion`. Extracts the M5.2 `CheckPropertyMacro.emitIdempotentPeer` / M5.3 `emitRoundTripPeer` body-rendering logic into a reusable `Sources/SwiftInferTemplates/LiftedTestEmitter.swift`. Both the macro impl AND M6.4's interactive-accept path call into this — single source of truth for the lifted-test text shape. Byte-stable goldens for both `.idempotent` and `.roundTrip` shapes; verifies the emitted text round-trips through the macro test framework. | Bridges M5's macro path and M6.4's file-writeout path. Doing it before M6.4 means M6.4 just orchestrates (read decisions, prompt, call emitter, write file) without inlining stub-template logic. |
| **M6.4** | `swift-infer discover --interactive` mode. New `Sources/SwiftInferCLI/InteractiveTriage.swift`: stdin reader (mockable via a `PromptInput` protocol that production resolves to `readLine()`-backed and tests fake), per-suggestion prompt loop with `[A/s/n/?]` (open decision #1 default — `B` deferred to M7), wires `A` → `LiftedTestEmitter` (M6.3) → file writeout to `Tests/Generated/SwiftInfer/<TemplateName>/<FunctionName>.swift` AND `DecisionsLoader.append` (M6.1); `s` and `n` only update decisions.json (open decision #2 — distinct decision states). M5.5's `--dry-run` flag flips meaningful here: when set, `A` shows the would-be file path + skips both file write and decisions update. The placeholder-status diagnostic from M5.5 is removed. New `Sources/SwiftInferCLI/PromptInput.swift` protocol + `StdinPromptInput` production impl. Integration tests with a `RecordingPromptInput` driver. | First user-facing piece. M6.1 + M6.3 ready as inputs. The interactive flow is the most architecturally invasive surface — splitting it from M6.5 keeps each PR reviewable. |
| **M6.5** | `swift-infer drift` subcommand + `--update-baseline` flag on `discover`. New `Sources/SwiftInferCLI/DriftCommand.swift`: subcommand mirroring `Discover`'s structure (`@Option var baseline: String`, optional `@Option var target: String` defaulting to the same conventions). Pipeline: load `Baseline` (M6.2), run `discover` against the same target, diff suggestion identities, filter to `Strong`-tier-only news that lack a recorded decision (M6.1), emit warnings on stderr in a CI-annotation-friendly format (`warning: drift: new Strong suggestion <hash> for <displayName> at <file>:<line> — <template> (no recorded decision)`). Exit code stays 0 — drift is non-fatal per PRD §3 non-goals. New `--update-baseline` flag on `Discover` snapshots the current run's identities to baseline.json (open decision #5 — separate flag on `discover` rather than a third subcommand). Golden tests for diff output + baseline-update behaviour. | Independent of M6.4 conceptually but shares the M6.1 decisions-reading code path. Last user-facing piece — closes the §3.6 step 7 gap. |
| **M6.6** | Validation suite: byte-stable goldens for emitted lifted-test stub files (one per template arm); CRUD lifecycle tests for decisions.json + baseline.json (write → re-read produces equal value); integration tests for `--interactive` accept + skip + reject paths via `RecordingPromptInput`; `swift-infer drift` golden output for a fixture corpus with a baseline; `--update-baseline` golden test producing a stable baseline.json shape; §13 perf re-check on `swift-collections` + the synthetic 50-file corpus with the M6.4 decisions-load active (the synthetic corpus gains a fixture decisions.json so the read path is exercised in the budget); CLI golden test for the `[A/s/n/?]` prompt rendering. Mirror of M1.6 + M2.6 + M3.6 + M4.5 + M5.6. | Validation, not new code. Closes the M6 acceptance bar. |

## M6 acceptance bar

Mirroring PRD §5.8's prior acceptance bars, M6 is not done until:

a. **`.swiftinfer/decisions.json` round-trips byte-identically** through write → read → write across the `accepted` / `rejected` / `skipped` decision states. CRUD lifecycle tests cover create-empty, append-new, update-existing-decision, and corrupt-file fallback (load returns an empty `Decisions` value + emits a stderr `warning:` matching the existing `ConfigLoader` warning convention).

b. **`.swiftinfer/baseline.json` round-trips byte-identically** through `--update-baseline` → load → re-`--update-baseline`. CRUD tests cover the same lifecycle. A fixture-corpus test snapshots an actual `discover` output and verifies the baseline byte-stability across two runs against the same source.

c. **Lifted-test stub files emit compilable Swift source** for both `.idempotent` and `.roundTrip` shapes. Byte-stable goldens pin the file content (function-test name, generator expression, seed literal, property closure body) — extracted from the M5.2 / M5.3 `CheckPropertyMacro` emission so a future drift in either path catches the other.

d. **`swift-infer discover --interactive` correctly walks all surface suggestions** and prompts `[A/s/n/?]` for each. `A` writes a file to `Tests/Generated/SwiftInfer/<TemplateName>/<FunctionName>.swift` AND records `accepted` in decisions.json. `s` and `n` update decisions.json without writing files. `?` shows help and re-prompts (does not advance). Integration tests via `RecordingPromptInput` cover all four input keys + the help-then-re-prompt loop.

e. **`swift-infer discover --dry-run --interactive` shows the would-be file paths but writes nothing.** decisions.json is not updated; no files appear under `Tests/Generated/SwiftInfer/`. The M5.5 placeholder-status diagnostic is removed (or replaced with the dry-run-active confirmation at the start of the interactive session).

f. **`swift-infer drift --baseline <path>` emits stderr warnings** for new `.strong`-tier suggestions whose identity isn't in the baseline AND isn't recorded in decisions.json. Doesn't warn on already-decided suggestions (regardless of decision). Doesn't warn on non-Strong-tier additions (open decision #4 default). Exit code stays 0 in all cases. Golden test pins the warning line shape per the §9 PR-review-UI annotation surface.

g. **§13 performance budget for `swift-infer discover` (< 2s wall on 50-file module) still holds** on `swift-collections` and the synthetic 50-file corpus *with the M6.1 decisions-load path exercised* — the synthetic corpus tests gain a fixture decisions.json so the load step is in the budget.

h. **§16 #1 hard guarantee preserved** — discover never writes to source files. The M6 writeouts go ONLY to `Tests/Generated/SwiftInfer/`. Verified by `HardGuaranteeTests` extension that runs `--interactive --auto-accept` (or accepts via `RecordingPromptInput`) and snapshots the source-file tree before/after.

## Out of scope for M6 (re-stated for clarity, milestone numbers per PRD v0.4)

- **Option B prompt + RefactorBridge writeout to `Tests/Generated/SwiftInferRefactors/`.** M7 deliverable. M6's prompt is `[A/s/n/?]` only.
- **Monotonicity / invariant-preservation templates.** M7.
- **Algebraic-structure composition** — M8.
- **`swift-infer apply --suggestion <hash>`** — v1.1+ per PRD §20.6. The same `LiftedTestEmitter` (M6.3) will back it eventually.
- **TestLifter integration** — TestLifter M1 hasn't started; the M3.5 cross-validation seam stays dormant.
- **`--show-suppressed` / `--seed-override` flags** — v1.1+ per PRD v0.4 §16 #6.
- **`swift-infer metrics`** — v1.1+ per PRD v0.4 §17.

## Open decisions to make in-flight

1. **Interactive prompt: include `B` for RefactorBridge?**
   - **(a) Defer to M7.** M6 prompt is `[A/s/n/?]`. M7 adds `B` when RefactorBridge writeout lands.
   - **(b) Show `B` with "not yet available" diagnostic.** Confusing — the prompt advertises a gesture that doesn't work.
   - **Default unless reason emerges:** **(a) defer**. Cleaner UX; matches the conservative-precision posture (don't surface affordances we can't deliver yet). M7's RefactorBridge work changes the prompt to `[A/B/s/n/?]` as a one-line edit.

2. **Decision states: `skipped` and `rejected` distinct?**
   - **(a) Three states (`accepted` / `rejected` / `skipped`).** `s` = skip-for-now (re-surfaces in future runs); `n` = no, don't surface again.
   - **(b) Two states (`accepted` / `dismissed`).** `s` and `n` collapse to "dismissed" — both hide from drift.
   - **Default unless reason emerges:** **(a) three states**. The `[A/B/s/n/?]` prompt distinguishes `s` and `n` per PRD §8; collapsing them throws away user intent. `s` lets a developer say "interesting, decide later"; `n` lets them say "definitely not, stop showing me." Drift surfaces both `skipped` and never-decided as "no recorded decision" but `n` doesn't re-surface — the developer pre-empted the drift warning.

3. **Stub file path convention.**
   - **(a) `Tests/Generated/SwiftInfer/<TemplateName>/<FunctionName>.swift`** — sub-folder per template; one file per function.
   - **(b) `Tests/Generated/SwiftInfer/<FunctionName>_<TemplateName>.swift`** — flat folder; template in filename.
   - **(c) `Tests/Generated/SwiftInfer/<FunctionName>.swift`** — flat; multiple `@Test func` per file when one function has multiple lifted properties.
   - **Default unless reason emerges:** **(a) sub-folder per template**. Mirrors `Tests/Generated/SwiftInferRefactors/<...>/<...>.swift` pattern RefactorBridge will use. Sub-folder lets users `git diff Tests/Generated/SwiftInfer/idempotence/` to see template-specific changes.

4. **Drift warns on Likely tier?**
   - **(a) Strong-only.** PRD §9 explicitly says "non-fatal warning per new Strong-tier suggestion." Tightest reading.
   - **(b) Strong + Likely.** Catches more.
   - **Default unless reason emerges:** **(a) Strong-only**. PRD-faithful; Likely-tier can be opted into via `swift-infer drift --include-likely` if a real CI dashboard wants it (M-post addition).

5. **`--update-baseline` as separate subcommand vs flag on `discover`?**
   - **(a) Flag on `discover`.** `swift-infer discover --update-baseline` snapshots the current run.
   - **(b) Separate subcommand.** `swift-infer baseline --update`.
   - **Default unless reason emerges:** **(a) flag**. PRD §3.6 step 7 says "CI runs `swift-infer drift --baseline .swiftinfer/baseline.json`" — discover-and-snapshot is the natural workflow; one fewer subcommand to learn.

6. **`LiftedTestEmitter` vs reusing `CheckPropertyMacro` directly.**
   - **(a) Extract a shared `LiftedTestEmitter` helper** in SwiftInferTemplates that both the macro impl AND M6.4's interactive accept path call into. Single source of truth for lifted-test text.
   - **(b) Run `CheckPropertyMacro` programmatically.** Macros aren't designed to be invoked outside the compiler; this would require driving SwiftSyntaxMacros' expansion machinery from within a CLI tool. Awkward.
   - **Default unless reason emerges:** **(a) extract a shared helper**. The macro impl's `emitIdempotentPeer` / `emitRoundTripPeer` are already pure functions over `(funcName, paramType, returnType, seed, generator)` — moving them into a shared `LiftedTestEmitter` enum is a textbook deduplication. Macro impl re-uses, M6.4 re-uses, future `apply` (v1.1+) re-uses.

7. **`Decisions.append` on update — overwrite or stack?**
   - **(a) Overwrite by identity.** A second decision on the same identity replaces the first; only the latest decision is persisted.
   - **(b) Stack history.** Multiple decisions per identity, ordered by timestamp.
   - **Default unless reason emerges:** **(a) overwrite**. The §17 metrics infrastructure (v1.1+) wants timestamps for time-to-adoption tracking, but doesn't need full history — the *latest* decision is what's currently in effect. A v1.1+ history-stacking opt-in can layer on top if calibration discovers a need (e.g. for "user changed their mind" telemetry).

## New dependencies introduced in M6

None at the SwiftPM level. M6 uses Foundation's `JSONEncoder`/`JSONDecoder` for the JSON I/O, `FileManager` for path resolution + atomic writes, and the existing `swift-syntax`/`swift-argument-parser` deps. No new package additions.

## Target layout impact

```
Sources/
  SwiftInferCore/         # + Decisions.swift               (M6.1: data model)
                          # + Baseline.swift                (M6.2: data model)
  SwiftInferTemplates/    # + LiftedTestEmitter.swift       (M6.3: pure-function stub emit)
  SwiftInferMacroImpl/    # CheckPropertyMacro refactored to call LiftedTestEmitter
  SwiftInferCLI/          # + DecisionsLoader.swift          (M6.1: walk-up read + atomic write)
                          # + BaselineLoader.swift           (M6.2: same shape)
                          # + InteractiveTriage.swift        (M6.4: prompt loop + accept/reject pipeline)
                          # + PromptInput.swift              (M6.4: stdin abstraction protocol)
                          # + DriftCommand.swift             (M6.5: drift subcommand)
                          # SwiftInferCommand.swift gains the Drift subcommand registration,
                          # --interactive flag on Discover, --update-baseline flag on Discover
Tests/
  SwiftInferCoreTests/         # + DecisionsTests.swift
                               # + BaselineTests.swift
  SwiftInferTemplatesTests/    # + LiftedTestEmitterTests.swift
  SwiftInferCLITests/          # + DecisionsLoaderTests.swift
                               # + BaselineLoaderTests.swift
                               # + InteractiveTriageTests.swift
                               # + DriftCommandTests.swift
                               # DiscoverPipelineTests gains --update-baseline + --interactive smoke
  SwiftInferIntegrationTests/  # + DriftIntegrationTests.swift
                               # HardGuaranteeTests extension confirming --interactive accept
                               # writes only to Tests/Generated/SwiftInfer/
```

`SwiftInferCommand.swift` gains the largest CLI surface change since M2 — a new subcommand (`drift`) plus two new flags on `discover` (`--interactive`, `--update-baseline`). Swift Argument Parser handles this cleanly via the existing `Discover` struct.

## Cross-cutting per-template requirement (PRD §5.8)

M6 doesn't add new templates. The §4.5 explainability-block requirement applies to suggestions; M6 reads suggestions and writes them to disk — neither operation changes template-emitted content. The closest "cross-cutting" concern in M6 is the lifted-test stub format (M6.3), which IS template-aware: each template arm emits a different stub shape (`.idempotent` → `f(f(x)) == f(x)`; `.roundTrip` → `g(f(x)) == x`). Future M7 templates (monotonicity, invariant-preservation) will need their own arms in `LiftedTestEmitter` — the M6.3 design leaves the switch open.
