# Real-world TCA dogfood — kitlangton/Hex

Captured: 2026-05-17. swift-infer at v1.110 / SwiftPropertyLaws at v2.5.0.

Sibling cycle to v1.106's [isowords dogfood](calibration-cycle-102a-findings.md). Hex (Kit Langton's voice-to-text macOS app, 2105 stars at clone time) was selected as a second real-world TCA app distinct from the calibration corpus + cycle-102a target. Pure discovery cycle — no code shipped.

## TL;DR

Two new findings surfaced (one actionable, one queued). The 100%-idempotence-only finding from cycle-102a reproduces and intensifies on Hex. Strong evidence the per-family acceptance-rate gate (PRD §3.5, 70% per family for tier promotion) needs adjustment for low-volume families (Cardinality / RefInt / Biconditional / Conservation) on real-world TCA — they may never see enough data to promote.

- **Finding I (actionable, queued)** — `Reduce(reduce)` method-ref form not detected by `ReduceClosureWalker`. Real-world TCA pattern when reducer body is extracted to a separate method for size. 1 of 5 `@Reducer`-attributed structs missed in Hex (20% local miss rate); broader real-world impact likely higher.
- **Finding J (queued, low priority)** — M1.A signature-scan produces reducer-shape false positives on non-TCA libraries (HexCore: 3 false positives). Zero impact on interaction output (downstream template engine drops them), but misleads users running `discover-reducers` directly. Cycle-89's scalar filter handles String × String but not String × `[CustomType]` or `(inout T, KeyedDecodingContainer<K>)`.
- **Reinforces Finding G + H** (cycle 102a) — Hex: 100% idempotence; calibration corpus: 78.6%; isowords: 97.7%. Real-world TCA appears to converge on idempotence-heavy distributions as the `@Presents var destination: Destination.State?` enum-routing pattern suppresses state-shape families.

## Aggregate results

| Corpus | Reducers | Interactions | Idempotence % |
|---|---:|---:|---:|
| Hex app (4 Features) | 4 | 22 | **100.0%** |
| HexCore (non-TCA library) | 3 (false positives) | 0 | n/a |
| **Hex total** | 4 (+3 FP) | 22 | 100.0% |

For comparison:

| Corpus | Reducers | Interactions | Idempotence % | Cycle |
|---|---:|---:|---:|---|
| Hex | 4 | 22 | 100.0% | this |
| isowords (post-Finding-F dedupe) | 22 unique | 21 unique | 97.7% | 102a / 103 |
| Calibration corpus (cycle 7) | 92 | 76 | 72.4% | 94 |

## Per-reducer breakdown (Hex)

| Reducer | Idempotence witnesses | Notes |
|---|---:|---|
| `SettingsFeature.body` | 16 | All `.set<X>` prefix-match — settings reducers naturally have many setter-shaped actions |
| `AppFeature.body` | 4 | `.binding`, `.task`, `.settings`, `.setActiveTab` |
| `TranscriptionFeature.body` | 2 | `.binding`, `.cancel` |
| `HistoryFeature.body` | 0 | No matching action names |
| `ModelDownloadFeature.body` | **(not detected — Finding I)** | Uses `Reduce(reduce)` method-ref form |

## Findings

### Finding I — `Reduce(reduce)` method-ref form not detected

**Status: CLOSED in v1.111.** Fix shipped immediately after this dogfood — `ReduceClosureWalker.visit(FunctionCallExprSyntax)` gained a second arm that matches `Reduce(<identifier>)` where the argument is a single unlabeled bare `DeclReferenceExpr`. Emits a candidate with the same shape as the closure form (`carrierKind: .tca`, `signatureShape: .inoutStateActionReturnsEffect`); purity defaults to `.effectBearing` since the method body lives outside the walker's reach (safe routing: subprocess verify path works for both pure and effect-bearing reducers). 8 new regression tests; Hex now detects 5 reducers / 27 interactions (was 4 / 22).

**Original report.** The `ReduceClosureWalker` introduced in cycle-71 (v1.74) walks `Reduce { state, action in ... }` closures inside a TCA `var body`. It did not match the method-reference form `Reduce(methodName)` where the body is extracted to a separate method on the conformer. This is a real-world TCA idiom — when reducer logic grows beyond a comfortable inline closure, extracting to a method is the natural refactor.

**Reproducer:** `/tmp/hex-dogfood/Hex/Features/Settings/ModelDownload/ModelDownloadFeature.swift:176`:

```swift
@Reducer
public struct ModelDownloadFeature {
    // State / Action / etc.
    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce(reduce)            // ← method reference, not detected
    }
    private func reduce(into state: inout State, action: Action) -> Effect<Action> {
        // ... 100+ lines of switch + side effects
    }
}
```

**Fix shape:** extend `ReduceClosureWalker` to also match `Reduce(<identifier>)` — a `FunctionCallExprSyntax` whose callee is `Reduce` and whose single argument is a bare identifier referencing a method. The method's signature can be inspected (already `(inout State, Action) -> Effect<Action>` — matches v1.83's `inoutStateActionReturnsEffect` shape). The state + action types come from the enclosing struct's nested `State` / `Action` (same path as the closure case).

**Corpus impact:** unchanged (calibration corpus has no method-ref-form bodies). **Real-world impact:** 1/5 reducers in Hex (20%); higher in larger TCA apps where extracting complex reducers is more common.

