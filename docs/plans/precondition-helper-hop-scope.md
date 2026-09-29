# Should an initializer that calls a trapping helper count as stating a precondition?

> **Status:** `shipped` · **As of:** 2026-09-29

A derived generator must not call an initializer that rejects arbitrary arguments; the kit declines one
whose body calls `assert` / `precondition` / `fatalError` / … (`InitializerPreconditionDetector`). The
detector reads one initializer's syntax, so a check routed through a helper is invisible to it:

```swift
public init(values: [Float]) {
    if values.count != 9 { HarbethError.failed("There must be nine values for 3x3 Matrix.") }
    self.values = values
}
// HarbethError.failed: #if DEBUG fatalError(…) #else log #endif
```

On Harbeth that was **5 of 7 traps** in `subject-harbeth.md` — the generator drawing 0–8 floats into
initializers requiring 9, 16, 20, 3 and 4. `criterion-a-swift-system.md` §8.5 sized the same gap one hop
through a *same-type* method (`SystemString._invariantCheck()`) at a ceiling of 61 candidate sites, and left
it unbuilt.

## 1. The change — swift-infer only, no kit release

During the scan's existing single pass, record (a) every function whose body calls one of the kit's
`preconditionFunctions`, keyed `Owner.name` (owner = the innermost enclosing type or extension, last path
component) or `name` for a free function, and (b) for each initializer, the keys of the functions it calls:
`T.f(…)` as `T.f`, `f(…)` / `self.f(…)` as `Owner.f` and `f`. `TypeShapeBuilder` then marks an initializer
`assertsPrecondition` when any callee key is a trapping key — so the kit's existing decline applies,
unchanged. One hop only: a helper that calls another helper is not followed.

## 2. Measurement

- **Harbeth**, same code (`6c01592`), before and after: the funnel census.
- **The 19 funnel repositories**, same code, before and after: the funnel census — the A/B for side effects.
- **A full `make test`**, whose batches assert discovery and generator baselines over the manifest corpora.

## 3. Predictions

| # | prediction |
|---|---|
| 1 | Harbeth: the 5 `codable-round-trip` generator traps disappear (traps 7 → **2**) — the stubs set aside with `.todo` instead |
| 2 | Harbeth: passes do not fall (66 → ≥ 66) |
| 3 | the 19 funnel repositories: **≤ 10 stubs** change outcome in total, and no pass becomes a failure |
| 4 | `make test` green with every batch unchanged |

## 4. What this does not answer

It trades a trap for a `.todo` — the type still has no generator; the reader is asked for one instead of the
suite dying. It follows one hop by name, so two functions with the same owner and name in different modules
are not told apart, and a helper that traps only on some paths counts the same as one that always does.
