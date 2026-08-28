# Screening candidates against §6.1 — the pool, two subjects, and a third real defect

> **Status:** `measured` · **As of:** 2026-08-28

**The local subject pool is exhausted, and that is now measured rather than asserted.** 63
subjects screened; after excluding the manifest and every subject named across `docs/`, the
best remaining on-disk candidate with any hand-written `Codable` ∩ `Equatable` carried **3
types and 275 C files**.

Two cloned subjects cleared every clause and were run:

- **`OpenAPIKit` refutes on shipped code.** `OpenAPI.XML` fails `codable-round-trip`, the
  defect is **real**, reproduced by execution, and their **2,147 tests pass** without it. That
  is a **third real defect, on a third independent codebase, and all three are
  `codable-round-trip`**.
- **`SymbolKit` gives the best reach reading ever taken — 21 of 27 rows reach the build
  stage — and converts almost none of it**, because **16 die inside our own emitted stub**.
  Two defects here, one of them a decline wearing a build failure's name.

⚠ **Named for what it is, not for a count.** The two predecessors are
`refutation-rate-second-subject.md` and `refutation-rate-third-fourth-subject.md`, and
continuing that series would put *fifth-sixth* in a filename — the mistake
`catalog-health-census.md` was renamed to fix three days ago. A count belongs in the body,
where it can be dated and re-taken.

---

## 1. The instrument, and why it is not a grep

`scripts/screen_candidates.py`, built **on** `scripts/measurement.py` rather than beside it.
That module's `declares_custom_codable` exists because instrument **#6** answered this exact
question with a 40-line window and read **7 of 14** where the truth was **14 of 14** — a
conformance written in a separate `+Codable.swift` extension is invisible to a line window and
Swift codebases put them there constantly.

**Validated on three controls before use, against figures already published:**

| control | published | this instrument |
|---|---|---|
| `jwt-kit` @ `8189d7c` | 74 source files · **6** hand-written | 74 · **6** |
| `swift-openapi-runtime` @ `643f3d6` | 71 source files · **5** hand-written | 71 · **5** |
| `lottie-ios` @ `3a7fb59` | 285 source files · **5** in the intersection | 285 · **5** |

All three checkouts sit at exactly the pinned revisions. **The column in use reproduces to the
digit on every one.**

⚠ **One disagreement, stated rather than smoothed.** On `lottie-ios` the *separate* conformance
counts do not reconcile — §6.1 records **32 Codable / 48 Equatable**, this instrument reads
**47 / 44**. The intersection is 5 either way. It is not chased because the amended clause is
that **the separate counts are the wrong number**; recording the disagreement is cheaper than
resolving it and keeps the next reader from treating 32/48 as reproducible.

**Two file counts are reported, not one.** `swift_files` walks the whole tree minus
`EXCLUDED_DIRS` (84 for `jwt-kit`); `sources_swift_files` counts `Sources/` (74). The published
tables use the narrower one. Labelling either with the other's number is instrument **#2**'s
shape exactly.

---

## 2. Two blind spots in the screen itself, both found mid-pass

**Neither was predicted. Both are recorded because a screen that has never been wrong has
not been used.**

**(1) It required `Package.swift` at the repo root** — so `IceCubesApp`'s **13 packages under
`Packages/`** were invisible. That is instrument **#7**'s exact shape: the availability join
that read `sources[0]` and never saw `Packages`, recorded four days earlier in this same
repository. Re-enumerating found **6** repos holding ≥20 `.swift` files with no root manifest,
and one of them was the best on-disk candidate.

**(2) The spent-subject check greps the DIRECTORY basename.** `~/GitHub_projects/swift-sdk` is
`modelcontextprotocol/swift-sdk` — that is **`mcp-swift-sdk`, the subject A-quality was met
on** — and it scored the highest hand-written count in the whole sweep at **21**. It was caught
only because `"swift-sdk"` is a substring of `"mcp-swift-sdk"`. **A directory named `mcp` would
have read zero mentions and passed**, and the contaminated result would have looked like the
best find of the pass. §7 turns this into a clause.

---

