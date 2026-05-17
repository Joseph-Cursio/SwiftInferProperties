# v1.96 Calibration Cycle 93 — Findings (Idempotence TCA action names)

Captured: 2026-05-17. swift-infer at v1.96.

## Headline

**Third family-pattern-calibration sub-cycle ships — biggest unlock
since M1.D macro recognition.** v1.96 closes sub-item #3 of
cycle-87 finding #5 — adds `task`, `delegate`, `binding` to
`IdempotenceWitnessDetector.exactNames`. Three new canonical TCA
Action-name conventions, every TCA Action enum uses at least one.

**TCA 1.25.5 interaction count: 23 → 31 (+8 idempotence).** Four
of seven examples gained witnesses, including **first detections
on SyncUps (+2) and Todos (+1)** — both had 0 interactions across
all prior cycles. VoiceMemos gained its first idempotence witness
(+2). CaseStudies +3.

**Bonus belated finding** — TCA 1.0.0 CaseStudies also gained
+1 cardinality witness from v1.94's `@Presents` recognition. Not
re-measured at cycle-4 (only TCA 1.25.5 was), surfaced this cycle.
Adds +4 idempotence on top from v1.96.

**Total cycle-6 corpus baseline: 92 reducers, 70 interactions**
(was 92 / 57 at cycle-5; +13). The largest single-cycle
interaction unlock outside the M1.D macro cycle.

After v1.96, one sub-item of cycle-87 finding #5 remains: (d)
Biconditional Effect/Task pairs.

## What landed

### A — Three exact-name additions

```swift
static let exactNames: Set<String> = [
    "refresh", "reset", "clear", "dismiss", "cancel", "close", "hide",
    "select",
    "task", "delegate", "binding"   // V1.96 cycle-93
]
```

**Semantic rationale per name:**

- **`task`** — TCA's "subscribe to a long-running effect" action.
  Conventionally wired through `.cancellable(id:)` so re-firing
  cancels-and-restarts the same subscription. State-level
  idempotent for same payload.
- **`delegate`** — payload-carrying parent-communication action.
  The child reducer typically does nothing in its body for
  `delegate(...)` cases (the parent observes them). State-no-op
  is trivially idempotent.
- **`binding`** — TCA's `BindingAction<State>` integration
  (`.binding(.set(\.$foo, value))`). Setter on a key-path;
  assigning the same value twice = same final state.

### B — Toggle deliberately excluded

`toggle` / `toggleX` / `toggleY` would be the next-obvious
candidate name pattern, but toggling toggles — applying twice
returns to original state, the canonical *non*-idempotent shape.
A new test confirms `toggle` / `toggleMenu` / `toggleChanged`
all stay unmatched. PRD §3.5 conservative-inference posture: when
the semantics don't fit, the detector errs toward not firing.

### C — 4 new tests in the existing M4.C suite

Plenty of headroom in `IdempotenceWitnessDetectorTests`
(165 → ~230 lines, under the 350 cap), so the new tests live
alongside the existing classify tests rather than in a sibling
file:

- `task` / `delegate` / `binding` classify as `.exactName`.
- Case-insensitive (`Task` / `DELEGATE` / `Binding` all match).
- `toggle` / `toggleX` stay unmatched (regression guard).
- End-to-end on a realistic TCA-shaped Action enum: 3 of 4 cases
  fire (`task`, `delegate(Delegate)`, `binding(BindingAction<State>)`);
  `incrementButtonTapped` stays unmatched.

Test count: 3038 → 3042 (+4). Idempotence M4.C suite: 11 → 15.

## Measured delta

### TCA 1.25.5 corpus

| Example | Interactions (c5 → c6) | Per-family delta |
|---|---|---|
| CaseStudies (SwiftUI) | 18 → **21** (+3) | +3 idempotence |
| UIKitCaseStudies | 4 → 4 | unchanged |
| Search | 0 → 0 | unchanged |
| SpeechRecognition | 0 → 0 | unchanged |
| SyncUps | 0 → **2** (+2) | +2 idempotence (**first detection on SyncUps**) |
| Todos | 0 → **1** (+1) | +1 idempotence (**first detection on Todos**) |
| VoiceMemos | 1 → **3** (+2) | +2 idempotence (**first idempotence on VoiceMemos**) |
| **Subtotal** | **23 → 31** (+8) | |

### TCA 1.0.0 corpus — bonus belated finding

| Example | Interactions (c2/c5 → c6) | Per-family delta |
|---|---|---|
| CaseStudies (SwiftUI) | 12 → **17** (+5) | +4 idempotence (v1.96) + **1 cardinality** (v1.94 belated) |
| UIKitCaseStudies | 4 → 4 | unchanged |
| tvOSCaseStudies | 0 → 0 | unchanged |
| **Subtotal** | **16 → 21** (+5) | |

The +1 cardinality on TCA 1.0.0 CaseStudies came from v1.94's
`@Presents` recognition but wasn't measured at cycle-4 (only TCA
1.25.5 was re-measured then). Surfaces now in the cycle-6
re-measurement — corpus measurement protocol updated to
re-measure all OSS corpora every cycle.

### Hand-rolled corpus

Unchanged at 18 interactions. Hand-rolled fixtures don't use
TCA-specific action names; the v1.96 additions are TCA-specific.

### Corpus-wide cycle-6 baseline

| Cycle | Reducers | Interactions |
|---|---|---|
| 0 (v1.89) | 29 | 114 |
| 1 (v1.91) | 29 | 34 |
| 2 (v1.92) | 42 | 35 |
| 3 (v1.93) | 92 | 56 |
| 4 (v1.94) | 92 | 57 |
| 5 (v1.95) | 92 | 57 |
| **6 (v1.96)** | **92** | **70** |

**Per-family cycle-6 breakdown (full corpus):**

- Idempotence: **55** (Hand 9 + TCA 1.25.5 26 + TCA 1.0.0 20)
- Cardinality: **8** (Hand 2 + TCA 1.25.5 5 + TCA 1.0.0 1)
- Biconditional: 4 (Hand only)
- Referential Integrity: 2 (Hand only)
- Conservation: 1 (Hand only)
- **Total: 70** across **92 reducers** (76% idempotence)

The 76% idempotence share reflects two findings together:
v1.96's unlock + cycle-91 / cycle-92's confirmation that
Cardinality and RefInt are bounded by TCA's *other* naming
conventions (enum-destination over multi-Presents; absence of
`selected*`). Idempotence's pairing rule is action-case-name
only — no companion-pattern bottleneck — and benefits maximally
from name-set expansion.

## What's next

One sub-item of cycle-87 finding #5 remains:

1. **Biconditional: Effect/Task pairs** — extend
   `BiconditionalWitnessDetector`'s pairing rules to recognize
   TCA's `Effect<X>?` / Task-style state pairs alongside the
   existing `(isLoadingX: Bool, taskX: Optional)` shape.
   Design-heavier than the prior three sub-items because the
   pairing rule has more degrees of freedom (which Bool pairs
   with which Optional? Stem-matching? Cartesian?). Smaller
   expected unlock — TCA's "is loading" state typically lives
   in the Effect's `.cancellable(id:)` registration rather than
   in State, so the pair often isn't materialized.

Plus the older queued items: N-arm interactive triage prompt
(single-repo UI) and kit-side `checkInteractionInvariantPropertyLaws`
harness (cross-repo).

After (d) ships, the v2.0 calibration arc closes for v1
scope — all 5 cycle-87 findings + their sub-items addressed. The
calibration loop proper (three cycles of stable acceptance rate
per family before tier promotion) can then begin in earnest.