**Why deferred:** Hex was a single dogfood datapoint. Want a second datapoint (third TCA app) before shipping a fix to confirm this isn't a one-off and to size the surface correctly.

### Finding J — M1.A signature-scan false positives on non-TCA libraries

**Status: queued, low priority.** HexCore is a non-TCA Swift library (no `import ComposableArchitecture`). M1.A's signature-scan (PRD v2.0 §6.2 three canonical shapes) doesn't gate on TCA; it just walks every function. Three HexCore functions match the reducer shape but are not actually reducers:

| Function | Shape | What it actually does |
|---|---|---|
| `WordRemappingApplier.apply(_:to:)` | `(String, [WordRemapping]) -> String` | Pure transformation — applies a list of word remappings to a string |
| `WordRemovalApplier.apply(_:to:)` | `(String, [WordRemoval]) -> String` | Pure transformation — applies a list of word removals to a string |
| `AnySettingsField.decode(into:from:)` | `(inout HexSettings, KeyedDecodingContainer<HexSettingKey>) -> Void` | Codable decoder — applies decoded field to settings |

**Impact:** zero on interaction output (template engine finds no Conservation / Cardinality / RefInt / Biconditional / Idempotence patterns in these because the "state" type is `String` or `HexSettings` without the right shape, and the "action" types aren't enums with idempotent-name cases). But `discover-reducers --target HexCore` shows 3 misleading entries.

**Fix shape options:** (a) gate M1.A on `import ComposableArchitecture` (matches M1.B/M1.D's gating); (b) extend cycle-89's scalar-filter list to include "obvious-non-action" types like `KeyedDecodingContainer`, `[CustomType]` where the type doesn't look like an enum; (c) post-hoc filter — only render M1.A candidates if their interaction-template-engine output is non-empty.

**Why deferred:** misleading-but-zero-impact. The interaction loop already drops these. Fix when the user-facing `discover-reducers` output noise becomes a complaint.

### Finding G reinforced — modern TCA suppresses non-idempotence

Cycle-102a's Finding G: modern TCA's `@Presents var destination: Destination.State?` enum-routing pattern suppresses Cardinality (no ≥ 2 presentation slots — collapsed into one Destination), RefInt (no `selected*` properties), and Biconditional (no Loading/Showing name matches).

Hex confirms and intensifies: **zero** Cardinality / RefInt / Biconditional / Conservation witnesses. Hex doesn't even use `@Presents` — its navigation is tab-based (`var activeTab: Tab`) and modal state lives in feature-level State (Transcription's recording flow, Settings's various sheets). State shape is entirely "scalar-toggle + tab-enum" with zero presentation Optionals.

### Finding H reinforced — real-world TCA is idempotence-heavy

| Corpus | Idempotence share |
|---|---:|
| Calibration corpus (cycle 7) | 72.4% |
| isowords (cycle 102a, post-dedupe) | 97.7% |
| Hex (this cycle) | **100.0%** |

The calibration corpus's HandRolled portion is what keeps non-idempotence non-zero. Real-world TCA appears to converge on idempotence-only distributions.

**Calibration implication (sharpened):** the per-family ≥ 70% acceptance-rate gate (PRD §3.5) for tier promotion is **structurally inapplicable** to Cardinality / RefInt / Biconditional / Conservation in real-world TCA — these families would need either a dramatically different real-world target (e.g., a TCA app explicitly using `@Presents` heavily) or a relaxed promotion criterion (e.g., absolute count threshold instead of rate, or per-corpus-context promotion).

## Methodology notes

1. **Symlink doesn't work** for swift-infer's directory walker. First attempt used `ln -s ../Hex Sources/Hex`; discover-reducers found 0. `cp -R Hex Sources/Hex` (real copy) worked. Worth noting in user docs if the workdir setup story is documented anywhere — symlinking is the natural first instinct for "point swift-infer at a real codebase."
2. **Hex's structure**: Xcode project + sibling SwiftPM package (`HexCore/`). The main app source lives in `Hex/` (Xcode-managed). The symlink/copy trick is needed to fit swift-infer's `Sources/<target>/` resolution.
3. **Coverage**: 30 of Hex's source files (`grep -l "import ComposableArchitecture"`) → 4-of-5 reducers discovered (`ReduceClosureWalker` misses the method-ref form). Detection rate is structural, not file-level — every file walked, but only certain body shapes match.

## What's next

- **No code shipped this cycle.** Two new findings queued: Finding I (actionable, real-world-visible, queue for next fix cycle) and Finding J (queued, low priority).
- **A third dogfood cycle** would help size Finding I's real-world frequency before shipping a fix. Candidate targets: EhPanda (3843 stars, large TCA app — content domain awkward but code is just code), or another community TCA app via `gh search code`.
- The cycle-104 human-triage path remains the dominant blocker for tier promotion in the calibration loop. This dogfood cycle reinforces that no amount of detector polish moves the per-family acceptance-rate signal forward — that needs human decisions on the 51 unique-identity surface.

## Raw outputs

Persisted at `docs/calibration-dogfood-hex-data/` — 4 files (Hex-reducers.txt, Hex-interaction.txt, HexCore-reducers.txt, HexCore-interaction.txt).
