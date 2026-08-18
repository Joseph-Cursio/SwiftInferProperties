# What do the backtest's blind spots cost this corpus?

> **Status:** `measured` · **As of:** 2026-08-17

Re-derivable at any time — `BlindSpotBaseRateCensusMeasuredTests` *is* the harness,
and `make batch2` runs it.

The base rates `docs/measurements/purity-backtest.md` named and filed rather than
guessed. **Measured: bucket 1 is zero and reconciled; bucket 2 is TWO, hand-checked,
and one of them is a live defect in this repository.**

---

## The two blind spots

The backtest scored 0 hits of 3 against public fix commits and named the gaps:

| blind spot | oracle's answer | decidable from a parse? |
|---|---|---|
| instance write on a reference type — `self.x = y` in a `class` | `.pure` | **yes** |
| hash-order rendering — a `Set` or dictionary rendered into a returned value | `.pure` | **no — lower bound only** |

A gap with no instances is item 40's shape: latent, not a defect. A gap with instances
is a **false `.pure`** per row.

---

## Provenance

| | |
|---|---|
| corpus | this repo's `Sources/`, the item 29 census's file enumeration — shared, so denominators agree |
| SEI pin | `3ea25f2` |
| harness | `Tests/SwiftInferCoreTests/BlindSpotBaseRateCensusMeasuredTests.swift` (+`Support`) |
| population | the **2,396 `.pure`** of 2,740 |

---

## Bucket 1 — instance writes: zero, and the zero needed reconciling

| receiver | `.pure` declarations writing `self.x` |
|---|---|
| `class` — shared reference state, **the defect** | **0** |
| `struct` / `enum` — a copy, and `mutating` says so | 0 |
| `actor` — shared but isolated | 0 |
| `extension` of a type declared elsewhere | 0 |
| **self-writes found in ANY declaration, `.pure` or not** | **0** |

**That last row is why this figure is publishable.** `grep` finds **1,226** explicit
`self.x =` lines in `Sources/`, so a detector reporting zero *anywhere* would be
broken — and the module-state census published a zero from exactly such a detector
before it was caught. The two readings had to be separated.

**Reconciled by sampling:** of the first 400 of those lines, **380 are inside an
`init`**. An initialiser writing `self` is not an impurity, and
`InitializerDeclSyntax` is not a `FunctionDeclSyntax`, so they are out of scope **by
construction** rather than by a filter that could drift. The remainder are computed
property setters and closures, also out of scope — the latter because
`refuteIfCaptured` already refutes them.

So: **methods in this package do not write `self` explicitly.** The blind spot the
backtest found on Harmonize's builder is real and has no instances here.

**One stated limitation.** Only an explicit `self.` receiver is counted. A bare
`stored = value` also writes instance state, but bare names are ambiguous against
locals without scope resolution, so counting them would inflate the bucket. This is a
lower bound — and note `.swiftlint.yml` enables `redundant_self`, which pushes this
codebase's writes toward the bare form, so the true figure could be higher than zero
even though the *method* population appears empty.

---

## Bucket 2 — hash-order rendering: TWO, and one is a live defect

| | |
|---|---|
| `.pure` declarations rendering a same-file `Set`/dictionary | **2** (lower bound) |

Both in `Sources/SwiftInferTestLifter/PartitionAggregator.swift`:

```
finalizeTwoClass -> winnerByPredicate
finalizeNClass   -> nClassBucketsByKey
```

### `finalizeTwoClass` is nondeterministic and judged `.pure`

```swift
private func finalizeTwoClass() -> [PartitionCandidate] {
    var winnerByPredicate: [String: RankedCandidate] = [:]
    …
    return winnerByPredicate.values.map(\.candidate)
}
```

`winnerByPredicate` is a dictionary. **`.values` yields its elements in hash-seed
order**, so the returned array's order differs run to run. `SoundPurity.verdict(for:)`
answers **`.pure`**.

