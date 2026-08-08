# Kit-suite backtest — §3a, §4a, Arm 2 and Arm 3

> **Status:** `measured` · **As of:** 2026-08-08

Closes the open remainder of [`docs/plans/kit-suite-backtest-plan.md`](../plans/kit-suite-backtest-plan.md),
whose Arm 1 ran 2026-08-02 and was a HIT. Read that plan first — it carries the method, the
pre-registered predictions, and the three-readings problem this design exists to solve.

**SHAs, per §5's rule that every number carries one.** Subject: `swift-collections@c8080d05`.
Observer: `SwiftInferProperties@fa57c45` plus the working-tree changes this pass made (the §3a
constant and the §4a table). Kit: `SwiftPropertyLaws@91e09a2`.

**Unscored**, per §5. No answer key was frozen; "which laws does this library owe" is not
freezable.

---

## 1. Headline

**Arm 2's prediction was right and its reasoning was wrong, which is the finding.**

The plan predicted a MISS on the three projection bugs because *"a projecting `==` is still a
valid equivalence relation, so the conformance laws are structurally blind to it."* The MISS
reproduced exactly — 26 emitted tests, verdict-for-verdict identical between correct code and
three mutants. But the laws are **not** blind: the same emitted suite, with nothing changed but
the generator's alphabet, refutes **all three**. `Hashable.equalityConsistency` — a Strict law
the emitted file already runs — catches every one.

So the MISS is a **generator-domain** failure, not a structural one. That matters because the
two have different remedies and only one of them is the tool's to fix.

| | plan's reading | measured |
|---|---|---|
| cause of the MISS | the laws cannot express the bug | the generator cannot reach a witness |
| remedy | emit model laws alongside conformance suites | **narrow the alphabet** — and model laws still help |
| whose problem | the kit's law catalogue | **this repo's derived generators** |

The model-law recommendation survives (it refutes all three at trial 1, against 12–314 for the
narrowed conformance law), but it is now the *second* recommendation, not the first.

---

## 2. Arm 2 — the projection bugs

### 2.1 Method

Same as Arm 1: vendor the sources, emit, run, then swap one file and re-run the **same** suite.
`OrderedCollections`, `BitCollections`, `DequeModule` (plus `InternalCollectionsUtilities` and
`ContainersPreview`) vendored verbatim from `c8080d05`.

Two accommodations, both disclosed:

- **Modules renamed `A2*`.** SwiftPropertyLaws pulls swift-collections in for
  `PropertyLawCollections`, and two copies of one package cannot share a graph — the same
  collision Arm 1 hit. Only `import` lines were rewritten (plus one module-qualified
  `InternalCollectionsUtilities._UnsafeBitSet`); type names and bodies are verbatim.
- **Build settings lifted from the upstream manifest** — the availability macros and six
  experimental features. Without them the vendored tree does not compile at all
  (`'@_lifetime' attribute is only valid when experimental feature Lifetimes is enabled`).
  Unlike Arm 1, **no source-level accommodation was needed**: HEAD builds under Swift 6.3.3.

The three mutations, one file each, `==` body only:

| arm | file | mutation |
|---|---|---|
| OrderedSet | `OrderedSet+Equatable.swift` | `left._elements == right._elements` → `Set(left._elements) == Set(right._elements)`. Not a strawman — this is `isEqualSet(to:)`'s semantics, which the real type ships one method away. |
| BitArray | `BitArray+Equatable.swift` | the `guard left._count == right._count` line deleted, so padding bits above the logical count decide equality. The shipped body is correct only while every mutating path keeps them zeroed. |
| Deque | `Deque+Equatable.swift` | `elementsEqual` → comparison in **physical slot order**, the canonical ring-buffer defect. |

### 2.2 The baseline is not green, and that is finding #1

Before any mutation, on **correct** swift-collections HEAD: **20 of 26 emitted tests pass, 6
fail.** All six trace to two derived generators, not to the library.

