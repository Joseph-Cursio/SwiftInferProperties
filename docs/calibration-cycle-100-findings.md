# v1.103 Calibration Cycle 100 — Findings (Finding A: cardinality distinct-field dedupe)

Captured: 2026-05-17. swift-infer at v1.103 / SwiftPropertyLaws at v2.5.0.

## Headline

**Cycle 100 closes Finding A from the cycle-99 cycle-100 scaffold — the `CardinalityWitnessDetector` cross-file aggregation bug.** The directory-walk entry concatenated fields across files without deduping by property name. Three TCA 1.25.5 SharedState files each independently declared `CounterTab.State { var alert: AlertState? }`; the suffix-matcher matched all three distinct types and naively appended each field set to a single `allFields` array, producing a 3-copy `alert` field array that satisfied the `≥ 2` guard and emitted the predicate `(state.alert != nil) + (state.alert != nil) + (state.alert != nil) <= 1` (mathematically `state.alert == nil` — not a cardinality bound).

**Fix:** add a `propertyName`-based dedupe between the cross-file aggregation and the `≥ 2` guard. The duplicated `alert` collapses to one entry, fails the guard, no witness fires — correct behavior (a single Optional doesn't have a cardinality invariant). Legitimate field accumulation across files with distinct names is unaffected (dedupe is a no-op when names don't collide).

**Corpus impact:** TCA 1.25.5 CaseStudies 23 → 20 interaction suggestions (−3 the CounterTab triplicate). Overall corpus baseline 76 → 73 occurrences, 55 → 54 unique identities. Per-family: cardinality 8 → 5 (others unchanged).

**Cycle reorder.** Cycle 100 was originally scheduled as the first triage datapoint cycle (per the v1.101 cycle-98 cadence plan). Shipping the Finding A fix first cleans the corpus before triage — preserves the same pattern as v1.91–v1.97 cycle-87 detector fixes interleaving with the calibration loop. The first triage datapoint shifts to cycle 101 (v1.104); the cycle-100 scaffold renames to `docs/calibration-cycle-101-findings.md`.

## What landed

### Detector fix (`SwiftInferTemplates`)

`CardinalityWitnessDetector.detect(stateTypeName:in directory:)` gains a private `deduplicateByPropertyName(_:)` helper that drops later occurrences of a `propertyName` already seen. Called between the `allFields.append(contentsOf:)` aggregation and the `≥ 2` guard:

```swift
let dedupedFields = deduplicateByPropertyName(allFields)
return dedupedFields.count >= 2
    ? [CardinalityWitness(fields: dedupedFields)]
    : []
```

The single-source entry (`detect(stateTypeName:in source:)`) is unaffected — a single file can't legitimately have two top-level type declarations of the same name in the same scope (compile error).

**Why deduplicate at this layer, not at field-extraction time:** the bug only manifests in the directory walk's aggregation step. Field extraction within one parsed source file is correct (one visitor walk = one field set per matching type). Pushing the dedupe higher would conflate two distinct concerns (within-file extraction vs cross-file aggregation).

### Tests

New `Tests/SwiftInferTemplatesTests/CardinalityDistinctFieldDedupeTests.swift` — 4 regression tests:

1. **`multiFileSameNameSingleField`** — the cycle-100 bug case. Three files each declaring `CounterTab.State { var alert: ...? }`. Pre-fix: malformed predicate emitted. Post-fix: dedupe collapses to 1 field, no witness fires (correct).
2. **`multiFileDifferentFieldsAggregates`** — two files declaring `AppState` with non-overlapping fields (`activeSheet`, `activeAlert`). Dedupe is a no-op; witness fires with both. Documents that the cross-file aggregation behavior is preserved when names don't collide.
3. **`multiFileOverlapStillProducesValidPredicate`** — mixed case: three files, two declaring `activeSheet` (collapses to 1), one declaring `activeAlert`. Post-dedupe: 2 distinct fields, well-formed witness.
4. **`singleFileDetectionPathUnchanged`** — the single-source entry is unaffected by the fix.

