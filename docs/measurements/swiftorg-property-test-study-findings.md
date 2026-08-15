# Findings — the swift.org property-style-test study

> **Status:** `measured` · **As of:** 2026-08-15


Companion to `swiftorg-property-test-study-scope.md`, which is the plan. This is the
record. **Every number here carries the corpus SHA it was measured at**; a count without
one is not a measurement (scope §3).

**Status: Q1 (§1.1), Q2 (§1.15) and Q5 (§1.5) answered on `check-battery`; Q2 + Q5 also
answered on `loops` (§1.25, exhaustive not sampled). **Q3 answered (§1.4) — 75% recall on
denominator A, carried entirely by one signal.** **Q4 answered (§6)** on the weak-generator
population: its stated deliverable — a before/after on generator coverage — is measured at
**2/8 → 8/8 mutants killed, gained 6 lost 0**, with a gated artifact at
`fixtures/integer-division-generator/`. §5 argued that deliverable might be the wrong one;
§6.7 records that it **lost this round** — on this file the tool's contribution was the
requantification, not the law completion.

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

| population | naive (whole tree) | scoped (`test/stdlib` + `validation-test/stdlib`) | out-of-population |
|---|---:|---:|---:|
| `check-battery` | 246 | **218** | 12% |
| `roundtrip` | 833 | **205** | 76% |
| `loops` | 698 | **36** | **95%** |
| `lit-checknot` | 3,386 | **17** | **100%** |

**"Out-of-population", not "noise", and the distinction is load-bearing.** Three different
things get discarded here and they want three different fixes:

| kind | example | remedy |
|---|---|---|
| **out of population** | `test/SILOptimizer`'s `for _ in 0..<1024` — a real loop in a real test, but a compiler-behaviour test | a **scope** rule |
| **wrong construct, same name** | `checkEquatable(true, a, b)` — a genuinely different overload | an **overload** split |
| **spurious match** | 2 comments mentioning `checkSequence()` | a better **regex** |

Only the third is noise in the ordinary sense; it is 2 sites of 5,163. The other two are
*precise matches on things the query should not have asked for*.

Two things the word "noise" would have implied, both false. It implies **randomness**: these
are highly structured — 537 in one directory, 521 sharing one trip count — and that structure
is what made them diagnosable. And it implies **the corpus is mostly junk**: it is not.
`test/SILOptimizer` is a large and legitimate body of tests. The 91% is a fact about *our
query*, not about swift.org's test suite, and reporting it as "noise" would read as a claim
about them when it is a claim about us.

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
| **total, order of magnitude** | **~450** | against a naive 5,163 — **91% out-of-population**, overwhelmingly compiler tests rather than spurious matches |

Rough by design (scope §Q1): what had to be precise is the definition and the error rate.

**Measured classifier error rate: ~13%** on `check-battery` (31 example-overload + 2 comment
of 246), and **95%** for an unscoped `loops` count. Note what that decomposes into: 12% is an
overload split and 0.8% is a spurious match. The error is almost never the regex — it is
*scope* and *overload*, which is why the definition is a scope rule first, a construct rule
second, and a syntax rule barely at all.

### 1.15 Q2 — reconciliation against the frozen key (`swift` @ `408632e5`)

Key frozen and committed in `a969ee9` **before** `discover` ran; 198 sites, 11 laws.

> **CORRECTED.** The first version of this section verdicted 96 sites as
> `gap-with-witness` on the grounds that no template and no `KnownProperty` case models the
> `Sequence`/`Collection` contracts. That check was incomplete: it never asked whether
> **PropertyLawKit** runs them. It does — `checkSequencePropertyLaws`,
> `checkCollectionPropertyLaws`, `checkBidirectionalCollectionPropertyLaws`,
> `checkRandomAccessCollectionPropertyLaws` all ship. All 96 are `declined`. The error was
> checking one layer of a two-layer toolchain and reporting the result as a toolchain gap.

| verdict | sites | share |
|---|---:|---:|
| **`declined`** — the toolchain runs it; `discover` stands aside | **198** | **100%** |
| `gap-with-witness` | 0 | 0% |
| `ours-covers` | 0 | 0% |

#### The two-layer answer

| layer | covers this population? |
|---|---|
| **PropertyLawKit** (44 law suites) | **all 198 sites** — Equatable, Hashable, Comparable, Sequence, Collection, Bidirectional, RandomAccess all have `check…PropertyLaws` |
| **`discover` template catalog** | **none of it**, by design |

So on the corpus's largest uniform population: **toolchain coverage 100%, `discover` recall
0%**, and the zero is correct rather than a miss. Q3d predicted exactly this shape; the
number is now measured.

#### Where the templates and the kit actually meet

The catalog is not disjoint from the kit — 15 of 22 `KnownProperty` cases have a template:

| has a template | no template |
|---|---|
| additive assoc/commut/identity/inverse · multiplicative assoc/commut/identity · set union assoc/commut/identity · set intersection idempotent · monoid identity · group inverse · semilattice idempotence · codable round-trip | **equatable reflexive/symmetric/transitive · comparable total order · hashable consistency** · distributivity · multiplicative inverse |

The seven without a template are almost exactly the **operator-conformance** laws — which is
the deliberate split, stated in both templates: *"`==` is `Equatable`'s and the kit already
runs its law"*.

#### The real finding: `ProtocolCoverageMap` is incomplete relative to the kit

The kit runs **44** law suites. `KnownProperty` models **22** properties, and has **no case
at all** for the Sequence/Collection family. So the coverage veto cannot reason about laws
the kit demonstrably runs.

**Latent, not actionable — and the second half of that sentence was wrong when first
written.** The veto only fires when a template *proposes* something, and no template proposes
a collection-contract law, so there is nothing to suppress. Missing entries also fail safe:
they cause *less* vetoing, never wrong vetoing.

The claim that `known-properties` / `stdlib-anchor` "under-report what the toolchain covers"
does not hold. `CuratedStdlibCatalog` describes itself as *"a curated catalog of
known-true **algebraic** properties on standard-library types"*, over carriers *"exactly the
ones the generator can construct"*, each tagged with the kit protocol it **witnesses**. It is
a curated algebraic catalog for live verification, not a coverage inventory of the kit — it
was never claiming to report what this gap would add.

So: **no user-visible symptom today.** Recorded as known-latent. Fixing it now would mean
adding `KnownProperty` cases nothing consumes, on the argument that something might later.
It becomes real the moment a collection-contract template exists — which Q2's own gap list
would be the reason to build.

*(Second overstatement in this section, after the 96-gaps error, and both went the same way:
inferring the architecture instead of reading it.)*

#### What this does to §2's suspect conclusion

§2 said *"nobody hand-rolls conservation or referential-integrity, so a catalog pruned to
observed demand would be pruned to round-trip."* Still dead — the corpus hand-rolls law
suites 198 times in the scoped set.

But the replacement is **not** the "disjoint targets" claim the first version of this section
made. The correct statement is narrower and less dramatic: *on this population* the
toolchain covers everything and the division of labour between kit and catalog is working
as designed. Whether the catalog reaches anything the corpus writes by hand is a question
about the OTHER populations — `roundtrip` (205 scoped sites) and `loops` (36) — and remains
open.

### 1.2 `roundtrip` — adjudicated (30 of 205 scoped, seed 20260730, `swift` @ `408632e5`)

#### The structural finding: the law is stated ONCE, the domain is hand-enumerated

`ParseFloat16.swift:18` states a genuine round-trip:

```swift
fileprivate func expectRoundTrip(_ value: Float16, …) {
  let text = value.debugDescription
  let roundTrip = Float16(Substring(text))
  expectEqual(roundTrip.bitPattern, value.bitPattern)   // parse(print(v)) == v
}
```

Comparing **bit patterns**, which is the correct comparison for floats — it separates `-0.0`
from `0.0` and preserves NaN payloads. A careful, universally quantified law.

Every call site is one hand-picked instance: `expectRoundTrip(Float64.infinity)`,
`expectRoundTrip(-Float64.infinity)`, `expectRoundTrip(Float32(bitPattern: 0xffffffff))`.

**This is Q5's finding from the other side.** `expectRoundTrip(-Float64.infinity)` *is* one of
the 70 `.infinity` mentions Q5 counted as "named by hand, never drawn". The law is excellent;
the domain is a hand-written list. Same shape as the `check-battery` instance lists (median
2.5 elements) — one law, enumerated inputs — arrived at from two independent directions.

#### Sample composition — the population is word-matched and shows it

| category | count | property-style? |
|---|---:|---|
| helper **invocation** (one instance of a law) | 14 | law yes, quantification no |
| **law definition** (`func expectRoundTrip`) | 3 | **yes — this is where the law lives** |
| local variable named `roundTrip` | 3 | no |
| comment / `CHECK-LABEL` | 3 | no |
| test-name string (`.test("String roundtrip")`) | 2 | no |
| other (assertions inside helpers, a gyb data row) | 5 | mixed |

**Only 3 of 30 are law statements.** 8 of 30 are not code that asserts anything. The
`check-battery` population is defined by *a call to a known function*; this one by *a word*,
and the error rate reflects it — the counting unit has to be the **helper definition**, not
the mention.

Extrapolated: ~205 scoped sites contain on the order of **20 distinct round-trip laws**,
invoked ~100 times with hand-picked values.

#### Q2 reconciliation — and unlike `check-battery`, we DO fire here

`discover` over `stdlib/public/core` proposes **19 round-trips**, and they are real:

| proposed pair | law |
|---|---|
| `_bridgeObject(fromTagged:)` × `_bridgeObject(toTagged:)` | tagged-pointer encode/decode |
| `_offset(_offset:)` × `_offset(of:)` | index ↔ offset |
| `distance(to:)` × `advanced(by:)` | **`Strideable`** — `advanced(by: distance(to: x)) == x` |
| `bitPattern(bitPattern:)` Int128 ↔ UInt128 | bit-pattern reinterpretation |
| `_dictionaryUpCast` × `_dictionaryDownCast`, `_setUpCast` × `_setDownCast` | cast round-trips |

**Overlap with what the corpus asserts: still zero, but for a different and more tractable
reason than `check-battery`.** There the catalog was silent by design; here both sides are
active and simply pointed at different pairs.

Two causes, and the first is a measurement error to fix before concluding anything:

1. **Wrong sources for the Codable sites.** `test/stdlib/CodableTests.swift` round-trips
   *Foundation* types (`Locale`, `Measurement`, `TimeZone`, `IndexPath`) whose sources are not
   in `stdlib/public/core`. Reconciling those requires `discover` over `swift-foundation`,
   where `codable-round-trip` fires **76** times. Not yet matched by type.
2. **The float parse/print pair is not reached.** `Float16.debugDescription` is a computed
   property and the parse half is `init?<S: StringProtocol>(_ text: S)` — a **failable
   generic initializer**. Pairing `Float16 -> String` against `S -> Float16?` needs `S`
   resolved to `String`. Worth confirming as the cause before treating it as a gap.

#### Reconciliation COMPLETE — and the first `ours-covers` in the study

Redone per-law against the tree that actually defines each carrier. The ~10 law definitions
resolve into four groups:

| law (definitions) | carrier | verdict |
|---|---|---|
| Codable round-trip through JSON / Plist (3) | Foundation types | **`ours-covers`** |
| `Float16/32/64` parse/print (3) | concrete float types | **unreachable — source is `.gyb`** |
| SIMD round-trip (1–2) | `SIMD4<Double>` etc. | **unreachable — source is `.gyb`** |
| `Character` ↔ `String` (1) | `Character` | `gap-with-witness`, with a caveat |
| `BridgeIdAsAny` dynamic-cast (1) | runtime | out of scope — no source-level pair |
| `getRoundtripBridged*` (3) | — | not laws; value-producing helpers |

**`ours-covers`, at last — 9 types.** The corpus round-trips them through `Codable`, and
`discover` independently proposes `codable-round-trip` on each one's `encode(to:)`:

`Calendar` · `DateComponents` · `IndexPath` · `Locale` · `Range` · `TimeZone` · `URL` ·
`URLComponents` · `UUID`

*Method, with its limitation stated:* matched by source-file basename against the type the
corpus names, then each of the 9 confirmed to be an `encode(to:)` suggestion in the file
named for that type. Basename-to-type is a heuristic; it was checked, not assumed.

**The earlier "zero overlap" was mine, not the tool's.** It came from reconciling
Foundation-typed sites against `stdlib/public/core`. Flagged at the time as a measurement
error rather than a finding, and this is the correction.

#### The finding that matters more: a `.gyb` blind spot

`Float16`, `Float32`, `Float64` and the `SIMD` types are declared **only** in `.gyb`
templates — verified, no `.swift` declaration exists for any of them. A `.gyb` file is not
valid Swift, so `FunctionScanner` cannot parse it and `discover` never sees those types at
all.

| `stdlib/public/core` | files | lines |
|---|---:|---:|
| `.swift` | 227 | 127,894 |
| **`.gyb`** | **11** | **7,220** |
| gyb share | 5% | 5% |

Five percent by volume — but a *concentrated* five percent: `FloatingPointTypes`,
`IntegerTypes`, `SIMDVectorTypes`, `FloatingPointParsing`, `AtomicInt`. Every concrete
numeric and SIMD type in Swift.

**Those are exactly the carriers this corpus writes property tests about.** Six of the ten
round-trip laws here are on gyb-only types, and Q5's entire edge-value finding (`.nan`,
`.infinity`, subnormals, `.ulp`) is about floats. The blind spot is small in bytes and
central in subject.

**FIXED for the study, and the result retracts the paragraph this used to be.**
`scripts/swiftorg_expand_gyb.py` expands the templates into a temp tree (all 11 in
`stdlib/public/core`, gyb needs `-DCMAKE_SIZEOF_VOID_P=8`), so `discover` can be run against
a superset and the gyb contribution isolated by diff.

**Deliberately study tooling, not a product feature.** Of the six swift.org corpora checked,
**only `swift` uses gyb at all** — 291 files there, **zero** in swift-collections,
swift-numerics, swift-algorithms, swift-syntax and swift-foundation. It is a stdlib build
tool, not an ecosystem pattern, so teaching `FunctionScanner` to expand it would be
speculative surface for one corpus.

**What it revealed is not what "most actionable item" implied.**

| | before | after |
|---|---:|---:|
| suggestions | 740 | **3,364** |
| `dual-style-consistency` | 22 | **1,247** (1,225 new, all `Likely` — default-visible) |
| `inverse-pair` | 128 | 1,091 |
| `round-trip` | 19 | 25 |

**1,225 of the 1,227 `dual-style-consistency` rows are a single function name** — `replace`,
in `SIMDMaskConcreteOperations.swift`, generated once per SIMD mask type × width. That is
*one* law replicated by a code generator, not 1,225 findings. Expanding gyb does not reveal
new laws so much as **the same laws multiplied across generated types**, and a template
family that put 1,225 default-visible rows on one law would be the Daikon trap arriving
through a new door.

So the volume is worthless and the *targeted* result is the valuable one:

**The float parse/print law is a CATALOG gap, not a reach gap.** With the templates expanded,
both halves are visible — `description` / `debugDescription` (8 declarations in
`FloatingPointTypes.swift`) and, crucially, a **non-generic** `public init?(_ text: String)`
at `FloatingPointParsing.swift:169`. `discover` still proposes nothing: **zero** suggestions
cite the parse file, against 129 citing the types file.

That kills the generic-initializer hypothesis recorded above — the non-generic overload
exists and is equally unreached.

#### Diagnosed: the gate excludes the protocol's own required spelling

`FunctionPairing.initializerPairAdmissible` is a **hard admission gate**, not a score:

```swift
guard label != "init", label.count >= 3 else { return false }
```

An unlabelled init synthesizes to the bare name `"init"`, so the guard fails and **the pair
never forms** — which is why *zero* suggestions cite the parse file rather than some scoring
below the cut.

The gate is defensible in general: without it every single-parameter init would pair with
every same-typed function, and its own doc says it exists so naming stays "a signal, not a
pre-filter". But `LosslessStringConvertible` declares, in `OutputStream.swift:185`:

```swift
public protocol LosslessStringConvertible: CustomStringConvertible {
  init?(_ description: String)          // UNLABELLED, by protocol definition
}
```

