# `instance-method-shape-not-supported` — the largest blocker, diagnosed

> **Status:** `measured` · **As of:** 2026-08-30

**31 of 64 `monotonicity` rows on `swift-collections` @ `899809d3` (48%)** — the single largest
blocker on that template, and untouched since it was first labelled. Diagnosed here, **not
fixed**, and two candidate fixes were built and measured before being rejected.

## 1. It is not a decline. It is a build failure, classified afterwards

`architecturalPendingDetail` reads the **compiler's output** and matches patterns. So every one
of these 31 rows emitted a stub, compiled it, and failed. Verified on one row end to end:

```
error: instance member 'index' cannot be used on type 'OrderedSet<<<hole>>>';
       did you mean to use a value of this type instead?
error: generic parameter 'Element' could not be inferred
```

The emitted line is `{ OrderedSet.index(before: $0) }(valueA)` — **a static call on an instance
method.**

⚠ **The label covers five distinct compiler errors**, including `generic parameter … could not be
inferred` and — separately — `compile command failed due to signal`, a compiler **crash**. A
crash is not an instance-method shape. That is unexamined here and is a second finding: *a
compile-error histogram is not a defect list*, applied to the classifier rather than the errors.

## 2. The subjects are the template's LEGITIMATE population

| carrier | rows | | carrier | rows |
|---|---:|---|---|---:|
| `OrderedSet` | 4 | | `RigidArray` | 2 |
| `UniqueDeque` | 3 | | `_HashTable.UnsafeHandle` | 2 |
| `UniqueArray` | 3 | | `OrderedSet.SubSequence` | 2 |
| `BitArray` | 2 | | `OrderedDictionary.Elements` | 2 |
| `Deque` | 2 | | `UnsafeBufferPointer` | 1 |
| `RigidDeque` | 2 | | `BigString._Chunk` | 1 |
| `OrderedDictionary.Elements.SubSequence` | 2 | | `_HashSlot` | 1 |
| `OrderedDictionary.Values` | 2 | | | |

Almost all are `index(after:)` / `index(before:)`. **`monotonicity-subject-census.md` identified
the `Collection` index family as the genuinely monotonic rows — 50 of 339, the only 15% of that
template that is actually about order. This blocker is aimed squarely at them.** The template's
false laws execute; its true ones do not compile.

## 3. Candidate fix 1 — the carrier spelling. Real mismatch, MEASURED ZERO, reverted

`monotonicityInstanceCarriers` is a curated set of **five fully-specialised spellings**
(`OrderedSet<Int>`, `OrderedDictionary<Int, Int>.Elements`, …). A discovery row's carrier is
spelled **unspecialised** — `OrderedSet`, `OrderedDictionary.Elements`. **12 of the 31 rows are
carriers that list already names**, missed purely on generic-argument spelling, and all five
entries are unreachable as written.

That looked like the `Swift.String` leaf-recognition defect again, and it is a real
inconsistency. **It is not what blocks these rows.** Normalisation was built and A/B'd on the same
subject and command:

| | before | after |
|---|---:|---:|
| `instance-method-shape-not-supported` | 31 | **31** |
| rows moved off it | — | **0** |

**Reverted.** Twenty lines of code whose premise is refuted is not worth shipping against a
measured zero.

⚠ **The mismatch is still there and is recorded rather than fixed**, because fixing it in
isolation makes the list *look* right while changing nothing — and `MonotonicityOCEmitterTests`
requires each entry to resolve a curated recipe, which the bare spelling does not. **A future fix
must move the recipe, not the list.**

## 4. The real cause: the recipe is derived for the PARAMETER, not the receiver

The emitted stub says it outright:

```swift
let defaultGenerator: Generator<Int, some SendableSequenceType> = Gen<Int>.int()
```

`recipe.carrierTypeName` is **`Int`** — the parameter type of `index(before:)`. The instance-path
dispatch asks `monotonicityInstanceCarriers.contains(recipe.carrierTypeName)`, i.e. *is `Int` an
ordered-collection carrier*. **It can never be true for these rows, at any spelling.** The
receiver — the thing that must be generated — is never what the recipe is built for, and nothing
on this path routes on `entry.isInstanceMethod`.

⚠ **`receiverCallExpression` exists and does gate on `entry.isInstanceMethod`** — but
`liftedOrMonotonicityCalls` never calls it. So monotonicity misses the receiver shape at call
resolution as well as at derivation. **Two independent places, one omission.**

**A fix therefore spans resolution and derivation**: for an instance-method subject, derive the
recipe for the receiver type and emit the receiver shape. That is a real change and is **not made
here** — the row asked what the blocker is.

## 5. What WAS kept — the empty-collection guard

The OC composer builds its index domain as `receiver.startIndex ... (receiver.endIndex - 1)`.
On an empty receiver that is `0 ... -1`: an invalid `ClosedRange`, which **traps**. There was no
runtime guard — only a comment reasoning that *"the curated OC recipes always produce non-empty
(4-element) collections, so no empty-collection guard [is] needed."*

**True while the carrier list was five curated entries, and it expires the moment that widens** —
which is the first thing any fix in §4 will do. A `guard !receiver.isEmpty else { continue }` now
stands in front of it. **It moves no rows today**, and it is kept because it is a soundness fix
rather than a reach one: trading a compile error for a trap is the worse direction, measured
repeatedly this cycle.

## 6. What would refute this

- **A row where `recipe.carrierTypeName` IS the receiver type**, which would mean §4 describes
  only some of the 31.
- **Any of the 31 failing for a reason other than the static-call shape** — only one was verified
  end to end; the other 30 are classified by the same label, and §1 shows that label is broad.
- **The `compile command failed due to signal` arm firing on this corpus**, which would mean some
  of the 31 are compiler crashes wearing an instance-method label.
