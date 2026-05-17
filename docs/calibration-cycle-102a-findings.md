# v1.106 Calibration Cycle 102a — Findings (real-world TCA dogfooding: isowords)

Captured: 2026-05-17. swift-infer at v1.106 / SwiftPropertyLaws at v2.5.0.

## Headline

**First real-world TCA dogfood cycle.** With the detector-fix queue empty + proactive self-survey clean, this cycle applies swift-infer to a non-corpus TCA codebase: Point-Free's flagship game [isowords](https://github.com/pointfreeco/isowords) (~50K LOC, 90 SwiftPM targets, 16 with `Feature` suffix). Confirms detection works end-to-end on real-world TCA code + surfaces one significant detector quality finding (**Finding F: ReduceClosureWalker inflation**) + confirms the cycle-91/92 calibration-corpus pattern about modern TCA's family-distribution shape.

**No code changes this cycle** — pure dogfood / discovery. Finding F is queued for the next fix cycle.

## What we measured

```sh
cd /tmp/isowords-dogfood   # GIT_LFS_SKIP_SMUDGE clone of pointfreeco/isowords@c727d3a
for tgt in ActiveGamesFeature AppFeature ChangelogFeature DailyChallengeFeature \
           DemoFeature GameOverFeature HomeFeature LeaderboardFeature \
           MultiplayerFeature OnboardingFeature SettingsFeature SoloFeature \
           StatsFeature TrailerFeature UpgradeInterstitialFeature VocabFeature; do
  swift-infer discover-reducers --target "$tgt"
  swift-infer discover-interaction --target "$tgt" --include-possible
done
```

32 raw output files persisted to `docs/calibration-cycle-102a-data/`.

## Aggregate results

### Per-target counts

| Target | Reducers | Interactions |
|---|---:|---:|
| ActiveGamesFeature | 0 | 0 |
| AppFeature | 5 | 0 |
| ChangelogFeature | 2 | 2 |
| DailyChallengeFeature | 2 | 2 |
| DemoFeature | 2 | 0 |
| GameOverFeature | 1 | 3 |
| HomeFeature | 1 | 0 |
| LeaderboardFeature | 2 | 2 |
| MultiplayerFeature | 2 | 1 |
| OnboardingFeature | 3 | 6 |
| SettingsFeature | 10 | 20 |
| SoloFeature | 1 | 1 |
| StatsFeature | 1 | 1 |
| TrailerFeature | 1 | 2 |
| UpgradeInterstitialFeature | 1 | 2 |
| VocabFeature | 1 | 1 |
| **Total raw** | **35** | **43** |
| **Total unique** | **22** | **21** |

### Per-family breakdown

| Family | Count | Share |
|---|---:|---:|
| Idempotence | 42 | 97.7% |
| Biconditional | 1 | 2.3% |
| Cardinality | 0 | 0% |
| Referential Integrity | 0 | 0% |
| Conservation | 0 | 0% |

## Findings

### Finding F — ReduceClosureWalker emits one candidate per `Reduce { ... }` closure

**Status: open. Queued for next fix cycle.**

isowords' `Settings.body` declares **10 separate `Reduce { ... }` closures** inside one `body` (typical TCA composition with `.onChange(of:)` blocks); each closure produces one candidate emission via `ReduceClosureWalker`. Settings's State + Action are identical across all 10 closures (`Settings.State`, `Settings.Action`), so:

- `discover-reducers --target SettingsFeature` reports **10 reducer candidates** all named `Settings.body`, distinguished only by file/line location.
- `discover-interaction --target SettingsFeature` runs the interaction template engine **10 times** over the same `Settings.State` + `Settings.Action`, producing **20 raw suggestions** that collapse to **2 unique identities** (10 × 2-suggestions-per-state).

Corpus-wide impact:
- **Raw reducer candidates: 35 → unique reducer types: 22** (37% inflation).
- **Raw interaction suggestions: 43 → unique identities: 21** (51% inflation).
- Per-Reducer-type-name breakdown of multi-closure offenders:

```
10 Settings.body
 3 Onboarding.body
 2 Demo.body
 2 AppReducer.body
 + 8 single-closure reducers
```

Why this matters:
- **Wasted work.** The interaction template engine runs N times per Reducer type where N is the closure count; 9 of 10 Settings runs are redundant.
- **Cluttered output.** `discover-interaction` emits 20 suggestion blocks for SettingsFeature where 2 would suffice; the user scrolls past duplicates.
- **Inflated metrics.** Per-reducer counts in surveys (like this cycle's per-target table) overcount real reducer types.
- **`metrics-interaction` masks the issue.** The identity-keyed dedupe collapses the 20 suggestions to 2 in the aggregated table; but the raw `--decisions` file (if the user accepts/rejects via `--interactive`) would record 10× the same decision unless the renderer dedupes upstream.

**Fix shape** (next cycle):
- In `DiscoverInteraction.collectSuggestions` (or earlier in the pipeline), dedupe `ReducerCandidate` instances by `(stateQualifiedName, actionQualifiedName)` before invoking the template engine. The first encountered location wins; the rest are dropped.
- Alternative: render-time identity-dedupe in `discover-interaction`. Less efficient (still runs N-times) but smaller code change.
- Either way: keep `discover-reducers` output unchanged (per-closure locations are useful for the user to see where each `Reduce` block lives), but make `discover-interaction` dedupe at the candidate or render layer.

**Why this didn't surface in the calibration corpus:** the calibration-corpus TCA examples (Examples/CaseStudies, etc.) use single-`Reduce`-closure bodies. Real-world TCA composition (`.onChange(of:)`, `.ifLet(_:action:)`, `.forEach(_:action:)`, etc.) creates multi-closure bodies that the synthetic corpus doesn't exercise.

### Finding G (observational, not actionable) — Modern TCA family-distribution skew

isowords's per-family distribution confirms the cycle-91/92 calibration finding: **modern TCA's idiomatic State doesn't fire Cardinality / Referential Integrity / Biconditional patterns at any non-trivial rate**.

- **Cardinality: 0%.** TCA's `@Presents var destination: Destination.State?` (single Optional + enum-based Destination) means the cardinality-required "≥ 2 presentation slots" threshold doesn't fire. Modern TCA collapses N modal slots into one Destination enum.
- **Referential Integrity: 0%.** No `selected*` properties exist in isowords; IDs are stored inside the destination's State or composed via `IdentifiedArrayOf<Reducer.State>` + binding to the active element.
- **Biconditional: 2.3%** (1 single hit). The Loading/Showing/Presenting/Active/Fetching/Refreshing patterns require a name match that isowords's State types don't conform to in most places.

**Idempotence dominates (97.7%)** because the name-based action-case detection works regardless of State shape, and TCA's conventions (`.task`, `.binding`, `.delegate`, `.setX`, `.showX`) are well-curated by the cycle-93 calibration.

**Calibration implication:** the three lesser families' acceptance-rate measurement is bounded by **API convention more than detection quality** on modern TCA. The cycle-103/104/105 triage cycles should expect very small Cardinality/RefInt/Conservation denominators (which the HandRolled corpus dominates) and broad Idempotence denominators (where the TCA corpora dominate).

### Finding H (observational, not actionable) — Family-share inversion vs calibration corpus

| Family | isowords | Calibration corpus (cycle 102) |
|---|---:|---:|
| Idempotence | 97.7% | 78.6% |
| Biconditional | 2.3% | 11.4% |
| Cardinality | 0% | 7.1% |
| Referential Integrity | 0% | 1.4% |
| Conservation | 0% | 1.4% |

isowords skews even further toward Idempotence than the calibration corpus's TCA share. The HandRolled portion of the calibration corpus is what's keeping the non-idempotence shares non-zero. Real-world TCA appears to be ~95%+ Idempotence-only.

**This is a real-world signal worth noting in the PRD §19 calibration plan:** the per-family ≥ 70% acceptance-rate gate may be inapplicable to Cardinality / RefInt / Conservation on real-world TCA. They might need a lower-volume promotion criterion (e.g., per-family ≥ 70% with denominator ≥ 5 across N cycles, rather than per-family across all cycles).

## What worked well

- **Detection ran cleanly across all 16 Feature targets.** No crashes, no parse errors on real-world TCA (which uses macros + `@ObservableState` + composition patterns the calibration corpus only partially exercises).
- **Identity-hash stability.** The 10 `Settings.body` candidates correctly collapse to 2 unique identities under the identity-keyed dedupe (`metrics-interaction` would aggregate them cleanly).
- **`@Reducer` macro detection (cycle 90 v1.93)** fires correctly on isowords's `@Reducer struct Foo { ... }` pattern, including the nested `@Reducer enum Destination` shape.
- **`@Presents` recognition (cycle 91 v1.94)** picks up isowords's State definitions, though as Finding G observes, modern TCA's single-`@Presents var destination` pattern doesn't trigger Cardinality's ≥ 2-slot threshold anyway.
- **All cycle-87 + cycle-100/101/102 fixes hold up on real-world code.** Zero same-identity-duplicates within any target, zero malformed predicates, zero cross-collection RefInt false positives (because RefInt didn't fire at all).

## What's still in flight after v1.106

- **Cycles 103 / 104 / 105 — the three triage-datapoint cycles.** Human-in-loop dependency. Cycle-103 scaffold pre-populated.
- **Finding F fix** (queued from this cycle) — ReducerCandidate dedupe by qualified state/action name in the DiscoverInteraction pipeline. Estimated 1 cycle.
- **Bridge-level N-arm peer triage** (PRD §9.4 full form) — lower priority.
- **Extension-split detector support** — both Cardinality and RefInt detectors only walk StructDecl/ClassDecl/EnumDecl, not ExtensionDecl. Zero corpus impact today; preemptive.
- **Finding E queue (cycle 102)** — Conservation Cartesian-product over aggregates × collections. Not actionable until real-world hits it; isowords didn't.

## Methodology notes

- isowords uses Git LFS for asset files. To clone without LFS (we only need source files):
  ```sh
  cd /tmp && rm -rf isowords-dogfood
  GIT_LFS_SKIP_SMUDGE=1 git clone https://github.com/pointfreeco/isowords.git isowords-dogfood
  cd isowords-dogfood
  git config filter.lfs.smudge "git-lfs smudge --skip -- %f"
  git config filter.lfs.process ""
  git config filter.lfs.required false
  git restore --source=HEAD :/
  ```
- Detection is SwiftSyntax-based and doesn't need compilation. Useful since isowords is iOS-only and we're on macOS.
- 16 Feature targets surveyed; the remaining 74 non-Feature targets (clients, helpers, models) are unlikely to host Reducers and weren't surveyed. Could add a corpus-wide sweep if Finding F fix wants more validation.

## Cycle-renumber chain (updated)

| Cycle | Ship |
|---|---|
| 100 | Finding A fix (cardinality distinct-field dedupe) |
| 101 | Finding C fix (RefInt element-type filter) |
| 102 | Finding D fix (bicond cardinality-overlap suppression) |
| 102a | **Dogfood cycle (this)** — isowords survey + Findings F / G / H |
| 103 | First triage datapoint (scaffold pre-populated) — _OR_ Finding F fix |
| 104+ | (continued per next-step choices) |

The "a" suffix marks the dogfood cycle as a sibling-not-renumber to keep the cycle-103-scaffold target intact. If Finding F fix ships next, it slots in as cycle 103 and the scaffold renames to cycle 104 (continuing the established pattern).
