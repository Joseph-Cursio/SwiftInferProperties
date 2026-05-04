# Stateful Testing Kit Proposal

**Status:** Draft / proposal — not yet committed to any milestone.
**Target:** SwiftPropertyLaws (kit, currently at v2.0.0) + swift-property-based (engine); enables a future SwiftInferProperties §9 PRD section.
**Date:** 2026-05-04
**Companion to:** `docs/ideas/ValueSemantic Kit Proposal.md` — drafted in the same conversation.

## 1. Summary

Add **stateful / model-based testing** to the kit: generate a sequence of commands against a System Under Test (SUT), run each against both the SUT and a user-provided reference model, and assert observable equivalence after every step. Single workstream, one major release; ships independently of the ValueSemantic and shrinking proposals on a parallel track.

Versioning context: ValueSemantic V1 → kit v2.1.0; **stateful testing → kit v2.2.0**; ValueSemantic V2 (shrinking) → kit v3.0.0; ValueSemantic V3 (primitives) → kit v3.x. Stateful testing lands before shrinking, accepting that early failure messages show unminimized command sequences until v3.0.0; the value-shrinkers from v3.0.0 then retroactively power up command-parameter shrinking.

-----

## 2. Motivation

### 2.1 Why stateful testing now

Every existing kit primitive — `forAll`, `Semigroup`/`Monoid`/`Group` law checks, the planned `ValueSemantic` mutation tests — is **single-step**: given a value, check a property. Stateful testing is **multi-step**: given a sequence of commands, check invariants throughout. This is the category of test that catches bugs which:

- Emerge from a specific *order* of operations, not from any individual call
- Require *accumulated state* before the bug surfaces
- Hide in the composition of operations that are individually correct

These bugs are systematically missed by single-step PBT. Erlang QuickCheck built its reputation on stateful testing precisely because it's the only category that reaches them. The kit currently can't express this category at all — it's a categorical expansion, not another law family.

### 2.2 Why now (versus later in the roadmap)

Two reasons:

1. **The ValueSemantic Example 3 problem (§2.2 of the ValueSemantic proposal) needs multi-step tests.** The closure-captured-state case fails on the *next* mutation of the original after a copy is mutated; single-step "copy → mutate copy → compare original" misses it. ValueSemantic open decision #8 currently defers this to a "V1.x follow-up". With stateful infrastructure in the kit, that deferral collapses to "use the command-sequence framework when it lands" rather than building a one-off two-step harness.

2. **swift-collections is a low-friction proof-of-value target.** Every type — `Heap`, `Deque`, `OrderedSet`, `OrderedDictionary`, `BitSet`, `TreeSet` — has an obvious reference model (sorted `Array`, dedup `Array`, `Set<Int>`, etc.). A small command vocabulary per type plus the reference model is enough for a meaningful test suite. The kit already runs Validation Pass 3 against `swift-collections@8e5e4a8f`; extending that pass into stateful + differential is the highest-leverage thing we can do with that pinned dep.

### 2.3 Worked examples of bugs caught

Each example shows a buggy stateful type, the failing sequence the framework would generate, and what divergence reveals.

**Example 1 — Order-dependent bug (the obvious case).**

```swift
struct PriorityQueue<T: Comparable> {
    private var heap: [T] = []
    mutating func insert(_ x: T) { heap.append(x); heap.sort() }   // BUG: should sort descending
    mutating func popMin() -> T? { heap.popLast() }                 // BUG: pops max, not min
}
```

Generated failing sequence:
```
insert(3); insert(1); insert(5); popMin   // expected 1, got 5
```
The model (sorted `Array<T>`) returns `1`; the SUT returns `5`. Divergence at command 4. Single-call testing of `popMin` on an empty queue passes (returns `nil`), masking the inverted-order bug; only multi-step shows it.

**Example 2 — Accumulated-state bug.**

```swift
struct CappedSet<T: Hashable>: Sequence {
    private var storage: Set<T> = []
    let capacity: Int
    mutating func insert(_ x: T) {
        if storage.count >= capacity { storage.remove(storage.first!) }   // BUG: removes arbitrary element on overflow
        storage.insert(x)
    }
    func contains(_ x: T) -> Bool { storage.contains(x) }
    // … sequence conformance …
}
```

