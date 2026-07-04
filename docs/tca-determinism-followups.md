# TCA determinism measured-verify — open follow-ups

## Status

Stage 3 (dependency-pinned determinism measured-verify for TCA reducers)
shipped and verified green under Swift 6.3.3 — the three-way
`tca-determinism-corpus` (pure / proper-dependency / snuck-raw). This note
registers the four follow-ups deferred at that point. **Items 3 and 4 are built;
item 1's discovery + pin disambiguation is built (its measured-verify M3
remains); item 2 remains.** See `tca-determinism-verify-scope.md` for the shipped
design.

## 1. Multi-module reducer pins / cross-module disambiguation

- **Shipped (discovery + pin disambiguation):** `discover-interaction` now
  accepts `--target` more than once. `ReducerCandidate` carries a `moduleName`
  (`ReducerCandidate.swift`); `collectSuggestions(targets:)`
  (`DiscoverInteractionCommand+MultiModule.swift`) scans each target's
  `Sources/<target>/`, tags candidates by module (only in multi-target runs, so
  a single-target run stays backward-compatible), applies the `--reducer` pin
  across the aggregate, dedupes module-aware, and runs the engine per module.
  `ReducerPin.matches` compares module when both the pin and candidate carry
  one, so `Bar.Counter.reduce` selects Bar's `Counter` over Alpha's. Fixture:
  `multi-module-discovery-corpus` (identical `CounterReducer` in `Alpha` +
  `Beta`); tests in `MultiModuleDiscoveryTests`.
- **Still open (multi-module measured *verify* — M3):** the measured
  verify-workdir builds one user package/product. Measuring reducers from
  different modules in one run needs per-module product resolution threaded
  through `VerifierWorkdir` (`PackageProductResolver.libraryProduct` is already
  module-aware). Discovery + disambiguation — the stated cross-module problem —
  is done; measured verify of a *pinned* cross-module reducer waits on M3.

## 2. Structured associated-value action payloads (composition-actions)

> **▶ Next: Slice 4 — `BindingAction<State>`.** Slices 1 (PresentationAction),
> 2 (Result), and **3b** (`IdentifiedActionOf<Child>` — canned-UUID / Int / String
> id + a payload-free child, no recursion) are built. Slice 4 needs State
> introspection (keypath into State + value); the `State.ID` capture landed in 3b
> (`ReducerCandidate.stateIDTypeName`, discovered in
> `ReducerDiscoverer+TCAWalk.stateIDType`) is the same introspection seam and can
> be generalized for it. See the slice list below.

