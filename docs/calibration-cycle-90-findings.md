# v1.93 Calibration Cycle 90 — Findings (M1.D `@Reducer` macro)

Captured: 2026-05-17. swift-infer at v1.93.

## Headline

**Biggest M1 unlock since v2.0 began.** v1.93 closes cycle-87
finding #3 (M1.B blind to `@Reducer` macro) by adding a parallel
attribute-walker path. New `hasReducerAttribute(_:)` static helper
checks each type-decl's `AttributeListSyntax` for `@Reducer`; the
existing `extractTCACandidatesIfReducerConformer` fires on
**either** inheritance-clause `: Reducer` (M1.B) **or** `@Reducer`
attribute (M1.D).

**TCA 1.25.5: 0 → 50 reducers, 0 → 21 interactions.** Every
example in the modern TCA corpus now surfaces. 18 idempotence + 3
cardinality witnesses — the 3 cardinality detections are the
**first non-idempotence family ever to fire on real TCA** across
both pinned TCA versions.

**Cycle-3 corpus baseline: 92 reducers, 56 interactions** (was 42 /
35 at cycle-2). All four bug-fix-shaped cycle-87 findings now
closed (#1, #2, #3, #4). Only #5 — family-pattern calibration —
remains, and cycle-3's data is the strongest evidence yet that it
is the dominant remaining gap.

## What landed

### A — `hasReducerAttribute(_:)` static helper

```swift
static func hasReducerAttribute(_ attributes: AttributeListSyntax) -> Bool {
    for element in attributes {
        guard let attribute = element.as(AttributeSyntax.self) else { continue }
        let name = attribute.attributeName.trimmedDescription
        if name == "Reducer" {
            return true
        }
    }
    return false
}
```

Matches the literal attribute name `Reducer` and handles the
parameterized form `@Reducer(state: .equatable)` transparently
(both have the same `attributeName.trimmedDescription`). Pure
function, mirrors `declaresReducerConformance`'s posture.

### B — Threading `attributes` through 4 visitor entry points

`StructDeclSyntax`, `ClassDeclSyntax`, `EnumDeclSyntax`, and
`ExtensionDeclSyntax` now pass their `attributes` parameter into
`extractTCACandidatesIfReducerConformer`. The gate becomes:

```swift
guard importsComposableArchitecture else { return }
let viaConformance = Self.declaresReducerConformance(inheritanceClause)
let viaMacro = Self.hasReducerAttribute(attributes)
guard viaConformance || viaMacro else { return }
```

The body-walk logic is shared and idempotent for a single decl —
a type satisfying both forms (`@Reducer struct Foo: Reducer`)
emits one set of candidates, not two.

### C — 8 new tests in `ReducerDiscovererMacroAttributeTests`

Split into a sibling file (not bloating the existing
`ReducerDiscovererTCATests` which is the M1.B-only suite):

- Bare `@Reducer struct Foo` (no inheritance clause) detected.
- Parameterized `@Reducer(state: .equatable)` detected.
- `@Reducer struct Foo: Reducer` (both forms) emits 1 not 2.
- Multiple `Reduce` closures in one body all surface.
- `@Reducer` without `import ComposableArchitecture` skipped.
- `private @Reducer struct` skipped (matches function-scan posture).
- `@Reducer enum Path` with no body emits 0 (composition shape).
- `@MainActor struct Foo` (non-`Reducer` attribute) doesn't fire.

Total test count 3016 → 3024 (+8). M1 suites now: 3 (signature
scan + shape-4/scalar + TCA conformance walk) → 4 (adds macro
attribute).

## Measured delta

### TCA 1.25.5 corpus — the load-bearing unlock

| Example | Reducers (c2 → c3) | Interactions (c2 → c3) |
|---|---|---|
| CaseStudies (SwiftUI) | 0 → **36** | 0 → **17** (14 idempotence + 3 cardinality) |
| UIKitCaseStudies | 0 → **3** | 0 → **4** (all idempotence) |
| Search | 0 → **1** | 0 → 0 |
| SpeechRecognition | 0 → **1** | 0 → 0 |
| SyncUps | 0 → **5** | 0 → 0 |
| Todos | 0 → **1** | 0 → 0 |
| VoiceMemos | 0 → **3** | 0 → 0 |
| **Subtotal** | **0 → 50** | **0 → 21** |

### TCA 1.0.0 + hand-rolled corpora

Unchanged at cycle-2 numbers — these don't use `@Reducer` macro
(or use it sparingly). TCA 1.0.0 retains the 35 reducers and 17
interactions captured at cycle-2.

### Corpus-wide cycle-3 baseline

| Cycle | Reducers | Interactions |
|---|---|---|
| 0 (v1.89) | 29 | 114 |
| 1 (v1.91) | 29 | 34 |
| 2 (v1.92) | 42 | 35 |
| **3 (v1.93)** | **92** | **56** |

### Per-family breakdown (cycle-3, full corpus)

| Family | Hand-rolled | TCA 1.25.5 | TCA 1.0.0 | Total |
|---|---|---|---|---|
| Idempotence | 9 | 18 | 16 | 43 |
| Biconditional | 4 | 0 | 0 | 4 |
| Referential Integrity | 2 | 0 | 0 | 2 |
| Cardinality | 2 | **3** | 0 | 5 |
| Conservation | 1 | 0 | 0 | 1 |
| **Total** | **18** | **21** | **17** | **56** |

**Cardinality fires on TCA 1.25.5 for the first time** (3 witnesses
in SwiftUICaseStudies, from State types with `Showing` /
`Presenting` Bool fields or `sheet` / `alert` Optional fields).
Conservation, referential integrity, and biconditional remain at
0 on TCA — the gap is M4.C / M5 / M6 / M7 pattern coverage of TCA's
`@PresentationState` wrapper, `IdentifiedArrayOf<X>` collections,
and Action-name conventions like `task` / `delegate(...)` /
`binding(.set(...))`.

## What's next

Only one cycle-87 finding remains, and it's the actual calibration
loop the §19 metrics measure against:

1. **Family-pattern calibration for real TCA conventions** —
   cycle-3 is the strongest evidence yet that this is the dominant
   remaining gap. With M1.D unlocking 50 modern-TCA reducers,
   only 21 interactions surface (idempotence 18 + cardinality 3).
   Conservation / referential integrity / biconditional fire 0
   times on the entire TCA corpus.

Concrete sub-items the calibration loop should address:

- **Cardinality**: detect `@PresentationState alert:
  AlertState<X>?` / `@Presents` wrapped Optionals as cardinality
  inputs alongside the existing bare `isShowingX: Bool` pattern.
- **Referential Integrity**: detect `IdentifiedArrayOf<X>` /
  `IdentifiedArray<X.ID, X>` as collection shapes alongside `[X]`.
- **Biconditional**: detect TCA's `Effect<X>?` / Task-style state
  pairs alongside the existing `(isLoadingX: Bool, taskX:
  TaskHandle?)` pattern.
- **Idempotence**: extend M4.C's curated set to recognize TCA's
  conventional non-mutating action names (`task`, `delegate(...)`,
  `binding(.set(...))`).

Each is a small, measurable change — the three-cycle calibration
loop fires on each in turn, with the corpus baseline as the
denominator for acceptance-rate measurement.
