# v1.107 Calibration Cycle 103 — Findings (Finding F: ReducerCandidate state+action dedupe)

Captured: 2026-05-17. swift-infer at v1.107 / SwiftPropertyLaws at v2.5.0.

## Headline

**Cycle 103 closes Finding F from the cycle-102a isowords dogfood.** `ReduceClosureWalker` emits one `ReducerCandidate` per `Reduce { ... }` closure inside a TCA `body` block; isowords's `Settings.body` (10 inline closures via `.onChange(of:)` composition) was producing 10 identical-by-state-action candidates → 10× redundant interaction-template-engine runs → 20 raw suggestions for 2 unique identities. 37% reducer-candidate inflation, 51% interaction inflation on isowords's 16-Feature-target corpus.

**Fix:** new private helper `dedupedByStateAndAction(_:)` in `DiscoverInteraction`, called between `filterCandidates` and `InteractionTemplateEngine.analyze` in the `collectSuggestions` pipeline. Deduplicates `ReducerCandidate` instances by `(stateQualifiedName, actionQualifiedName)`. First-seen wins. `discover-reducers` output is unaffected — per-closure locations stay visible there because the dedupe is local to the interaction pipeline.

**Corpus impact:**
- **isowords: 43 → 21 occurrences** (−51%; matches the cycle-102a unique-identity count exactly).
- **Calibration corpus: 70 → 70 occurrences** (no change — calibration corpus has no Reduce-closure-dupe pattern; cycle-102 finding showed within-corpus duplicates were zero post-Finding-A).

## Why the calibration corpus shows zero change

The calibration corpus's TCA examples use single-`Reduce`-closure bodies (`Examples/CaseStudies` predates the modern `.onChange(of:)` composition idiom). The HandRolled fixtures are also single-closure by construction. The dedupe is a no-op on the calibration corpus by structure — the fix is real-world-only-visible-today.

This is the inverse of cycle-91/92 findings about Cardinality / RefInt: those detectors work on the calibration corpus but didn't fire on real-world TCA due to API conventions. Finding F is the opposite — the calibration corpus didn't expose the bug; real-world TCA did.

## Per-target isowords delta

| Target | Pre-fix (occurrences) | Post-fix (occurrences) | Δ |
|---|---:|---:|---:|
| ActiveGamesFeature | 0 | 0 | 0 |
| AppFeature | 0 | 0 | 0 |
| ChangelogFeature | 2 | 2 | 0 |
| DailyChallengeFeature | 2 | 2 | 0 |
| DemoFeature | 0 | 0 | 0 |
| GameOverFeature | 3 | 3 | 0 |
| HomeFeature | 0 | 0 | 0 |
| LeaderboardFeature | 2 | 2 | 0 |
| MultiplayerFeature | 1 | 1 | 0 |
| OnboardingFeature | 6 | 2 | **−4** |
| SettingsFeature | 20 | 2 | **−18** |
| SoloFeature | 1 | 1 | 0 |
| StatsFeature | 1 | 1 | 0 |
| TrailerFeature | 2 | 2 | 0 |
| UpgradeInterstitialFeature | 2 | 2 | 0 |
| VocabFeature | 1 | 1 | 0 |
| **Total** | **43** | **21** | **−22** |

Two targets carried the inflation (Settings + Onboarding); all others were already at 1 candidate per Reducer type and the dedupe was a no-op for them.

## Per-family corpus baseline (unchanged from cycle-102)

| Family | Calibration corpus |
|---|---:|
| Idempotence | 55 |
| Biconditional | 8 |
| Cardinality | 5 |
| Referential Integrity | 1 |
| Conservation | 1 |
| **Total** | **70 (54 unique)** |

The cycle-104 scaffold's effective-denominator table stays at 70/54 because Finding F was a real-world-only fix. Triage workflow + decisions file aggregation unchanged.

## What landed

### Code (`SwiftInferCLI`)

`DiscoverInteractionCommand.dedupedByStateAndAction(_:)` — pure helper, returns the input candidates with subsequent occurrences of any `(stateQualifiedName, actionQualifiedName)` key dropped. Insertion-order preserved (Swift `Set.insert(_:).inserted` semantics paired with explicit append). Called once in `collectSuggestions` between `filterCandidates` and `InteractionTemplateEngine.analyze`.

The 4-line wrapping in the pipeline:

```swift
let allCandidates = try ReducerDiscoverer.discover(directory: directory)
let filtered = try filterCandidates(allCandidates, pinRaw: pinRaw)
let deduped = dedupedByStateAndAction(filtered)
return try InteractionTemplateEngine.analyze(
    candidates: deduped,
    sourcesDirectory: directory,
    firstSeenAt: firstSeenAt
)
```

### Tests

`Tests/SwiftInferCLITests/DiscoverInteractionDedupeTests.swift` — 7 regression tests:

1. **`twoCandidatesSameStateAndActionDedupedToOne`** — the isowords Settings.body case (3 candidates with identical state/action → 1 result).
2. **`distinctStateOrActionPreservedSeparately`** — different Reducer types stay distinct.
3. **`sameStateDifferentActionPreserved`** — edge case: same State, different Action.
4. **`sameActionDifferentStatePreserved`** — symmetric edge case.
5. **`emptyInputReturnsEmpty`** — degenerate.
6. **`singleCandidateUnchanged`** — single-element identity.
7. **`firstSeenOrderingPreserved`** — stable ordering for deterministic downstream.

7 new tests + the existing `DiscoverInteractionCommandTests` (which exercises the full pipeline against synthetic single-candidate fixtures) — both pass.

## Why `discover-reducers` output is unaffected

The dedupe is in the `DiscoverInteraction.collectSuggestions` pipeline only. `discover-reducers` calls `ReducerDiscoverer.discover` directly and renders the raw output. The per-closure locations stay visible there — useful for users wanting to see where each `Reduce { ... }` block lives, especially with TCA's composition shapes (`.onChange(of:)`, `.ifLet(_:action:)`, `.forEach(_:action:)`). The dedupe only matters for downstream analysis which the State+Action shape drives.

## What's still in flight after v1.107

- **Cycles 104 / 105 / 106 — the three triage-datapoint cycles.** Human-in-loop dependency. Cycle-104 scaffold pre-populated.
- **Bridge-level N-arm peer triage** (PRD §9.4 full form) — lower priority.
- **Real-world TCA dogfooding (cycle 2)** — apply the chain to another TCA app + see if any new detector edges surface beyond Finding F.
- **Extension-split detector support** — both Cardinality and RefInt detectors only walk StructDecl/ClassDecl/EnumDecl, not ExtensionDecl. Zero corpus impact today.
- **Finding E queue (cycle 102)** — Conservation Cartesian-product. No false positives surface today.

## Cycle-renumber chain (updated)

| Cycle | Ship |
|---|---|
| 100 | Finding A fix (cardinality distinct-field dedupe) |
| 101 | Finding C fix (RefInt element-type filter) |
| 102 | Finding D fix (bicond cardinality-overlap suppression) |
| 102a | Dogfood vs isowords — Findings F / G / H surfaced |
| 103 | **Finding F fix (this)** — ReducerCandidate state+action dedupe |
| 104 | First triage datapoint (scaffold pre-populated) |
| 105+ | (continued per next-step choices) |

The Finding F fix preserves the established fix-then-triage cadence: cycles 100 + 101 + 102 + 103 all detector fixes; cycle 104 is the first actual triage datapoint cycle.
