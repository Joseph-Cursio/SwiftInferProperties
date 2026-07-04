# Design: composition-action slice 3 — `IdentifiedActionOf<Child>`

> **Status: 3b SHIPPED (2026-07-04).** The recount (below) killed 3a (0 real
> reach — all real ids are UUID) and landed **3b** (canned-UUID / Int / String
> id + payload-free child, no recursion) instead. **3c (recursion) deferred**
> (0 added reach on the corpus + the self-recursion hazard). See the
> "Recount results" + "Recommendation (revised)" sections and the
> `## 2 · Slice 3b` entry in `docs/tca-determinism-followups.md`.

Design note for follow-up item 2, slice 3 (`docs/tca-determinism-followups.md`).
Slices 1 (`PresentationAction`) and 2 (`Result<_, any Error>`) are built; this
note works out slice 3 before any code, because it is categorically harder than
1–2 and forces two net-new capabilities plus a genuine precision decision. No
implementation is proposed as landed here — this is a scoping + sequencing
record, in the spirit of `tca-determinism-verify-scope.md` and the cycle-123/124
Phase-B decision records.

## Why slice 3 is not "one more branch"

Slices 1 and 2 worked because the wrapped payload had a **universal canned
construction that needs nothing from the wrapped type**:

- `PresentationAction<T>` → `.dismiss` — a payload-free case that always exists,
  independent of `T`.
- `Result<_, any Error>` → `.failure(CancellationError())` — a canned
  type-erased error, independent of `Success`.

Both are one-liners in `compositionGenerator(for:action:)`
(`ActionSequenceStubEmitter+PayloadConstructibility.swift`) because the emitter
only ever needs the payload's **type-name string** and a fixed literal.

`IdentifiedActionOf<Child>` has no such escape hatch. It is a typealias:

```swift
public typealias IdentifiedActionOf<R: Reducer> = IdentifiedAction<R.State.ID, R.Action>

public enum IdentifiedAction<ID: Hashable & Sendable, Action> {
    case element(id: ID, action: Action)
}
```

The **only** case is `.element(id:action:)`. To construct one, the emitter must
synthesize *two* values that both depend entirely on `Child`:

1. an **ID value** of type `Child.State.ID`, and
2. a valid **child action** of type `Child.Action` — which is itself a
   composition target (the recursion the follow-ups doc flags).

Neither is expressible in the current one-line pattern.

## The two net-new capabilities (neither exists today)

### A. Threading child candidates into the emitter

The emitter's input is a single `ReducerCandidate`
(`ActionSequenceStubEmitter.Inputs.candidate`), and an `ActionCaseInfo` carries
only `{ name: String, payloadTypes: [String] }`. For an
`IdentifiedActionOf<Child>` payload, the emitter sees the *string*
`"IdentifiedActionOf<Child>"` and nothing about `Child`.

`VerifyInteractionPipeline.resolveAndEmit` (`VerifyInteractionPipeline.swift:45`)
resolves a single `matched` candidate and builds `Inputs` from it. The full
`[ReducerCandidate]` set (`deduped`) is right there at the call site but is
**not** threaded through. To recurse into `Child.Action`, the emitter needs
access to `Child`'s discovered candidate (its `actionCases`). So slice 3 is the
first slice that must widen `Inputs` (or a companion lookup) beyond the single
candidate.

Precedent: cycle 132 already recorded that a nested `child(Child.Action)` case is
"Phase B non-derivable → excluded." Slice 3 is the identified-array variant of
exactly that exclusion, so lifting it is a deliberate widening of the disclosed
excluded set, consistent with the ratified relaxed-partial-exploration posture
(cycle 124) — no new *precision* principle, but real new *plumbing*.

### B. Synthesizing an ID value (`Child.State.ID`)

There is no universal canned `ID` literal the way `.dismiss` / `CancellationError()`
were universal. Two sub-problems:

1. **The ID type is not captured.** `ReducerCandidate` has `stateTypeName` but no
   `State.ID`. Discovery would need to record the child's ID type — from an
   `Identifiable` `var id: X`, an explicit `typealias ID = X`, or the
   `IdentifiedArrayOf<Child>` element's `id` keypath. This is the **same State
   introspection slice 4 (`BindingAction<State>`) needs**, so building it here
   pays for both.

2. **Only some ID types are cheaply defaultable.** `RawType` (PropertyLawCore)
   recognizes `Int/String/Bool/Double/Float` + sized integers — so an `Int` id
   defaults to `0`, a `String` id to `""`. It does **not** recognize `UUID`,
   which is the single most common TCA `IdentifiedArray` id type. `UUID` is still
   constructible with a **canned deterministic literal**
   (`UUID(uuidString: "00000000-0000-0000-0000-000000000000")!`), analogous to
   slice 2's canned error — but that is a hand-added special case, not something
   `RawType` gives us. Tagged / custom `ID` types (`Tagged<Child, UUID>`, a
   struct id) remain non-defaultable and stay excluded.