| failing test | generator | why it fails on correct code |
|---|---|---|
| `BitSet.Counted` — Codable, Sequence, SetAlgebra | `zip(…map { BitSet(words: $0) }, Gen<Int>.int(in: -10_000...10_000)).map { BitSet.Counted(_bits: $0.0, count: $0.1) }` | `count` is drawn **independently of the bits**, so the generator constructs values whose count contradicts their contents. `SetAlgebra.unionIdempotence` fails at trial 1. |
| `OrderedDictionary`, `.Elements`, `.Values` — Hashable | `zip(Gen<Int>.int(in: -10_000...10_000), Gen<Bool>.bool()).map { OrderedDictionary(minimumCapacity: $0.0, persistent: $0.1) }` | every value is an **empty** dictionary differing only in reserved capacity and a flag — and the capacity can be negative. |

Both are the same defect class: **the strategist picked an initializer whose parameters are not
independent**, and `@testable` is what made it reachable — `BitSet.Counted(_bits:count:)` is
internal. This is §3b's finding 3 (*"a derived generator can be silently vacuous"*) arriving
from the other side. There it was saved by a compile error, and the note said *"that is a
fragile place for the safety to live"*. It was: the same class now ships live and produces
**false refutations on correct code**.

A user reading this file is told three of swift-collections' `SetAlgebra` laws are violated.
They are not.

### 2.3 The MISS

The three mutated carriers are all in the passing 20 at baseline, so the arm is clean.

| carrier | emitted suites | correct code | mutated |
|---|---|---|---|
| `OrderedSet` | Hashable, Sequence | pass | **pass** |
| `OrderedSet.UnorderedView` | Hashable, SetAlgebra | pass | **pass** |
| `BitArray` | Codable, Hashable, LosslessStringConvertible, Sequence | pass | **pass** |
| `Deque` | Hashable, Sequence | pass | **pass** |

`diff` over all 26 tests: **identical**. Not one law changed verdict. **MISS, as predicted —
publish it.**

### 2.4 …but the laws are not blind

Same kit calls, same laws, same mutants. Only the generator changed.

| arm | emitted generator | narrowed generator | law that fired |
|---|---|---|---|
| OrderedSet | `int(in: -10_000...10_000).array(of: 0...8)` → **no refutation** | `int(in: 0...3).array(of: 0...4)` → **refuted, 73–102 trials** | `Hashable.equalityConsistency` |
| BitArray | `Gen<UInt>.uint().array(of: 0...8)` → **no refutation** | short mostly-false bit patterns → **refuted, 2–12 trials** | `Hashable.equalityConsistency` |
| Deque | `int(in: -10_000...10_000).array(of: 0...8)` → **no refutation** | tiny alphabet × two construction paths → **refuted in 5 of 6 runs, 10–314 trials** | `Hashable.equalityConsistency` |

The law is the correct one-directional form — `!(a == b) || a.hashValue == b.hashValue` — so
these are real catches, not the `⟺` false positive. All three mutants make values *wrongly
equal*, and all three hashes are order- or count-sensitive.

Every one of these bugs needs two values to **collide**: to be permutations of each other, to
share storage while differing in logical count, or to hold the same elements at different head
offsets. Independently drawn values from a 20,001-wide alphabet do not collide. This is
CLAUDE.md's standing rule — *"any property whose failure needs two generated values to collide
is invisible to a generator drawing from a realistic domain"* — measured on a third party
rather than on this repo's own `Decisions.merge`.

**The Deque arm's flakiness is the sharpest version of the point.** 5 of 6 runs refute, 1 does
not. The witness needs a **wrapped** buffer (`head + count > capacity`), and neither
construction path reaches one reliably: `init` leaves the head at 0, `prepend` moves it to 1.
Building a witness by hand took three attempts — rotating the deque `count` times returns the
head to 0 whenever the capacity is a multiple of the count, and a non-wrapping deque's physical
order **is** its logical order, so it is not a witness at all. Both failed attempts are recorded
in the harness rather than deleted.

### 2.5 The model law, on the same subjects

`(a == b) == a.elementsEqual(b)` — what `SequenceViewModelLawTemplate` emits from source alone.
Against the same three mutants on the **real** types: **all three refuted at trial 1**, given a
witness pair. `fixtures/equatable-signal` measured this on reproductions; this is the same
result on the shipping carriers.

So the recommendation stands and its order changes:

1. **Narrow the alphabet where a law is collision-dependent.** This is the one that turns a MISS
   into a HIT on a law the tool already emits.
