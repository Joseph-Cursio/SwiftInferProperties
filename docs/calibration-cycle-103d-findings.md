# v1.110 Calibration Cycle 103d — Findings (`accept-bridge` recorder subcommand)

Captured: 2026-05-17. swift-infer at v1.110 / SwiftPropertyLaws at v2.5.0.

## Headline

**Cycle 103d ships the scripted analog of `--interactive-bridges`.** New `swift-infer accept-bridge` subcommand records a decision against a `BridgeSuggestion` identity hash without invoking the interactive loop. Mirror of v1.88's `accept-interaction` recorder (which is keyed on individual `InteractionInvariantSuggestion` identities) but with two additions:

1. **Bridge-only decision arms.** Only `acceptedAsConformance` and `rejected` are valid — plain `accepted` and `skipped` are explicitly rejected at parse time. Matches cycle-103b's design decision that bridges imply kit-side protocol conformance commitment per PRD §9.4.
2. **`--peer N` scoping.** Optional 1-based peer index. When present, scopes the decision to one peer's invariants only. When omitted, applies to every peer's invariants in the bridge.

Useful for scripted workflows (CI, accept-by-hash from a known identity) without spinning up the interactive `--interactive-bridges` loop.

**Production effect today: zero** — same as cycle 103b/c. Bridges only fire on Strong-tier, calibration-gated. The wiring is end-to-end ready; the moment calibration unlocks Strong tier, `accept-bridge` becomes a real gesture.

## What landed

### CLI (`SwiftInferCLI`)

`AcceptBridgeCommand.swift` — new subcommand:

- **Flags**: `--target`, `--identity`, `--decision`, optional `--peer N`, optional `--decisions <path>`.
- **`run(...)`** — full pipeline. Calls `DiscoverInteraction.collectSuggestions` + `InteractionInvariantBridge.bridges(from:now:)`, then delegates to `runWithBridges`.
- **`runWithBridges(...)`** — pure logic seam. Tests inject synthetic Strong-tier bridges directly (PRD §3.5 keeps every family at default-`.possible` until calibration unlocks; no real bridges fire today). Matches identity, upserts per-invariant records, writes JSON.
- **`parseDecision(_:)`** — pure helper that validates the decision string. Rejects `accepted` and `skipped` as non-bridge decisions via the new `AcceptBridgeError.nonBridgeDecision`.
- **`resolveScope(bridge:peerIndex:)`** — pure helper that translates the optional `--peer N` into the list of invariants to record. Validates index bounds.
- **`renderSummary(...)`** — pure helper for the success message.

`AcceptBridgeRequest` struct + `AcceptBridgeError` enum file-scope (SwiftLint nesting cap).

CLI registered alongside the other subcommands in `SwiftInferCommand.subcommands`.

### Pipeline refactor (DiscoverInteractionCommand)

Cycle-103c added the `--interactive-bridges` flag; cycle 103d's tests + the existing tests together pushed the main struct over SwiftLint's body-length cap. The fix:

- **`DiscoverInteractionEffectiveFlags`** new file-scope struct replaces the 3-element tuple `(interactive:interactiveBridges:updateBaseline:)`. SwiftLint flagged the tuple as a `large_tuple` violation (cap = 2).
- **`SideOrchestratorInputs`** new file-scope struct bundles the 8 dependencies `dispatchSideOrchestrator` needed. Drops the helper's signature from 9 args to 2 (suggestions + inputs).
- **`dispatchSideOrchestrator(suggestions:inputs:)`** new helper in the side-orchestrators extension. Replaces the inline `if effectiveFlags.interactive { ... } else if effectiveFlags.interactiveBridges { ... } else if effectiveFlags.updateBaseline { ... }` chain in `run`.
- **`warnAndResolveFlagMutex(...)`** moved from the main struct into the side-orchestrators extension. Reason: the main struct kept inflating with each cycle. The extension is the right home for "shape-y" orchestration helpers.

Result: main struct drops from 256 lines → fits under 250 cap. `run` body drops from 51 → 16 lines.

### Tests

Split into three files to stay under the type-body-length cap:

- **`AcceptBridgeCommandTests.swift`** (14 tests) — `parseDecision` arms (5 tests), `resolveScope` arms (4 tests), CLI registration (3 tests), argument parsing (2 tests). Plus shared `ABRecordingOutput` helper at file scope.
- **`AcceptBridgePipelineTests.swift`** (5 tests) — end-to-end via `runWithBridges` against synthetic Strong-tier bridges. Covers acceptAll / acceptPeer / rejected / unknown-identity / case-insensitive-hash.
- **`AcceptBridgeRenderTests.swift`** (2 tests) — `renderSummary` output for all-peers vs scoped-peer.

21 new tests total.

## End-to-end demonstration

```
$ swift-infer accept-bridge \
    --target Inbox \
    --identity DEADBEEFDEADBEEF \
    --decision accepted-as-conformance \
    --peer 2
Recorded accepted-as-conformance for peer #2 (BiconditionalInvariant) of bridge
0xDEADBEEFDEADBEEF on Inbox.body (1 invariants).
```

Errors are explicit:

```
$ swift-infer accept-bridge --target Inbox --identity ABCD --decision accepted
swift-infer accept-bridge: decision 'accepted' is not valid for bridges.
Bridges imply kit-side protocol conformance commitment (PRD §9.4) — only
accepted-as-conformance and rejected are accepted.
```

## What's still in flight after v1.110

- **Cycles 104 / 105 / 106 — the three triage-datapoint cycles.** Human-in-loop dependency. Cycle-104 scaffold pre-populated.
- **Bridge-level drift** (sibling of M10 / v1.87 `drift-interaction`). Today drift fires per-suggestion; bridge-level drift would warn on bundle additions / family changes per-reducer.
- **Second real-world TCA dogfooding cycle** — optional.
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
| 103c | `--interactive-bridges` CLI flag wiring |
| 103d | **`accept-bridge` recorder subcommand (this)** |
| 104 | First triage datapoint (scaffold pre-populated) |
| 105+ | (per next-step choices) |

`103d` follows the sibling-not-renumber convention. The cycle-103b/c/d sequence (bridge namespace → CLI flag → scripted recorder) completes the bridge-level user surface to parity with the per-suggestion family (v1.88/v1.98). Both forms now have:
- Per-X interactive triage (v1.98 + v1.108)
- Per-X scripted recorder (v1.88 + v1.110)
- Per-X persistence (v1.88's `InteractionDecisions` covers both via per-invariant records)

## Note on the consecutive-fix-cycle pattern

Five consecutive non-triage cycles in a row (100/101/102/102a/103/103b/103c/103d). This is genuinely approaching the limit of useful detector / CLI work that doesn't require triage data. After v1.110, the realistic next step is the calibration loop's first triage datapoint (cycle 104). Further "more code" cycles would start looking like deliberate avoidance.