## 3. The pool, decomposed

| | count |
|---|---:|
| Swift packages on disk with a root manifest | 67 |
| disqualified as manifest corpora | 17 |
| screened (3 cross-root duplicates collapsed) | **47** |
| repos with no root manifest, ≥20 `.swift` files (§2.1) | **6** |
| cloned deliberately, this pass | **10** |
| **total subjects screened** | **63** |

**Of the 47 on disk, exactly one zero-mention candidate had any hand-written intersection:**
`indexstore-db`, **3 types and 275 C files**, disqualified by §6.1's no-C-interop clause.
Everything else with a usable count was already in the manifest or already spent.

**So the claim in `refutation-rate-third-fourth-subject.md` §5 — *the local pool is now
exhausted* — is confirmed, and it was worth re-taking rather than carrying**: the check that
confirmed it is the same one that surfaced `IceCubesApp` and the `swift-sdk` near-miss, neither
of which was visible from the assertion.

---

## 4. The two subjects that were run

| | `OpenAPIKit` | `SymbolKit` |
|---|---|---|
| revision | `651cc55` | `c1f9484` |
| in manifest / prior mentions | no / **0** | no / **0** |
| source files · C files | 196 · **0** | 55 · **0** |
| macOS floor declared | `.v10_15` | *(none — builds anyway)* |
| hand-written `Codable` ∩ `Equatable` | **9** | **10** |
| index rows | 97 | 27 |
| **rows reaching the build stage** | 15 (15%) | **21 (78%)** |
| **rows reaching a VERDICT** | **5** | **5** |
| verdicts | 4 pass · **1 refutation** | 5 pass · 0 refutations |
| `codable-round-trip` rows | 34 | 21 |

⚠ **THE TWO READINGS ARE DIFFERENT NUMBERS AND THIS DOCUMENT QUOTES BOTH.** A
`measured-error: build-failed` row **reaches the build stage and yields no verdict about the
law**. Counting it as a verdict overstates OpenAPIKit by 3× (15 against 5). This was gotten
wrong once in-session and corrected before it was written down.

⚠ **A consequence for §6.1: the published pre-check figures cannot be compared to these
without knowing which of the two they counted.** `jwt-kit`'s **17 of 35** is recorded as *rows
reaching a verdict*, and 12 `codable-round-trip` rows are separately recorded as yielding 6
passes and 1 refutation — 7 verdicts. Whether the other 10 were verdicts or errors is not
recoverable from the table. **The pre-check's threshold is only as meaningful as the reading it
names**, and that is unresolved, not resolved here.

### 4.1 The first OpenAPIKit run read 0 of 33, and the cause was the target

Indexing `--target OpenAPIKitCore` — an **internal target, not a vended library product** —
produced 33 rows, **0 verdicts**, and **13 declines reading `unsupported-carrier:
OpenAPIKitCore is not a library product of OpenAPIKit`**.

**The true cause is target selection and it was reported under the carrier label.** Fifth
instance of *a decline bucket's NAME is not its cause*, and the same shape as the swift-system
misdiagnosis where **21 of 36** carrier declines were module resolution. Re-running against the
vended `OpenAPIKit` product gave the 97-row reading above.

---

## 5. The third real defect — `OpenAPI.XML`

**Row:** `codable-round-trip` · `OpenAPI.XML.encode(to:)` · `measured-defaultFails` at
**trial 5** · tier `Likely`.

**Counterexample:** `XML(name: Optional(""), namespace: nil, prefix: nil,
conditionalWarnings: [], structure: Optional(.legacy(attribute: false, wrapped: false)))`

### 5.1 The mechanism, traced end to end

`OpenAPI.XML` has two public initializers. The **legacy** one sets
`structure = .legacy(attribute:wrapped:)` **even when both are false**; the `nodeType:` one
sets `structure = nodeType.map(Structure.nodeType)`, so `nil` for a `nil` node type.

- `encode(to:)` on `.legacy(false, false)` writes **nothing** — both `if attribute` and
  `if wrapped` are false, so neither key is emitted.