2. **Emit model laws alongside conformance suites.** Cheaper witnesses (trial 1 vs up to 314)
   and it does not depend on a lucky draw.

---

## 3. §3a — the zip-nesting bisect

**Bisected 4 → 13. Nothing failed anywhere, at any depth tried.**

The plan asked for this because 4 was empirical: 8 failed once, 4 compiled, nothing between was
tried, so derivation rate was being measured against an arbitrary constant.

- **Synthetic ladders**, so the boundary is found by construction rather than by whatever a
  corpus happens to contain. Wide-and-deep (each rung wraps the previous and adds four
  mixed-type members): **13 nested `zip(`s, 2,412 characters, compiles, no expression over
  200 ms** under `-warn-long-expression-type-checking`. A flat ladder confirmed a
  **15-argument variadic `zip`** is fine.
- **The real corpus.** `SwiftInferCore` emitted with the cap lifted: **0 compile errors,
  191/191 tests green**, deepest expression 5.

**Measured cost of the old value: 2 emitted suites out of 241** across seven corpora — both in
`SwiftInferCore`, both at nesting 5, both verified to compile and pass. The same near-no-op
shape `ProtocolCoverageAudit` measured for the coverage veto.

Two corrections fall out:

- **The constant counts `zip(` occurrences, not nesting depth.** The emitter writes *variadic*
  `zip(a, b, c, …)`; occurrences accumulate through composed sub-generators. A 15-member flat
  struct has occurrence count 1 and is never capped, at any value.
- **The doc's own justification no longer reproduces.** It cites 8 nested zips and 1,935
  characters failing on `SwiftInferCore`; today that corpus's deepest expression is 5, and a
  synthetic 13 at 2,412 characters compiles.

### 3.1 The pathology is real and this guard cannot see it

One expression in the same run took **26,209 ms to type-check**. Its `zip(` count is **1**. It is
`StateSurface`, an enum, emitted as `Gen.oneOf(…)` with `.eraseToAny()` over heterogeneous arms.
No value of `maximumZipNesting` gates it.

Not fixed by inventing a second threshold — one measurement is a data point, not a curve, and a
guard fitted to a single witness is how the first arbitrary constant happened. Filed as an open
item. *Caveat: measured while a second build was running on the same machine; the margin is two
orders of magnitude but it has not been re-measured in isolation.*

---

## 4. §4a — decided: comment, do not depend

**Decision: emit the kit's recipe as a comment on the blocked entry.** The plan's "honest
middle", taken as written. `KitSuiteEmitter.propertyLawCollectionsRecipe` is read by
`blockedBlock` and nothing else; the live path never sees it, so no dependency is added and no
name-keying enters the path that produces running code. Seven recipes, guarded by
`KitSuiteCollectionsRecipeTests` — including a freshness test that re-derives against the
sibling kit checkout when present, and a control that was watched failing.

**But §3b's "single largest lever on the blocked count" is now worth exactly one row.** Measured
across five swift-collections modules: **1 blocked carrier gets a recipe** (`TreeDictionary`,
5 laws). §3b measured 7-of-8 when all eight public types were blocked; `749df12` and `b99019e`
have since made seven of them derive live. The lever was real when it was measured and was
mostly spent by the time it was pulled.

Two things worth keeping from the decision:

- **`BitArray` is deliberately absent** from the table. The kit ships no generator for it, so it
  keeps the plain `.gen()` hint — six of seven siblings being answered is exactly the condition
  under which a reader assumes the seventh was too.
- **The prior art cuts the other way.** `StrategistDispatchEmitter.curatedOCRecipes` already
  keys on carrier names and hand-writes generators for `OrderedSet<Int>`,
  `OrderedDictionary<Int, Int>` and `Deque<Int>` — three of these seven. That concession is not
  the same one: there the recipe must be *live* because the emitted stub has to run. The
  duplication is recorded, not fixed.

---

## 5. Arm 3 — derivation and compile rate (diagnostic only)

Per the plan: context, never a headline, and not to be read without Arms 1 and 2.