So the gate structurally excludes **every conformance to the one standard-library protocol
whose entire contract is a round-trip law**. `extension ${Self}: LosslessStringConvertible`
at `FloatingPointParsing.swift.gyb:59` is exactly that conformance, on exactly the types
this corpus property-tests most.

#### Three layers, three different states — and only the middle one is a "miss"

| layer | state |
|---|---|
| **PropertyLawKit** | **covers it** — `checkLosslessStringConvertiblePropertyLaws` ships |
| **`discover`** | **cannot reach it** — the admission gate rejects the protocol's spelling |
| **`ProtocolCoverageMap`** | **now records it** — `.losslessStringRoundTrip`, added 2026-07-30 |

**No behavioural symptom, and the entry was still worth adding.** The veto only fires on a
proposed suggestion and the pair never forms, so nothing moved. The symptom is epistemic — we
could not distinguish *"we decline this because the kit runs it"* from *"we miss this"*, which
is precisely the confusion that produced two wrong verdicts earlier in this study.

**It went on to produce a third, and this section is the one that was right.** The `loops`
adjudication (§1.25) later filed `PrintFloat.swift.gyb:795/908` as `gap-in-reach` against this
same gate and called it a *"second independent witness"* for a blocker to relax — contradicting
the table above, which had already established that the kit covers the law. Relaxing the gate
would have recreated the `Strideable` double-report. The coverage entry and a pair-scoped veto
now exist, so the decline is explicit and a future relaxation meets a guard rather than the
defect.

#### A second witness for the coverage-map gap

§1.15 recorded `ProtocolCoverageMap` (22 properties) as incomplete against the kit (44 law
suites), missing the `Sequence`/`Collection` family, and downgraded it to latent for want of
a symptom. `LosslessStringConvertible` is a second absence of the same kind.

Two witnesses make it a pattern rather than an oversight: **the coverage map is a hand-kept
subset of the kit, with no mechanism keeping the two in step.**

**That mechanism now exists — `KitCoverageDriftTests` — and building it found a THIRD
witness that is not epistemic.** Classifying all 44 kit suites turned up `Strideable`:
the kit runs `"Strideable.distanceRoundTrip"`,
`first.advanced(by: first.distance(to: second)) == second` (`StrideableLaws.swift:72`), and
`discover` independently proposes `distance(to:)` × `advanced(by:)` as a `round-trip` on
`stdlib/public/core`. **The same law, reported twice** — exactly what
`protocolCoveredProperty` exists to prevent: *"re-reporting another tool's finding teaches
people the tools disagree."*

So the gap is no longer latent. Full disposition of the 44 suites: **13 covered, 10 not a
conformance** (kit-invented law shapes like `ValueSemantic` and `InteractionInvariant`, with
nothing to key a veto on), **20 uncovered with no symptom**, and **1 live double-report**
(since fixed — see below; the map now models 14 protocols and the suite pins zero live
double-reports).

The test asserts a *decision* rather than coverage — a new kit suite lands unclassified and
fails, which is the drift nothing could previously detect. Verified it can fail by removing a
disposition and watching it go red. The `Strideable` entry is pinned by its own assertion, so
closing the defect turns the suite red as the signal to delete it.

**Verdict for this law: `declined` in substance, by accident in mechanism.** The toolchain
runs it; `discover` stands aside for a reason unrelated to the division of labour, and cannot
say so.

##### Closing it took two fixes, and the second one was the real finding

The obvious fix — a `Strideable` coverage entry plus a **pair-scoped** veto in
`RoundTripTemplate` — was verified to fire on a concrete `Strideable` carrier, and **moved
`stdlib/public/core` not at all.** The veto was correct and simply never consulted, because
the carrier there is the *protocol* `BinaryInteger` and the scanner skipped protocol
declarations outright. Their inheritance clause was never recorded, so `ProtocolCoverageMap`
could not learn that **any** protocol refines any other: not a `Strideable`-shaped gap but a
whole mechanism disabled for a whole class of carrier.

Recording protocol decls for their inheritance clause (body still skipped — requirements have
no implementations) closed it. The double-report went away, 740 → 739 suggestions, the single
removed row being exactly `distance(to:)` × `advanced(by:)` at `Integers.swift:1843/1882`.

The **43 other rows that changed** are the more useful result. Each had carried

> ⚠ T must conform to Equatable for the emitted property to compile. This tool does not
> verify protocol conformance — confirm before applying.

and each dropped it, across the carriers `SIMD`, `FloatingPoint`, `StringProtocol` and
`SetAlgebra`. All four genuinely refine `Equatable` — the first three via `Hashable`,
`SetAlgebra` directly — so the tool had been asking a reviewer to hand-confirm something it
was standing on the evidence for. Zero rows *gained* the caveat. The test that had pinned the
old behaviour justified it as *"protocol bodies contribute no `Equatable` evidence about
concrete types"*, which is the belief the measurement falsified.

**The transferable point:** a correct veto that nothing ever calls is indistinguishable from a
missing veto from the outside, and reading the veto cannot tell them apart — only running it
on a corpus can. This is the *"refuter that fires first hides every refuter behind it"* rule
one level up: here the thing in front was not another refuter but the absence of an input.

###### Cross-corpus: the effect is real but confined, and that is a fact about the stdlib

| corpus | suggestions before → after | `Equatable` caveats before → after |
|---|---|---|
| `swift/stdlib/public/core` | 740 → **739** | 169 → **126** |
| `swift-syntax` | 1,115 → 1,115 | 417 → 417 |
| `swift-foundation` | 1,265 → 1,265 | 695 → 695 |
| this repo | 249 → 249 | 18 → 18 |

The change is *active* on all four — protocol decls are recorded everywhere — there is simply
no evidence to act on outside the stdlib. swift-syntax declares **80** protocols with an
inheritance clause and exactly **1** that directly refines `Equatable`/`Hashable`/`Comparable`;
swift-foundation, 37 and 5. The stdlib is the outlier because **its protocols are its
carriers**: the numeric and SIMD API lives in `extension FloatingPoint` / `extension SIMD`,
so the carrier of a suggestion is routinely a protocol name. Elsewhere the API hangs off
concrete types and the question never arises.

###### One guard had to come with it

Recording protocol decls exposed them to `CarrierKindResolver` for the first time, and a
protocol record carries **no stored members** — so it fell straight through to
`classifyMembers([])`, whose documented default is *"empty stored properties → value-semantic
by default."* For an `AnyObject`-constrained protocol that is not a heuristic but a false
statement, and `.valueSemantic` is a **+5 signal** asserting *"algebraic property is
well-defined under aliasing"* — precisely what a reference type breaks. A class-bound check
(`AnyObject`, and the legacy `class` spelling) now runs before the member aggregation.

Deliberately narrow: an *unconstrained* protocol still classifies value-semantic, which is
also unsound — a class may adopt it — but that is the resolver's pre-existing answer for every
protocol carrier reached via an extension record, and it is why `FloatingPoint` and
`BinaryInteger` already classified value-semantic before this change and the corpus carrier
classification did not move. Tightening it is a separate decision that wants its own
measurement, not a rider on a scanner fix. `CarrierKindProtocolBoundTests` pins both halves.

