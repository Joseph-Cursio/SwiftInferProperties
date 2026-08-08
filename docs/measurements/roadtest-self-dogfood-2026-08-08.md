# Road test: SwiftInferProperties on itself, second pass

> **Status:** `measured` · **As of:** 2026-08-08

**Re-tested the same day at `10c59e8` — see §7.** The `As of` line stays a bare date because
`DocStatusHeaderTests` parses it as an expiry stamp; a trailer there is unparseable, which is
the guard that had just been repaired on `main` when this note nearly reintroduced the break.

**Subject:** this repo at `fa57c45` (`v1.148.0`), six source targets.
**Tool:** `swift-infer` built from that checkout, release, into an isolated scratch path.
**Predecessor:** `docs/measurements/roadtest-self-dogfood.md` (2026-07-26, measurements
**withdrawn** 2026-08-01). This pass does not re-open those numbers; it asks a different
question and reaches different findings.

**The question.** Not "how does the tool score" but **"point the toolchain at this repo and
land property tests from what it says."** Holes found on the way are the second output, and
they turned out to be the larger one.

---

## §0 What was produced

Four suites, **15 laws, all passing, all three controls confirmed refutable**:

| file | laws | subject |
|---|---|---|
| `Tests/SwiftInferCoreTests/NameStrippingDifferentialPropertyTests.swift` | 5 | the four `strippingGenericParameters` copies |
| `Tests/SwiftInferCoreTests/LawTotalHomomorphismPropertyTests.swift` | 4 | `ProtocolCoverageAudit.lawTotal(for:)` |
| `Tests/SwiftInferCLITests/BareTypeNameDifferentialPropertyTests.swift` | 3 | the two reachable `bareTypeName` copies |
| `Tests/SwiftInferCLITests/HashPrefixLookupPropertyTests.swift` | 3 | `VerifyHarness.lookupSuggestion` — §2's private-subject law, **lifted** |

**Scored in refutation units, per Appendix C.** A green property suite that has never
failed is not evidence, so each family was run against a deliberate mutant:

| mutant | laws that killed it | laws that correctly survived |
|---|---|---|
| `ProtocolCoverageMap.strippingGenericParameters`: `firstIndex(of:"<")` → `lastIndex` | differential (`"Array<Array<Int>>"` → `"Array<Array"`), idempotence, no-`<` postcondition | prefix, fixed-point — a `lastIndex` strip *is* still a prefix and still leaves generic-free names alone |
| `lawTotal`: per-carrier sum → cross-carrier `Set` union (the "tidier" refactor) | additivity, at 1 + 1 findings | identity, order-independence, monotonicity — dedup satisfies all three |
| `lookupSuggestion`: drop `normalize(hash:)` on the entry side, call site only | spelling-insensitivity, prefix resolution | empty-index — and, by construction, the *helper-level* law `discover` actually proposed (see §2) |

The second row is the point of that suite: the refactor its docstring forbids keeps **three
of four** laws green and breaks exactly one. That is the law carrying the docstring's claim.

---

## §1 Hole — test-lifting is package-wide while discovery is target-scoped

> **FIXED 2026-08-08 — `TestTargetScope`.** Lifting is now scoped to the test targets that
> (transitively) depend on the scanned target, read from `swift package dump-package`.
> **Measured Strong-tier: 26 → 16.** See §1.1 for why that is not the 26 → 7 this section
> originally measured, and why the difference is the fix being *correct* rather than weak.

**73% of this repo's Strong-tier output is cross-target leakage.**

`discover --target X` resolves production code to `Sources/X/`, but
`effectiveTestDirectory` (`Discover+RunHelpers.swift:101`) walks up to the package root and
returns `Tests/` **wholesale**. There is no `Tests/<Target>Tests/` counterpart to the
`Sources/<target>/` convention the tool otherwise honours.

Measured, `--stats-only`, same binary, one flag:

| target | Strong, default | Strong, `--test-dir Tests/<Target>Tests` |
|---|---|---|
| SwiftInferCore | 4 | 2 |
| SwiftInferTemplates | 4 | 1 |
| SwiftInferCLI | 6 | 4 |
| SwiftInferTestLifter | 4 | **0** |
| SwiftInferKitEvidence | 4 | **0** |
| SwiftInferMacroImpl | 4 | **0** |
| **total** | **26** | **7** |

