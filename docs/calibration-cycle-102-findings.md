# v1.105 Calibration Cycle 102 — Findings (Finding D: bicond cardinality-overlap suppression)

Captured: 2026-05-17. swift-infer at v1.105 / SwiftPropertyLaws at v2.5.0.

## Headline

**Cycle 102 closes Finding D — surfaced by the proactive detector self-survey rather than a triage cycle.** With the detector-fix queue empty after cycles 100 + 101, the proactive survey walked all 5 detector outputs against the cycle-101 corpus looking for unflagged quality issues. The biconditional family fired 10 witnesses across the corpus; 2 of them were structurally redundant cross-pairings on Hand03's State (`isShowingSheet × activeFullScreenCover` and `isShowingAlert × activeFullScreenCover`) where the same 3 fields were already covered by Cardinality's 3-way mutual-exclusion predicate.

**Fix:** in `BiconditionalExtractor.extract`, skip bicond pairings where (a) both halves are classified as Cardinality presentation slots, AND (b) the cardinality witness covers ≥ 3 fields. The 2-slot cardinality case (where bicond is the legitimate stronger invariant) is deliberately not suppressed — the triage rubric handles cardinality-vs-bicond disambiguation for 2-slot States.

**Corpus impact:** HandRolled 17 → 15 (−2 Hand03 bicond cross-pairings). Overall: 72 → 70 occurrences, 53 → 51 unique identities. Per-family: biconditional 10 → 8 (others unchanged).

**Cycle reorder.** Cycle 102 was the scheduled first triage datapoint cycle. Shipping Finding D first preserves the fix-then-triage cadence established by cycles 100 + 101; the first triage datapoint shifts to cycle 103 (v1.106). The cycle-102 scaffold renames to `docs/calibration-cycle-103-findings.md` with denominator adjusted from 72/53 → 70/51 and the 2 suppressed bicond rows removed.

## What landed

### Detector fix (`SwiftInferTemplates`)

`BiconditionalExtractor.extract` gains a cardinality-overlap suppression step before the Cartesian pair loop:

```swift
let cardinalityFields = CardinalityFieldExtractor.extract(from: memberBlock)
let cardinalityHasThreeOrMore = cardinalityFields.count >= 3
let presentationFieldNames = Set(cardinalityFields.map(\.propertyName))
```

In the pair loop:

```swift
if cardinalityHasThreeOrMore,
   presentationFieldNames.contains(boolField.name),
   presentationFieldNames.contains(optionalField.name) {
    continue
}
```

The 3+-slot threshold is load-bearing. A 2-slot cardinality witness (e.g., `isShowingSheet` + `sheet: Sheet?`) legitimately suggests both interpretations (cardinality "at most one" + biconditional "iff non-nil"); the rubric decides which the user wants. Only 3+-slot cardinality unambiguously indicates mutual-exclusion across independent slots, and bicond cross-pairings between those slots are structural noise.

### Tests

New `Tests/SwiftInferTemplatesTests/BiconditionalPresentationOverlapTests.swift` — 6 regression tests:

1. **`threeSlotPresentationOverlapSuppressed`** — Hand03 shape; bicond witnesses suppressed.
2. **`twoSlotPresentationPairStillFires`** — 2-slot case; bicond witness preserved (the rubric handles cardinality-vs-bicond ambiguity).
3. **`nonPresentationBoolStillPairs`** — `isLoading × fact` survives because neither is a cardinality candidate.
4. **`presentationBoolWithNonPresentationOptionalSurvives`** — narrow-rule guard: presentation Bool + non-presentation Optional still pairs.
5. **`nonPresentationBoolWithPresentationOptionalSurvives`** — symmetric guard.
6. **`tcaNavigateAndLoadShapeUnaffected`** — TCA pattern preserved (`isNavigationActive × optionalCounter`; neither field matches presentation-name patterns).
7. **`hand05LoadingResultsCachedResultStillPairs`** — known noise case `isLoadingResults × cachedResult` survives because it's a semantic issue the rubric handles, not a cardinality overlap.

37 bicond tests pass total (was 31 — +7 from new suite, −1 from semantic adjustment in existing tests).

### Re-measurement at v1.105

Raw outputs in `docs/calibration-cycle-102-data/` (22 files). Per-corpus:

| Corpus | Cycle-101 | Cycle-102 | Δ |
|---|---:|---:|---:|
| HandRolled | 17 | 15 | −2 |
| TCA 1.25.5 (all 7) | 31 | 31 | 0 |
| TCA 1.0.0 (all 3) | 24 | 24 | 0 |
| **Total** | **72** | **70** | **−2** |

Per-family:

