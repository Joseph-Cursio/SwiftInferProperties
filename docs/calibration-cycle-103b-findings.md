# v1.108 Calibration Cycle 103b — Findings (bridge-level N-arm interactive triage)

Captured: 2026-05-17. swift-infer at v1.108 / SwiftPropertyLaws at v2.5.0.

## Headline

**Cycle 103b ships the bridge-level N-arm interactive triage namespace** — closes the PRD §9.4 sibling thread queued since cycle 95 (v1.98). The per-suggestion form (`[A/C/s/n/?]`) shipped in v1.98 for individual `InteractionInvariantSuggestion`s; the bridge form (`[A/1/2/.../s/n/?]`) ships now for multi-peer `BridgeSuggestion`s. New `InteractionBridgeInteractiveTriage` namespace with the same Inputs / run / readChoice shape as v1.98's `InteractionInteractiveTriage` so wiring + tests follow the same pattern.

**Production effect today: zero.** Bridges only fire on Strong-tier suggestions, which is gated on the calibration loop. Until cycle 104+'s triage cycles promote a family to Strong, no Bridge fires in production. The wiring lands now so it's ready when calibration unlocks it.

**No CLI wiring yet** — the namespace ships standalone. A future cycle adds the `--interactive-bridges` flag to `discover-interaction` (or a new `triage-bridges` subcommand). Decision pending whether to bundle into discover-interaction (consistent with v1.98) or stand alone (cleaner separation since bridges have their own data shape).

## What landed

### CLI namespace (`SwiftInferCLI`)

`InteractionBridgeInteractiveTriage` — new namespace sibling to `InteractionInteractiveTriage`:

- **`Choice` enum** — 4 cases: `acceptAll` / `acceptPeer(index: Int)` / `skip` / `reject`. The `acceptPeer` index is 1-based to match the user-typed prompt arm labels.
- **`Inputs` struct** — `prompt` / `output` / `diagnostics` / `dryRun` / `now`. Mirrors v1.98's shape.
- **`run(bridges:packageRoot:explicitDecisionsPath:inputs:)`** — drives a full triage session. Loads existing decisions, walks each bridge through `readChoice`, applies the choice via `applyChoice`, persists (unless `dryRun`).
- **`readChoice(prompt:output:peerCount:)`** — loop-on-help / fall-through-on-invalid / EOF→.skip posture (matches v1.98). Calls `parseChoice` for the actual arm classification.
- **`parseChoice(_ trimmed: String, peerCount:)`** — pure pure helper for arm classification. Numeric arm labels are validated against `1...peerCount`.
- **`applyChoice(_:bridge:decisions:output:now:)`** — folds a parsed choice into the running decisions log. `.acceptAll` / `.reject` write a record for every invariant in every peer; `.acceptPeer` writes records for one peer's invariants only; `.skip` is a no-op.
- **`upserting(_ peer:decision:into:now:)`** — peer-level fold helper. Extracted from `applyChoice` so the latter stays under SwiftLint's body-length cap.
- **`upsertingAllPeers(_ bridge:decision:into:now:)`** — bridge-level fold helper.
- **`promptLine(position:total:peerCount:)`** + **`helpText(peerCount:)`** — rendering helpers that enumerate the per-peer arms (`1, 2, 3, ...`).

### Design decisions

