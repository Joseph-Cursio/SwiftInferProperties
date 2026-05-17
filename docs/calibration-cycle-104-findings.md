# v1.107 Calibration Cycle 104 — Findings (first triage datapoint)

> **STATUS: DRAFT.** This file is a scaffold prepped after cycle 99
> shipped the `metrics-interaction` aggregation helper, cycles 100 +
> 101 + 102 + 102a (dogfood) + 103 closed Findings A (cardinality
> distinct-field dedupe), C (RefInt element-type filter), D (bicond
> cardinality-overlap suppression), and F (ReducerCandidate dedupe
> by state+action in the discover-interaction pipeline). Sections
> marked `_DRAFT_` need triage decisions filled in via the per-corpus
> `discover-interaction --interactive` workflow. The aggregated metrics table at the bottom is generated
> by piping the persisted decision logs through `metrics-interaction`
> (one invocation, all three corpora's decisions files). Replace this
> banner with a "Captured: YYYY-MM-DD" line when the cycle is final.
>
> **Cycle-renumber note** — this file was originally drafted as the
> cycle-100 scaffold. Cycles 100 + 101 + 102 ended up shipping
> detector bug fixes instead (same pattern as v1.91–v1.97 cycle-87
> fixes interleaving with calibration cycles), so the first triage
> datapoint becomes cycle 104 + v1.107.

## Headline (TODO once decisions land)

_DRAFT_ — fill in once the first per-family acceptance-rate datapoint is in hand.

Template:

> Cycle 104 lands the first per-family acceptance-rate datapoint of
> the three-cycle calibration loop. **HandRolled: X% acceptance**
> (denominator N); **TCA 1.25.5: X%** (denominator N); **TCA 1.0.0:
> X%** (denominator N); **overall: X%** (across 51 unique identities,
> 70 occurrences, K skipped). Families above the rubric's 70%
> promotion threshold: [list]. Families flagged for rubric refinement
> (skip rate > 30%): [list].

## Workflow

The cycle-102 corpus (70 suggestion occurrences across 11 targets
post Findings A + C + D fixes; **51 unique identities** post
identity-keyed dedupe) is the input.
Run from each corpus's workdir so `--interactive` picks up the
correct `Package.swift` walk-up:

```sh
# 1. HandRolled (7 fixtures, 15 unique identities, 15 occurrences post-Findings-C+D)
cd /Users/josephcursio/xcode_projects/SwiftInferProperties/Tests/Fixtures/v2.0-corpus
swift-infer discover-interaction --target HandRolled --include-possible --interactive

# 2. TCA 1.25.5 (7 examples, 31 unique identities, 31 occurrences post-Finding-A)
cd /tmp/tca-25-discovery
for tgt in CaseStudies UIKitCaseStudies SyncUps Todos VoiceMemos; do
  swift-infer discover-interaction --target "$tgt" --include-possible --interactive
done

# 3. TCA 1.0.0 (3 examples, 24 unique identities, 24 occurrences;
#    several identities overlap with TCA 1.25.5 — fast pass)
cd /tmp/tca-10-discovery
for tgt in CaseStudies UIKitCaseStudies; do
  swift-infer discover-interaction --target "$tgt" --include-possible --interactive
done

# 4. Aggregate
cd /Users/josephcursio/xcode_projects/SwiftInferProperties
swift-infer metrics-interaction \
  --decisions Tests/Fixtures/v2.0-corpus/.swiftinfer/interaction-decisions.json \
  --decisions /tmp/tca-25-discovery/.swiftinfer/interaction-decisions.json \
  --decisions /tmp/tca-10-discovery/.swiftinfer/interaction-decisions.json
```

Paste the rendered markdown table into the "Cycle 104 aggregated metrics" section below.

## Effective denominator

| Corpus | Occurrences | Unique identities | Notes |
|---|---:|---:|---|
| HandRolled | 15 | 15 | post Findings C + D — drafts pair + 2 Hand03 bicond cross-pairs filtered |
| TCA 1.25.5 (7 examples) | 31 | 31 | post Finding A — CounterTab.body no longer fires |
| TCA 1.0.0 (3 examples) | 24 | 24 | several identities overlap with TCA 1.25.5 (cross-corpus dedupe) |
| **Aggregated (cross-corpus dedupe)** | **70** | **51** | merged decision count after `metrics-interaction` aggregation |

The 19 occurrence → identity collapse is cross-corpus only (the
within-corpus collapses from cycles 100 + 101 already shrank the
raw count): the same `NavigateAndLoad.setNavigation`,
`Animations.setColor`, `BindingForm.binding`, etc. emit identical
identity hashes across both TCA pinned versions because identity
keys on family + reducer qualified name + predicate string.

## Per-suggestion triage worksheet

Walk this top-to-bottom during `--interactive`. The decision column
records what gets persisted to `.swiftinfer/interaction-decisions.json`
(per-corpus): `accepted` (A) / `acceptedAsConformance` (C) /
`rejected` (n) / `skipped` (s). Cross-reference notes column captures
rationale for non-obvious decisions per the rubric.

### HandRolled (15 occurrences, 15 unique — post cycles-101+102 Findings C + D)

Designed-by-construction — these are the rubric's calibration anchor.
The fixtures intentionally satisfy each family. **All 18 are expected
to be `accepted` or `acceptedAsConformance`** (per the per-fixture
designed-witness table in `calibration-corpus-v2.0.md §3`). Any
`rejected` here is a rubric-rater disagreement worth recording in
the findings.

| Family | Reducer | Identity | Predicate | Decision | Notes |
|---|---|---|---|---|---|
| cardinality | `PresentationReducer.reduce` | `0x1628477269C29926` | 3-slot Bool / Bool / Optional | _DRAFT_ | Hand03 — designed cardinality |
| idempotence | `SettingsReducer.reduce` | `0x28E063D1073103E6` | `.refresh` | _DRAFT_ | Hand02 setter shape |
| idempotence | `SettingsReducer.reduce` | `0x39993CA9A4560942` | `.dismiss` | _DRAFT_ | Hand02 setter shape |
| idempotence | `PresentationReducer.reduce` | `0x3C390CFE6D5A9176` | `.showCover` | _DRAFT_ | Hand03 prefix-set match |
| biconditional | `FetchReducer.reduce` | `0x5322E671E7B9C8B0` | `isLoadingResults == (cachedResult != nil)` | _DRAFT_ | Hand05 designed bicond |
| biconditional | `FetchReducer.reduce` | `0x6AE3CAC27441579E` | `isLoadingResults == (activeTask != nil)` | _DRAFT_ | Hand05 designed bicond |
| conservation | `CountedListReducer.reduce` | `0x7EC3E1F5B21BA03B` | `itemCount == items.count` | _DRAFT_ | Hand01 designed conservation |
| idempotence | `SettingsReducer.reduce` | `0x827AC3C0D3F7639E` | `.setColor` | _DRAFT_ | Hand02 prefix-set match |
| idempotence | `PresentationReducer.reduce` | `0x8B9287484B528EC2` | `.showAlert` | _DRAFT_ | Hand03 prefix-set match |
| cardinality | `reduce` (elm-style) | `0x8D6BD8CCFE6C8A14` | 2-slot Bool / Bool | _DRAFT_ | Hand06 elm-style cardinality |
| idempotence | `SettingsReducer.reduce` | `0x97C9FD09CAE9C108` | `.clear` | _DRAFT_ | Hand02 setter shape |
| idempotence | `PresentationReducer.reduce` | `0x9B61B0C65BC892D9` | `.showSheet` | _DRAFT_ | Hand03 prefix-set match |
| idempotence | `MessageListReducer.reduce` | `0x9C2E692E188CC9D5` | `.select` | _DRAFT_ | Hand04 — review: is select setter-shape or transition? |
| idempotence | `reduce` (elm-style) | `0xDB4AF9FDB178C90F` | `.refresh` | _DRAFT_ | Hand06 elm-style idempotence |
| referential-integrity | `MessageListReducer.reduce` | `0xDF7B4776E4770460` | `selectedMessageID == nil \|\| messages.contains { $0.id == selectedMessageID }` | _DRAFT_ | Hand04 — selectedMessageID × messages |

### TCA 1.25.5 (31 occurrences, 31 unique — post-cycle-100 Finding A fix)

| Family | Reducer | Identity | Predicate | Decision | Notes |
|---|---|---|---|---|---|
| idempotence | `SharedStateFileStorage.body` | `0x029429B00EA31B2F` | `.selectTab` | _DRAFT_ | non-curated name; depends on reducer's `.selectTab` handler |
| idempotence | `FocusDemo.body` | `0x03305FCA3F2C90C1` | `.binding` | _DRAFT_ | TCA convention — usually accept |
| idempotence | `Refreshable.body` | `0x039376A414D935FA` | `.refresh` | _DRAFT_ | curated; check if reducer uses incrementing counter |
| idempotence | `LongLivingEffects.body` | `0x1CD499C261AD459F` | `.task` | _DRAFT_ | TCA convention — usually accept |
| idempotence | `NavigateAndLoad.body` | `0x222DD422104373CD` | `.setNavigationIsActiveDelayCompleted` | _DRAFT_ | prefix-set; setter shape |
| cardinality | `AlertAndConfirmationDialog.body` | `0x2661FFB7152A81C6` | `(alert != nil ? 1 : 0) + (confirmationDialog != nil ? 1 : 0) <= 1` | _DRAFT_ | dual modal slot — strong cardinality candidate |
| idempotence | `MultipleDestinations.body` | `0x2CF145DE9F15BBC3` | `.showDrillDown` | _DRAFT_ | prefix-set |
| idempotence | `BindingForm.body` | `0x4D5AA3831F8F39F5` | `.binding` | _DRAFT_ | TCA convention |
| idempotence | `SharedStateUserDefaults.body` | `0x55B2D1BD3AC66895` | `.selectTab` | _DRAFT_ | same as FileStorage twin |
| biconditional | `ScreenA.body` | `0x6207F353D6E8C2C4` | `isLoading == (fact != nil)` | _DRAFT_ | textbook biconditional — likely strong accept |
| idempotence | `NavigateAndLoad.body` | `0x6CD1437C507D2C40` | `.setNavigation` | _DRAFT_ | prefix-set |
| idempotence | `PresentAndLoad.body` | `0x6D02629A0B7E2AD6` | `.setSheetIsPresentedDelayCompleted` | _DRAFT_ | prefix-set |
| idempotence | `SharedStateInMemory.body` | `0x8EACCFC0953B8503` | `.selectTab` | _DRAFT_ | third twin of SharedState |
| biconditional | `NavigateAndLoad.body` | `0x94FF67A336D17466` | `isNavigationActive == (optionalCounter != nil)` | _DRAFT_ | classic isActive ↔ optional-state |
| idempotence | `Animations.body` | `0x98095E03B5CB50C6` | `.setColor` | _DRAFT_ | prefix-set |
| idempotence | `NavigateAndLoadList.body` | `0xA4E1C7777957793A` | `.setNavigationSelectionDelayCompleted` | _DRAFT_ | prefix-set |
| idempotence | `MultipleDestinations.body` | `0xD73376B29A2C4843` | `.showSheet` | _DRAFT_ | prefix-set |
| idempotence | `MultipleDestinations.body` | `0xDC63548560C7FF3A` | `.showPopover` | _DRAFT_ | prefix-set |
| idempotence | `PresentAndLoad.body` | `0xF1BDBD0D08BB8479` | `.setSheet` | _DRAFT_ | prefix-set |
| idempotence | `NavigateAndLoadList.body` | `0xF5C13CD78D4B01D6` | `.setNavigation` | _DRAFT_ | prefix-set |
| biconditional | `EagerNavigation.body` (UIKit) | `0x16AD1B03D0321336` | `isNavigationActive == (optionalCounter != nil)` | _DRAFT_ | parallel to SwiftUI NavigateAndLoad |
| idempotence | `EagerNavigation.body` (UIKit) | `0xCDD3C7C47F9CAA85` | `.setNavigation` | _DRAFT_ | prefix-set |
| idempotence | `LazyNavigation.body` (UIKit) | `0xD026F5CB9B3CAC36` | `.setNavigation` | _DRAFT_ | prefix-set |
| idempotence | `LazyNavigation.body` (UIKit) | `0xF8AA84E3C9B94589` | `.setNavigationIsActiveDelayCompleted` | _DRAFT_ | prefix-set |
| idempotence | `EagerNavigation.body` (UIKit) | `0xFB6656B406E394A4` | `.setNavigationIsActiveDelayCompleted` | _DRAFT_ | prefix-set |
| idempotence | `SyncUpDetail.body` | `0x0601E26716079C49` | `.delegate` | _DRAFT_ | TCA convention — delegate is parent-comms no-op |
| idempotence | `SyncUpForm.body` | `0x2F42BD614C76A015` | `.binding` | _DRAFT_ | TCA convention |
| idempotence | `Todos.body` | `0x65552F900B4B1991` | `.binding` | _DRAFT_ | TCA convention |
| cardinality | `VoiceMemos.body` | `0x2518F5817C36B01B` | `(alert != nil ? 1 : 0) + (recordingMemo != nil ? 1 : 0) <= 1` | _DRAFT_ | dual modal slot |
| idempotence | `VoiceMemo.body` | `0xC4E850D15D81A545` | `.delegate` | _DRAFT_ | TCA convention |
| idempotence | `RecordingMemo.body` | `0xFE45216FC753E6A5` | `.delegate` | _DRAFT_ | TCA convention |

### TCA 1.0.0 (24 occurrences, 24 unique; ~19 overlap with TCA 1.25.5)

Several identity hashes overlap with TCA 1.25.5 entries above (same
reducer / family / predicate). When a decision is already recorded
for an overlapping identity in the TCA 1.25.5 corpus, the TCA 1.0.0
triage of that identity is a no-op for the aggregate denominator
(both decisions persist in their own corpus files; `metrics-
interaction --decisions ... --decisions ...` merges by identity with
latest-timestamp wins).

| Family | Reducer | Identity | Predicate | Decision | Notes |
|---|---|---|---|---|---|
| idempotence | `FocusDemo.body` | `0x03305FCA3F2C90C1` | `.binding` | _DRAFT_ | overlaps tca-25 |
| idempotence | `NavigateAndLoad.body` | `0x222DD422104373CD` | `.setNavigationIsActiveDelayCompleted` | _DRAFT_ | overlaps tca-25 |
| cardinality | `AlertAndConfirmationDialog.body` | `0x2661FFB7152A81C6` | dual modal slot | _DRAFT_ | overlaps tca-25 |
| idempotence | `MultipleDestinations.body` | `0x2CF145DE9F15BBC3` | `.showDrillDown` | _DRAFT_ | overlaps tca-25 |
| idempotence | `BindingForm.body` | `0x4D5AA3831F8F39F5` | `.binding` | _DRAFT_ | overlaps tca-25 |
| idempotence | `SharedState.body` | `0x6A1C5F8B800C666B` | `.selectTab` | _DRAFT_ | tca-10-only (no FileStorage / UserDefaults / InMemory split yet) |
| idempotence | `NavigateAndLoad.body` | `0x6CD1437C507D2C40` | `.setNavigation` | _DRAFT_ | overlaps tca-25 |
| idempotence | `PresentAndLoad.body` | `0x6D02629A0B7E2AD6` | `.setSheetIsPresentedDelayCompleted` | _DRAFT_ | overlaps tca-25 |
| biconditional | `NavigateAndLoad.body` | `0x94FF67A336D17466` | `isNavigationActive == (optionalCounter != nil)` | _DRAFT_ | overlaps tca-25 |
| idempotence | `Animations.body` | `0x98095E03B5CB50C6` | `.setColor` | _DRAFT_ | overlaps tca-25 |
| idempotence | `LongLivingEffects.reduce` | `0xA128952D45DE0EE8` | `.task` | _DRAFT_ | tca-10-only (`reduce` not `body` — pre-`@Reducer`-macro shape) |
| idempotence | `NavigateAndLoadList.body` | `0xA4E1C7777957793A` | `.setNavigationSelectionDelayCompleted` | _DRAFT_ | overlaps tca-25 |
| idempotence | `MultipleDestinations.body` | `0xD73376B29A2C4843` | `.showSheet` | _DRAFT_ | overlaps tca-25 |
| biconditional | `ScreenA.reduce` | `0xD8040F167F092FA9` | `isLoading == (fact != nil)` | _DRAFT_ | tca-10-only `reduce` shape — same pattern as tca-25 `ScreenA.body` |
| idempotence | `Root.body` | `0xDC04AF5A07FE1BD5` | `.presentAndLoad` | _DRAFT_ | tca-10-only |
| idempotence | `MultipleDestinations.body` | `0xDC63548560C7FF3A` | `.showPopover` | _DRAFT_ | overlaps tca-25 |
| idempotence | `PresentAndLoad.body` | `0xF1BDBD0D08BB8479` | `.setSheet` | _DRAFT_ | overlaps tca-25 |
| idempotence | `NavigateAndLoadList.body` | `0xF5C13CD78D4B01D6` | `.setNavigation` | _DRAFT_ | overlaps tca-25 |
| idempotence | `Refreshable.reduce` | `0xFDD5E07840BF51F1` | `.refresh` | _DRAFT_ | tca-10-only `reduce` shape |
| biconditional | `EagerNavigation.body` (UIKit) | `0x16AD1B03D0321336` | `isNavigationActive == (optionalCounter != nil)` | _DRAFT_ | overlaps tca-25 UIKit |
| idempotence | `EagerNavigation.body` (UIKit) | `0xCDD3C7C47F9CAA85` | `.setNavigation` | _DRAFT_ | overlaps tca-25 UIKit |
| idempotence | `LazyNavigation.body` (UIKit) | `0xD026F5CB9B3CAC36` | `.setNavigation` | _DRAFT_ | overlaps tca-25 UIKit |
| idempotence | `LazyNavigation.body` (UIKit) | `0xF8AA84E3C9B94589` | `.setNavigationIsActiveDelayCompleted` | _DRAFT_ | overlaps tca-25 UIKit |
| idempotence | `EagerNavigation.body` (UIKit) | `0xFB6656B406E394A4` | `.setNavigationIsActiveDelayCompleted` | _DRAFT_ | overlaps tca-25 UIKit |

## Cycle 100 aggregated metrics (TODO)

Paste the rendered table from:

```sh
swift-infer metrics-interaction \
  --decisions Tests/Fixtures/v2.0-corpus/.swiftinfer/interaction-decisions.json \
  --decisions /tmp/tca-25-discovery/.swiftinfer/interaction-decisions.json \
  --decisions /tmp/tca-10-discovery/.swiftinfer/interaction-decisions.json
```

_DRAFT_ — replace this with the rendered output.

## Findings surfaced during triage

### Finding A — Cardinality detector emitted triplicate same-field predicate **(CLOSED in cycle 100)**

**Status: closed by the v1.103 cycle-100 dedupe fix.**

Root cause (confirmed): the `detect(stateTypeName:in directory:)`
directory walk concatenated fields across files. The 3 SharedState
files each declared their own `CounterTab.State` with a single
`alert: AlertState?` field; the suffix-matcher matched all 3
distinct types and naively appended each field set to `allFields`,
producing 3 copies of the same `alert` field before the `≥ 2`
guard. Mathematically the resulting predicate reduced to
`state.alert == nil` — not a cardinality bound.

**Fix (v1.103 cycle 100):** added a `propertyName`-based dedupe
between the cross-file aggregation and the `≥ 2` guard. The single
`alert` field collapses to one entry, fails the ≥ 2 guard, no
witness emits — correct behavior (a single Optional doesn't have
a cardinality invariant). Legitimate extension-splits where files
contribute distinct field names remain unaffected.

**Corpus impact:** TCA 1.25.5 CaseStudies dropped from 23 → 20
interaction suggestions (−3 occurrences from the CounterTab
triplicate). Overall corpus baseline: 76 → 73 occurrences, 55 → 54
unique identities. Per-family: cardinality 8 → 5 (others
unchanged). The cycle-101 worksheet above is post-fix.

### Finding B — TCA cross-version identity overlap is high (~80% of TCA 1.0.0)

Of TCA 1.0.0's 24 unique identities, 19 are duplicates of TCA 1.25.5
entries (same family + qualified reducer name + predicate). This is
the calibration-corpus pinning paying off: the 1.0.0 → 1.25.5 era
preserved the example reducers' API shape even as `@Reducer` /
`Reducer.body` carrier changed. For the calibration loop this means
the marginal cost of triaging TCA 1.0.0 after TCA 1.25.5 is ~5 new
decisions, not 24.

### Finding C — RefInt cross-collection false positive **(CLOSED in cycle 101)**

**Status: closed by the v1.104 cycle-101 element-type filter.**

Pre-fix, the HandRolled `MessageListReducer` would have fired RefInt
on both `selectedMessageID × messages: [Message]` and
`selectedMessageID × drafts: [Draft]` — the second is a cross-
collection pairing that the rubric flags as a likely reject. v1.104
adds an element-type filter (`impliedElementType(fromSelectedName:)`
extracts `Message` from `selectedMessageID`; `elementTypeMatches`
checks if any dotted component of the collection's element type
matches `Message`). The `[Draft]` collection no longer pairs.

(Note: the HandRolled `Hand04` fixture was also updated in cycle
101 — previously its `drafts` field was typed `[Message]` (same
element type), so the cross-collection case wasn't actually
exercised by the calibration corpus. The fixture now uses
`[Draft]`, making the filter's behavior visible in the corpus
re-measurement: HandRolled drops 18 → 17, refint 2 → 1.)

### Finding D / E / ... (TODO)

Add per-triage findings as they surface during the actual cycle 100
walk-through.

## Promotion candidates (TODO)

After 1 cycle of data, no promotions are eligible (PRD §3.5 requires
3 consecutive cycles at ≥ 70%). This section becomes meaningful in
cycle 102's findings.

For cycle 100, report:
- Per-family rate.
- Whether each family is **on track** (≥ 70% — promotion candidate
  if cycles 101 + 102 hold).
- Whether each family is **at risk** (< 70% — reset counter even
  with future improvements, unless rubric refinement intervenes).
- Whether each family is **gap-bound** (skip rate > 30% — rubric
  refinement for cycle 101).

## What's next after cycle 104

| Cycle | What lands |
|---|---|
| 100 | **Finding A fix** (closed) — distinct-field dedupe in CardinalityWitnessDetector |
| 101 | **Finding C fix** (closed) — RefInt element-type filter |
| 102 | **Finding D fix** (closed) — bicond cardinality-overlap suppression |
| 103 | **First triage datapoint** (this file) — populates the worksheet + metrics + findings |
| 105 | Second triage datapoint. Optional: rubric refinement if cycle-104 surfaced a high-skip family. |
| 105 | Third datapoint; families at ≥ 70% across 103 + 104 + 105 propose tier promotion in cycle-105 findings. |
| 106+ | Per-promotion-family follow-up cycles; bridge-level N-arm peer triage if calibration unlocks bridge-firing volume. |

## CLAUDE.md / version bump notes

When cycle 104 is final:
- Bump `Sources/SwiftInferCLI/SwiftInferCommand.swift` version to `1.108.0`.
- Update CLAUDE.md `Current: v1.108.0` header with the cycle-104 summary.
- Update the arc-summary tail with the v1.108 / cycle-104 entry.
- Update the "Most recent" pointer to `docs/calibration-cycle-104-findings.md`.
