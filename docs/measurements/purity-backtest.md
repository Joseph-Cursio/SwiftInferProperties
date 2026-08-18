# Does the purity oracle flag real historical purity bugs?

> **Status:** `measured` · **As of:** 2026-08-17

Re-derivable at any time — `PurityBacktestMeasuredTests` *is* the harness, and
`make batch2` runs it.

Phase 0.6 of `docs/plans/declaration-claims-plan.md`. **Measured: 0 HITS of 3, and
0 false alarms.** The oracle sees neither of the two bug classes a public history
actually produced.

---

## Why this arm is different from every other measurement here

Everything else in `docs/measurements/` grades the tool with the tool: this corpus,
this binary, the instrument CLAUDE.md calls contaminable — *a tool may not grade its
own homework*. This one cannot be: **the oracle is a public fix commit that predates
these tools**, cannot be influenced by them, and survives churn.

**It is the only arm producing a number defensible outside this repository**, and
that is why the plan put it early rather than last.

---

## Method

1. **Mine** third-party history for fix commits whose bug *was* a purity failure.
2. **Take the declaration at `<fix>^` and at `<fix>`**, and ask
   `SoundPurity.verdict(for:)` about both.
3. Read it as **HIT** (pre refuted, post pure), **MISS** (pre `.pure`), or **FALSE
   ALARM** (post refuted).

**A hit needs both halves.** Seeing the bug is worth nothing if the tool also objects
to the fix — that is a rule that dislikes a shape, not an oracle that detects a
defect.

**Backtest at `<fix>^`, never `HEAD`.** These libraries are correct at `HEAD`, so an
all-green run there cannot be told from a blind tool.

### What the mine actually yielded, including what it did not

Searched `SwiftLint` (9,977 commits), `ViewInspector` (1,316), `swift-argument-parser`
(610), `SwiftPlantUML` (134), `Harmonize` (119), `Hummingbird`, `swift-aws-lambda-runtime`.

**Marker-removal mining produced almost nothing usable.** Commits that net-remove
`Date()` or `arc4random` from SwiftLint are, with two exceptions, *"Automated
deployment to GitHub Pages"* — generated documentation, not source. That is worth
recording: the obvious query for this arm is mostly noise, and a reader repeating it
should expect to discard ~90% of hits by hand.

**Thread-safety fixes were rejected as wrong-shaped.** `make regex cache thread-safe`
and its siblings add a lock; the function is impure before *and* after, so the fix
moves no purity verdict and the case cannot distinguish a working oracle from a
blind one.

---

## Provenance

| | |
|---|---|
| SEI pin | `3ea25f2` (`Package.swift:122`) |
| harness | `Tests/SwiftInferCoreTests/PurityBacktestMeasuredTests.swift` |
| cases | 3, frozen as source fixtures with their commit SHAs |

**The sources are frozen in the harness rather than read from sibling checkouts.**
That keeps the suite runnable on a machine with none of these repos cloned, and makes
each case a fixture the oracle is re-run against on every commit rather than a number
in a document. The cost is that a fixture can drift from the commit it quotes; the
SHAs are recorded, and the extraction is:

```sh
git -C ../SwiftLint show 006bb2a85^:Source/SwiftLintFramework/Rules/RuleConfigurations/ImplicitReturnConfiguration.swift
git -C ../SwiftLint show 0c0952046^:Source/SwiftLintFramework/Rules/RuleConfigurations/AttributesConfiguration.swift
git -C ../Harmonize show a8abcfa^:Sources/Harmonize/Core/ScopeBuilder/HarmonizeScopeBuilder.swift
```

---

## The results

| case | bug | pre-fix | post-fix | |
|---|---|---|---|---|
| SwiftLint `006bb2a8` — `consoleDescription` | a `Set`'s iteration order rendered into a `String` | `.pure` | `.pure` | **MISS** |
| SwiftLint `0c095204` — attributes description | two `Set`s interpolated into a cache key | `.pure` | `.pure` | **MISS** |
| Harmonize `a8abcfa` — scope builder | methods mutated shared reference state | `.pure` | `.pure` | **MISS** |

**0 HITS of 3. 0 false alarms.**

The zero false alarms is not nothing — the tool never objects to corrected code,
which is the worse failure of the two, since a miss is silence and an objection is
advice to undo a fix. But it is also the reading a tool that answers `.pure` to
everything would produce, so it carries weight only alongside the controls.

---

## The two blind spots, which are different from each other

### 1 · Hash-order nondeterminism (cases 1 and 2)

