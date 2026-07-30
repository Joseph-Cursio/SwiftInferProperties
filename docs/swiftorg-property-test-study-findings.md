# Findings — the swift.org property-style-test study

Companion to `swiftorg-property-test-study-scope.md`, which is the plan. This is the
record. **Every number here carries the corpus SHA it was measured at**; a count without
one is not a measurement (scope §3).

**Status: Q5 answered (§1.5). Q1 answered (§1.1). Q2/Q3/Q4 not started.**

---

## 0. Setup (2026-07-30)

Three items, and all three produced findings before any question was asked — which is the
argument for doing setup as measurement rather than as plumbing.

### 0.1 The corpus was re-pinned, and the old pin was contaminated by us

`~/GitHub_projects/swift` was on the local branch `fix-vacuous-sortedness-check` — two
commits ahead of upstream, **one of which edits a file inside the corpus**
(`test/stdlib/sort_integers.swift`, the `swiftlang/swift#91083` fix). Any count taken
against it would have been a count against a tree we had modified.

Re-pinned by fast-forwarding to upstream `main`, which moved **1,894 commits**. The PR
branch is preserved locally and on the fork; the PR is unaffected.

| repo | pinned SHA | date |
|---|---|---|
| `swift` | `408632e59834c1a5ee4166ff61dd2c8b0585a1c5` | 2026-07-30 |
| `swift-foundation` | `96d4094` | 2026-07-16 |
| `swift-syntax` | `1b5cd99f` | 2026-07-17 |

### 0.2 Population sizes at the pin

Produced by `scripts/swiftorg_sample.py`, over `test/`, `validation-test/`, `stdlib/`:

| population | sites | `.swift` | `.gyb` |
|---|---:|---:|---:|
| `check-battery` | **246** | 134 | 112 |
| `loops` | **698** | 694 | 4 |
| `roundtrip` | **833** | 809 | 24 |
| `lit-checknot` | **3,386** | 3,385 | 1 |

### 0.3 Three findings that change Q1 before Q1 starts

**(a) 46% of `check-battery` sites are `.gyb` templates, not Swift.** 112 of 246. A
`checkEquatable` inside a gyb template expands to N instantiations at build time, so
"how many property-style tests exist" is genuinely ambiguous: counting the template
undercounts what executes, counting expansions requires running gyb. **Q1 must decide this
explicitly**, and the sampler records `ext` per site so the adjudication can split it.

**(b) The battery's own implementation is not a test site.** `StdlibUnittest` defines
`checkEquatable` and calls it internally from `checkHashable`; 25 such matches on `swift`
inflated the population ~9% before `IMPLEMENTATION_PATHS` excluded them. A definition is
not a test.

**(c) `lit-checknot` is 3,386 and mostly not property verification.** The scope doc listed
"9 files", which was `test/stdlib/*.swift` only. Across the whole compiler test suite,
`CHECK-NOT` is overwhelmingly *diagnostic* assertion — "this error should not appear" —
not the print-on-failure property idiom `sort_integers.swift` uses. **This population needs
a much tighter definition or it should be dropped**; as measured it would dominate every
total while contributing almost nothing.

### 0.4 The classifier hazard fired three times during setup