## The semantic subtlety that reframes the ROI

Even once `.element(id:action:)` is constructed, **it no-ops against the
zero-value initial State.** `.forEach` (and `IdentifiedArray` reducer
composition) looks the element up by `id`; against the emitter's default/empty
initial State there is *no* element with our canned id, so TCA runs no child
reducer and returns `.none`. The transition is deterministic and green — but it
exercises **nothing in the child**. It adds action-space *breadth* (the case is
no longer "excluded") without behavioral *signal*.

Extracting real signal would require **seeding State** with an element whose id
matches the canned id — a materially bigger change (constructing a `Child.State`
value and inserting it into the parent's `IdentifiedArray`), which is squarely
the value-type–synthesis work cycle 123 measured at low reach (~2/99). So:

> Slice 3's honest near-term value is *disclosure-set reduction* (fewer
> `excluded:` cases in the partial-exploration annotation), not new
> counterexample-finding power for determinism.

This should be stated plainly in the slice's verdict annotation, exactly as
cycles 124–125 required the excluded set to be disclosed.

## Reach reality-check

Cycle 123 counted `nested-X.Action = 72` as the biggest blocker, but that bucket
is **all** nested-action wrappers — plain `Child.Action` via `Scope`,
`PresentationAction` (already slice 1), and `IdentifiedActionOf` via `.forEach`.
`IdentifiedActionOf` alone is some fraction of 72. Before committing to the full
build, a one-off recount over the road-test corpus (how many cases are
specifically `IdentifiedActionOf<_>` / spelled-out `IdentifiedAction<_, _>`,
and of those how many have an `Int`/`String`/`UUID` id vs. a custom id) would
size the actual payoff. **Recommended pre-work: measure before building.**

## Proposed sub-slice breakdown

Land incrementally; each sub-slice is independently green and testable.

- **3a — plumbing + recognizer, `Int`/`String` id only, no recursion.** Thread
  the child `[ReducerCandidate]` (or a `name → candidate` map) into `Inputs`.
  Recognize `IdentifiedActionOf<Child>` / `IdentifiedAction<ID, Action>`, resolve
  `Child`'s candidate, require (i) a defaultable `RawType` id and (ii) a
  **payload-free** child case (depth-0, no recursion yet), and emit
  `Gen.always(.rows(.element(id: 0, action: .someFreeCase)))`. Everything else
  stays excluded + disclosed. New unit tests; extend the composition corpus with
  an `Int`-id `.forEach` parent + trivial child; one measured `bothPass`.

- **3b — canned `UUID` id.** Add the zero-UUID literal path so `UUID`-id
  identified arrays (the common case) are recognized. Unit + corpus row.

- **3c — depth-bounded recursion for the child action.** Reuse
  `constructibleCases` / `compositionGenerator` on `Child.Action` to pick a
  constructible non-payload-free child action (raw, `PresentationAction`,
  `Result`, or a *nested* `IdentifiedActionOf`). **Depth bound is mandatory** —
  the corpus already contains a self-recursive `Nested` reducer (`.forEach` over
  `Self()`); an `IdentifiedActionOf<Self>` would recurse forever without a bound.
  Propose depth ≤ 2, then fall back to "child excluded." Unit tests for the
  bound (self-recursive child terminates) + a two-level corpus row.

Splitting this way keeps the risky recursion (3c) off the critical path: 3a+3b
already retire the disclosure-set-reduction goal for the common id shapes.

## Test / corpus plan (per sub-slice)

Mirror slices 1–2:

- **Unit** — extend `ActionSequenceCompositionPayloadTests`: recognizer returns
  the right generator for `Int`/`String`/`UUID` ids; returns `nil` for a custom
  id or an unresolvable child; recursion terminates at the depth bound.
- **Corpus** — extend `Tests/Fixtures/tca-composition-payload-corpus/` with a
  self-contained `.forEach` parent + child (no custom `DependencyKey`, so it
  co-compiles against CA alone, per the curation rule in follow-up item 4).
- **Measured** — extend `CompositionPayloadCorpusMeasuredTests` with a
  `measured-bothPass` proving the emitted `.element(id:action:)` compiles against
  CA and drives a deterministic (no-op) transition. `.subprocess`-tagged,
  6.3.3-gated, ~68–71s like the existing rows.

