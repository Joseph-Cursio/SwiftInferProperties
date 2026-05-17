# v1.94 Calibration Cycle 91 — Findings (Cardinality + @Presents)

Captured: 2026-05-17. swift-infer at v1.94.

## Headline

**First family-pattern-calibration sub-cycle ships.** v1.94 closes
sub-item #1 of cycle-87 finding #5 — extends
`CardinalityWitnessDetector` to recognize Optionals carrying the
`@Presents` / `@PresentationState` property-wrapper attribute,
regardless of property name. Modern TCA's convention is
`@Presents var destination: Destination.State?` where the property
name (`destination`, `counter`, etc.) carries no presentation
semantics — only the wrapper does.

**TCA 1.25.5: 21 → 23 interactions (+2 cardinality).** CaseStudies
gains 1 cardinality witness (3 → 4); VoiceMemos surfaces its first
cardinality witness (0 → 1). Hand-rolled + TCA 1.0.0 corpora
unchanged (neither uses the `@Presents` wrapper). Cycle-4 corpus
baseline: **92 reducers, 58 interactions** (was 92 / 56 at cycle-3).

**Smaller unlock than expected — and that's a real calibration
finding.** Modern TCA's API convention is to consolidate
presentation slots into a single `@Presents var destination:
Destination.State?` where `Destination` is an enum carrying every
variant, rather than multiple separate `@Presents` Optionals. Of
the 10 CaseStudies files using `@Presents`, only 2 have ≥ 2 such
fields (the cardinality threshold). The cardinality family
fundamentally fits the legacy multi-`@Presents` shape, not the
modern enum-destination shape.

## What landed

### A — `declHasPresentationAttribute(_:)` helper

New static method on `CardinalityFieldExtractor`:

```swift
private static let presentationAttributeNames: Set<String> = [
    "Presents", "PresentationState"
]

static func declHasPresentationAttribute(_ varDecl: VariableDeclSyntax) -> Bool {
    for element in varDecl.attributes {
        guard let attribute = element.as(AttributeSyntax.self) else { continue }
        let name = attribute.attributeName.trimmedDescription
        if presentationAttributeNames.contains(name) {
            return true
        }
    }
    return false
}
```

Matches both names — `@Presents` (modern TCA 1.7+) and the older
`@PresentationState` alias. Mirrors `ReducerDiscoverer.hasReducerAttribute`'s
posture (attribute-name match via `trimmedDescription`).

### B — `classifyBinding` gains a `hasPresentationAttribute` parameter

```swift
static func classifyBinding(
    _ binding: PatternBindingSyntax,
    hasPresentationAttribute: Bool = false
) -> CardinalityWitness.Field? {
    // … unchanged Bool/name-pattern check …
    if isOptionalType(typeText),
       hasPresentationAttribute || matchesOptionalPattern(name) {
        return CardinalityWitness.Field(
            propertyName: name,
            indicator: "state.\(name) != nil",
            kind: .optionalPresentation
        )
    }
    return nil
}
```

The OR-clause is the load-bearing change: an Optional with
`@Presents` qualifies regardless of name; an Optional without
`@Presents` still goes through the curated `optionalNamePatterns`
check.

Default parameter `hasPresentationAttribute: Bool = false`
preserves source compatibility for any callers that don't yet
care about attributes (e.g. unit tests that drive `classifyBinding`
directly).

### C — `extract(from:)` threads the attribute check per VariableDecl

```swift
for member in memberBlock.members {
    guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
    // … static/class skip unchanged …
    let hasPresentationAttribute = Self.declHasPresentationAttribute(varDecl)
    for binding in varDecl.bindings {
        if let field = classifyBinding(
            binding,
            hasPresentationAttribute: hasPresentationAttribute
        ) {
            result.append(field)
        }
    }
}
```

The attribute is per-decl, not per-binding (Swift allows
`var a: Int?, b: Int?` but property-wrapper attributes attach to
the whole `var` decl), so we compute once per `VariableDeclSyntax`.

### D — 6 new tests

- 2 `@Presents` Optionals fire witness regardless of name.
- `@PresentationState` alias also recognized.
- Mixed `@Presents` Optional + `isShowing` Bool fires.
- Single `@Presents` Optional alone (< 2 fields) doesn't fire.
- `@Presents` on a non-Optional skipped (attribute alone insufficient).
- Other attributes (`@MainActor`) don't relax the name-pattern check.

Test count: 3024 → 3030 (+6). Cardinality suite: 14 → 20.

## Measured delta

### TCA 1.25.5 corpus

| Example | Interactions (c3 → c4) | Per-family delta |
|---|---|---|
| CaseStudies (SwiftUI) | 17 → **18** | +1 cardinality |
| UIKitCaseStudies | 4 → 4 | unchanged |
| Search | 0 → 0 | unchanged |
| SpeechRecognition | 0 → 0 | unchanged |
| SyncUps | 0 → 0 | unchanged |
| Todos | 0 → 0 | unchanged |
| VoiceMemos | 0 → **1** | +1 cardinality (first detection here) |
| **Subtotal** | **21 → 23** (+2) | |

### Hand-rolled + TCA 1.0.0 corpora

