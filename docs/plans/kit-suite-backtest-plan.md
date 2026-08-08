# Plan — backtest `scaffold-kit-suites` against real, already-fixed swift.org bugs

> **Status:** `shipped` · **As of:** 2026-08-08


**Status (2026-08-08): ALL ARMS RUN.** Arm 1 was a HIT (2026-08-02). **Arms 2 and 3, §3a and
the §4a decision closed 2026-08-08 — results in
[`docs/measurements/kit-suite-backtest-arms-2-3.md`](../measurements/kit-suite-backtest-arms-2-3.md).**
Arm 2's prediction held (MISS) and **its reasoning did not**: the conformance laws are not
structurally blind to a projection bug — the same emitted suite refutes all three mutants once
the generator's alphabet is narrowed, so the MISS is a *generator-domain* failure. Read §4a and
Arm 2 below as written, then that file.

**Status (2026-08-02): §3b measured, §3d added, Arm 1 RUN and it is a HIT.** Arms 2 and 3
and the §4a decision are still open. Written for execution in a fresh context; the
prerequisites section and the Arm 1 prediction are left as originally written, with results
appended rather than folded in, because a pre-registered prediction that gets quietly
corrected was never pre-registered.

Read this file and `docs/measurements/backtest-apple-libraries.md` before touching anything. This plan is
a *different question* asked with the *same method* as that 2026-07-18 backtest.

---

## 1. The question, and why it is not the obvious one

The obvious road test — run `swift-infer scaffold-kit-suites` over the swift.org repos at
`HEAD` and report how many laws it generates — **must not be run as the headline.** These are
mature, heavily-tested libraries. Everything will pass. "N laws, all green" is strong evidence
of *reach* and almost no evidence of *value*, and it is the same discover-only-count mistake
this repo has now corrected four times.

Worse, at `HEAD` the two explanations are indistinguishable:

| observation at `HEAD` | reading A | reading B |
|---|---|---|
| generated suites all pass | the library is correct | **the tool is blind** |

**The backtest design separates those two.** Check out the commit *before* a real fix
(`<fix>^`), generate the suites there, and run them. On a commit that demonstrably had the
bug, green cannot mean "the library is correct." That is the only version of this road test
that can produce a falsifiable result.

**But it leaves a third reading, and it is not hypothetical — it has already eaten a whole
pass of this exact work.** SwiftPropertyLaws' own git-archaeology (`Validation/FINDINGS.md`,
Pass 3) checked out `swift-collections@35349601^`, where `_Bitmap.symmetricDifference`
returns the intersection, ran the kit, and got `TreeSet<Int>` **passing every law including
all four `symmetricDifference*` ones**. Not blindness: `_Bitmap.symmetricDifference` has no
callers at that SHA. `TreeSet` dispatches through `_HashNode`'s structural traversal instead,
so Apple's own regression inputs produce the *correct* answer pre-fix. The typo was real,
fix-on-sight, and in unreachable code.

| observation at `<fix>^` | reading A | reading B | reading C |
|---|---|---|---|
| generated suites all pass | — (excluded by construction) | **the tool is blind** | **the bug is unreachable from the public API at this SHA** |

So `<fix>^` collapses three readings to two, not to one, and C is indistinguishable from B
without a separate check. **Probe reachability before generating anything** — see §3d. A
"fix touched a property test" heuristic (the mining filter in
`backtest-apple-libraries.md` §Method step 1) selects for commits like `35349601`, which
*added* a regression test to guard code no caller reaches; the heuristic is doing its job and
still handing you a void arm.

Reading C does not apply to Arm 1: the `876177db` bug is in the public `@inlinable
PersistentSet.symmetricDifference(_:)` itself, with no dispatch layer that could route around
it. Verified 2026-08-02. That is a fact about Arm 1, not a reason to skip §3d on the others.

The method is already established in `docs/measurements/backtest-apple-libraries.md` (§Method). Reuse it
verbatim; do not reinvent it — with §3d inserted between its step 2 (check out `<fix>^`) and
step 3 (discover), which is the one thing it does not have.

