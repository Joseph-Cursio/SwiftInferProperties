# v1.92 Calibration Cycle 89 — Findings (M1.A 4th-shape + scalar filter)

Captured: 2026-05-16. swift-infer at v1.92.

## Headline

**Two cycle-87 findings closed in one push.** v1.92 lands:

- **Finding #4** (M1.A blind to `(inout S, A) -> Effect<A>`):
  `ReducerDiscoverer.matchReducer` learns the 4th canonical reducer
  shape. The case label `inoutStateActionReturnsEffect` existed
  since v1.83 (M1.B closure walker); M1.A's signature scan now
  recognizes the same shape on plain methods + free functions.
- **Finding #1** (signature-only scan produces two-scalar false
  positives): `ReducerDiscoverer.matchReducer` rejects candidates
  where both State and Action types are in a curated scalar set
  (Int / UInt variants, Bool, Double, Float, String, Character —
  both `Swift.`-prefixed and bare).

**Reducer-detection count: 29 → 42 (+13, +44.8%).** TCA 1.0.0's
SwiftUICaseStudies alone jumped 19 → 31 reducers; UIKit picked up
1; tvOSCaseStudies (which had 0 detections at cycle-87) now
surfaces 1. Hand-rolled corpus lost 1 to the scalar filter (the
`transform(_: Int, _: Int) -> Int` known false positive).

**Interaction-suggestion count: 34 → 35 (+1).** The small delta
relative to the +14 reducer jump confirms cycle-87 finding #5
(only idempotence fires on real TCA — Action conventions skew
toward `task` / `delegate` / `binding` shapes outside the curated
idempotent set). Family-pattern calibration (queued cycle-87
follow-up) is the dominant gap, not detection.