Reference model: an `Array<T>` with FIFO eviction (oldest-first). Generated failing sequence:
```
insert(1); insert(2); insert(3); insert(4); contains(1)    // expected false, got true sometimes
```
The bug only surfaces *after* the storage is filled past capacity; below capacity the SUT and model agree. The non-determinism (`Set.first` is hash-order-dependent) makes the divergence intermittent — exactly the shape unit tests miss.

**Example 3 — Closure-capture leak via stateful framing (synergy with ValueSemantic).**

The ValueSemantic Example 3 (`Counter` carrying a closure that captures `box`) becomes catchable as a *two-instance* stateful test:

```swift
// Spec runs commands on two independent SUT copies a, b
// derived from the same initial state, asserting they remain
// independent under interleaved mutations.

initialize: a = Counter(); b = a
sequence:   a.tick(); b.tick(); a.tick()
expect:     a.lastValue == 2  (would be 2 if a were independent of b)
actual:     a.lastValue == 3  (the captured `box` was incremented by b.tick())
```

This isn't a *one-instance* command sequence; it's a *two-instance* independence check. The stateful framework V1 covers single-instance; the two-instance case is a small extension flagged in the open decisions. Both forms reuse the same command-sequence + shrinking infrastructure.

-----

## 3. The Spec Type

### 3.1 Shape

The user defines a `Spec` type (a struct conforming to a `StatefulSpec` protocol) that describes:

- **`SUT`** — the type under test
- **`Model`** — the reference type (typically simpler — `Array<Int>` for a `Heap<Int>`, etc.)
- **`Command`** — an enum or struct enumerating the operations
- **`Response: Equatable`** — what each command returns (use `Void` / a sentinel when there's no return value)
- **`initialState() -> (SUT, Model)`** — both starting empty/equivalent
- **`generateCommand(modelState: Model) -> Gen<Command>`** — state-aware generator (precondition logic lives here)
- **`runOnSUT(_:_:)` / `runOnModel(_:_:)`** — apply the command, return a `Response`
- **`postcondition(modelState: Model, command: Command, response: Response) -> Bool`** *(optional)* — global invariants beyond response equality

```swift
public protocol StatefulSpec {
    associatedtype SUT
    associatedtype Model
    associatedtype Command
    associatedtype Response: Equatable

    static func initialState() -> (SUT, Model)
    static func generateCommand(modelState: Model) -> Gen<Command>
    static func runOnSUT(_ command: Command, _ sut: inout SUT) -> Response
    static func runOnModel(_ command: Command, _ model: inout Model) -> Response
    static func postcondition(modelState: Model, command: Command, response: Response) -> Bool
}

public extension StatefulSpec {
    static func postcondition(modelState: Model, command: Command, response: Response) -> Bool { true }
}
```

### 3.2 The kit-side runner

```swift
public func checkStateful<S: StatefulSpec>(
    _ spec: S.Type,
    sequenceLength: Int = 50,
    iterations: Int = 100
) async throws -> StatefulCheckResult
```

Per iteration: generate a sequence of `sequenceLength` commands using `generateCommand` threaded through the model state; execute each against SUT and model in lockstep; assert response equality + postconditions after every command; on divergence, capture the command sequence and shrink it.

### 3.3 State threading: pre-state-aware generation

The generator takes the *current model state* and produces only valid commands for that state. This avoids the "generate any command, filter at execution" pattern (which produces too many invalid sequences and is hard to shrink). It does couple generation to the model — if `Heap.popMin` requires non-empty, the generator checks `model.isEmpty` and emits only `insert` until at least one element exists.

This mirrors Erlang QuickCheck's approach. The alternative (post-execution filtering) is simpler but burns sample budget on invalid commands; the pre-state approach is the standard answer.

-----

## 4. Sequence Shrinking

When a sequence of length 47 fails, the runner shrinks it to a minimal failing subsequence using three heuristics, applied iteratively until no further reduction succeeds:

1. **Drop individual commands.** Try removing each command in turn; keep the removal if the shorter sequence still fails.
2. **Drop spans.** Try removing contiguous runs of commands (length 2, 4, 8, 16, …); keep the span removal if the shorter sequence still fails.
3. **Simplify command parameters.** *(Available only after kit v3.0.0 brings integrated shrinking — until then, this step is a no-op.)* For each command in the minimal sequence, try shrinking its associated values via the underlying generator's shrinker.

The runner reports both the original failing sequence (for context) and the minimal sequence (for debugging).

-----

## 5. Failure Reporting

When a divergence is detected, the failure message includes:

- **Iteration / seed**: enough to reproduce
- **Command sequence (minimal)**: list of commands that triggered divergence
- **Command sequence (original)**: list before shrinking, for context
- **Divergence point**: index of the command where SUT and model first disagreed
- **State at divergence**: a description of the SUT and model at that step
- **Responses at divergence**: the disagreeing values

Format example:
```
StatefulSpec: HeapSpec failed.
  Seed: 0xDEADBEEFCAFEBABE
  Original sequence (47 commands).
  Minimal sequence (4 commands):
    [0] insert(3)        → ()                    [SUT and model agree]
    [1] insert(1)        → ()                    [SUT and model agree]
    [2] insert(5)        → ()                    [SUT and model agree]
    [3] popMin           → SUT: 5, model: 1      [DIVERGENCE]
  State at divergence:
    SUT (Heap):   storage=[5, 3, 1]  (note: violates min-heap invariant)
    Model (sorted Array): [1, 3, 5]
```

-----

## 6. swift-collections Validation Suite

Ship the framework with a per-type Spec for the core swift-collections types. These double as integration tests for the framework itself and as proof-of-value:

| SUT | Model | Commands |
|---|---|---|
| `Heap<Int>` | sorted `Array<Int>` | `insert`, `popMin`, `popMax`, `min`, `max` |
| `Deque<Int>` | `Array<Int>` | `prepend`, `append`, `popFirst`, `popLast`, `subscript(read)` |
| `OrderedSet<Int>` | dedup-preserving `Array<Int>` | `append`, `remove`, `contains`, `firstIndex(of:)` |
| `OrderedDictionary<Int, String>` | `Array<(Int, String)>` w/ key uniqueness | `subscript(set/get)`, `removeValue(forKey:)` |
| `BitSet` | `Set<Int>` | `insert`, `remove`, `contains`, `union`, `intersection` |
| `TreeSet<Int>` | sorted dedup `Array<Int>` | `insert`, `remove`, `contains`, set algebra |

Validation Pass 3 already pins swift-collections@8e5e4a8f and runs protocol laws against `TreeSet<Int>`. Extend that pass to run the per-type stateful Specs alongside.

-----

## 7. Milestone Sketch

### S-prep-1 — Framework (kit v2.2.0)

1. **S1.0** — `StatefulSpec` protocol declaration + associated types.
2. **S1.1** — Sequence runner (`checkStateful`) with state threading.
3. **S1.2** — Sequence shrinker (commands + spans only; parameter shrinking is a no-op until v3.0.0).
4. **S1.3** — Failure reporting (formatted output per §5).
5. **S1.4** — Documentation: protocol reference + a tutorial walk-through using a deliberately-buggy `PriorityQueue` (Example 1 from §2.3).
6. **S1.5** — Validation suite: `Heap` Spec only as a smoke test for the framework.

### S-prep-2 — swift-collections suite (kit v2.3.0)

1. **S2.0** — `Deque` + `OrderedSet` Specs.
2. **S2.1** — `OrderedDictionary` + `BitSet` Specs.
3. **S2.2** — `TreeSet` Spec.
4. **S2.3** — Wire all six into Validation Pass 3.

### After kit v3.0.0 (shrinking lands)

- **S-prep-3** — Upgrade S1.2 sequence shrinker to use integrated value-shrinkers from v3.0.0 (so command parameters shrink alongside the sequence).
- Ships as v3.x minor — not blocking on V3 primitives.

### SwiftInferProperties-side

Future PRD §9 "Stateful Property Inference" with its own M-series:

- **M-S-1** — TestLifter detector for stateful test bodies (heuristic: `var sut = T(); sut.foo(); sut.bar(); XCTAssertEqual(sut.x, ...)` shapes)
- **M-S-2** — TemplateEngine arm for inferring a command vocabulary from the SUT's mutating methods + observable getters
- **M-S-3** — RefactorBridge writeout for "Define a `StatefulSpec` for `T`" proposals
- **M-S-4** — Cross-validation +20 seam between TestLifter-detected stateful bodies and TE-side spec proposals

These are *post* kit-side shipment. The proposal here is kit-side only.

-----

## 8. Open Decisions

1. **Pre-state vs post-execution generation.** Recommended: pre-state (Erlang QuickCheck pattern, §3.3). Sticking point: it couples the command generator to the model. Alternative: generate any command, filter at execution. Lean: pre-state for v2.2.0; revisit if user friction warrants.

2. **Async commands.** Some types have `async` methods (e.g., actor-isolated containers). Should `runOnSUT` be `async`? Lean: yes, make it `async` from the start; sync commands can use the no-await form. Adds minimal complexity; future-proofs against actor SUTs.

3. **Two-instance / parallel command sequences.** The ValueSemantic Example 3 case needs two SUT instances under interleaved commands. Lean: defer to a follow-on milestone (S-prep-4); v2.2.0 ships single-instance only. Reason: two-instance design has its own thorny questions (interleaving order, divergence-attribution) that shouldn't gate the single-instance baseline.

4. **Concurrency / true-parallel sequences.** Erlang QuickCheck does parallel command sequences (multiple threads issuing commands against the same SUT). This is a much bigger lift — race detection, schedule generation, etc. Out of scope for this proposal; deferred indefinitely.

5. **Command discovery via macros.** Hand-writing the `Command` enum + `runOnSUT` switch is boilerplate. A future macro (`@StatefulSpec` on the SUT type?) could derive both from the SUT's mutating methods. Lean: out of scope for v2.2.0; prove the manual shape works first.

6. **Postcondition strength.** §3 ships `postcondition` as a `Bool`-returning hook for invariants beyond response equality. Should it be richer (a `Failure?` returning structured error info)? Lean: start with `Bool`; promote later if usage shows generic "postcondition failed" isn't informative enough.

7. **Sequence length default.** Current §3.2 default is 50 commands. Erlang QuickCheck defaults to 30; QuickCheck-Haskell to "size-controlled growth" (~10–100). Lean: 50 with a configurable override; revisit after the swift-collections suite measures real failure-detection rates.

8. **Sample budget allocation.** Within `iterations: 100`, how many commands per iteration on average? `100 × 50 = 5000` commands per `checkStateful` call is the upper bound. Performance review needed before settling defaults; might want a wall-clock budget instead of a count.

-----

## 9. Out of Scope

- **Two-instance / independence checks** (open decision #3) — flagged for a follow-on; powers the ValueSemantic Example 3 case but not in v2.2.0.
- **True-parallel command sequences** (open decision #4) — deferred indefinitely.
- **Macro-derived Spec generation** (open decision #5) — manual shape only for v2.2.0.
- **Race / interleaving / scheduling exploration** — well outside the v1 surface.
- **SwiftInferProperties-side detection of stateful tests** — separate workstream once kit lands.

-----

## 10. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Reference model drifts from SUT specification | High | Document explicitly: "the model is the spec; the SUT is the optimization." Model-vs-SUT divergence must be reconciled by updating one or the other, not by silencing the test. |
| Sequences too long → slow tests | Medium | `sequenceLength` default at 50; configurable. Add wall-clock budget (open decision #8). |
| Sequences too short → bugs not surfaced | Medium | Rely on the Erlang QuickCheck-tested heuristic of 30–50 commands; revisit after empirical data from swift-collections suite. |
| Pre-state generator coupling makes Spec authoring painful | Medium | Provide rich helpers in v2.2.0 (`generateInsertOnly`, `generateAnyValid`, etc.). Worst case: switch to post-execution filtering with a minor version bump. |
| Shrinker can't simplify command parameters until v3.0.0 | Low | Documented; sequence-shrinking alone (drop commands + spans) catches most failures meaningfully. v3.0.0 retroactively upgrades the experience. |
| `async` runOnSUT adds complexity for sync SUTs | Low | Provide a sync-shim helper; most users won't notice. |
| swift-collections version drift | Low | Already pinned at 8e5e4a8f for Validation Pass 3; same pinning works for the stateful suite. |