**The symptom is that it looks like signal.** The same four rows appear byte-identical on
every target, including `SwiftInferKitEvidence` and `SwiftInferMacroImpl`, where the
conformance scan reports *0 carriers*. On those two, **4 of 4 suggestions were about other
targets' code** — the rows cite `render(suggestion)`, `merge(merge(log))` and
`Set(declarations).count`, none of which exist in the scanned target.

The narrowing is a *bound*, not a fix: `Tests/SwiftInferIntegrationTests` legitimately
exercises `SwiftInferCLI`, so the correct scoping is by test-target dependency, not by name.
19 of 26 is therefore a floor.

**No recorded decision says this is deliberate.** `DiscoverCLITestDirTests` covers the
resolution *precedence* only (explicit → walk-up → degraded fallback) and never asserts
attribution. The doc comment describes the same precedence and is silent on scope.

---

## §1.1 The fix, and why it lands at 16 rather than 7

`TestTargetScope` resolves the test targets that could be exercising the scanned module by
walking the **transitive closure of target dependencies** in `swift package dump-package`,
and TestLifter scans that set of roots instead of `Tests/` wholesale.

**A/B, one binary, same afternoon.** `--test-dir Tests` reproduces the pre-fix default
*exactly* (an explicit override bypasses scoping), so the two arms differ only in the change
under test — a cleaner comparison than §10.3's two-binary form:

| target | Strong before | Strong after | total before | total after |
|---|---|---|---|---|
| SwiftInferCore | 4 | 4 | 129 | 129 |
| SwiftInferTemplates | 4 | 4 | 114 | 114 |
| SwiftInferCLI | 6 | **5** | 74 | 73 |
| SwiftInferTestLifter | 4 | **3** | 24 | 23 |
| SwiftInferKitEvidence | 4 | **0** | 4 | 0 |
| SwiftInferMacroImpl | 4 | **0** | 4 | 0 |
| **total** | **26** | **16** | 349 | 339 |

**All 10 removed rows are lifted Strong-tier rows; nothing else moved.** No non-lifted
suggestion was lost on any target, which is the control that says the change did what it
claims and nothing else.

### Why not 26 → 7

§1 measured 26 → 7 by narrowing to `Tests/<Target>Tests/`. That number is **too good**, and
§1 said so at the time: name-matching is a bound, not a fix, because it drops
`SwiftInferIntegrationTests`, which legitimately exercises `SwiftInferCLI`. Dependency
scoping keeps those rows, so it lands higher — and higher is correct.

The 10 that go are the ones that were *provably* wrong. `SwiftInferKitEvidence` and
`SwiftInferMacroImpl` are reached by exactly one test target each, because nothing else
depends on them; they had been inheriting laws citing `render(suggestion)` and
`Set(declarations).count`, symbols neither target declares. `SwiftInferCore` stays at 4
because **everything genuinely does depend on Core** — and at least one of those rows,
`merge(merge(log))`, really is about `Decisions.merge`, which lives in Core. Scoping it away
would have been the error.

### The honest limit

Transitive dependency is a **sound over-approximation, not an attribution**. It answers *could
this test target be exercising that module* — and for a base module the answer is legitimately
"all of them". A law lifted from a CLI test body still shows up on `SwiftInferCore` whenever
the dependency graph permits it, even when the symbol it names is CLI's.

Closing that needs the lifted law attributed to **the target that declares the symbol it
mentions**, which is a different feature (symbol resolution) and is not built here. Recorded
as the remaining gap rather than smuggled in as a name heuristic — which is the thing §1
already measured and rejected.

### Cost

`dump-package` is ~0.3s. On a leaf target the scan savings more than pay for it; on the
widest target there is nothing to save and it is a straight add:

| target | before | after |
|---|---|---|
| SwiftInferKitEvidence (leaf) | 0.61s | **0.30s** |
| SwiftInferCore (scoped to all 8) | 1.48s | **1.76s** |

Neither §13 perf suite is affected — both call `TemplateRegistry.discover` /
`TestLifter.discover` directly and never reach the CLI resolver.

