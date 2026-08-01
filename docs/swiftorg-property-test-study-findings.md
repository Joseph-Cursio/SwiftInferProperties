# Findings — the swift.org property-style-test study

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

**Adjacent, and deliberately not touched:** `OrderSensitiveCarrierNames` is a
six-name curated denylist whose own doc says it stands in for *"structural
order-sensitivity detection pre-SemanticIndex"*. This is that detection, and
`CommutativityTemplate`'s veto still uses the denylist. Same predicate, opposite
polarity — commutativity vetoes *on* an ordered carrier, the model law *requires*
one. Migrating that veto is its own change with its own measurement.
