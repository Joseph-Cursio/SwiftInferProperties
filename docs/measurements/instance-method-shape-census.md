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

---

## 7. The fix, scoped — and the finding is bigger than §4

§4 said the recipe is derived for the parameter type. That is true and it is only half of it.
**Fixing it alone would still not work**, and the reason is a key-space mismatch that makes the
whole V1.69 ordered-collection path unreachable.

### 7.1 The carrier rule, and the precedent already in the file

`strategistBundle` chooses the generator carrier as:

```swift
roundTripDomainCarrier(entry: entry) ?? entry.carrierTypeName ?? entry.typeName
```

`carrierTypeName` is the **parameter** `T`; `typeName` is the **call-site owner**. For
`OrderedSet.index(before:)` that is `Int` and `OrderedSet` respectively, and monotonicity takes
the first.

⚠ **The rule that fixes this is already written down, one function up, and applied to a different
template.** `roundTripDomainCarrier` anchors `round-trip` at the parameter and guards it with
`!entry.isInstanceMethod`, documented as:

> *instance-method forward — the value IS the receiver, so the declaring type is already right*

**That is exactly the missing clause for monotonicity.** The codebase knows the rule; it is
applied to one template and not the other.

### 7.2 And fixing that alone still fails, because the key space does not meet production

With the carrier corrected, `recipe.carrierTypeName` becomes **`OrderedSet`** — and everything
downstream is keyed on **`OrderedSet<Int>`**:

| keyed on a fully-specialised spelling | entries |
|---|---|
| `monotonicityInstanceCarriers` | 5 |
| curated OC `GeneratorRecipe`s | `OrderedSet<Int>`, `OrderedSet<Int>.SubSequence`, `OrderedDictionary<Int, Int>`, `.Elements`, `.Values`, `.Elements.SubSequence`, `Deque<Int>`, … |

**Measured against production output: of 34 distinct carriers in the `swift-collections`
monotonicity rows, ZERO contain `<`.** Discovery records the declaring type's name, unspecialised,
always.

✅ **So the V1.69 ordered-collection monotonicity path — carrier list, curated recipes, and the
composer they feed — has never fired on a real row.** Its emitter tests pass because they
construct `Inputs(carrier: "OrderedSet<Int>", …)` directly, supplying the one spelling production
cannot produce. **A shipped feature, green tests, unreachable in production.**

⚠ **This is why §3's spelling normalisation measured ZERO and was right to revert**: it is the
*second* half of a two-part fix and inert without the first. Reverting it was correct; it should
come back **with** §7.1, not before.

### 7.3 What the fix requires, and why it is not made here

1. **Anchor instance-method monotonicity at the receiver** — the `roundTripDomainCarrier` clause,
   inverted, for this template.
2. **Make the OC key space meet production's spelling.** Either normalise both sides — recipes
   keyed unspecialised, each choosing its own element type — or specialise the carrier, which
   needs an element type **discovery does not record**.

**(2) is a design decision, not a rename**, and it is the reason this is scoped rather than
shipped. Doing half of it is what §3 already measured at zero.

⚠ **`Deque<Int>` HAS a curated recipe and is NOT in `monotonicityInstanceCarriers`**, so even a
perfect key-space fix leaves the list narrower than the recipes it draws on. The 19 rows §3 could
not reach (`Deque`, `BitArray`, `UniqueDeque`, `RigidDeque`, `UniqueArray`, …) need that list
widened as well as re-keyed — behind the empty-collection guard §5 put in for exactly that moment.

### 7.4 What would refute this

- **A production discovery row whose carrier is spelled with generic arguments**, which would mean
  the key space is reachable after all and something else blocks it.
- **A monotonicity row anywhere that took the OC composer path**, which would falsify *never fired
  on a real row* outright.