**Guards.** `TestTargetScopeTests` (9 laws) and `MultiRootScanTests` (6). The fallback arms
carry the weight: every arm that cannot answer returns `nil` rather than empty and is
separately asserted to reach the old whole-`Tests/` behaviour, because a scoping bug that
returns "nothing" silently switches lifting off, and a tool that suggests nothing looks
exactly like a tool with nothing to suggest. `MultiRootScanTests` pins the two properties the
widening introduces: overlapping roots must not double-count (a duplicated summary reads
downstream as *independent corroboration* — the "stated N times by the scan" line — inflating
a score from one source), and root order must not change output (PRD §16 #6).

---

## §2 NOT a hole — private subjects need the law *lifted*, not an accessibility gate

> **Corrected 2026-08-08**, after review, and the correction is the useful part. The first
> draft of this section called the absence of an accessibility gate a defect and proposed a
> caveat plus a demotion. **That was wrong.** `private` is the correct design, and the
> remedy is to state the law at the public boundary instead of reaching down to the helper.
> The measurement below stands; the recommendation it carried does not.

**The measurement.** Non-`predicate` subjects, resolved to their declaration line and read
for an access modifier:

| target | private | internal | public | private share |
|---|---|---|---|---|
| SwiftInferCLI | **22** | 13 | 3 | **58%** |
| SwiftInferCore | 5 | 0 | 22 | 19% |

It lands on the top tier, not just the tail: of the three Strong-tier `idempotence` rows for
`SwiftInferCLI`, **two are private** — `normalize(prefix:)` and `normalize(hash:)`
(`VerifyHarness.swift:145`, `:156`) — and so is `SwiftInferCore`'s Strong-75
`deduplicated(_:)` (`EqualityBodyShape.swift:391`).

### Lift, don't widen

Two ways to make a law about a `private` subject executable:

* **Widen** — change the production code to reach the test (`private` → `internal`). The
  helper joins the surface and can no longer be renamed, inlined or deleted freely, and the
  test is now coupled to an implementation detail. Every refactor that touches the helper
  breaks the test *as a test failure*, which reads like a bug.
* **Lift** — leave the helper private and restate the law about the nearest reachable
  **caller**. Production code is untouched, and the test survives the helper being renamed,
  inlined, split or replaced, because it never names it.

Properties are the kind of test that should survive refactoring, so lifting is the
right move — and it costs nothing, because the helper exists to serve the caller.

### The lifted law is *strictly stronger*, measured

This is the part that is not just a stylistic preference. `discover` proposed idempotence of
`normalize`. Lifted to `lookupSuggestion(hashPrefix:in:)` the law becomes metamorphic — one
index, four spellings of one prefix, one answer — and it catches a bug the helper-level law
is structurally blind to.

`lookupSuggestion` normalizes **both** sides: the query prefix (`:77`) and each entry's hash
(`:79`). Drop one of the two calls and `normalize` is untouched, so its idempotence still
holds — while `0xBC43` silently stops matching an entry stored as `BC43`.

Run as a control (`HashPrefixLookupPropertyTests`):

| mutant | widened law (`normalize` idempotence) | lifted law (spelling-insensitivity) |
|---|---|---|
| drop `normalize(hash:)` at the entry side, call site only | **holds** — `normalize` is byte-identical, so the law is unaffected *by construction* | **fails**: `index stored "0xBC43359C0574816B" but query "0xBC43359C0574816B" resolved to nothing`, and the prefix law fails with it |

The mutant is a one-line change at the call site. Testing the helper tests the helper;
testing the boundary tests how the helper is *used*, which is where this class of bug lives.

### What, if anything, the tool should change

**Not a gate, not a demotion, not a veto.** A row pointing at a `private` function is
correct and useful — it says *there is a law near here*. What would help is a caveat that
names the nearest reachable caller, turning "you cannot test this" into "state it on
`lookupSuggestion`". That is an additional line of explainability, the opposite of
suppressing the row.

This still interacts with §1, and that interaction is real: a reader taking the Strong tier
first gets rows that are disproportionately either about another target (§1, a genuine
defect) or in need of lifting (this section, a reading skill).

---

## §3 Hole — `differential-equivalence` misses same-name duplication (the miss that produced §0's best suite)

`DifferentialTemplate` is the tool's own "two implementations of one specification must
agree" family. Pointed at this repo it proposed `differential-equivalence` rows **only from
lifted test bodies, and zero from source** — while `Sources/` declares the same
generic-parameter strip **nine times**:

Seven are the same function (strip at the first `<`):

* `CarrierKindResolver.strippingGenericParameters` · `OrderSensitiveCarrierNames` ·
  `FloatingPointStorageNames` · `ProtocolCoverageMap` (all `SwiftInferCore`, all `public`)
* `SwiftInferCommand.Index.bareTypeName` · `RoundTripPairResolver.bareTypeName` ·
  `DoccPageBuilder.bareTypeName` (all `SwiftInferCLI`)

**Two share the name and do something else entirely:**

* `OutputDeterminismVerifierEmitter.bareTypeName` strips an `any ` prefix and trailing
  `?`/`!`/space — and leaves generics alone.
* `SelectionSubsetTemplate.bareTypeName` strips only a trailing `?`.

So `bareTypeName("Array<Int>")` is `"Array"` in three places and `"Array<Int>"` in two
others, under one name, across three targets.

**Why the gate reaches none of it.** `VariantMarkers` pairs on a *name marker* — the variant
must be spelled `parseIncrementally`, `appendUnchecked`, `fooSlow`. Real duplication here is
spelled with the **same name in a different type**, which carries no marker. This is the
failure mode CLAUDE.md §10 already records for `homomorphism`: *built for a shape the
language does not use*.

The sharpest part: `VariantMarkers`' own measured-reach note — *12 pairs across ~5,900
function names in seven corpora* — **lists this repo among the seven**. The measurement was
taken and the shape was never in scope for it.

**What was already tested, and why it was not enough.** All four Core copies have
example-based tests (`CarrierKindResolverTests:384`, `FloatingPointStorageNamesTests:41-45`,
`RoundTripPairResolverTests:158`, `IndexCommandBuildEntryTests:242`). Every one checks the
same four hand-picked inputs — `Complex<Double>`, `Array<Int>`, `Foo`, `""` — against its
own copy. **Four copies of one example set cannot detect that the copies have drifted**,
because no test ever ran two of them on one input. That is now five laws that do.

A candidate rule — *same name, same signature, different enclosing type* — is **not**
proposed as a filter here. Per the `domain-transfer-signal` practice, it would have to be
scored against the pairs that legitimately differ (`run()`, `makeConstraint()`) before
anyone builds it.

> **It was scored, and DECLINED — `docs/measurements/same-name-differential-pairing.md`
> (2026-08-08).** Precision **40%** against a ≥50% bar frozen before the scorer existed, so
> the template does not ship and the hand-written suite stays. Two results worth carrying
> back here. The dominant false positive is **not** protocol conformance as guessed above but
> *undeclared role interfaces* (`emit` ×16, `makeConstraint` ×14, `suggest` ×13) — a name is
> shared because it names a **role**, and no vocabulary separates a role from a copy. And the
> pairs the rule gets right are the byte-identical ones, whose differential law is `f(x) ==
> f(x)` and cannot fail — their value is drift protection, which is a lint question rather
> than a property one. The census does say the shape is not rare: `intDefaultPass(functionCall:)
-> String`, `doubleEdgePass`, `doubleDefaultPass`, `complexDoubleShrinkPhase` and five more
are each declared 3× in this repo.

---

## §4 Hole — the `(String, String) -> String` source-emitter shape floods type-symmetry

A code generator's functions render Swift text. Type symmetry `(T, T) -> T` fires on all of
them, and text rendering is essentially never associative or commutative.

All 7 `round-trip` rows on `SwiftInferCLI` pair `codableCollisionBody(carrier:)` with a
*different* `(String) -> String` emitter each time — `stripTupleLabel`, `ocDictExpression`,
`dualStyleNonMutatingCallExpression`, `firstItem(as:)`, `ocSetExpression`, `literal(_:)`,
`dualStyleTrailingArgument`. One function paired against every other function of its shape.

The `associativity` / `commutativity` rows are the same story on the two-argument shape:
`scalarShrinkPhase(carrier:oracle:)`, `tripleShrinkPhase(carrier:oracle:)`,
`ternarySweep(functionCall:carrier:)`, `pairShrinkPhase(carrier:oracle:)` — all
`(String, String) -> String` emitters of Swift source fragments.

Stated as an observation, **not** as a request for a filter: PRD §3.5 corollary 3 says the
remedy for too much output is to raise thresholds, and the conjecture caveat already fires on
every one of these rows. What is new is that the population is *structural* — this tool is a
code generator, so it is exactly the corpus where the shape is dense. It is a candidate
sibling to `OrderedCarrierDiscriminator`: a "renders source text" carrier signal. Any such
rule must be scored against the laws that **held**, not against the class it targets.

---

## §5 Friction, not defects

* **`--stats-only` hides the leak.** The per-template summary is what a CI dashboard reads,
  and §1 is invisible in it — the counts look plausible on every target. It took the full
  explainability blocks to see that four rows were the same four rows.
* **The coverage note is a fixed banner.** `SwiftInferKitEvidence` reports *"0 laws over 0
  carriers"* and still emits the full "call `KitEvidenceRecorder.record(...)`" paragraph
  advising the reader to record evidence for the zero carriers. Cosmetic.
* **Two Claude sessions, one `.build`.** A concurrent session held the SwiftPM lock and
  edited a source file mid-build (`error: input file ... was modified during the build`).
  Building into a `--scratch-path` under the session scratchpad is the workaround, and is
  worth knowing before blaming a manifest.

---

## §6 What this pass does *not* claim

* **`verify` / `prove-then-show` was not exercised.** Every verdict here is from `discover`
  plus hand-executed laws. No `measured-bothPass` is asserted, and nothing in this document
  should be read as a statement about the measured-verify path.

  Two **preconditions** were established before the run was called off, and are recorded so
  the next attempt does not rediscover them. (1) `.swiftinfer/index.json` was **a week
  stale** — 251 entries dated `2026-08-01`, against ~123 current picks for `SwiftInferCore`
  alone. `IndexStore.upsert` keeps historical entries, so running against it verifies the
  *union* of every run that ever happened; archive or delete the index first, which is the
  trap CLAUDE.md's whole-corpus-survey row already names. (2) The machine was at **96% disk
  (38 GB free)**, and a killed subprocess suite skips its cleanup `defer` — the
  `verify --all-from-index` survey once cost 24 GB. Run `make clean-temp` first and watch
  free space, or scope the run with `--template`.
* **The mutants are planted evidence.** Per `fixtures/planted-defect-arm`, planted evidence
  falsifies a categorical claim ("these laws cannot fail") and **cannot estimate precision**.
  The two mutant rows say the laws are refutable, not how often they would catch a real bug.
* **No real defect was found in the subjects.** All nine name strips that claim to agree do
  agree, and `lawTotal` is additive. The honest gain is `unchecked → checked and held`, plus
  a drift guard over nine copies that previously had none — not `bug found`.
* **§1's 19-of-26 is a floor**, for the reason given there.

---

## §7 Re-test at `10c59e8`, same day

Re-run after the holes above were worked, with a release binary built from `origin/main`.
Same day as §0–§6, so this is a controlled comparison rather than a run against a remembered
count (§10.3).

### §7.1 The scoping fix holds in production

| target | §1 baseline (`fa57c45`) | re-test (`223373b`) |
|---|---|---|
| SwiftInferCore | 129 / **4** Strong | 129 / **4** |
| SwiftInferTemplates | 114 / **4** | 114 / **4** |
| SwiftInferCLI | 73 / **6** | 73 / **5** |
| SwiftInferTestLifter | 24 / **4** | 23 / **3** |
| SwiftInferKitEvidence | 4 / **4** | **0 / 0** |
| SwiftInferMacroImpl | 4 / **4** | **0 / 0** |
| **Strong total** | **26** | **16** |

Identical to the A/B's "after" arm, on a binary built from `main` rather than from the
branch. Confirmation, not new information — recorded because a fix that measures well on its
own branch and not in production is the failure mode this table exists to exclude.

### §7.2 REFUTED — no self-corroboration from the tests this road test produced

The worry, worth stating because it sounds right: §0 landed 15 laws *because `discover`
proposed them*; TestLifter pays **+20 `crossValidation`** for a law restated in a test; so the
tool might now corroborate its own suggestions with no new evidence, inflating tier.

**It does not happen.** `strippingGenericParameters` idempotence is still `Likely` **50**,
carrying type-symmetry (+30), author-declared (+15) and value-semantic (+5) and **no
`crossValidation` signal** — although `NameStrippingDifferentialPropertyTests` asserts exactly
`implementation.strip(once) == once`. `lawTotal` is unchanged at 70, `deduplicated` at 75.

The loop is not closed. But the *reason* it is not closed is the finding below, and it is a
worse problem than the one feared.

### §7.3 NEW — TestLifter cannot see the property tests this workflow produces

Four suites, 15 laws, in test targets that scoping puts **in scope** for the modules they
test. Lifted rows attributable to them: **zero**.

`SwiftInferCLI`'s four lifted rows are `expectedRender` vs `render`, `Set(declarations).count`,
`merge(merge(log))` and a `SipHasher.finalize()` value-semantics lift. None is
`BareTypeNameDifferentialPropertyTests` — which states a **differential-equivalence** law
explicitly, the very family the row above it was lifted for — and none is
`HashPrefixLookupPropertyTests`.

The shape TestLifter misses is `propertyCheck(input: gen) { value in #expect(...) }` with the
subject reached through a collection element (`implementation.strip(name)`). That is the
house style for property tests in this repo — 10 suites before this road test, 14 after.

**The consequence is sharper than a missed row.** The `+20` cross-validation seam exists to
reward a codebase that already states its laws. It is systematically unavailable to precisely
the tests this toolchain's own workflow produces: `discover` proposes, a human writes the
property test, and `discover` cannot read it back. The seam works for XCTest-style example
assertions and not for the property tests the product exists to encourage.

This confirms, in a new context, the standing note that TestLifter's detectors are keyed to
existing templates and miss hand-rolled random-input property tests. What is new is that the
gap now covers the tool's *own* recommended output.

> **FIXED 2026-08-08 — `Slicer.quantifierClosureBody`.** A quantifier's trailing closure is
> now unwrapped exactly as a tail `for` body always was, gated on a curated callee list
> (`propertyCheck`, `forAll`, `property`, `checkProperty`, `quickCheck`). A/B across six
> targets: **Strong 16 → 24**, totals 339 → 342. **Read §7.6 before celebrating that number** —
> most of the movement is the `+20` cross-validation seam firing for the first time, and four
> of the eight new Strong rows are corroborated by a test this road test itself wrote.

### §7.4 NEW — a lifted row carries no provenance, and that is why §1 hid so long

> **FIXED same day.** `LiftedSuggestion.provenanceLine()` resolves through `LiftedOrigin`,
> and every lifted row now names its test file, line and method. Measured after:
> `SwiftInferCore`'s three lifted rows resolve to `SharedVerifierPackageTests.swift:79`,
> `GeneratorSelectionIntegrationTests.swift:18` and
> `IdentityElementTemplateGoldenTests.swift:9` — **an audit that was impossible before**,
> and which shows none of them sits in `Tests/SwiftInferCoreTests/`. Whether each is
> *correctly* attributed is now a question a reader can answer in one click, which is the
> whole point. Guarded by `LiftedProvenanceTests`.

Every lifted row renders `Lifted from <test-body>:0`. Not a path, not a line — a placeholder
and a zero. A source-derived row in the same output carries
`— …/Sources/SwiftInferCore/EqualityBodyShape.swift:391`.

**This is the diagnostic gap that let §1 survive.** A row citing `render(suggestion)` on
`SwiftInferKitEvidence` is only *obviously* wrong if it says which file it came from; without
that, it reads as a plausible finding about a target you have not memorised. §1 was found by
noticing four byte-identical rows across six targets and then grepping — not by reading the
output, which could not say.

It also blocked §7.3 above: establishing that none of the four new suites was lifted could not
be done from the tool's output at all, and needed the *content* of each lifted row matched
against source by hand. **A tool whose entire posture is human review is emitting a row a
human cannot audit.**

Cheapest fix of the three findings here, and the one that makes the other two checkable:
`LiftedOrigin` already exists as a type; the renderer prints a placeholder instead of it.

### §7.5 Status of the original findings

| finding | status |
|---|---|
| §1 package-wide lifting | **FIXED** — `TestTargetScope`, confirmed in production above |
| §2 private subjects | **not a hole** — lift the law, do not widen access (corrected) |
| §3 same-name duplication miss | **DECLINED** — 40% precision, `same-name-differential-pairing.md` |
| §4 emitter-shape flood | open, deliberately — observation, not a filter request |
| §5 `--stats-only` hides the leak | open; §7.4 is the same gap seen from the row level |
| §6 `verify` / `prove-then-show` | still not exercised |


---

## §7.6 The §7.3 fix closes a loop §7.2 could only refute because the tool was blind

§7.2 asked whether the 15 laws this road test landed would feed back as `+20`
`crossValidation` and inflate their own tier. The answer was no — **because TestLifter could
not read a property test at all**. §7.3 fixes that, and the loop is now live.

**Measured.** A/B, two binaries, same afternoon:

| target | Strong before | Strong after |
|---|---|---|
| SwiftInferCore | 4 | **8** |
| SwiftInferTemplates | 4 | **5** |
| SwiftInferCLI | 5 | **6** |
| SwiftInferTestLifter | 3 | **4** |
| **total** | **16** | **24** |

Totals barely move (339 → 342), so this is **promotion, not discovery**: only 3 genuinely new
rows, and 8 existing rows crossing into `Strong` because the `+20` finally fires.

**The four promotions on `SwiftInferCore` are the whole question.** All four are `merge(_:)`
commutativity, 70 → **90**, on `Decisions`, `InteractionDecisions`, `PostAcceptanceOutcome`
and `VerifyEvidence`. Their corroborating suite is `MergeAlgebraPropertyTests`, whose own
header reads:

> *"Self-dogfood road test — the laws `swift-infer discover --target SwiftInferCore`
> **proposed** against this repo's own persistence layer, executed rather than read."*

So: `discover` proposed the law, a human wrote the property test **on that advice**, and
`discover` now reads the test back and raises its own suggestion by 20 points.

### Why this was still shipped

**Blindness is not a safeguard.** The slicer failing to parse a property test is a defect
whichever way the score moves; keeping it would be preserving a bug because it happened to
suppress a second one.

And the evidence is not empty. `MergeAlgebraPropertyTests` did not rubber-stamp the law — it
**refuted** commutativity when first written, which is what drove the `IdentityKeyedFold`
fix. A law that survives an executing property test over a generated domain is better
supported than one read off a name and a shape.

### What is genuinely unresolved

The `+20` was designed to mean *this codebase independently states this law*. After §7.3 it
can also mean *this codebase took our advice*. Those are different claims and the signal
renders identically for both — `Cross-validated by TestLifter`, naming nothing.

Two further caveats sharpen it. TestLifter reads **source, not results**, so the signal fires
for a law a test merely *states* — a failing or skipped test corroborates exactly as much as
a passing one. And a third-party reader sees `Strong 90, cross-validated` and reasonably
infers two independent sources agreeing, when one caused the other.

### The remedy, applied — name the source

**Done in the same PR**, and it is §7.4's medicine again. `Artifacts.crossValidationOrigins`
carries the corroborating `LiftedOrigin` per key, threaded through
`discover`/`discoverArtifacts` into `applyCrossValidation`, and the row now reads:

```
✓ Cross-validated by TestLifter — Tests/SwiftInferCLITests/MergeAlgebraPropertyTests+Commutativity.swift:53 `mergeCommutesForEveryReadingPair` (+20)
✓ Cross-validated by TestLifter — Tests/SwiftInferCLITests/MergeAlgebraPropertyTests.swift:177 `decisionsMergeIsAssociative` (+20)
```

A reader who recognises `MergeAlgebraPropertyTests` as a suite this road test wrote can now
discount the corroboration accordingly. That was impossible when the line said only
*"Cross-validated by TestLifter"*.

**The origins map is advisory, and that is the load-bearing design choice.** The key set stays
authoritative for *whether* the `+20` fires; origins change only how it **renders**. So the two
collections disagreeing can produce a vaguer sentence but never a wrong score — a presentational
map never becomes a scoring input. `CrossValidationOriginTests` pins exactly that: supplying
origins must not change which suggestions are cross-validated, and an origin without a matching
key must fire nothing.

**What this does and does not settle.** It does not decide whether corroboration-from-our-own-
advice *should* count `+20` — that is a judgement about evidence, and reasonable people can
differ. It makes the judgement **available at the point of reading** instead of hidden. The two
narrower caveats stand unchanged: TestLifter still reads source rather than results, so a
failing or skipped test corroborates as much as a passing one; and the signal still cannot
distinguish a test written independently from one written on the tool's advice — it can now only
show you which test, and let you decide.