| Family | Cycle-101 | Cycle-102 | Δ |
|---|---:|---:|---:|
| Idempotence | 55 | 55 | 0 |
| Biconditional | 10 | 8 | −2 |
| Cardinality | 5 | 5 | 0 |
| Referential Integrity | 1 | 1 | 0 |
| Conservation | 1 | 1 | 0 |

Unique identities post identity-keyed dedupe: 53 → 51 (the two Hand03 bicond cross-pairing identities `0x91FF71388151015C` and `0xBF2FFDE33CF877F2` no longer fire).

## Self-survey methodology

The cycle ran a systematic walk of all 5 detector outputs against the cycle-101 raw data:

1. **Dump unique predicates per family.** Identifies pattern outliers (e.g., the cycle-100 triplicate-same-field was visible from a predicate string scan).
2. **Per-reducer witness counts per family.** Identifies reducers with multiple same-family witnesses (where Cartesian-product behavior is most visible).
3. **Cross-family overlap analysis.** Identifies reducers firing in multiple families on the same fields.
4. **Within-corpus duplicate analysis.** Identifies same-identity-hash duplicates from cross-file aggregation.

Survey findings:
- **Idempotence (55 witnesses):** clean — name-based per Action case, no Cartesian-product issues.
- **Cardinality (5 witnesses):** clean post Finding A. All 5 predicates well-formed.
- **Biconditional (10 witnesses):** **Finding D** — 2 cross-pairings on Hand03 (this fix). Plus 1 semantic noise case (`isLoadingResults × cachedResult`) that the rubric handles (not a detector fix).
- **Referential Integrity (2 → 1 post-101):** clean post Finding C.
- **Conservation (1 witness):** clean. Cartesian-product structure exists (aggregates × collections) but the corpus has only one aggregate + one collection in any one State, so no false positives. Same pattern as RefInt's pre-Finding-C case — would need a name-extraction filter if real-world code surfaces multi-collection Conservation States. **Queued as Finding E**: not actionable until corpus exhibits the pattern.
- **Cross-family overlap:** Found 1 case (PresentationReducer fires both Cardinality and Biconditional on overlapping fields) — addressed by this fix.
- **Within-corpus duplicates:** Zero post Finding A.

## Findings queue after v1.105

Closed in this cycle: **Finding D** (bicond cardinality-overlap suppression).

Queued (not actionable today):
- **Finding E (conservation Cartesian-product):** ConservationWitnessDetector pairs aggregates × collections Cartesian-style with no name filter. Corpus has only 1×1=1 case so no false positives surface. Queue for fix when real-world code or new fixtures exhibit multi-collection States with aggregates.
- **2-slot cardinality vs biconditional ambiguity:** when State has exactly 1 presentation Bool + 1 presentation Optional (e.g., `isShowingSheet` + `sheet: Sheet?`), both Cardinality and Biconditional fire. Combined acceptance would over-constrain the State. Triage rubric handles disambiguation. Could be a structural fix (prefer bicond over cardinality for 2-slot presentation cases) but the rubric is doing this job today.

## What's still in flight after v1.105

- **Cycles 103 / 104 / 105** — the three triage-datapoint cycles. Human-in-loop dependency. Cycle-103 scaffold pre-populated in `docs/calibration-cycle-103-findings.md` with updated denominator (70 / 51) and suppressed rows removed.
- **Bridge-level N-arm peer triage** (PRD §9.4 full form) — lower priority.
- **Real-world TCA dogfooding** — would surface Finding E + more bicond / RefInt edge cases.
- **Extension-split detector support** — both Cardinality and RefInt detectors only walk StructDecl/ClassDecl/EnumDecl, not ExtensionDecl. Zero corpus impact today.

## Cycle-renumber chain (running)

Three consecutive detector-fix cycles before the first triage datapoint:

| Original plan | Actual ship | Reason |
|---|---|---|
| Cycle 100 = first triage datapoint | Cycle 100 = Finding A fix | Clean corpus before triage |
| Cycle 101 = second triage datapoint | Cycle 101 = Finding C fix | Same — clean a second false-positive class |
| Cycle 102 = third triage datapoint | Cycle 102 = Finding D fix (this) | Surfaced by proactive self-survey, fix-then-triage cadence preserved |
| Cycle 103 = (etc.) | Cycle 103 = first triage datapoint (scaffold renamed) | Renumbered |

The proactive survey gives high confidence the detector-fix queue is now empty: all 5 detectors checked for Cartesian-product over-fire, malformed predicates, cross-file aggregation issues, cross-family overlap. The remaining false-positive class (`isLoadingResults × cachedResult`) is semantic noise the rubric handles, not a detector bug.