**The real value of the fix is epistemic, not numeric**: it converted an unmeasurable reach
question ("we cannot see those sources") into a measurable catalog question ("we see them and
still do not pair them"). Calling it "the most actionable item the study has produced" was an
overstatement — the third of the session, and again in the direction of making a finding sound
larger than it was.

#### The `Character` case, which is more interesting than a gap

```swift
func checkRoundTripThroughCharacter(_ s: String) {
  let c = Character(s); let s2 = String(c)
  expectEqual(Array(s.unicodeScalars), Array(s2.unicodeScalars))
}
```

Two *initializers* across two types, compared on a **projection** (`unicodeScalars`) rather
than by equality. And the projection is load-bearing: `String(Character(s)) == s` is **false**
for some inputs, because a multi-scalar grapheme can normalise. The corpus states the weaker,
correct law deliberately.

We propose nothing here, and it is worth being precise about why that is only half a gap: our
`round-trip` template states `g(f(x)) == x`, which for this pair would be the **false** law.
Reaching this case needs projection-aware round-trip — closer to `normal-form` than to
`round-trip` — so the honest verdict is "a gap, and naively closing it would ship a false
law".

### 1.25 `loops` ANSWERED — and it disagrees with `check-battery` completely

**36 scoped sites, adjudicated exhaustively rather than sampled** — small enough to read all
of them, which removes the stopping-rule objection raised against Q1's sampled passes. Key
frozen at `fixtures/swiftorg-study/loops-answer-key.json` before any `discover` run; the law
lives in the loop *body* here, so there was no mechanical extraction available even in
principle and every row is hand-read.

Three of 36 are not laws, and saying so is part of the count: `RangeSet:34` **is** the
generator (`buildRandomRangeSet`), `objc-array-slice:16` builds a 1000-element array as setup
for a crash regression, and `InlineArray:219` is a counting check. 33 remain.

#### The headline: 33% covered, against `check-battery`'s 100%

| verdict | sites |
|---|---:|
| `gap-with-witness` | **18** |
| `gap-in-reach` (template exists, cannot reach the code) | 4 |
| `declined` (kit runs it) | 5 |
| `ours-covers` | 3 |
| `borderline-covers` | 2 |
| `partial-declined` | 1 |

**11 of 33 covered — 33%. `check-battery` was 198 of 198.** The two populations are not
measuring the same thing and averaging them would destroy the finding. `check-battery` sites
invoke *conformance axioms* (`checkEquatable`, `checkCollection`) — the kit's home turf, where
standing aside is the correct division of labour. `loops` sites state *bespoke domain laws*
about one type's semantics, and that is where a catalog either has the shape or does not.

#### Five model laws, which we independently concluded were the right thing to propose

`RangeSet` states five laws of the form `rangeSet.op(other) == opViaSet(set1, set2)` — union,
intersection, symmetricDifference, isDisjoint, isSubset — each checking the type against
`Set<Int>` as reference semantics. A sixth (`RangeSet:74`) checks bulk construction against a
fold of `insert(contentsOf:)`.

This is exactly the shape `fixtures/equatable-signal/README.md` arrived at from the opposite
direction: *"Propose the model law, not the Equatable laws, for projections"* — the conclusion
drawn from three real projection bugs (`OrderedSet` order, `BitArray` padding, `Deque` head
rotation) that pass 4/4 Equatable laws and die at trial ≤3 against a model. `homomorphism` is
narrowly additive-measure-over-concatenation; `differential-equivalence` pairs *named* variants
(`fast`/`reference`) and the reference here is written in the test. Two independent lines of
evidence pointing at the same missing template was the strongest build signal the study
produced.

##### BUILT — `model-law`, and the abstraction function is not the one we expected

Shipped 2026-07-30. The design question was *what is the model*, and the obvious answer failed
immediately: `RangeSet` conforms to `Equatable, Hashable, Sendable, CustomStringConvertible`
— **not** `SetAlgebra`, **not** `Sequence`. There is no free abstraction function from a
conformance, and the tests supply theirs (`unionViaSet`) inside the test file where no
source-only analysis can see it.

What `RangeSet` does have is `contains(_:) -> Bool`. **A set is its characteristic function**,
so the law needs no conversion at all:

```
(a.union(b)).contains(x) == (a.contains(x) || b.contains(x))
```

Stated in the type's own API — no conformance, no annotation, which is why this reaches code
`invariant-preservation` (annotation-only) cannot. Measured on `stdlib/public/core`: **6 rows,
739 → 745.** `RangeSet` ×4 at **Strong 80** — the four operations the study found tested by
hand — and `Set` ×2 at Likely 70 (no cluster bonus; its `union` takes a generic `Sequence`, so
only `subtracting` and `intersection` present the `(T) -> T` shape).

**It is not a kit double-report, and that was checked before building rather than after.**
`checkSetAlgebraPropertyLaws` ships **15** laws — commutativity, idempotence, distributivity,
De Morgan, absorption, the symmetric-difference identities — every one relating the operations
*to each other*, and the suite mentions `contains` **zero** times. It proves the lattice
algebra and never ties it to membership. The membership law entails all 15 modulo
extensionality, so it is strictly stronger: a range-backed union that fails to merge the seam
`[1,3) ∪ [3,5)` into `[1,5)` is commutative, idempotent, absorptive and De Morgan-compliant,
passes all 15, and answers `contains(3)` wrongly.

**The first measured run produced three false positives at Strong, and they were worth more
than the six true rows.** `OptionSet` fired on `union`/`intersection`/`symmetricDifference`,
because `OptionSet.contains(_ member: Self) -> Bool` (`OptionSet.swift:216`) is a **subset
test**, not membership. Read as membership the law is not merely unproven but *false*:
`x ⊆ (a ∪ b) ⟺ x ⊆ a ∨ x ⊆ b` fails at `x = {1,2}`, `a = {1}`, `b = {2}`. The gate is now
that the predicate's parameter must not be the carrier — a characteristic function maps
*elements* to `Bool`, whereas `(Self) -> Bool` is a relation between two sets and says nothing
pointwise. Reading the template could not have found this; running it on a corpus did, which
is the same lesson the `Strideable` veto taught earlier the same day from the opposite side.

**The law's real hazard is vacuity, and it ships stated twice.** This is collision-dependent
in exactly the sense CLAUDE.md records: draw `x` from a wide domain and it misses both
operands, `contains` is false on both sides, and every trial passes having checked nothing.
The caveat says so and `GeneratorRecipe.rationale` repeats it at the point of use — that field
exists because *"a reader who does not understand why the alphabet is small will widen it back
on the first cleanup pass, and the law will go quiet without anyone noticing."*

Sweep: swift-syntax and swift-foundation produced **zero** rows (neither has a carrier pairing
a curated set operation with an element-typed `contains`), and this repo's own `+2` is
self-dogfood on the two new files, not the template firing.

> **CORRECTION 2026-08-01 — it closed THREE of the five `RangeSet` witnesses, not
> five.** The sentence below says "the five swift.org `RangeSet` witnesses are now
> covered". Measured: `union` / `intersection` / `symmetricDifference` fire;
> `isDisjoint` and `isSubset` are **boolean-valued** and were never in
> `SetOperation`. They are now covered by `SetRelationModelLawTemplate` (§8).

**It closes ONE of the two evidence lines, and the other is still open.** The five swift.org
`RangeSet` witnesses are now covered. The `Equatable`-signal line is not: its recommendation
names the model as *"the type's canonical `Sequence` / `Collection` view"*, and the three bugs
behind it — `OrderedSet` order, `BitArray` padding, `Deque` head rotation — are **order and
representation** bugs. A membership law is order-insensitive by construction and cannot see
any of them; `Array(a) == Array(b)` can. That is a second family (`a == b ⟺ Array(a) ==
Array(b)`, gated on `Sequence` conformance) and it is deliberately not built here, because it
has a false-positive problem the membership family does not: `Set` is a `Sequence` whose
iteration order is unspecified, so it fails the law spuriously. Resolving that needs an
ordered-carrier discriminator, which is its own measurement. Recorded rather than attempted —
claiming both lines closed on the strength of one would misreport the state.

##### BOTH LINES NOW CLOSED — the discriminator was measured and the second family shipped (2026-07-31)

`OrderedCarrierDiscriminator` + `SequenceViewModelLawTemplate`, stating
`(a == b) == a.elementsEqual(b)`. See §7 for the measurement; the short version is **0 false
positives against 20 types with documented order semantics, 7 firings**, including all three
`Equatable`-signal witnesses at Strong.

#### `discover` and the tests aim at different properties of the same functions

Unscored, per the guardrail. On `RangeSet` / `Duration` / `Diffing`, `discover` proposes **33**
laws where the tests state ~18, and **the overlap is approximately zero**:

| what `discover` proposes | what the tests state |
|---|---|
| `dual-style-consistency` ×4 (`formUnion`↔`union`, Strong 75) | model laws vs `Set<Int>` |
| `idempotence` ×4, `inverse-pair` ×7 (Possible) | membership biconditional |
| `monotonicity` ×8 on `Duration.seconds/milliseconds/…` | unit decomposition of `.components` |
| `predicate` ×6, `measure-non-negativity` ×1 | representation invariant |

This is not a recall failure. Both sets are legitimate; they are simply *different laws about
the same functions*, and a reconciliation that scored one against the other would report a
miss where none exists. Worth noting the catalog does **not** propose commutativity or
associativity for `union`/`intersection`, which are true — method-form binary operations
(`self.op(other)`) are not paired by those templates.

One suggestion looked like a false positive and is not: `idempotence` on `symmetricDifference`
(where `a △ a = ∅`, not `a`). The rendered block carries *"THIS LAW IS A CONJECTURE — read off
the shape and the name, not entailed by either, so a CORRECT implementation can fail it"*, at
Possible (35), hidden without `--include-possible`. That is the explainability contract
working, not a precision defect.

#### `f(x) == f(x)` is refutable here, which qualifies a stated design principle

Eleven of the 33 sites are *repetition without generation*: call the same accessor 3–10 times
on a fixed value and assert the answer does not change. Five assert **referential** stability
(`unsafeBitCast(… as AnyObject, to: UInt.self)` — the same address each time), four assert an
**absorbing state** (an exhausted iterator keeps returning `nil`; `countByEnumerating` keeps
returning 0), two guard against **over-release** of a bridged `NSError`.

The design note says *"`f(x) == f(x)` passes 'did discovery return > 0' and cannot fail."*
That holds **for a pure function**, and the stdlib writes this test precisely where purity is
in doubt — across ObjC bridging, ARC, and CoW, repeated observation is not free, and these
tests exist because it has broken. The principle is right about what to *score*; it should not
be read as "the shape is never worth testing." The absorbing-state variant has no template at
all.

#### The most textbook property in the population is unreachable, for a precise reason

`Diffing:708` states `a.applying(b.difference(from: a)) == b` plus `applied.applying(d.inverse())
== a` — diff/patch round-trip with an involution, keyed `ours-covers` on the catalog question.
`discover` proposes **nothing** on `Diffing.swift`. The halves live on **different protocol
extensions**: `applying(_:)` is in `extension RangeReplaceableCollection` (`Diffing.swift:59`),
`difference(from:)` in `extension BidirectionalCollection` (`:126`). Pairing requires a common
carrier and there is none — and `applying` returns `Self?`, so even co-located the type
symmetry would not close. Recording protocol decls (2026-07-30) was necessary for this and is
not sufficient.

`PrintFloat.swift.gyb:795` and `:908` were first recorded here as a **second independent
witness** for the blocker Q2/`roundtrip` found — `initializerPairAdmissible`'s `guard label !=
"init"` rejecting the float parse/print pair — with "relax the gate" as the implied fix.

**The verdict here was wrong, and §1.2 above had already said so.** That section's own table
lists PropertyLawKit as *covering* this law and asks only for a coverage-map entry to record
the decline; this adjudication then contradicted it and filed the gate as a defect to fix. The
kit does run the law: `checkLosslessStringConvertiblePropertyLaws` ships
`"LosslessStringConvertible.roundTrip"`, `Value(String(describing: x)) == x`
(`LosslessStringConvertibleLaws.swift:40`). Relaxing the gate would have made `discover`
propose a law another tool in the toolchain already states — the **exact `Strideable`
double-report** found and fixed the same day, approached from the other side. The gate is not
arbitrary either: pairing evidence for `round-trip` is name-stem overlap
(`base64EncodedString` ⊃ `base64Encoded`), and an unlabelled `init?(_ description: String)`
synthesizes to the bare name `"init"`, which has no stem to match. **Declining is correct.**

Recorded as `partial-declined`, and the correction exposed a better gap than it removed.
`expectAccurateDescription` checks *two* things in order — round-trip accuracy, then
**shortness** (*"it makes no sense to check shortness if the result is inaccurate"*). The kit
covers the first. *"The printed form is the shortest string that round-trips"* is a real,
refutable law that no template states, and it is the half worth building for.

`ProtocolCoverageMap` now carries a `LosslessStringConvertible` entry and `RoundTripTemplate` a
pair-scoped veto, so the decline is **explicit** rather than an accident of a name-stem gate —
the same "declined in substance, by accident in mechanism" phrasing this study already applied
to `Strideable`. The veto guards a door that is currently locked, deliberately: it is placed
while the reasoning is on the record, so a future relaxation meets it instead of the defect.

#### Q5 on this population — the opposite result from `check-battery`

`check-battery` named six IEEE-754 specials 252 times and generated them **0** times. `loops`
is the reverse: three of its generators reach for edges *deliberately*.

| site | edge strategy |
|---|---|
| `Duration` ×4 | `Int64.random(in: 0 ... 0x7fff_ffff_ffff_fc00)` — the largest `Int64` exactly representable as `Double`, i.e. the top of the range chosen for exactness |
| `Character:296` | `randomGraphemeCluster(1, 9)`, commented *"making the maximum length 9 scalars tests both sides of the limit"* — spans the 63-bit small-representation boundary |
| `PrintFloat` ×2 | walks `nextUp`/`nextDown` ten steps from a seed, testing each float's *neighbours* |

The `RangeSet` generators are the interior kind Q5 flagged (`Int.random(in: -100...100)`, no
`Int.min`/`Int.max`), so the population is split rather than uniformly good. But the three
above are real edge discipline, hand-written, and they are what a derived generator does not
produce — the generator weakness Q5 recorded is a weakness against *these* authors' practice,
not a universal.

---

### 1.4 Q3 ANSWERED — 75% recall, carried entirely by one signal

Blinded per the protocol: `discover` run with `--test-dir` pointed at an empty directory, key
frozen at `fixtures/swiftorg-study/q3-reach-key.json` **before** the run, with three misses
**predicted in writing** so none could be rationalised afterwards.

**Blinding was not a formality.** `swift-foundation` went **1,265 → 1,259** once blinded, and
the six lost suggestions were *all* `differential-equivalence` — that template's entire output
on that corpus was test-derived and does not survive source-only. `stdlib/public/core` was
already blind (0 cross-validation signals), so earlier stdlib numbers stand. **swift-syntax was
also checked and is clean**: 1,115 both ways, zero cross-validation signals, so its output is
entirely source-derived.

#### The headline

| denominator | recall |
|---|---|
| **A as frozen** (13 entries) | **9 / 13 = 69%** |
| **A corrected** (12 entries) | **9 / 12 = 75%** |

Both are reported because the correction is **post-hoc**. `loops-random-totality` was keyed to
`input-totality`, and that attribution is wrong on grounds independent of the result:
`InputTotalityTemplate`'s own doc defines its role as *"a function handed arbitrary bytes must
return or throw for every one of them — it must never trap"* — the fuzz law for **parsers**,
which fires exactly twice on core (`decodeCString`, `_tryFromUTF8`). `[].randomElement() == nil`
is an empty-input edge law that no template states. Attributed by name-similarity
("totality") rather than by role. Silently swapping the denominator after seeing the score is
precisely what freezing a key exists to prevent, so it is not swapped — it is disclosed.

**Every miss was predicted, 3 for 3**, and all three are *reachability*, not scoring:

| miss | cause |
|---|---|
| `Diffing:708` — diff/patch inverse | halves on **different protocol extensions** (`RangeReplaceableCollection` / `BidirectionalCollection`); pairing needs a common carrier |
| `RangeSet:206` — representation invariant | `invariant-preservation` is **annotation-only** |
| `Dictionary:5269` — index validity | same annotation gate |

#### The finding that matters more than the percentage

**All 9 hits are one template, at one score, on one signal.**

| | |
|---|---|
| template | `codable-round-trip`, 9 of 9 |
| signal | *"declares a custom `Codable` conformance (hand-written)"*, **+50**, on all 9 |
| score / tier | **50 (Likely)** on all 9 |
| unique contribution — conformance | **9 / 9 = 100%** |
| unique contribution — shape, name, docstring | **0** |
| marginal | remove the +50 and every hit goes **50 → 0 = Suppressed** |

The decomposition the protocol asked for is **degenerate**. There is no redundancy to measure:
no shape corroboration, no curated-vocabulary hit, no docstring corroboration contributed
anything. Delete the conformance channel and measured recall on this denominator goes to
**zero** — not "below the tier cut", to zero.

That is uncomfortable for the project's own framing. This is a **type-directed inference**
tool, and on the denominator where it succeeds, the success comes from *reading a conformance
declaration* — the one channel `fixtures/equatable-signal/README.md` already measured and found
**does not predict refutability**. The tool is right that these types round-trip; it is right
for the cheapest available reason.

#### What A cannot support

**12 entries are not 12 independent observations.** Nine are instances of a single law family
(Codable round-trip on nine Foundation-ish types), so the effective sample is closer to *one
hit family plus three distinct misses*. A 75% figure carries far less weight than its
denominator suggests, and it should not be quoted without this sentence attached.

#### B alongside — the coverage context

Denominator B (all non-`declined` law-bearing `loops` entries) is **28**, of which **18** are
`gap-with-witness` — laws no template can state, misses before `discover` runs. The ceiling
under B is therefore ≤ 10/28 ≈ 36%, and the measured hits on `loops` specifically are **0**:
every `loops` entry in A missed. B restates §1.25's 33% coverage figure in recall units, which
is why A was chosen as the headline.

#### The answer to the question Q3 was built to settle

*Is the limiting factor threshold height, or the discriminator?* **Neither, on this evidence.**
The misses are not near a cut — they are structurally unreachable (two annotation gates, one
cross-carrier pairing). The hits are not near a cut either — they sit at 50 with a single +50
signal holding them up.

##### CORRECTION — "nothing is threshold-sensitive" was too strong

That sentence was true of the 12-entry denominator and **false corpus-wide**, and the
generalisation was mine rather than the data's. Measured blinded across three corpora:

| corpus | suggestions at exactly score 20 (the Possible floor) |
|---|---:|
| swift-syntax | **738 of 1,115 — 66% of all output** |
| `stdlib/public/core` | 138 of 745 |

Move the Possible cut from 20 to 21 and two-thirds of swift-syntax's output disappears.
Thresholds are *extremely* sensitive — at the **floor**, which is not where I looked. I checked
the Likely and Strong cuts and generalised from them.

**The insensitivity in the middle is real, and it is structural.** Scores land on a sparse
lattice — `{20, 25, 30, 35, 40, 45, 50, 65, 70, 75, 80, 85}`, with nothing at all between 50
and 65 on either corpus — because the weights are few and coarse and most suggestions carry
**one** signal:

| signals per suggestion | swift-syntax | core |
|---|---:|---:|
| 1 | **820 (74%)** | 363 (49%) |
| 2 | 283 | 278 |
| 3+ | 12 | 104 |

When a suggestion has one signal, **its score *is* that signal's weight**, and the number
carries no information beyond which signal fired. Tuning a cut in the middle does nothing
because there is nothing in the middle. That is a property of the scoring structure, not of the
sample — so the right statement is: *threshold work is a lever at the floor and nowhere else.*

##### The prototype that makes the trade measurable — `--require-corroboration`

`CorroborationRule` withholds default visibility from any suggestion resting on a single
positive signal. Opt-in, and deliberately **not** a change to `Tier.init(forScore:)` — the tier
arithmetic is not adjusted to reach a target; carve-outs live in the consumers. The
role-entailed escape hatch (`isWorthSurfacingBelowCut`) is not gated by it, because "the code
owes this law" is a different justification from "one signal fired."

Measured, blinded:

| corpus | default | with the rule | cost |
|---|---:|---:|---:|
| swift-syntax | 586 | **586** | **free** |
| `stdlib/public/core` | 315 | 264 | −16% |
| swift-foundation | 347 | 259 | −25% |
| **Q3 recall (denominator A)** | **9 / 12** | **0 / 12** | **−100%** |

That last row is the finding. The rule demotes **exactly** the family Q3's recall was made of,
and it costs nothing at all on the corpus with no Codable-shaped surface. So the design question
is now a single sharp one, with numbers attached: **is a lone "declares a custom `Codable`
conformance" worth a Likely?** If yes, the rule is wrong. If no — and `equatable-signal` already
measured that conformance does not predict refutability — the rule is the fix, and Q3's 75%
was measuring the wrong thing.

**Not enabled by default.** It is shipped as a flag precisely so the judgement is made against
these numbers rather than argued from the posture.

---

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

## 1.6 Q4's prerequisite — BUILT (2026-07-31, `swift` @ `408632e5`)

Q4 was blocked on the most concrete deliverable in the study: `TestLifter` could not
see this corpus at all. `TestSuiteParser` recognised two shapes, both
*declaration*-shaped — an `XCTestCase` method named `test…`, and a function carrying
`@Test`. `StdlibUnittest` has neither. A test is a **call taking a trailing closure**,
and the assertion table held ten `XCTAssert*` names plus `#expect`, so the entire
`expect*` family was invisible.

### What it measures now

Over `test/stdlib` + `validation-test/stdlib`, 558 files:

| | before | after |
|---|---|---|
| tests recognised | **0** | **4,171** |
| tests slicing to an assertion anchor | 0 | **2,263** (54%) |

Anchor kinds: `xctAssertEqual` 1,931 · `xctAssertTrue` 179 · `xctAssertFalse` 101 ·
`xctAssertNotEqual` 33 · `xctAssertNotNil` 13 · the four ordering kinds 6.

### Two decisions worth recording

**The rule is structural, not name-based.** Recognition cannot key on the receiver:
the corpus spells it `suite`, `tests`, `SetTestSuite`, `DictionaryTestSuite`,
`ArrayTestSuite`, `StringTests`, `mirrors`, `FloatingPoint`, `OptionSetTests`, … across
5,092 call sites with no common prefix. Nor on the trailing closure's immediate
callee — the chained form `…test("x").xfail(…).code { }` puts `.test` several links
down the base chain. The rule is: *a call with a trailing closure whose callee chain
contains a `.test(<string literal>)` call.*

**`expect*` maps onto the EXISTING assertion kinds rather than adding new ones.**
`AssertionInvocation.Kind` discriminates assertion *shape* — "two expressions claimed
equal", "one expression claimed true" — and the `xctAssert` case-name prefix is
historical. Mapping is what makes every downstream detector (round-trip, symmetry,
idempotence, count-change, reduce-equivalence) read this corpus without being touched.

### The gap, and it is named

4,171 recognised against 5,038 textual `.test("` occurrences — **867 unaccounted for
(17%)**, from two causes, both witnessed:

- **`.test(…) { }` inside a `func` body.** Function bodies are never descended into
  (the M1.1 nested-decl contract), so these are missed.
  `test/stdlib/Observation/Observable.swift` puts 20 of them inside
  `static func main() async`.
- **No trailing closure at all.** `test/stdlib/StaticBigInt.swift` writes
  `testSuite.test("Name", testCase.testMethod)` — the body lives in a separate method,
  so there is nothing inline to slice.

Both are limits, not bugs, and both are pinned by tests so they cannot silently change.

### The one deliberate omission — now closed

`expectNil` (809 sites) was **not** mapped at first: there was no `.xctAssertNil` kind,
only `.xctAssertNotNil`, and mapping it there would invert the assertion's polarity — a
detector would read "asserted non-nil" from `expectNil(x)` and infer the opposite law.
Dropping was the safe choice; adding the kind was the correct one, and it landed
2026-07-31.

**It was not merely additive.** The slicer anchors on the *terminal* assertion, so while
`expectNil` was unrecognised a body ending in one anchored on an **earlier** assertion —
pointing at the wrong conclusion. Recognising it both adds anchors and corrects those.

| | before | after |
|---|---|---|
| bodies slicing to an anchor | 2,263 | **2,677** |
| `xctAssertNil` anchors | 0 | **452** (2nd-largest kind) |

The small dips elsewhere (`xctAssertEqual` 1,931 → 1,906, `xctAssertTrue` 179 → 173) are
those corrected anchors, not lost ones.

Also unmapped, and not equality/ordering assertions at all: `expectCrashLater` (810),
`expectParse` (441), `expectType` (227), `expectPrinted` (191).

### What this unblocks

Q4 itself — and, per §1.4, the corroboration question. Q3 measured that all nine laws
`discover` reached rested on a **single** `+50` conformance signal, which is why
`--require-corroboration` took recall from 9/12 to 0/12: there was no second channel.
The test-derived channel is that second channel, and against this corpus it was
returning zero.

**The target decision is made** (scope §8, resolved 2026-07-31): **local gated fixture**,
pinned at the corpus SHA; upstream stays open for *defects* found while converting, closed
for the conversions themselves. The Swift repo vendors no property-based testing library and
`StdlibUnittest`'s whole randomness surface is `LinearCongruentialGenerator` — the generator
this study measured as weak — so an upstream conversion could only add a dependency
(a proposal, not a PR) or be written with the broken generator.

**And which population changed.** Scope §Q4 predicted the `check*` batteries were "strictly
more valuable" to convert. Measured false: `checkEquatablePropertyLaws` already asserts the
same four laws `StdlibUnittest.checkEquatable` does, and `fixtures/equatable-signal/README.md`
already measured those four as **structurally blind** to projection bugs (arm 7 drops a whole
word and passes 4/4). Converting them enlarges the domain of a law that cannot fail. Some
sites are vacuous outright — `test/stdlib/Result.swift:192` checks a *synthesized* `==`,
which cannot violate reflexivity, symmetry or transitivity. That population's verdict is
`declined`; convert the **weak-generator** population instead.

## 2. Pass 2 — census

**Not started.** Gated on Pass 1 producing a definition and a classifier error rate
(scope §6).

---

## 3. Upstream defects found

| defect | corpus | status |
|---|---|---|
| `test/stdlib/sort_integers.swift` — sortedness check could not fail (`CHECK-NOT: Error!` vs printed `Error: `) | `swift` | **`swiftlang/swift#91083`** — approved by `tbkka`, **merged 2026-07-30** |
| `SortedDictionary.Keys.==` and `.Values.==` — inverted comparison, `if e1 == e2 { return false }` where `!=` was meant. **Reflexivity is false and disjoint views compare equal.** | `swift-collections` @ `899809d3`, still present on `main` @ `ff27e367` | **`apple/swift-collections#696`** — filed 2026-08-01, open. See §3.1 |

### 3.1 The `SortedDictionary` views, and why the caveat is load-bearing

Found by chasing what §7.4's tightening dropped. Both files, verbatim:

```swift
if lhs.count != rhs.count { return false }
for (e1, e2) in zip(lhs, rhs) {
  if e1 == e2 {          // <-- `!=` was meant
    return false
  }
}
return true
```

**Confirmed by running it, not by reading it** — the repo's standing rule, and it
paid: the behaviour is worse than the reflexivity violation the body suggests.

| expression | result | should be |
|---|---|---|
| `keys == keys` | **false** | true |
| `values == values` | **false** | true |
| `[1,2,3].keys == [4,5,6].keys` | **true** | false |
| `SortedSet == SortedSet` (control) | true | true |
| `SortedDictionary == SortedDictionary` (control) | true | true |

Not merely non-reflexive: two *disjoint* views of the same size compare **equal**.
`SortedSet`, `SortedSet.SubSequence`, `SortedDictionary` and
`SortedDictionary.SubSequence` all use `!=` and are correct — only the two
projection views are wrong.

**And it has no coverage**: `Tests/SortedCollectionsTests/` has no equality test
for either view, which is the §3 bar (*"a check that cannot fail **and** has no
other coverage"*) reached from the other side — here there is no check at all.

**Filed as `apple/swift-collections#696`, 2026-08-01**, after four checks that the
report itself would otherwise have failed: the bug is still on `main` at
`ff27e367` (the local checkout was 74 commits behind), no existing issue covers
it, the reproduction was run against `main` in a throwaway worktree rather than
against the study's pin, and the one-character fix was **applied and re-run**
rather than merely proposed. The worktree was removed and the pinned corpus
verified byte-identical afterwards, per §0.1.

**The caveat that keeps this honest.** `SortedCollections` is gated behind the
`UnstableSortedCollections` trait, which is **commented out of the default trait
set**, and the trait's own description reads *"early developer drafts, and they
are not ready for use in production. We will make significant, source breaking API
changes to these types before they ship."* So this is a real bug in **unreleased,
opt-in** code, not a defect in shipping swift-collections. Recording it as the
latter would be exactly the over-claim §4 retracted for `sort_integers`.

**What it says about the toolchain, which is the reusable part.** This is *not* the
projection-blindness class the study has been chasing — `checkEquatablePropertyLaws`
would catch it on the first trial, because reflexivity is plainly false. So the
finding is not "our model law found something the kit could not". It is that a
public `==` shipped with **no law suite pointed at it at all**, and the thing that
surfaced it was reading `==` bodies systematically rather than any property being
proposed. That is the §5 location-marking claim arriving from an unexpected
direction: the catalogue never fired here, and the *census* did.

Found opportunistically before this study began. Q2 predicts more; each gets a row.

**One row was retracted from this table on 2026-07-31** — the `sort_integers` permutation
observation. It is not a defect; see §4. The bar for this table is `#91083`'s: a check that
cannot fail **and** has no other coverage.

---

## 4. An incomplete law that is probably deliberate — `sort_integers`

**Retracted as a defect, kept as an observation.** This was first written up under
"Upstream defects found" and headed "what the issue actually is". That framing was
wrong, and the correction came from the repo owner rather than from measurement.

### 4.1 What the test does and does not check

The test checks that sorting produces something **in order**:

```swift
var y = $0.sorted()
for i in 0..<y.count - 1 {
  if (y[i] > y[i+1]) { print("Error: \(y)"); return }
}
```

It never checks that the output contains the **same elements** as the input. The two
are different claims and only the pair pins the result — the intuition being that **a
function returning `[]` passes**, since an empty list is trivially in order.

Compiled and run against the verifier copied verbatim, both of these pass:

| wrong `sorted()` | in order? | caught? |
|---|---|---|
| replaces every element with the smallest | yes | no |
| drops half the elements | yes | no |

`partition_verifier` has the same shape: input multiset `[1,2,3,4,6,8]` returned as
`[1,1,1,4,4,4]` is correctly *grouped* and passes.

Our `ReorderPartitionTemplate` names the missing invariant in capitals — *"IT IS A
PERMUTATION — this is the load-bearing invariant"* — which is why this was found at
all.

### 4.2 Why it is almost certainly deliberate, and not reported

Two arguments, both stronger than the original write-up allowed.

**~~It costs 14×.~~ Efficiency is NOT the reason — this argument was raised, measured,
and withdrawn within the hour.** A microbenchmark over 5,040 arrays of 7 elements
showed the multiset check at 4.2 ms against the sort's 0.3 ms, and "14×" was reported
as if it settled the matter. It does not: **the whole test binary runs in under 10 ms
either way** (5 runs each, original and patched), inside a CI build measured in hours.
A ratio on a 0.3 ms base is not a cost argument, and quoting one instead of the
absolute number is exactly the kind of dramatic-sounding framing this study is
supposed to catch. Recorded rather than deleted because the error is instructive:
**14× of nothing is nothing.**

**The property is covered elsewhere — and this argument alone carries the
retraction.** `sorted()` is exercised by essentially every
other test in the suite; a sort that dropped elements would break thousands of them.
So the permutation law *is* checked — just not here. **That is the same reasoning as
the study's `declined` verdict** ("we understand it and stand aside because something
else runs it"), applied to the test ecosystem rather than to PropertyLawKit. The
original write-up applied that reasoning to the kit an hour earlier and failed to
apply it here.

No PR was opened and no question was asked upstream.

### 4.2a What this example is actually for

The retraction is about whether to *report* it. The finding itself is larger than that,
and it is the toolchain's founding case:

> To ensure sort works properly, **two properties need to hold, but only one was
> explicitly stated.**

Sortedness and permutation are jointly necessary — neither alone pins the result.
A human wrote one down. `ReorderPartitionTemplate` names the other, and named it
before anyone opened this file. That is the product thesis demonstrated on the most
canonical example in property-based testing, and it does not depend on the omission
being a bug, being worth fixing, or being reported.

The framing error was treating "is this a reportable defect?" as the question. It was
never the question.

### 4.3 What survives as a finding

Not "the Swift project has a bug". Two things:

1. **The catalogue named a real incompleteness before anyone read the file.** That is
   evidence about `ReorderPartitionTemplate`'s precision, which is what the study is
   for — independent of whether the omission is worth fixing.
2. **"Incomplete" and "defective" are different verdicts, and the study already has
   vocabulary for the difference.** Reaching for the defect table first, when
   `declined` was right there, is the same over-claim the study's §0.4 classifier
   hazard keeps producing in other costumes.

### 4.3a The artifact — Q4's first conversion (2026-07-31)

The completed laws were applied **in the fork**, which is the §8 target for conversions
(upstream stays for defects only).

| | |
|---|---|
| repo | `Joseph-Cursio/swift` |
| branch | `complete-sort-permutation-laws` |
| commit | `14c0fb86348` |
| branched from | the pinned corpus SHA `408632e5983` |
| diff | +22 lines, `test/stdlib/sort_integers.swift` |

```swift
// Element-count multiset, built without calling `sorted()` or `partition(by:)`.
// The oracle for a reordering operation must not be computed with that same
// operation, or a bug that loses elements hides itself on both sides.
func _elementCounts(_ a: [Int]) -> [Int: Int] {
  var counts: [Int: Int] = [:]
  for x in a { counts[x, default: 0] += 1 }
  return counts
}

// …then, at the end of each verifier:
if y.count != $0.count || _elementCounts(y) != _elementCounts($0) {
  print("Error: \(y) is not a permutation of \($0)")
  return
}
```

**Verified four ways**, because "it compiles" is not evidence that a check can fail:

1. Compiles against the local toolchain.
2. **Output byte-identical** to the pristine original on a correct standard library, so
   the `CHECK` / `CHECK-NOT` contract is untouched.
3. **The predicate is correct as written in the file** — extracted verbatim and run over
   five cases, not merely as retyped into a probe. The load-bearing one is that a
   *reordered* array is a permutation and correctly does **not** fire; getting that
   backwards would turn every passing run red.
4. Whole test still runs in well under 10 ms (see §4.2 — the cost argument was withdrawn).

**Corpus integrity.** §0.1 records that the study once measured against a tree we had
modified. So the fix lives only on the branch and the fork: `~/GitHub_projects/swift` was
returned to `main` @ `408632e5983` with `sort_integers.swift` byte-identical to the pin and
a clean working tree, verified after pushing. Every number in this document still carries a
valid SHA.

**What the artifact demonstrates** — and it is not "we fixed Swift". Two properties were
jointly necessary, a human wrote one down, and `ReorderPartitionTemplate` named the other
before anyone opened the file. The patch is the evidence; §4.2a is the point.

**What it is not.** It is not yet a *before/after on generator coverage*, which is Q4's
stated deliverable. Nothing here replaced a generator — the law was completed, not
requantified. `sort_integers` cannot supply that number: it is `lit`+FileCheck (no anchor
for TestLifter) and its sortedness law already runs exhaustively. The generator before/after
has to come from `IntegerDivision.swift`'s `Int64` arm (scope §Q4).

### 4.4 The near-miss, which is the finding that survives intact

This one is about my own error, not the Swift project's, so the retraction above
leaves it untouched. **The first version of the fix was itself a check that could
not fail**, and it was nearly recorded as the patch:

```swift
if y.sorted() != $0.sorted() { … }   // WRONG
```

`y` is `$0.sorted()`. So this computes the oracle for `sorted()` **using
`sorted()`** — the very function under test. A sort that drops elements drops
them on both sides of the comparison, and the check passes. An oracle for a
reordering operation must not be built from that operation.

**Worse, the probe written to validate the fix reported success.** It varied a
`sortFn` *parameter* while `.sorted()` inside the verifier remained the real
standard library — so the substitution the probe made was not the substitution
the real test needs. In the actual file the subject **is** `Array.sorted()`, and
stdlib cannot be swapped out, so the probe was structurally incapable of
detecting the flaw it was built to detect.

It was caught by re-reading the patch in its real shape, not by evidence.

This is the same failure the whole study is about — a check that cannot fail —
reproduced *while fixing an instance of it*, and it generalises past this file:

> **A test's oracle must be independent of the thing under test.** This is the
> testing-side form of the repo's standing rule that a tool may not grade its own
> homework — and the corollary is that a probe which substitutes something other
> than the real subject proves nothing about the real subject.

---

## 5. Q4 closing note — what the corpus is actually for (2026-07-31)

Recorded at the end of the session that unblocked Q4, because the reframe is
obvious on the day and gone in three weeks.

### 5.1 The claim

Scope §Q4 says *"the human supplied the law — the judgment part — and the
generator is the mechanical part that is measured weak."* That is right and too
narrow. **It is not only the generator that is mechanical. The completeness of
the law set is too.**

Stated as a division of labour:

> **Humans mark where properties live. The tool completes the set and
> requantifies it.**

A property-style test is a **high-precision signal that a property exists at
that location**, and a **low-quality signal of what the full property set is**.
That asymmetry is the useful part, because existence is the hard judgement and
completeness is the mechanical one.

`sort_integers` is the whole claim in one file:

| layer | who supplied it | quality |
|---|---|---|
| "sorting has a law worth testing here" | the human | **correct** — and not derivable from shape alone |
| the law as written | the human | **half** — ordered, not permuted (§4.1) |
| the missing half | `ReorderPartitionTemplate` | named before anyone read the file |
| the quantification | the human | exhaustive on one arm, an LCG on another (§2) |

### 5.2 Two qualifications, or the claim overreaches

**It is a precision signal, not a recall one.** A test marks a property where
someone bothered to write one; absence of a test is not evidence of absence of a
law. That is exactly what Q3 measures from the other direction, and why Q3's 75%
matters independently of anything here.

**Some tests are regression markers, not law perceptions.** A test can exist
because a bug was fixed there, with nobody having thought "there is an invariant
here". Those still mark interesting locations, but for a different reason, and
**this study has not separated the two populations.** `sort_integers` is itself
ambiguous: `permute` / `randomize` reads like someone thinking in domains, while
the `FIXME(prext)` suggests accretion. Splitting them is unmeasured work.

### 5.3 What it implies for the product

If tests mark locations, then `TestLifter`'s job is not primarily *lifting tests
into properties*. It is **using tests as a search index for where to point the
catalogue** — the corpus tells you where a human already judged a law to exist,
and the catalogue tells you what the complete set at that location is.

That is a different product from the one scope §Q4 describes, and on today's
evidence a better one: the transformation half was measured *declined* for the
`check*` batteries (§Q4 correction) and structurally impossible for
`sort_integers` (§4.3a), while the location-marking half paid out on the first
file anyone read.

**Not yet tested.** Whether that reframe survives contact with the
weak-generator population — `IntegerDivision.swift`'s `Int64` arm is where it
gets its first real trial, and it is still the recommended next move.

> **TESTED — see §6. The reframe LOST on this file, and the deliverable it
> questions won.** Q4's stated deliverable is now measured (2/8 → 8/8 mutants
> killed, gained 6 lost 0, artifact in `fixtures/integer-division-generator/`).
> The location-marking half found nothing to add here: the law as written is
> already complete, and `discover` proposes nothing on the marked API at all.

---

## 6. Q4 ANSWERED on the weak-generator population (2026-07-31)

`swift` @ `408632e5`. The trial §5 asked for, on the file scope §Q4 named.
Both halves were run: the **transformation** half (replace the generator) and
the **location-marking** half (does the catalogue complete the law set at the
place the human marked). They came out opposite ways, and the one §5 bet
against is the one that paid.

### 6.1 The transformation half — measured, and it is a strict gain

Artifact: `fixtures/integer-division-generator/` — a gated local fixture per
scope §8, ~0.3s, no network dependencies. Full table in its README; the
headline:

| | original | converted |
|---|---:|---:|
| edge classes reached (of 17) | **0** | **17** |
| mutant dividers killed (of 8) | **2** | **8** |
| sign quadrants covered | 4 | 4 |
| law failures against the real stdlib | 0 | 0 |

Gained 6, lost 0, at the same 65,536 trials and with the law **verbatim**.

**Score refutability, not coverage — so the 8/8 is the number, not the 17/17.**
A coverage table only says boundary values are present now. Both domains were
therefore run against eight mutant dividers, six boundary and **two interior
controls**. The controls are the point: spending a quarter of the trial budget
on edges cost no interior detection, which a coverage table cannot show and a
6–0 table without controls would have quietly assumed.

*Limitation, on the record:* the mutants are hand-written, so this scores the
domain against **plausible** defects rather than the observed defect
distribution of real dividers. Each carries a `standsFor` naming its defect
class so a reader can judge that independently.

**No defect found.** The standard library answers correctly on all 65,536
converted trials, boundary cases included. This is a finding about the test's
reach, not about `dividingFullWidth`.

### 6.2 The corpus's generator is stratified for sign and blind to magnitude

"Weak generator" invites the wrong picture, and this file corrects it. The
original's `bhi << 56 | random(0 ..< 2^56)` is **stratification by top byte** —
it covers the four sign quadrants at exactly 16,384 trials each, which uniform
sampling would only approximate. Someone thought about it.

What it structurally cannot produce is a small magnitude:

| over the 65,536 trials | |
|---|---|
| distinct divisors | **256** |
| smallest \|divisor\| | **2^53.3** |
| smallest \|remainder\| | **2^43.4** |
| divisors below 2^50 | **0 of 256** |

The bottom 53 binades are not under-sampled, they are **unreachable** — a
divisor below 2^50 needs the top byte in `{0, -1}` *and* 56 random bits to land
low, ~2^-40 per draw against 256 draws.

**This sharpens Q5's headline rather than repeating it.** §1.5 measured 85% of
corpus ranges as "interior", meaning a hand-picked window like `0..<100`. This
is a different and worse mechanism reaching the same place: the window here is
not hand-picked at all, it falls out of a stratification scheme that is *good*
at the axis it was designed for. A reviewer scanning for `random(in: 0..<100)`
would pass straight over it.

### 6.3 The location-marking half — the catalogue adds nothing here

§5's claim is that a property-style test is a high-precision signal that a
property exists *at that location*, and the tool's job is to complete the set.
Applied here, both steps fail.

**The law set is already complete.** The `Int8` arm checks three things
(`|r| < |b|`, `r`'s sign matches the dividend's, `a == b*q + r`); the `Int64`
arm checks quotient and remainder against the constructed values by equality,
which **entails** all three, because the `r` being compared against was
constructed to satisfy them. There is no `sort_integers`-shaped missing half.

**And `discover` proposes nothing at all on the marked API.** Run over
`stdlib/public/core/Integers.swift`: 23 suggestions, all `Possible` (≤35), on
`min`/`max`/`magnitude`/`signum`/`abs`/`distance`/`advanced` — and **zero**
citing `dividingFullWidth` or `multipliedFullWidth`. Wiring `--test-dir` to the
corpus test changes nothing: 23 → 23.

### 6.4 The reach gap behind it, isolated — and two wrong hypotheses first

The pair is real and is exactly the round-trip family: for a fixed divisor,
`quotient ↦ multipliedFullWidth(by:)` and `dividend ↦ dividingFullWidth(_:)`
are inverse. Why does nothing fire?

**Hypothesis 1, tuples: WRONG.** Free functions with tuple parameters and
returns pair fine — `(Widget) -> (high: Int64, low: UInt64)` against
`((high: Int64, low: UInt64)) -> Widget` fires both `round-trip` and
`inverse-pair`, labelled or bare, and identically to the same shape written
with a named struct.

**Hypothesis 2, the method form or the `by:` label: WRONG.** A method
`mul(by:) -> (high: Widget, low: UInt64)` pairs with a method
`div(_: (high: Widget, low: UInt64)) -> Widget` at both templates.

**The isolated cause is the *2-tuple return*.** In one controlled file, three
`mul` variants paired with every `div` variant returning `Widget` — and the one
returning `(quotient: Widget, remainder: Widget)` paired with **nothing**. That
is `dividingFullWidth`'s real signature.

So the round-trip here is not `g(f(x)) == x`. It is

```
divide(multiply(by: q)) == (quotient: q, remainder: 0)
```

— a **projected** round-trip against a product-typed return, where one
component is the round-trip and the other is a constant.

**Which is the same shape as the `Character` case (§1.2), with the opposite
verdict.** There the projection was lossy — `String(Character(s)) == s` is
false under normalisation — so the honest verdict was *"a gap, and naively
closing it would ship a false law."* Here both components are exactly true. A
projected-round-trip template would ship a **false** law on `Character` and a
**true** one on `dividingFullWidth`; the discriminator is whether the discarded
component is constrained, not whether a projection is involved. Recorded as a
gap-with-witness, deliberately not built — it needs that discriminator first.

**And the catalogue's law would have been the case the human never generates.**
`divide(multiply(q)) == (q, 0)` *is* the `remainder == 0` slice — measured at
**zero** trials in the original domain (§6.1). The two halves converge from
opposite directions and neither reaches it: the human quantified over a domain
that excludes exact division, and the tool cannot state the law that is exactly
that case.

### 6.5 TestLifter sees the tests and anchors none of them

All 6 arms are recognised (§1.6's work), and all 6 slice to `assertion: nil`.
Isolated by controlled probe: the `Slicer` unwraps **one** level of trailing
loop, not two, and every arm is `for bhi { for qhi { … } }`.

That limit is **documented and deliberate** (`Slicer.swift:78`): *"applied once,
not recursively: a doubly-nested loop is a table-driven test rather than a
quantifier."* IntegerDivision is a counter-witness — a doubly-nested loop that
is a genuine two-variable quantifier.

**And relaxing it is not worth it, which is why this is recorded rather than
built.** Measured over the whole corpus (4,171 recognised / 2,677 anchored, both
reproducing §1.6 exactly):

| of the 1,494 unanchored | |
|---|---:|
| blocked by the nested-loop limit | **25** |
| …of which a second unwrap would reach an assertion | **20** |

**20 of 1,494 — 1.3%.** The documented decision is right at corpus scale and
this file is in a 20-test minority. Chasing it would have been tuning the wrong
lever, which is the *"refuter that fires first hides every refuter behind it"*
rule one level up: the first blocker found was real, deliberate, and almost
worthless.

### 6.6 Where the unanchored population actually goes — and two more of my own errors

Classified syntactically by the terminal statement, since that is what the
slicer anchors on:

| bucket | count |
|---|---:|
| plain non-assert call is terminal | **698** |
| trailing `do`/`catch` | 205 |
| trailing closure call | 138 |
| trailing expression, other | 130 |
| trailing loop (unwrapped once, still no anchor) | 101 |
| trailing statement / declaration, other | 89 |
| unmapped `expect*` is terminal | ~90 |
| **mapped assertion is terminal yet unanchored** | **0** |

The last row is the important one: **there is no slicer defect here.** Every
unanchored test is unanchored because its terminal statement is not a mapped
assertion.

**Error 1 — a 315-case bucket that did not exist.** A first pass classified by
*text* (`contains("expectEqual(")` on the last statement) and produced "315
tests where a mapped assert is last yet no anchor", which reads as a defect.
Dumping the actual samples showed the assertion sits inside a trailing
`autoreleasepool { }` / `withAUMP { }` closure or a `do`/`catch`. Fifth instance
of §0.4's classifier hazard in this study, this one mine, and caught only by
looking at the rows instead of the totals.

**Error 2 — a "biggest lever" worth exactly zero.** 413 of the 698 terminal
plain calls are `_blackHole`, StdlibUnittest's optimizer barrier. That looked
like a one-line fix worth 28% of the unanchored population: skip trailing
semantic no-ops before anchoring. Measured before recommending: **+0**. Two
reasons, and both matter more than the fix would have. `Slicer` already takes
the *last assertion in source order* rather than requiring the last statement to
be one, so a trailing no-op never blocked anything. And **399 of the 445 bodies
with a trailing no-op are preceded by `expectCrashLater()`** — they are trap
tests, with no equality assertion by design. That population is correctly
unanchorable: its property is "this input is outside the domain", which is the
precondition half, not the equality half.

Three hypotheses of mine falsified in one session (tuples, the nested-loop
limit as *the* blocker, the no-op lever), all in the direction of making a
finding sound larger or more fixable than it was. Same direction as the three
§1.2 records.

### 6.7 What this does to §5

**§5's reframe lost this round, and the deliverable it questioned won.** Stated
plainly because §5 was written with the opposite expectation:

| half | `sort_integers` (§4/§5) | `IntegerDivision` `Int64` (here) |
|---|---|---|
| tool completes the law set | **won** — named the missing permutation law | **nothing to add** — the law is already complete |
| tool requantifies the domain | impossible (exhaustive; no anchor) | **won** — 2/8 → 8/8 |

So the two files are each other's mirror, and the honest conclusion is that
**neither half generalises yet.** §5's *"the transformation half was measured
declined for one population and structurally impossible for the site we tried"*
is now false as a general claim: it was measured a strict gain on the population
scope §Q4 actually recommended. The division of labour §5 proposes — humans mark
where properties live, the tool completes the set — is not wrong so much as
**one of two mechanisms**, and this file is the witness that the other one is
real.

What survives §5 intact is the weaker and probably more durable form: a
property-style test is a high-precision signal that a property exists at that
location. Both files agree on that. What they disagree about is what the tool
then contributes there — and on this evidence it depends on whether the human
wrote the law completely, which is not knowable from the location alone.

### 6.8 Still open

- **The projected-round-trip discriminator** (§6.4). The witness exists on both
  sides now — one true (`dividingFullWidth`), one false (`Character`). Building
  it needs the rule for when the discarded component is constrained.
  > **Attempted and DECLINED on measurement, 2026-07-31 — see §7.1.** The
  > product-typed-return shape has no population: 27 raw candidates on the
  > stdlib, all endomorphism noise, and **0.19%** of functions across nine
  > parsing corpora. The discriminator that *was* built is a different one — §7.
- Unchanged from the last session: whether `checkComparable` shares the
  `Equatable` blindness, and whether 88% `predicate` volume matters now that it
  sorts last.

---

## 7. The ordered-carrier discriminator (2026-07-31)

The question was "build the projected-round-trip discriminator". Three candidate
shapes were measured before one was built, and the two that came from §6 both
died. What shipped came from a passage in §1.15 instead.

### 7.1 Two declined shapes, and why the corpus refused them

**Product-typed returns — declined, no population.** §6.4 proposed a template for
`g(f(a)).<component> == a` where `g` returns a tuple. Measured:

| corpus | candidates | what they are |
|---|---:|---|
| `stdlib/public/core` | 27 | `byteSwapped` × `addingReportingOverflow`, `signum` × `quotientAndRemainder` — every one an endomorphism paired with an `A -> (A, …)`, the clique `endomorphismRoundTripPair` already exists to stop |
| 9 parsing corpora, 54,929 summaries | **106 tuple returns (0.19%)** | labels are domain nouns — `year`, `month`, `serverChannel`, `similarity` |

And **the motivating witness is not reachable anyway.** §6.4 isolated the blocker
to a 2-tuple return on a synthetic file where both halves sat on one type. On the
real stdlib `multipliedFullWidth` is on `FixedWidthInteger` and `dividingFullWidth`
on `SignedInteger`/`UnsignedInteger` — **different carriers**, so `Self` resolves
differently and the pair cannot form regardless. The tuple was the *second*
blocker. Same wall as `Diffing.swift` in §1.25, and the same "measure after each
fix" lesson.

**Parser residues — declined, the shape is not Swift's.** The redirect to parsing
was right about the domain and wrong about the shape: the parser-combinator
`parse(input) -> (value: T, rest: Substring)` essentially does not exist here.
`rest` appears **0** times across the nine corpora and `remainder` twice; Swift
parsers carry a mutating cursor (`Parser.expect`, `JSON5Scanner`) instead. So
there is no residue vocabulary for a discriminator to key on.

### 7.2 What shipped instead, and what forced each rule

§1.15's closing line — *"it becomes real the moment a collection-contract template
exists"* — points at the one discriminator with **measured bug witnesses** behind
it. `fixtures/equatable-signal` had recorded the sequence-view model law as
deliberately unbuilt pending exactly this.

`OrderedCarrierDiscriminator` decides whether a carrier's iteration order is part
of its **value**, so `(a == b) == a.elementsEqual(b)` can be proposed for
`OrderedSet` and not for `Set`. Scored against 20 types with documented order
semantics:

| rule | correct | false positives | safe abstains |
|---|---:|---:|---:|
| Bidirectional/RandomAccess, veto `SetAlgebra` | 16 | **1** | 3 |
| drop `BidirectionalCollection` | 16 | **0** | 4 |
| …and require `ExpressibleByArrayLiteral` | 9 | **0** | 11 |

Each tightening was forced by a witness:

- **`TreeDictionary`** — the measured false positive. `BidirectionalCollection`
  with hash order and no `SetAlgebra` to veto it. Walking backwards is something
  a hash-tree's chain does fine, so that conformance says nothing about order.
- **`Range`** — ordered, but its value outlives its elements: `5..<5` and `7..<7`
  are both empty and compare **unequal**, so `elementsEqual(b) ⟹ a == b` is
  false. That direction catches two of the three bug witnesses and cannot be
  dropped, so the carrier must be excluded instead.
  `ExpressibleByArrayLiteral` is the type's own statement that a sequence of
  elements suffices to build it — exactly what the law claims.

Measured firing set: **7, zero false positives** — `OrderedSet`, `Deque`,
`BitArray` (all three `equatable-signal` witnesses), `Array`, `ContiguousArray`,
`ArraySlice`, `IndexPath`. Zero on swift-syntax.

### 7.3 Three things recorded rather than tidied away

**One of the two gates is redundant on every corpus measured.** Re-adding
`BidirectionalCollection` produces a byte-identical firing set, because the
element-determined gate already excludes every hash-ordered type present
(`TreeSet` is `SetAlgebra`-vetoed, `TreeDictionary` is dictionary-literal). Kept
anyway, and labelled as untested-but-sound rather than load-bearing — a rule kept
for a reason that was *measured false* would be worse than one kept for a reason
that is merely unexercised.

**The tier bonus is nearly a constant.** The `hash(into:)` bonus was drafted to
separate Likely from Strong; measured, **all seven firings carry it**, because
`Hashable`'s contract ties the two together. Left alone rather than retuned —
adjusting the arithmetic to hit a target tier is what this repo forbids.

**The law's hazard is vacuity, not falsity.** A carrier whose `==` is already
implemented as `elementsEqual` — `Deque`'s shipped body is close to that — makes
the law `f(x) == f(x)`. It still refutes every mutant, so it ships with the
hazard in the caveat rather than a veto. Detecting that body shape needs a
scanner signal that does not exist; that is the next measurement.

### 7.4 That measurement, done — `EqualityBodyClassifier` (2026-07-31)

`fixtures/equatable-signal`'s headline is that conformance does not predict
refutability and *"the shape of the `==` body"* does. Nothing read the body until
now; §7.3 shipped with a caveat asking the reader to go open it themselves.

Three shapes, defined by the real bodies they were read off:

| shape | body | meaning for the law |
|---|---|---|
| `sequenceComparison` | `Deque` returns `elementsEqual` | **vacuous** — restates the result expression |
| `storedFieldProjection` | `BitArray`: `_count` guard + `_storage ==` | **refutable** — the shape 3 real bugs live in |
| `conversionComparison` | `Set(a) == Set(b)` | the fixture's own mutant shape |

**The result is the whole point of building it.** The default surface went from
**7 Strong to 3**, and the 3 are exactly the refutable ones:

| carrier | shape | tier |
|---|---|---|
| `BitArray`, `OrderedSet`, `IndexPath` | projection | **Strong 80** |
| `Deque`, `Array`, `ContiguousArray`, `ArraySlice` | sequence comparison | Possible 35 |

A penalty (−45) rather than a veto, weighted to reach `.possible` from either
configuration the template produces. The law still refutes every mutant at trial
≤3 and still guards the count check and fast path in front of the comparison, so
it keeps its worth as a regression guard and loses its claim on the default
surface.

#### Both extensions to the classifier were forced by its own output

The first version keyed on `elementsEqual` alone and classified `Array`,
`ContiguousArray` and `ArraySlice` as `unclassified` — three of the seven carriers
it exists to score. Reading them showed two further spellings of one idea:
`Array` inlines the comparison over indices, `ArraySlice` over parallel iterators.

Then the generalisation over-fired: `sequenceComparison` went 5 → **17**, and
`OrderedSet.UnorderedView` was among them. Its body is

```swift
for item in left._base { if !right._base.contains(item) { return false } }
return true
```

— result `true`, a loop returning `false`, both operands referenced. It satisfied
every condition the rule checked while meaning the **reverse**: it iterates one
operand and *searches* the other, which is deliberately order-INsensitive.
Tightening to lockstep traversal (two subscripts, or two iterators) took it back
to **8**, all genuine.

Two false starts, both caught by reading output rather than by reasoning — the
same pattern as §6.6, and the argument for running a new signal over a corpus
before trusting it.

#### A third: the tightening threw out a real spelling with the false positives

Chasing the types the tightening dropped found a **fourth spelling** —
`SortedSet+Equatable.swift:27`:

```swift
for (k1, k2) in zip(lhs, rhs) { if k1 != k2 { return false } }
return true
```

`zip` is lockstep *by definition*, so this is the least ambiguous pairwise
traversal of the four. It was lost because it uses neither subscripts nor
`makeIterator`, and the tightening was validated by checking that the false
positives had gone — **not** by checking what else went with them. Adding it takes
the classification 8 → 14 (six `Sorted*` entries), with the two membership scans
and `Dictionary.Keys` correctly staying out.

The transferable point is narrow and worth keeping: *"measure after each fix"*
applies to what a fix **removes**, not only to what it was aimed at. A tightening
validated against its own motivating example is validated against one row.

#### One housekeeping note worth leaving

`Signal+Kind.swift` is now at **exactly** its 400-line SwiftLint cap. An enum's
cases cannot be split across files, so the next signal added there will not fit
without moving prose out of the file first. Recorded because the failure mode is
a lint error on someone else's unrelated change.

**Adjacent, and deliberately not touched at the time:** `OrderSensitiveCarrierNames`
is a six-name curated denylist whose own doc says it stands in for *"structural
order-sensitivity detection pre-SemanticIndex"*. This is that detection, and
`CommutativityTemplate`'s veto used the denylist. Same predicate, opposite
polarity — commutativity vetoes *on* an ordered carrier, the model law *requires*
one.

> **Migrated 2026-08-01 — see §7.5.**

### 7.5 Migrating the commutativity veto onto the discriminator

**The two consumers ask different questions, and that was the live hazard.** The
model law states a biconditional, so it needs both halves of the rule — `Range` is
ordered but its value outlives its elements. Commutativity asks only whether
`a.union(b)` and `b.union(a)` can differ, which turns on order alone.

Migrating to the full `verdict` would therefore have silently dropped `String`,
`Substring`, `Data` and `Slice` — every one a carrier where an order-preserving
`union` is genuinely non-commutative. So the discriminator now exposes
`isOrderSensitive` separately and the veto reads that.

**Measured before changing anything**, across swift-collections,
`stdlib/public/core`, swift-foundation, swift-syntax and swift-nio: the denylist
and the structural rule agree on **every** carrier declaring one of the four set
verbs — zero disagreements, and suggestion counts unchanged after the migration
(684 / 779 / 1,278 / 0).

**The agreement is thinner than it looks, and that is the finding.** Five of the
six denylist names never appear at all — `Array`, `ContiguousArray`, `ArraySlice`,
`Deque` and `OrderedDictionary` declare no set operations — so `OrderedSet` is the
only entry the denylist actively fires on. A six-name list doing one name's work.

**What the migration actually buys** is therefore entirely on carriers nobody has
written yet, demonstrated on synthetic ones:

| carrier | conformances | before | after |
|---|---|---|---|
| `Timeline` | `RandomAccessCollection`, `ExpressibleByArrayLiteral` | suggestion shipped | **vetoed** |
| `Ledger` | `RandomAccessCollection` only | suggestion shipped | **vetoed** |
| `Bag` | none | shipped | shipped (control) |

`Ledger` is the arm that justifies reading `isOrderSensitive` rather than the whole
verdict: it is ordered but not element-determined, so the full verdict abstains
while an order-preserving `union` on it is still non-commutative.

**The denylist is kept as a union, not replaced.** `OrderedDictionary` conforms to
`Sequence` and to nothing marking position as value-determined, so the structural
rule abstains on it. Dropping the list would be safe on everything measured and
unsafe on a shape nobody has written — the same posture as §7.3's redundant gate,
and pinned by its own test arm so the residue is visible rather than assumed.

---

## 8. Working the gap list — the boolean-valued model law (2026-08-01)

§1.25 left **19** `gap-with-witness` rows (the table says 18; row 13 was moved in
post-hoc during Q3). Adjudicated into families, they are not 19 problems:

| family | rows | state |
|---|---:|---|
| model law, set **operations** | 3 | closed by `ModelLawTemplate` |
| model law, set **relations** | 2 | **closed here** |
| absorbing state (exhausted iterator returns nil forever) | 4 | **declined §8.5** |
| scaled decomposition (`Duration.seconds(d).components`) | 4 | **shipped §8.8** |
| randomness (surjectivity, seeded determinism, shuffle-preserves-multiset) | 4 | open — mostly purity-gated |
| bulk-vs-incremental construction | 1 | **closed §8.6** |
| selection/membership biconditional | 1 | open |

### 8.1 The correction that made this findable

§1.25 recorded *"the five swift.org `RangeSet` witnesses are now covered."* Measured:
**three**. `isDisjoint` and `isSubset` return `Bool` about a *pair*, and
`ModelLawPairing.SetOperation` only ever held `union` / `intersection` /
`symmetricDifference` / `subtracting`.

The claim was written the day the sibling template shipped, from the same cluster,
and nobody checked the two that did not fit its shape.

### 8.2 What ships

`SetRelationModelLawTemplate` — the relation held to the carrier's own membership:

```
if a.isDisjoint(with: b) { expect(!(a.contains(x) && b.contains(x))) }
```

A relation cannot be an equation, because its answer is one `Bool` about the whole
pair. What *is* statable pointwise is an **implication** — and only one direction.

**The direction it cannot check, stated rather than buried.** A wrongly-`true`
answer dies as soon as `x` lands in the overlap. A wrongly-`false` answer cannot be
refuted pointwise at all: that needs an existential, which no single trial
establishes. The direction it does check is the one interval- and bitset-backed
implementations actually fail — a missed overlap at a seam.

**Measured, four corpora: 23 rows, zero false positives.**

| corpus | rows | carriers |
|---|---:|---|
| swift-collections | 17 | `BitSet`, `BitSet.Counted`, `OrderedSet`, `OrderedSet.UnorderedView`, `SortedSet`, `TreeSet` |
| `stdlib/public/core` | 6 | `RangeSet`, `Set` |
| swift-foundation | 0 | — |
| swift-syntax | 0 | — |

Both witnesses fire at Strong. `OptionSet` is absent, because the template reuses
`ModelLawPairing.membershipPredicate` verbatim — including the element-typed gate
that stopped three `OptionSet` false positives at Strong on the sibling's first
measured run.

### 8.3 Two things declined

**The strict variants.** `isStrictSubset` differs from `isSubset` only in requiring
properness, and properness is an existential — pointwise the two produce an
*identical* law. Emitting them would add rows that cannot test the thing their name
is about, which is what "score refutability, not suggestion count" forbids. That is
5 relations found per carrier reduced to 3 proposed.

**Strong by default was not.** It scores 70 (Likely) for a lone relation and 80
with the three-relation cluster bonus — one tier below the sibling's baseline on
purpose, because the equation form is a biconditional refutable from either side
and this one checks a single implication.

### 8.4 The four gates, as applied

The two shapes declined in §7.1 died on gates 1 and 4. This one was checked against
all four *before* building, which is the only reason it was worth starting:

1. **Population** — 38 relations across 8 carriers, measured first.
2. **Refutability** — a false `true` at a seam is the bug class the sibling template
   was built for.
3. **Non-duplication** — `checkSetAlgebraPropertyLaws`' 15 laws relate operations to
   each other and mention `isSubset` / `isDisjoint` / `isSuperset` **zero** times.
4. **Statability** — pointwise as an implication, with the missing direction named
   in the caveat rather than discovered by a reader.

### 8.5 The absorbing-state family — DECLINED, twice over

Four rows, the largest open family, and the one with witnesses on two independent
carriers. It fails on two different gates, and neither was visible before checking.

**Row 16 — `test/stdlib/Strideable.swift:236` — the kit already runs it.**

```swift
var i = stride.makeIterator()
for _ in 0..<nonNilResults { expectNotNil(i.next()) }
for _ in 0..<10 { expectNil(i.next()) }
```

`checkIteratorProtocolPropertyLaws` ships `"IteratorProtocol.terminationStability"`,
and its body is that law verbatim — pull to exhaustion, then assert two further
`next()` calls are `nil`. Building from this witness would have recreated the
**`Strideable` double-report**, the defect this study found and fixed on 2026-07-30.

**Rows 17–19 — `countByEnumerating` — no population.** These are genuinely
uncovered: `NSFastEnumeration`, not `IteratorProtocol`, so the kit says nothing.
They are declined on gate 1 instead:

| corpus | files mentioning `countByEnumerating` |
|---|---:|
| `swiftlang/swift` | 13 |
| swift-collections, swift-foundation, swift-nio, swift-syntax, SwiftProjectLint | **0** |

An ObjC bridging shadow protocol, not an ecosystem pattern. A template would serve
one corpus's test inputs.

#### What shipped instead, and why it is not nothing

`ProtocolCoverageMap` now carries `.iteratorTerminationStability`, keyed on both
`IteratorProtocol` and `Sequence` (the kit's `SequenceLaws` chains the iterator
suite, so a carrier reached under either name is covered). `KitCoverageDriftTests`
reclassifies `IteratorProtocol` from `.uncoveredNoSymptom("as Sequence")` to
`.covered`.

That reclassification is the point. §1.15 recorded twenty kit suites as
"uncovered with no symptom" and downgraded them to latent for want of one. **The
symptom arrived, and it was this adjudication**: a hand-read of a stdlib test filed
a law the kit runs as `gap-with-witness`, which is the precise confusion
`protocolCoveredProperty` exists to prevent — *"we could not distinguish 'we decline
this because the kit runs it' from 'we miss this'."*

Changes no output today, because no template proposes the law. The same latent
state `.losslessStringRoundTrip` was added in, and for the same reason: a future
attempt now meets a guard instead of the defect.

#### The tally, and what it says about the gate order

Four families assessed today, three declined:

| shape | died on |
|---|---|
| product-typed round-trip (§7.1) | population |
| parser residues (§7.1) | population |
| **absorbing state** | **non-duplication**, then population |
| set relations (§8) | — shipped |

Non-duplication is the gate that fired latest and cost least, because checking it
is one grep of the kit. Population took a corpus sweep; statability took building a
prototype. **Check the gates in ascending order of what they cost to check** — this
family would have been declined in two minutes rather than an hour if the kit grep
had come first.

## 8.6 Bulk-vs-incremental — built, and thin on purpose (2026-08-01)

The last of the seven families. Row 1 —
`validation-test/stdlib/RangeSet.swift:74`, over 1,000 random inputs:

```swift
let set = RangeSet(ranges)
var comparison = RangeSet<Int>()
for r in ranges { comparison.insert(contentsOf: r) }
expectEqual(set, comparison)
```

`BulkIncrementalTemplate` states `T(elements) == elements.reduce(into: T()) { $0.insert($1) }`.

### The gates, checked cheapest-first this time

The §8.5 lesson applied. One grep of the kit came first and it passed —
`checkRangeReplaceableCollectionPropertyLaws` runs `emptyInitIsEmpty`,
`removeAllMakesEmpty`, `removeAtInsertRoundTrip`, `replaceSubrangeAppliesEdit`, and
no `reduce`-based fold law exists anywhere in the kit. Had that failed, the
population sweep would not have been worth running.

### The discriminator is the whole template

**The inserter's parameter must be the bulk init's ELEMENT type.** `RangeSet`
declares *both* `insert(_ value: Bound)` and `insert(contentsOf: Range<Bound>)`,
and its bulk init takes `[Range<Bound>]`. Pairing the wrong one states a flatly
false law. Measured on the shipped pipeline: it picks `insert(contentsOf:)`.

Without that rule this family is unstatable, which is what "general shape,
unmeasured" was hiding.

### Population: 2, and the survey that said 3 was wrong

| corpus | rows |
|---|---:|
| `stdlib/public/core` | 1 — `RangeSet`, the witness |
| swift-foundation | 1 — `IndexPath` |
| swift-collections, swift-syntax, swift-nio | 0 |

The sizing sweep said three carriers. `OrderedSet.UnorderedView` matched only
through its variadic `init(arrayLiteral elements: Element...)`, which the scanner
records as `[Element]`; its real bulk init is
`init(_ elements: some Sequence<Element>)`. Pairing against an
`ExpressibleByArrayLiteral` requirement is a much weaker basis than pairing against
a declared bulk entry point, so the pipeline is right to decline it and the survey
was over-counting.

**Two rows is below both templates shipped today** (sequence-view 7,
set-relation 23). It ships anyway because both rows are real, the discriminator is
demonstrably correct on the carrier that could have produced a false law, and the
repo's posture is high precision over recall.

### Why it is an undercount, and what was deliberately not done

The element match is textual: it resolves `[Range<Bound>]` and `Array<Element>`
and gives up on `init<S: Sequence>(_ elements: S) where S.Element == Element` —
the idiomatic spelling, and the one `RangeReplaceableCollection` mandates.

The obvious widening is to key on `RangeReplaceableCollection` conformance
instead, which would name dozens of carriers. **Deliberately not done**: that
protocol *default-implements* the bulk init as `self.init();
self.append(contentsOf: elements)`, so for every conformer that does not override
it the law is true by construction — the unrefutable-by-construction shape
`preconditionElidingVariant` was vetoed for. Widening it needs an
"overrides the default" discriminator, which is its own measurement.

## 8.7 The gap list, closed

Seven families, all assessed:

| family | rows | outcome |
|---|---:|---|
| model law, set operations | 3 | shipped (earlier) |
| model law, set relations | 2 | **shipped** §8 |
| bulk-vs-incremental | 1 | **shipped** §8.6 |
| absorbing state | 4 | **declined** §8.5 — kit covers it, then no population |
| scaled decomposition | 4 | **shipped** §8.8 |
| randomness | 4 | open — purity-gated, a policy question |
| selection biconditional | 1 | open |

**Three shipped, one declined, three open.** The declined one is worth as much as
the shipped ones: it is now an explicit `ProtocolCoverageMap` entry, so the next
attempt meets a guard instead of the `Strideable` defect.

And the four gates earned their keep — they killed two shapes in §7.1 and one
family here, each before any code was written except a probe.

## 8.8 Scaled-unit consistency (2026-08-01)

Rows 8–11. I predicted this would die on population — *"4 rows, one carrier"* — and
that prediction was wrong.

### The shape recurs

| corpus | carrier | units |
|---|---|---|
| `stdlib/public/core` | `Duration` | seconds, milliseconds, microseconds, nanoseconds |
| swift-nio | `TimeAmount` | hours … nanoseconds (6) |
| swift-nio | `ByteCount` | bytes, kilobytes, megabytes, gigabytes |

Three carriers, not one.

### The law was restated to make it statable

The witnesses check `Duration.milliseconds(v).components` against
`(v / 1000, v % 1000 * 1e15)`. That form needs **two** carrier-specific facts: the
scale factor *and* the internal decomposition. `Duration` splits into seconds and
attoseconds and nothing else does, so reproducing it would have been a one-carrier
template.

Stating the law between two **constructors** needs only the ratio:

```
Duration.seconds(n) == Duration.milliseconds(n * 1_000)
```

It says nothing about how the carrier stores the value and reaches the same defect —
a wrong conversion constant.

### The discriminator: time units are definitional, byte units are a convention

SI *time* prefixes cannot be reinterpreted — `milli` is 1/1000 of a second, the same
standing `union` means "in either".

**Byte prefixes can.** `kilobytes` means 1000 in some types and 1024 in others, and
both are defensible; swift-nio's `ByteCount` uses `1000 * count`. A template
asserting either ratio would be flatly wrong for half the ecosystem, so the byte
family is excluded — which costs one of the three carriers found.

`days` and `weeks` are excluded for the same class of reason: a calendar type may
make a day something other than 86,400 seconds.

### Measured: 8 rows, all Strong, zero false positives

| corpus | rows |
|---|---:|
| `stdlib/public/core` | 3 — `Duration` |
| swift-nio | 5 — `TimeAmount` |
| swift-foundation, swift-collections | 0 |

**Adjacent pairs only.** A six-unit family would otherwise be fifteen rows saying
much the same thing, and the distant ratios are the dangerous ones — hours to
nanoseconds is 3.6e12, so the multiplication overflows for almost any drawn input
and the law would report a domain limit rather than a defect.

That overflow bound is the caveat that matters: the right-hand side multiplies, so
an unbounded generator produces false counterexamples. The recipe says to bound `n`
so the product is representable *and to keep the boundary of that bounded range*,
because the largest surviving `n` is exactly where a conversion off-by-one shows.

### The prediction that was wrong, and why it was wrong

I sized this family from the answer key alone — four rows, all on `Duration`,
therefore one carrier. The rows are one carrier because the *witness file* is one
carrier: swift.org's test suite tests `Duration`, so of course all four sites are
`Duration`.

**The gap list counts test sites, not carriers.** A family's population has to be
measured against the corpus, never inferred from how many rows the adjudication
produced — that number is a fact about what someone chose to write a test for.

## 8.9 Running the known-properties traps against today's templates (2026-08-01)

`swift-infer known-properties --verify` reports **71/71 laws held** and 9 caveats
correctly failing. The catalog is live, not asserted — and the 9 caveats are a
curated **false-positive test set**: laws known to be false, executable, with the
counterexample explained.

Pointed at the four templates shipped today, it found a real defect in one run.

### The one that fired

`sequence-view-model-law` proposed `(a == b) == a.elementsEqual(b)` at **Strong 80**
on a carrier built to the trap *"Set: iteration order is not a property"*:

```swift
public struct HashBag: RandomAccessCollection, ExpressibleByArrayLiteral, Equatable {
    public var slots: [Int]
    public static func == (left: HashBag, right: HashBag) -> Bool {
        Set(left.slots) == Set(right.slots)
    }
}
```

Every conformance the discriminator keys on, and the law is flatly false: two values
equal under `Set` need not be `elementsEqual`.

**Both halves of the fix were already in the codebase.** §7.3 documented the hole —
*"a hash carrier that IS array-literal-expressible, which nothing in these corpora
happens to be"* — and `EqualityBodyClassifier` already classified the body
`conversionComparison(via: "Set")`. The template scored that **+20, the same as a
safe projection**.

Fixed by vetoing it: a conversion that is not sequence-preserving discards order or
duplicates, which is exactly a statement that `==` is **coarser** than the sequence
view. Scored-then-vetoed on the `protocolCoveredProperty` posture so `metrics` can
still count it. Real corpora unchanged (3 / 3 / 1 / 2 rows).

### The three that held

| template | trap carrier | verdict |
|---|---|---|
| `set-relation-model-law` | `Tally` — trap 4, `subtracting` not commutative | **safe** — it states membership implications, not commutativity |
| `bulk-incremental-agreement` | `Ledger` — trap 5, `merging` not commutative | **safe** — different law |
| `scaled-unit-consistency` | `Span` — traps 1–2, `+` not commutative | **safe** — different law |

Worth noting *why* they held: in each case the trap and the template state laws about
the same carrier but different operations. A trap set is a filter on carriers, not a
proof about laws, and reading a pass as "this template is sound" would over-claim.

### The process finding, which is the reusable part

**Run the traps before the corpus sweep, not after.** They are nine executable
false-law witnesses that ship with the product. Applied at the start they would have
caught this defect, and probably the `OptionSet.contains` and `Range` biconditional
failures too — three of the four discriminators derived the hard way today.

Cost: one synthetic file and one `discover` run. Compare with a corpus sweep, which
takes minutes and only finds carriers that happen to exist.

**And the traps reach where corpora cannot.** No real corpus contained a
`HashBag` — the hole was real, documented, and unreachable by measurement.
Adversarial construction is the only way to test a rule against the shape it was
written to exclude.

## 9. The `[reference]` list is the better backlog (2026-08-01)

`known-properties` ships **71 known-true laws, 49 tagged `[reference]`** — *"true and
self-verified under `--verify`, but invisible to `discover` because no template names
its shape."*

**That phrasing needs care, and my first summary got it wrong.** A reference law is
**already usable**: `--verify` executes it, and it works as a portability self-check
on the running toolchain. What is missing is not the law but the **transfer** — the
ability to look at a *user's* container and say it owes the same law.

So the measure of success for a template built from this list is *carriers reached
outside the catalog*, not "is the law true". That was already settled.

### 9.1 Stack / queue / deque — built

Five reference rows. `Stack`: *"push x then pop ⇒ x, and the stack is restored"*.
`Deque`: *"prepend(x) then removeFirst() yields x and restores the deque"*.

`EndedAccessRoundTripTemplate` states:

```
var copy = c; copy.append(x); copy.removeLast() == x && copy == c
```

**Gate 1 split, and the split is the interesting part.** The kit ships
`Deque.prependPopFirstRoundTrips` and `Deque.appendPopLastRoundTrips` — so the *Deque*
row is a double-report. But those are stated over the **concrete** `Deque<Element>`,
and the kit's own doc says why: *"no double-ended protocol exists to abstract over."*

That is the division of labour in one sentence. **The kit needs a type; `discover`
works from shape.** A user's own `RingBuffer` gets nothing from the kit and everything
from the template. The caveat tells a `Deque` carrier to prefer the kit.

**Two admission gates, and the second was found rather than designed.**

*Ends must match* — back-add with front-remove is a FIFO queue, where the law is false
for any non-empty container.

*Both halves must NAME an end.* The population sweep surfaced
`swift-nio`'s **`PriorityQueue: push/pop`**, where `push(x); pop() == x` is **false** —
`pop` returns the extremum. A bare `pop` names no end and cannot be assumed to take
one. Same shape as `OptionSet.contains` and `kilobytes`: a verb that looks
definitional until a carrier reinterprets it. Requiring positional names cost nothing
measured — `PriorityQueue` was the only bare pair in seven corpora.

**Measured: 15 rows over 11 carriers**, the widest reach of anything built today.

| corpus | rows | carriers |
|---|---:|---|
| swift-collections | 9 | `Deque`, `InputSpan`, `OrderedSet`, `RigidArray`, `RigidDeque`, `UniqueArray`, `UniqueDeque` |
| `stdlib/public/core` | 4 | `OutputSpan`, `OutputRawSpan`, `RangeReplaceableCollection`, `UniqueArray` |
| swift-nio | 2 | `CircularBuffer` |
| swift-foundation | 0 | — |

Ten of eleven carriers are outside the catalog — which is the number that matters.

### 9.2 Why this list beats the study's gap list

The swift.org gap list took a hand-adjudication pass over 36 sites to produce 19 rows,
of which 3 families shipped and 1 was declined for being a kit double-report.

The `[reference]` list is 49 rows that are **already known true and already
executable**, which pre-answers gates 2 and 3 before any work starts. On this family
the only open question was gate 1 — one grep — and the discriminator.

It was in the product the whole time. That is the fifth instance today of knowledge
sitting in the repo unconnected to the question being asked, and the cheapest one to
have avoided: `known-properties` is a shipped command with a documented `[reference]`
tag.

### 9.3 Functor identity — the second family from the reference list

Six `[reference]` rows: `Optional`'s map identity / composition / flatMap right
identity, and `mapValues` functor identity on `Dictionary`, `OrderedDictionary` and
`TreeDictionary`.

`FunctorIdentityTemplate` states `c.map { $0 } == c`.

#### One rule doing two jobs

**The return type must be the carrier.** That single requirement is both gates:

*Correctness.* `Set.map` returns `[T]`, not `Set<T>` — `s.map { $0 } == s` does not
typecheck. `Dictionary.map` is the same, which is exactly why the catalog states the
law over `mapValues`.

*Kit overlap.* `checkTransformationPropertyLaws` ships `Transformation.mapFusion` —
`sample.map(f).map(g) == sample.map { g(f($0)) }` — over **any `Sequence`**. So a bare
`map` on a sequence carrier is the kit's job. `mapValues` is not `Sequence.map`, so a
dictionary carrier is new surface *even though `Dictionary` is a `Sequence`*.

That distinction is the difference between 5 usable rows and 8.

#### The name fallback, forced by a measured admission

`LazyMapSequence.map` **is** `Sequence.map` and a double-report — but its `Sequence`
conformance lives in a conditional extension the scanner does not record, so a
conformance-only rule **admitted it**. Adding the `IdempotenceTemplate+IteratorVeto`
pattern — textual conformance primary, name suffix secondary — took the count from 9
to 8 and removed the only double-report.

That is the second time today the conformance index has been wrong in the
*permissive* direction. `stdlibConformances` was missing collections (§8.8-adjacent);
here a conditional extension is invisible. **The index is reliable when it answers and
unreliable when it does not**, so a rule keyed on it needs a decline-on-silence branch.

#### Measured: 8 rows, no double-reports

| corpus | rows | carriers |
|---|---:|---|
| `stdlib/public/core` | 4 | `Result` (×2, `map` + `mapError`), `Dictionary.mapValues` |
| swift-collections | 3 | `OrderedDictionary`, `SortedDictionary`, `TreeDictionary` |
| swift-nio | 2 | `EventLoopFuture`, `IOResult` |

Re-checked against the 9 traps: no trap carrier fires.

#### Identity, not composition, and the caveat says why

Composition is the stronger law — it catches a map correct at the identity function
and wrong on everything else. It is not proposed because it needs **two generated
functions** rather than a value, which is a generator capability rather than a
template shape. The caveat says so and tells a reader writing one law by hand to
write that one.

### 9.4 Registry housekeeping

Six family fan-outs in `collectModelLawSuggestions` pushed it past its cyclomatic cap.
Split one-helper-per-family rather than shaved: they share nothing but the name "model
law" — membership keys on a `contains` predicate, sequence-view on conformances, the
rest on curated verb tables.

## 10. Catalog health census (2026-08-01)

Prompted by finding that `HomomorphismTemplate` — a shipped template with a carefully
argued doc and a full exclusion list — fires **zero times**. If one template can be
dead without anyone noticing, the obvious question is how many others are.

Run: `discover --include-possible` over eight corpora (`stdlib/public/core`,
swift-collections, swift-foundation, swift-nio, swift-syntax, swift-package-manager,
SwiftProjectLint, this repo) — roughly 55,000 scanned functions — counting rows per
template against the 39 declared `templateName`s.

### The distribution

| rows | templates |
|---:|---|
| **0** | `diff-disjointness`, `homomorphism`, ~~`involution`~~, `multiplicative-homomorphism`, `partition`, `selection-subset` |
| 1–2 | `composition`, `caseiterable-case-coverage`, `caseiterable-key-injectivity`, `override-precedence`, `invariant-preservation`, `bulk-incremental-agreement` |
| 3–23 | `comparator` (3) … `set-relation-model-law` / `binary-idempotence` (23) |
| 48–1,598 | `commutativity` (48) … `idempotence` (**1,598**) |

**6 of 39 templates (15%) never fire. 12 of 39 (31%) produce two rows or fewer.**

> **Read that as "never fire ON THESE EIGHT CORPORA" — `involution` did not belong in the zero
> row even on the day this was written, and §10.5 has the measurement.** The number is a claim
> about a *scope*, and this table stated it as a property of the *template*. Nothing else in the
> distribution is retracted; the census was not re-run.

And the head is heavy: `idempotence` + `predicate` + `round-trip` = **2,724 of 4,102
rows, 66% of all output**. That is the quantitative form of the observation that the
tool "says the generic thing when it has nothing specific to say".

### Zero is indistinguishable from conservative, which is why this went unnoticed

A dead template and a correctly-silent one produce identical output. The catalog's
whole posture is high precision / low recall, so silence is the expected state and
nobody investigates it. `homomorphism` has been reaching nothing since it was written.

**This is the §7's four-kinds-of-silence problem applied to our own catalog.** The
study built that taxonomy for laws the tool misses in a *corpus*; the same blindness
applies to templates that miss *everything*.

### One cause is diagnosed; the other five are not the same story

`HomomorphismTemplate`'s gate is
`summary.parameters.count == 1 && isArrayShaped(param.typeText)` — a **free function**
`[T] -> Int`. Nobody writes `func count(_ xs: [T]) -> Int` in Swift; they write
`var count: Int`. The template was built for a shape the language does not use.

The member form has population: `Array`, `BitArray`, `RigidArray`, `IndexPath`,
`SyntaxCollection`, `BigString.UnicodeScalarView` — with `String` and `BigString`
excluded on the template's own existing reasoning (grapheme count is not additive
across a combining-character boundary).

**`InvolutionTemplate` does NOT share that cause** — it already handles a member form
(`containingTypeName` at line 104). So the six zeros are not one bug repeated, and
each needs its own diagnosis before anyone "fixes" them as a batch.

### What this suggests for process

A **catalog health census belongs in CI**, or at least in the road-test routine. It
costs one `discover` run per corpus and answers a question no existing mode does:
`metrics` aggregates *decisions* about surfaced rows, and `--stats-only` reports one
corpus. Neither can see a template that reaches nothing everywhere.

The census also reframes "add a template" as a decision with an ongoing cost: 15% of
what has been added so far is inert, and the inertness was invisible.

### 10.1 `homomorphism` revived — 0 → 5

The member form ships as `HomomorphismTemplate+MemberForm.swift`, under the **same**
`templateName: "homomorphism"` — it is the same law family, and the census should show
one template going 0 → N rather than a sibling appearing beside a dead one.

```
(a + b).count == a.count + b.count
```

| carrier | corpus |
|---|---|
| `Array` | stdlib |
| `BitArray`, `RigidArray` | swift-collections |
| `IndexPath` | swift-foundation |
| `SyntaxCollection` | swift-syntax |

**This table said 0 → 4 and omitted the swift-syntax row until §10.3 re-measured it.**
The under-count is self-inflicted in an instructive way: §10's own population list —
three paragraphs above — names `SyntaxCollection` among the member form's carriers. The
prose predicted five and the table recorded four, so the error was never in the
measurement, only in the transcription of it. A row count copied by hand from a run is
not a measurement; §10.3 exists because re-running is cheap and re-reading is not.

**The exclusions carry over verbatim and both were confirmed by the repo owner.**
`String` and `BigString` are out because `count` is grapheme count and `"e" + "◌́"` is
one grapheme, not two — the free-function doc had already reasoned this and it applies
unchanged. Set-like carriers are out because `|A ∪ B| <= |A| + |B|`, vetoed twice over
(a `SetAlgebra` conformance, and `formUnion` never counting as a free join).

**One over-exclusion is pinned as a known cost.** The grapheme test is textual, so
`BigString.UnicodeScalarView` — whose count *is* additive, because scalars do not
combine — is caught too. A missed law rather than a false one, which is the direction
PRD §3.5 asks for. Its test arm says so, and says that the arm going red means someone
made the rule structural, which would be an improvement rather than a regression.

### 10.2 What the revival says about the census

The fix was two hours of work and the diagnosis was one line of the existing gate. The
expensive part was **noticing** — and nothing in the toolchain was looking.

That is the argument for running the census periodically rather than once. `metrics`
aggregates decisions about rows that surfaced; `--stats-only` covers one corpus.
Neither can see a template that reaches nothing everywhere, and 15% of the catalog was
in that state.

Five templates remain at zero: `diff-disjointness`, `involution`,
`multiplicative-homomorphism`, `partition`, `selection-subset`. `involution` is known
*not* to share `homomorphism`'s cause — it already handles a member form — so each
wants its own diagnosis rather than a batch fix.

> **CORRECTED 2026-08-15: four, not five — `involution` was never in this list, and the witness
> was already in this repository when the list was written.** See §10.5. The surviving four are
> `diff-disjointness`, `multiplicative-homomorphism`, `partition`, `selection-subset`, **at zero
> on the eight census corpora as of 2026-08-01 and not re-measured since** — so read them as
> *unwitnessed*, not as *dead*, which is precisely the distinction this section spent three
> paragraphs establishing and then dropped one sentence later. (`partition` has since been
> measured from the other direction: `whole-to-parts-partition-declined.md` puts a third form at
> ~4% against a 70% bar, so its silence is diagnosed even though its count is not re-run.)

### 10.3 Did the template push actually gain laws? A controlled A/B (2026-08-01)

§10.2 argued for running the census periodically. This is the first time it was run
**as a before/after**, and the design matters more than the numbers: two binaries, one
built at `bc1b5f8` (the commit before the 2026-07-31 → 08-01 template push) and one at
`4eb0a3b`, both run **on the same afternoon over the same eight corpora with the same
flags** (`discover --sources <path> --stats-only --include-possible`).

Running both *now* is the whole point. The alternative — comparing today's run against
a count written down last week — cannot tell a template gain from a corpus that moved,
a config that changed, or a `.swiftinfer/` directory that acquired evidence between the
two readings.

**The concrete hazard turned out to be simpler and worse than any of those.** This
paragraph originally cited `SwiftInferCore` reading **96** in a prior session and **80**
today "with no scoring change in between" as measured drift. It was not drift. The 96
was taken with `--include-possible` and the 80 without: `discover --target SwiftInferCore
--stats-only` returns **80**, and the same command with `--include-possible` returns
**96**, on one binary, one afternoon, one corpus. The gap was entirely mine.

That is the more useful lesson, so it replaces the original claim rather than being
dropped. A remembered count carries no record of the **flags** it was taken with, and
tier visibility moves this tool's headline number by 20%. An A/B is immune not mainly
because it controls for the corpus — corpora rarely move — but because writing the
invocation once and running it twice makes the flags part of the measurement instead of
part of the memory.

| corpus | `bc1b5f8` | `4eb0a3b` | delta |
|---|---:|---:|---:|
| stdlib | 786 | 797 | **+11** |
| swift-collections | 701 | 715 | **+14** |
| swift-nio | 400 | 409 | **+9** |
| swift-foundation | 1,283 | 1,284 | +1 |
| swift-syntax | 1,121 | 1,122 | +1 |
| swift-package-manager | 598 | 598 | 0 |
| SwiftProjectLint | 3 | 3 | 0 |
| this repo | 247 | 247 | 0 |

**+36 rows, and the diff is pure addition — no template lost a single row.**

Attributed by template, the gain is exactly the four families added in that window:

| template | rows | where |
|---|---:|---|
| `ended-access-round-trip` | 15 | stdlib 4, collections 9, nio 2 |
| `scaled-unit-consistency` | 8 | stdlib 3, nio 5 |
| `functor-identity` | 8 | stdlib 3, collections 3, nio 2 |
| `homomorphism` (member form) | 5 | stdlib, collections ×2, foundation, syntax |

Two of those totals were already recorded — 15 and 8 — and reproduce exactly, which is
the useful kind of boring. The third did not: §10.1's table said 4 where the measurement
says **5**, corrected above.

**The tier split is the part worth keeping.** 23 of the 36 are `Strong` — every
`ended-access-round-trip` and `scaled-unit-consistency` row — and the remaining 13 are
`Likely`. None landed at the score-20 `Possible` floor. Against the standing complaint
that the catalog "says the generic thing when it has nothing specific to say" (66% of
output is three templates, 738 of 1,115 swift-syntax rows sit at the floor), a push that
adds only default-visible rows is the shape the Daikon trap entry asks for: the gain
arrived by naming shapes, not by lowering a cut.

**The #26 traps veto cost zero rows.** `sequence-view-model-law` and `model-law` are
byte-identical across all eight corpora before and after. The veto was found by a
synthetic trap file rather than by a corpus sweep, and this confirms the reason given at
the time — no real corpus contains the `conversionComparison` shape. A precision fix
with no measured recall cost, which is the outcome §3.5 wants and rarely gets to verify.

**Three corpora gained nothing**, and that is not a defect: swift-package-manager,
SwiftProjectLint and this repo have no stack/queue/deque carriers, no scaled-unit
constructors, and no `map`-returning-Self containers. A template that fires on shapes
absent from a corpus is correctly silent there — the §10 distinction between a dead
template and a conservative one, now with the A/B that can tell them apart.

### 10.4 How many property tests does the toolchain actually yield on THIS repo?

A different question from §10.3's, and the one an adopter asks. Not "how many rows does
`discover` emit" but "how many property-based tests do I end up with".

Whole repo, one pass over `Sources/`, default visibility, **deduplicated by identity**:

| tier | rendered | distinct |
|---|---:|---:|
| Strong | 7 | **3** |
| Likely | 19 | **19** |
| Possible | 139 | 139 |

**22 laws worth writing** (3 Strong + 19 Likely) — `codable-round-trip` 8,
`associativity` 6, `commutativity` 5, `differential-equivalence` 2,
`invariant-preservation` 1. The persisted index of 2026-07-31 records 3 Strong + 20
Likely, so the figure has been stable in the low twenties across a week of template work.
That stability is consistent with §10.3: the four new families target container and
unit-constructor shapes this repo does not have.

The other 139 default rows are almost entirely `predicate` totality laws surviving below
the cut under `3e38e34` (*a law the code OWES is never hidden*). Real, and not what
anyone writes first — the `predicate-display-order` doc exists because of exactly this
ratio.

**Two defects, both found by asking for a per-target breakdown.**

1. **A lifted row is emitted five times.** Identity `0x17DFFF16631D81B7`, a
   `differential-equivalence` law lifted from a test body, renders 5× per run with
   byte-identical output — same identity, same score, same explainability. The dedup gap
   is 4 rows and it lands **entirely in the top tier**, inflating Strong from 3 to 7.
   A duplicate is worse here than elsewhere: `Strong` is the tier a reader is told to
   trust, and 4 of its 7 rows are one law wearing a hat.

2. **Test-body lifting is not scoped to `--target`.** The same 4 lifted identities appear
   under *every* target. `swift-infer` is a single file (`SwiftInferEntry.swift`) and
   reports 8 Strong suggestions — identical, identity for identity, to
   `SwiftInferMacro`'s. So **per-target counts are not additive**; summing the seven
   targets gives ~203 against a true 174. Anyone building a dashboard by summing
   `--stats-only` over targets will over-report, and the error is invisible because each
   individual run looks reasonable.

Both are counting bugs rather than inference bugs — the laws themselves are fine — which
is why neither showed up in a year of reading `discover` output one corpus at a time.

> **Item 2 is FIXED — re-measured 2026-08-15 at `3548db4`: the over-count is 0.4%, not 17%.**
> Collecting `Identity:` hashes per target over a seeded run of all eight targets and taking
> the distinct set gives **1,895 naive → 1,888 distinct, 7 rows**, with three identities
> appearing under more than one target. The cause is `TestTargetScope` (2026-08-08), which
> scoped test-lifting to the test targets that *transitively depend* on the scanned target —
> precisely the population this item's over-count was made of. **Summing `--stats-only` over
> targets is now defensible to within half a percent**, so read this warning as closed rather
> than obeyed.
>
> **The residual 7 is not a bug and should not be chased.** Transitive dependency is a sound
> over-approximation, as `roadtest-self-dogfood-2026-08-08.md` §1.1 states: a law authored in a
> test target still lands on every target that target depends on, and closing that needs the law
> attributed to the target declaring the symbol it names. Three identities is what that
> approximation costs here.
>
> Item 1 (the duplicate `Strong` rows) is **not** re-measured and is not covered by this note.

### 10.5 `involution` was never dead, and the witness predates the census (2026-08-15)

**Measured.** `discover --target ComplexModule` on **swift-numerics @ `899af71`** — the
revision `fixtures/corpora/manifest.json` pins for that corpus, in a fresh `git worktree` so
`.swiftinfer/` is absent by construction:

```
Template: involution
  ✓ Involution verb match: 'conjugate' — applying it twice returns the original (+40)
  ✓ Proven analog: `Complex` satisfies `z.conjugate.conjugate == z`
```

**1 pick, and it is a DEFAULT-tier row** — not rescued by `--include-possible`, which was
checked separately because a `--include-possible` count is a different number (§10.3's own
warning). `RealModule` and `IntegerUtilities` are 0, so the population is one declaration.

**A second, independent witness landed 2026-08-14**: GRDB @ `b83108d10`, **8 involution
proposals, 1 Proven** (`EqualityOperator.negated()`) —
`exploratory-swiftformat-grdb.md` §7.3, which called it *"fired for the first time"*. That
framing is generous to this section and wrong on the facts: it was the first time on a corpus
anyone was watching.

**Neither corpus was among the census's eight.** That is the whole mechanism, and no code
changed to produce either row.

#### The part worth keeping: the refutation was already in the repository

`dogfood-new-templates-findings.md` carries a header update dated **2026-07-15** — a
fortnight *before* this census — recording Epic 1 making the scanner surface read-only
computed properties as nullary `self -> T` summaries, *"so involution now fires on
`Complex.conjugate` (verified: +1 pick on real swift-numerics ComplexModule)."* Same corpus,
same target, same declaration, same count. The census then filed `involution` under *never
fires*, and §10.2 repeated it, and CLAUDE.md's index row quoted §10.2.

**Nothing joined the two documents, and one of them is internally inconsistent**, which is
why reading could not settle it: that doc's *header* says involution fires on
`Complex.conjugate`, and its *body table* — three screens down, under an `As of 2026-07-18`
that postdates the header — records `involution … 0` for `ComplexModule`. The body table is
the pre-Epic-1 measurement and was never re-run; the header is right. **This is the
detail-maintained / summary-stale shape inverted** — here the *summary* was updated and the
*detail* was left, and an index quoting either one had a 50% chance of being wrong.

#### What this does and does not change

- **Does not** re-run the census. The distribution table's other rows stand as measured on
  2026-08-01 over those eight corpora.
- **Does** move the dead list from five to four, and reframes those four as *unwitnessed on a
  known corpus set* rather than *inert*.
- **Does not** ask for any change to `InvolutionTemplate`. It is correct, it is narrow, and
  §10's own note that it *"does NOT share `homomorphism`'s cause — it already handles a member
  form"* was right for a reason it did not know: the template was not broken, so there was
  nothing for a member form to fix.

#### The process finding

§10 argued a catalog health census *"belongs in CI"*. This is the sharper version of that
argument, and it is not about frequency: **a census is only as wide as its corpus list, and
its zero row is the one cell that cannot be trusted without knowing that list.** A template
with a witness in a ninth corpus is indistinguishable, in this table, from one with no witness
anywhere — and the repo held the ninth corpus, registered, pinned, and already measured.

The corpus registry (`fixtures/corpora/README.md`) is what makes the denominator checkable at
all; its own entry for swift-algorithms says as much — *"registered so the sweep's denominator
is checkable: the finding that 6 of 39 templates never fire depends on which corpora were in
it."* **That sentence was written about this exact number and did not prompt anyone to check
it.**

**And checking it surfaced a second discrepancy — now RESOLVED 2026-08-15, in this section's
favour.** Four registry entries claimed membership in *"the eight-corpus catalog-health sweep"* —
`swift-nio`, `swift-algorithms`, `swift-argument-parser`, `swift-effect-inference` — and only
`swift-nio` was in it, while `swift-package-manager` was a member with no registry entry at all.

**§10.3 settled it, and that is the argument for having written it that way.** This section's
prose names the eight; §10.3's A/B table names them *with a row count each*. A summary can drift;
**an eight-row table of measured numbers cannot**, because every row would have to drift
together and stay internally consistent. The two agree exactly, so the registry was wrong on all
four counts and is corrected:

- `swift-algorithms` — its pin `ff223da` is the **swift.org study's corpus survey** table,
  verbatim (Tier 3: 8 `check*`, 0 loops). Re-filed there.
- `swift-argument-parser` — the whole-to-parts half of its `why` was true; the census half was not.
- `swift-effect-inference` — *"17 rows, unchanged with the coverage veto disabled"* is the
  **coverage-veto A/B**, a different measurement over a different six corpora, now `discover-ab`.
  **Its only record anywhere is CLAUDE.md's `ProtocolCoverageAudit` row** — no doc under `docs/`
  carries it.
- `swift-package-manager` is registered, revision recovered from its reflog (one entry, the
  2026-03-13 clone, no `FETCH_HEAD` — the tree could not have been anything else on census day).

**The structural remedy proposed here was tried and does not work.** *"Name the corpus list by
registry id and let `swift-infer corpus` print it"* founders twice: five of the eight have no
recorded revision for 2026-08-01, so per-member census measurements would need five `null`s, and
`null` is only worth having while it is rare enough to read as a flag; and `census` is the
apparatus of *several* sweeps, so `--apparatus census` selects seven corpora that are not these
eight. What would work is recording the corpus list **at run time, by id, as part of the sweep** —
a change to how a census is run, not to where its denominator is written down afterwards.

> **BUILT 2026-08-15 — `swift-infer census`** (`docs/reference/census-command.md`). It surveys
> corpora named by registry id and writes the list into the artifact alongside the counts, with
> each checkout's run-time revision, its dirty flag, and the pipeline flags. So the next census
> carries its own denominator and this section's excavation does not have to be repeated.
>
> **It does not repair this one.** The denominator of a sweep taken by a shell loop is not
> recoverable by building a better loop, so §10's eight remain established the way they were —
> by reading §10.3's per-corpus table against the prose. The value here is prospective only, and
> saying otherwise would be the same over-claim this section is correcting.
>
> Two things fell out of building it, both recorded in the command's doc. A census scans a
> **directory** while `prove-then-show` builds a **target**, which the registry did not model:
> `swiftlang-swift` claimed `target: "stdlib"` and the compiler repo has no `Sources/` at all.
> And routing a census at a path that does not exist failed with *"the file couldn't be opened
> because it isn't in the correct format"* — a decode error from a missing directory, which is
> now a refusal that names the path.

## 11. The `[reference]` backlog was over-reported 3x — the tags had fallen behind the templates

§9 called the 49 `[reference]` rows "the standing catalog backlog". That number was
right when written and wrong by the time it was cited. On 2026-08-01 a re-tag took it
to **15** (14 laws + 1 caveat), without adding a single template.

**34 rows named a law a shipped template already stated.** The tags had simply never
been updated.

### 11.1 Why it was invisible

`CuratedEntryRole`'s doc says the role "is DERIVED from `template`, so it cannot drift:
the day a shape gets a template, its entries stop being reference and start anchoring."

The derivation is real — `law()` computes `role` from `template`. But it guards the
wrong join. **The role cannot drift from the tag; the tag drifts from the template
catalog**, and nothing watched that. The mechanism built to prevent drift prevented the
half that was never going to happen.

The giveaway was sitting in the file the whole time: `Array`'s "count is additive over
concatenation" carried `template: "homomorphism"`, and `Deque`'s **identical** law
carried nothing. Two carriers, one law, one tag — which makes it an oversight rather
than a policy.

There is also no runtime registry to check a tag against. `TemplatePack.allTemplateNames`
resolves to **10** names (packs are a `--packs` filter, and the set omits `involution`
and `homomorphism`, both tagged for months); `TemplateName` has **17** cases against ~89
template files. A test asserting "every tag names a real template" fails on correct tags
under either oracle. That absence is a large part of why this went unseen.

### 11.2 Cost, in both directions

**Output.** `StdlibAnchor` keys on `entry.template == candidate.templateName`, so an
untagged row is invisible to `discover`. Measured on a synthetic `Stack` with
`append`/`removeLast`: **0 "Proven analog" lines before the re-tag, 2 after.** The
`Stack` and `Queue` rows state in their own comment that they exist "so the stdlib
anchor has a ground truth to match a discovered `push`/`pop` pair against" — and they
could not, for want of a tag.

**Planning.** The `.reference` count is the backlog metric. Reporting 49 when the true
figure was 15 pointed work at rows already covered.

### 11.3 The 14 that stay, and one that must

Three groups. Most are "no template names this shape" — `Set` distributive lattice,
absorption, relative De Morgan; `TreeSet` value semantics; `OrderedSet` order
preservation.

Two are **near-misses worth naming**, because both look taggable and are not:

- **Functor composition** (`Optional`, `Dictionary`). A `composition` template exists,
  and it states a *different* law — two sequential mutating additive-monoid actions
  equal one combined call. Functor composition needs two **generated functions**, a
  generator capability rather than a template shape.
- **The two `Heap` model laws.** `ModelLawTemplate`'s abstraction function is
  `contains`. `Heap` drains to a sorted **array** — an ordered model — and `Heap` is not
  a `Sequence`, so `sequence-view-model-law` does not reach it either.

And one row must **never** be tagged: `OrderedSet` "commutative under membership (NOT
under order)". Tagging it `commutativity` would attach a proven-analog line to a
commutativity candidate on `OrderedSet`, whose `union` is **not** commutative under
`==` — it keeps the left operand's order. The row states the coarser membership
equality only, and the anchor prints the statement without that distinction. A harmful
tag, not a missing one — and the reason the sweep was done per-row rather than by
pattern-match.

### 11.4 The guard

`CatalogTemplateTagDriftTests` pins the reference set **explicitly**: every `.reference`
law must appear on an allowlist carrying the reason no template states it. A new
untagged law fails; a newly tagged row fails until its allowlist entry is removed. The
residual-set-by-default behaviour is what allowed 34 rows to accumulate silently.

