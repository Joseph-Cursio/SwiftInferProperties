# v1.74 Calibration Cycle 71 — Findings (V2.0.M1.B: TCA Reducer.body conformance walk)

Captured: 2026-05-15. swift-infer at v1.74.

## Headline

**M1.A's gap is closed.** v1.73 shipped M1.A — signature-scan reducer
discovery against three canonical shapes (`(S, A) -> S`,
`(inout S, A) -> Void`, `(S, A) -> (S, Effect<A>)`). That walk misses
TCA's modern reducer entirely: `var body: some ReducerOf<Self>` isn't
a `FunctionDeclSyntax`, so signature scanning silently skips it.

v1.74 ships **V2.0.M1.B** — the TCA conformance walk. Types
conforming to `Reducer` get their `var body` walked recursively for
`Reduce { state, action in ... }` closures. Each closure emits a
`ReducerCandidate` with the new `.tca` carrier-kind label and a
synthesized 4th signature shape (`(inout S, A) -> Effect<A>`). The
walk is conservative: it only fires in files that
`import ComposableArchitecture`, matching v1's name-match strategy
for `@Discoverable` and avoiding false matches against unrelated
`Reducer` protocols.

Cycle-66's **52/103 = 50.5% measured-execution** carries forward
unchanged — v1.74 touches no v1 emitter / resolver / carrier path.

## Three decisions settled

The M1.B scoping conversation produced three open decisions, all
resolved per the recommended posture:

1. **Move `carrierKind` from M1.C to M1.B.** Originally scoped at
   M1.C, but M1.B introduces the first non-`.generic` carrier — the
   field arrives organically. M1.A candidates retroactively keep
   `.generic` via a default on the initializer, so all M1.A-shipped
   tests stay green without modification.
2. **New `inoutStateActionReturnsEffect` signature-shape case.** TCA
   `Reduce { ... }` closures synthesize as `(inout S, A) -> Effect<A>`
   — genuinely different from M1.A's three shapes (not `Void`, not a
   tuple, not pure state). Downstream pipelines (M3 verify, M4+
   scoring) will need to branch on it, so it gets its own case rather
   than being shoehorned into an existing one.
3. **Conservative posture: require `import ComposableArchitecture`.**
   Matches v1's `@Discoverable` name-match strategy; avoids
   false-matching projects with their own `Reducer` protocol named
   the same way.

## What shipped — two sub-cycles

### V2.0.M1.B.1 — data-model extensions

- `ReducerCarrierKind` enum in
  `Sources/SwiftInferCore/ReducerCandidate.swift`: `.generic` /
  `.tca` (shipped at M1.B); `.elmStyle` reserved for M1.C.
- `carrierKind` field on `ReducerCandidate` with default `.generic`
  on the initializer.
- 4th `ReducerSignatureShape` case:
  `inoutStateActionReturnsEffect` (rawValue
  `"inout-state-action-returns-effect"`).
- Custom Codable decoder so pre-V1.B records (none persisted yet,
  but the schema is forward-defended) decode as `.generic`.
- 5 new tests covering rawValue stability, defaults, TCA
  round-trip, backward-compat decode.

### V2.0.M1.B.2 — TCA conformance walk

- Extended `ReducerDiscoverer.Visitor`:
  - Tracks `importsComposableArchitecture` per file.
  - On each struct / class / enum / extension visit, checks the
    inheritance clause via `declaresReducerConformance(_:)` (static
    helper; matches `Reducer`, `Reducer<…>`, `ReducerOf<…>`).
  - For matching conformers, calls `extractTCACandidates(from:
    enclosingTypeName:)` which finds `var body` and walks its
    initializer / accessor block.
- New `Sources/SwiftInferCore/ReduceClosureWalker.swift` — a
  recursive `SyntaxVisitor` that finds `Reduce { ... }` calls
  anywhere in a body subtree, including nested under `Scope` /
  `CombineReducers` / similar wrappers. Per matching call with an
  arity-2 trailing closure, emits one `ReducerCandidate` with
  `carrierKind: .tca`, `signatureShape:
  .inoutStateActionReturnsEffect`, synthesized State / Action
  type names.
