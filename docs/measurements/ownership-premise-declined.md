# Do `consuming` and `borrowing` carry purity evidence?

> **Status:** `measured` · **As of:** 2026-08-17

Re-derivable at any time — `OwnershipPremiseCensusMeasuredTests` *is* the harness,
and `make batch2` runs it.

Phase 0.7 of `docs/plans/declaration-claims-plan.md`. **Measured: the premise is
false and the population is zero, so both rows close as
*measured-premise-false*.** And the probe turned up a separate, larger defect the
rows were only gesturing at.

---

## The question

The plan proposes two Family C edges resting on parameter ownership:

- **`consuming` → in-place mutation unobservable**, scored by *"count of
  `consuming`-parameter mutations currently refuting purity"*.
- **`borrowing` → non-escape evidence**, scored by *"overlap between
  inferred-`borrowing` params and functions refuted on capture"*.

Both scorers presuppose that something in the purity oracle reacts to a
parameter. Neither was checked before being written down, and this line of work has
had **three** premises come back backwards — always in the permissive direction.

---

## Provenance

| | |
|---|---|
| corpus | this repo's `Sources/`, the item 29 census's own `corpus` static — shared, not recomputed |
| SEI pin | `3ea25f2` (`Package.swift:122`) |
| harness | `Tests/SwiftInferCoreTests/OwnershipPremiseCensusMeasuredTests.swift` |
| probes | 10 synthetic shapes, 3 of them controls that must refute |

---

## 1 · The premise is false — no parameter shape refutes

| probe | verdict |
|---|---|
| `inout`, mutated | **`.pure`** |
| `inout`, read only | **`.pure`** |
| `consuming` | **`.pure`** |
| `consuming`, mutated (via local copy) | **`.pure`** |
| `borrowing` | **`.pure`** |
| control: plain value parameter | `.pure` |
| control: marker in body (`print`) | `.refuted` |
| control: force unwrap | `.refuted` |

**The controls are the point.** *"Nothing refutes"* is indistinguishable from *"the
oracle is not running"* without them, and that is the shape a zero measured with a
blind instrument takes.

This matches what `verdict(for:)` reads, which is worth stating because the list is
short and closed: body presence, `async`, body markers, body totality, default
arguments, then the `throws` clause. **No clause examines a parameter.**
`mutatesCapturedState` exists but is reachable only through `isPure(_ closure:)`.

---

## 2 · And the population is zero, which decides it independently

| | count |
|---|---|
| parameters declared `inout` | **52** (over 47 functions) |
| parameters declared `consuming` | **0** |
| parameters declared `borrowing` | **0** |

**Even had the premise held, there is nothing to score.** A scorer over zero
declarations is unbuildable, and this is a stronger decline than the premise
failure alone: the two facts are independent, so closing the rows does not rest on
either one being right.

The 52 `inout` parameters are a real population and are **all in `.pure`-eligible
functions as far as the oracle is concerned** — `inout` mutation is invisible to it.
Whether that is a soundness hole is a separate question this census does not ask: an
`inout` parameter is the caller's storage, so mutating it is not obviously an
*impurity* so much as a second return value.

---

## 3 · The finding this probe was not looking for

**Sharper and narrower than expected**, and it is not about ownership at all:

| shape | verdict | refuted by |
|---|---|---|
| `S.total += value` — static member | `.refuted` | `ReducerPurityAnalyzer`'s *"write to static or `Self` state"* |
| `counter += value` — **file-scope `var`** | **`.pure`** | **nothing** |
| `{ counter += 1 }` — closure capture | refuted | `refuteIfCaptured` |

**The same write is refuted inside a closure and admitted inside a function.** That
makes this an asymmetry between two code paths in one type, not a limit of the
analysis — `PurityInferrer`'s own doc says of closures *"what refutes purity is the
body **mutating** what it captured — then it is not a function of its inputs, and no
extraction saves it."* The reasoning transfers to functions verbatim; the code does
not.

**Why this is bigger than the rows it replaces.** It needs no ownership modifier to
occur, so its population is every function in the corpus rather than the zero that
declare `consuming`. It is also a **false `.pure`**, which is the direction SEI's own
doc calls the most dangerous place to land wrongly, since a generated property test
runs the function in-process.

`moduleStateMutationIsNotRefuted` pins both halves. It fails the day a module-state
refuter lands for functions, and the static assertion fails if
`ReducerPurityAnalyzer`'s static clause ever regresses — a soundness loss well beyond
this census.

**Not measured here: the base rate.** How many functions in `Sources/` actually
mutate a file-scope `var` is the number that decides whether this is worth building,
and it is a different query from the one this harness runs. **File it, do not build
on it.** The `.pure` population is 2,396; if the base rate is zero this is item 40's
result — a latent unsoundness with no victims — and if it is not, it belongs ahead of
everything left in the plan.

---

## The verdict

**Both ownership rows: DECLINED, *measured-premise-false*.** Two independent
grounds, either sufficient:

1. no clause in `verdict(for:)` examines a parameter, so there is no mechanism for
   ownership to inform;
2. this corpus declares **zero** `consuming` and **zero** `borrowing` parameters, so
   there is nothing to measure against.

This is the second time in this line of work a Family C row has been declined for a
premise that reads plausibly and measures false — item 33 was the first. **The
transferable practice is the cheap one: probe the premise before scoping the
build.** Both rows cost an afternoon to close and would have cost a phase to
discover.

### What would reopen it

- **A corpus that uses ownership modifiers.** Zero here is a fact about this
  repository, not about Swift. A noncopyable-heavy codebase would give the rows a
  population — but they would still need a mechanism, so ground 1 stands alone.
- **A parameter-aware refuter landing in SEI.** Then ownership could inform it, and
  `parameterShapesDoNotRefute` fails on the day it does.
- **The `inout` question being asked properly.** 52 parameters is not nothing, and
  "is `inout` mutation an impurity or a second return value" is a real design
  question this census deliberately leaves open.