After v1.92, two cycle-87 findings remain queued: M1.D `@Reducer`
macro recognition (#3) and family-pattern calibration (#5).

## What landed

### A — M1.A 4th-shape extension

`ReducerDiscoverer.matchReducer`'s inout-branch grew from one
sub-arm (return-must-be-Void) to two:

```swift
if firstIsInout {
    if returnType == "Void" || returnType.isEmpty {
        shape = .inoutStateActionReturnsVoid
    } else if looksLikeEffect(returnType) {
        shape = .inoutStateActionReturnsEffect
    } else {
        return nil
    }
}
```

New helper `looksLikeEffect(_:) -> Bool` matches the literal
prefix `"Effect<"` + suffix `">"`. Doesn't validate the type
argument since M1.B's closure walker also leaves it unchecked
(mirror posture).

The case label `.inoutStateActionReturnsEffect` was added in v1.83
for M8.B's effect-bearing verify path; M1.A's signature scan
previously rejected this shape entirely. Now M1.A and M1.B
recognize the same four shapes, with `.inoutStateActionReturnsEffect`
the most TCA-shaped of the four.

### B — Two-scalar false-positive filter

After shape classification, before constructing the candidate:

```swift
if Self.isScalarTypeName(firstType) && Self.isScalarTypeName(secondType) {
    return nil
}
```

`isScalarTypeName(_:)` checks membership in a curated set:

- Numeric: `Int`, `UInt`, `Int8`, `Int16`, `Int32`, `Int64`,
  `UInt8`, `UInt16`, `UInt32`, `UInt64`, `Double`, `Float`,
  `Float80`.
- Other primitives: `Bool`, `String`, `Character`.
- `Swift.`-prefixed equivalents for explicit-module callers.

Excludes `Optional<X>` (`X?`) and collection types like `[T]` since
both occasionally legitimately stand in for compact State. The
filter only fires when *both* halves are scalar — a `(MyEnum,
MyEnum) -> MyEnum` reducer still passes.

PRD §3.5 conservative-inference posture: when in doubt, the
detector should produce fewer false positives. Scalar State +
scalar Action has no plausible reducer interpretation.

### C — Tests (+9)

New tests in `ReducerDiscovererTests`:

**Shape 4 (4 tests)**:
- Method form: `Focus.reduce(into:action:) -> Effect<AppAction>`.
- Namespaced action: `Counter.reduce(into:action:) -> Effect<Counter.Action>`.
- Free function form (rare but symmetric; stays `.generic`, not `.elmStyle`).
- Negative: `(inout S, A) -> Publisher<A>` rejected — `Effect<...>`
  prefix is required.

**Scalar filter (4 tests)**:
- `(Int, Int) -> Int` rejected (the cycle-87 `transform` case).
- `(Bool, Bool) -> Bool` rejected.
- `(Int, Int) -> (Int, Effect<Int>)` rejected even with tuple
  return (the filter applies to all shapes, not just shape 1).
- Positive control: `(AppState, Int) -> AppState` accepted — only
  scalar+scalar gets rejected; struct State + scalar Action
  passes through.

One existing test renamed for accuracy: `shape2RejectsInoutWithReturn`
→ `shape2RejectsInoutWithStateReturn` (with updated docstring
noting that `(inout S, A) -> Effect<A>` is now recognized but
`(inout S, A) -> S` remains rejected).

Total test count: 3008 → 3017 (+9). Discoverer suite: 35 → 44.

## Measured delta

### Hand-rolled corpus

| Metric | Cycle-1 | Cycle-2 | Delta |
|---|---|---|---|
| Reducers | 8 | 7 | −1 (scalar filter caught `transform`) |
| Interaction suggestions | 18 | 18 | unchanged |

Per-family counts unchanged because the filtered `transform`
function had no Action enum to fire idempotence against.

### TCA 1.0.0 corpus

| Example | Reducers (c1 → c2) | Interactions (c1 → c2) |
|---|---|---|
| SwiftUICaseStudies | 19 → **31** (+12) | 12 → **13** (+1) |
| UIKitCaseStudies | 2 → **3** (+1) | 4 → 4 |
| tvOSCaseStudies | 0 → **1** (+1) | 0 → 0 |
| **Subtotal** | **21 → 35** (+14) | **16 → 17** (+1) |

The 14-reducer jump is entirely from shape 4. tvOSCaseStudies'
`Focus.reduce(into:action:)` becomes detectable for the first
time (cycle-87 specifically called this out as the missed case).
SwiftUICaseStudies has 12 more reducers using the same shape that
previously fell through the rejection path. The 1-suggestion
interaction-delta is the lone newly-detected reducer whose Action
case happens to match M4.C's curated idempotent set.

### TCA 1.25.5 corpus

Unchanged at 0 reducers across all 7 examples — `@Reducer` macro
remains the blind spot (cycle-87 finding #3). M1.D is the next
unlock.

### Corpus-wide cycle-2 baseline

| Cycle | Reducers | Interactions |
|---|---|---|
| 0 (v1.89) | 29 | 114 |
| 1 (v1.91) | 29 | 34 |
| **2 (v1.92)** | **42** | **35** |

Both deltas are now measured against persistent raw outputs:
- `docs/calibration-cycle-87-data/` — cycle-0 baseline
- `docs/calibration-cycle-88-data/` — cycle-1
- `docs/calibration-cycle-89-data/` — cycle-2

## What's next

Two cycle-87 findings remain:

1. **M1.D `@Reducer` macro recognition** — the highest-impact
   remaining unlock. TCA 1.25.5 still produces 0 reducers across
   all 7 examples surveyed; every `@Reducer struct Feature { ... }`
   declaration is invisible to v1.92's M1.B walker (which keys on
   the `: Reducer` inheritance clause that the macro replaces).
   Medium scope: new attribute-walker path parallel to M1.B.
2. **Family-pattern calibration** for real TCA conventions —
   cycle-89's +14 reducers / +1 interaction delta confirms that
   Action name conventions, not detection, are the dominant gap.
   M4.C's curated idempotent set (refresh / reset / clear /
   dismiss / cancel / close / hide / select + set/select/show/
   present prefixes) misses TCA's `task` / `delegate(...)` /
   `binding(.set(...))` shapes. Three-cycle calibration loop.

#1 unblocks #2 — without `@Reducer` macro recognition, the
calibration corpus can't grow to a meaningful size for #2.