The doc comments capture an aside: the original detector's "extension split" doc comment was aspirational — the visitor only handles `StructDecl` / `ClassDecl` / `EnumDecl`, not `ExtensionDecl`. The cross-file aggregation was real, the extension support was not. Worth a future detector cycle if extension-split State definitions become a real-world hit, but currently zero impact on the corpus.

### Re-measurement at v1.103

Raw outputs persisted to `docs/calibration-cycle-100-data/` (22 files mirroring the cycle-98 layout). Per-corpus totals:

| Corpus | Cycle-98 | Cycle-100 | Δ |
|---|---:|---:|---:|
| HandRolled | 18 | 18 | 0 |
| TCA 1.25.5 CaseStudies | 23 | 20 | −3 |
| TCA 1.25.5 UIKitCaseStudies | 5 | 5 | 0 |
| TCA 1.25.5 Search | 0 | 0 | 0 |
| TCA 1.25.5 SpeechRecognition | 0 | 0 | 0 |
| TCA 1.25.5 SyncUps | 2 | 2 | 0 |
| TCA 1.25.5 Todos | 1 | 1 | 0 |
| TCA 1.25.5 VoiceMemos | 3 | 3 | 0 |
| TCA 1.0.0 CaseStudies | 19 | 19 | 0 |
| TCA 1.0.0 UIKitCaseStudies | 5 | 5 | 0 |
| TCA 1.0.0 tvOSCaseStudies | 0 | 0 | 0 |
| **Total** | **76** | **73** | **−3** |

Per-family:

| Family | Cycle-98 | Cycle-100 | Δ |
|---|---:|---:|---:|
| Idempotence | 55 | 55 | 0 |
| Biconditional | 10 | 10 | 0 |
| Cardinality | 8 | 5 | −3 |
| Referential Integrity | 2 | 2 | 0 |
| Conservation | 1 | 1 | 0 |

Unique identities post identity-keyed dedupe: 55 → 54 (the `CounterTab.body` identity `0x75CF20AD5DDBE3B1` no longer fires).

## Why the fix matters for the calibration loop

The malformed CounterTab predicate would have wasted a calibration decision: the rater would have triaged `0x75CF20AD5DDBE3B1` once (identity-keyed) but the decision would have been recording "is the predicate `(alert != nil) + (alert != nil) + (alert != nil) <= 1` a useful invariant for `CounterTab.body`?" — a question with no useful answer (the predicate is malformed regardless of the reducer's actual semantics). Cycle 100's fix removes this noise before the first triage datapoint lands in cycle 101, so the acceptance-rate measurement reflects real detector quality, not detection-emission bugs.

## What's still in flight after v1.103

- **Cycles 101 / 102 / 103** — the three triage-datapoint cycles. Human-in-loop dependency. Cycle-101 scaffold pre-populated in `docs/calibration-cycle-101-findings.md`.
- **Bridge-level N-arm peer triage** (PRD §9.4 full form) — lower priority.
- **Real-world TCA dogfooding** — lowest velocity, highest cross-cutting signal.
- **Finding C (cycle-99 scaffold)** — RefInt type-compatibility filter. Still pre-flagged; worth a fix cycle after the first triage datapoint confirms the false-positive shape.
- **Extension-split CardinalityWitnessDetector support** — the doc comment promised it but the visitor doesn't actually walk `ExtensionDecl`. Zero corpus impact today; queue if a real-world case surfaces.

## Notes on the cycle-renumber

The cycle-100 scaffold (committed in `a48db41`) anticipated cycle 100 as the first triage datapoint. Shipping the Finding A fix as cycle 100 instead is the cleaner option: cleaning the corpus before triage avoids contaminating the first acceptance-rate measurement. The scaffold rename (`calibration-cycle-100-findings.md` → `calibration-cycle-101-findings.md`) preserves the prepped worksheet — the CounterTab row is removed in the rename, and the denominator + headline are adjusted from 76/55 to 73/54.

Pattern precedent: v1.91 – v1.97 cycle-87 finding-fix cycles each shipped between corpus-measurement cycles. The interleaving is intentional — fix the detector, re-measure, then proceed to the next calibration step.
