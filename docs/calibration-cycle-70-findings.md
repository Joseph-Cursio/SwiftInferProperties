# v1.73 Calibration Cycle 70 — Findings (V2.0.M1.A: reducer discovery surface)

Captured: 2026-05-15. swift-infer at v1.73 — **first non-v1 cycle.**

## Headline

**v2.0 work begins.** The PRD §17.2 metric arc closed at v1.72 (5/5);
cycle 69's "what's next" report identified v2.0 — interaction-invariant
inference for SwiftUI state systems — as the queued direction over the
three carried-forward v1 candidates (all of which lacked a triggering
signal). v1.73 pivots and ships **V2.0.M1.A** — the foundation
milestone the entire v2.0 arc depends on: a SwiftSyntax pass that
detects reducer-shaped functions and surfaces them via a new
`swift-infer discover-reducers` subcommand.

Cycle-66's **52/103 = 50.5% measured-execution** carries forward
unchanged — v1.73 touches no v1 emitter / resolver / carrier path.
v2.0's own measured-execution metric (PRD §19 Phase 2 target: ≥30% on
the calibration corpus) is not yet measurable — M3's verify path
ships at a later milestone.

## Why this cycle and not another v1.7x

Cycle 69 surfaced three v1 carryforward candidates:

1. **(A) CI-hook variant of accept-check** — gated on the v1.72
   manual gesture producing useful signal first, and no usage to
   measure yet. Premature.
2. **Kit-side `Ring` / `CommutativeGroup` / `Group acting on T`** —
   lives in SwiftPropertyLaws, not this codebase.
3. **Incremental index analysis** — PRD §20.1 optimization, deferred
   until profiling says it's needed. No profiling signal.

None had a triggering signal. The recent commit history
(`04a4d25 docs: draft v2.0 PRD`, `1b75228 docs: address v2.0 PRD
review punch list`) had the v2.0 PRD queued. The honest move was
to pivot, not pick a reactive v1 cycle.

## Three decisions settled on the pivot

The v2.0 M1.A scoping conversation produced three open decisions
the PRD didn't pin. All three resolved before code landed:

1. **Separate subcommand `discover-reducers` vs `discover --reducers`
   flag.** PRD §3.6 step 1 says `discover --reducers`; §5.8 M1 says
   `swift-infer discover-reducers`. The two contradicted. Picked
   separate subcommand because `discover.run` is rooted around
   algebraic-suggestion emission and a `--reducers` mode would force
   a structurally-different output deep in that pipeline. Folding
   into `discover` later is non-breaking — the hyphenated form can
   stay as an alias.
