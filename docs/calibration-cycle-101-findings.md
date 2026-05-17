# v1.104 Calibration Cycle 101 — Findings (Finding C: RefInt element-type filter)

Captured: 2026-05-17. swift-infer at v1.104 / SwiftPropertyLaws at v2.5.0.

## Headline

**Cycle 101 closes Finding C from the cycle-99 scaffold — the `ReferentialIntegrityWitnessDetector` cross-collection false-positive.** The detector previously paired every `selected<X>` Optional with every collection in the same State via pure Cartesian product. M6's original ship comment (cycle 78) noted "Type-relationship resolution... deferred" — the rubric's "selection references one collection" guidance had to be enforced manually by raters. v1.104 adds a name-based element-type filter: extract `<X>` from `selected<X>(ID)?`, only pair with collections whose element type matches `X` (case-insensitive, any dotted component). Falls back to current Cartesian behavior when the selected name has no extractable core (bare `selected`, `selectedID`).

**Corpus fixture update:** The HandRolled `Hand04_ReferentialIntegrity.swift` fixture's `drafts` field was typed `[Message]` (same element type as `messages`) so the rubric's cross-collection case wasn't actually exercised by the calibration corpus. Cycle 101 updates the fixture to use `[Draft]` (distinct element type) + adds the `Draft` element type — making the filter's behavior visible in the corpus re-measurement.

**Corpus impact:** HandRolled 18 → 17 (−1, the suppressed `drafts` pairing). Overall corpus baseline: 73 → 72 occurrences, 54 → 53 unique identities. Per-family: referential-integrity 2 → 1 (others unchanged).

**Cycle reorder.** Cycle 101 was originally scheduled as the first triage datapoint cycle (per the cycle-100 cadence plan). Shipping Finding C first cleans the corpus before triage (avoids wasting a calibration decision on a suppressible-at-detection false positive). The first triage datapoint shifts to cycle 102 (v1.105); the cycle-101 scaffold renames to `docs/calibration-cycle-102-findings.md`.

## What landed

### Detector fix (`SwiftInferTemplates`)

Two new helpers on `ReferentialIntegrityExtractor`:

- **`impliedElementType(fromSelectedName name:)`** — strips the `selected` prefix (case-insensitive) and trailing `ID`/`Id` suffix (case-insensitive); returns the remaining core, or `nil` if empty. Examples: `selectedMessageID` → `Message`; `selectedItem` → `Item`; bare `selected` / `selectedID` → `nil` (preserves Cartesian fallback).
- **`elementTypeMatches(implied:collection:)`** — case-insensitive any-component match against the collection's element type. Two TCA-relevant conventions both produce matches:
  - `selectedMessageID` → implied `Message`; collection `[Inbox.Message]` extracts element `Inbox.Message`; component check `["inbox", "message"]` contains `"message"` → match.
  - `selectedTodoID` → implied `Todo`; collection `IdentifiedArrayOf<Todo.State>` extracts element `Todo.State`; component check `["todo", "state"]` contains `"todo"` → match. (TCA convention: a Reducer `Todo` defines `Todo.State`; `selectedTodoID` references one of those `Todo.State` records.)

The `extract(from:)` pair loop calls `impliedElementType` once per selected Optional, then gates each collection by `elementTypeMatches`. When `implied == nil`, the gate is skipped (fallback to current behavior).

### Fixture update (`Tests/Fixtures/v2.0-corpus`)

`Hand04_ReferentialIntegrity.swift` updated: `drafts: [Message]` → `drafts: [Draft]` + new `struct Draft: Identifiable`. Fixture comment updated to reflect the post-v1.104 expected witness count (1, not 2). Pre-v1.104 the fixture's `drafts: [Message]` collapsed the cross-collection signal because both halves had the same element type; the update makes the filter's behavior verifiable end-to-end.

### Tests

- **New** `Tests/SwiftInferTemplatesTests/ReferentialIntegrityElementTypeFilterTests.swift` — 11 tests:
  - Filter happy path: `selectedMessageID` × `[Message]` only (not `[Draft]`)
  - `selectedItem` (no ID suffix) pairs with `items` collection
  - Multiple selected fields each pair with their compatible collection (no cross-pairing)
  - Fallback for bare `selected` / `selectedID` (Cartesian preserved)
  - Module-qualified element types (`Inbox.Message` matches `Message`)
  - Case-insensitive matching
  - No witnesses fire when no collection matches (intended Finding C behavior)
  - 4 direct unit tests for `impliedElementType` (prefix-only, ID-suffix-stripping, mixed casing, nil-when-no-selected-prefix)
