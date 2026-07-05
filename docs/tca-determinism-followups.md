# TCA determinism measured-verify — open follow-ups

## Status

Stage 3 (dependency-pinned determinism measured-verify for TCA reducers)
shipped and verified green under Swift 6.3.3 — the three-way
`tca-determinism-corpus` (pure / proper-dependency / snuck-raw). This note
registers the four follow-ups deferred at that point. **Items 3 and 4 are built.
Item 2 is now 4/5 slices built** — slices 1 (PresentationAction), 2 (Result),
3b (IdentifiedActionOf), and 4 (BindingAction) shipped 2026-07-04; only slice 3c
(child recursion — deferred, 0 added reach) remains. **Item 1 is now fully built
— discovery + pin disambiguation *and* multi-module measured verify (M3, 2026-07-05).**
All four registered follow-ups are complete but for the deliberately-deferred
slice 3c. See `tca-determinism-verify-scope.md` for the shipped design.

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
- **Shipped (multi-module measured *verify* — M3, 2026-07-05):** the survey
  (`verify-interaction --all`) now takes a **repeatable `--target`** and verifies
  each reducer against **its own** module's library product in one run. The key
  insight: the module *is* the verify target (both the `Sources/<module>/`
  discovery dir and the product name), so no pipeline-internal rewiring was
  needed — `InteractionInvariantSuggestion` gained a `moduleName` (stamped from
  `ReducerCandidate.moduleName` at emission in `InteractionTemplateFamily`), the
  survey discovers via `collectSuggestions(targets:)` and passes each identity's
  `moduleName` as the per-verify target, and `makeWorkdirInputs`'s existing
  `PackageProductResolver.libraryProduct(exposingModule:)` call already resolves
  the right product from it. `CorpusPackager.packageMultiModule` packages N
  modules into one SwiftPM package (one library product each). Proof:
  `Tests/Fixtures/multi-module-verify-corpus/` (`AlphaCounter` + `BetaCounter`,
  distinct names + a module-local helper each so a wrong-product build would
  fail) → `MultiModuleVerifyMeasuredTests` (survey over `[Alpha, Beta]` → 2
  determinism identities → 2 `measured-bothPass`, each built against its own
  product; ~34s, dependency-free) + fast `MultiModuleVerifyTests` (module
  tagging, no build). **Known limitation:** two *identically-named* reducers in
  different modules share an identity hash (the hash omits module, to keep the
  existing single-module evidence-join keys stable), so a measured survey must
  use distinct type names across modules; the fixture does. The single-reducer
  (non-`--all`) path verifies within the first `--target` (a module-prefixed
  `--reducer` still disambiguates).

## 2. Structured associated-value action payloads (composition-actions)

> **▶ All four composition-action slices are built.** Slices 1 (PresentationAction),
> 2 (Result), **3b** (`IdentifiedActionOf<Child>` — canned id + payload-free child,
> no recursion), and **4** (`BindingAction<State>` — `.set(\.field, value)` over
> `@ObservableState` fields) are shipped. Remaining open: slice **3c**
> (depth-bounded child recursion — deferred, 0 added reach on the corpus) and
> widening any slice's value-type / field coverage. See the slice list below.

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
- **Slice 4 — `BindingAction<State>` — ✅ BUILT (2026-07-04):** emit
  `.binding(.set(\.field, <canned value>))` for each `@ObservableState` stored
  `var` of a defaultable type — **a real transition through `BindingReducer`**,
  not a no-op (higher value than 3b). **Recount over the real Examples tree: 15
  `case binding(BindingAction<State>)` cases, 9 files `@ObservableState`** (the
  modern `.set(\.field, value)` keypath; 2 legacy `@BindingState` files gate —
  they use `\.$field`), value types **String / Bool / Int / Double dominate**
  (all defaultable). Discovery captures the `@ObservableState` State's bindable
  stored `var` fields (`ReducerCandidate.stateFields`, via
  `ReducerDiscoverer+TCAWalk.stateStoredVarFields` — annotation + literal-type
  inference; `let` / `static` / computed / attributed fields excluded); a
  same-candidate resolution pass `BindingActionResolver.resolve` (in
  `resolveAndEmit`, no cross-candidate lookup — `BindingAction` binds the
  reducer's own State) enriches the `binding` case with the defaultable fields
  (`ActionCaseInfo.resolvedBinding`). The emitter binds each field
  (`Gen.oneOf` over them; `defaultValueLiteral` — `Bool`→`false`, `Int`→`0`,
  `String`→`""`, `Double`→`0.0`, `UUID`→canned). **Gates (stay excluded +
  disclosed):** no defaultable field (custom-type-only State — e.g. `SyncUpForm`),
  non-`@ObservableState` State (legacy), no binding case. **Discovery caveat
  (pre-existing, not slice-4-specific):** a pure-`BindingReducer()` body with no
  `Reduce { }` closure surfaces no candidate, so slice 4 reaches binding reducers
  that also have a `Reduce` closure (most real ones do — onChange/side effects).
  Corpus: `tca-binding-action-corpus` (`Settings` — String/Bool/Double/Int
  fields); fast proof `BindingActionCorpusTests` (discover→resolve→emit, no
  build) + measured `BindingActionCorpusMeasuredTests` (1 identity → bothPass,
  `Verified`, no `excluded: binding`). Units: `BindingActionResolverTests`,
  extended `ActionSequenceCompositionPayloadTests` +
  `ReducerDiscovererStateIDTests`.

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

(3) and (4) are **done**. (2)'s composition-action epic is **done** for the four
high-reach slices — the value-type slice was correctly bypassed (low reach,
~2/99 per cycle 123) in favour of composition-action construction
(`PresentationAction`, `Result`, `IdentifiedActionOf`, `BindingAction`), all
shipped; only slice 3c (child recursion — 0 added reach) is deferred. (1) is **done** —
discovery + pin disambiguation *and* measured-verify M3 (multi-module survey,
per-module product resolution). Everything registered here is now complete
except the deliberately-deferred slice 3c (0 reach). Remaining TCA-track items
are all off this list: blocked upstream (Workflow's uncallable `ApplyContext`;
the Mobius release pin) or optional volume (corpus / value-type widening).
