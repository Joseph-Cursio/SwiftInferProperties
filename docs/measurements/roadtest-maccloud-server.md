# Road-test — MacCloud_server (2026-07-18)

Third and final MacCloud fixture (after the iOS and macOS clients). Toolchain-facing
record. Outcome: **one toolchain fix shipped** (namespace-reducer qualification), the
**async clock-deterministic reducer verify validated** on a real server reducer, and
**no fixture bugs** — plus two of my own working hypotheses corrected along the way,
recorded here because the corrections are the useful part.

## Setup

SwiftPM package (Vapor/Fluent). The pure kernel is **`SyncCore.SyncEngine`** — a
`reduce(_ state: SyncState, _ action: SyncAction) async -> SyncState` state machine
marked `@lint.determinism clock_deterministic`, already partially PBT-adopted (its
tests depend on `PropertyLawKit`, and it ships hand-written invariant tests). The
Vapor/Fluent layer is I/O and surfaces nothing algebraic (`discover` → 4 Possible,
all noise) — correct. `SyncEngine` is a **reducer**, so the tool is
`discover-interaction`, not algebraic `discover`.

## Toolchain positive — async clock-deterministic reducer verify

`discover-interaction` discovered `SyncEngine.reduce` and the **`determinism` family
is Verified (80)** — `reduce(s,a) == reduce(s,a)` measured **bothPass, 1024/1024
clean**. The async-verify-via-clock-determinism path (v1.146) works end-to-end on a
real, independent server reducer. Strong positive.

## Toolchain fix — namespace-reducer qualification (shipped)

The tool reported `SyncAction` as an *open* alphabet and surfaced only `determinism`
+ `unknown-action-is-no-op`, missing the richer witness families. The root cause was
**not** the empty case set (that only gates the vacuous `unknown-action-is-no-op`) —
it was a **name over-qualification bug**:

- A reducer that is a **method on a namespace** (`enum SyncEngine { static func
  reduce }`) with **top-level** State/Action. Discovery's `qualifyIfNested`
  (cycle-109) correctly leaves `SyncAction` bare (not in the namespace's nested-type
  set), but `ReducerCandidate.qualify()` (cycle-88) then re-prepended →
  `"SyncEngine.SyncAction"`. The witness detectors' type-stack **suffix match** never
  matched that 2-component name against the top-level `["SyncAction"]`, so
  idempotence / conservation / cardinality / refint / biconditional all silently
  vanished for this shape. A free-function Elm reducer (`enclosingTypeName == nil`)
  works, which is why the gap was invisible until a *namespace-method* reducer.

**The fix** (commit on `main`): the `qualify()` prepend (cycle-88) is redundant to
`qualifyIfNested` (cycle-109), which already qualifies NESTED names at discovery and
leaves TOP-LEVEL names bare. `stateQualifiedName`/`actionQualifiedName` now trust the
discovery-time name. Validated end-to-end on sync **and** annotated-async namespace
reducers with a vocab-matching action (`.reset` → idempotence fires; was silent).

**Regression safety:** the cycle-88 prepend was the anti-inflation mechanism for the
cycle-87 finding (bare `Action` matching every reducer, ~8×). Removing it is safe
because `qualifyIfNested` produces distinct qualified names for nested types
(`AReducer.State` ≠ `BReducer.State`) — proven by a new **real-discovery**
no-contamination test, and the frozen-corpus witness counts are unchanged. The three
cycle-87 guard suites hand-built bare-name candidates that leaned on the prepend;
they were updated to construct discovery-faithful (qualified) candidates.

## Corrected hypotheses (the useful part)

1. **"Empty session can't complete" is NOT a bug.** `sessionCompleted` requires
   `queuedChunks > 0`, so a 0-chunk session never completes — but there's an explicit
   `emptySessionCannotComplete()` test asserting exactly that. Intentional design.
   (Checked the answer key before claiming a bug — the road-test discipline.)
2. **There is no "async witness gap."** I initially thought async reducers skipped the
   witness families. They don't — `witnessBasedFamilies` runs unconditionally.
   Annotated async + `.reset` → idempotence fires once qualification is correct. The
   whole gap was qualification.
3. **`verifiedChunks <= queuedChunks` isn't a family the tool has.** The author's
   `accountingInvariantHolds` is a **relational counter** invariant, not conservation's
   `count == collection.count`. So the tool "missing" it is out-of-catalog, not a gap.

## No fixture bugs

`SyncEngine` is small, well-designed, and already property-tested
(`accountingInvariantHolds`, `phaseActionsAreIdempotent`, the transition-legality
tests). Nothing to fix on the server value layer.

## Recall follow-up (separate, optional)

`SyncEngine`'s *own* invariants still don't surface even post-fix:
- **Idempotence:** its phase actions (`sessionStarted` / `uploadStalled` /
  `sessionCompleted` / `sessionCancelled`) are genuinely replay-idempotent (per the
  legality table), but those names aren't in the idempotence witness verb set — the
  tool conservatively doesn't guess. Expanding the vocabulary with session-lifecycle
  verbs is a precision-sensitive **recall** item (cf. the docstring-corroboration
  vocab work), not this bug.
- **Relational counter invariants** (`a <= b` between two counters) have no family at
  all — a possible new family, out of scope here.

## Net — the three-fixture MacCloud road-test

| Fixture | Result |
|---|---|
| iOS | (prior) established the two-tool workflow + the fixture-bug method |
| macOS | 2 fixture bugs fixed (sync path-key mismatch; ChunkPlan `Int.max` overflow); toolchain fix (`Data` ∈ Equatable stdlib); comparator extraction + SWO properties |
| server | toolchain fix (namespace-reducer qualification); async clock-deterministic verify validated; no fixture bugs |

Two toolchain fixes shipped, two fixture bugs fixed, one boundary documented, and the
async-verify + two-tool workflows validated on independent fixtures. See
`docs/roadtest-maccloud-macos.md` for the macOS half.