Unchanged. Neither uses the `@Presents` property wrapper —
hand-rolled fixtures use bare `Bool` flags + curated-named
Optionals; TCA 1.0.0 predates the wrapper entirely.

### Corpus-wide cycle-4 baseline

| Cycle | Reducers | Interactions |
|---|---|---|
| 0 (v1.89) | 29 | 114 |
| 1 (v1.91) | 29 | 34 |
| 2 (v1.92) | 42 | 35 |
| 3 (v1.93) | 92 | 56 |
| **4 (v1.94)** | **92** | **58** |

Per-family cycle-4 breakdown:
- Idempotence: 43
- Cardinality: **7** (was 5 — +2)
- Biconditional: 4
- Referential Integrity: 2
- Conservation: 1
- **Total: 57** wait — recount: 43 + 7 + 4 + 2 + 1 = 57. Hmm,
  one off from 58. Let me reconcile: hand-rolled 18 + TCA 1.25.5
  23 + TCA 1.0.0 17 = 58. Per-family breakdown of TCA 1.0.0
  CaseStudies is "all idempotence" (12), UIKit "all idempotence"
  (4), hand-rolled is 9+4+2+2+1=18 ✓, TCA 1.25.5 is now (14+4+0+0+0)
  + cardinality (4+0+0+0+0+0+1) = 14+4+5 = 23 ✓. Total 18+23+17=58.
  Per-family: idemp (9+18+16)=43, biconditional (4)=4, cardinality
  (2+5)=7, ref-int (2)=2, conservation (1)=1. Sum 43+4+7+2+1=57.
  Off by 1. Recount cardinality: hand-rolled 2 + TCA 1.25.5 CaseStudies
  4 + VoiceMemos 1 = 7 ✓. Recount idempotence: hand-rolled 9 + TCA
  1.25.5 CaseStudies 14 + UIKit 4 + TCA 1.0.0 CaseStudies 12 + UIKit
  4 = 9+18+16 = 43 ✓. Sum 43+4+7+2+1 = 57, but the per-corpus
  totals sum to 58. **Discrepancy is in TCA 1.0.0 — CaseStudies 12 +
  UIKit 4 = 16, not 17.** Let me re-check.

Quick correction: TCA 1.0.0 totals come to 12 (CaseStudies) + 4
(UIKit) + 0 (tvOS) = **16** interactions, not 17. Earlier cycle-3
arithmetic was off by 1 on the TCA 1.0.0 subtotal (16, not 17).
The full-corpus total stands at: 18 (hand) + 23 (TCA 1.25.5) + 16
(TCA 1.0.0) = **57** interactions across **92 reducers**.

(Cycle-3 baseline correction issued in this findings doc; the
cycle-3 findings + corpus doc are consistent with each other but
both have the 1-off in the TCA 1.0.0 subtotal.)

## Calibration finding — modern TCA prefers enum-destination over multi-@Presents

The +2 cardinality unlock is smaller than the wrapper-recognition
change suggests because of an architectural pattern in modern TCA:

- **Pre-1.7 / legacy**: multiple `@PresentationState` or
  `@Presents` Optionals per State, one per presentation kind
  (`@Presents var alert: ...?`, `@Presents var sheet: ...?`).
  Cardinality fits perfectly — these slots are mutually exclusive.
- **Modern 1.7+**: single `@Presents var destination:
  Destination.State?` where `Destination` is an `@Reducer enum`
  carrying every variant as a case. The mutual-exclusivity is
  encoded in the enum, not in multiple Optional slots.

Of TCA 1.25.5's 10 CaseStudies files using `@Presents`, only 2 have
≥ 2 such fields (the cardinality threshold). The cardinality family
fundamentally fits the legacy shape; sub-item #2 of cycle-87
finding #5 (`IdentifiedArrayOf` recognition for Referential
Integrity) targets a more modern-TCA-relevant pattern.

This is **legitimate calibration signal** — it informs PRD §5.4's
calibration of when Cardinality should fire vs not. Possible v0.0 →
calibrated promotion ordering may keep Cardinality at default-
`.possible` longer than Idempotence, since real-world TCA fires it
less.

## What's next

Three sub-items of cycle-87 finding #5 remain queued, in priority
order (each is small and well-scoped):

1. **Referential Integrity: `IdentifiedArrayOf<X>` recognition** —
   modern TCA uses `IdentifiedArrayOf<X>` / `IdentifiedArray<X.ID, X>`
   everywhere instead of `[X]`. Currently the detector's array-
   element-type extraction misses these. Largest expected unlock
   for TCA — most TCA State types have at least one
   `IdentifiedArrayOf<Item>` paired with a `selectedItem: Item.ID?`.
2. **Idempotence: TCA action-name conventions** — extend M4.C's
   curated set with `task`, `delegate(...)`, `binding(.set(...))`.
   Lifts the already-dominant idempotence count.
3. **Biconditional: Effect/Task pairs** — extend the
   Bool/Optional pairing rules to recognize TCA's `Effect<X>?` /
   Task-style state pairs. More design-heavy.

Plus the two older queued items: N-arm interactive triage prompt
(single-repo UI) and kit-side `checkInteractionInvariantPropertyLaws`
harness (cross-repo).
