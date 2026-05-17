# v1.109 Calibration Cycle 103c — Findings (`--interactive-bridges` CLI wiring)

Captured: 2026-05-17. swift-infer at v1.109 / SwiftPropertyLaws at v2.5.0.

## Headline

**Cycle 103c wires the cycle-103b bridge-triage namespace into a CLI flag.** New `--interactive-bridges` flag on `discover-interaction` drives the M9 bridge-level N-arm prompt loop. Mutex with `--interactive` and `--update-baseline`; precedence is `--interactive` > `--interactive-bridges` > `--update-baseline` with explicit warnings on downgrade. Empty-bridges sentinel covers the common case (no Strong-tier suggestions in the corpus until calibration promotes a family) without leaving the user staring at an empty prompt.

**Production effect today: zero.** Bridges only fire on Strong-tier suggestions; Strong tier is calibration-gated. Running `swift-infer discover-interaction --target X --include-possible --interactive-bridges` against the current calibration corpus or against isowords emits the no-bridges sentinel — but the wiring is end-to-end and the chain runs the moment calibration unlocks Strong tier.

## What landed

### CLI (`SwiftInferCLI`)

`DiscoverInteractionCommand`:
- **New `--interactive-bridges` flag** with full help text covering the N-arm prompt semantics, persistence behavior, mutex notes, and Strong-tier-gating disclaimer.
- **`run(... interactiveBridges:Bool = false, ...)`** orchestrator parameter (default false preserves existing callers).
- **`warnAndResolveFlagMutex(interactive:interactiveBridges:updateBaseline:diagnostics:)`** extracted from `run` to keep it under SwiftLint's body-length cap. Pure helper returns the resolved 3-tuple of effective flags after emitting warnings to `diagnostics` for each downgrade. Precedence:
  - `--interactive` + `--interactive-bridges` → `--interactive` wins; bridges flag ignored with warning.
  - `--interactive` (or bridges) + `--update-baseline` → triage wins; baseline ignored with warning.
- **`runInteractiveBridgesBranch(...)`** new side-orchestrator (sibling to v1.98's `runInteractiveBranch`). Groups Strong-tier suggestions into bridges via `InteractionInvariantBridge.bridges(from:now:)`, then hands the bridge list to `InteractionBridgeInteractiveTriage.run`. Empty-bridges → sentinel + early return.

### Tests

`Tests/SwiftInferCLITests/DiscoverInteractionBridgesFlagTests.swift` — 9 tests:

1. **`interactiveBridgesFlagDefaultsToFalse`** — argparse default.
2. **`interactiveBridgesFlagSetsTrue`** — flag presence.
3. **`interactiveBridgesParsesAlongsideOtherFlags`** — argparse interaction with `--reducer` / `--include-possible` / `--dry-run`.
4. **`mutexInteractiveBeatsBridges`** — both flags → interactive wins, bridges warning emitted.
5. **`mutexBridgesBeatsBaseline`** — bridges + baseline → bridges wins, baseline warning emitted.
6. **`mutexInteractiveBeatsBaseline`** — interactive + baseline → interactive wins, baseline warning emitted (regression-guards the existing v1.98 mutex through the refactored helper).
7. **`mutexAllThreeFlagsInteractiveWinsAndBothDowngradesWarn`** — three-way mutex; interactive wins; both downgrades produce warnings.
8. **`mutexNoFlagsPassesThrough`** — degenerate case; no warnings emitted.
9. **`mutexBaselineAloneNoWarning`** + **`mutexBridgesAloneNoWarning`** — single-flag-set cases produce no warnings.

End-to-end smoke confirmed against the calibration corpus (HandRolled target): empty-bridges sentinel renders correctly, suggestion stream still emits.

## End-to-end demonstration

```
$ swift-infer discover-interaction \
    --target HandRolled \
    --include-possible \
    --interactive-bridges
No bridges fire — all suggestions are below Strong tier or fewer than the 3-witness
threshold per reducer. Bridges fire only on Strong-tier suggestions (PRD §3.5 —
gated on the calibration loop's tier-promotion rule). Re-run after calibration
promotes a family to Strong / Verified.

15 interaction-invariant suggestions.

[Interaction-Invariant Suggestion]
Family:    idempotence
...
```

The bridge loop reports the empty state + the suggestion stream continues — both branches are additive to the rendered output, same posture as `--interactive` / `--update-baseline`.

## What's still in flight after v1.109

- **Cycles 104 / 105 / 106 — the three triage-datapoint cycles.** Human-in-loop dependency. Cycle-104 scaffold pre-populated.
- **`accept-bridge` recorder subcommand** (analog of `accept-interaction` for `BridgeSuggestion.identity`). Useful if a user wants to accept a bridge by hash without running the interactive loop. Queued for future cycle.
- **Bridge-level drift** (sibling of M10 / v1.87 `drift-interaction`). Today drift fires per-suggestion; bridge-level drift would warn on bundle additions / family changes per-reducer. Queued.
- **Second real-world TCA dogfooding cycle** — see if any new detector edges surface beyond Finding F. Optional.
- **Extension-split detector support** — zero corpus impact today.
- **Finding E queue** — Conservation Cartesian-product. No false positives.

## Cycle-renumber chain (updated)

| Cycle | Ship |
|---|---|
| 100 | Finding A fix (cardinality distinct-field dedupe) |
| 101 | Finding C fix (RefInt element-type filter) |
| 102 | Finding D fix (bicond cardinality-overlap suppression) |
| 102a | Dogfood vs isowords — Findings F / G / H surfaced |
| 103 | Finding F fix (ReducerCandidate state+action dedupe) |
| 103b | Bridge-level N-arm interactive triage namespace |
| 103c | **`--interactive-bridges` CLI flag (this)** |
| 104 | First triage datapoint (scaffold pre-populated) |
| 105+ | (per next-step choices) |

`103c` follows the `102a` / `103b` convention — sibling cycle, not renumber. Cycle-104 scaffold target stays intact because the bridge-triage flag has zero production effect today (Strong-tier gated).
