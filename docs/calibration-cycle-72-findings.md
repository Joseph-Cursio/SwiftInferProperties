# v1.75 Calibration Cycle 72 — Findings (V2.0.M1.C: M1 complete)

Captured: 2026-05-15. swift-infer at v1.75.

## Headline

**M1 is done.** M1.A (cycle 70 / v1.73 — signature scan against three
canonical reducer shapes) + M1.B (cycle 71 / v1.74 — TCA `Reducer.body`
conformance walk + 4th synthesized shape) + M1.C (this cycle / v1.75 —
`.elmStyle` differentiation + `--reducer` pinning + calibration corpus
skeleton) close the first PRD §5.8 milestone. Reducer discovery is the
foundation every later v2.0 milestone (M2 ActionSequenceGenerator
through M9 InteractionInvariantBridge) builds on.

Cycle-66's **52/103 = 50.5% measured-execution** carries forward
unchanged — v1.75 touches no v1 emitter / resolver / carrier path.

## What M1.C settled (cycle-by-cycle recap)

Three sub-cycles, each a small step:

### V2.0.M1.C.1 — `.elmStyle` carrier-kind differentiation

- Free `(S, A) -> S` reducer functions now emit `carrierKind:.elmStyle`
  (the Elm idiom — `func update(_:_:)` at module scope).
- Everything else from signature-scan stays `.generic`: methods on a
  type, free `(inout S, A) -> Void`, free `(S, A) -> (S, Effect<A>)`.
- Tiny change — one branch in `matchReducer` keyed on
  `enclosingTypeName == nil && shape == .stateActionReturnsState`.
- The M1.B `.tca` path is unaffected; carrier-kind is decided at the
  emit site for each path independently.

### V2.0.M1.C.2 — `ReducerPin` + `--reducer` flag

- New `ReducerPin` value in Core: `(moduleName?, typeName?,
  functionName)`. Parsing splits the raw `--reducer <pin>` string
  right-to-left.
- Three error cases: `emptyPin`, `malformed(raw:)`,
  `moduleResolutionUnsupported(raw:)` — the last is reserved for M2+
  when multi-module plumbing lands.
- `DiscoverReducersCommand` gains a `--reducer` option that filters
  output to the matched candidate; zero / multiple matches throw via
  the new file-scope `DiscoverReducersError` enum (never silently
  pick one — PRD §6.5).
- The same `ReducerPin` + `matches(_:)` pair is what downstream M2+
  pipelines consume to know which reducer to feed into the
  action-sequence generator / verify harness / template scoring.

### V2.0.M1.C.3 — calibration corpus skeleton

- New `docs/calibration-corpus-v2.0.md` — a skeleton that frames what
  the v2.0 corpus *will* be: TCA examples + Elm-style OSS + hand-rolled
  reducers, partitioned by carrier kind (`.tca` / `.elmStyle` /
  `.generic`) and by interaction-template family (cardinality / ref-
  integrity / biconditional / conservation / idempotence).
- Real OSS commit pins deferred to M3+ when the verify pipeline can
  validate expected per-family suggestion counts. Pinning numbers
  before we can measure them produces a false anchor.

## Test count

**2618 → 2633 (+15)**:

- M1.C.1 (+3): new V1.C carrier-kind tests minus the obsolete
  V1.B `m1aCandidatesAreGeneric` (now `.elmStyle`, not `.generic`).
- M1.C.2 (+12): 8 `ReducerPin` parse + match tests, 4 CLI pin-flag
  tests (filter / no-match / ambiguous / module-prefixed).

§13 budgets unchanged. M1 surface stays under SwiftLint's
`file_length` + `type_body_length` caps post-M1.B's drive-by
splits.

## What M1 produced — quick reference

After M1.C, `swift-infer discover-reducers` produces a candidate list
where each `ReducerCandidate` carries:

| Field | M1.A | M1.B | M1.C |
|---|---|---|---|
| `location` | ✓ | | |
| `enclosingTypeName` | ✓ | | |
| `functionName` | ✓ | TCA closures use `"body"` | |
| `signatureShape` | 3 cases | + 4th `.inoutStateActionReturnsEffect` | |
| `stateTypeName` / `actionTypeName` | ✓ | synthesized `<Type>.State` / `<Type>.Action` | |
| `carrierKind` | (default `.generic`) | `.tca` for TCA closures | `.elmStyle` for free `(S, A) -> S` |

Pin syntax for downstream pipelines:

| Pin | Matches |
|---|---|
| `"reduce"` | All candidates with `functionName == "reduce"` |
| `"Inbox.body"` | Candidates with `enclosingTypeName == "Inbox" && functionName == "body"` (typical TCA shape) |
| `"MyModule.Inbox.body"` | (M2+) — module resolution deferred |

## What's next — M2

M2 is the first cross-repo coordination for v2.0. PRD §8.1 sketches
the kit-side surface:

```swift
public extension DerivationStrategist {
    static func actionSequence<A: Sendable>(
        from actionGen: Gen<A>,
        length: ClosedRange<Int> = 0...16,
        statefulGuards: [any StatefulGuard<A>] = []
    ) -> Gen<[A]>

    static func actionSequence<A: Sendable>(
        _ actionType: A.Type,
        length: ClosedRange<Int> = 0...16,
        statefulGuards: [any StatefulGuard<A>] = []
    ) -> Gen<[A]>?
}
```

That ships in the next SwiftPropertyLaws minor (additive — no kit
breaking change). The work is:

1. **Kit side (SwiftPropertyLaws).** Add the `actionSequence` entries
   to `DerivationStrategist` + the `StatefulGuard` protocol. Tests
   for default-length bounds, stateful-guard filtering, derivation
   chain fallback (`.caseIterable` / `.rawRepresentable` /
   `.memberwise`).
2. **Repo side (SwiftInferProperties).** Consume the new kit entries
   from inference paths that need an action-sequence generator —
   probably M3's in-process verify harness, since M2 + M3 are
   tightly coupled.

M2 is naturally bigger than M1's three sub-cycles because it spans
two repos. Scope conversation worth having before starting.

## Artifacts

- v1.75 sources:
  - `Sources/SwiftInferCore/ReducerDiscoverer.swift` (`.elmStyle`
    branch in `matchReducer`).
  - `Sources/SwiftInferCore/ReducerPin.swift` (parse + matches).
  - `Sources/SwiftInferCLI/DiscoverReducersCommand.swift` (`--reducer`
    flag + filter).
- `docs/calibration-corpus-v2.0.md` (skeleton, M1.C.3).
- Prior cycles: `docs/calibration-cycle-71-findings.md` (M1.B),
  `docs/calibration-cycle-70-findings.md` (M1.A).
- v2.0 PRD: `docs/SwiftInferProperties PRD v2.0.md`.
