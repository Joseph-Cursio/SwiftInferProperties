# v1.97 Calibration Cycle 94 — Findings (Biconditional inferred Bool)

Captured: 2026-05-17. swift-infer at v1.97.

## Headline

**Fourth family-pattern-calibration sub-cycle ships — closes the
cycle-87 arc.** v1.97 closes sub-item #4 of cycle-87 finding #5,
the last queued v2.0 detector fix. `BiconditionalWitnessDetector`
now recognizes Bool fields declared without an explicit `: Bool`
annotation but with a `true` / `false` literal initializer
(modern TCA's `var isLoading = false` idiom).

**Biconditional fires on real TCA for the first time.** TCA 1.25.5
+3, TCA 1.0.0 +3 — both via the inferred-Bool detection path
unlocking `(fact: String?, isLoading: <inferred Bool>)`-shape
pairs. Hand-rolled unchanged (already uses explicit annotations).

**Cycle-7 corpus baseline: 92 reducers, 76 interactions** (was
92 / 70 at cycle-6; +6 biconditional).

**Design pivot from the cycle-87 framing**. Sub-item (d) was
originally scoped as "extend pairing rules to recognize TCA's
`Effect<X>?` / Task-style state pairs alongside `(isLoadingX:
Bool, taskX: Optional)`". On inspecting real TCA code, the actual
blocker turned out to be different: the existing pairing rule
was already unconstrained on the Optional side (any Optional
qualifies, including Effect / Task / String? / etc.) — but the
**Bool side** required an explicit `: Bool` annotation, which
modern TCA almost never uses. The fix delivers what the spirit
of sub-item (d) intended (make Biconditional fire on real TCA)
by addressing the actual gap.

**All 5 cycle-87 findings + 4 sub-items closed. v2.0 calibration
arc closes for v1 scope.** The three-cycle calibration loop the
§19 metrics measure against — three cycles of stable acceptance
rate per family before tier promotion — can now begin in earnest.

## What landed

### A — Inferred-Bool path in `classifyBinding`

Before (v1.96):

```swift
guard let typeAnnotation = binding.typeAnnotation else { return }
let typeText = typeAnnotation.type.trimmedDescription
if isBoolType(typeText), nameLooksLikeBiconditionalFlag(name) {
    boolFlags.append((name, typeText))
}
```

After (v1.97):

```swift
if let typeAnnotation = binding.typeAnnotation {
    // … existing annotation-bearing path, unchanged …
    return
}
if isBoolLiteralInitializer(binding.initializer?.value),
   nameLooksLikeBiconditionalFlag(name) {
    boolFlags.append((name, "Bool"))
}
```

New helper `isBoolLiteralInitializer(_:) -> Bool` checks whether
an expression is a `BooleanLiteralExprSyntax` (matches `true` and
`false` literals). The Optional half stays annotation-required
because `nil` literals don't carry enough info to infer the
Optional's wrapped type, and `Optional<X>(...)` constructor
expressions would be a separate, lower-value extension.

The branch order matters: annotation-bearing bindings short-circuit
through the existing code path unchanged, preserving every
cycle-93 test exactly. The inferred-Bool branch only fires when
the binding has *no* type annotation.

### B — 7 new tests in new `BiconditionalInferredBoolTests` suite

Sibling to the M7 suite (keeps both files under SwiftLint's
type-body length cap):

- `var isLoading = false` paired with `var fact: String?` fires.
- `var isActive = true` (literal-true variant) also fires.
- String-literal initializer (`var isLoading = "false"`) doesn't
  trigger Bool inference.
- Int-literal initializer (`var isLoading = 0`) doesn't trigger.
- Inferred Bool with non-matching name (`var isEnabled = false`)
  doesn't fire — still gated on `nameLooksLikeBiconditionalFlag`.
- Explicit `: Bool = false` still works (regression guard).
- Mixed inferred + explicit Bools in the same State all surface
  via Cartesian product.

Test count: 3042 → 3049 (+7). Biconditional M7 suites: 1 → 2.

## Measured delta

### TCA 1.25.5 corpus

| Example | Interactions (c6 → c7) | Per-family delta |
|---|---|---|
| CaseStudies (SwiftUI) | 21 → **23** (+2) | +2 biconditional |
| UIKitCaseStudies | 4 → **5** (+1) | +1 biconditional |
| Search | 0 → 0 | unchanged |
| SpeechRecognition | 0 → 0 | unchanged |
| SyncUps | 2 → 2 | unchanged |
| Todos | 1 → 1 | unchanged |
| VoiceMemos | 3 → 3 | unchanged |
| **Subtotal** | **31 → 34** (+3) | |

### TCA 1.0.0 corpus

| Example | Interactions (c6 → c7) | Per-family delta |
|---|---|---|
| SwiftUICaseStudies | 17 → **19** (+2) | +2 biconditional |
| UIKitCaseStudies | 4 → **5** (+1) | +1 biconditional |
| tvOSCaseStudies | 0 → 0 | unchanged |
| **Subtotal** | **21 → 24** (+3) | |

### Hand-rolled corpus

Unchanged at 18 interactions. Hand05_Biconditional.swift uses
explicit `var isLoadingResults: Bool` — the annotation-bearing
path was already firing pre-v1.97.

### Corpus-wide cycle-7 baseline

| Cycle | Reducers | Interactions |
|---|---|---|
| 0 (v1.89) | 29 | 114 |
| 1 (v1.91) | 29 | 34 |
| 2 (v1.92) | 42 | 35 |
| 3 (v1.93) | 92 | 56 |
| 4 (v1.94) | 92 | 57 |
| 5 (v1.95) | 92 | 57 |
| 6 (v1.96) | 92 | 70 |
| **7 (v1.97)** | **92** | **76** |

**Per-family cycle-7 breakdown (full corpus):**

- Idempotence: 55 (Hand 9 + TCA 1.25.5 26 + TCA 1.0.0 20)
- Biconditional: **10** (Hand 4 + TCA 1.25.5 3 + TCA 1.0.0 3) — **up from 4**
- Cardinality: 8 (Hand 2 + TCA 1.25.5 5 + TCA 1.0.0 1)
- Referential Integrity: 2 (Hand only)
- Conservation: 1 (Hand only)
- **Total: 76** across **92 reducers**

Biconditional moves from 5.7% → 13.2% share. Idempotence
share drops slightly from 78.6% → 72.4% as the corpus diversifies.

## What's next — the calibration loop proper

The v2.0 calibration arc closes here. All 5 cycle-87 findings + 4
sub-items addressed:

**Closed findings**:
- **#1** (two-scalar false positive) — v1.92.
- **#2** (bare-`State` / bare-`Action` cross-contamination) — v1.91.
- **#3** (M1.B blind to `@Reducer` macro) — v1.93.
- **#4** (M1.A 4th-shape extension) — v1.92.
- **#5** family-pattern calibration, in four sub-items:
  - (a) Cardinality `@Presents` — v1.94.
  - (b) RefInt `IdentifiedArrayOf` — v1.95.
  - (c) Idempotence TCA action names — v1.96.
  - (d) Biconditional inferred Bool — v1.97.

The **three-cycle calibration loop the PRD §19 metrics measure
against** can now begin. Per-family acceptance-rate measurement
needs:

1. **Decision-recording on the corpus** — `swift-infer
   accept-interaction` already exists (v1.88). For calibration,
   the cycle-7 baseline numbers become the denominator; each
   suggestion gets accepted / rejected / skipped to produce the
   numerator. The hand-rolled corpus's 18 suggestions and TCA's
   58 are a manageable triage workload — likely a single
   afternoon's gesture per cycle.

2. **Three cycles of stable acceptance rate per family** — PRD
   §3.5 corollary. After three cycles where each family's
   acceptance rate sits in a narrow band, that family promotes
   from default-`.possible` to `.likely` (≥ 40% → ≥ 70% threshold,
   PRD §4.2). Strong tier requires verified-via-`verify-interaction`
   evidence on top.

3. **PRD §19 success bar** — ≥ 70% acceptance rate at promoted
   tier, measured against the cycle-7 corpus baseline.

The detector-fix queue is empty; the measurement-loop queue is
the new active surface. Sibling threads remain:

- **N-arm interactive triage prompt** (PRD §9.4) — UI work to
  walk a user through the accept/reject decisions efficiently.
  Mechanical wrapper around `accept-interaction` recorder.
- **Kit-side `checkInteractionInvariantPropertyLaws` harness**
  (cross-repo) — third cross-repo cycle after M2 and M9. Wires
  v2.3.0 conformances to auto-run on every CI invocation.

Either thread could pick up next; both unblock different aspects
of the calibration loop's UX.