## 2. What is different from the 2026-07-18 backtest

That backtest asked whether **`discover`'s catalog** would surface the violated law. It ran
7 cases and scored **1 hit, 6 misses**.

This one asks whether **PropertyLawKit's conformance suites, as emitted by
`scaffold-kit-suites`, would fail** at `<fix>^`. Nothing generated those suites in July — the
command shipped 2026-08-02 (PR #42, #43). So the cases may score differently, and a case that
missed for `discover` can still hit here (or vice versa).

Keep the two straight in any write-up. They are not comparable scores.

---

## 3. Do these four things first — all cheap, all affect the result

**3a. Bisect the zip-nesting cap.** `KitSuiteEmitter.maximumZipNesting = 4` is empirical, not
derived: 8 nested `zip`s failed to type-check, 4 compiled, and nothing in between was tried.
Third-party types nest more deeply than ours, so derivation rate would be measured against an
arbitrary constant. Bisect 4→8 on `SwiftInferCore` (and ideally on swift-collections) and set
the real boundary. Record the number that failed.

> **DONE 2026-08-08 — and no number failed.** Bisected 4 → **13**; the cap now carries its
> experiment in `KitSuiteEmitter`'s own doc comment. A synthetic wide-and-deep ladder reached
> **13 nested `zip`s / 2,412 characters** with no expression over 200 ms, and `SwiftInferCore`
> emitted with the cap lifted compiled with **0 errors, 191/191 green**. **Measured cost of the
> old value: 2 suites of 241** across seven corpora, both verified to compile and pass.
> Two corrections: the constant counts `zip(` **occurrences**, not depth (the emitter writes
> *variadic* `zip`, so a 15-member flat struct is never capped at any value), and the doc's own
> justification no longer reproduces. **The real pathology is unguarded and unrelated**: one
> expression took **26,209 ms** to type-check at `zip(` count **1** — `Gen.oneOf` +
> `eraseToAny` over enum arms. Deliberately not fixed by inventing a second threshold.

**3b. Measure `Sendable` / access-level compile failures.** ~~`check<Protocol>PropertyLaws`
requires `Value: Sendable`, which a `TypeShape` cannot always establish, and a carrier may be
`private` or nested past `@testable`'s reach. On this repo it was 0 errors — **one data point,
on the codebase the emitter was written against.** Expect this to be the dominant failure mode
on third-party code.~~

> **DONE 2026-08-02, and the prediction was wrong in the interesting direction.** Five
> swift-collections targets at `899809d3`, emitted per-target and compiled in a scratch
> package (swift-collections by path, kit at the pinned 3.21.0). **Not one `Sendable` error
> appeared.** Access level mattered, but inverted: the problem was not carriers being
> *unreachable*, it was `@testable` making internal implementation details reachable and the
> emitter picking those.
>
> **Zero of the eight public collection types were reached** — not `Deque`, `OrderedSet`,
> `OrderedDictionary`, `TreeSet`, `TreeDictionary`, `BitSet`, `BitArray`, `Heap`; absent from
> both the live and the blocked list. All 12 live carriers were internal HAMT/bitmap
> scaffolding: `_Bitmap`, `_HashSlot`, `_DequeSlot`, `_HeapNode`, `_HashTable.Bucket`,
> `BitSet.Index`.
>
> **Cause, and it is one wiring line.** `TypeShapeBuilder:172` merges the primary decl with
> **same-file** extensions only; the command passed `shapes.mapValues { Set($0.inheritedTypes) }`.
> swift-collections writes `public struct BitSet {` with a bare inheritance clause and puts
> all eleven conformances in separate `BitSet+X.swift` files — the dominant Swift convention.
> `ProtocolCoverageMap.inheritedTypesIndex(from:)` already merged cross-file records; nothing
> routed it here. **Fixed**, guarded by `CrossFileConformanceReachTests`: 0 → **6 of 8**
> public types reached, `Deque` becomes the first with a live suite, compile errors 28 → 13.
>
> **Three findings that outrank the compile rate:**
>
> 1. **The emitted file does not build against the toolchain it targets.** Every suite does
>    `import SwiftInferKitEvidence` — a product of *this* repo. A consumer depending on
>    swift-collections + PropertyLawKit gets a hard failure, and the header's "NOT GUARANTEED
>    TO COMPILE" caveat names `Sendable` and access level, not a missing dependency.
> 2. **The kit already ships the generators the emitter asks users to hand-write.**
>    `PropertyLawCollections` has `Gen<Deque<Int>>`, `Gen<OrderedSet<Int>>`, `Gen<BitSet>`,
>    `Gen<Heap<Int>>`, `Gen<TreeSet<Int>>`, `Gen<TreeDictionary<Int,Int>>`,
>    `Gen<OrderedDictionary<Int,Int>>` — 7 of the 8 types the emitter reports as *"BLOCKED on
>    a generator, provide `static func gen()`"*. The emitter does not know that product
>    exists. This is the single largest lever on the blocked count and it is **not a bug fix,
>    it is a design decision** (see §4a).
> 3. **A derived generator can be silently vacuous.** For `Deque` the emitter derives
>    `Gen<Int>.int(in: -10_000...10_000).map { Deque(minimumCapacity: $0) }` — every value is
>    an *empty* deque differing only in reserved capacity, which is not part of the value. The
>    Hashable and Sequence laws would pass over a constant. It does not ship only because it
>    fails to compile (`generic parameter 'Element' could not be inferred`, the emitter writes
>    `Deque.self` with no type argument). **The compile error is the only thing preventing a
>    vacuously green suite** — that is a fragile place for the safety to live, and it is the
>    `f(x) == f(x)` failure mode wearing a generator.
>
> Remaining 13 compile errors: the `Deque` generic argument; `checkIteratorProtocolPropertyLaws`
> requiring `Sequence` while the emitter selects it for `IteratorProtocol` conformers
> (`Deque.Iterator`, `_Bitmap.Iterator`); `_Bitmap.Element` being a tuple (the kit ships
> `elementSameResult:` overloads for exactly this, unused); a missing `strideGenerator`.

**3c. `--module` ergonomics.** `scaffold-kit-suites --sources` requires `--module`. A
multi-target package (swift-collections has several) needs one invocation per target. Confirm
the per-target loop works before running it 30 times.

**3d. Probe reachability, per arm, before generating a single suite.** This is reading C from
§1, and it is a go/no-go: at `<fix>^`, call the **public** API with the fix commit's own
regression-test inputs and confirm it returns the wrong answer. If it returns the right one,
the arm is void — no amount of emitter work makes an uncalled method fail a law, and a green
run there measures nothing. Cheapest sufficient version is `git show <fix>` plus a caller
grep: if the changed symbol is `internal`/underscored, find its callers before trusting it;
if the diff lands in the public method itself, reachability is structural and you are done.
Ten minutes. Pass 3 spent a pass discovering this the expensive way.

---

## 4. The arms, in priority order

### Arm 1 — swift-collections `symmetricDifference` (`876177db`). **Predicted HIT.**

Case 2 of the July backtest, and its only hit. Pre-fix implementation was
`self.subtracting(self.intersection(other))` — i.e. `self \ other` — which is not commutative:
`{1,2,3} △ {3,4,5}` gave `{1,2}` one way and `{4,5}` the other; correct is `{1,2,4,5}` both.

**The law is not "should reach this" — it is in the kit by name.** An earlier draft of this
plan reasoned from `ProtocolCoverageMap.protocolCoverage["SetAlgebra"]`, whose four
`KnownProperty` entries (union-associative, union-commutative, union-empty-identity,
intersection-idempotent) are a **discover-side veto ledger, not a preview of what executes**.
`KitSuiteEmitter` reads that map only as a non-emptiness gate — *is this conformance worth a
suite* (`KitSuiteEmitter.swift:138`, plus the subsumption drop at `:133`) — and then emits a
call to `checkSetAlgebraPropertyLaws`. What runs is the **kit's fifteen** laws, two of which
name this bug outright:

- `SetAlgebra.symmetricDifferenceCommutativity` — `x △ y == y △ x`
- `SetAlgebra.symmetricDifferenceDefinition` — `x △ y == x.union(y).subtracting(x.intersection(y))`

`self \ other` fails both. So a HIT on the law is close to foregone, and **the arm's real
question is derivation, not reach**: does `scaffold-kit-suites`, told nothing, find
`PersistentSet` at `876177db^`, establish `Sendable`, derive a generator, and emit a suite
that compiles and runs? That is what §3b measures, and it is the only place this arm can
honestly fail. Report it that way — a hit written up as "the kit caught the bug" claims credit
for a law that was already sitting in the catalog with the right name on it.

**And the arm is uncontaminated, which is worth stating rather than leaving to inference.**
The kit's four `symmetricDifference*` laws were added in response to a *different* bug —
`35349601`, `TreeSet`, 2025-12, the Pass 3 case in §1. Different type, different SHA, three
years later, and Pass 3's sweep of 1,873 swift-collections commits never surfaced `876177db`
at all. The laws were not fitted to this witness.

> **Blocking decision, found while checking the above — see `docs/measurements/protocol-coverage-law-drift.md`.**
> Reading the kit to write this section turned up that **`checkSetAlgebraPropertyLaws` does
> not run union associativity** (no such law exists anywhere in the kit) while
> `ProtocolCoverageMap` vetoes the suggestion as though it did, with
> `AssumedKitCoverageTests:224` pinning the suppression as correct. The generated suite
> inherits the hole, because it just calls the kit. The full sweep — **13 false `(key, law)`
> claims across 17 keys**, and why `KitCoverageDriftTests` passes green through all of them —
> is in that doc. **What matters for this arm:** the `SetAlgebra` fix is a fork (add the law
> to the kit, or drop the map entry and let `discover` propose it), the two have different
> corpus deltas, and the choice changes what Arm 1's emitted suite covers. Decide before the
> arm runs.

> ## RUN 2026-08-02 — **HIT.** The refutation unit is complete.
>
> Same generated suite, same generator, one-file difference between the two runs.
>
> | | `876177db^` (`d6b1e6c7`, buggy) | `876177db` (fixed) |
> |---|---|---|
> | `SetAlgebra.symmetricDifferenceCommutativity` | **FAIL, trial 1** | pass |
> | `SetAlgebra.symmetricDifferenceDefinition` | **FAIL, trial 1** | pass |
> | the other 13 `SetAlgebra` laws | pass | pass |
> | **summary** | **2 violations of 15** | **0 of 15** |
>
> ```
> x = [7, 5, 4], y = [8, 0, 5]
>   x.symmetricDifference(y) = [7, 4],  y.symmetricDifference(x) = [8, 0]
>
> x = [7, 1, 6], y = [8, 2, 0, 6]
>   x.symmetricDifference(y) = [7, 1],  (x ∪ y) \ (x ∩ y) = [8, 7, 2, 0, 1]
> ```
>
> **Method.** `PersistentCollections` + `_CollectionsUtilities` vendored verbatim from a
> detached worktree at `d6b1e6c7`, because SwiftPropertyLaws pulls swift-collections in for
> `PropertyLawCollections` and two copies of one package cannot share a graph. The second run
> swaps **one file** — `PersistentSet+SetAlgebra symmetricDifference.swift`, whose three-line
> body is the entire fix — and changes nothing else: same sources, same generator, same suite.
>
> ### What running it taught that reading it could not
>
> **1. The cross-file conformance fix was load-bearing for this arm.** The emission reported
> `PersistentSet — 11 law(s), BLOCKED on a generator` and named `checkSetAlgebraPropertyLaws`.
> Before that fix (same day, PR #48) `PersistentSet` declared `SetAlgebra` in a sibling
> extension file and was invisible: the arm would have emitted nothing, and **nothing is
> indistinguishable from reading B, "the tool is blind"** — the §1 problem, arriving from a
> direction §1 did not anticipate.
>
> **2. §3b's `Sendable` prediction was right about the mechanism and wrong about the era.**
> Zero `Sendable` errors on swift-collections HEAD. On the 2022 tree, `PersistentSet` predates
> the annotation entirely and `checkSetAlgebraPropertyLaws` requires `Value: Sendable`. The
> constraint bites on OLD code, which is exactly the population a backtest visits and a
> HEAD survey never does. Neither run alone would have found this.
>
> **3. Two edits were needed to run the emitted call, and both are defects.**
> `PersistentSet.self` → `PersistentSet<Int>.self` (the emitter writes the bare generic name,
> which does not typecheck — the same defect as `Deque` in §3b), and the generator, which is
> what BLOCKED means.
>
> ### Accommodations, all disclosed
>
> The 2022 tree does not build under Swift 6.3.3. Three changes, none touching
> `symmetricDifference`:
>
> - **SE-0370 back-port removed** from `_CollectionsUtilities` — its
>   `Slice.initialize(fromContentsOf:)` is ambiguous with the stdlib's, which has shipped
>   SE-0370 since. Deleting the back-port restores the implementation it stood in for. Four
>   modules from the SUT.
> - **Swift 5 language mode** on the vendored targets. The upstream manifest is
>   `swift-tools-version:5.3`, so v5 is the mode this code shipped under; Swift 6 strict
>   concurrency rejects `_Node+Storage._emptySingleton`. Setting the mode is faithful, editing
>   2022 sources to satisfy a 2026 checker would not be.
> - **`PersistentSet: @unchecked Sendable`** — what HEAD annotates it as anyway, for the same
>   CHAMP copy-on-write reason.
>
> ### The honest bound
>
> **The generator is hand-written, not derived.** The tool proposed the law, named the suite,
> and told the user exactly what was missing; a human supplied the domain — deliberately
> narrow (`0...8`, count `0...6`) so operands OVERLAP, since `symmetricDifference` on
> near-disjoint sets approximates `union`, which *is* commutative. That is CLAUDE.md's
> collision-alphabet rule applied by hand, and it is the difference between this arm and a
> claim that the toolchain caught the bug unaided. **It did not.** What it did was reach the
> carrier, name the law, name the suite, and state the one thing a human had to add — and then
> the law failed at trial 1 and passed after the fix. That is the unit of value §5 asks for,
> and it is smaller than "the loop found it".
>
> Harness in the session scratchpad, not committed. It should become a gated fixture on the
> `fixtures/cycle27-surface/` precedent if Arm 2 reuses it.

### 4a. Open decision — should the emitter know about `PropertyLawCollections`?

Surfaced by §3b and **not decided.** 7 of the 8 public swift-collections types the emitter
reports as *"BLOCKED on a generator"* already have hand-written generators in the kit's
opt-in `PropertyLawCollections` product. Emitting `Gen<Deque<Int>>.someRecipe()` instead of a
derived `Deque(minimumCapacity:)` would take the blocked count down sharply AND fix finding 3
(the vacuous generator) in the same move.

Against it, and the reason this is a decision rather than a task:

- It makes `scaffold-kit-suites` **carrier-name-aware** — a curated table of
  `TreeSet -> PropertyLawCollections recipe`. That is the `curatedVerbs` posture applied to
  types, and the repo's standing line is that *the kit needs a type, `discover` works from
  shape* (`FunctionalIdentityTemplate` gate 1).
- It adds a dependency the user may not want: `PropertyLawCollections` exists precisely to
  keep swift-collections off the main `PropertyLawKit` line.
- It only helps carriers the kit already curated, which is the opposite of the transfer
  property the `[reference]` backlog is measured by — *success is carriers reached OUTSIDE
  the catalog*.

The honest middle is probably to **emit the recipe as a comment** on the blocked entry —
"`PropertyLawCollections` ships `Gen<Deque<Int>>`; add that product and use it" — which costs
no dependency and no name-keying in the live path. Decide before Arm 1.

> **DECIDED 2026-08-08 — the honest middle, taken as written.**
> `KitSuiteEmitter.propertyLawCollectionsRecipe` is read by `blockedBlock` and nothing else, so
> the live path never references the opt-in product; seven recipes, guarded by
> `KitSuiteCollectionsRecipeTests` (including a freshness test re-derived against the sibling
> kit checkout, and a control watched failing). **`BitArray` is deliberately absent** — the kit
> ships no generator for it, and six of seven siblings being answered is exactly when a reader
> assumes the seventh was too.
>
> **The lever was mostly spent before it was pulled.** §3b's *"single largest lever on the
> blocked count"* is now worth **one row** — `TreeDictionary`, 5 laws — because `749df12` and
> `b99019e` have since made seven of the eight public types derive live. Measured across five
> swift-collections modules.
>
> **And the objection was already conceded elsewhere.** `StrategistDispatchEmitter.curatedOCRecipes`
> keys on carrier names today and hand-writes generators for three of these seven. Not the same
> concession — there the recipe must be *live* — but recorded rather than left to inference.

### Arm 2 — the projection bugs. **Predicted MISS, and publish it.**

`fixtures/equatable-signal/README.md` measured that **3 of 3 real swift-collections projection
bugs pass 4 of 4 Equatable laws**: `OrderedSet` order, `BitArray` padding, `Deque` head
rotation. A projecting `==` is still a valid equivalence relation, so the conformance laws are
*structurally* blind to it.

`BitArray.toggleAll()` (`e01391e5`) is Case 6 of the July backtest — a miss there, which also
exposed a tool-side false positive.

**This arm is expected to go green on buggy code, and that is the finding.** It is the honest
counterweight to "877 laws generated": it states precisely what this codegen does not buy.
Do not soften it, and do not bury it under the Arm 1 hit.

Positive half: the model law (`left == right ⟺ model(left) == model(right)`) catches all three
at trial ≤3, and `ModelLawTemplate` / `SequenceViewModelLawTemplate` already ship. So the
finding converts into a recommendation — *generate model laws alongside conformance suites* —
rather than a shrug.

> ## RUN 2026-08-08 — **MISS, as predicted. The reasoning was wrong, and that is the finding.**
>
> swift-collections `c8080d05`, three modules vendored, one file mutated per arm. **26 emitted
> tests, verdict-for-verdict identical between correct code and all three mutants.** Not one law
> moved. Full record: `docs/measurements/kit-suite-backtest-arms-2-3.md`.
>
> **But the laws are not blind.** Same kit calls, same laws, same mutants, **only the generator
> narrowed** — and `Hashable.equalityConsistency`, a Strict law the emitted file already runs,
> refutes **all three**: OrderedSet at 73–102 trials, BitArray at 2–12, Deque in 5 of 6 runs at
> 10–314. Every one of these bugs needs two values to **collide**, and a 20,001-wide alphabet
> does not collide. So the MISS is a **generator-domain** failure, not a structural one — a
> different problem with a different owner, and it is this repo's.
>
> The model law still earns its recommendation (all three at trial **1**), but it is now the
> second recommendation. The first is *narrow the alphabet where a law is collision-dependent*.
>
> **Two things running it taught that reading could not.** The **baseline is not green**: 6 of
> 26 tests fail on *correct* code, all six from two derived generators that construct
> invariant-violating values — `BitSet.Counted(_bits:count:)` draws its count independently of
> its bits. That is §3b's finding 3 arriving from the other side, no longer saved by a compile
> error, and it reports three swift-collections `SetAlgebra` laws as violated when they are not.
> And the `Deque` witness needs a **wrapped** buffer, not merely a narrow alphabet — three
> hand-built witnesses were non-witnesses for structural reasons before one worked.

### Arm 3 — derivation and compile rate across the corpora. **Diagnostic only.**

For each package: carriers covered, laws covered, % derivable, % of emitted files that
compile, % of tests that pass. Report all five. This is the reach measurement; it is context,
never the headline, and it must not be reported without Arms 1 and 2.

`swift/stdlib/public/core` can only yield derivability — validating compilation there means
building the toolchain. Say so rather than quietly omitting it.

> **RUN 2026-08-08 — 12 corpora, 366 carriers, 141 derivable (38%), 591 of 1,168 laws live
> (50%).** Table in `docs/measurements/kit-suite-backtest-arms-2-3.md` §5.
> **Derivation on third-party code is roughly half what it is here**: §7's 74% was this repo,
> `SwiftInferCLI` scores 86% and the stdlib 18%. **Compile-and-pass was measured on 2 of 12**
> (SwiftInferCore 191/191, vendored swift-collections 20/26) and the other **10 are named, not
> dropped** — compiling a third-party emitted suite means vendoring it with `@testable` reach,
> which is the whole Arm 2 apparatus. The stdlib is derivability-only as predicted. Also:
> **`Heap` is reached by neither list**, the only public collection type that is not.

---

## 5. Scoring rules

- **Unscored. Do not freeze an answer key.** "Which laws does this library owe" is not
  freezable the way `fixtures/swiftorg-study/q2-answer-key.json` was, and forcing one is the
  premature ceremony already rejected on the leaderboard fixture.
- **Report in refutation units.** A suite that fails at `<fix>^` and passes at `<fix>` is the
  unit of value. Counts of generated laws are reach.
- **Every number carries its SHA** — the fix commit, the parent, and this repo's commit.
- **A tool may not grade its own homework.** Anything found that the July backtest's cases did
  not name is recorded separately and unscored.

## 6. Traps, all previously hit

- **Corpora live in `~/GitHub_projects/`**, not `~/xcode_projects/`: `swift`,
  `swift-collections`, `swift-foundation`, `swift-nio`, `swift-syntax`,
  `swift-package-manager`. `SwiftProjectLint` and the sibling kit are in `~/xcode_projects/`.
- **`swift package clean` before trusting a build.** Stale SwiftPM state produced
  `Internal Error: DecodingError.dataCorrupted … Corrupted JSON` repeatedly on 2026-08-02
  (root cause: the repo directory was moved mid-build). A from-scratch build cleared it.
- **`.swiftinfer/kit-evidence.json` now exists in this repo** and changes `discover`'s
  coverage headline from "no kit evidence" to the `contradicted` state. Never `git add` it.
- **zsh aborts a command line when a glob matches nothing** — `rm -rf foo-*` runs *nothing*,
  not "the rest". Use `find … -exec`.
- **Old commits may not build under the current toolchain.** The July backtest's workaround is
  to extract the pre-fix logic into a minimal verify-ready fixture with a generatable carrier
  (a `CaseIterable` enum is cleanest). Reuse it; do not fight the build.

## 7. State at handoff (2026-08-02, `main` @ `229c445`)

Seven PRs merged today: #38–#44.

| | |
|---|---:|
| `scaffold-kit-suites` live | 262 carriers / **877 laws** |
| blocked on a hand-written `gen()` | 91 carriers / 282 laws |
| generated `@Test` functions | **341** |
| generator derivation | **74%** of carriers |
| verified on `SwiftInferCore` | compiles 0 errors, **209/209 green** |
| suite | 4,747 tests green, `swiftlint --strict` clean |

Commands:

```sh
swift build -c release
.build/release/swift-infer scaffold-kit-suites --target <T> --output <path>
.build/release/swift-infer scaffold-kit-suites --sources <dir> --module <M> --output <path>
make test-fast          # ~26s, includes the lint gate
```

Two constants that encode judgement calls, both documented in `KitSuiteEmitter`:
`maximumZipNesting = 4` (see 3a) and the ±10_000 numeric bound (matches the verify path;
cannot find overflow bugs at the extremes, deliberately).

## 8. What would make this road test worthless

Writing it up as "we generated N laws across six swift.org repos." That is reach with a large
denominator, it will be all-green, and it answers nothing. If Arms 1 and 2 cannot be run, run
neither and say so — a diagnostic-only run should be labelled diagnostic, not published as a
road test.