- `init(from:)` reads `(attribute: false, wrapped: false, nodeType: nil)`, hits
  `case (false, false, nil)`, and sets `structure = **nil**`.
- `==` compares `lhs.structure == rhs.structure`, and `Optional(.legacy(false, false)) != nil`.

### 5.2 Reproduced by execution, not by reading

A temporary probe against the package (written, run, deleted):

```
json      : {"name":"x"}
original  : Optional(.legacy(attribute: false, wrapped: false))
decoded   : nil
equal     : false

bytes-identical: true    equatable-says-equal: false
```

So **`XML(name:"x", attribute:false, wrapped:false)` and `XML(name:"x", nodeType:nil)` encode
to byte-identical JSON and are `!=`** — and the first of them does not survive its own round
trip.

**This is the `ToolChoice` mechanism**: two distinct values encode identically while `Equatable`
distinguishes them. `codable-round-trip` refutes exactly when `Codable` and `Equatable` disagree
about identity, which is now observed on three codebases.

### 5.3 Their tests miss it, and the near-miss is the interesting part

**`swift test` on `OpenAPIKit` @ `651cc55`: 2,147 tests, 0 failures.**

`XMLTests.test_empty_decode` asserts `decoded == OpenAPI.XML()` **and passes** — because bare
`XML()` resolves to the `nodeType:` overload, whose `structure` is `nil`. Their legacy coverage
(`test_completeLegacy_*`) uses `attribute: true, wrapped: true`. **They test legacy with both
flags true and empty via the other initializer; the one combination that breaks — legacy with
both flags false — is the gap between the two tests they wrote.**

### 5.4 The tally

**30 hand-checked · 3 real · all three `codable-round-trip`, on three independent unmet
subjects, each missed by the subject's own suite.** `idempotence` remains **0 real of 18**.

⚠ **Still not a rate, and the reason is unchanged.** Nine of the twelve `codable-round-trip`
hand-checks remain one mechanism from one generated codebase. Deduplicated by mechanism this is
nearer **3 real of 5 distinct mechanisms** — a stronger reading than last pass and still far too
small to quote as a precision.

---

## 6. Two defects in our own emitter, found by the stubs that did not compile

**16 of SymbolKit's 21 build-stage rows and 10 of OpenAPIKit's 15 failed to compile.** They are
not one cause.

### 6.1 `codable-round-trip` is missing from the equatable gate — 6 rows

`VerifyCommand+TemplateDispatch.swift:367`:

```swift
static let equalityShapedTemplates: Set<String> = ["inverse-pair", "identity-element"]
```

`codable-round-trip`'s emitted law is `decode(encode(x)) == x`. **It needs `==` and it was never
added to the set.**

SymbolKit's `SPI`, `Snippet`, `Availability`, `FunctionSignature` and `Endpoint` conform to
`public protocol Mixin: Codable` — **no `Equatable` anywhere in the chain** — so the stub emits
`!=` on a type that has none and the compiler rejects it. The gate's own doc comment states the
joining criterion: *"A template joins when someone has looked at its emitted law and seen the
`==`."* This one meets it on sight.

**The screen excluded all five types correctly, so the tool's belief is the wrong one** — which
is what makes this a defect rather than a disagreement.

**Payoff, stated as ROWS MOVED and not laws gained: 6 rows move from `measured-error:
build-failed` to `carrier-not-equatable`, and 0 laws are gained.** A reporting-correctness fix
of the same kind as the availability gate: it stops a **real static decline from wearing a build
failure's name**, which currently reads as *our emitter is broken* when the truth is *the law is
unstatable on that carrier*. **Population across the corpora is UNMEASURED** — 6 is one
subject's figure and this project's decline-to-rows ratio does not apply to it, because nothing
is being freed.

⚠ **Not fixed here.** Filed as `open-threads.md` row 67 with the fix named.

#### The one-line fix is REFUTED — measured 2026-08-28, and not shipped

**Adding `"codable-round-trip"` to `equalityShapedTemplates` and stopping there would wrongly
decline 20% of the template's carriers.**