2. **Strict Action surface (§21 question #2).** PRD §2.3 already
   documents strict (require first-class Action enum;
   `@Observable`-method-dispatch out of scope). §21 #2 reopened it.
   Resolved as "strict, as written" — the arity-2 signature check
   implements §2.3 for free (single-parameter `dispatch(_:)` doesn't
   match canonical shape, so it's rejected without special-casing).
3. **Version bump.** Continued the existing cadence (each cycle
   minor-bumps; 1.72.0 → 1.73.0). v2.0.0 stays reserved for the
   eventual full v2.0 ship (probably ≈ M9 InteractionInvariantBridge).
   This is purely additive — new subcommand, no behavior change to
   existing commands.

## What shipped — three sub-cycles

### V2.0.M1.A.1 — `ReducerCandidate` value + signature-shape enum

- `Sources/SwiftInferCore/ReducerCandidate.swift` — value type with
  `location`, `enclosingTypeName?`, `functionName`, `signatureShape`,
  `stateTypeName`, `actionTypeName`. Codable + Equatable. Stable
  rawValues on `ReducerSignatureShape` (`state-action-returns-state`
  / `inout-state-action-returns-void` /
  `state-action-returns-state-and-effect`) so downstream consumers
  can key on them.
- Signature-only by design: no `carrierKind` field yet (M1.C), no
  Equatable/Sendable/Hashable signals (M4+ scoring), no pinning
  (M1.C).
- 5 tests covering `qualifiedName`, rawValue stability, Codable
  round-trip with and without `enclosingTypeName`.

### V2.0.M1.A.2 — `ReducerDiscoverer` SwiftSyntax pass

- `Sources/SwiftInferCore/ReducerDiscoverer.swift` — mirrors v1's
  `FunctionScanner` architecture: public namespace with
  `discover(source:file:)` / `discover(file:)` /
  `discover(directory:)` entries + a private `SyntaxVisitor`.
  Sorted-path walk for byte-stable output.
- Matches three canonical shapes (PRD §6.2). `Effect<…>` recognition
  is name-prefix-only — no type resolution. Cross-import correctness
  is calibration's problem (and why §3.5's default-`Possible`
  visibility on every new template family exists).
- Tuple-return shape `(S, Effect<A>)` uses **depth-counting comma
  split** so `Effect<Output, Failure>` (Combine-era) parses without
  choking on the inner comma.
- Deliberate skips (each tested):
  - `private` / `fileprivate` (V1.57.A cycle-53 posture).
  - Generic functions (`func reduce<S, A>(...)`).
  - Single-parameter `dispatch(_:)` (naturally rejected by the
    arity-2 check; cleanly implements §2.3).
  - `inout` on the Action parameter; `(inout S, A) -> S`; tuple
    returns where the second element isn't `Effect<...>`.
- 17 tests across the three shapes × edge cases.

### V2.0.M1.A.3 — `discover-reducers` CLI subcommand

- `Sources/SwiftInferCLI/DiscoverReducersCommand.swift` —
  `SwiftInferCommand.DiscoverReducers` registered in the subcommands
  list alongside `Verify` / `Metrics` / `AcceptCheck`.
- Output: one line per candidate (`<location>  <qualifiedName>
  signature:<shape>  state:<S>  action:<A>`), sorted by `(location,
  functionName)`, plus a header / tail summary with singular vs
  plural handling.
- 6 tests covering the renderer (empty / single / plural / sort
  stability / per-record fields) and an end-to-end `runPipeline`
  against a temp-directory fixture.

## Test count

**2572 → 2600 (+28)**:

- V2.0.M1.A.1 (+5) — `ReducerCandidateTests`.
- V2.0.M1.A.2 (+17) — `ReducerDiscovererTests`.
- V2.0.M1.A.3 (+6) — `DiscoverReducersCommandTests`.

§13 performance budgets unchanged — discovery is pure SwiftSyntax and
the M1.A surface ships with no per-target perf regression test yet
(deferred to M1.C when a calibration corpus is pinned and the §15 /
§6.6 budgets become measurable against real targets, not synthetic
fixtures).

## What's next (M1.B / M1.C / corpus pin)

M1.A's reducer list misses TCA's modern `var body: some ReducerOf<Self>`
shape entirely — that's the next sub-cycle's job. The remaining M1
sub-tasks per the cycle-69 conversation:

1. **M1.B — TCA conformance walk.** Recognize types conforming to
   `Reducer` by name match (no runtime dep). Walk `body` declarations
   and extract embedded `Reduce { state, action in ... }` closures
   per PRD §6.3. Each closure surfaces as a `ReducerCandidate` with
   synthesized signature shape — and once added, the `.tca`
   carrier-kind value becomes real.
2. **M1.C — Carrier-kind labeling + `--reducer` pinning.** Distinguish
   `.tca` / `.elmStyle` / `.generic`. Add the `--reducer
   <module>.<typeName>.<funcName>` flag that downstream M2+
   pipelines need to disambiguate when ≥ 2 candidates exist.
   Calibration corpus pinning (`docs/calibration-corpus-v2.0.md`)
   ships alongside — by M1.C we'll have seen what real-world
   discovery produces.

Beyond M1, the §5.8 milestone arc continues: M2 ActionSequenceGenerator
(needs SwiftPropertyLaws next-minor coordination), M3 in-process
verify path, M4 lifted families (Conservation + Idempotence on
reducer carriers, first calibration cycle).

## Artifacts

- v1.73 sources:
  - `Sources/SwiftInferCore/ReducerCandidate.swift`
  - `Sources/SwiftInferCore/ReducerDiscoverer.swift`
  - `Sources/SwiftInferCLI/DiscoverReducersCommand.swift`
- Prior cycle: `docs/calibration-cycle-69-findings.md` (v1.72 —
  post-acceptance failure rate, §17.2 complete at 5/5).
- v2.0 PRD: `docs/SwiftInferProperties PRD v2.0.md`.
