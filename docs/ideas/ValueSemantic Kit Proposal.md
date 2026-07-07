# ValueSemantic Kit Proposal

**Status (updated 2026-07-07):** **Workstream 1 SHIPPED; Workstream 2 resolved (no action); Workstream 3 mostly pre-existing, remainder low-value.**
- **WS1 `ValueSemantic`** — **delivered end-to-end.** The kit ships `ValueSemantic` + `DefensiveCopy` + `StableIdentity` (protocols + `*Laws` + peer macros, kit **v3.4.0–v3.9.0**), and the engine discovers + measured-verifies all three §2.2 bug classes (`valuesemantic-verify-corpus`: `SafeStore`/`LeakyStore`/`ClosureCounter`). The closure-capture case (open decision #8) shipped as multi-step interleaving (`copyMutationDoesNotLeakUnderInterleaving`, kit v3.5.0). See §6 for the as-built version map.
- **WS2 shrinking** — **premise resolved, nothing to build here.** `swift-property-based` already provides `.shrink(towards:)`, and the engine uses it in its emitted verifiers (algebraic since v1.141; MVVM state-invariant sequences since 2026-07). The proposal's actual workstream — refactoring `Gen<T>` to carry a shrinker — targets `x-sheep/swift-property-based`, an **external dependency the owner doesn't control**; the practical need is met engine-side.
- **WS3 primitives** — `frequency` / `recursive` / `sized` / the edge-case-biased generators (v2.1.0) already exist; the only genuine gap is the **Foundation generators** (`Gen.date/url/data/uuid`), which are **low-value** because the engine's verify path uses its own deterministic curated literals (`ViewModelArgumentGenerator`), not kit generators. Optional kit-user convenience only.

**Original status:** Draft / proposal — not yet committed to any milestone.
**Target:** SwiftPropertyLaws (kit) + swift-property-based (engine); pre-requisite to a SwiftInferProperties §8 PRD section. *(Kit is now at v3.9.0, well past the v2.0.0 this note was drafted against.)*
**Date:** 2026-05-04 (status refreshed 2026-07-07)

## 1. Summary

Three related workstreams, each independently shippable:

1. **`ValueSemantic` protocol** — a new kit-defined property family covering type-level integrity ("copying then mutating doesn't affect the original"). New PRD section in SwiftInferProperties (not a §5 retrofit) since it's *type-level*, not *function-level*. — **✅ SHIPPED (kit v3.4.0–v3.9.0), extended to `DefensiveCopy` + `StableIdentity` reference-type companions.**
2. **Shrinking** in swift-property-based — when a property fails on a generated 200-element array, narrow it to the minimal failing case. Architecturally load-bearing; touches the `Gen<T>` API. — **RESOLVED: `.shrink(towards:)` already exists in swift-property-based and the engine uses it; the `Gen<T>` refactor is on an external unowned library. No owner action.**
3. **More PBT primitives** in the kit — `Gen.frequency`, `Gen.recursive`, ergonomic `Gen.filter`, Foundation generators, sized generators. Incremental; ship one at a time. — **PARTLY PRE-EXISTING** (`frequency` / `recursive` / `sized` / edge-case-biased present); only the Foundation generators are missing, and they're low-value (engine uses curated literals, not kit generators).

The three are linked: `ValueSemantic` test stubs benefit immediately from shrinking; mutation-parameter generators benefit from new primitives. But each can ship on its own schedule.

-----

## 2. Motivation

### 2.1 Why ValueSemantic in the kit

A type has value semantics if mutating one instance is unobservable through any other instance. The Swift stdlib is designed around this; many libraries claim it without verifying it. Real bug classes:

- Struct holding `NSMutableArray` (or any class-typed stored property without CoW machinery)
- Struct with an escaping-closure stored property capturing shared mutable state
- CoW types where the CoW path is broken or incomplete
- Accidental reference sharing through `inout` aliasing

The property is uniformly testable: for every mutating operation `m` on `T`, copying-then-mutating cannot be observed via the original. That's exactly the "law-bearing protocol + auto-generated test scaffolding" mold the kit already runs on for Semigroup / Monoid / Group / Semilattice.

### 2.2 Worked examples of bugs caught

Each example shows a struct that *claims* `ValueSemantic` conformance, the mutation that leaks, and what the auto-generated test would assert.

**Example 1 — Reference container leak (the obvious case).**

```swift
struct Inventory: ValueSemantic {
    private var items: NSMutableArray = []
    var count: Int { items.count }
    mutating func add(_ item: String) { items.add(item) }
}

var a = Inventory()
a.add("apple")
var b = a              // struct copied; NSMutableArray inside is the SAME instance
b.add("banana")
// a.count == 2 — leaked through b
```

The struct copy duplicates the `items` reference, not the underlying array. Mutating `b` mutates the array `a` still points at. The auto-generated test fails on the first `add` invocation: `var b = a; b.add(s); a.count == originalCount(a)` → false.

**Example 2 — Broken copy-on-write (the subtle case).**

```swift
struct Buffer: ValueSemantic {
    private final class Storage { var bytes: [UInt8] = [] }
    private var storage = Storage()
    var bytes: [UInt8] { storage.bytes }

    mutating func append(_ byte: UInt8) {
        // BUG: missing `if !isKnownUniquelyReferenced(&storage) { storage = copy() }`
        storage.bytes.append(byte)
    }
}

var a = Buffer()
a.append(1)
var b = a              // shares Storage
b.append(2)
// a.bytes == [1, 2] — should have stayed [1]
```

The struct *intends* CoW but never triggers the uniqueness check. The test catches it the same way as Example 1 — post-mutation comparison fails. This is the case where opt-in conformance plus runtime verification has the most leverage: the developer believes they wrote a value type, the structural detector sees the class-typed stored property and would have flagged it, but the developer's CoW intent silences the static warning. Only the runtime test catches the implementation bug.

**Example 3 — Closure capturing mutable state (the sneaky case).**

```swift
struct Counter: ValueSemantic {
    private let increment: () -> Int    // captures `box` by reference
    private(set) var lastValue = 0

    init() {
        var box = 0
        self.increment = { box += 1; return box }
    }

    mutating func tick() { lastValue = increment() }
}

var a = Counter()
a.tick()               // a.lastValue == 1
var b = a              // closure captured the same `box`
b.tick()               // b.lastValue == 2
a.tick()               // a.lastValue == 3 — would be 2 if `a` were independent
```

The closure captures a heap-allocated reference (the captured `var box`), so every copy shares the same counter state. This case is harder than Examples 1–2 because mutating `b` doesn't directly change `a`'s observable state — `a.lastValue` is still `1` immediately after `b.tick()`. The leak only surfaces on `a`'s *next* mutation, which sees the contaminated `box`. Catching it requires multi-step property tests (mutate `b`, then mutate `a`, then compare `a` against the original-mutated-without-`b`-interference). Open decision #8 below tracks whether the V1 test architecture covers this case or defers it to V1.x.

### 2.3 Why shrinking now

Every property test SwiftInferProperties emits today returns its failing example unminimized. A 200-element array counterexample is much harder to debug than a 3-element one. Shrinking is the single biggest QoL feature modern PBT libraries (Hedgehog, modern Hypothesis) ship — and once the engine has committed to a non-shrinking architecture, retrofitting is invasive. The earlier this lands, the cheaper it is.

### 2.4 Why more primitives

Every `?.gen()` placeholder SwiftInferProperties emits in the `.todo` fallback case is a moment of user friction. The fewer primitives the kit ships, the more the user has to write themselves. Foundation generators (`Gen.date()`, `Gen.url()`, `Gen.data(of:)`), structured combinators (`Gen.frequency`, `Gen.recursive`), and sized generators directly reduce that friction.

-----

## 3. The `ValueSemantic` Protocol

### 3.1 Shape

```swift
public protocol ValueSemantic: Equatable {
    // Marker — no required methods.
}
```

`Equatable` is required so the test can compare original-before vs. original-after. Conformance is **opt-in** (not auto-derived); the user explicitly claims their type has value semantics, and the kit's auto-generated test verifies it.

### 3.2 The property

For every mutating operation `m` on `T`:

```
let a_original = a              // capture
var a_copy = a                  // copy
m(&a_copy, params...)           // mutate copy with generated params
a == a_original                 // original unchanged
```

The kit synthesizes one property test per discovered mutating operation. Failure surfaces the specific mutation that leaked, which is what makes the diagnostic useful.

### 3.3 Mutation enumeration

The kit's existing macro discovery (the same one that finds Semigroup / Monoid laws) walks decls. Extend it to recognize:

- `mutating func` declarations
- Settable stored `var` properties
- Mutating subscript setters

Each becomes one sub-test. Mutating methods with parameters need generators for the parameter types — the kit already has the strategist to derive them.

### 3.4 CoW handling

Opt-in is the answer. Types like `Array` deliberately conform to `ValueSemantic` even though they hold a class internally; the test verifies *exposed* semantics, not implementation. The structural detector in SwiftInferProperties (a separate workstream — §8 of that PRD) backs off on types that explicitly conform — the user has claimed it, the runtime test is the verification.

### 3.5 Out of scope for the protocol itself

- Reference-semantics types (classes) — not the target
- Sendable / concurrency-safety — related but distinct property family
- "Partial" value semantics (some operations safe, others not) — not modeled in v1

-----

## 4. Shrinking

### 4.1 Prerequisite: audit the current state — ✅ RESOLVED

**Step zero was done: shrinking already exists in swift-property-based.** Values expose `.shrink(towards:)`, and the engine drives it in its emitted verifiers — the algebraic stubs since v1.141 (`scalarShrinkPhase` shrinks a failing Int/Double counterexample toward 0, emitting `VERIFY_DEFAULT_SHRUNK` + `VERIFY_SHRINK_STEPS`), and the MVVM state-invariant sequences since 2026-07 (greedy-shrink the failing action sequence). So the whole "is shrinking absent?" branch collapses: the API-break concern is moot, and **the `Gen<T>` refactor below targets `x-sheep/swift-property-based` — an external dependency the owner doesn't control.** The rest of §4 is retained as background; there is no owner-side work here.

### 4.2 Architecture choice

Two options:

| | Integrated (Hedgehog-style) | External (old-QuickCheck-style) |
|---|---|---|
| **Where shrinkers live** | Attached to `Gen<T>` itself | Separate `Shrinker<T>` registry |
| **Pro** | Always available; never out of sync; composable | Less invasive; opt-in |
| **Con** | Invasive `Gen<T>` refactor (API break) | Easy to forget; drifts from generator |

**Recommendation: integrated.** The composability matters — when a user writes `.map`, `.flatMap`, `Gen.tuple`, the shrinker has to compose with the same operators. External shrinking forces the user to maintain a parallel structure, and they won't.

The cost is real: it's a `Gen<T>` API break, and a major version bump for swift-property-based + every consumer. Worth it.

### 4.3 Per-primitive shrinking strategies

Standard heuristics:

| Type | Shrink toward |
|---|---|
| `Int` / `UInt` | 0, then halve toward zero |
| `Double` / `Float` | 0.0, then halve; -inf / +inf / NaN special-cased |
| `String` | empty, then drop characters |
| `Array<T>` | empty, then halve length, then shrink elements |
| `Optional<T>` | `.none`, then shrink the wrapped value |
| `Result<T, E>` | shrink toward success, then shrink the wrapped value |
| User types | per-stored-property shrinker derived by the strategist |

### 4.4 The `Gen.filter` problem

Filter-with-shrinker is a known hard problem: a shrunk value might not satisfy the filter predicate. Standard answers:

- Track multiple candidate paths in the shrink tree
- Bounded retries with explicit budget surfaced in the API: `Gen.filter(_:retries: 100)`
- Fail loudly when retries exhaust rather than silently widen the search

Recommend the explicit-retry-budget API even pre-shrinking — unbounded `filter` is a footgun regardless.

### 4.5 Shrunk-counterexample provenance

When shrinking succeeds, the test failure should include both the *original* generated counterexample and the *shrunk* one, plus how many shrink steps it took. Useful for debugging the shrinker itself, and reassures the user that shrinking actually ran.

-----

## 5. More PBT Primitives

**Status:** `frequency`, `recursive`, `sized`, and the edge-case-biased generators (v2.1.0) already exist in the kit / swift-property-based. The only genuine gap is the **Foundation generators** (`Gen.date/url/data/uuid`) — and they're **low-value for this project** because the engine's verify path emits its own deterministic curated literals (`ViewModelArgumentGenerator`) rather than consuming kit generators (verify needs fixed values). So the remaining table below is an **optional kit-user convenience**, not an engine capability. Ship on demand if kit users ask.

Each shippable independently as a kit minor version. Order is a sequencing decision, not a design decision.

| Primitive | Purpose |
|---|---|
| `Gen.frequency([(weight, gen)])` | Weighted choice — e.g., "10% empty, 90% non-empty" |
| `Gen.oneOf([gen])` | Uniform choice (verify whether already exists) |
| `Gen.recursive(depth:_:)` | Tree-shaped types with explicit depth bound |
| `Gen.filter(_:retries:)` | Bounded filter; replaces unbounded variant |
| `Gen.sized { size in ... }` | Generators that scale with framework size parameter |
| `Gen.date()` | Foundation `Date` |
| `Gen.url()` | Foundation `URL`; valid URLs only |
| `Gen.data(of: countRange)` | Foundation `Data` with size control |
| `Gen.uuid()` | Foundation `UUID` |
| `Gen.array(of: elementGen, count: range)` | Size-controlled array (verify whether already exists) |

-----

## 6. Milestone Sketch

Three K-prep series, mirroring the M7-prep / M8-prep pattern.

### K-prep-V1 — `ValueSemantic` (kit) — ✅ SHIPPED (as-built version map)

The as-built shape went further than this sketch — a copy-mutate-compare law plus two reference-type companions, each with its own peer macro + engine discoverer + measured verifier:

- **kit v3.4.0** — `ValueSemantic` protocol + `ValueSemanticLaws` (`copyMutationDoesNotLeak`, single-step).
- **kit v3.5.0** — multi-step `copyMutationDoesNotLeakUnderInterleaving` (resolves open decision #8 — the closure-capture case).
- **kit v3.6.0** — `@ValueSemanticTests` peer macro.
- **kit v3.7.0 / v3.8.0** — `DefensiveCopy` + `StableIdentity` (reference-type companions: distinct-copy + identity-stability laws).
- **kit v3.9.0** — `@DefensiveCopyTests` + `@StableIdentityTests` macros (shared `LawTestPeerMacro`).
- **Engine side** — `ValueSemanticDiscoverer` / `DefensiveCopyDiscoverer` / `StableIdentityDiscoverer` (surfaced in `discover-reducers`) + `ValueSemanticVerifier` (self-contained + package-path-dep), proven on `valuesemantic-verify-corpus` (`SafeStore` bothPass / `LeakyStore` defaultFails / `ClosureCounter`) + `valuesemantic-package-corpus`. See `docs/valuesemantic-build-plan.md`.

*(Original sketch, for the record:)*
1. **V1.0** — Audit existing macro discovery; sketch the extension surface for mutating-method enumeration.
2. **V1.1** — `ValueSemantic` protocol declaration + auto-derived `Equatable` integration.
3. **V1.2** — Macro extension for mutating-method discovery.
4. **V1.3** — Auto-generated property tests (one sub-test per mutating operation).
5. **V1.4** — Validation suite + release docs.
6. ~~Ship as kit v2.1.0~~ — shipped across v3.4.0–v3.9.0 instead (v2.1.0 became the edge-case-biased generators).

### K-prep-V2 — Shrinking (engine, breaking)

1. **V2.0** — Audit current swift-property-based shrinking state. *Output: a one-page report.*
2. **V2.1** — Architecture decision (integrated vs. external; default: integrated).
3. **V2.2** — Refactor `Gen<T>` to carry shrinker.
4. **V2.3** — Per-primitive shrinkers.
5. **V2.4** — `Gen.filter(_:retries:)` migration.
6. **V2.5** — Failure-message provenance (shrunk vs. original counterexample).
7. **V2.6** — Validation suite + release docs.
8. **Ship as kit v3.0.0** (major bump — `Gen<T>` API breaks; the v2.x line stays on the post-rename pre-shrinking shape).

### K-prep-V3 — Primitives (kit, non-breaking)

Each primitive ships as a minor bump after V2 (so v3.1.0, v3.2.0, …). No architectural commitments; ship as user demand surfaces. Suggested order: `frequency` → `recursive` → Foundation generators (`date`, `url`, `data`, `uuid`) → `sized` → others.

### Then SwiftInferProperties-side

- New PRD section **§8 "Type Integrity Properties"** with its own M-series:
  - **M-VS-1** — Structural detector (negative signals: class-typed stored prop / `NSMutableX` / escaping-closure capture; positive signal: all-value-type stored props)
  - **M-VS-2** — Conservative-bias suppression for opt-in CoW types (back off when `ValueSemantic` conformance present)
  - **M-VS-3** — RefactorBridge writeout for "Add `ValueSemantic` conformance" proposals
  - **M-VS-4** — TestLifter detector for `let copy = a; copy.x = ...; XCTAssertEqual(a.x, ...)` shapes → +20 cross-validation seam

-----

## 7. Open Decisions

1. **Equatable requirement.** Some types are intentionally non-Equatable (closures stored as properties, etc.). Should `ValueSemantic` *require* `Equatable`, or offer a key-path-based fallback (`ValueSemantic` plus an associated witness saying which key-paths to compare)?
2. **Reference-semantics companion.** Out of scope, or do we add `ReferenceSemantic` asserting the opposite for documentation purposes?
3. **CoW opt-in mechanics.** Does plain conformance suffice, or do users need to also implement a `triggerCoWForTesting()` method that the kit calls to ensure the CoW path is exercised in the test?
4. **Shrinking architecture.** Integrated vs. external — needs the V2.0 audit to confirm the call.
5. **Sequencing V1 vs. V2.** Ship `ValueSemantic` (V1) first to deliver the user-visible property family fastest, or ship shrinking (V2) first so `ValueSemantic` debuts with shrunk counterexamples? V1-first → faster shipping; V2-first → better debut. Lean: V1-first, accept that early `ValueSemantic` failures show unminimized counterexamples until V2 lands.
6. **Versioning.** Bundle V2 + V3 into a single 2.0 cut to amortize the breakage, or ship V2 alone and add primitives non-breakingly afterward? Lean: V2 alone, then primitives — primitives shouldn't wait on each other.
7. **`Gen.oneOf` / `Gen.array(of:count:)` existence.** Verify whether these already exist in swift-property-based before listing them as "additions".
8. **Multi-step test architecture (closure-capture case, §2.2 Example 3).** The simple "copy → mutate copy → compare original" test shape doesn't catch closure-captured shared state — the leak manifests on the *next* mutation of the original, not immediately. Options: (a) extend the test to a two-step sequence (`mutate b; mutate a; compare a against a-mutated-without-b`); (b) defer this case to V1.x with explicit "single-step semantics only" documentation in V1; (c) detect closure-typed stored properties at the structural layer and flag them as inherently incompatible with `ValueSemantic` conformance. Lean: (b) for V1 + a §6 §6.3 follow-up milestone for multi-step tests once the basic surface is proven. — **✅ RESOLVED: shipped option (a).** `ValueSemanticLaws.copyMutationDoesNotLeakUnderInterleaving` (kit v3.5.0) does the two-step interleaving; the `ClosureCounter` corpus fixture is the closure-capture proof. Decisions #4/#7 are moot per §4.1 (shrinking already exists, external); #1 (`Equatable`) shipped as required.

-----

## 8. Explicitly Out of Scope

- **Coverage instrumentation** (distribution coverage like "10% of generated lists were empty"; statement/branch coverage during PBT runs). Lower leverage; deferred to a separate proposal if pursued.
- **The SwiftInferProperties-side detector implementation** — captured here only as a downstream pointer; gets its own PRD section + plan once the kit lands.
- **Reference-semantics property family** — see open decision #2.
- **Sendable / concurrency-safety property family** — related but distinct; separate proposal.

-----

## 9. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| `Gen<T>` refactor breaks existing kit consumers | High (it's an API break) | V2 ships as kit v3.0.0; coordinate with downstream consumers; keep the migration trivial via deprecated shims for one minor cycle |
| Mutation enumeration misses an operation, false-passes a leaky type | Medium | Macro discovery should err on the side of over-enumeration; tests for the enumerator itself |
| Shrinker for user types diverges from generator | Low if integrated; high if external | Integrated architecture eliminates this by construction |
| CoW types still false-positive after opt-in (CoW path not exercised in test) | Medium | Open decision #3 — explicit `triggerCoWForTesting` may be required |
| Shrinking adds runtime overhead even when not needed | Low | Shrink only on failure; sampling-pass uncost-affected |
| Scope creeps — V1 + V2 + V3 + four §8 milestones is a lot | High | Each ships independently; explicit "ship V1 alone is fine" stance |
