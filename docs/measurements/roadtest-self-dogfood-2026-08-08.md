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
| §6 `verify` / `prove-then-show` | **CLOSED — §8**: 153 picks, 81 Proven, 1 Disproven (a false law at `Possible`), **0 defects** |


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

---

## §8 `prove-then-show` — §6 closed, and the tool gets a clean bill

The measured-verify path had never been exercised by this road test: every verdict up to here
came from `discover` plus hand-executed laws. §6 recorded that as the standing gap. This runs it.

**Subject:** `SwiftInferCore` @ `ca2e73c`, release binary built from `origin/main`.
**Command:** `prove-then-show --target SwiftInferCore --budget small --max-parallel 4`, no
`--corpus-module` (per that command's doc: omit it when proving the package you stand in, so
the survey derives `@testable import` per entry). **12 min, 9.3 GB of workdir, exit 0.**

**The stale-index precondition §6 warned about was sidestepped rather than managed.** The run
was done in a fresh `git worktree`, and `.swiftinfer/` is gitignored — so the index was clean
*by construction*, with no archive-and-restore dance and no risk of verifying the union of
every past run.

### §8.1 The result

| | count |
|---|---|
| **Proven** | **81** |
| Expected-to-hold | 0 |
| **Disproven** | **1** |
| Unverifiable | 63 |
| Inconclusive | 8 |
| **tested** | **153** |

Proven by template: `predicate` 49 · `idempotence` 14 · `codable-round-trip` 10 ·
`commutativity` 4 · `associativity` 4.

The four `commutativity` and four `associativity` rows are the `merge(_:)` folds — the laws
the *first* road test proposed, that refuted, that drove `IdentityKeyedFold`, and that
`MergeAlgebraPropertyTests` pins. They now execute and hold under the tool's own generator as
well as under the hand-written suite.

### §8.2 The single refutation is a false law, not a defect

```
✗ BuildIdentity  idempotence  versionString(_:)   [counterexample: XO8hGC]
```

```swift
isAttributable ? "\(version) (\(commit))" : "\(version) (unattributable build)"
```

Applying it twice appends the suffix twice. **The code is correct and the conjecture was
wrong** — precisely what the tool's own standing caveat says (*a `T -> T` need not be
idempotent; a one-shot suffix strip applied twice removes two suffixes*).

It sits at **`Possible`, score 35**. That independently reproduces the whole-corpus survey's
finding — *all real bugs are `Likely`; all `Possible` refutations are false laws* — on a
different corpus and a different binary. **Tier predicted the reading correctly.**

**So the honest headline is a clean bill: 81 laws executed and held, zero defects found.**
That is the outcome a correct codebase should produce, and it is the first *execution-backed*
evidence anywhere in this road test. It is also the weaker kind of result — absence of
refutation over a generated domain is not proof, and `measured-bothPass` means only "no
counterexample in the generated domain" (Appendix C).

### §8.3 Unverifiable 63 of 153 (41%) — mostly correct silence

Reasons: 24 `unsupported-carrier`, 10 `unsupported-template`, the rest assorted
(`monotonicity-domain-not-comparable` ×2, and single instances).

By template the bucket is 40 `predicate`, 7 `idempotence`, 3 `monotonicity`,
3 `input-totality`.

> **CORRECTED 2026-08-08.** This section first read: *"The carriers are dominated by
> SwiftSyntax visitor types … **those are untestable by construction, not a gap**: a syntax
> visitor has no meaningful generator."* **That was too strong, and it drew the line in the
> wrong place.** It is true of the *visitors* and false of the syntax *nodes*, which the
> sentence lumped together — `DeclModifierListSyntax` was cited as an example of the former
> and is one of the latter. The corrected split is below. Prompted by SwiftPropertyLaws'
> `PropertyLawSyntax`, which demonstrably generates syntax values, so "no meaningful
> generator" cannot be a property of the kind.

The 24 `unsupported-carrier` picks split three ways, and only the first is untestable by
construction:

| kind | count | carriers | reading |
|---|---|---|---|
| **our own visitor / aggregate types** | 11 | `FunctionScannerVisitor` ×2, `BodySignalVisitor` ×2, `Visitor`, `TypeDecl`, `SamplingSeed`, `FunctionSummary`, `Finding`, `Effect`, `Coverage`, `Ranked<Record>` | a visitor is a *traversal*, not a value; generating one is meaningless. Correct silence |
| **concrete SwiftSyntax nodes** | 6 | `DeclModifierListSyntax` ×2, `StringLiteralExprSyntax`, `InheritanceClauseSyntax`, `DictionaryExprSyntax`, `CodeBlockItemSyntax`, `ArraySlice<CodeBlockItemSyntax>` | **a gap, not a law of nature.** These are ordinary values with a grammar |
| stdlib / unresolved generic | 2 | `String`, `S` | `String` is generable and the pick is a shape problem, not a carrier one |

**The middle row is the correction.** `PropertyLawSyntax` vends `gen()` for six *erased base*
types — `DeclSyntax`, `ExprSyntax`, `PatternSyntax`, `StmtSyntax`, `TokenSyntax`,
`TypeSyntax` — so the kit already generates syntax. Our six are **concrete or collection**
nodes, and **zero of the 24 are among the six**, which is why adopting
`--extra-import PropertyLawSyntax` would unblock none of them today. But "nobody has written
the generator" is a different claim from "no generator is possible", and the first draft
asserted the second.

That also makes the middle row the concrete downstream ask for the kit: generators for
concrete nodes, or a derivation from the erased base, would move six picks out of
Unverifiable. Recorded as a measured demand rather than a guess.

### §8.3.1 The ask was answered, and four of the six already worked

Relayed back from the kit side the same day. **Four of the six needed nothing new** —
`DeclModifierListSyntax`, `StringLiteralExprSyntax`, `InheritanceClauseSyntax` and
`CodeBlockItemSyntax` were already generable, because `Gen<T>.syntaxNode()` was written
**generically** rather than by hand for the three types some earlier corpus happened to name.
That is the payoff of the general form landing before the demand for it did, and it is worth
recording as the reason the answer was cheap rather than as a lucky outcome.

The remaining two each needed real work, and each is a different kind:

* **`DictionaryExprSyntax`** — needed a new template (no existing template carried a
  dictionary literal). A gap in *coverage*.
* **`ArraySlice<CodeBlockItemSyntax>`** — **not a `SyntaxProtocol` at all**, so it was not a
  syntax problem. It became a new `GeneratorPlan.arraySlice` case in the kit's
  `CompositeMemberParser` — **general, not syntax-specific**, since `ArraySlice` is stdlib
  and every element type gains. Deliberately a distinct case rather than a spelling of
  `.array`, because **a member declared `ArraySlice<T>` will not accept `[T]`**; collapsing
  them would emit a generator that does not typecheck at the use site.

**This is unconfirmed on our side, and the bound matters.** The work is uncommitted in the
kit's working tree (`GeneratorPlan.swift` modified, `Sources/PropertyLawSyntax/` untracked)
and the newest tag, `v3.27.1`, contains no `arraySlice` — so the version this package resolves
cannot exercise any of it. **Nothing here is measured by us.** Confirming it means bumping the
pin once the kit tags, re-running `prove-then-show --target SwiftInferCore`, and checking that
those six move out of `unsupported-carrier`. Until then this section records a *reported*
outcome, not a verified one.

**No falsifier is attached, deliberately, and the reason is worth keeping.** The first draft
wrote `(falsifier: ``SwiftPropertyLaws/GeneratorPlan.arraySlice``)` and
`DeferralFalsifierTests` immediately failed it — correctly. The resolver reads the sibling's
**working tree**, where that symbol already exists, so it reported the deferral as resolved.
But the symbol existing is not the condition being waited on: the kit has to *tag*, this
package has to bump its pin, and the survey has to be *re-run*. The falsifier convention
answers "has this landed in the tree", and what is pending here is "have we re-measured" —
which no symbol can settle. Attaching one anyway would have produced a guard that goes green
while the claim stays unverified, which is the failure mode the convention exists to prevent.

### §8.3.2 MEASURED — and it corrects §8.3 a second time

Run against the kit at `0720714` (its `access-provenance-and-syntax-generators` branch, since
`v3.27.1` is still the newest tag and contains none of this). **Both pins had to move**: this
package's, so the binary can *derive* the plan, and
`VerifierWorkdir.swiftPropertyLawsRequirement`, so the generated stub packages resolve the
same kit — changing only the first would have left every stub on 3.27.1 and produced a null
result that looked like a finding.

| | 3.27.1 | 0720714 |
|---|---|---|
| Proven | 81 | 81 |
| Disproven | 1 | 1 |
| **Unverifiable** | **63** | **61** |
| Inconclusive | 8 | **10** |
| `unsupported-carrier` picks | **24** | **20** |

**Four picks stopped being "no generator" — and none of them is a syntax node.** The carriers
that left the unsupported set are `Finding`, `Coverage` and `TypeDecl`: *our own aggregate
structs*. The six concrete SwiftSyntax nodes §8.3 predicted would move did **not**, because
their generators live in `PropertyLawSyntax`, a product this package does not depend on and
whose import is opt-in by design. The prediction was right that they are generable and wrong
about what a pin bump reaches.

**So §8.3's corrected table is still wrong, in a new place.** It put `Finding`, `Coverage`,
`TypeDecl`, `SamplingSeed`, `FunctionSummary`, `Effect` and `Ranked<Record>` in a row headed
*"our own visitor / aggregate types … a visitor is a traversal, not a value"* and called the
whole row correct silence. **Only the visitors belong there.** `FunctionScannerVisitor`,
`BodySignalVisitor` and `Visitor` are traversals; the other seven are ordinary value structs,
and at least three of them are generable — measured, not argued.

The line is **traversal vs value**, and it cuts across both origins. It is not
visitor-vs-node (§8.3's first attempt) and not ours-vs-theirs (§8.3's second). Two wrong cuts
in one section is the reason this subsection exists: the classification kept being made from
the *name* of the type, and only the survey settled it.

### §8.3.3 The bottleneck moved from the kit to us

