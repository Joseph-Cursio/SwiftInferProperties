# Real-world TCA dogfood — renaudjenny/HeuresCreuses

Captured: 2026-05-17. swift-infer at v1.111 / SwiftPropertyLaws at v2.5.0.

Third real-world TCA dogfood after [isowords](calibration-cycle-102a-findings.md) (v1.106) and [Hex](calibration-dogfood-hex-findings.md) (this cycle). Selected as a smaller community TCA app for fast iteration + to size [Finding I](calibration-dogfood-hex-findings.md#finding-i--reducereduce-method-ref-form-not-detected)'s real-world frequency now that the fix shipped at v1.111. Pure discovery cycle — no code shipped.

HeuresCreuses is a French electricity-tariff utility (iOS / Apple Watch / macOS) — "off-peak hours" calendar that finds the best delay to start dishwasher / washing machine programs. 3 stars, last updated 2025-02-23. SwiftPM-shaped (no Sources/ symlink trick needed).

## TL;DR

**Clean.** Zero new findings. Detection works correctly across all 4 substantial TCA targets. **Reinforces the 100%-idempotence trend** for a fourth real-world TCA codebase. v1.111's Finding I fix had **zero impact** here (no `Reduce(<methodName>)` forms in the codebase) — confirms the fix is non-regressing on real-world TCA without the targeted pattern.

| Metric | Value |
|---|---|
| Reducers detected | 15 across 4 targets |
| Interactions surfaced | 11 |
| Per-family share | **100% idempotence** |
| `Reduce(<methodName>)` forms | 0 |
| `Reduce { state, action in ... }` forms | 14 |
| New findings | 0 |

## Per-target breakdown

| Target | Reducers | Interactions |
|---|---:|---:|
| `ApplianceFeature` | 9 | 4 |
| `OffPeak` | 2 | 2 |
| `UserNotification` | 2 | 4 |
| `AppFeature` | 1 | 0 |
| `SendNotification` | 1 | 1 |
| `Models` | 0 | 0 |
| `UserNotificationsClientDependency` | 0 | 0 |
| `HomeWidget` | 0 | 0 |
| **Total** | **15** | **11** |

All 15 reducers are TCA `body` shape (`.inoutStateActionReturnsEffect` signature, `.tca` carrier) discovered via the v1.74 closure-form walker. The 11 interactions are all idempotence witnesses matching TCA-convention action names.

## Predicate distribution

| Predicate | Count | Match arm |
|---|---:|---|
| `.task` | 7 | exact (cycle 93) |
| `.cancel` | 2 | exact |
| `.binding` | 1 | exact (cycle 93) |
| `.delegate` | 1 | exact (cycle 93) |
| **Total** | **11** | |

All 11 predicates map cleanly to `IdempotenceWitnessDetector.exactNames`. No prefix-rule matches, no unusual patterns. Heavily skewed toward `.task` (64% of all interactions) — typical of TCA apps with multiple long-running effect subscriptions.

## What the absence of non-idempotence confirms

| Family | Count | Why |
|---|---:|---|
| Cardinality | 0 | No `@Presents` slots, no `isShowing*` × `isShowing*` patterns. State shape is utility-app-flat. |
| Referential Integrity | 0 | No `selected<X>` Optionals. |
| Biconditional | 0 | No `isLoading == (X != nil)` patterns. State uses optionals directly. |
| Conservation | 0 | No `count == array.count` patterns. |

This is now the **fourth** real-world TCA codebase confirming the cycle-102a Finding G observation: modern TCA's idiomatic State shape suppresses non-idempotence-family detection at any non-trivial rate.

## Cross-dogfood idempotence convergence

Updated rollup:

| Corpus | Reducers | Interactions | Idempotence share |
|---|---:|---:|---:|
| Calibration corpus (cycle 7) | 92 | 76 | 72.4% |
| isowords (cycle 102a, post-Finding-F) | 22 | 21 | 97.7% |
| Hex (cycle dogfood-hex) | 5 | 27 | 100.0% |
| HeuresCreuses (this cycle) | 15 | 11 | **100.0%** |
| **Real-world TCA combined** | **42** | **59** | **98.3%** |

The calibration corpus's HandRolled fixtures are essentially the only thing driving non-idempotence-family counts in the project. Real-world TCA converges on idempotence-only.

**Implication for PRD §3.5 calibration:** the 70% per-family acceptance-rate gate for tier promotion is structurally inapplicable to Cardinality / RefInt / Biconditional / Conservation on real-world TCA — these families would need a different promotion criterion (absolute count threshold, or per-corpus-context promotion). The Hex findings doc surfaced this as a sharpened call; HeuresCreuses is the third independent confirmation.

## Finding I sizing (post-v1.111)

| Codebase | Reducers (closure-form) | Reducers (method-ref form) | Method-ref share |
|---|---:|---:|---:|
| Hex (cycle dogfood-hex) | 4 | 1 (`ModelDownloadFeature`) | **20%** |
| HeuresCreuses (this cycle) | 15 | 0 | **0%** |
| Combined | 19 | 1 | **5%** |

Two-datapoint estimate: ~5% of real-world TCA reducers use the `Reduce(<methodName>)` extracted-method form. Hex's 20% local rate was inflated by being a 5-reducer codebase. The fix was still worth shipping (catches the entire blind spot), but the production-wide pattern frequency is single-digit. Stays on the fix-when-found posture for similar future-discovery-time gaps.

## What's next

- **No code shipped.** Detector is healthy across all 4 real-world dogfoods (isowords, Hex, HeuresCreuses, plus the project's own calibration corpus).
- **Cycle 104 human triage remains the dominant blocker** for tier promotion. Three real-world dogfoods don't help with that — only human acceptance/rejection decisions on the existing 51 unique-identity surface do.
- **Detector-fix queue genuinely empty** at v1.111: Finding I closed, Finding J still queued (low priority), no new findings from this cycle.

## Raw outputs

Persisted at `docs/calibration-dogfood-heurescreuses-data/` — 16 files (8 targets × 2 commands).