Q1's guardrail is *"a structural classifier proved unreliable — it read `result ==
Decimal(12340)` as a round-trip; automate second."* That hazard recurred three times while
merely **preparing** to study it:

| attempted signal | what it actually was |
|---|---|
| swift-collections "associativity ×92" | 54 `associated`, 25 `associatedtype` — zero the law |
| swift-protobuf "idempotence ×315" | 214 `idempotencyLevel` — protobuf's `.proto` method option |
| `lit-checknot` ×3,386 | compiler diagnostics, not property verification |

Three witnesses in one sitting, none of them subtle in hindsight, all of them confident at
the time. This is why `scripts/swiftorg_sample.py` **locates and stops** — it does not
classify. Adjudication is by hand, into §1 below.

---

## 1. Pass 1 — adjudication

**Not started.** Schema below; one row per sampled site. Sample manifests are regenerated
with the seed and SHA recorded in each table header, so any row can be traced back.

### Adjudication schema

| column | values | notes |
|---|---|---|
| `site` | `file:line` | from the sample manifest |
| `ext` | `swift` / `gyb` | see §0.3(a) — gyb rows are templates, not instances |
| `property-style?` | yes / no / borderline | **the Q1 judgement** |
| `law` | free text | the property in one sentence, or `—` |
| `template` | template name / `none` | **Q2 recall** — which of ours would state it |
| `verdict` | `ours-covers` / `gap-with-witness` / `their-bug` / `declined` | see below |
| `generator` | idiom name | **Q5** — `.random(in:)`, LCG, instance-list, exhaustive, none |
| `notes` | free text | why, especially for borderline and `their-bug` |

`verdict` values, with `declined` being the one that is not a miss (scope §Q3d):

- **`ours-covers`** — a template states this law; counts toward recall.
- **`gap-with-witness`** — no template states it, and here is a real function that wants it.
- **`their-bug`** — the test does not check what it claims (the `sort_integers` class).
  Record separately; an upstream defect is a finding about the corpus, not the catalog.
- **`declined`** — we understand it and stand aside because PropertyLawKit runs it
  (operator conformances). Counts toward *toolchain coverage*, not *discover recall*.

### 1.1 Q1 ANSWERED — the definition, and it is a scope plus an overload split

Two adjudication passes settled it, and both came from reading sites rather than counting
them.

#### Finding 1 — the population must be SCOPED to the stdlib test directories

The `loops` sample was 30 of 30 compiler-diagnostic tests:
`moveonly_addresschecker_diagnostics.swift`, `noimplicitcopy.swift`,
`transfernonsendable_inout_sending_params.swift`. There, `for _ in 0..<1024 { }` exercises
the borrow checker and `for _ in 0..<1 { }` runs **once** — neither is a quantifier.

Distribution confirms it: **537 of 698 loop sites are in `test/SILOptimizer`**, and 521 of
all trip counts are the single `0..<1024` idiom. Only `validation-test/stdlib` (20 sites, 17
in files that also generate) and `test/stdlib` (16 / 6) hold the real population.

The general rule, which applies to every population: **the compiler test suite dwarfs the
stdlib test suite and its idioms collide with property-test idioms.** Any population defined
by a Swift-level idiom alone is dominated by compiler-behaviour tests.

| population | naive (whole tree) | scoped (`test/stdlib` + `validation-test/stdlib`) | noise |
|---|---:|---:|---:|
| `check-battery` | 246 | **218** | 12% |
| `roundtrip` | 833 | **205** | 76% |
| `loops` | 698 | **36** | **95%** |
| `lit-checknot` | 3,386 | **17** | **100%** |

#### Finding 2 — `checkEquatable` has two overloads and only one is a battery

Sample site #27 is `checkEquatable(true, Set<Int>(), Set<Int>())`. That is not the axiom
battery — `StdlibUnittest` ships a *second* overload,
`checkEquatable<T: Equatable>(_ expectedEqual: Bool, _ lhs: T, _ rhs: T)`, which asserts one
fact about two named values. An example test wearing a battery's name.

Split across the naive population: **213 axiom-battery (86%), 31 example-assertion (12%),
2 comments (1%)**.

#### The definition

> A **property-style test** is a site that executes a *universally quantified* law over a
> domain it supplies. The domain may be degenerate — a 2-element instance list is a property
> test with a broken generator, and Q5 measures exactly that. What excludes a site is
> asserting a *fact about named values* (the example overload), or not quantifying at all
> (a loop that runs once, a diagnostic `CHECK-NOT`).

#### Q1's answer, at `swift` @ `408632e5`

| population | property-style sites | basis |
|---|---:|---|
| axiom batteries | **~190** | 218 scoped, less the ~12% example-overload share |
| round-trip tests | ~205 | scoped; overload split not yet applied |
| quantifier loops | ~36 | scoped; 23 in files that also generate |
| lit exhaustive verifiers | ~17 | scoped; the `sort_integers` family |
| **total, order of magnitude** | **~450** | against a naive 5,163 — **91% noise** |

Rough by design (scope §Q1): what had to be precise is the definition and the error rate.

**Measured classifier error rate: ~13%** on `check-battery` (31 example + 2 comment of 246),
and **95%** for an unscoped `loops` count. The error is not a property of the regex — it is
a property of *scope*, which is why the definition is a scope rule first and a syntax rule
second.

### 1.2 `roundtrip` — not started (overload/adjudication pass pending)

### 1.3 `lit-checknot` — resolved by scoping, §0.3(c) closed

3,386 → 17 under the correct scope. The population is real but tiny, and it is the
`sort_integers` family — the one that produced `swiftlang/swift#91083`.

---

## 1.5 Q5 — generators (2026-07-30, `swift` @ `408632e5`)

Run first because it is independent of Q1's definition (scope §7) and its deliverable is a
**spec we would build from**, not another measurement.

### Idiom census — exhaustive, as the scope requires

