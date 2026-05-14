# Cycle-60 — Monotonicity-pick investigation + findings correction

Captured: 2026-05-14. swift-infer at v1.63. Follow-up to
`docs/calibration-cycle-60-findings.md`.

## Why this note exists

The cycle-60 findings doc framed the v1.64 priority as a "Comparable-aware
monotonicity composer" closing "4 picks currently blocked on Comparable."
A direct verify-run investigation shows that framing is **wrong on two
counts**: the picks are not classified as Comparable-blocked in the
committed cycle-60 data, *and* a Comparable-aware composer alone would
close zero of them. This note records the evidence and re-scopes v1.64.

## The data discrepancy

`docs/calibration-cycle-60-findings.md` and
`docs/calibration-cycle-60-data/full-surface-summary.md` both report **4
`carrier-missing-required-conformance` picks** for cycle-60. The committed
cycle-60 survey JSON (`full-surface-outcomes.json`) contains **zero** —
`grep -c conformance` returns 0. The category is real (it appears in the
cycle-58 and cycle-59 JSONs, 2 each, and is emitted by
`VerifyCommand+AllFromIndex.swift:365`), but it is absent from cycle-60.

Root cause: `architecturalPendingDetail` checks
`instance-method-shape-not-supported` (line 348) **before**
`carrier-missing-required-conformance` (line 364). V1.63.A added the
`"generic parameter … could not be inferred"` pattern to the first check.
That pattern now also matches the OrderedSet `index(after:)` /
`index(before:)` monotonicity picks, so they moved from
`carrier-missing-required-conformance` (cycle-59) →
`instance-method-shape-not-supported` (cycle-60). The cycle-60 findings
doc described the cycle-59 classification without re-checking the new JSON.

## The verify-run investigation

Ran `swift-infer verify --suggestion 5F9B` (OrderedSet × `index(after:)` ×
monotonicity) and built the synthesized stub directly. The stub:

```swift
let valueA = min(firstDraw, secondDraw)        // line 28
let valueB = max(firstDraw, secondDraw)        // line 29
let resultA = OrderedSet.index(valueA)         // line 30
let resultB = OrderedSet.index(valueB)         // line 31
```

Build output — four errors, **two distinct root causes**:

```
line 28: error: global function 'min' requires that 'OrderedSet<Int>' conform to 'Comparable'
line 29: error: global function 'max' requires that 'OrderedSet<Int>' conform to 'Comparable'
line 30: error: generic parameter 'Element' could not be inferred
line 31: error: generic parameter 'Element' could not be inferred
```

**Bug A — Comparable (lines 28–29).** The monotonicity stub orders its two
trial values with global `min` / `max`, which requires the *carrier* to
conform to `Comparable`. `OrderedSet<Int>` does not. This is the genuine
"Comparable-blocked" issue — a Comparable-aware value-ordering strategy
would fix this part.

**Bug B — call shape (lines 30–31).** `OrderedSet.index(valueA)` is a
**static call on the type**, passing a generated `OrderedSet<Int>` *value*
as a positional argument. But `index(after:)` is an **instance method**
requiring a receiver and a labeled *index* argument —
`someCollection.index(after: someIndex)`. The emitter generated the wrong
call shape entirely: it treats the carrier value as the argument to
`index()`. Swift cannot infer `Element` because `OrderedSet.index(_:)` in
that form does not exist. A Comparable-aware composer does not touch this.

Both diagnostics are emitted on every build of this pick. Because the
classifier short-circuits at the first match, the JSON shows only
`instance-method-shape-not-supported` and the findings doc saw only the
Comparable half — each captured one of two co-occurring real bugs.

## Corrected breakdown — 22 pending monotonicity picks

| Block reason | Count | Picks | Composer alone closes? |
|---|---:|---|---|
| dual bug (Comparable + call-shape) | 4 | `OrderedSet`, `OrderedDictionary.Elements` × `index(after:)` / `index(before:)` | **No** — needs both fixes |
| `unsupported-carrier` (nested-OC) | 6 | `OS.SubSequence`, `OD.Values`, `OD.Elements.SubSequence` × `index(after:)` / `index(before:)` | No — needs a 3-edit carrier scaffold each, *then* both fixes |
| `internal-api-not-accessible` | 3 | `OrderedSet._maximumCapacity` / `_minimumCapacity` / `_scale` | No — dead end |
| `unsupported-carrier` (`_HashTable*`) | 7 | `_HashTable`, `_HashTable.UnsafeHandle` | No — internal API, will reclassify to internal-api |
| `unsupported-carrier` (other) | 2 | `EvenlyChunkedCollection`, `ViolationFormatter` | No — unrelated non-OC scaffolds |

## v1.64 re-scope

**A standalone "Comparable-aware monotonicity composer" closes 0 picks.**
It would compile lines 28–29 and still hard-fail on lines 30–31.

The actual work to close the 4 dual-bug picks is a monotonicity-emitter
rework, not a composer:

1. **Instance-method call shape** — emit `receiver.index(after: index)`,
   not `Carrier.index(value)`. The emitter currently mismodels instance
   methods on collection carriers.
2. **Order-by-input, not `min`/`max`-on-carrier** — the monotonicity
   property for `index(after:)` is over *indices*, not over the carrier
   value; the value-ordering step should not require carrier `Comparable`.

Estimated yield: 4 direct picks, +6 more only if bundled with three
nested-OC carrier scaffolds (`OS.SubSequence`, `OD.Values`,
`OD.Elements.SubSequence`). The remaining 12 pending monotonicity picks
are internal-API dead ends or unrelated non-OC carriers.

Given cycle-60's own diminishing-returns finding (v1.62 closed 8, v1.63
closed 1), an emitter rework for ~4 direct picks is a weak trade.
Recommended re-prioritisation for v1.64:

1. **Non-OC generic scaffolds** (17 picks) — larger surface, same 3-edit
   pattern that already worked for UnorderedView (V1.62.A) and OD.Elements
   (V1.63.A).
2. **`_minimumCapacity` / `_maximumCapacity` curated round-trip pair**
   (3 picks at the resolver; likely reclassifies to internal-api).
3. **Phase 2 accept-flow integration** — viable now (40.8% measured, 0
   measured-error).
4. **Monotonicity-emitter rework** — only if a cycle is specifically
   budgeted for it, with eyes open about the 4-pick direct yield.

## Methodology note

The cycle-60 findings doc was written against the cycle-59 classification
without diffing the regenerated cycle-60 JSON — a re-occurrence of the
"findings doc not cross-checked against the machine-generated survey"
pattern. A fixture-level guard that asserts the findings doc's
outcomeDetail counts match the committed JSON would have caught this
pre-merge, analogous to the V1.58.B curated-bindings methodology guard.

## Artifacts

- Verify run: `swift-infer verify --suggestion 5F9B --index-path fixtures/cycle27-surface/.swiftinfer/index.json`
- Stub + build errors captured from the synthesized workdir at
  `fixtures/cycle27-surface/.swiftinfer/verify-workdir/5F9B/` (gitignored
  build artifact).
- Classifier ordering: `Sources/SwiftInferCLI/VerifyCommand+AllFromIndex.swift:348` vs `:364`.