**This is the same bug class three times over.** SwiftLint fixed it twice
(`006bb2a8`, `0c095204`) — the backtest's own cases. This repository fixed it once and
wrote the lesson down in `CrossFileVisitorBase.orderedSources`: *"its order derives
from the process's hash seed and differs on every launch… the idempotency family's
upward effect inference described one violation as resting on a 5-hop chain on one run
and a 4-hop chain on the next."* **And it is live in `Sources/` right now**, in a
function the purity oracle vouches for.

### It does NOT escape — measured 2026-08-17, so this is a smell and not a bug

The open question was whether the order reaches a user-visible artifact. It does not,
and the reason is one hop up:

```swift
func finalize() -> [PartitionCandidate] {
    let twoClass = finalizeTwoClass()
    let nClass = finalizeNClass()
    return (twoClass + nClass).sorted(by: Self.sortCandidates)
}
```

**Which makes the whole question comparator totality, because Swift's sort is not
stable.** `sorted(by:)` over a *partial* order leaves tied elements in input order, so
a tie plus a hash-ordered input is nondeterministic output *even though a sort ran*.
Containment rests entirely on no two candidates comparing equal.

They cannot, and the key types are what guarantee it:

| tier | separates | why a tie is impossible |
|---|---|---|
| 1 · `predicateName` | anything with distinct names | — |
| 2 · two-class before N-class | a two-class from an N-class candidate | — |
| 3 · `markerSet?.name` | two N-class candidates | `NClassPartitionKey` **is** `(predicateName, markerSetName)` — two distinct rows cannot share both |
| — | two two-class candidates | `winnerByPredicate` is keyed by `predicateName` alone, so there is at most one |

**Asserted by permutation, not by that argument.** `PartitionOrderContainmentTests`
sorts every rotation and the reversal of a population built to nearly collide, and
requires one sequence — and carries a **control that fails against a comparator with
its last tier removed**, without which the property would pass against anything. The
reasoning in the table is the kind that has been wrong three times in this line of
work; the property fails the day a tier is dropped or `NClassPartitionKey` gains a
field, which no reading catches.

`sortCandidates` moved from `private` to internal so the property could reach it.

**So: the oracle is still wrong** — `finalizeTwoClass` genuinely is nondeterministic at
its own boundary and is judged `.pure` — **but the defect is contained and no artifact
is affected.** A smell, not a bug. The row stays in the census because the *oracle's*
error is the census's subject; what changed is the consequence.

**The count is a lower bound, twice over.** A name declared in another file is
invisible; a name whose type is inferred rather than annotated is invisible. Both are
the same class of limit the unrecognised-callee census reports for free-shape callees.

---

## The verdict

**Bucket 1: latent, zero instances, reconciled.** Item 40's shape. The reconciliation
is the part that makes it worth reading — 1,226 self-writes exist and every one is
correctly out of scope, which is a stronger statement than an unexplained zero.

**Bucket 2: non-zero, and the first blind spot measured in this line of work that has
live instances.** Two rows, both hand-checked, one of them returning
hash-seed-ordered output from a function the oracle calls pure.

**That makes the hash-order gap the highest-value fix the backtest surfaced**, and it
is marker-shaped rather than analysis-shaped: rendering `.values`, `.keys` or a `Set`
into a returned value is a syntactic pattern, in the same family as the
`FileHandle` / `Process` / `Pipe` addition SEI made at `3ea25f2` — three names,
measured first, cheap.

### What would change this

- **Resolving bucket 2's downstream question.** If every caller sorts, the two rows are
  a smell rather than a defect and the fix's priority drops.
- **Counting bare-name writes in bucket 1.** `redundant_self` is enabled here, so the
  explicit-receiver requirement may be hiding the population rather than measuring it
  as empty. That needs scope resolution, not a wider regex.
- **A cross-file type index.** Both buckets are within-file lower bounds for the same
  reason the callee censuses are: name-keying without resolution. Item 38 again.