> **RESOLVED 2026-08-09 — see §9.** Both halves shipped and the prediction below held:
> the kit work merged as SwiftPropertyLaws `b59cdb4` / **`v3.28.0`**, this package's two
> pins moved together (`9919bed`), and `e5731a9` (PR #206) qualifies the generator
> carrier. `ProtocolCoverageAudit.homomorphism lawTotal(for:)` — the pick this section
> is about — now **executes and holds**. Its three-configuration trajectory is the
> record: `unsupported-carrier: Finding` → `build-failed: cannot find type 'Finding'`
> → **Proven**. The sentence below that "this package still resolves `v3.27.1`" is
> therefore superseded, and so is the *"nothing was shipped"* note.

The four picks did not become Proven. They became **Inconclusive**, and `build-failed` went
from 2 to 4:

```
? lawTotal(for:)  (unsupported-carrier: Finding)                    ← 3.27.1
· lawTotal(for:)  (build-failed: cannot find type 'Finding' in scope) ← 0720714
```

The kit can now derive a plan for `ProtocolCoverageAudit.Finding`; our emitter then writes
`Finding` unqualified into a stub that has no such type at file scope. **That is exactly the
`cannot find 'Visitor' in scope` gap already recorded in §8.4** — nested-carrier
qualification — and this run doubles its population from 2 picks to 4.

**The transferable result is the direction of the constraint, not the two picks.** Before this
run the honest reading was "the kit cannot generate our carriers". After it, the kit can, and
**our own emitter is what stops the law from executing**. That reprices
`nestedCarrierImportResolution` from the cheapest open item to the one gating everything the
kit unblocks next. **Resolved 2026-08-09 — see §9.1**; the falsifier that stood here is retired, because the generator-carrier half it named is fixed and measured.

**Nothing was shipped to get this.** Both pin edits were made in a throwaway worktree and
discarded; this package still resolves `v3.27.1`. The measurement stands on a committed,
citable SHA rather than on a working tree.

**What the exchange demonstrates is the loop, not the six picks.** A downstream survey named
six concrete types it could not generate; the upstream answer was four already-solved, one
coverage gap, and one general stdlib improvement that no syntax-shaped framing would have
found. The ask was worth making *because* it named types rather than asking for "better
generators".

One Unverifiable is a gap on **our** side that this road test had already met by hand:

```
? ProtocolCoverageAudit  homomorphism  lawTotal(for:)  (unsupported-carrier: Finding)
```

That is the law §0 landed as `LawTotalHomomorphismPropertyTests` — where a `Finding`
generator had to be **hand-written**. So the tool proposes a law it cannot itself test, and
the missing capability is generator derivation for a struct holding a `Set<KnownProperty>`
and an enum. It says so plainly rather than passing silently, which is the right failure.

### §8.4 Inconclusive 8 — two findings, and the honest one is about the generator

> **CORRECTED 2026-08-09 (§9.2): "two build failures, one emitter gap" was one label over
> three different defects.** The re-run splits them, and only one was what this section
> says. `Coverage` is a **residual bug in the `e5731a9` fix** — the stub qualifies the
> *values* (`Gen.always(RefutedExpectation.Coverage.notApplicable)`) but not the *type
> annotation* (`Generator<Coverage, …>`), because `Coverage` is a **parameter type**
> rather than the generator carrier and flows through an emit path the fix never reached.
> `Visitor` is the fix **correctly declining**: seven declaration sites, so it is
> ambiguous and `VerifyCommand+NestedCarrier`'s never-guess rule refuses to pick one.
> `NonDeterministicAPIs` is **not a qualification problem at all** — it is `private` at
> file scope, and `@testable` promotes `internal`, not `private`, so it is misfiled here
> when the survey already has an `internal-api-not-accessible` bucket that describes it
> exactly. The falsifier below is therefore **narrowed, not retired**: it now names only
> the ambiguous-name case.

**Six are generator traps.** The verifier trapped (signal 5) before comparing, and the
message is explicit that this is *"evidence about the generator's domain, not about the
law"*. One flushed counterexample shows the mechanism outright:

```
SourceLocation(file: "4pUWyvJ8", line: -691367222 …)
```

An unbounded negative `Int` drawn for a line number. That is the weak-generator idiom
`parsing-catalog-gap.md` records as a measured weakness, caught in the act on this repo's own
types. It is not a defect in the subject code and the tool does not claim it is.

**Two are build failures, and these are the actionable finding:**

```
build-failed: cannot find 'Visitor' in scope
build-failed: cannot find 'NonDeterministicAPIs' in scope
```

The survey derives `@testable import <Module>` per entry, which reaches `internal` but not
types that are nested or otherwise unreachable at file scope. Two picks are therefore lost to
an emitter gap rather than to anything about their laws. **Open follow-up**, and the cheapest
remaining item in this document. **Narrowed 2026-08-09 (§9.2)** to the AMBIGUOUS-name case only — `Visitor` has seven declaration sites and no lookup can choose between them, so closing it needs module-aware resolution rather than a name lookup. **DECLINED on measurement 2026-08-09 — §9.8.**

### §8.6 A Proven verdict that is FALSE — and the 81 were never tests

Two things this section exists to correct, both found *after* the survey ran.

**(a) "81 Proven" is not 81 tests.** The survey generates each law into a throwaway verifier
workdir, compiles it, runs it once, and the workdir is deleted with the run. A Proven verdict
is a **measurement, not regression protection** — nothing re-checks it afterwards. The picks
that survive have to be *banked* to become tests. Banked here: the 5 uncovered
`codable-round-trip` carriers (`InversePair`, `MarkerPair`, `SeedEffect`, `SeedRestriction`,
`SeedRole`) and the uncovered `idempotence` subjects, as
`SurveyedCodableRoundTripPropertyTests` and `SurveyedIdempotencePropertyTests` — **13 laws,
2 mutant controls**. The rest were already covered (`MergeAlgebraPropertyTests`,
`PersistenceRoundTripPropertyTests`, `NameStrippingDifferentialPropertyTests`) or are
`predicate` totality claims that the Daikon-trap entry already warns are 88% of output.

**(b) One Proven verdict is wrong.** `ViewModelNameHeuristics.booleanStem` is **not
idempotent**, and the survey proved it:

```
isShowing     -> showing    -> ing
hasShown      -> shown      -> n
willShowAlert -> showalert  -> alert
```

It strips ONE prefix from `["isshowing", "is", "has", "show", "should", "did", "will"]`, so a
second application strips a second prefix whenever the stem starts with another one — which
English identifiers do constantly.

**Why the verifier missed it is the whole lesson.** The derived `String` generator draws
values like `"XO8hGC"` and `"uvYUbS"` — the literal counterexamples §8.4 captured from other
picks — which never begin with an English boolean prefix, so the failing branch was
unreachable in the generated domain. This is the standing rule in the sharpest form it has
taken in this repo: ***`measured-bothPass` means no counterexample in the generated domain,
not that the property holds.*** It generalises the `Decisions.merge` alphabet-width finding
from *collisions* to *any branch keyed on realistic content*.

**It is a false law, not a defect.** Both call sites apply it once to a raw property name and
the docstring says one strip by design. `SurveyedIdempotencePropertyTests` therefore pins the
**refutation**, with a message telling a future editor to check those call sites before
"fixing" it — looping would turn `isShowingSheet` into `sheet` and change what every
view-model invariant keys on.

**This was found by reading the code, not by running the tool**, which bounds §8.1's headline:
81 Proven contains at least one false positive, discovered by hand on the ~30 non-`predicate`
rows. The 49 `predicate` rows were not audited this way.

### §8.7 The controls

Banking a Proven law is only worth it if the banked law can fail. Both suites were run against
deliberate mutants:

| mutant | killed by | correctly survived |
|---|---|---|
| `SemanticIndexEntry.updated(from:)` takes `identityHash` from the **argument** | identity-preservation | **idempotence** — still true, and blind to it |
| `InversePair.init(from:)` decodes the two-element array **swapped** | round-trip + the explicit `forward` assertion | the other four carriers |

The first row is the argument for not banking the survey's verdict alone: **the law the survey
proved is exactly the law that cannot see this bug.** Re-keying every index row stays perfectly
idempotent. The refutable companion law had to be added by hand.

### §8.5 What §8 does not claim

* **Zero defects found is not zero defects present.** 81 held over a generated domain at
  `--budget small`; a wider budget or a narrowed alphabet could still refute. The
  collision-dependent class (merge tie-breaks, dedup, key injectivity) is invisible to a
  generator drawn for type coverage — the standing `measured-bothPass` rule.
* **One target only.** `SwiftInferCore`. The other five are unmeasured on this path.
* **41% Unverifiable bounds the claim**, and the bound is honest rather than hidden: the
  report separates *not tested* from *passed*, which is the distinction the withdrawn 2026-07
  road test got wrong when a hardcoded Pass 2 made zero-trial runs read as `bothPass`.

---

## §9 Re-run at kit `v3.28.0` (2026-08-09)

Same corpus (`SwiftInferCore`), same command, a release binary built from the branch that
bumps the kit pin. **Two variables moved against §8.3.2 and that is stated rather than
buried:** the kit version *and* `e5731a9`'s nested-carrier qualification, on a tree 25
commits past §8's `ca2e73c`. This tests §8.3.3's prediction; it does not isolate a cause.

**The configuration was verified, not assumed.** The survey workdir's `Package.resolved`
names revision `b59cdb4` and its `Package.swift` declares `from: "3.28.0"` — so the stubs
really did build against the new kit. That check exists because §8.3.2's method note warns
that a pin which fails to move makes a null result read as a finding, and because the
subject worktree was checked out before the pin commit and still declares `3.27.1`; `from:`
ranges unify upward, which is an argument, and the resolved file is the evidence.

| | §8 (kit 3.27.1) | §9 (kit 3.28.0) |
|---|---|---|
| Proven | 81 | **82** |
| Disproven | 1 | 1 |
| Unverifiable | 63 | **61** |
| Inconclusive | 8 | **9** |
| total picks | 153 | 153 |

The single `Disproven` is unchanged — `BuildIdentity.versionString`, counterexample
`XO8hGC` — independently reproducing §8.2's false-law finding on a different kit.

### §9.1 The §8.3.3 prediction held, and the marquee row is Proven

`ProtocolCoverageAudit  homomorphism  lawTotal(for:)` now **executes and holds**. Its
trajectory across three configurations is the whole result:

```
? lawTotal(for:)  (unsupported-carrier: Finding)                      ← 3.27.1        (§8.3)
· lawTotal(for:)  (build-failed: cannot find type 'Finding' in scope) ← kit 0720714   (§8.3.2)
✓ lawTotal(for:)                                                      ← 3.28.0 + e5731a9
```

The stub now writes `Generator<ProtocolCoverageAudit.Finding, …>` qualified. **Both halves
were required**: the kit had to derive a plan for a nested type, and our emitter had to
write its qualified path. Neither alone moves the row, which is exactly what §8.3.3 said
and is now measured rather than predicted.

This is also the row §8.3.3 called out as *"the tool proposes a law it cannot itself test"*
— the law §0 landed as `LawTotalHomomorphismPropertyTests` only after hand-writing a
`Finding` generator. The tool can now test it itself.

### §9.2 Three build failures, three different causes

§8.4 filed two build failures under one heading — *"the per-entry `@testable import` does
not reach a nested carrier"*. The re-run has three, and only one of them is that:

| row | cause | verdict |
|---|---|---|
| `RefutedExpectation.statesAFork(…)` — `cannot find type 'Coverage' in scope` | **residual bug in `e5731a9`** | **FIXED — §9.4** |
| `Visitor.isStaticOrSelfMemberAccess(_:)` — `cannot find 'Visitor' in scope` | ambiguous: **7 declaration sites** | fix declining correctly |
| `NonDeterministicAPIs.matches(_:)` — `cannot find 'NonDeterministicAPIs' in scope` | `private` at file scope | **relabel DECLINED — §9.5** |

**`Coverage` is the actionable one, and it is small.** The emitted stub qualifies the
*values* and not the *type annotation*:

```swift
let generator2: Generator<Coverage, some SendableSequenceType> =   // ← unqualified
    Gen.oneOf(
    Gen.always(RefutedExpectation.Coverage.notApplicable).eraseToAny(),   // ← qualified
```

`Finding` gets both because it is the **generator carrier**, which is what `e5731a9`
fixed. `Coverage` is a **parameter type** of a four-argument predicate and reaches the
stub through a different emit path. Same defect class, one site missed — and it was
invisible until a carrier appeared in the parameter position rather than the carrier
position.

**`Visitor` is the fix working.** Seven declaration sites across `SwiftInferCore` and
`SwiftInferTemplates`, so `VerifyCommand+NestedCarrier`'s never-guess rule declines.
Closing it needs module-aware resolution, not a wider name lookup. The falsifier is
narrowed to this case rather than retired.

**`NonDeterministicAPIs` is misfiled.** It is `private enum` at file scope in
`BodySignalVisitor.swift`, and `@testable` promotes `internal`, not `private`. The survey
already has an `internal-api-not-accessible` bucket holding 27 rows that describes it
exactly; reporting it as `build-failed` calls an accessibility decline a tooling error.
The remedy is §2's, not a qualification fix: lift the law to a reachable caller.

### §9.3 Can the unsupported carriers be supported?

**20 rows decline `unsupported-carrier`** (not 18 — a first count used a character class
that dropped carriers containing `[`, `?` or a space). They are four different questions,
and the doc has twice filed them under one:

| group | rows | verdict |
|---|---|---|
| syntax nodes + `ArraySlice<CodeBlockItemSyntax>` | 9 | **supportable today** |
| our own visitors (`FunctionScannerVisitor`, `BodySignalVisitor`, `Visitor`) | 5 | correct silence — a traversal is not a value |
| our own value types (`SamplingSeed`, `FunctionSummary`, `Effect`, `Ranked<Record>`, `String.Index`) | 5 | a real gap; `static func gen()` is the cheap route |
| `S`, a generic parameter | 1 | unsupportable by construction |

**The 9 declined for want of an import, not for want of a generator.** The kit's coverage
is *generic* — `public extension Gen where Value: SyntaxProtocol { static func syntaxNode() }`
— which is why grepping `PropertyLawSyntax` for those type names finds nothing and reads as
absence. `ArraySlice<…>` is `GeneratorPlan.arraySlice` in `PropertyLawCore` and not
syntax-specific at all.

**Wired and measured, same afternoon (arm A = §9's run, arm B = the same binary with
`PropertyLawSyntax` declared and `StrategistDispatchEmitter.kitSyntaxNodeRecipe` routing
to `Gen<T>.syntaxNode()`):**

| | arm A | arm B |
|---|---|---|
| Proven | 82 | **83** |
| Unverifiable | 61 | **60** |
| `unsupported-carrier` rows | 20 | **16** |

**All 6 bare syntax-node rows moved. Only 1 became Proven.** That gap is the result:

| arm A row | arm B |
|---|---|
| `ReducerDiscoveryVisitor  declaresReducerConformance` (`InheritanceClauseSyntax?`) | **✓ Proven** |
| `Visitor  isStatic` (`DeclModifierListSyntax`) | `internal-api-not-accessible` |
| `MemberBlockInspector  isStaticOrClass` (`DeclModifierListSyntax`) | `internal-api-not-accessible` |
| `EqualityBodyClassifier  iteratesAZipOfBoth` (`StringLiteralExprSyntax`) | `internal-api-not-accessible` |
| 2 rows (`CodeBlockItemSyntax`, `DictionaryExprSyntax`) | `unsupported-carrier: BodySignalVisitor` |

**This is the standing rule measured again: a refuter that fires first hides every refuter
behind it.** Five of the six picks were blocked by *two* independent things, and reading the
code could not say so — the generator gap was simply the one that reported. Three turn out to
have unreachable subjects (§2's case: lift the law, do not widen access) and two have a second
unsupported carrier in the same signature, the enclosing visitor.

**So the honest gain is `+1 executed law` and `5 truer diagnoses`, not "9 carriers
supported".** The rows that did not become Proven are better off — *the subject is
unreachable* is actionable where *no generator for the carrier* was a dead end pointing at
the wrong repo — but a reader counting laws should count one.

**The prediction was 7 of 9 and the answer is 6 of 9.** The miss is arithmetic, not
conceptual: three rows are collection spellings (`[CodeBlockItemSyntax]` ×2 and
`ArraySlice<CodeBlockItemSyntax>`), not two, and `kitSyntaxNodeRecipe` declines all of them
by design — they reach the kit through `GeneratorPlan.array` / `.arraySlice` over the
element. They did **not** move, so that path does not currently pick up the element recipe.
Open, and cheaper to state than to guess at: the composite path never consults the syntax
fallback for its element type. **FIXED — §9.6.**

**What was NOT touched, deliberately.** The 5 visitor rows stay unsupported — a traversal is
not a value — and `S` stays unsupportable, being a generic parameter with no concrete type.
The 5 our-own-value-type rows (`SamplingSeed`, `FunctionSummary`, `Effect`, `Ranked<Record>`,
`String.Index`) are untouched by this change and remain the largest addressable group.


### §9.4 The `Coverage` residual is fixed (2026-08-09)

`qualifyingNestedCarrier` had **exactly one production call site** — the generator carrier
in `VerifyCommand+TemplateDispatch.swift:163`. The n-ary parameter loop in
`StrategistDispatchEmitter+Totality` resolved each parameter from raw `typeText` and never
went through it.

**That is why `e5731a9` looked complete.** For a unary law the carrier and the parameter are
the same type, so one call site covers both; it took a four-argument predicate with a nested
type in the *third* slot to separate them. The symptom was two adjacent lines disagreeing —
values qualified, annotation not:

```swift
let generator2: Generator<Coverage, some SendableSequenceType> =        // ← wrong
    Gen.oneOf(Gen.always(RefutedExpectation.Coverage.notApplicable)…)   // ← right
```

Two changes at that site. Parameters now pass through the qualifier. And the shape lookup
prefers the **qualified** key — `TypeShapeBuilder` groups `allShapes` by
`TypeDecl.qualifiedName`, so the old bare lookup missed *every* nested type and the
strategist derived with no shape at all; the bare fallback preserves prior behaviour for
names the qualifier leaves alone.

**Measured, same corpus and binary discipline as §9:**

| | arm B | arm C (this fix) |
|---|---|---|
| Proven | 83 | **84** |
| Inconclusive | 9 | **8** |
| `build-failed` rows | 3 | **2** |

The pick did not merely stop failing to build — it **executes and holds**. The two
remaining `build-failed` rows are the two that should not clear: `Visitor` (ambiguous, and
the qualifier is right to decline) and `NonDeterministicAPIs` (`private` at file scope, an
accessibility decline misfiled as a tooling error — §2's remedy, not a qualification one).

**The transferable point is about call sites, not carriers.** A rewrite rule with one call
site is a rewrite rule that has been applied to one of the places that needed it, and
nothing in the type system says how many those are. Guarded by
`NestedParameterQualificationTests`.


### §9.5 The accessibility relabel was built, measured and REVERTED (2026-08-09)

§9.2 called `NonDeterministicAPIs` the cheapest remaining item: the row is correctly
*declined*, just under `build-failed` when `internal-api-not-accessible` — a bucket that
already holds 30 rows — says the true thing. It is not cheap, and the reason is a fact
about the index that reading its purpose does not give you.

**Why the obvious fix is not available.** `architecturalPendingDetail` is a pure
`(stdout, stderr) -> String?` classifier keyed on `is inaccessible due to '<level>'`, which
is what Swift emits for an **`internal`** member. A **`private`** type at file scope emits
`cannot find 'X' in scope` instead — the name does not resolve at all. That string cannot
be mapped on its own, because it is *also* what an unqualified nested carrier produces:
`Visitor` fails with exactly the same diagnostic. Relabelling it would be **worse than the
wrong bucket**, turning a live unresolved-nesting bug into a settled "cannot reach this"
verdict. The value-vs-type spelling does not separate them either; both are value-position
references.

**The design that was built.** Thread the index's type-name set into the classifier: a leaf
name matching no key was never scanned, therefore not test-visible, therefore an
accessibility decline; a name that matches stays `build-failed`. Written with an
empty-set-answers-false guard and a conservative mixed-output rule, plus seven tests.

**It is a no-op, and the premise is false.** Arm D: `build-failed` **2 → 2**, the row
unmoved. One query against the survey's own `index.json` says why:

```
typeShapes keys: 283
NonDeterministicAPIs keys: ['NonDeterministicAPIs']
```

**`TypeShapeBuilder` indexes declarations regardless of access.**
`EnclosingTypeAccess.notVisibleToTests` gates *function candidacy*, not type-shape
indexing — so a `private` type is in the index like any other, and "absent ⇒ private" is
false on the exact case it was written for. The premise came from reasoning about what the
index is *for* rather than looking at what is *in* it.

**Reverted rather than kept**, because the arm is not merely inert: absence from a 283-type
index means a genuinely unknown name — an external type, a typo, a real unresolved symbol —
and those would start reporting as accessibility declines. A signal that cannot fire on its
target and can fire on others is worse than none.

**What would work is carrying the access level** on the shape rather than inferring it —
`IndexedTypeShape` has no such field and `SemanticIndexEntry+Codable` has explicit coding
keys, so it is a schema addition plus decode-tolerance for existing indexes. That is real
work on persisted state to correct a label on a row whose *verdict* is already right, so it
is **recorded as declined-for-now** rather than queued: the two open generator items each
add executing laws, and this adds none.
(falsifier: `IndexedTypeShape.accessLevel`)

**One thing the same query corrected in passing.** §9.2 describes `Visitor` as ambiguous
across seven declaration sites. The index holds **both** `ViewModelProtocolScanner.Visitor`
*and* a bare `Visitor` key, so the candidates are not uniformly qualified. The verdict is
unchanged — still ambiguous, still correctly declined — but anyone building
`ambiguousNestedCarrierResolution` should check that mechanism rather than inherit the
seven-qualified-siblings picture from §9.2.

**Method note.** This is the `domain-transfer-signal` practice landing on a classifier
instead of a veto: the rule was scored against the case it targets *and* the cases it must
not touch, and it failed on the first. The whole cost was one build and one survey because
the prediction was written down first — `build-failed` 2 → 1 with Proven held at 84 — so
the null result was legible immediately rather than needing interpretation.


## §9.6 Syntax nodes in leaf position (2026-08-09)

§9.3 left exactly three rows declining — `[CodeBlockItemSyntax]` ×2 and
`ArraySlice<CodeBlockItemSyntax>` — and named the cause. It was right.

`resolveRecipe` consults the syntax tables for the **top-level** carrier, so
`CodeBlockItemSyntax` derives. `[CodeBlockItemSyntax]` takes the composite branch instead,
where `DerivationStrategist.composedGenerator` recurses through `Array`/`Set`/`Optional`
and hands each **leaf** to `resolve` — a resolver that knows only the indexed shape
universe. A swift-syntax node has no indexed shape, so the leaf answered nil and the whole
composition collapsed, for an element type the emitter generates perfectly well one call
earlier. `syntaxAwareResolve` wraps the resolver: base first, then curated, then generic.

**The base resolver is never overridden**, which is the arm that matters — a type the
module declares keeps its real shape even if its name ends in `Syntax`. And the leaf
carries its own imports on the `ComposedGenerator`, which the composite branch already
unions in, so the collection case never has to know its element wants `PropertyLawSyntax`.

**Measured (arm E), and the prediction was exact:**

| | arm D | arm E |
|---|---|---|
| Proven | 84 | 84 |
| Unverifiable | 60 | **59** |
| Inconclusive | 8 | **9** |
| `unsupported-carrier` rows | 16 | **13** |

| row | before | after |
|---|---|---|
| `DedupGateClassifier.effectDominatedByGate` | `unsupported-carrier` | `internal-api-not-accessible` |
| `EqualityBodyClassifier.drawsFromTwoIterators` | `unsupported-carrier` | `internal-api-not-accessible` |
| `DedupGateClassifier.hasUngatedAccumulator` | `unsupported-carrier` | **`parse-error`** |

The third row is the proof the gap closed: the generator ran, produced a
`[CodeBlockItemSyntax]`, and the subject trapped — a real trial, reported as evidence about
the generator's domain rather than about the law.

### §9.6.1 Three fixes, three exact predictions, ZERO new executing laws

This is the third consecutive generator gap closed on this corpus, and the pattern is now
strong enough to state as a finding rather than a coincidence:

| fix | rows moved | became Proven |
|---|---|---|
| §9.3 syntax carriers | 6 of 6 | **1** |
| §9.4 parameter qualification | 1 of 1 | **1** |
| §9.6 syntax leaves | 3 of 3 | **0** |

Ten rows moved; **two** laws execute that did not before. Every other row landed on a
second, independent blocker — overwhelmingly `internal-api-not-accessible`, whose bucket
has grown from 27 to 32 across these three changes while Proven went 82 → 84.

**The generator gap was never the binding constraint on this corpus; ACCESSIBILITY is.**
That is §2's finding arriving from the opposite direction — §2 reasoned from source that
58% of non-`predicate` CLI subjects are `private`, and the survey has now walked into the
same wall three times from the generator side. The remaining generator work
(`SamplingSeed`, `FunctionSummary`, `Effect`, `Ranked<Record>`, `String.Index`) should be
expected to behave the same way: the rows will move and mostly not execute.

**What this does NOT say is that the fixes were not worth making.** A row reporting
*the subject is unreachable* is actionable — §2's remedy is to lift the law to the nearest
reachable caller, which is exactly what `HashPrefixLookupPropertyTests` did and where the
metamorphic strengthening came from. A row reporting *no generator for the carrier* points
at the wrong repo entirely. Ten rows now name their real blocker. But the honest headline
for three changes is **+2 executing laws**, and anyone reading a bucket count as progress
should read this table first.

## §9.7 The tool already knew: `subjectNotVisibleToTests` (2026-08-09)

§9.2 filed `NonDeterministicAPIs` as an accessibility decline misfiled as `build-failed`
and called relabelling it the cheapest remaining item. §9.5 then measured a relabel and
**reverted it** — inferring privateness from absence in the index is false, because
`TypeShapeBuilder` indexes private declarations like any other.

Both were looking in the wrong place. **The verdict already existed, one stage earlier.**

`accessRestriction` gets this right at scan time: `private enum NonDeterministicAPIs`
pushes `.notVisibleToTests`, `matches(_:)` is classified `.enclosingTypeNotVisibleToTests`,
and `withAccessRestrictionCaveats` writes it onto the suggestion in as many words —

> *"NO TEST CAN RUN THIS LAW AS WRITTEN"*

— as **prose**. `StructuralBlocker` keys on `Signal.Kind`, so nothing downstream could act
on it, and `verify` built the stub anyway and filed *cannot find 'X' in scope* as
`build-failed`: an instrument-failure bucket for a fact known before the build started.

`Signal.Kind.subjectNotVisibleToTests` says it as a signal. No schema change, no new
persisted field — the channel (`score.signals` → `StructuralBlocker.reason` →
`SemanticIndexEntry.structuralBlocker` → `structurallyBlockedRecord`) already ran end to
end and was carrying one kind.

**Weight 0, deliberately.** §2's remedy is to LIFT the law to the nearest reachable caller,
not widen the helper's access; demoting the row would suppress the advice it exists to give.

**Two of the four restrictions only.** `.internalOrSPI` is genuinely reached by `@testable`,
and blocking it would silently stop verifying laws that pass today. `.nestedLocal` is also
unreachable but is left out until measured. The asymmetry is tested in both directions.

### Measured (arm F)

| bucket | arm E | arm F |
|---|---|---|
| Proven | 84 | **84** |
| Disproven | 1 | 1 |
| Unverifiable | 59 | 61 |
| Inconclusive | 9 | **7** |
| `not-a-candidate` | 0 | **46** |
| `internal-api-not-accessible` | 32 | **0** |
| `unsupported-carrier` | 13 | **6** |
| `build-failed` | 2 | **0** |

**Proven unchanged is the safety property, not a null result.** A private subject can never
have been Proven — `@testable` cannot reach it — so any movement in Proven would mean a
reachable row had been blocked. It was checked row-by-row, not inferred: no Proven row from
arm E is absent in arm F.

**46 rows — 30% of the corpus — now decline on the tool's own analysis, before a build**,
rather than by pattern-matching compiler output after one.

### §9.7.1 Three earlier findings are corrected, all in the same direction

**(a) `build-failed` is ZERO, including `Visitor`.** §9.2 called it an ambiguous nested
carrier correctly declined. That was true and **not the binding constraint**: `Visitor` is
private, so it could never have run whatever the qualifier decided. A diagnosis can be
correct about a mechanism and wrong about which mechanism is load-bearing.

**(b) 7 of 13 `unsupported-carrier` rows were accessibility-blocked all along** —
`BodySignalVisitor` ×4, `Visitor`, `Ranked<Record>`, `String.Index`. They were reported as
generator gaps where no generator would have helped.

**(c) §9.6.1's "five remaining value types" is wrong; there are THREE** — `Effect`,
`FunctionSummary`, `SamplingSeed`. Of the other three rows, `FunctionScannerVisitor` ×2 is a
traversal (correct silence) and `S` is a generic parameter (unsupportable by construction).

This **strengthens** §9.6.1 rather than undermining it. The generator chase was even less
load-bearing than that table showed, because part of what it was chasing was never a
generator problem. The corpus has now said the same thing four times: **accessibility is the
binding constraint, and every measurement that looked like carrier reach was partly this.**

### §9.7.2 Method — the previous attempt was the reason this one worked

§9.5 built the wrong fix and reverted it, and that was not wasted. It established that the
index cannot answer *is this private*, which is what sent the search one stage earlier to
where the answer already was. The generalisable form: **when a downstream stage cannot tell
two cases apart, check whether an upstream stage already did** — the tool had been printing
the right sentence for weeks and only prose carried it.


## §9.8 Ambiguous nested carriers — declined, with the rule recorded (2026-08-09)

§9.2 narrowed the nested-carrier deferral to the ambiguous case: `Visitor` has several
declaration sites, `qualifyingNestedCarrier` refuses to choose, and closing it needs
module-aware resolution. **§9.7 removed its only witness** — `Visitor` is `private`, so it
is now blocked as `subjectNotVisibleToTests` before a build, and would never have run
whatever a resolver decided.

### The population is real; the reachable population is empty

Structural scan of `Sources/` — 876 type declarations, 784 distinct leaf names:

| | count |
|---|---|
| ambiguous leaf names (≥2 declarations) | 35 |
| …with a nested declaration | 34 |
| …and at least one non-`private` declaration | **27** |

Led by `Inputs` ×19 (all `public`), `Result` ×12, `Resolved` ×9, `Kind` ×7, `Collector` ×6.
So ambiguity has not gone away — this is the same `Inputs`-nested-in-40-odd-emitters shape
CLAUDE.md's dead-code note already records.

**But none of the 27 is ever a carrier.** Checked against the arm-F survey: zero rows, in
any bucket, take one of them as a carrier. They are emitter input structs and internal
result types — plumbing, never the subject of a law. And arm F has **zero** declines
attributable to ambiguity, in any bucket.

### Why declining is not merely cheaper

`qualifyingNestedCarrier`'s own doc states the decisive fact: *"a wrong qualification fails
to compile just as surely as no qualification — while being harder to read."* **Declining
and guessing wrong have the same outcome.** Only a *correct* resolution gains anything, and
there is no case on this corpus to be correct about. Building it now would ship an
unexercised path — the shape §3.6 records for `statefulGuards:`, plumbed end to end and
never once passed, invisible to `make dead-code` because only the parameter was dead.

### The rule, recorded so it is not re-derived

It is **not** a heuristic, which is why it is worth keeping. Prefer the candidate whose
parent path matches the call-site owner's qualified path — already carried on
`entry.qualifiedTypeName`, which `resolveFunctionCalls` has qualified since 2026-08-05.
`lawTotal(for:)` is declared on `ProtocolCoverageAudit` and quantifies over `Finding`, so
`ProtocolCoverageAudit.Finding` wins. That is lexical scoping, the same way Swift resolves
the name in the source. Fall back to declining when no candidate's parent matches — two
types called `Finding` under unrelated parents still give no way to choose.

### What reopens it

A row that declines because of ambiguity, on any corpus. This one has none, and one corpus
is not a general claim: a syntax-visitor corpus like SwiftProjectLint has different carrier
shapes and was never checked here. **The trigger is a witness, not an argument** — and the
population scan above is the cheap way to look for one before building anything.

## §9.9 "Three real generator gaps" was three different things (2026-08-09)

§9.7.1 narrowed the `unsupported-carrier` remainder to three carriers and called them the
real generator gaps: `Effect`, `FunctionSummary`, `SamplingSeed`. Opening the rows shows
**one of the three is not a generator gap at all**, and the other two are not the same kind
of problem as each other.

| carrier | actual cause |
|---|---|
| `SamplingSeed` | **carrier-attribution bug.** A caseless namespace enum — no value of that type exists |
| `Effect` | **cross-module.** `public enum` in SwiftEffectInference with an associated value (`externallyIdempotent(keyParameter: String?)`), so not `CaseIterable`; needs enum-payload derivation *and* a dependency shape |
| `FunctionSummary` | **the one real local gap.** `public struct`, 8 stored properties, 2 user inits → Tier 6 `.initializerBased`, and needs `Parameter` and `SourceLocation` to derive too |

**This is the fourth time in §9 that a bucket label turned out to be several problems
wearing one name** — §9.2's three build failures, §9.3's four groups, §9.7's 46 rows, and
now this. The generalisable practice is uncomfortable and cheap: **a decline-reason count is
a hypothesis, not a finding, until the rows are opened.** Every count in §9 that was
reported without opening rows has been corrected by opening them.

### The `SamplingSeed` defect

`SamplingSeed` is `public enum SamplingSeed { public struct Value { … }; public static func
derive(…) -> Value }` — a namespace. `RoundTripTemplate:61` takes
`carrier: { $0.forward.containingTypeName }`, which is **right for an instance method**,
where the containing type is the value being round-tripped, and **wrong for a `static` on a
namespace**, where the containing type has no values at all.

Reported as `unsupported-carrier: SamplingSeed`, it reads as a generator gap and sends a
reader to write `static func gen() -> Generator<SamplingSeed, _>` — a function that cannot
return.

**Declined rather than re-attributed, deliberately.** The obvious repair — take the forward
function's parameter type — is ambiguous for a round trip, which has *two* legitimate
carriers depending on which direction the stub runs: `g(f(a)) == a` generates `A`,
`f(g(b)) == b` generates `B`. *A caseless enum has no values* requires no such choice and
cannot be wrong. **Re-attribution stays open and would supersede this.**

**The predicate is provable, not heuristic.** Swift does not permit adding cases to an enum
in an extension, so `kind == .enum && enumCases.isEmpty` is a statement about inhabitants,
not about what the scan happened to read.

**And it has a load-bearing dependency worth stating.** This is sound only while `enumCases`
is populated. That field was dropped from the index once — `IndexedTypeShape.EnumCase`
records it — and a `String`-raw enum then fell through to `.rawRepresentable`, hanging two
verifiers at 99.9% CPU for the better part of an hour with the survey reporting nothing. If
that regresses, this arm converts a hung verifier into a **silent decline**: quieter, and no
more correct.

### Measured (arm G)

| | arm F | arm G |
|---|---|---|
| Proven | 84 | **84** |
| `unsupported-carrier` | 6 | **5** |
| `not-a-candidate` | 46 | **47** |

```
? SamplingSeed  round-trip  derive(fromIdentityHash:)
  (not-a-candidate: carrier `SamplingSeed` is a caseless enum — a namespace
   with no values, so no generator can exist for it)
```

Proven unchanged, as it must be: this is a relabel, and the law it declines was very likely
false anyway — `renderHex(derive(fromIdentityHash: s)) == s` is a hash round-trip that
cannot hold.

**The remaining five are now honest.** `Effect` (cross-module), `FunctionSummary` (a real
local derivation gap), `FunctionScannerVisitor` ×2 (a traversal — correct silence), and `S`
(a generic parameter — unsupportable by construction). Neither remaining actionable row was
attempted here: `Effect` needs dependency shapes, and `FunctionSummary` wants the kit to
derive through a user init, which is kit-side work worth measuring on more than one row.

---

## §10 Third pass at `af7ebc9` (2026-08-10)

29 commits past arm G (12 touching `Sources/`), almost all of it *error-reporting*
hardening — the "report the swallow" series — plus dependency-scan reporting. Release
binary built from `af7ebc9` into an isolated scratch path.

**The measured-verify path did not move, and the discover surface moved a great deal for a
reason that is not progress.** The second half is the finding.

### §10.1 `prove-then-show` is bucket-for-bucket identical to arm G

`prove-then-show --target SwiftInferCore --budget small --max-parallel 4`, run in a fresh
`git worktree` so `.swiftinfer/` is absent by construction (§8's method note).

| | arm G (2026-08-09) | §10 (2026-08-10) |
|---|---|---|
| Proven | 84 | **84** |
| Disproven | 1 | **1** |
| Unverifiable | 61 | **61** |
| Inconclusive | 7 | **7** |
| `not-a-candidate` | 47 | **47** |
| `unsupported-carrier` | 5 | **5** |
| `build-failed` | 0 | **0** |
| total picks | 153 | **153** |

Every bucket identical. That is the **correct** result and is recorded as a control, not as
a null: the 12 source commits were about reporting errors that were previously swallowed,
and a change to error *reporting* that moved a verification bucket would mean it had
changed verification. `BuildIdentity.versionString` is still the single Disproven with
counterexample `XO8hGC` — §8.2's false law reproducing a third time — and §9.1's marquee
row `ProtocolCoverageAudit.lawTotal(for:)` is still Proven.

### §10.2 THE HOLE — `discover` promotes on verify evidence of unbounded age, and the identity hash cannot see a body change

> **FIXED 2026-08-10 — `SubjectFingerprint`. See §10.8 for the shipped design and its
> measured effect.** The identity hash is deliberately NOT changed: evidence now carries a
> fingerprint of the body it was measured against, and is applied only when that matches.


**Symptom first.** The same binary, the same six targets, the same afternoon — run once in
the working repo and once in a clean worktree. The only difference is the presence of
`.swiftinfer/`:

| target | clean total | working total | clean "Strong" | working "Strong" |
|---|---|---|---|---|
| SwiftInferCore | 129 | **138** | 7 | **36** |
| SwiftInferTemplates | 115 | **123** | 5 | **14** |
| SwiftInferCLI | 75 | **92** | 4 | **22** |
| SwiftInferTestLifter | 25 | 25 | 4 | 4 |
| SwiftInferKitEvidence | 0 | **1** | 0 | **1** |
| SwiftInferMacroImpl | 0 | 0 | 0 | 0 |
| **total** | **344** | **379** | **20** | **77** |

The clean arm is within noise of §7.6's 342 / 24. **Read against a remembered count, the
working-repo arm reads as "Strong tripled since the last road test."** It did not. Nothing
in scoring changed — the only signal added since 2026-08-08 is
`subjectNotVisibleToTests`, at weight 0. The entire delta is `.swiftinfer/verify-evidence.json`.

This is CLAUDE.md §10.3's rule earning itself again, in a new way. That rule was written
about *flags* (`--include-possible` moved the headline 20%). The same failure has a second
cause nobody had recorded: **a persisted evidence store, whose contents depend on what was
run in this directory last week.**

**What is in the store.** 349 records, all distinct identity hashes:

| `capturedAt` | records |
|---|---|
| 2026-08-04 | 9 |
| 2026-08-05 | **187** |
| 2026-08-10 | 153 |

Of the 150 `measured-bothPass` records — the ones paying `+50` — **66 are from 2026-08-05**.
On `SwiftInferCLI` the picture is starker: **all 28** evidence-promoted rows are dated
2026-08-05, five days and ~40 commits stale. Not one is current.

**`discover` never asks.** `VerifyEvidence` records `capturedAt` and `swiftInferVersion`,
and ten CLI files reference staleness — `grep -rn "stale" Sources/SwiftInferCLI/Discover*.swift`
returns **nothing**. The row renders `✓ Verify: bothPass — defaultTrials=100 …` with no
date, no commit, no provenance of any kind. This is §7.4's finding — *a row a human cannot
audit* — arriving on a different channel, and §7.4's remedy (name the source) is the same one.

**And `swiftInferVersion` cannot stand in for it.** All 349 records say `1.148.0`, because
that is a *package* version and the package has not been bumped across ~40 commits. The
field varies for an unrelated reason instead — 153 records read
`1.148.0 (unattributable build)`, distinguishing *how the binary was built*, not *when*.
A staleness key that does not move when the code moves, and does move when it does not, is
worse than none.

#### The soundness half, and it was tested rather than argued

`SuggestionIdentity`'s own docstring says the hash is computed from *"(template ID, function
signature canonical form, AST shape of property region)"* — and then: *"M1.5 uses template
ID + canonical signature(s) only — the AST-shape addition is deferred until M6."* The
canonical input is `"<template>|<canonicalSignature>"`. **The body is not in the hash.**

So a body-only edit that falsifies the law leaves the identity unchanged, and stale evidence
keeps attaching. Measured, in a throwaway worktree with the store copied in:

```swift
 public static func strippingGenericParameters(_ name: String) -> String {
-    guard let openAngle = name.firstIndex(of: "<") else { return name }
+    guard let openAngle = name.firstIndex(of: "<") else { return name + "!" }
     return String(name[..<openAngle])
 }
```

`f("Foo")` is now `"Foo!"` and `f(f("Foo"))` is `"Foo!!"` — flatly not idempotent, signature
byte-identical.

| arm | verdict |
|---|---|
| mutant **+ evidence** | **`Score: 100 (Verified)`** · `✓ Verify: bothPass — defaultTrials=100 edgeTrials=100 edgeSampled=0 (+50)` |
| mutant, **no evidence** (control) | `Score: 50 (Likely)`, no verify line |

Identity `0x8454E302FAC7F5BB` in **both** arms. The control is what makes this a measurement
rather than an anecdote: the evidence store alone produces the false verdict, and the hash is
provably blind to the change that falsified the law.

**This is the tool's strongest claim failing in its safest direction.** `Verified` is the only
execution-backed tier — the one a reader is *entitled* to trust more than a static score — and
it can be carried across an arbitrary rewrite of the subject. Appendix C's confident-zero
inverted: a confident *positive*.

**No guard covers it.** No test asserts that evidence is invalidated by a body change, and the
`canonicalInput` assertions in `Tests/` pin the `"<template>|"` prefix — i.e. they ratify the
shape that omits the body.

### §10.3 `--stats-only` structurally cannot say `Verified`

> **FIXED 2026-08-10 — and fixing it uncovered a worse one right next to it. See §10.9.**


The renderers are asymmetric. `SuggestionRenderer.render(_:verifyEvidenceByIdentity:)` applies
`.promoted(byVerifyOutcome:)`; `SuggestionRenderer.renderStats(_ suggestions:)` takes **no
evidence parameter at all**, so the tier it prints falls back to `tier(forScore:)` — and a
score of 100 is `Strong`.

Measured, same run, two views:

| target | full output | `--stats-only` |
|---|---|---|
| SwiftInferCore | 33 Verified + 3 Strong | **36 "Strong"** |
| SwiftInferCLI | 18 Verified + 4 Strong | **22 "Strong"** |

Both add up exactly, which is the proof of mechanism rather than a correlation. The stats view
**inflates `Strong`** (36 reported, 3 true) and simultaneously **hides the tool's best result**
(33 execution-backed verdicts rendered as static ones). It is the view a CI dashboard reads —
the same complaint as §5, now with a second instance and a one-parameter cause.

### §10.4 The known-false `booleanStem` law is re-proven every run, and now renders `Verified`

> **FIXED 2026-08-10 — see §10.11.** The channel existed and was blind: TestLifter's
> counter-signal detector could not read the shape the refutation was written in, and even
> when it fires a demotion cannot remove a `Verified` label that never came from the score.


§8.6(b) established by hand that `ViewModelNameHeuristics.booleanStem` is **not** idempotent
(`isShowing → showing → ing`), that the survey proved it anyway because the derived `String`
generator never draws an English boolean prefix, and banked the **refutation** as
`SurveyedIdempotencePropertyTests`.

Three runs later nothing has changed, and the blast radius has grown:

* `prove-then-show` proves it again this pass (`✓ ViewModelNameHeuristics idempotence booleanStem(_:)`).
* That writes a fresh `measured-bothPass` record.
* `discover` reads it back and renders **`Score: 85 (Verified)`**.

So the repo now contains a passing test whose entire purpose is to assert the law is false,
and the flagship developer-facing command labels the same law with its strongest tier. **The
two never meet.** `VerifyEvidenceScoring` has a `verifyDisproven` veto, but it fires on
`.measuredDefaultFails` — a *machine* refutation. There is no channel by which a refutation
established by a **human**, and banked as a test, re-enters the evidence loop.

This is not the generator-domain lesson §8.6 already drew; that one is recorded and stands.
What is new is that the false verdict is now **self-regenerating** — each survey re-mints the
evidence — and has been promoted from a survey artifact into the default output.

### §10.5 What §10 does not claim

* **The stale-evidence effect is not a bug in persistence.** Evidence feeding back into
  inference is the design (`KitEvidence`, `VerifyEvidence`). What is missing is *provenance at
  the point of reading* and an identity that covers what the evidence was about.
* **The mutation is planted evidence.** Per `fixtures/planted-defect-arm`, it falsifies a
  categorical claim ("a `Verified` row reflects the current body") and **cannot estimate how
  often** a real edit would strand real evidence.
* **One target for the survey.** `SwiftInferCore`. The other five are unmeasured on that path.
* **Nothing was shipped.** No fix is included here; the working repo's `.swiftinfer/` was read
  and never written (timestamps unchanged at 06:33/06:36), and the mutation lived in a
  throwaway worktree that has been removed.
* **The 344 clean total is not comparable to §1.1's 339 or §7.6's 342** as drift — those were
  taken on different binaries. It is quoted only to show the clean arm sits where the last
  road test left it, which is what rules out a scoring change as the cause of the 379.

### §10.6 The pending-falsifier report says the opposite of what it means

> **FIXED 2026-08-10.** `renderPending` gives the report its own verdict phrase; a green run
> now prints `is pending`. The failure path keeps `has landed`, which is correct there.


Found by running the guards after editing docs, not by looking for it.

`DeferralFalsifierTests.pendingPopulationIsVisible` selects the **pending** falsifiers
(`resolves($0.symbol) != .resolved`) and renders them through `Self.render(_:)`, whose line is:

```
\(entry.file):\(entry.line) — falsifier `\(entry.symbol)` has landed
```

So a green run prints:

```
CLAUDE.md:75 — falsifier `Pairing.permuted` has landed
docs/measurements/roadtest-self-dogfood-2026-08-08.md:1120 — falsifier `IndexedTypeShape.accessLevel` has landed
docs/plans/dependency-carrier-imports-scope.md:92 — falsifier `VerifierWorkdir.dependencyProductEdge` has landed
```

All three are **pending** — `grep -rn "accessLevel" Sources/SwiftInferCore/SemanticIndexEntry.swift`
is empty, and the sibling assertion *"no deferral names a falsifier that now exists"* passes,
which is only possible if none of them exists. The wording belongs to the failure path and was
reused for the population report.

**Why it is worth a line rather than a shrug.** This shipped in `d98ed6e` — *"Report the
pending falsifier population, and retire an inert one"* — one of the commits in this very
window, and the report exists precisely so a falsifier cannot go inert unnoticed
(`falsifier-naming-failure-modes.md`). A reader skimming a green run sees three deferrals
announced as resolved and would reasonably go reopen them. **A visibility mechanism that
states the negation of its own finding is worse than silence**, which is the same argument
§9.5 used to revert a signal that could fire on the wrong target.

One-word fix (`has landed` → `is pending` on the report path, or a separate renderer per
path). Not applied here, per §10.5's "nothing was shipped".

### §10.7 `--scan-dependencies` is inert under this document's own recommended method

`prove-then-show --scan-dependencies` is the main new *feature* in this window. It was run
twice against `SwiftInferCore` and recorded **0 dependency shapes both times**, so the output
is identical to §10.1 in every bucket (84 / 1 / 61 / 7) and `EffectResolver
carriesInformationUpward(_:)` still declines `unsupported-carrier: Effect` rather than
`carrier-declared-in-dependency`.

**The reason is a collision between two pieces of this document.** §8's method note recommends
running the survey in a fresh `git worktree`, because `.swiftinfer/` is gitignored and the
index is therefore clean *by construction*. But a fresh worktree has no `.build/checkouts` —
and **a prove-then-show run to completion does not create one**, because it builds its stubs in
a separate verifier workdir. Checked directly: after the §10.1 run finished, the worktree
contained `.swiftinfer/` and **no `.build/` at all**.

So the documented way to get a trustworthy index is also the way to guarantee the new flag has
nothing to read. Neither half is wrong on its own; the two were written against different
preconditions and nothing states the intersection.

**The tool reports this correctly, and that is worth crediting**, because it is exactly what
`27608f7` ("Make the dependency scan say which empty it is") shipped for:

```
warning: dependency scanning was requested, but there is no `.build/checkouts` under <root>
— SwiftPM puts resolved dependency sources there, so nothing could be read.
Run `swift build` first. 0 dependency shape(s) recorded.
```

Without that line this pass would have recorded *"`--scan-dependencies` moves nothing"* as a
finding about the feature, when the truth is that the scan never ran. **A null result that says
which null it is, is the difference between a measurement and a wrong conclusion** — the same
argument `DependencyTypeShapes` makes in its own doc comment about `checkoutsDirectoryFound`.

**One accommodation was tried and FAILED, recorded so it is not repeated.** Symlinking the main
checkout's directory in (`ln -s <main>/.build/checkouts .build/checkouts`) did **not** make the
scan see it: the warning was byte-identical and shapes stayed 0, even though the exact path the
warning names is readable — `os.listdir` returns 11 entries through it, and `SwiftSourceFiles`
explicitly resolves symlinks (`isSymbolicLink` → `resolvingSymlinksInPath()`). **The mechanism
was not isolated** and is deliberately not guessed at here. The honest next step is a real
`swift build` in the worktree rather than a symlink, which costs a dependency build plus a
~40-minute survey and was not spent.

**So the label added by `3035e7e` remains unexercised on this corpus.** `DependencyCarrierLabelTests`
pins it at the unit level and its arms are the right ones (including the must-not-fire arm for a
locally declared type), but no end-to-end run in this repo has yet produced a
`carrier-declared-in-dependency` row. The population that would produce one is `Effect`, and
`dependency-carrier-imports-scope.md` already measures that population at **2 rows** — which is
the reason to fix the label rather than the plumbing, and equally the reason this is a low-value
gap to close rather than an urgent one.

---

## §10.8 The fix — validate evidence, do not destabilise identity (2026-08-10)

§10.2 measured that a body-only edit falsifying a law left the suggestion identity unchanged,
so stale `measured-bothPass` evidence still attached and `discover` reported the now-false law
as `Verified`. The obvious repair — put the body in the identity hash — was **considered and
rejected**, and the reason is the useful part.

### Why not fix the identity hash

`SuggestionIdentity` is not only an evidence key. It keys `decisions.json` (accept/reject),
`baseline.json` and drift, the deterministic sampling seed, and the user-written
`// swiftinfer: skip 0x…` markers that live in source. Two PRD guarantees say so explicitly:

* §7.5 — *"`// swiftinfer: skip [hash]` markers in source survive regeneration."*
* §16 #1 — *"The AST-shape suggestion-identity hash survives renames and signature-preserving
  refactors."*

Folding the body into that hash would void a user's skip markers and reset their decisions and
baseline every time they edited a function. **The bug is not that identity is stable — identity
is stable on purpose. The bug is that nothing else was answering the other question.**

### What shipped

Identity is untouched. `VerifyEvidence` gains `subjectFingerprint`, and the outcome is applied
only when it matches the subject's body as scanned *this run*:

| stage | change |
|---|---|
| scan | `FunctionSummary.bodyFingerprint` — `SubjectFingerprint.of(bodyText:)` over the body syntax |
| index | `SemanticIndexEntry.subjectFingerprint`, from the same pass's summaries |
| verify | stamps each record with the entry's fingerprint |
| discover | `VerifyEvidenceScoring` withholds the outcome unless it matches |

Four decisions carry the weight, and each is guarded:

1. **Withheld in BOTH directions.** The premise is *evidence taken against a different body is
   not evidence about this body*; honouring it for promotions but not vetoes would be
   incoherent. A stale `defaultFails` stops suppressing — but the caveat still names the
   refutation, so the warning survives even though the score effect does not.
2. **Weight 0.** A stale pass is not counter-evidence; the law may well still hold. Demoting
   would assert more than is known. Withholding the `+50` is the whole effect; the signal
   exists to make that visible.
3. **A missing fingerprint counts as stale.** Every pre-fix record has none, so nothing can
   establish what it measured. Treating unknown as valid would preserve the defect on exactly
   the population most likely to be stale.
4. **A partial fingerprint is no fingerprint.** A law over two functions returns `nil` if
   either subject is unfingerprintable — validating a round trip against one half would leave
   the other half's edits invisible, which is the hole one layer down.

**Normalization is whitespace-only, and over-invalidation is the deliberate direction.**
Reindenting does not move the fingerprint; a comment change does. Withholding good evidence
under-claims (the row falls back to its static tier, which is true); applying stale evidence
over-claims (the row asserts `Verified` about code nobody ran it against). Keeping comments is
not merely caution: this project *reads comments as evidence*
(`DocstringPropertyCorroborator`), so a comment is not reliably inert here.

### Measured, on the real store

The working repo's 349 records all predate fingerprinting, so all 349 are now withheld. Same
binary discipline as §10.2 — the fixed binary against the same contaminated store, versus the
clean-worktree arm:

| target | working repo, before fix | working repo, AFTER fix | clean worktree (no evidence) |
|---|---|---|---|
| SwiftInferCore | 138 / **36 "Strong"** | 130 / **7** | 129 / 7 |
| SwiftInferCLI | 92 / **22 "Strong"** | **75 / 4** | 75 / 4 |

**`SwiftInferCLI` lands exactly on the clean arm, 75 for 75.** Core is 130 against 129 because
the corpus itself grew by one row — `SubjectFingerprint.normalized(_:)` is a `String -> String`
the fix itself added, and the tool proposes an idempotence law about it. **129 rows carry the
new caveat**, which renders as:

```
⚠ Verify evidence from 2026-08-10T11:36:28Z is NOT being applied: it was recorded before
  swift-infer stamped runs with the subject's body, so there is no way to tell whether it was
  measured on the code above. Re-run `swift-infer verify` for this pick to restore it. (+0)
```

### The cost, stated plainly

**Every existing verify verdict stops counting until re-verified.** That is not a side effect;
it is the fix. Anyone upgrading sees execution-backed rows fall back to their static tiers
until they re-run `verify`, and the caveat tells them why and what to do.

### Guards

`VerifyEvidenceStalenessTests` — 8 laws. The mutation from §10.2 is one of them (same identity,
different body, promotion withheld). **The arm that matters most is the control**: a *matching*
body must still promote, because a gate that withholds everything is indistinguishable from a
broken evidence loop and would read as a clean result. Both absent-fingerprint directions are
asserted separately, and each is required to say which of the two it is. `FieldCoverageReflectionTests`
caught the new field the moment it was added — a `nil` optional is dropped by the synthesized
encoder, so an unpopulated fixture read as *never encoded*.

Four existing suites had to be updated, and how is worth recording: they hand-write evidence
for a fixture and expect it applied, which now requires a real fingerprint. They derive it
through the **same production join** (`subjectFingerprint(of:in:)` in the test support file)
rather than a literal — a hardcoded hash would silently stop matching the first time a fixture
was reformatted, and the arm would then pass only because the evidence was being discarded,
green for the opposite of the intended reason.

### Not fixed here

§10.3 (`--stats-only` cannot say `Verified`) and §10.4 (the `booleanStem` loop has no channel
for a human-established refutation) are untouched and remain open.

---

## §10.9 Fixing the stats view uncovered a contradiction in the one shipped the day before

§10.3 was queued as a one-parameter fix: `renderStats` takes no evidence map, so
`--stats-only` cannot print `Verified`. It is a one-parameter fix. But reading the *full*
renderer to mirror its tier logic turned up a defect in **§10.8's own fix**, shipped hours
earlier and merged.

### The contradiction

`SuggestionRenderer.render` computes the displayed tier as
`score.tier.promoted(byVerifyOutcome:)` — `.verified` is set by the surfacing pipeline rather
than derived from the score (`Tier`) — and it was handed the **raw** evidence map. The
staleness gate lives in `VerifyEvidenceScoring`, one stage upstream.

So a row whose `+50` had been correctly withheld still printed `Verified`, immediately above
its own caveat saying the evidence was not being applied:

```
Score:    100 (Verified)
  ⚠ Verify evidence from … is NOT being applied: it was recorded before swift-infer
    stamped runs with the subject's body …
```

**Measured: 4 such rows on `SwiftInferCore`.** The score was right and the label was wrong,
which is the worse half — a reader takes the tier.

### Why it survived §10.8's guards

`VerifyEvidenceStalenessTests` asserts on `score.total`, `score.tier` and the signal list —
all of which were **correct**. Nothing asserted on *rendered output*, and the rendered tier is
computed independently of the score by design. The guards were complete about the thing they
guarded and blind to the seam beside it.

**The transferable point: a fix that adds a gate must be checked at every consumer of the
thing it gates, not only at the point the gate was installed.** Scoring and rendering both
consume verify evidence, and only one of them learned about staleness.

### The remedy

One rule, one place. `VerifyEvidenceScoring.applicable(evidenceByIdentity:currentFingerprintByIdentity:)`
filters the map by the same `stalenessCaveat` the scorer uses, and the discover render path
passes the **filtered** map to both renderers. Scoring and rendering can no longer disagree
because they are the same decision.

`ApplicableEvidenceTests` pins it, including the arm asserting `applicable` and `applied`
agree in both directions — a filter that diverged from the scorer would reintroduce exactly
this bug — and the control that a *matching* body still survives the filter, since filtering
everything would make the renderer silent about every verified law and read as a clean result.

### Measured after

| | before | after |
|---|---|---|
| rows both `Verified` and "NOT being applied" | **4** | **0** |
| `SwiftInferCore` full render | 4 Verified + 4 Strong | **8 Strong** |
| `SwiftInferCore` `--stats-only` | "36 Strong" (§10.3) | **8 Strong** |

The two views now agree, which was §10.3's whole complaint. Zero `Verified` is correct on this
corpus today: every record predates fingerprinting, so nothing is applicable until a re-verify.

`RenderStatsTierTests` guards the stats side — a `bothPass` row reports `1 Verified` rather
than being folded into `Strong`, the no-evidence line is byte-identical to before (so goldens
are unaffected), and the stats and full renderers are asserted to agree on the effective tier.

---

## §10.10 Re-verify — the loop closes, and the tool refutes a law about the fix itself

The staleness gate (§10.8) made all 349 existing records inert, so only the WITHHOLDING
direction had been demonstrated on this repo. The matching direction — verify writes a
fingerprint, discover matches it, the row promotes — was covered by unit tests and fixtures
and had never run here. This closes that gap.

`prove-then-show --target SwiftInferCore --budget small --max-parallel 4`, fresh worktree at
`d1eaa1f`, binary built from the merged `main`.

### §10.10.1 Buckets are stable

| | §10.1 (arm G parity) | §10.10 |
|---|---|---|
| picks tested | 153 | **156** |
| Proven | 84 | **85** |
| Disproven | 1 | **2** |
| Unverifiable | 61 | 62 |
| Inconclusive | 7 | 7 |

**The +3 picks are the corpus growing, not the tool changing** — §10.8 and §10.9 added
`SubjectFingerprint` and `VerifyEvidenceScoring.applicable`, and the templates propose laws
about them like any other code.

### §10.10.2 The new refutation is a false law, about the fix's own code

```
✗ SubjectFingerprint  idempotence  of(bodyText:)   [counterexample: ]
```

`of(bodyText:)` returns a 16-character digest, so `of(of(x)) != of(x)`. **Correct code, wrong
conjecture** — and specifically the **domain-transfer** class: a `T -> T` whose output is a
different *kind* of thing, so composing it type-checks and means nothing. That is the exact
exclusion `returnExtendsInput`'s rationale names (moved to
`docs/design/signal-kind-rationales.md` earlier the same day), and the one
`fixtures/domain-transfer-signal` measured a veto for and **declined** at 4/12 precision.

Its sibling is the control:

| pick | tier | verdict | reading |
|---|---|---|---|
| `SubjectFingerprint.normalized(_:)` | **Strong 75** | **Proven** | true law — collapsing whitespace twice is idempotent |
| `SubjectFingerprint.of(bodyText:)` | **Possible 35** | **Disproven** | false law — a digest is not its own input |

**Tier predicted the reading, for the third independent time** — after the whole-corpus survey
and §8.2's `BuildIdentity.versionString`, which is also `Possible` 35. *All real bugs are
`Likely`+; all `Possible` refutations are false laws.* Two laws proposed about the same new
type, one held and one refuted, and the tier separated them before either ran.

**Zero defects found in the fix's own code.**

### §10.10.3 The loop closes

New store: **156 records, 153 carrying a fingerprint.**

| | stale store (§10.8) | re-verified store |
|---|---|---|
| `discover` full render | 0 Verified, 8 Strong | **34 Verified**, 3 Strong |
| `discover --stats-only` | 8 Strong | **34 Verified**, 3 Strong |
| rows both `Verified` and "NOT being applied" | 0 | **0** |

The two views agree, and every `Verified` row is now backed by evidence measured against the
body that is there. **Before §10.9 this table would have been meaningless**: the renderer
promoted from the raw map, so rows showed `Verified` whether or not the evidence was
applicable. A `Verified` here now carries information it did not carry yesterday.

### §10.10.4 The 3 records with no fingerprint, and the limitation they expose

All three are `architectural-coverage-pending` — declines, not verdicts — so nothing is lost:
`differential-equivalence` ×2 and `invariant-preservation` ×1, the same rows CLAUDE.md already
records as not running because both `differential` subjects are `private` funcs in test files.

**But the mechanism is worth stating, because it is a standing limitation rather than an
accident.** `forSuggestion` returns `nil` when ANY subject is unfingerprintable — deliberately,
since validating a two-function law against one half would let an edit to the other half
through. The consequence is that **a multi-subject law whose subjects are not all scannable can
never have applicable evidence**, even if it one day produces a verdict. Today that set is
exactly the rows that decline for other reasons, so the cost is zero; it would stop being zero
if a differential pair ever became reachable. Recorded rather than fixed — the alternative
(validate partially) is the hole this rule exists to close.

---

## §10.11 The human-refutation channel existed, and was blind twice over (2026-08-10)

§10.4 recorded that `discover` renders `ViewModelNameHeuristics.booleanStem` at `Verified`
while `SurveyedIdempotencePropertyTests` exists for the sole purpose of pinning that law as
FALSE, and concluded there was *"no channel by which a refutation established by a human, and
banked as a test, re-enters the evidence loop."*

**That conclusion was wrong in an instructive way: the channel was built, and silent.**
`LiftedCounterSignal` + `AsymmetricAssertionDetector` read negative-form assertions out of test
code and apply `-25 .asymmetricAssertion`, with the polarity already stated in its own doc —
*"the user's explicit negative assertion is dispositive: we don't surface a suggestion the test
author has actively contradicted."* It was doing nothing here for **two independent reasons**,
and either alone was enough to hide it.

### Blindness 1 — the detector could not read the shape a human writes

Every matcher keys on syntax. `idempotenceNegativePair` requires both sides of the inequality
to be `FunctionCallExprSyntax`, so it recognises

```swift
#expect(booleanStem(booleanStem(name)) != booleanStem(name))
```

and nothing else. The refutation this repo actually banked reads:

```swift
let once = ViewModelNameHeuristics.booleanStem(name)
let twice = ViewModelNameHeuristics.booleanStem(once)
#expect(once != twice)
```

Both sides are `DeclReferenceExprSyntax`, so the matcher returned nil. **This is §7.3's failure
mode on the negative side** — a detector keyed to the shape the tool imagines rather than the
shape people write — and it is the second time that exact mistake has surfaced in this road
test.

`LocalBindingResolver` substitutes the slice's local `let` bindings into the assertion before
matching, once, so all six negative detectors benefit and any added later inherit it.

### Blindness 2 — a demotion could never have removed the label

Even firing, `-25` against `+50` nets positive. And decisively: **the displayed `Verified`
never came from the score at all.** `Tier.promoted(byVerifyOutcome:)` reads the outcome and
ignores every signal, so no demotion of any size could have removed it. Fixing only the
detector would have moved the number and left the label.

`VerifyEvidenceScoring.isContradictedByAuthor` makes the evidence **inapplicable** — in scoring
and in rendering both, via the §10.9 `applicable` seam. A measurement over a generated domain
cannot outrank a person who has written a counterexample down: `measured-bothPass` means only
*no counterexample in the generated domain*, and the author is telling us where that domain
fell short.

### Measured

`booleanStem` is gone from the output entirely, and the arithmetic says why:

| | before | after |
|---|---|---|
| type-symmetry + value-semantic | 35 | 35 |
| verify `bothPass` | **+50** | **withheld** |
| counter-signal | not firing | **−25** |
| **total → tier** | **85 → `Verified`** | **10 → `.suppressed`** |

**Its absence under `--include-possible` is the proof the counter-signal fired**, and is worth
stating as a method note: 35 alone lands in `Possible` (20..<40) and would be visible with that
flag, so only the `-25` explains the silence. Both halves are confirmed by one observation.

That matches how a MACHINE refutation is already treated (`verifyDisproven` → veto →
suppressed → dropped) and the polarity `LiftedCounterSignal` documents for the lifted side.
Corpus totals are unchanged at 139 rows; `Verified` 34 → 33.

### Two honest bounds

**Suppression here is score arithmetic, not a guarantee.** `booleanStem` lands at 10 because
its base is 35. A contradicted law with a stronger base — say 70 — would land at 45 and still
surface at `Likely`, carrying the counter-signal caveat. What is closed unconditionally is the
**`Verified` label**, since the evidence is filtered rather than merely outweighed. That is the
right split: the false confident claim is gone in every case, and a lower-tier row that names
its own contradiction is information rather than a wrong answer.

**A crash found the real edge, and it is recorded because reading would not have found it.**
The first implementation substituted every binding, including a member's NAME — a member
access holds its callee in a `DeclReferenceExprSyntax` too. The rewritten tree violated the
grammar and the first consumer to read `.declName` force-cast and TRAPPED: `swift-infer
discover` died with `Unexpectedly found nil while unwrapping an Optional value` inside
`roundTripNegativePair`, a detector the change was not aiming at. Then the **control arm**
caught a second over-reach: substituting INPUT bindings (`let name = "isShowing"`) rewrote the
identifier the matchers quantify over into a string literal, so the nested form that had always
worked stopped matching. Substitution is now restricted to bindings whose initializer is a
CALL — computed intermediates — and inputs stay symbolic. **Both bugs were in the widening, not
the feature, and both were found by arms written to fail rather than by reading.**

---

## §11 Fourth pass at `fdae49f` (2026-08-14) — issue #256's re-measurement

Issue #256 closed the message half of its own defect at `3c62596` (a refusal named
`--extra-import`, a flag the CLI does not declare, for an import the tool already performs).
Its remaining ask was a measurement, not a fix: **do the syntax-node picks actually reach
execution now that the kit's generators are wired?** This runs it.

`prove-then-show --target SwiftInferCore --budget small --max-parallel 4`, fresh detached
`git worktree` at `fdae49f`, release binary built from that commit. §8's method note: the
worktree makes the index clean by construction, since `.swiftinfer/` is gitignored. Exit 0,
~10 GB of workdirs.

### §11.1 Buckets

| | §10.10 (`d1eaa1f`, 2026-08-10) | §11 |
|---|---|---|
| picks tested | 156 | **159** |
| Proven | 85 | **87** |
| Expected-to-hold | 0 | **0** |
| Disproven | 2 | **2** |
| Unverifiable | 62 | **61** |
| Inconclusive | 7 | **9** |
| `unsupported-carrier` | 5 | **5** |
| `build-failed` | 0 | **0** |

**Compare against §10.10, not §10.1** — §10.10 is the most recent run and already holds the
`SubjectFingerprint.of(bodyText:)` refutation, so reading this against §10.1 would report a
month-old finding as new. Both Disproven rows here are the pair §10.10.2 records
(`BuildIdentity.versionString`, `SubjectFingerprint.of(bodyText:)`), both `Possible`, both
false laws about correct code. **No new refutation, and zero defects.**

**Movement is corpus growth, and it is only partly attributable.** Four subjects landed since
`d1eaa1f`: `CollisionBias.isPathShaped`, `HostileInputEntryPoints.hasResultNoun` and
`.normalizedLabel` (all Proven here) and `VerifyEvidenceScoring.isContradictedByAuthor`
(Inconclusive — §10.11's own code, a trap in the generator's domain). That is four new picks
against a net **+3**, so at least one earlier pick left the corpus or changed bucket, and
saying which would need the previous run's row list — **which this document does not record**.
The bucket tables here have always been counts; per-row diffs have only ever been possible for
populations someone opened by hand. Recorded as a limitation of the method, not smoothed over.

### §11.2 The answer: zero `unsupported-carrier` rows name a syntax node

```
? EffectResolver           predicate  carriesInformationUpward(_:)   (unsupported-carrier: Effect)
? FunctionScannerVisitor   predicate  hasSPIAttribute(_:)            (unsupported-carrier: FunctionScannerVisitor)
? FunctionScannerVisitor   predicate  isNestedLocalFunction(_:)      (unsupported-carrier: FunctionScannerVisitor)
? ProtocolCoverageMap      predicate  anyCovers(_:_:)                (unsupported-carrier: S)
? SetAlgebraShape          predicate  isSelfTypedBinaryOp(_:)        (unsupported-carrier: FunctionSummary)
```

All five are §9.9's residual categories and none is a syntax node: `Effect` cross-module,
`FunctionScannerVisitor` ×2 our own visitor (a traversal is not a value — correct silence),
`S` a generic parameter (unsupportable by construction), `FunctionSummary` the one real local
gap. **The population #256 asked about is gone from this bucket.**

**#256's own baseline was stale when it was filed.** It quotes *"9 of 20 `unsupported-carrier`
rows ... declined for want of an import, not for want of a generator"* from 2026-08-09 — which
is §9.3's finding, and §9.3 *measured the answer the same afternoon* in an A/B before the
wiring shipped as `3c5ebd4`. So this pass is a production **re-test of a branch-arm result**,
not a first measurement, and the question it settles is narrower than the issue frames it.

### §11.3 It reproduces §9.3 arm B exactly — 1 of 9 reached execution

| arm A row (2026-08-09) | §9.3 arm B | §11 (production) |
|---|---|---|
| `ReducerDiscoveryVisitor  declaresReducerConformance` (`InheritanceClauseSyntax?`) | ✓ Proven | **✓ Proven** |
| `Visitor  isStatic` (`DeclModifierListSyntax`) | `internal-api-not-accessible` | subject not visible to tests |
| `MemberBlockInspector  isStaticOrClass` (`DeclModifierListSyntax`) | `internal-api-not-accessible` | subject not visible to tests |
| `EqualityBodyClassifier  iteratesAZipOfBoth` (`StringLiteralExprSyntax`) | `internal-api-not-accessible` | subject not visible to tests |
| 2 rows (`CodeBlockItemSyntax`, `DictionaryExprSyntax`) | `unsupported-carrier: BodySignalVisitor` | **subject not visible to tests** |

**The honest headline is 1 of 9, not 9 of 9.** Eight were blocked by a second, independent
thing, and the generator gap was merely the one that reported — the standing rule *a refuter
that fires first hides every refuter behind it*, confirmed in production rather than on a
branch. Three have unreachable subjects (§2's case: **lift the law, do not widen access**).

**The two `BodySignalVisitor` rows improved on arm B**, which is the one place production
beats the branch. Arm B left them declining on a *second* unsupported carrier, the enclosing
visitor; §9.7's `subjectNotVisibleToTests` re-attribution now fires ahead of the carrier gate,
so they report the blocker that actually bites first. A reader is no longer sent to write a
`gen()` for a visitor when the subject is `private` anyway.

Two further syntax carriers are Proven that arm B never listed —
`MemberBlockInspector.hasUserGen(in:)` and `.hasUserInit(in:)`, both `MemberBlockSyntax`.

### §11.4 What §11 does not claim

**A Proven syntax law is a weak claim wearing a strong-sounding carrier.** The one law that
executes quantifies over a *randomly drawn* `InheritanceClauseSyntax?`. `measured-bothPass`
means no counterexample in the generated domain, and a generated syntax node is drawn from a
pool rather than derived from the shape the code expects — so the standing caveat applies here
with **more** force than usual, not less. It should not be read as *the law holds*.

**Inconclusive 7 → 9 is not diagnosed.** One is `isContradictedByAuthor`, new code. The other
is unattributed for the reason §11.1 gives. All nine are the generator-trap family already on
record — §8.4's unbounded draw, with `SourceLocation(line: -691367222)` visible in the flush
again, and one `Range requires lowerBound <= upperBound`. **These are evidence about the
generator's domain, not about the laws**, which is what the bucket exists to say.

**Nothing was shipped and nothing was written to the working repo.** The run was read-only in
a throwaway worktree; this repo's own `.swiftinfer/` was never touched, so no evidence store
here was overwritten — the trap `fixtures/whole-corpus-survey/` records.
