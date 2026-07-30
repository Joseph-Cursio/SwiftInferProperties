# Findings — the swift.org property-style-test study

Companion to `swiftorg-property-test-study-scope.md`, which is the plan. This is the
record. **Every number here carries the corpus SHA it was measured at**; a count without
one is not a measurement (scope §3).

**Status: Q1 (§1.1), Q2 (§1.15) and Q5 (§1.5) answered on the `check-battery` population.
Q3/Q4 not started.**

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
| **`ProtocolCoverageMap`** | **cannot record it** — has no `LosslessStringConvertible` entry, so the decline is inexpressible |

**No behavioural symptom.** Adding the protocol to the coverage map would change nothing
today: the veto only fires on a proposed suggestion, and the pair never forms. The symptom is
epistemic — we cannot currently distinguish *"we decline this because the kit runs it"* from
*"we miss this"*, which is precisely the confusion that produced two wrong verdicts earlier
in this study.

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
nothing to key a veto on), **20 uncovered with no symptom**, and **1 live double-report**.

The test asserts a *decision* rather than coverage — a new kit suite lands unclassified and
fails, which is the drift nothing could previously detect. Verified it can fail by removing a
disposition and watching it go red. The `Strideable` entry is pinned by its own assertion, so
closing the defect turns the suite red as the signal to delete it.

**Verdict for this law: `declined` in substance, by accident in mechanism.** The toolchain
runs it; `discover` stands aside for a reason unrelated to the division of labour, and cannot
say so.

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