| corpus | carriers | derivable | % | laws | live | % |
|---|---:|---:|---:|---:|---:|---:|
| swift-argument-parser | 15 | 12 | 80% | 58 | 46 | 79% |
| swift-collections · BitCollections | 4 | 4 | 100% | 36 | 36 | 100% |
| swift-collections · DequeModule | 2 | 1 | 50% | 9 | 5 | 55% |
| swift-collections · HashTreeCollections | 16 | 6 | 37% | 66 | 31 | 46% |
| swift-collections · HeapModule | 1 | 1 | 100% | 4 | 4 | 100% |
| swift-collections · OrderedCollections | 8 | 5 | 62% | 39 | 30 | 76% |
| swift-foundation · FoundationEssentials | 109 | 33 | 30% | 299 | 126 | 42% |
| swift-nio · NIOCore | 33 | 11 | 33% | 124 | 47 | 37% |
| swift-syntax · SwiftSyntax | 21 | 12 | 57% | 77 | 50 | 64% |
| **swift stdlib** · public/core | 105 | 19 | 18% | 293 | 98 | 33% |
| *self* · SwiftInferCLI | 36 | 31 | 86% | 109 | 94 | 86% |
| *self* · SwiftInferTemplates | 16 | 6 | 37% | 54 | 24 | 44% |
| **TOTAL** | **366** | **141** | **38%** | **1168** | **591** | **50%** |

**Derivation on third-party code is roughly half what it is on the codebase the emitter was
written against.** §7's handoff figure was 74%; that was this repo. `SwiftInferCLI` scores 86%
and the stdlib scores 18%.

**Compile and pass rate was measured on 2 of 12 corpora, and the other 10 were not compiled.**
Saying so is the point — compiling a third-party corpus's emitted suite means vendoring it with
`@testable` reach, which is the whole Arm 2 apparatus.

| corpus | compiles | tests | pass |
|---|---|---:|---|
| self · SwiftInferCore | **0 errors** | 191 | **191/191** |
| swift-collections (3 modules, vendored) | **0 errors** | 26 | **20/26** — the 6 failures are §2.2's generator defects, not library bugs |

Not compiled, and named rather than dropped: swift-argument-parser, swift-foundation, swift-nio,
swift-syntax, the stdlib, `HashTreeCollections`, `HeapModule`, `SwiftInferCLI`,
`SwiftInferTemplates`. The stdlib **can only ever** yield derivability here — validating
compilation there means building the toolchain.

**`Heap` is absent entirely.** `HeapModule` reports 1 carrier, and it is `_HeapNode`; the public
`Heap` appears in neither the live nor the blocked list. Every other public collection type is
reached. Not diagnosed.

---

## 6. What this pass found that the plan did not ask for

Recorded unscored, per §5's *a tool may not grade its own homework*.

1. **Invariant-violating generators produce false refutations on correct code** (§2.2). Two
   witnesses, six failing tests. The strategist picks an initializer whose parameters are not
   independent — `BitSet.Counted(_bits:count:)` — or one that varies nothing that is part of the
   value — `OrderedDictionary(minimumCapacity:persistent:)`, which can also draw a *negative*
   capacity. `@testable` is what makes the internal ones reachable.
2. **`Gen.oneOf` + `eraseToAny` costs 26 s of type-checking at `zip(` count 1** (§3.1), which no
   value of `maximumZipNesting` gates.
3. **`Heap` is never reached** (§5).
4. **A collision-dependent law needs a *wrapped* witness, not merely a narrow alphabet** (§2.4).
   Narrowing the alphabet was necessary and not sufficient for `Deque`; three hand-built witness
   attempts produced non-witnesses for structural reasons.

## 7. Still open

- **Arms 2 and 3 are now run; Arm 1 was run 2026-08-02.** The plan's remaining unrun item is
  none — but §2.2's generator defects are unfixed, and they are worth more than anything left in
  it.
- **The harness is not committed.** Arm 1's note said it *"should become a gated fixture on the
  `fixtures/cycle27-surface/` precedent if Arm 2 reuses it"*. Arm 2 did reuse it, and it is still
  in a scratch directory — committing it means vendoring swift-collections, so the decision is
  not automatic. §2.1 and §2.4 carry enough to rebuild it.
- **The 26 s type-check has not been re-measured in isolation** (§3.1).