| idiom | sites | files |
|---|---:|---:|
| `.random(in:)` half-open `..<` | 105 | 53 |
| `.random(in:)` closed `...` | 63 | 32 |
| `SystemRandomNumberGenerator` | 23 | 10 |
| `arc4random` | 19 | 8 |
| `.randomElement()` | 20 | 14 |
| `.shuffled()` | 11 | 9 |
| hand-rolled LCG (`x = x * k % m`) | 1 | 1 |

### Range blindness — the general result is broader than the one we had

| classification | sites | share |
|---|---:|---:|
| **interior** — no `.min`/`.max` anywhere in the range | **165** | **85%** |
| spans `.min ... .max` (full domain) | 17 | 9% |
| other | 10 | 5% |

Most common interior ranges: `0..<100` (14), `1..<100` (13), `1...10` (7), `0..<10` (6).

**85% of generated values are drawn from a hand-picked interior window.** That is a much
broader finding than the half-open-excludes-`.max` idiom we had been citing, and it does not
depend on it.

### A correction to §2's cited finding

The scope doc's §2 says *"`.random(in: 0 ..< T.max)` 8× (excludes `.max`)"*, attributed to
"the corpus". At this pin, `swift` has **zero** such sites. The 8 are real but live in
**`swift-foundation`**, and all eight are consecutive lines in a single function
(`Tests/FoundationEssentialsTests/DecimalTests.swift:59-66`). swift-foundation has 13
half-open-to-`.max` sites in total.

So the idiom is real, narrow, and **one file's habit** — not a corpus-wide pattern. It was
being generalised past its evidence, including by me earlier in this study.

### The deliverable — edge values named by hand, never drawn

`swift`, `test/` + `validation-test/`. "Blocks" is a crude regex split on `func`, so the
denominators are inflated; the *ratio* is computed within one split and is what matters.

| edge value | blocks naming it | …that also generate | drawn |
|---|---:|---:|---:|
| `.nan` | 72 | **0** | **0%** |
| `.infinity` | 70 | **0** | **0%** |
| `.signalingNaN` | 49 | **0** | **0%** |
| `-0.0` / `negativeZero` | 26 | **0** | **0%** |
| subnormals (`leastNonzero/NormalMagnitude`) | 22 | **0** | **0%** |
| `.ulp` / `.ulpOfOne` | 13 | **0** | **0%** |
| `.max` | 145 | 15 | 10% |
| `.min` | 86 | 10 | 11% |
| `.zero` | 139 | 5 | 3% |

**Six IEEE-754 special values are named 252 times and never once appear in a function that
also generates a value.** Not rarely — never. Verified directly rather than inferred from the
split: `.nan` is never an argument to any generator anywhere in the corpus.

The one file where `.nan` and randomness co-occur, `test/stdlib/ParseFloat32.swift`, is the
pattern rather than the exception — `expectRoundTrip(Float32.nan)` and `expectParse("nan",
Float32.nan)` are hand-written example calls, in different functions from the random loops.
Edge cases covered *thoroughly*, by hand, and never under the quantifier.

### What this is a spec for

Ranked priority for what a derived generator must weight in, by how often the corpus names
the value by hand while never drawing it:

1. `.nan` (72) · 2. `.infinity` (70) · 3. `.signalingNaN` (49) · 4. `-0.0` (26) ·
5. subnormals (22) · 6. `.ulp` (13)

This is the ordering our edge-biased generators currently lack an empirical basis for. Note
`.signalingNaN` at #3 — higher than `-0.0` — which is not the order anyone would guess.

### Caveats

- **Co-occurrence is not generation.** A 0% means the value never even appears in a block
  that generates, which is the strong form. A *non*-zero percentage (`.max` at 10%) does not
  establish that the generator produces the extreme — only that both appear nearby.
- **Crude function split**, same caveat the earlier survey attached to this analysis.
- **swift-foundation shows a weaker pattern** (20–50% co-occurrence) on a much smaller
  sample: 767 blocks, 19 with randomness. Not comparable; recorded, not concluded from.

### A fourth classifier-hazard instance

Checking the `.nan` result, a grep for `nan` matched **`nanoseconds:`** — `Task.sleep(nanoseconds:
.random(in: 0..<50000))` read as "nan drawn from a generator". Caught only because the claim
was surprising enough to verify. Four instances now (§0.4), all in one sitting.

## 2. Pass 2 — census

**Not started.** Gated on Pass 1 producing a definition and a classifier error rate
(scope §6).

---

## 3. Upstream defects found

| defect | corpus | status |
|---|---|---|
| `test/stdlib/sort_integers.swift` — sortedness check could not fail (`CHECK-NOT: Error!` vs printed `Error: `) | `swift` | **`swiftlang/swift#91083`**, approved by `tbkka`, unmerged |

Found opportunistically before this study began. Q2 predicts more; each gets a row.