**Key finding (from the repo's own cycle 123):** value-type payload synthesis
(custom structs/tuples/nested enums via `TypeShapeBuilder`) unlocks only ~2/99
real Action enums — non-raw payloads in real reducers are overwhelmingly
**composition wrappers**. The 81/99 blockers are `nested-X.Action` (72),
`PresentationAction` (25), `Result`/`TaskResult` (14), `BindingAction` (10). So
the valuable work is **constructing composition actions**, not deriving
`Gen<T>`. Each slice widens the already-ratified Phase B relaxed-exploration
subset (`ActionSequenceStubEmitter.compositionGenerator`) — the excluded set is
still disclosed, so no new precision decision.

- **Slice 1 — `PresentationAction<T>` — ✅ BUILT (2026-07-04):** emit the
  payload-free `.dismiss` case, so `case alert(PresentationAction<Alert>)`
  explores `Action.alert(.dismiss)` with no `Gen<Alert>` needed.
  `+PayloadConstructibility.swift`; units in
  `ActionSequenceCompositionPayloadTests`; validated end-to-end by the Tier-2
  `AlertAndConfirmationDialog` reducer (its presentation cases are now explored,
  corpus stays green).
- **Slice 2 — `Result<_, any Error>` — ✅ BUILT (2026-07-04):** emit
  `.case(.failure(CancellationError()))` — a canned type-erased error, no
  `Gen<T>` needed. Gated to the type-erased error forms (`, any Error>` /
  `, Error>`); concrete-error `Result`s stay excluded. Corpus:
  `tca-composition-payload-corpus` (`NumberFact`); measured by
  `CompositionPayloadCorpusMeasuredTests` (bothPass). ~14 cases.
- **Slice 3b — `IdentifiedActionOf<Child>` — ✅ BUILT (2026-07-04):** emit
  `.case(.element(id: <canned id>, action: .<childFreeCase>))` — a canonical
  identified-array element, no `Gen` over the child needed. **Design +
  recount in `tca-identified-action-slice3-design.md`.** The recount over
  Point-Free's real Examples tree (8 `IdentifiedActionOf<Child>` cases) killed
  the design's original "land 3a" plan: **id distribution UUID 6/8, URL 1, none
  1, Int/String 0/8** — 3a (Int/String only) had zero reach, so **3b (canned
  UUID)** is the minimal honest increment. Two net-new capabilities landed:
  (i) discovery captures each reducer's `State.ID`
  (`ReducerCandidate.stateIDTypeName`, via `ReducerDiscoverer+TCAWalk.stateIDType`);
  (ii) a resolution pass `IdentifiedActionResolver.resolve` (run once in
  `VerifyInteractionPipeline.resolveAndEmit`, before Inputs) enriches a parent's
  `IdentifiedActionOf<Child>` cases with resolved facts (`ActionCaseInfo`'s new
  `resolvedElement`) against the discovered child — so the emitter needs **no
  threaded child map** and emit + evidence coverage stay consistent (both read
  the enriched candidate). `compositionGenerator` formats the id literal
  (`UUID` → all-zero canned literal; `Int`→`0`; `String`→`""`). **Gates
  (stay excluded + disclosed):** non-defaultable id (URL / custom), no
  payload-free child case (Todo — child is pure `BindingAction`), unresolvable /
  undiscovered child, spelled-out `IdentifiedAction<_, _>` (recount: 0 real).
  **Depth 0 — no recursion** (3c below), so a self-recursive
  `IdentifiedActionOf<Self>` terminates by picking a payload-free child case.
  **ROI is disclosure-set reduction, not new signal:** the constructed
  `.element` no-ops against the empty initial-State `IdentifiedArray`. Corpus:
  `tca-identified-action-corpus` (`RowList` `.forEach` parent + UUID-id `Row`);
  fast proof `IdentifiedActionCorpusTests` (discover→resolve→emit, no build) +
  measured `IdentifiedActionCorpusMeasuredTests` (2 identities → 2 bothPass,
  parent `Verified` with no `excluded: rows`). Units:
  `IdentifiedActionResolverTests`, extended `ActionSequenceCompositionPayloadTests`,
  `ReducerDiscovererStateIDTests`.
- **Slice 3c — depth-bounded child recursion (open, deferred):** reuse
  `compositionGenerator` on the child action to pick a *non*-payload-free child
  (raw / `PresentationAction` / `Result` / nested `IdentifiedActionOf`) with a
  depth bound. **Recount: 0 added reach** on the real corpus (every reachable
  UUID case already has a payload-free child), and it introduces the
  self-recursive-`Nested` termination hazard — so deferred until a corpus
  justifies it. See the design doc.
- **Slice 4 — `BindingAction<State>` (open):** keypath into State + value. ~10
  cases, high complexity (needs State introspection — the `State.ID` capture
  from 3b is the same seam to generalize).

## 3. `unknownActionIsNoOp` measured-verify — ✅ BUILT (2026-07-03)

- **Shipped:** `reduce(s, unknown) == s` for open-alphabet redux reducers is now
  a measured `InteractionInvariantFamily`. `UnknownActionIsNoOpInteractionTemplate`
  surfaces one suggestion per open-alphabet redux reducer (`actionCases` empty),
  the stub emitter mints a file-scope probe (`__UnknownActionProbe: <ActionType>`)
  conforming to the reducer's open Action protocol, drives an empty action
  sequence (open alphabets have no `CaseIterable` action set to generate from),
  and asserts the reducer leaves State unchanged post-loop.
  `UnknownActionCorpusMeasuredTests` proves the split on a plain-Swift corpus
  (no CA): `NoOpCounter` → bothPass → Verified; `LeakyReducer` (mutates State on
  the default branch) → defaultFails → suppressed (~37s, no toolchain gate).
- **Correction to the earlier "cheapest" framing:** this was *not* just a stub
  arm. `unknownActionIsNoOp` existed only as a `PropertyKind` (via
  `ReducerInteractionAnalyzer`), whose sole consumer was the discovery *render*
  path — the measured pipeline is keyed on `InteractionInvariantFamily`, which
  had no such case. So it needed a 7th family case, a template (the measured
  producer the analyzer's prototype lacked), a new probe-synthesis emitter path
  (open alphabets aren't `CaseIterable`, so the normal generator can't drive
  them), a corpus, and tests — comparable to a determinism stage.

## 4. Tier-2 curated-compilable real-TCA measured corpus — ✅ BUILT (2026-07-03)

- **Shipped:** `Tests/Fixtures/tca-examples-measured-corpus/` — the **maximal
  six** real Point-Free reducers that co-compile against CA alone, curated from
  the `Examples/` tree (SwiftUI View / `#Preview` scaffolding stripped, `@Reducer`
  verbatim): `Counter` (pure), `OptionalBasics` (pure, composes `Counter` via
  `.ifLet`), `BindingBasics` (pure), `AlertAndConfirmationDialog` (pure; CA
  `@Presents` / `AlertState` built-ins), `Timers` (pinned `\.continuousClock`),
  `Nested` (recursive `.forEach` over `Self()`, pinned `\.uuid`).
  `TCAExamplesMeasuredTests` packages them via `CorpusPackager`, runs a real
  `swift build` against ComposableArchitecture in the verify-workdir, and measures
  determinism: 6 identities → 6 measured-bothPass → all Verified (~71s under
  6.3.3). `.subprocess`-tagged, 6.3.3-gated.
- **Curation rule (faithful, maximal-compilable):** only reducers that co-compile
  against CA alone are included. Excluded, because one non-compiling file poisons
  the shared module: custom `DependencyKey` types (`\.factClient` in
  `Effects-Basics` / `NavigationStack`, `\.weatherClient` in `SearchView`,
  `\.screenshots` in `Effects-LongLiving`), `@Shared` (`SharedState-InMemory`),
  an external sub-reducer (`Todos` → `Todo`), and a generic reducer with a
  required stored closure (`Favoriting<ID>` — the verifier can't construct it).
- The discovery-only `tca-examples-corpus` (13 vendored files) stays as-is; this
  is the separate curated compilable subset its ATTRIBUTION.md always pointed to.
- Answers `tca-determinism-verify-scope.md` "Open questions for sign-off" #3 in
  the affirmative: the pipeline works on real idiomatic TCA, not just synthetic
  fixtures.

## Sequencing

(3) and (4) are **done**. (1)'s discovery + pin disambiguation is **done**; its
measured-verify M3 (per-module product resolution in the verify-workdir) remains.
(2) remains — the value-type slice is low reach (~2/99 per cycle 123); the
high-reach version is composition-action construction (nested child actions,
`PresentationAction`, `Result`, `BindingAction`), the epic the team shelved.