- Closure parameter names are not validated (positional shape only;
  the §4 scoring system at M4+ handles vocabulary).
- Deliberate skips (each tested):
  - No `import ComposableArchitecture` → walk doesn't fire.
  - Arity-1 trailing closures (`Reduce { $0 }`) → skipped.
  - `private` / `fileprivate` conformers → skipped (V1.57.A posture).
  - `EmptyReducer` / `BindingReducer` alone → no `Reduce` closure
    to emit; nothing surfaces.
- 13 new tests in a separate suite
  (`ReducerDiscovererTCATests.swift`) covering basic match, import
  gating, generic `Reducer<...>`, multiple closures, nested under
  `Scope`, class conformer, extension conformer, arity-1 rejection,
  private skip, parameter-name agnosticism, non-Reducer types
  ignored.

### Drive-by file splits

The V1.B additions pushed both `ReducerDiscoverer.swift` (438 lines)
and `ReducerDiscovererTests.swift` (445 lines) past SwiftLint's
`file_length` / `type_body_length` caps. Extracted:

- `ReduceClosureWalker` → `Sources/SwiftInferCore/ReduceClosureWalker.swift`.
- TCA tests → `Tests/SwiftInferCoreTests/ReducerDiscovererTCATests.swift`.

Both sides back under the caps. Lint clean.

## Test count

**2600 → 2618 (+18)**:

- M1.B.1 (+5) — carrierKind default, rawValue stability, 4th-shape
  rawValue, TCA round-trip, backward-compat decode.
- M1.B.2 (+13) — TCA basic match, import gating, generic conformer,
  multiple closures, nested Scope, EmptyReducer/BindingReducer,
  class conformer, extension conformer, arity-1 rejection, private
  skip, parameter-name agnosticism, non-Reducer ignored, plus
  the M1.A `carrierKind == .generic` regression test kept in the
  main suite.

§13 performance budgets unchanged — discovery stays pure SwiftSyntax;
the M1.B walk runs once per Reducer-conforming type, bounded by
the candidate count.

## What's next (M1.C)

M1.C is the last M1 sub-cycle. Three deliverables:

1. **Carrier-kind refinement.** Distinguish `.elmStyle` (free
   `(S, A) -> S` reducers — the Elm idiom) from `.generic`
   (signature-matching method on a non-`Reducer` type). The
   `ReducerCarrierKind.elmStyle` case is already reserved; the
   signature-scan path needs the heuristic that distinguishes them
   (probably: free function at module scope → `.elmStyle`; method on
   a type that doesn't conform to TCA's `Reducer` → `.generic`).
2. **`--reducer <module>.<typeName>.<funcName>` pinning flag.**
   Downstream M2+ pipelines need to disambiguate when ≥ 2
   candidates exist in the same target. Default behavior stays
   "list candidates and exit" — never silently pick one (PRD §6.5).
3. **Calibration corpus pin.** `docs/calibration-corpus-v2.0.md`
   listing the reference reducers (TCA examples directory + Elm
   exemplars + hand-rolled corpus per PRD §18). v2.0's analog of
   v1's cycle-1 1167-baseline starts here.

After M1.C, M1 is done and the v2.0 arc moves to M2 (kit-side
`actionSequence` derivation in SwiftPropertyLaws — first cross-repo
coordination for v2.0).

## Artifacts

- v1.74 sources:
  - `Sources/SwiftInferCore/ReducerCandidate.swift` (data-model
    extensions).
  - `Sources/SwiftInferCore/ReducerDiscoverer.swift` (visitor extensions
    for TCA conformance walk).
  - `Sources/SwiftInferCore/ReduceClosureWalker.swift` (closure walker).
- Prior cycle: `docs/calibration-cycle-70-findings.md` (v1.73 M1.A —
  first non-v1 cycle).
- v2.0 PRD: `docs/SwiftInferProperties PRD v2.0.md`.
