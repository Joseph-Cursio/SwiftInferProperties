# What would a precise delegation gate recover? — declined, and the exhibit that motivated it was wrong

> **Status:** `measured` · **As of:** 2026-09-23

`open-threads.md` row 72. The kit declines a delegating initializer when **any** initializer on its type
asserts (`InitializerBasedDerivation.isDeclined`), because matching `self.init(…)` to one overload would
take overload resolution. `kit-scaffold-conversion.md` §3.2 measured the cost on Euclid (17 laws
withdrawn to remove one trap) and said resolving the delegation to its actual target "would keep `Path`
and `LineSegment` live". This census asks how often a precise gate would give a type a generator it
does not have today.

## The answer

**DECLINE.** Across the 20 manifest corpora, a precise gate gives **10 types** a generator. All 10 are
in `swift-collections`, and they are **3 types, not 10**: `BigSubstring`, `BigSubstring.UnicodeScalarView`
and `SortedSet`. The other 7 are their iterators and views, which become buildable because their parent
does. The bar written before the run was ≥ 10 types across ≥ 3 corpora with none holding more than
half. This is 10 across 1.

| over 23 distinct scan directories | |
|---|---:|
| type shapes | 4,682 |
| gate fires (struct with a delegating init and an asserting one) | **355** |
| — of which `swift-syntax` | 300 |
| gate fires wrongly (a declined init's target is clean) | **16** |
| — of which the init does not delegate at all | 4 |
| initializers the label match cannot resolve | 773 |
| **types GAINING a generator** | **10** (3 roots + 7 downstream) |
| types losing one (instrument check) | 0 |

**Why it is so small:** the gate is per *initializer*, not per type. A declined delegating initializer
only costs a generator when it was the type's last candidate, and 13 of the 16 wrongly-gated types still
fail for another reason (failable, throwing, capacity-only, unresolvable parameters) or already derive
through a different initializer.

**Even the 3 are weak.** `SortedSet` sits behind the `UnstableSortedCollections` trait, which is
commented out of the default traits: row 74's code-not-in-the-build case. `BigSubstring` and its view
live in `_RopeModule`, an underscored module.

## The Euclid exhibit was wrong, by its own source

The positive control was pre-registered as "Euclid must show `Path` and `LineSegment` as wrongly gated".
Half of that prediction was false, and the census is right:

- **`Path` is correctly gated.** `init(_:)` → `init(_:plane:)` → `self.init(unchecked:plane:)`, and two
  overloads share those labels: `init(unchecked points:plane:)` and `init(unchecked storage:plane:)`.
  **Both assert** (`Path.swift:676` and `:683`). `kit-scaffold-conversion.md` itself noted `Path` "did not
  trap here, not cannot trap".
- **`LineSegment` is wrongly gated on one initializer, and it changes nothing.** The clean one is
  `init?(undirected:_:)` → `init?(start:end:)`, and it is **failable**, so it is declined anyway. The
  initializer it derived through before the gate, `init(undirected segment:)`, calls
  `self.init(unchecked:_:)`, which asserts `start != end`.
- **On Euclid a precise gate recovers 0 generators.** So §3.2's "would keep `Path` and `LineSegment`
  live" is false for both, and most of what §3.2 called collateral were correct withdrawals.

## How it was measured

`DelegationGateCensusMeasuredTests` (opt-in, `SWIFT_INFER_DELEGATION_CENSUS=<scan dir>`, batch 8). It
restates none of the gate. The real `GeneratorResolver` runs twice over one scan: on the shapes as built,
and on shapes where a delegating initializer's `delegatesToSelf` is cleared when its target is **clean**.
A target is resolved by argument labels, allowing omitted defaulted parameters, following `self.init`
chains. Whether a target asserts is read off the shape, which the kit's own
`InitializerPreconditionDetector` computed. Anything ambiguous stays gated, so GAINED is a **floor**.

- ⚠ **773 initializers are unresolvable by labels, and on Euclid every one was checked**: they are real
  overloads that share labels and differ by type (`Color.init(_:)` ×4, `Rotation.init(_:)` ×4, …). A
  type-aware resolver could recover more than 10. It would be overload resolution, which the kit declined
  to build; this census does not say what it would buy, only that the label-level answer is 10 types in
  one corpus. Most of the 773 are `swift-syntax` (605), whose node initializers delegate everywhere.
- ⚠ **The kit's `delegatesToSelf` over-detects**: it fires on ANY `.init` member access, so `.init(…)`
  on another type inside a body reads as delegation. 4 types here; the census clears them in the
  counterfactual and they gain nothing.
- One clean verdict hand-checked: `BigSubstring.init(_ elements:)` delegates to `init(_:in:)`, which
  rounds its bounds rather than asserting. The asserting overload is `init(_unchecked:in:)`.
- ⚠ The scan read each corpus's **working tree**. `swift-collections` was at `c0c4b3bf` (a local branch),
  not a pinned revision. GRDB's scan directory appears twice in the manifest (as `sources` and `target`)
  and is counted once. `swift-collections/Sources/Collections` resolves 0 shapes (umbrella module), and
  the census's own non-empty guard fired on it, as designed.

## What would reopen it

A corpus where a precise gate gains ≥ 3 root types that are in the build and outside an underscored
module. Or a type-aware version of this census, if overload resolution ever becomes available cheaply.