## Open questions for sign-off

1. **Is disclosure-set reduction alone worth the plumbing?** Given the no-op
   semantics, 3a–3b buy "fewer excluded cases," not new bug-finding. Acceptable,
   or hold until State seeding makes the transitions load-bearing?
2. **Recount first?** Run the `IdentifiedActionOf`-specific reach measurement
   before building, so the sub-slice effort is sized against real payoff.
3. **UUID canned literal** — is a fixed zero-UUID acceptable as a "canned
   constructible" in the same spirit as `CancellationError()`, or does it read as
   too magic?
4. **State/ID introspection ownership** — build it here (slice 3 pays) or as a
   shared prerequisite landed with slice 4 (`BindingAction<State>`), which also
   needs State introspection?

## Recount results (Q2) — done, and it revises the recommendation

The `tca-10`/`tca-25` road-test corpora are not checked into this repo, so the
recount was run over the faithful at-scale real-TCA source: Point-Free's own
**Examples + CaseStudies tree** (the local `swift-composable-architecture`
checkout), cross-checked against the in-repo faithful copies in
`Tests/Fixtures/tca-examples-corpus/`.

**8 `IdentifiedActionOf<Child>` cases** in the real Examples tree; **zero**
spelled-out `IdentifiedAction<_, _>`:

| # | Case | Child | `State.ID` | Defaultable? | Payload-free child case? |
|---|------|-------|-----------|--------------|--------------------------|
| 1 | `CounterList.counters` | Counter | *none visible* (`var count = 0`) | ✗ | — |
| 2 | `Nested.rows` | Nested | **UUID** | 3b canned | ✓ `addRowButtonTapped` — **self-recursive** |
| 3 | `Favoriting.episodes` | Favoriting | **UUID** | 3b | ✓ `buttonTapped` |
| 4 | `CityMap.cityMaps` | DownloadComponent | **UUID** | 3b | ✓ `buttonTapped` |
| 5 | `VoiceMemos.voiceMemos` | VoiceMemo | URL (computed) | ✗ | — |
| 6 | `iOS17 IdentifiedList.rows` | ObservableBasicsView.Feature | **UUID** | 3b | ✓ many |
| 7 | `iOS16 IdentifiedList.rows` | BasicsView.Feature | **UUID** | 3b | ✓ |
| 8 | `Todos.todos` | Todo | **UUID** | 3b | ✗ — child is **only** `binding(BindingAction)` |

**ID distribution: UUID 6/8 (75%), URL 1, none-visible 1, `Int`/`String` 0/8.**

Consequences for the sub-slices:

- **3a (Int/String id) has ZERO reach.** No real reducer uses an `Int`/`String`
  `IdentifiedArray` id — they are all `UUID`. The originally-recommended
  "land 3a only" would recognize nothing. The Int/String `RawType` path is
  speculative and must not be the standalone deliverable.
- **3b (canned zero-UUID) is the actual minimal honest increment — reach ≈ 5/8.**
  UUID id + a constructible payload-free child both hold for Nested, Favoriting,
  CityMap, and the two Integration Features. Excluded: Todo (child is pure
  `BindingAction` → slice 4), VoiceMemo (URL id), Counter (no visible id).
- **3c (depth-bounded recursion) adds 0 reach on this corpus** and only
  introduces the self-recursive-`Nested` termination hazard — every reachable
  UUID case already has a payload-free child, so depth-0 suffices (Nested
  included: pick `addRowButtonTapped`, don't recurse). Confirmed low-value; defer.
- **The no-op-against-empty-State caveat is confirmed empirically**: all 8 are
  `.forEach` over an initially-empty `IdentifiedArray`, so every constructed
  `.element(id:action:)` no-ops. Even 3b's 5/8 buys disclosure-set reduction,
  not new counterexample-finding signal — exactly the ROI reframe above.

## Recommendation (revised by the recount)

Skip 3a as a standalone (0 real reach) and build **3b directly**: recognize
`IdentifiedActionOf<Child>` / `IdentifiedAction<ID, Action>`, resolve `Child`'s
candidate, require a defaultable id (`UUID` via the canned zero-UUID literal;
`Int`/`String` via `RawType` folded in for free) **and** a payload-free child
case, and emit `Gen.always(.<case>(.element(id: <id>, action: .<childFreeCase>)))`
— no recursion. Everything else stays excluded + disclosed, and the verdict
annotation states the no-op-against-empty-State caveat. Keep **3c deferred**
(confirmed 0 added reach + the recursion hazard). This holds the cycle-124
posture (widen the constructible subset, disclose the rest) without overbuilding
recursion for reach that isn't there.