```swift
let includedKinds = self.includedKinds.map { $0.rawValue }   // includedKinds is a Set
return "…, included: [\(includedKinds.joined(separator: ", "))]"
```

`includedKinds` is a `Set`, so its iteration order derives from the process's hash
seed and the rendered string differs run to run. The fix inserts `.sorted()`.

The marker sets contain `random`, `randomElement`, `shuffled`, `arc4random`,
`drand48` — **but iterating an unordered collection is not a marker**, and no
totality or `throws` clause fires either. The oracle has no way to see it.

**This repository has paid for exactly this bug class already.**
`CrossFileVisitorBase.orderedSources` documents it in its own words: *"`fileCache.values`
yields a dictionary's values, so its order derives from the process's hash seed and
differs on every launch… the idempotency family's upward effect inference described
one violation as resting on a 5-hop chain on one run and a 4-hop chain on the next."*
The toolchain hit it, fixed it, wrote it down — and its purity oracle still cannot
detect it in someone else's code.

### 2 · Instance state mutation on a reference type (case 3)

```swift
func excluding(_ excludes: [String]) -> HarmonizeScope {
    self.exclusions = excludes + exclusions
    return self
}
```

`HarmonizeScopeBuilder` is an `internal class`, so this mutates state every holder of
the reference can see — two scopes built from one builder collided on a cache key.

**Verified not to be a harness artifact.** The verdict is identical whether the
method is wrapped in a `struct`, a `class`, or nothing at all. What decides it is the
spelling of the receiver:

| write | verdict | refuted by |
|---|---|---|
| `Self.y = x` — static | `.refuted` | `ReducerPurityAnalyzer` |
| `self.y = x` — instance, **class** | **`.pure`** | **nothing** |
| `self.y = x` — instance, `mutating` struct | `.pure` | defensible — value semantics, and `mutating` says so |
| file-scope `var` | `.pure` | nothing, but base rate 0 here |

**`ReducerPurityAnalyzer`'s clause covers *static or `Self`* state — literally the
capitalised spelling.** Instance writes are outside it.

**The class row is the defect; the struct row is not.** A `mutating` struct method
mutates a copy and Swift makes the caller opt in. A non-`mutating` method writing
`self` on a class mutates shared state with nothing in the signature to say so —
which is precisely why an oracle is wanted, and precisely what the Harmonize bug was.

`stateMutationBoundary` pins both rows and fails if either moves.

---

## What this costs the module-state census

`docs/measurements/module-state-base-rate.md` measured file-scope `var` mutation at a
base rate of **zero** and closed it as a latent unsoundness in item 40's shape. **That
reading was correct and narrower than the gap.** File-scope `var`s are absent from
this corpus; **classes with mutable instance state are not rare anywhere**, and the
same oracle admits both.

So the state-mutation blind spot has two populations, and only the empty one has been
counted. **The instance-write base rate is unmeasured. Filed, not built on** — it is
a different query, and folding it in here would repeat the error that census was
careful to avoid.

---

## The verdict

**The oracle does not detect the purity bugs this history actually produced.** Three
cases, two independent bug classes, zero hits.

That is a defensible statement about the tool because nothing in it depends on this
repository's corpus or on a measurement the tool influenced.

**What it does not say.** Three cases is not a rate — it is an existence proof about
two bug classes, with no claim about how common either is in the wild. The mine that
produced them was shallow and message-driven, and a deeper one keyed on diff shape
rather than commit prose would likely find more of both.

**What follows.** Neither blind spot needs a new verdict state or a dataflow analysis:

- **Hash-order** is a marker-shaped gap. `Set`/`Dictionary` iteration feeding a
  returned value is a syntactic pattern, in the same family as the `FileHandle` /
  `Process` / `Pipe` addition SEI made in `3ea25f2` — three names, measured, cheap.
- **Instance writes on a class** is a one-clause extension of a refuter that already
  exists, and `ReducerPurityAnalyzer` is already the thing that would carry it. The
  hard part is not detection; it is deciding whether a `mutating` struct method should
  share the verdict, and the table above argues it should not.

### What would reverse this

- **A deeper mine finding cases the oracle does hit.** Three MISSes is an existence
  proof of two gaps, not a claim that the oracle hits nothing.
- **The struct/class distinction turning out to matter less than argued.** If a
  consumer treats `mutating` as impure anyway, the boundary this document draws is the
  wrong one and case 3 stops being a clean defect.
- **A false alarm appearing.** Zero of three is the strongest thing this arm reports;
  a single post-fix refutation would make the oracle's silence look less like caution
  and more like luck.