`TypeShapeBuilder.swift:170` merges conformances from **same-file extensions only**, so
`extension Foo: Equatable` in a separate `Foo+Equatable.swift` never reaches
`shape.inheritedTypes`. The gate fires on *absence of an equality token in the shape*, which
for those types is absence of evidence rather than evidence of absence.

**Measured across the 20 manifest corpora plus both subjects — 136 hand-written `Codable` ∩
`Equatable` types, and 27 (20%) get their equality ONLY from a cross-file extension:**

| corpus | cross-file | named |
|---|---:|---|
| `swiftlang-swift` | 11 | `Array`, `Optional`, `Dictionary`, `String`, `Set`, `UInt128`, … |
| `swift-collections` | 9 | `OrderedSet`, `OrderedDictionary`, `Deque`, `BitSet`, `BitArray`, `TreeSet`, … |
| `swift-package-manager` | 3 | `Triple`, `State`, `PackageReference` |
| `swift-foundation` | 2 | `Expression`, `Argument` |
| `swift-nio` | 1 | `ByteBuffer` |
| `OpenAPIKit` | 1 | `Either` |
| **total** | **27 of 136** | |

**Those are the prime carriers.** The naive fix would suppress the only template that has ever
found a real defect, on the collection types most likely to carry one. **A fix that costs 27
rows to correct 6 is not a fix.**

⚠ **The gate is SOUND where it fires today, checked rather than assumed.** OpenAPIKit's two live
`carrier-not-equatable` declines are on `EitherDecodeNoTypesMatchedError.IndividualFailure`,
which is declared `: Swift.Error` with no equality conformance anywhere in the package. **This
is a finding about EXTENDING the gate, not about the gate.**

#### What a correct fix needs, and why `EquatableResolver` is not quite it

`TypeShapeBuilder`'s own docstring names the missing piece: *"The M3.3 `EquatableResolver`
reaches into raw `TypeDecl`s for cross-file conformance evidence; the strategist's shape doesn't
need it."* That resolver **exists**, is built from all `TypeDecl`s, explicitly handles
`extension Foo: Equatable` *"declared in a separate file"*, and carries the three-state
`.equatable / .notEquatable / .unknown` model the gate's docstring claims to want.

**It has ZERO consumers in `Sources/`** — one doc-comment reference in `ProtocolCoverageMap` and
nothing else. Another instance of the shape row 28 named: a component that answers the question,
consumed by nobody.

**But its tri-state cannot carry this gate either, and the reason is specific.** A plain struct
with no equality conformance classifies `.unknown`, not `.notEquatable` — `isProvablyNonEquatable`
covers function types, `Any`, `AnyObject` and existentials, not "nothing declared it". Firing
only on `.notEquatable` would leave all 6 SymbolKit rows exactly where they are.

So the negative half has to be *`the type is corpus-local, every declaration and extension of it
was scanned, and none declares equality`* — decidable, and **needing one thing the resolver does
not do: transitive closure through corpus protocols.** SymbolKit's carriers conform to
`public protocol Mixin: Codable`; had it been `Mixin: Hashable`, every one of them would be
`Equatable` with no equality token on the type itself. A negative that skips that step trades
this false-decline class for another.

**Estimated shape of the real fix**, recorded so the next attempt does not restart from the
one-line version: a tri-state computed at INDEX time (where all `TypeDecl`s are in hand),
carried on `IndexedTypeShape` as an additive `decodeIfPresent` field like `enumCases` before it,
consumed by the gate, with the positive side from `EquatableResolver` and the negative side
requiring protocol-chain closure. **Not one line, and not attempted here.**

### 6.2 The other shapes

| subject | compiler error | rows |
|---|---|---:|
| SymbolKit | `incorrect argument label in call (have 'textFragment:', expected 'from:')` | 5 |
| SymbolKit | `type 'SymbolGraph.Symbol.Swift.GenericConstraint.Kind' does not conform to …` | 4 |
| SymbolKit | `missing argument for parameter #2 in call` | 1 |
| OpenAPIKit | `reference to generic type 'JSONReference' requires arguments in <…>` | 5 |
| OpenAPIKit | `call can throw, but it is not marked with 'try'` | 4 |
| OpenAPIKit | `missing argument label 'for:' in call` | 1 |