**Numeric arm labels** (`1`, `2`, `3`, ...) instead of PRD §9.4's `B`, `B'`, `B''` notation:
- Numeric labels scale to N peers without notation ambiguity.
- No apostrophe-typing UX cost.
- Easier to enumerate in `promptLine` / `helpText`.
- The PRD notation is a doc-only convention; the CLI uses numerics for typing convenience.

**Per-invariant decision persistence**: each peer carries `invariants: [InteractionInvariantSuggestion]`. Accepting a peer records `acceptedAsConformance` for each invariant in that peer's list (potentially multiple records per peer choice). The per-invariant identity stays the unit of `metrics-interaction` aggregation, so bridge-level triage is just batched per-invariant recording — no new schema, no migration.

**`acceptedAsConformance` for all accept paths**: both `.acceptAll` and `.acceptPeer` use `.acceptedAsConformance` (not `.accepted`). The rationale: a Bridge implies the user wants to commit to the kit-side InteractionInvariant protocol conformance (the bridge writer emits the stub at `Tests/Generated/SwiftInferRefactors/<state>/<stub>.swift`). Plain `accepted` is the per-suggestion path where the user accepts the invariant but isn't committing to a conformance stub. The bridge form's narrower semantics matches PRD §9.4's "kit-side conformance proposal" framing.

**`.skip` on EOF**: matches v1.98's piped-input safety posture. A bridge isn't accepted-or-rejected by stdin-running-out.

### Tests

`Tests/SwiftInferCLITests/InteractionBridgeInteractiveTriageTests.swift` — 12 tests covering:

1. **Arm classification (`parseChoice`)** — table-driven test over `a` / `s` / `n` / numeric / out-of-range / unrecognized inputs. Includes case-sensitivity guard (caller lowercases; `parseChoice` doesn't).
2. **Help-loop semantics (`readChoice`)** — `?` shows help, next input is the choice.
3. **Fall-through on unknown** — `xyz` is rejected, next valid input is the choice.
4. **EOF returns `.skip`** — piped input safety.
5. **Accept-all records conformance for all peer invariants** — multi-peer bridge, 2 invariants → 2 records.
6. **Reject records rejected for all** — 3 invariants → 3 rejected records.
7. **Accept-peer records only that peer's invariants** — picks peer #2 of 3, only 1 record.
8. **Skip leaves decisions unchanged**.
9. **Accept-peer with out-of-range index is no-op** — defensive (`applyChoice` re-validates).
10. **Peer with multiple invariants records all** — single peer with 2 invariants → 2 records.
11. **promptLine enumerates peer arms** — `(1/2/3)`.
12. **helpText enumerates peer arms** — `1, 2, 3, 4`.

Test suite name `BridgeTriageTests` (not `InteractionBridgeInteractiveTriageTests`) to stay under SwiftLint's 40-char type-name cap.

## What's deferred to next cycle(s)

- **CLI wiring.** A `--interactive-bridges` flag on `discover-interaction` (or a new `triage-bridges` subcommand). The data path: collect Strong-tier suggestions → `InteractionInvariantBridge.bridges(from:now:)` → triage namespace. Each path is small but represents a UX decision.
- **`accept-bridge` recorder subcommand.** Analog of `accept-interaction` (v1.88) but keyed on `BridgeSuggestion.identity`. Useful if a user wants to accept a bridge by hash without running the interactive loop.
- **Bridge-level drift** (sibling of M10 / v1.87 `drift-interaction`). Today drift fires per-suggestion; bridge-level drift would warn on bundle additions / family changes.

## Why ship this now, with zero production effect

1. **Closes the v1.98 sibling thread.** Cycle 95 deferred bridge-level triage explicitly; the queue has been in the CLAUDE.md "what's next" lists for 8 cycles. Closing it before calibration starts avoids the situation where calibration produces Strong-tier suggestions, bridges fire, and the user has no triage UI for them.
2. **The data path is ready.** `InteractionInvariantBridge` (Core) + `InteractionBridgeWriter` (CLI) shipped in M9 / v1.86. Adding the interactive triage now means the full chain is ready for the moment a family is promoted to Strong (cycle 105+).
3. **Pattern matches v1.98.** The per-suggestion form was ready before any Strong-tier suggestions existed too; bridge-level is the same shape.

## What's still in flight after v1.108

- **Cycles 104 / 105 / 106 — the three triage-datapoint cycles.** Human-in-loop dependency. Cycle-104 scaffold pre-populated.
- **Bridge-level CLI wiring** (deferred from this cycle). The namespace ships; the CLI flag does not.
- **Real-world TCA dogfooding (cycle 2)** — apply the chain to another TCA app + see if any new detector edges surface.
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
| 103b | **Bridge-level N-arm interactive triage (this)** |
| 104 | First triage datapoint (scaffold pre-populated) |
| 105+ | (per next-step choices) |

`103b` follows the `102a` convention — sibling cycle, not renumber. The cycle-104 scaffold target stays intact because Bridges have no production effect today (Strong-tier required, calibration-gated).