- **Updated** `ReferentialIntegrityWitnessDetectorTests.cartesianProductWitnesses` — renamed `elementTypeFilteredPairings`, expectation updated from 4 Cartesian witnesses to 2 element-type-filtered. The pre-fix Cartesian expectation explicitly documented the cross-collection behavior the cycle-99 rubric flagged for rejection; the post-fix expectation matches the rubric's "selection references one collection" intent.

41 RefInt tests pass total (was 32 — +11 from new suite, −2 from removed Cartesian assertions in the renamed test).

### Re-measurement at v1.104

Raw outputs in `docs/calibration-cycle-101-data/` (22 files). Per-corpus:

| Corpus | Cycle-100 | Cycle-101 | Δ |
|---|---:|---:|---:|
| HandRolled | 18 | 17 | −1 |
| TCA 1.25.5 (all 7) | 31 | 31 | 0 |
| TCA 1.0.0 (all 3) | 24 | 24 | 0 |
| **Total** | **73** | **72** | **−1** |

Per-family:

| Family | Cycle-100 | Cycle-101 | Δ |
|---|---:|---:|---:|
| Idempotence | 55 | 55 | 0 |
| Biconditional | 10 | 10 | 0 |
| Cardinality | 5 | 5 | 0 |
| Referential Integrity | 2 | 1 | −1 |
| Conservation | 1 | 1 | 0 |

Unique identities post identity-keyed dedupe: 54 → 53 (the suppressed `selectedMessageID × drafts` pairing's identity `0xE850A01097DFE59D` no longer fires).

## Why the corpus delta is small but the fix matters

The filter has zero impact on TCA 1.25.5 and TCA 1.0.0 — both corpora have **zero** `selected*` properties anywhere in their 10 example apps (cycle-92 finding: modern TCA prefers `@Presents var destination: Destination.State?` over `selected<X>` patterns). The HandRolled fixture is currently the only refint signal in the calibration corpus.

The fix's value is **prospective**: real-world TCA dogfooding on a non-corpus app (or future fixture additions) that hits the `selected<X>` × multi-collection State pattern will surface the cross-collection false-positive. The filter suppresses it at detection time rather than relying on per-suggestion rubric application.

The fix also closes M6's cycle-78 deferred TODO: "Type-relationship resolution... deferred". v1.104 ships a name-based proxy for type resolution that handles the common cases without needing full type-arg parsing.

## Note on the pre-flagged Finding C accuracy

The cycle-99 scaffold's Finding C noted: "HandRolled `MessageListReducer` has both `messages: [Message]` and `drafts: [Draft]` collections paired against the same `selectedMessageID` Optional." This was based on a misread of the fixture — `drafts` was actually `[Message]`, not `[Draft]`, so the cross-collection case wasn't actually present pre-cycle-101. The rubric guidance the Finding referenced ("selection references one collection") was correct in intent; the corpus just didn't exercise it.

Cycle 101 makes the Finding accurate retroactively: the fixture update introduces the `[Draft]` distinction, the filter suppresses the false-positive pairing, and the corpus baseline reflects both.

## What's still in flight after v1.104

- **Cycles 102 / 103 / 104** — the three triage-datapoint cycles. Human-in-loop dependency. Cycle-102 scaffold pre-populated in `docs/calibration-cycle-102-findings.md` with updated denominator (72 / 53) and the suppressed row removed.
- **Bridge-level N-arm peer triage** (PRD §9.4 full form) — lower priority.
- **Real-world TCA dogfooding** — would surface more `selected<X>` × multi-collection patterns for the filter, plus cross-cutting ergonomics.
- **Extension-split detector support** — both `CardinalityWitnessDetector` and `ReferentialIntegrityWitnessDetector` visitors only handle `StructDecl`/`ClassDecl`/`EnumDecl`, not `ExtensionDecl`. Zero corpus impact today; queue if real-world extension-split State definitions surface.

## Cycle-renumber chain (running)

Cycles 100 + 101 both shipped detector fixes interleaved with the planned calibration sequence:

| Original plan | Actual ship | Reason |
|---|---|---|
| Cycle 100 = first triage datapoint | Cycle 100 = Finding A fix (cardinality distinct-field dedupe) | Clean corpus before triage |
| Cycle 101 = second triage datapoint | Cycle 101 = Finding C fix (RefInt element-type filter) | Same — clean a second false-positive class |
| Cycle 102 = third triage datapoint | Cycle 102 = first triage datapoint (scaffold renamed) | Renumbered |

Same pattern as v1.91–v1.97 cycle-87 fixes interleaving with calibration. The detector-fix queue should be empty now (Finding A + Finding C closed; Finding B was the cross-version identity-overlap observation, not a detector bug); cycle 102 should be the actual first triage datapoint.