**None is diagnosed here.** They are recorded because *whether the emitted code compiles* was
measured zero ways for nine cycles, and 89% of one subject's output once failed to build without
anyone noticing.

---

## 7. Three clauses §6.1 does not have

Each was paid for in this pass rather than reasoned to.

1. **The subject must build for the HOST.** `IceCubesApp/Packages/Models` had the best on-disk
   hand-written count (**9**) and declares no macOS platform, so it defaults to 10.13 against
   `SwiftSoup`'s 10.15 and `swift build` fails outright. Every row would have reported
   `build-failed`, which CLAUDE.md warns *reads as an architectural limitation rather than a
   broken manifest*. **The cheap check is reading `platforms:`; only an actual `swift build`
   settles it**, because a dependency can out-require a declared floor — which is exactly how
   this one failed. Now computed by the screen.
2. **Index a VENDED LIBRARY PRODUCT, not an internal target.** §4.1: 33 rows, 0 verdicts, and
   13 declines wearing the carrier label.
3. **The spent-subject disqualifier must key on MEASURED, not on MENTIONED.** Two independent
   problems. It reads the directory basename, so a subject whose docs name differs from its
   directory passes (§2.2, caught by coincidence). And **publishing a screen spends every
   candidate it names** — this document names `swift-docc`, `supabase-swift`, `soto-core`,
   `postgres-nio`, `apollo-ios`, `BigInt`, `vapor` and `algoliasearch-client-swift`, none of
   which has been measured against. The rule's intent is *not previously measured*, and the
   letter of it now disqualifies subjects for having been screened. **Read §8's list as
   AVAILABLE, not as spent.**

---

## 8. What is left, and how to read it

**`swift-docc` @ `f160765` was the richest candidate found — 46 hand-written, 552 source files,
0 C files, 0 mentions on five independent tokens, macOS `.v13` — and it has since been RUN.**
`docs/measurements/subject-swift-docc.md`: **267 rows, 49 verdicts, 13 refutations**, ten times
any previous subject's verdict count, and **a fourth real defect that breaks the
one-mechanism generalisation** — `CatalogFeatureFlags`'s decode THROWS on its own encoder's
output, so `==` is never reached. The screen's ranking was borne out.

**`algoliasearch-client-swift` scores 757 hand-written and should be screened LAST.** It is
generated code, and the tally already carries what that produces: nine refutations, **one**
mechanism, one codebase. Any result there must be read by mechanism, never by count.

Screened and available, with their hand-written counts: `supabase-swift` **6** ·
`soto-core` **3** (21 C files) · `vapor` **4** · `BigInt` **2** · `postgres-nio` **0** ·
`apollo-ios` **0**.

---

## 9. What this does NOT claim

- **Not a rate.** §5.4. Three real defects across five distinct mechanisms is a stronger prior
  than two across four, and it is not a precision.
- **Not a bill of health for `SymbolKit`.** Zero refutations there is a fact about **5**
  verdicts, 16 of its rows never having compiled.
- **Not that the emitter defects in §6 are the binding constraint anywhere else.** They are two
  subjects' figures.
- **Not that the screen is complete.** It found two blind spots in itself inside one pass, and
  §2 is the argument for expecting a third.

## 10. What would refute this

- **A `codable-round-trip` refutation that is false for a NEW reason** would weaken the
  template hypothesis more than a fourth real one strengthens it.
- **A real `idempotence` refutation** would end the comparison outright. 18 for 18 is a strong
  prior and not a proof.
- **`OpenAPI.XML` being intended behaviour.** The defect rests on `Equatable` being finer than
  `Codable` for that type; a maintainer who says the two `structure` values are meant to be
  distinguishable in memory and identical on the wire would make this a design decision rather
  than a defect. **The round-trip failure would survive that reading** — a value produced by a
  public initializer still does not decode back to itself.
- **The equatable-gate fix moving more than 6 rows, or fewer.** The figure is one subject's and
  is offered as such.
