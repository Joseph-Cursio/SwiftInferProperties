# Calibration Cycle 104 — Findings (first triage datapoint)

> **Captured: 2026-06-13.** First triage datapoint of the v2.0
> calibration loop. All 51 unique identities triaged (worksheet below);
> per-family + per-corpus metrics computed. Decisions are the rater's
> reviewed recommendations grounded in reducer source — the persisted
> `--interactive` run that writes `.swiftinfer/interaction-decisions.json`
> is an optional reproducible-artifact follow-up (numbers match by
> construction; see the metrics section's note).
>
> **Result:** idempotence 100% (sole promotion-track family, counter
> 1/3); cardinality 50% + biconditional 33% re-homed to SwiftProjectLint
> per Finding G (both rules shipped); overall 89.8% (44/49). The
> scaffold's prior assumption that all 15 HandRolled anchors would accept
> was falsified — 3 HandRolled rejects (Finding G).
>
> Scaffold lineage: prepped after cycle 99's `metrics-interaction`
> helper; cycles 100/101/102/103 closed detector Findings A/C/D/F;
> 103b/c/d + v1.111's Finding I fix had no calibration impact.
>
> **Cycle-renumber note** — this file was originally drafted as the
> cycle-100 scaffold. Cycles 100 + 101 + 102 ended up shipping
> detector bug fixes instead (same pattern as v1.91–v1.97 cycle-87
> fixes interleaving with calibration cycles), so the first triage
> datapoint became cycle 104. The version when cycle 104 ships will
> be assigned at ship time (project is currently at v1.111).

## Headline

> Cycle 104 lands the first per-family acceptance-rate datapoint of the
> three-cycle calibration loop. **HandRolled: 80%** (12 accept / 15, 3
> reject); **TCA 1.25.5: 96.6%** (28 / 29, 1 reject, 2 skip); **TCA
> 1.0.0: 95.7%** (22 / 23, 1 reject, 1 skip); **overall: 89.8%** (44
> accept / 49, across 51 unique identities, 5 reject, 2 skip).
>
> The aggregate splits cleanly by family: **idempotence 100%** (39/39)
> is the sole promotion-track family; **cardinality 50%** (1/2, skip 50%)
> and **biconditional 33%** (2/6) are *not* promotion candidates and not
> a detector to fix — Finding G shows both are *illegal-state-representable
> smells* now **re-homed as shipped SwiftProjectLint refactor lints**
> (`mutually-exclusive-presentation-state`, `flag-optional-pair-state`).
> Referential-integrity and conservation are 100% but thin (n=1 each).
>
> Families above the 70% promotion threshold: **idempotence** (the
> substantive one; refint/conservation pass on n=1). Family flagged for
> rubric refinement by skip rate > 30%: **cardinality** (50% skip) — but
> the refinement is the SwiftProjectLint re-home, not a rubric bullet.
> Net: the scaffold's prior assumption that all 15 HandRolled anchors
> would accept was falsified — the fixtures are designed to be *detected*,
> not to *dynamically satisfy* their family.

## Workflow

The cycle-102 corpus (70 suggestion occurrences across 11 targets
post Findings A + C + D fixes; **51 unique identities** post
identity-keyed dedupe) is the input.
Run from each corpus's workdir so `--interactive` picks up the
correct `Package.swift` walk-up:

```sh
# 1. HandRolled (7 fixtures, 15 unique identities, 15 occurrences post-Findings-C+D)
cd $HOME/xcode_projects/SwiftInferProperties/Tests/Fixtures/v2.0-corpus
swift-infer discover-interaction --target HandRolled --include-possible --interactive

# TCA workdirs live under the stable sibling dir (NOT /tmp — purge-safe).
# Reconstitute via calibration-corpus-v2.0.md §4.1/§4.2 if missing.
CORPORA="$HOME/xcode_projects/calibration-corpora"

# 2. TCA 1.25.5 (7 examples, 31 unique identities, 31 occurrences post-Finding-A)
cd "$CORPORA/tca-25-discovery"
for tgt in CaseStudies UIKitCaseStudies SyncUps Todos VoiceMemos; do
  swift-infer discover-interaction --target "$tgt" --include-possible --interactive
done

# 3. TCA 1.0.0 (3 examples, 24 unique identities, 24 occurrences;
#    several identities overlap with TCA 1.25.5 — fast pass)
cd "$CORPORA/tca-10-discovery"
for tgt in CaseStudies UIKitCaseStudies; do
  swift-infer discover-interaction --target "$tgt" --include-possible --interactive
done

# 4. Aggregate
cd $HOME/xcode_projects/SwiftInferProperties
swift-infer metrics-interaction \
  --decisions Tests/Fixtures/v2.0-corpus/.swiftinfer/interaction-decisions.json \
  --decisions "$CORPORA/tca-25-discovery/.swiftinfer/interaction-decisions.json" \
  --decisions "$CORPORA/tca-10-discovery/.swiftinfer/interaction-decisions.json"
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

### Pre-triage environment verification (v1.111, 2026-06-07)

Before the interactive walk, the three corpora were re-measured
non-interactively (`discover-interaction --include-possible`, raw
outputs persisted to `docs/calibration-cycle-104-data/{handrolled,
tca-25,tca-10}-raw.txt`) and audited against this worksheet:

- **Occurrence counts reproduce exactly:** HandRolled 15, TCA 1.25.5
  31 (CaseStudies 20 / UIKit 5 / SyncUps 2 / Todos 1 / VoiceMemos 3),
  TCA 1.0.0 24 (CaseStudies 19 / UIKit 5) → 70 total.
- **All 51 unique identity hashes match the worksheet** — zero drift
  between the cycle-102 baseline (when this scaffold was authored) and
  v1.111. `comm -23` / `comm -13` of emitted-vs-worksheet identity
  sets are both empty.
- Full `swift package clean && swift test` is green (3156 tests / 420
  suites). Scaffold command flags (`--interactive`,
  `metrics-interaction --decisions … --format markdown`) confirmed
  current against the v1.111 CLI surface.

### Re-verification at HEAD `262e43a` (2026-06-13)

Re-confirmed before starting the triage, after 455 commits of
post-v1.16-tag refactoring (the `InteractionTemplateFamily` /
`ExprSyntax.binaryOperands` / `FunctionSummary` consolidation arc):

- **All counts + all 51 identity hashes still reproduce exactly** —
  HandRolled 15/15, TCA 1.25.5 31/31 (20·5·2·1·3), TCA 1.0.0 24/24
  (19·5), union 51 unique. `comm -23` / `comm -13` of the emitted
  union against the worksheet identities are both empty. Zero drift
  from the refactors.
- **Corpora relocated out of `/tmp`.** The TCA workdirs had been
  silently gutted by the macOS `/tmp` purge (Sources tree gone →
  `discover-interaction` returned 0 with no error). Reconstituted from
  `calibration-corpus-v2.0.md` §4.1/§4.2 (tags `1.25.5` = `1eaa6fa`,
  `1.0.0` = `195284b`, commits verified) and moved to the stable
  `$HOME/xcode_projects/calibration-corpora/tca-{25,10}-discovery`.
  The §4.1/§4.2 setup blocks + the Workflow section above now point
  there. **Do not run the triage against `/tmp` paths.**

The triage can proceed directly against the worksheet below.

## Per-suggestion triage worksheet

Walk this top-to-bottom during `--interactive`. The decision column
records what gets persisted to `.swiftinfer/interaction-decisions.json`
(per-corpus): `accepted` (A) / `acceptedAsConformance` (C) /
`rejected` (n) / `skipped` (s). Cross-reference notes column captures
rationale for non-obvious decisions per the rubric.

### HandRolled (15 occurrences, 15 unique — post cycles-101+102 Findings C + D)

Designed-by-construction — these are the rubric's calibration anchor.
**The scaffold originally assumed all 15 would be `accepted` /
`acceptedAsConformance`. Grounding each decision in the actual reducer
body falsified that** (see Finding G): the fixtures are designed to be
*detected*, not necessarily to *dynamically satisfy* their family.
**12 accept (C), 3 reject** — Hand03 cardinality (no reducer mutex),
Hand05 ×2 biconditional (result outlives the flag). HandRolled positives
take `C` (acceptedAsConformance) because the user owns these anchor
fixtures.

| Family | Reducer | Identity | Predicate | Decision | Notes |
|---|---|---|---|---|---|
| cardinality | `PresentationReducer.reduce` | `0x1628477269C29926` | 3-slot Bool / Bool / Optional | **n** | Hand03 — **reject**: no mutex; `.showSheet` then `.showAlert` → 2 slots true. Designed for detection, not dynamic mutex → SwiftProjectLint `mutually-exclusive-presentation-state` |
| idempotence | `SettingsReducer.reduce` | `0x28E063D1073103E6` | `.refresh` | **C** | Hand02 — fixed-state setter |
| idempotence | `SettingsReducer.reduce` | `0x39993CA9A4560942` | `.dismiss` | **C** | Hand02 — fixed-state setter |
| idempotence | `PresentationReducer.reduce` | `0x3C390CFE6D5A9176` | `.showCover` | **C** | Hand03 — sets cover to payload; idempotent |
| biconditional | `FetchReducer.reduce` | `0x5322E671E7B9C8B0` | `isLoadingResults == (cachedResult != nil)` | **n** | Hand05 — **reject**: cachedResult persists after load; `false == true` at rest → SwiftProjectLint `flag-optional-pair-state` |
| biconditional | `FetchReducer.reduce` | `0x6AE3CAC27441579E` | `isLoadingResults == (activeTask != nil)` | **n** | Hand05 — **reject**: activeTask never set non-nil; `isLoading=true` sits at rest with optional nil |
| conservation | `CountedListReducer.reduce` | `0x7EC3E1F5B21BA03B` | `itemCount == items.count` | **C** | Hand01 — `itemCount = items.count` every mutation |
| idempotence | `SettingsReducer.reduce` | `0x827AC3C0D3F7639E` | `.setColor` | **C** | Hand02 — key-path setter, same payload |
| idempotence | `PresentationReducer.reduce` | `0x8B9287484B528EC2` | `.showAlert` | **C** | Hand03 — set-to-true |
| cardinality | `reduce` (elm-style) | `0x8D6BD8CCFE6C8A14` | 2-slot Bool / Bool | **C** | Hand06 — holds (degenerate: `isShowingHelp` never set true) |
| idempotence | `SettingsReducer.reduce` | `0x97C9FD09CAE9C108` | `.clear` | **C** | Hand02 — fixed-state setter |
| idempotence | `PresentationReducer.reduce` | `0x9B61B0C65BC892D9` | `.showSheet` | **C** | Hand03 — set-to-true |
| idempotence | `MessageListReducer.reduce` | `0x9C2E692E188CC9D5` | `.select` | **C** | Hand04 — pure setter (not a transition); idempotent |
| idempotence | `reduce` (elm-style) | `0xDB4AF9FDB178C90F` | `.refresh` | **C** | Hand06 — fixed-state setter |
| referential-integrity | `MessageListReducer.reduce` | `0xDF7B4776E4770460` | `selectedMessageID == nil \|\| messages.contains { $0.id == selectedMessageID }` | **C** | Hand04 — accept (designed); `.deleteSelected` nils selection. **#1 rater-judgment row**: `.select(arbitrary id)` could set a non-member under a literal every-sequence reading |

### TCA 1.25.5 (31 occurrences, 31 unique — post-cycle-100 Finding A fix)

| Family | Reducer | Identity | Predicate | Decision | Notes |
|---|---|---|---|---|---|
| idempotence | `SharedStateFileStorage.body` | `0x029429B00EA31B2F` | `.selectTab` | **A** | pure setter `currentTab = tab` |
| idempotence | `FocusDemo.body` | `0x03305FCA3F2C90C1` | `.binding` | **A** | TCA `BindingReducer` key-path setter |
| idempotence | `Refreshable.body` | `0x039376A414D935FA` | `.refresh` | **A** | State-side `fact=nil` + Effect; idempotent (Effect out of scope) |
| idempotence | `LongLivingEffects.body` | `0x1CD499C261AD459F` | `.task` | **A** | TCA convention |
| idempotence | `NavigateAndLoad.body` | `0x222DD422104373CD` | `.setNavigationIsActiveDelayCompleted` | **A** | sets fresh `Counter.State()`; value-equal → idempotent |
| cardinality | `AlertAndConfirmationDialog.body` | `0x2661FFB7152A81C6` | `(alert != nil ? 1 : 0) + (confirmationDialog != nil ? 1 : 0) <= 1` | **s** | **skip**: modality auto-nils on dismiss → both-set UI-unreachable; mutex is presentation-layer (M8 ignores) → SwiftProjectLint `mutually-exclusive-presentation-state` |
| idempotence | `MultipleDestinations.body` | `0x2CF145DE9F15BBC3` | `.showDrillDown` | **A** | sets destination; idempotent |
| idempotence | `BindingForm.body` | `0x4D5AA3831F8F39F5` | `.binding` | **A** | TCA convention |
| idempotence | `SharedStateUserDefaults.body` | `0x55B2D1BD3AC66895` | `.selectTab` | **A** | twin of FileStorage |
| biconditional | `ScreenA.body` | `0x6207F353D6E8C2C4` | `isLoading == (fact != nil)` | **n** | **reject**: `fact` persists after load; `false == true` at rest → SwiftProjectLint `flag-optional-pair-state` |
| idempotence | `NavigateAndLoad.body` | `0x6CD1437C507D2C40` | `.setNavigation` | **A** | pure bool setter |
| idempotence | `PresentAndLoad.body` | `0x6D02629A0B7E2AD6` | `.setSheetIsPresentedDelayCompleted` | **A** | setter |
| idempotence | `SharedStateInMemory.body` | `0x8EACCFC0953B8503` | `.selectTab` | **A** | third SharedState twin |
| biconditional | `NavigateAndLoad.body` | `0x94FF67A336D17466` | `isNavigationActive == (optionalCounter != nil)` | **A** | **accept**: `isActive ⟺ optionalCounter` at rest; `setNav(false)` clears both. Only break is the in-flight window (ignored per at-rest reading) |
| idempotence | `Animations.body` | `0x98095E03B5CB50C6` | `.setColor` | **A** | setter |
| idempotence | `NavigateAndLoadList.body` | `0xA4E1C7777957793A` | `.setNavigationSelectionDelayCompleted` | **A** | setter |
| idempotence | `MultipleDestinations.body` | `0xD73376B29A2C4843` | `.showSheet` | **A** | setter |
| idempotence | `MultipleDestinations.body` | `0xDC63548560C7FF3A` | `.showPopover` | **A** | setter |
| idempotence | `PresentAndLoad.body` | `0xF1BDBD0D08BB8479` | `.setSheet` | **A** | setter |
| idempotence | `NavigateAndLoadList.body` | `0xF5C13CD78D4B01D6` | `.setNavigation` | **A** | setter |
| biconditional | `EagerNavigation.body` (UIKit) | `0x16AD1B03D0321336` | `isNavigationActive == (optionalCounter != nil)` | **A** | **accept**: UIKit parallel of NavigateAndLoad |
| idempotence | `EagerNavigation.body` (UIKit) | `0xCDD3C7C47F9CAA85` | `.setNavigation` | **A** | setter |
| idempotence | `LazyNavigation.body` (UIKit) | `0xD026F5CB9B3CAC36` | `.setNavigation` | **A** | setter |
| idempotence | `LazyNavigation.body` (UIKit) | `0xF8AA84E3C9B94589` | `.setNavigationIsActiveDelayCompleted` | **A** | setter |
| idempotence | `EagerNavigation.body` (UIKit) | `0xFB6656B406E394A4` | `.setNavigationIsActiveDelayCompleted` | **A** | setter |
| idempotence | `SyncUpDetail.body` | `0x0601E26716079C49` | `.delegate` | **A** | delegate is a no-op for own State |
| idempotence | `SyncUpForm.body` | `0x2F42BD614C76A015` | `.binding` | **A** | TCA convention |
| idempotence | `Todos.body` | `0x65552F900B4B1991` | `.binding` | **A** | TCA convention |
| cardinality | `VoiceMemos.body` | `0x2518F5817C36B01B` | `(alert != nil ? 1 : 0) + (recordingMemo != nil ? 1 : 0) <= 1` | **s** | **skip**: dual `@Presents`; partial nil-on-conflict, mutex not fully reducer-enforced → SwiftProjectLint `mutually-exclusive-presentation-state` |
| idempotence | `VoiceMemo.body` | `0xC4E850D15D81A545` | `.delegate` | **A** | delegate no-op |
| idempotence | `RecordingMemo.body` | `0xFE45216FC753E6A5` | `.delegate` | **A** | delegate no-op |

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
| idempotence | `FocusDemo.body` | `0x03305FCA3F2C90C1` | `.binding` | **A** | overlaps tca-25 |
| idempotence | `NavigateAndLoad.body` | `0x222DD422104373CD` | `.setNavigationIsActiveDelayCompleted` | **A** | overlaps tca-25 |
| cardinality | `AlertAndConfirmationDialog.body` | `0x2661FFB7152A81C6` | dual modal slot | **s** | overlaps tca-25 (skip) |
| idempotence | `MultipleDestinations.body` | `0x2CF145DE9F15BBC3` | `.showDrillDown` | **A** | overlaps tca-25 |
| idempotence | `BindingForm.body` | `0x4D5AA3831F8F39F5` | `.binding` | **A** | overlaps tca-25 |
| idempotence | `SharedState.body` | `0x6A1C5F8B800C666B` | `.selectTab` | **A** | tca-10-only; pure setter |
| idempotence | `NavigateAndLoad.body` | `0x6CD1437C507D2C40` | `.setNavigation` | **A** | overlaps tca-25 |
| idempotence | `PresentAndLoad.body` | `0x6D02629A0B7E2AD6` | `.setSheetIsPresentedDelayCompleted` | **A** | overlaps tca-25 |
| biconditional | `NavigateAndLoad.body` | `0x94FF67A336D17466` | `isNavigationActive == (optionalCounter != nil)` | **A** | overlaps tca-25 (accept) |
| idempotence | `Animations.body` | `0x98095E03B5CB50C6` | `.setColor` | **A** | overlaps tca-25 |
| idempotence | `LongLivingEffects.reduce` | `0xA128952D45DE0EE8` | `.task` | **A** | tca-10-only (`reduce` shape); convention |
| idempotence | `NavigateAndLoadList.body` | `0xA4E1C7777957793A` | `.setNavigationSelectionDelayCompleted` | **A** | overlaps tca-25 |
| idempotence | `MultipleDestinations.body` | `0xD73376B29A2C4843` | `.showSheet` | **A** | overlaps tca-25 |
| biconditional | `ScreenA.reduce` | `0xD8040F167F092FA9` | `isLoading == (fact != nil)` | **n** | tca-10-only `reduce` shape — **reject**, same as `0x6207` (`fact` persists at rest) |
| idempotence | `Root.body` | `0xDC04AF5A07FE1BD5` | `.presentAndLoad` | **A** | tca-10-only; setter |
| idempotence | `MultipleDestinations.body` | `0xDC63548560C7FF3A` | `.showPopover` | **A** | overlaps tca-25 |
| idempotence | `PresentAndLoad.body` | `0xF1BDBD0D08BB8479` | `.setSheet` | **A** | overlaps tca-25 |
| idempotence | `NavigateAndLoadList.body` | `0xF5C13CD78D4B01D6` | `.setNavigation` | **A** | overlaps tca-25 |
| idempotence | `Refreshable.reduce` | `0xFDD5E07840BF51F1` | `.refresh` | **A** | tca-10-only `reduce`; State-side idempotent |
| biconditional | `EagerNavigation.body` (UIKit) | `0x16AD1B03D0321336` | `isNavigationActive == (optionalCounter != nil)` | **A** | overlaps tca-25 UIKit (accept) |
| idempotence | `EagerNavigation.body` (UIKit) | `0xCDD3C7C47F9CAA85` | `.setNavigation` | **A** | overlaps tca-25 UIKit |
| idempotence | `LazyNavigation.body` (UIKit) | `0xD026F5CB9B3CAC36` | `.setNavigation` | **A** | overlaps tca-25 UIKit |
| idempotence | `LazyNavigation.body` (UIKit) | `0xF8AA84E3C9B94589` | `.setNavigationIsActiveDelayCompleted` | **A** | overlaps tca-25 UIKit |
| idempotence | `EagerNavigation.body` (UIKit) | `0xFB6656B406E394A4` | `.setNavigationIsActiveDelayCompleted` | **A** | overlaps tca-25 UIKit |

## Cycle 104 aggregated metrics

Per-family acceptance over the **51 unique cross-corpus identities**
(acceptance = `(A + C) / (A + C + n)`; skips excluded from the rate):

| Family | A + C | reject (n) | skip (s) | unique | acceptance | skip rate | status |
|---|---:|---:|---:|---:|---:|---:|---|
| Idempotence | 39 | 0 | 0 | 39 | **100%** | 0% | ✅ on-track (promotion candidate) |
| Cardinality | 1 | 1 | 2 | 4 | 50% | 50% | re-homed (Finding G) |
| Biconditional | 2 | 4 | 0 | 6 | 33% | 0% | re-homed (Finding G) |
| Referential Integrity | 1 | 0 | 0 | 1 | 100% | 0% | thin (n=1) |
| Conservation | 1 | 0 | 0 | 1 | 100% | 0% | thin (n=1) |
| **Overall** | **44** | **5** | **2** | **51** | **89.8%** | 4% | — |

Per-corpus (using each corpus's own occurrence counts, which is what the
persisted per-corpus decisions files would report):

| Corpus | A + C | n | s | acceptance |
|---|---:|---:|---:|---:|
| HandRolled | 12 | 3 | 0 | 80.0% (12/15) |
| TCA 1.25.5 | 28 | 1 | 2 | 96.6% (28/29) |
| TCA 1.0.0 | 22 | 1 | 1 | 95.7% (22/23) |

> **Note — decisions not yet persisted via `--interactive`.** This table
> is computed from the finalized worksheet above (the rater's reviewed
> recommendations). The reproducible artifact — running
> `discover-interaction --interactive` per corpus to write
> `.swiftinfer/interaction-decisions.json`, then `metrics-interaction
> --decisions … --format markdown` — is an optional follow-up; the
> numbers will match the worksheet by construction. Reconstitute the TCA
> corpora first (they live in `$HOME/xcode_projects/calibration-corpora`,
> per `calibration-corpus-v2.0.md` §4.1/§4.2):
>
> ```sh
> CORPORA="$HOME/xcode_projects/calibration-corpora"
> swift-infer metrics-interaction \
>   --decisions Tests/Fixtures/v2.0-corpus/.swiftinfer/interaction-decisions.json \
>   --decisions "$CORPORA/tca-25-discovery/.swiftinfer/interaction-decisions.json" \
>   --decisions "$CORPORA/tca-10-discovery/.swiftinfer/interaction-decisions.json"
> ```

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

### Finding G — Cardinality + biconditional false-positives are *illegal-state-representable* smells; re-homed as SwiftProjectLint refactor lints **(cross-tool, SHIPPED)**

> First **triage-surfaced** finding of the v2.0 loop (Findings A/C/D/F
> were detector-fix findings from cycles 100–103). Surfaced while
> grounding the cycle-104 decisions in reducer source. Independent of how
> the rows are scored — it is about what the State *shape* permits, not
> any single accept/reject call.
>
> **STATUS: SHIPPED.** Both recommended rules now exist on SwiftProjectLint
> `main`: `mutually-exclusive-presentation-state` (commit `ec74f50`) and
> `flag-optional-pair-state` (commit `4264236`) — both opt-in `.info`
> State-Management lints with TCA-distilled tests, full suite green
> (2531 tests). The cardinality/biconditional rows below are skipped/
> rejected here in SwiftInferProperties *and* covered there as refactor
> findings.

**Observation.** Once the recommended decisions are grounded in actual
reducer bodies (not just detected shape), idempotence and the
structural families split sharply:

| Family | A+C | reject | skip | rate |
|---|---:|---:|---:|---:|
| Idempotence | 39 | 0 | 0 | **100%** |
| Cardinality | 1 | 1 | 2 | 50% (skip 50%) |
| Biconditional | 2 | 4 | 0 | **33%** |
| Referential Integrity | 1 | 0 | 0 | 100% (n=1) |
| Conservation | 1 | 0 | 0 | 100% (n=1) |

Every cardinality/biconditional non-accept traces to the **same root
cause**, and it is not a detector bug: the detector matches the State
*shape* correctly, but the invariant's truth lives in the reducer
body / presentation layer, which first-pass triage (M8 discards
`Effect`, per PRD §16 #1) deliberately does not model.

**Root cause — two independent fields encoding one sum type.** Both
families fire on a State that has crammed a 3+-state machine into
independent fields, leaving an illegal combination *representable*:

- **Biconditional (`isLoading == (fact != nil)`).** `isLoading`
  describes a *transition in progress*; `fact != nil` describes the
  *current value*. They are orthogonal: ScreenA (`0x6207`/`0xD804`)
  keeps `fact` after the fetch completes, so at rest `isLoading=false`
  with `fact != nil` → predicate false **at rest** (not transient).
  Same shape in Hand05: `cachedResult` (`0x5322`) persists; `activeTask`
  (`0x6AE3`) is never assigned non-nil, so `isLoadingResults=true` sits
  at rest with the optional nil. The State wants to be
  `enum Status { case idle, loading, loaded(T) }`. *Contrast:* the two
  **accepts** (NavigateAndLoad `0x94FF`, EagerNavigation `0x16AD`) hold
  because their optional is a **session artifact** — `setNavigation(false)`
  nils it in lockstep with the flag, so the value cannot outlive the
  transition. Litmus test for this family: **does the optional get
  cleared the instant the flag goes false?** Persisted result → reject;
  session artifact → accept. (Triage rule adopted this cycle: judge the
  predicate *at rest*; ignore the in-flight window.)

- **Cardinality (`≤ 1` modal).** AlertAndConfirmationDialog (`0x2661`)
  uses **two separate `@Presents` optionals**; neither handler nils the
  other. Both-set is representable in the reducer. It does *not* break
  in the running app, because a `@Presents` modal auto-nils on dismiss
  and modality forces dismiss-before-next-interaction — so `[tapAlert,
  tapDialog]` is UI-unreachable. Hence **skip, not reject**: the mutex
  is real but enforced by the presentation framework M8 ignores, so a
  property test generated against the bare reducer would false-fail.
  The idiomatic fix is a **single `@Presents var destination:
  Destination.State?` enum** (one case per modal) — which makes the
  illegal state *unrepresentable* and leaves nothing to test. The
  example has the invariant *only because* it didn't use the enum.
  VoiceMemos (`0x2518`) is the murkier twin (partial nil-on-conflict).

**The reframe.** In both families the detector is correctly smelling a
**representable illegal state**. As "here is an invariant to test" the
row is a false positive (the test false-fails). As "here is a
structural risk to refactor" the *same* finding is a true positive.
The signal is right; the output mode is wrong.

**Recommendation — re-home, don't promote.** These two families are
[SwiftProjectLint](file://~/xcode_projects/SwiftProjectLint) rules in
disguise. SwiftProjectLint is a SwiftSyntax cross-file SwiftUI/arch
linter (160 rules, State-Management category, an existing
`string-switch-over-enum` "model-with-a-sum-type" cousin, and a
`SwiftProjectLintIdempotencyRules` package). A *lint* needs no
verification — it asserts only that the illegal state is representable,
which is pure structural AST detection: no reducer flow-analysis, no
presentation semantics, no TCA-version coupling (the exact things that
forced the M8 skip). The hard part of the property check is
*unnecessary* for the lint.

Two concrete rules fall out:

1. **`mutually-exclusive-presentation-state`** — ≥ 2
   `@Presents`/`@PresentationState` optionals in one State with no
   enclosing `destination` enum → suggest collapsing. (Covers the
   AlertAndConfirmationDialog / VoiceMemos cardinality rows.)
2. **`flag-optional-pair-state`** — a `Bool` named
   `isLoading`/`isActive`/… paired with the optional it tracks →
   "represents loading-with-stale-result and loaded-but-flag-off; model
   as `enum Status { case idle, loading, loaded(T) }`." (Covers the
   ScreenA / Hand05 biconditional rows.)

**Division of labor this clarifies:** SwiftInferProperties stays
*affirmative* (high-precision "your code maintains this law — lock it
in"; idempotence is the promotion-track family). SwiftProjectLint is
*corrective* ("your State can represent an illegal combination — make
it unrepresentable"). The families that are low-precision **as
properties** are exactly the ones that are high-value **as lints**.
Keep the tools decoupled — a shared idea, not a build dependency.

**SInferP-side follow-up (separate cycle, still OPEN):** now that the
SwiftProjectLint rules exist, re-frame cardinality + biconditional
*output* to defer ("→ see SwiftProjectLint rule X") rather than emitting
a property stub, OR gate them behind `--include-possible` permanently and
never promote past `.possible`. Do **not** pursue option (c) (teaching
SInferP the presentation contract) — it reintroduces the TCA-version
fragility the corpus pinning exists to expose.

**Cycle impact:** does not change any cycle-104 decision. It removes
cardinality + biconditional from the property-promotion track
(idempotence remains the sole on-track family). The SwiftProjectLint work
item is **shipped** (`ec74f50`, `4264236`); the open remainder is the
SInferP-side output re-frame above. PRD-adjacent — worth flagging to the
SwiftPropertyLaws/PRD side per the "explainability is a first-class
output" principle.

### Finding H / I / ... (TODO)

Add further per-triage findings as they surface during the actual
cycle-104 `--interactive` walk-through.

## Promotion candidates

After 1 cycle of data no family promotes yet (PRD §3.5 requires 3
consecutive cycles at ≥ 70%). Cycle-104 standings:

- **Idempotence — ON TRACK (100%).** The sole substantive promotion
  candidate. Promotes `.possible → .likely` if cycles 105 + 106 also
  hold ≥ 70%. This is the headline result: idempotence is high-precision
  on real TCA code (every `.binding` / `.delegate` / `.task` / `.set*` /
  `.show*` / `.selectTab` / `.refresh` row accepted).
- **Referential Integrity — passes (100%) but thin (n=1).** One
  identity (Hand04), and it is the #1 rater-judgment row. Not a
  meaningful promotion signal until the corpus carries more refint.
- **Conservation — passes (100%) but thin (n=1).** Same caveat (Hand01
  only).
- **Cardinality — AT RISK (50%) + gap-bound (50% skip).** Not pursued
  for promotion. The "refinement" is the Finding-G re-home to
  SwiftProjectLint (`mutually-exclusive-presentation-state`, shipped),
  not a rubric bullet.
- **Biconditional — AT RISK (33%).** Not pursued for promotion;
  re-homed to SwiftProjectLint (`flag-optional-pair-state`, shipped).

Net: cycle 104 starts the idempotence promotion counter at 1/3 and
converts the two structural families from "promotion track" to "lint
track." Cycles 105–106 only need to re-confirm idempotence.

## What's next after cycle 104

| Cycle | What lands |
|---|---|
| 100 | **Finding A fix** (closed) — distinct-field dedupe in CardinalityWitnessDetector |
| 101 | **Finding C fix** (closed) — RefInt element-type filter |
| 102 | **Finding D fix** (closed) — bicond cardinality-overlap suppression |
| 103 | **Finding F fix** (closed) — ReducerCandidate dedupe in DiscoverInteraction |
| 104 | **First triage datapoint** (this file) — populates the worksheet + metrics + findings |
| 105 | Second triage datapoint. Optional: rubric refinement if cycle-104 surfaced a high-skip family. |
| 106 | Third datapoint; families at ≥ 70% across 104 + 105 + 106 propose tier promotion in cycle-106 findings. |
| 107+ | Per-promotion-family follow-up cycles; bridge-level N-arm peer triage if calibration unlocks bridge-firing volume. |

## CLAUDE.md / version bump notes

When cycle 104 is final:
- Bump `Sources/SwiftInferCLI/SwiftInferCommand.swift` version (next available — currently v1.111, so `1.112.0` or higher depending on any intervening cycles).
- Update CLAUDE.md `Current:` header with the cycle-104 summary.
- Update the "Most recent" pointer in CLAUDE.md (or wherever the latest-cycle pointer lives) to `docs/calibration-cycle-104-findings.md`.
