# Road test: SwiftInferProperties on itself

**Subject:** this repo, `SwiftInferProperties @ 89d1a21` (473 source files, 653 test files).
**Tools:** `SwiftProjectLint @ 6176101` (seed manifest) → `swift-infer` built from this checkout (discover) → `SwiftPropertyLaws` (run the laws).
**Date opened:** 2026-07-26.

This is the kit dogfooding on itself — Appendix C's "and so do the five tool packages above." It is
scored the same way as `docs/roadtest-swiftprojectlint.md`: **refutability, not suggestion count**
(Appendix C, "Score refutability, not suggestions"). A law counts only if some type-correct, plausible
implementation of the function is *rejected* by it. `f(x) == f(x)` scores zero.

---

## §0 The starting number (measured before any tool ran)

| | |
|---|---|
| `@Test` declarations in `Tests/` | **4,294** |
| Test files | 539 |
| Files importing `PropertyLawCore` / `PropertyLawKit` | 118 |
| **Actual property-law executions in test bodies** | **2** |
| `propertyCheck(` call sites | **0** |

The 118 importing files are a false signal, and the shape of the falsity is worth recording. They import
`PropertyLawCore` for its *domain types* (`GeneratorRecipe`, `Signal`, …), not to run laws. Every one of the
58 `Gen<Int>` occurrences is a **string literal inside an expected-emitted-stub assertion** — the engine
emitting the text `"Gen<Int>.int()"` and a test checking the text came out right. Grepping for `Gen<` reports
a property-testing codebase; reading it finds a string-comparison codebase.

The two genuine law executions are both in `KitV24InteractionInvariantLawsSmokeTests.swift`, and their
docstring says what they are: a compile-check that the kit's v2.4.0 API entry points still exist.

**So the tool that tells other people to write property tests has, by its own accounting, none.**
That asymmetry is the subject of this road test, not an aside in it.

## §1 Prediction, logged before the first `discover` run

Recorded in advance so the result can disagree with it. Written by reading the source tree only —
no tool output consulted.

1. **Reach.** `discover` on this repo's own `Sources/` will surface **fewer than 15** default-tier
   candidates, and most will be on `SwiftInferCore` value types rather than on the analysis engine.
   Reasoning: the engine is the same shape as the SwiftLintRuleStudio subject — SwiftSyntax visitors
   (stateful accumulators, not `(T) -> T`) and scan functions taking syntax nodes. Out-of-catalog by
   construction, and this repo's own dogfood record already says so.
2. **The generator wall.** A majority of whatever *is* surfaced will print `Generator: .todo` /
   `not derived`, for the reason the SwiftProjectLint road test recorded: the kernels take SwiftSyntax
   nodes, and there is no proxy-representation recipe (`String` → `Parser.parse` → `SourceFileSyntax`).
3. **The richest seam is not in `discover` at all.** The highest-value refutable laws in this repo are
   over its own *scoring and tier algebra* — `Signal` combination, `Tier(score:)` monotonicity, the
   `lub`-like fold in `InteractionVerifyEvidenceScoring` — because those are total functions on small
   value types with documented intent. I predict `discover` proposes laws for **at most one** of them,
   and that the rest have to be reached the Chapter 2 §2.4.2 way: by reading the documented intent.
4. **The score.** Of the refutable laws I end up shipping, I predict **under half** originate from a
   tool suggestion; the majority will come from documented intent the catalog has no name for.

Prediction 4 is the one I expect to be least comfortable, and it is logged for that reason.

---

*(Results below this line are appended as measured. Nothing above it is edited in response to them.)*

## §2 What the loop returned

**Step 1 — `SwiftProjectLint @ 6176101 --format pbt-seeds`:** 1,657 seeds (1,457 `pure-function`,
200 `extractable-kernel`), across SwiftInferCLI 715 / Templates 506 / Core 276 / TestLifter 157 /
MacroImpl 3. The linter is emphatically not the weak link — the same reconfirmation the
SwiftProjectLint road test recorded as Finding B.

**Step 2 — `swift-infer discover`, built from this checkout:**

| Target | Default tier (Likely+) | Possible | Total |
|---|---|---|---|
| SwiftInferCore | **16** — assoc 4, commutativity 4, codable-round-trip 7, comparator 1 | 36 | 52 |
| SwiftInferTemplates | **3** — comparator 1, round-trip 2 | 43 | 46 |
| SwiftInferCLI | **2** — assoc 1, commutativity 1 | 13 | 15 |
| SwiftInferTestLifter | 0 | 3 | 3 |
| **Total** | **21** | 95 | 116 |

## §3 Scoring the predictions

| # | Prediction | Outcome |
|---|---|---|
| 1 | Fewer than 15 default-tier candidates | **Wrong.** 21. Under-predicted by 40%. The direction of the error is the interesting part — see below. |
| 2 | A majority of surfaced picks print `not derived` | **Wrong.** 16 of 61 rendered blocks in Core, ~26%. The generator wall is real but far smaller here than on SwiftProjectLint, because Core's value types are plain `Codable` structs, not SwiftSyntax nodes. |
| 3 | `discover` proposes laws for at most one of the scoring/tier seams | **Right, and then some.** Zero. Nothing on `Tier`, `Score`, `Signal`, or `InteractionVerifyEvidenceScoring`. |
| 4 | Under half the shipped refutable laws originate from a tool suggestion | **Right.** 17 of 44 shipped tests trace to a `discover` suggestion (39%); 27 came from documented intent. |

Prediction 1 was wrong in the direction that matters, and the reason is worth more than the number.
The engine is out-of-catalog on its own *analysis* layer — 715 seeds in SwiftInferCLI produced two
default-tier picks — but it is squarely in catalog on its own **persistence** layer, which nobody had
thought of as the interesting part. Four `merge` folds and seven hand-written `Codable` pairs are
exactly the shapes the templates name. The tool found the value types under the compiler-adjacent code.

## §4 Findings

### F1 — `merge` is associative and **not** commutative; `discover` proposed both, at the same tier

The headline. Four structurally identical last-write-wins folds — `Decisions`,
`InteractionDecisions`, `PostAcceptanceOutcomeLog`, `VerifyEvidenceLog` — were surfaced as *both*
associativity and commutativity candidates at `Likely`. Associativity holds. Commutativity does not:
on a `timestamp` tie the fold's `>=` keeps the **receiver's** record, so `a.merge(b) != b.merge(a)`
whenever two records share an identity and an instant but differ elsewhere.

Reading the code cannot tell you which of two equal-confidence proposals is real. That is the
argument for `verify` in one sentence, and it is the first time this repo has made it against itself.

**The tie is reachable, and that is the sharper half.** All four logs persist with
`dateEncodingStrategy = .iso8601` — whole-second resolution — so two records written in the same
second are *exactly* equal after a load. Aggregating decision logs across corpora (`swift-infer
metrics`) can therefore report different numbers depending on file order.

**Doc-vs-code drift, from the same fact.** Two of the four docstrings claim the aggregate is
"order-deterministic regardless of input ordering." The *sort* is. Which record survives to be sorted
is not. This is Chapter 2 §2.4.2's technique catching a real drift: the sentence is in the source, and
it is false.

Pinned by `MergeAlgebraPropertyTests` (10 tests). Not fixed: a deterministic receiver-wins tie-break
is a defensible policy; the docstrings are what is wrong, and rewording them is the owner's call.

### F2 — the naive idempotence law is false: `merge` normalizes, `upserting` appends

`a.merge(a) == a` fails, because `merge` returns records sorted by `(timestamp, identityHash)` while
`upserting(_:)` — the canonical mutator that actually builds these logs — appends. So a log assembled
the ordinary way is not in merge's canonical order. The true law is that `merge` is idempotent **on
its own image**: it is a normalizer, and the first merge is a normalization step rather than a no-op.

Found only by executing it. Every prior reading of that function in this repo, including mine an hour
earlier, took "fold another log into this one" at face value.

### F3 — two unenforced invariants, both the shape this tool flags in other people's code

- **`Decisions` / `VerifyEvidenceLog` uniqueness.** `upserting` keeps one record per identity; the
  public memberwise `init(records:)` accepts any array, and the loaders will decode a duplicate from
  a hand-edited JSON file. The first version of `MergeAlgebraPropertyTests` failed all eight of its
  tests on exactly this, and the shrinker named the cause in one line.
- **`SeedKind.unrecognised(raw)`.** The payload is constrained by convention only, so
  `.unrecognised("pure-function")` is constructible and does not round-trip — it normalizes to
  `.pureFunction`, flipping `isAnalysable` from `false` to `true` on the way. Harmless today (the
  decoder never produces such a value) and pinned so it stays that way.

Both are *representable illegal states* — precisely what `InteractionInvariantFamily`'s cardinality
and biconditional families exist to flag in subject code. The tool does not point them at itself.

### F4 — `Score(advisorySignals:)` has an unenforced precondition with a trap behind it

Unlike `init(signals:)`, the advisory initializer does not filter vetoes; it sums every weight it is
handed, and `Signal.vetoWeight` is `Int.min`. One veto signal yields an incoherent `Score`
(`.advisory` tier, `isVetoed == false`, `total == Int.min`); **two** overflow `reduce(0, +)` and trap.
Both live call sites pass a single hand-built non-veto signal, so nothing is broken — this is a guard
for the third call site. Same family as the appendix's `ChunkPlan.progress` `Int.max` overflow.

### F5 — the Finding-G gate and its one carve-out had no test

`CLAUDE.md` lists the gate under "follow rather than re-litigate," and the source calls
`tier(forScore:)` the "single source of truth … so the gate can't be bypassed on one path and not the
other." Neither sentence had a test. `FindingGGatePropertyTests` states the gate over the full
family × score cross product and the fold over family × outcome × coverage — including the arm a
reader gets wrong, which is that **legacy `nil` coverage must count as partial, not as full**.

### F6 — the fold is not idempotent, and nothing guards against a second application

`InteractionVerifyEvidenceScoring.applied` adds +50 on every pass. Correct today (the docstring is
explicit that the render path runs it once), but it is a pure function on values with no marker saying
it has already run, and the obvious next change — folding evidence into the SemanticIndex as well as
the render path — would double-count silently and promote picks the gate is holding down. Pinned as a
characterization rather than fixed; making it idempotent means a persistence change.

### F7 — `make test-fast` is already red, at its lint gate

`swiftlint lint --quiet --strict` reports **52 errors on a clean `89d1a21`** — `type_body_length`,
`file_length`, `unneeded_throws_rethrows`, `sorted_imports` in older test files. The pre-2026-07-26
CLAUDE.md asserted lint was "silent project-wide." Not a road-test finding about the tools, but it is
a confident claim in the project's own instructions that the project does not meet, and it was
believed until something ran it. Corrected in the rewritten CLAUDE.md.

## §5 Unscored finds

Per the rule that **a tool may not grade its own homework**, nothing above was folded into §1's
prediction. Recorded here for completeness: F5 and F6 were reached because prediction 3 sent me to
read `InteractionVerifyEvidenceScoring`, not because any tool proposed them.

## §6 What shipped

Four suites, 44 tests, in `Tests/SwiftInferCoreTests/`:

| Suite | Tests | Origin |
|---|---|---|
| `MergeAlgebraPropertyTests` | 10 | `discover` (assoc + commutativity ×4) |
| `PersistenceRoundTripPropertyTests` | 7 | `discover` (codable-round-trip ×7) |
| `TierScoreAlgebraPropertyTests` | 16 | documented intent |
| `FindingGGatePropertyTests` | 11 | documented intent |

Repo `propertyCheck` call sites: **0 → 22**. Genuine property-law executions: **2 → 44 tests**, of
which 22 are randomized `propertyCheck` runs and the rest are exhaustive sweeps over finite domains
(see §7).

## §7 Two method notes, both earned by being wrong

**Sampling a finite domain is worse than walking it.** The threshold laws were first written as
`propertyCheck` over `Gen<Int>.int(in: -200...200)`. A mutation — `case 40..<75` → `case 41..<75`, a
one-character boundary slip — was caught by **one** of the three tests that should have caught it,
because a uniform draw from 401 integers hits the value 40 about 22% of the time in 100 trials. The
suite would have reported that mutant as survived four runs in five. Rewritten to sweep `-10...130`
exhaustively, all three catch it every time. The §4.2 thresholds live in a 141-value domain; there
was never a reason to sample it.

**A green property test is a claim until something breaks it.** Every suite here was mutation-tested
before being called done — 16 hand-authored mutants, all killed:

| | Mutant | Result |
|---|---|---|
| T1 | `Tier(score:)` `40..<75` → `41..<75` | killed (3 tests) |
| T2 | `severityRank` advisory 5 → 4 (rank collision) | killed |
| T3 | `Score` veto never fires | killed |
| T4 | `promoted()` also promotes `.likely` | killed |
| M1 | `merge` tie-break `>=` → `>` | killed |
| M2 | `merge` drops the sort | killed |
| G1 | gate clamp removed | killed (248 expectations) |
| G2 | partial coverage also overrules the pin | killed |
| G3 | legacy `nil` coverage treated as full | killed |
| G4 | `defaultFails` no longer suppresses | killed |
| G5 | overrule disclosure dropped | killed |
| C1–C3 | `SemanticIndexEntry` drops a field from `encode` | killed |
| C4 | `Vocabulary` drops `monotonicityVerbs` from `encode` | killed |
| C5 | unknown `SeedKind` narrowed to `.pureFunction` | killed |

G3 and G5 are the two worth naming. G3 is the subtle arm of the cycle-135 decision, and G5 is the
*disclosure* guardrail CLAUDE.md calls binding — a mutant that keeps the promotion correct and only
drops the explanation. Both were caught, which is the evidence that the gate suite tests the decision
and not merely its arithmetic.

## §8 Still open

1. **The 95 `Possible`-tier picks are unexamined** — 78 of them `predicate`, a role the catalog
   explicitly attaches no law to. Not obviously worth a pass.
2. **`SwiftInferTemplates` and `SwiftInferCLI` are untouched by this round** — 5 default-tier picks
   between them, including two `round-trip` pairs and a `comparator` that is worth checking, since a
   comparator that is not a strict weak ordering can crash `sorted(by:)`.
3. **The `comparator` pick on `isCanonicalInversePair(_:_:)` looks like a template misfire** — that
   function is a *symmetric* relation, not an ordering, so the strict-weak-ordering law is the wrong
   one. The right law (symmetry) is the `equivalenceRelationSignature` family, which did not fire.
   Worth a look as a precision question in its own right.
4. ~~`swift-infer verify` was never run~~ — **closed, see §9.**
5. **The 52 pre-existing lint errors** (F7) block `make test-fast` and want a sweep.

---

# §9 Closing the loop — `swift-infer verify` on the same laws

The point of running the tool's own verify path over laws already settled by hand is that the answers
are known in advance. Anywhere the two disagree, one of them is wrong and it is cheap to find out
which. They disagreed twice, and both disagreements were the tool's.

`swift-infer index --target SwiftInferCore` → 85 entries, including exactly the 16 default-tier
candidates from §2. Then `verify --all-from-index --corpus-module SwiftInferCore`, per template.

## §9.1 The headline: a confident **green** on a law that is false

`Decisions.merge` commutativity — the law §F1 disproves — is reported by the tool as
**`measured-bothPass`, 100 trials**.

The stub is not wrong. It is, line for line, the property in
`MergeAlgebraPropertyTests.mergeIsNotCommutativeOnTies`:

```swift
let lhsResult = { $0.merge($1) }(lhs, rhs)
let rhsResult = { $0.merge($1) }(rhs, lhs)
if lhsResult != rhsResult { … FAIL … }
```

What is wrong is the **generator**. The strategist derives `identityHash` as
`Gen<Character>.letterOrNumber.string(of: 0...8)` and `timestamp` as `Gen<Date>.date` — a ~62⁸ key
space against a ~2⁶⁴ instant space. Two records essentially never share an identity, and if they did
they would never share a timestamp, so the tie branch that carries the whole failure is unreachable.
The property is refutable in principle and unrefutable in practice.

Confirmed by experiment rather than argument. The generated stub was run twice, changing **only** the
two alphabets and nothing about the property:

| Generator | Outcome |
|---|---|
| Strategist-derived, as emitted | **PASS**, 100 trials → recorded `measured-bothPass` |
| Identical stub, `identityHash` drawn from 2 values and `timestamp` from 2 | **FAIL at trial 5** |

The counterexample the narrowed run printed is precisely §F1's: `identityHash "c"` present in both
logs at the same instant, forward keeping `.accepted` and inverse keeping `.skipped`.

**This is the mirror image of the confident zero.** Appendix C's road test is organised around a tool
saying "there is nothing here" when there was; this is a tool saying "verified, 100 trials" about a
law that is false, on a corpus it was pointed at deliberately. A `measured-bothPass` promotes a pick
to `Verified` in `discover` and would have published it through `docc`, whose entire premise is that
documented properties are *provable*. Nothing in the pipeline is positioned to notice, because every
stage downstream of the generator is working correctly.

**The generalisation, which is the part worth keeping.** A derived generator is tuned for *coverage of
the type* and is silently mistuned for *coverage of the law*. Any property whose failure needs two
generated values to **collide** — merge tie-breaks, cache-key collisions, dictionary-key injectivity,
dedup, anything keyed by identity — is invisible to a generator that draws keys from a realistic
domain. It is not a niche shape; it is most of what a persistence layer does.

That the same trap caught the *hand-written* suite first is the strongest evidence it is systemic
rather than an oversight: the first draft of `MergeAlgebraPropertyTests` drew identity hashes freely
and had to be narrowed to a three-value alphabet before the tie appeared. The tool made the same
mistake the human did, for the same reason, and only the human got a second try.

No fix attempted. Collision-biasing a derived generator is a `DerivationStrategist` design question
(kit-side, PRD §11), and it trades against every other property that wants a realistic domain. It is
recorded here, and `MergeAlgebraPropertyTests` carries the narrow alphabet with a comment saying why.

## §9.2 Three emitter defects, all of which made verify report a non-verdict

Before any verdict could be reached at all, three separate bugs had to be cleared. Every one produced
`measured-error: build-failed: exit=1` — a verdict-shaped non-verdict that reads as "this property
could not be checked" and files under *architectural limitation*, when the property was never involved.

**(a) The kit pin had drifted a major version — FIXED.** Every synthesized verifier declared
`SwiftPropertyLaws` `from: "2.1.0"` (algebraic) or `"2.2.0"` (the three interaction modes) while this
package requires `from: "3.17.0"`. A `--corpus-module` survey adds a `.package(path:)` on the
working-dir package, so SwiftPM has to reconcile the two — disjoint major ranges, resolve fails,
**every entry in the survey reports `measured-error`**. Invisible until now because no prior survey
pointed the verifier at a corpus that was itself a SwiftPropertyLaws consumer: the frozen
cycle27-surface corpus is a library-carrier survey with no path dependency, so its resolve never had
to reconcile anything.

Fixed by replacing the four literals with `VerifierWorkdir.swiftPropertyLawsRequirement`, guarded by
`VerifierWorkdirKitPinTests`, which reads `Package.swift` and fails the build on drift. Two existing
tests asserted the stale literals verbatim — the same drift one layer out, a guard that confirmed the
bug rather than catching it — and now assert against the constant.

**(b) Multi-line generator expressions were not fully commented — FIXED.** The stub header
interpolates the recipe after a single `//`. A derived-composite recipe for a multi-property struct
spans several lines, so line 1 was a comment and lines 2+ were bare top-level code. The stub failed to
*parse*, reporting `consecutive statements on a line must be separated by ';'` at a line that is
supposed to be a comment. Hidden because every carrier in the frozen corpus derives a single-line
recipe; the first multi-property struct to reach this path is the first one that breaks it. Fixed in
`StrategistDispatchEmitter+Header.commented(_:label:)`.

**(c) Two codegen defects in the kit's `GeneratorExpressionEmitter` — NOT fixed, kit-side.**
`SwiftPropertyLaws/Sources/PropertyLawCore/GeneratorExpressionEmitter.swift` emits expressions that
cannot compile:

- **Line 43** — `.caseIterable` → `"Gen<\(typeName)>.element(of: \(typeName).allCases)"`. But
  `Gen.element(of:)` is `Generator<Element?, _>`, so this is a `Generator<T?, _>` where a
  `Generator<T, _>` is required: *"static method 'element(of:)' requires the types 'Tier' and 'Tier?'
  be equivalent."* The one-line fix is the one this repo already applied to its own carrier-level
  recipe at `StrategistDispatchEmitter.swift:286` — `Gen.element(of: T.allCases).map { $0! }` — but
  the composite-member path routes through the kit's emitter and never got it. So a struct with a
  `CaseIterable` enum *member* is unverifiable, which is all four merge carriers.
- **Nested types are emitted unqualified.** `SemanticIndexEntry` derives a recipe naming `Kind`,
  `StoredMember`, and `InitializerParameter`, which are nested inside `IndexedTypeShape` — *"cannot
  find 'Kind' in scope."* The emitter has no notion of an enclosing type.

Both are cross-repo; this package pins the kit by version, so neither can be fixed from here. Defect
(c)-1 was confirmed rather than assumed: hand-applying the one-line fix to a generated stub made it
compile and run, which is how §9.1's measurement became possible at all.

## §9.3 What the tool actually verified

After (a) and (b), the codable-round-trip family — §F's largest group — produces real verdicts:

| Carrier | Outcome | Agrees with the hand-written suite? |
|---|---|---|
| `Vocabulary` | `measured-bothPass` (100 trials) | yes |
| `SemanticIndexEntry` | `architectural-coverage-pending` | blocked by (c)-2 |
| `MarkerPair` | `measured-bothPass` | yes |
| `DualStyleNamePair` | `measured-bothPass` | yes |
| `RegisteredGenerator` | `measured-bothPass` | yes |
| `InversePair` | `measured-bothPass` | yes |
| `SeedKind` | `architectural-coverage-pending` (`unsupported-carrier`) | honest skip — enum with an associated value |

**5 of 7 verified by the tool, and all 5 agree with the hand-written results.** The two that did not
are honest non-verdicts rather than wrong ones. `associativity` (×4) and `commutativity` (×4) remain
blocked by (c)-1; `comparator` on `isCanonicalInversePair` reports `unsupported-carrier`, which is
the right answer for the wrong reason — see §8 item 3, where that pick is argued to be a template
misfire regardless.

## §9.3a The loop actually closes

Re-running `discover` after the survey folds the evidence back in, and the five verified picks are
promoted through the full chain:

```
discover (Likely, 50)  →  verify (measured-bothPass, 100 trials)
                       →  .swiftinfer/verify-evidence.json
                       →  discover fold (+50 → 100)
                       →  Score: 100 (Verified)
```

Worth noting what the explainability block says about the verified picks, unprompted:

> ⚠ The round-trip is COORDINATE-relative: it holds under the CONCRETE coder the verifier uses
> (`JSONEncoder` / `JSONDecoder`) … `Date` / `Data` fields depend on the coder's encoding strategy.

That is §F1's ISO8601 truncation, anticipated by the tool's own caveat before anyone measured it.
The "why this might be wrong" block is doing exactly the job PRD §4.5 claims for it — which makes the
§9.1 silence more pointed, not less: the caveats warn about the coder, and nothing warns about the
generator.

### F8 — `--stats-only` and full output disagree about the same pick's tier

The five picks above render as `Score: 100 (Verified)` in full output and as `Strong` under
`--stats-only`. `Tier.promoted(byVerifyOutcome:)` is applied at `SuggestionRenderer.swift:30`, inside
`render(_:verifyEvidenceByIdentity:)`; `renderStats` is called without the evidence map and cannot
reach it. The `+50` *score* fold happens upstream and reaches both, so stats sees the score move
Likely → Strong but never the final promotion.

`--stats-only` is documented as "useful for CI dashboards tracking suggestion-count regressions over
time" — so the surface built for automation is the one that cannot report a verified pick. Not fixed:
the render path deliberately keeps stats output byte-identical across the advisory channels, and
changing what a CI dashboard emits is the owner's call.

## §9.4 The ledger

| | Count |
|---|---|
| Default-tier candidates surveyed | 16 |
| Real verdicts obtained | 5 (all `measured-bothPass`, all agreeing with hand-written laws) |
| Honest non-verdicts (`unsupported-carrier`) | 2 |
| Blocked by kit-side codegen defects (c) | 9 |
| Verdicts that were **wrong** | 1 — commutativity `bothPass`, §9.1 |

The one wrong verdict is worth more than the five right ones. Five agreements confirm that the verify
path works when it works; the disagreement is the only thing here that could not have been learned any
other way, and it says that `measured-bothPass` means "no counterexample **in the generated domain**"
rather than "the property holds." That distinction has no representation anywhere in the pipeline —
not in `VerifyEvidenceOutcome`, not in the `+50` weight, not in the `Verified` tier, and not in
`docc`, which publishes exactly these as facts.

## §9.5 Changes shipped in §9

| File | Change |
|---|---|
| `VerifierWorkdir+KitPin.swift` (new) | `swiftPropertyLawsRequirement` — one constant replacing four drifted literals |
| `StrategistDispatchEmitter+Header.swift` (new) | `commented(_:label:)` — comment every line of a multi-line recipe |
| `VerifierWorkdirKitPinTests.swift` (new) | 3 tests; the pin must equal `Package.swift`'s, in every workdir mode |
| `VerifierWorkdirTests.swift` | two guards moved off the stale literals onto the constant |

`swift test --skip 'MeasuredTests|MeasuredExecutionTests|VerifyPipeline'` green at 4,188; `make batch3`
(the `VerifyPipeline` measured suites, which exercise the changed emitter) green at 31; lint error
count unchanged at the pre-existing 52.

## §9.6 Still open after §9

1. **The confident green (§9.1) has no mitigation.** Options, none cheap: collision-biasing in
   `DerivationStrategist`; a per-template hint that a law needs colliding inputs; or a caveat in the
   explainability block saying `bothPass` is domain-relative. The third is the only one that is
   honest without being a research project.
2. **Kit defects (c)-1 and (c)-2** — both one-file fixes in `GeneratorExpressionEmitter`, both
   blocking 9 of the 16 candidates here, and (c)-1 blocks *any* struct with an enum member.
3. **`architectural-coverage-pending` conflates two very different things** — "this carrier is out of
   scope" (`SeedKind`) and "our codegen emitted something that does not compile"
   (`SemanticIndexEntry`). The first is a boundary; the second is a bug. Reporting them identically is
   how (b) and (c) stayed invisible.
4. **F8** — `--stats-only` cannot report `Verified`.

---

---

# §11 Re-running the survey against the fixed kit

Both kit defects from §9.2(c) are now fixed in SwiftPropertyLaws. Predictions logged **before** the
re-run, so the result can disagree.

1. **The four `commutativity` picks will now build — and will report `measured-bothPass` anyway.**
   The codegen fixes remove the build failure; they do nothing about §9.1. The confident green is a
   *generator* problem, and neither fix touches the generator. If this prediction holds, it is the
   more useful outcome: it separates "the pipeline could not run" from "the pipeline ran and was
   wrong," and only the second is the finding.
2. **The four `associativity` picks will build and `bothPass`** — that law is genuinely true (F1), so
   this is the control.
3. **`SemanticIndexEntry` will still not verify, and that is now the correct answer.** Bug 2's fix
   makes the resolver *refuse* the ambiguous `Kind` rather than resolve it to an unrelated type, so
   the strategy drops to `.todo`. The pick should move from `build-failed` (a defect) to a clean
   non-verdict (a boundary). Same outcome column, entirely different meaning.
4. **The five already-verified `codable-round-trip` picks stay `bothPass`** — no regression.

## §11.1 Result

Kit v3.18.0 resolved through the real dependency graph (`swift package update` → 3.18.0; the
generated verifier's own manifest declares `from: "3.17.0"`, which resolves it too — no local
override anywhere). `make batch4` green first, 7/7 suites in 415s, including
`AlgebraicSurveyCorpusMeasuredTests` — so the kit bump and the SwiftInferProperties pin change are
both regression-clear.

| Template | Before §9.2 fixes | After |
|---|---|---|
| `commutativity` ×4 | 4 × `build-failed` | **4 × `measured-bothPass`** |
| `associativity` ×4 | 4 × `build-failed` | **4 × `measured-bothPass`** |
| `codable-round-trip` ×7 | 5 pass, 1 pending, 1 `build-failed` | 5 pass, 1 pending, 1 `build-failed` |
| `comparator` ×1 | `unsupported-template` | `unsupported-template` |

**Real verdicts: 5 → 13 of 16.** The two kit codegen fixes unblocked 8 of the 9 blocked candidates.

| Prediction | Outcome |
|---|---|
| 1. commutativity builds and still returns `bothPass` | **Right.** |
| 2. associativity builds and passes (control) | **Right.** |
| 3. `SemanticIndexEntry` moves from `build-failed` to a clean non-verdict | **Wrong** — still `build-failed`. |
| 4. the five verified codable picks stay verified | **Right.** |

### Prediction 1 held, and that is the point

The four commutativity picks now build and report `measured-bothPass` at 100 trials — on a law
`MergeAlgebraPropertyTests` disproves. Fixing the codegen changed the failure from *"the pipeline
could not run"* to *"the pipeline ran and was wrong."* Only the second is the finding, and it is
untouched by anything shipped in §9.2 or §12, because it is a generator problem: the derived
generator draws `identityHash` from an 8-char alphanumeric space and `capturedAt` from `Gen<Date>.date`,
so the tie the law dies on is unreachable. §9.1 measured that directly; this run confirms it survives
the repair.

### Prediction 3 was wrong, for a reason worth more than the prediction

I expected the kit's new ambiguity refusal to move `SemanticIndexEntry` to a clean `.todo`. It did
not — the stub still emits a bare, unqualified `Kind`, and still fails to compile.

**The ambiguity is destroyed before the kit ever sees it.** `IndexStore.Index.typeShapes` is a
`[String: IndexedTypeShape]` keyed on the *bare* type name, and `GeneratorResolver` is constructed
from `allShapes.values` — so by the time the kit's guard runs, the eight distinct `Kind`s have already
been collapsed to one by the consumer's own dictionary. The kit refuses ambiguity it is never shown.

Measured on this repo's index: **218 `typeShapes` entries, 13 of which carry more than one source
declaration** — `Kind` ×8, `Visitor` ×7, `CodingKeys` ×6, `Argument` ×3, `Parameter` ×2, `Score` ×2.

Two dictionaries keyed on the same lossy key, in series. Deduplicating at the first makes the second's
guard dead code for this path — the fix is real and correct and reachable only by a caller that hands
the resolver an un-collapsed array. That is a *fix in the wrong repo*, and nothing about reading
either side would have shown it: the kit's guard has tests that pass, the consumer has an index that
looks complete, and only running the pipeline end to end exposes that they never meet.

**The consumer-side fix is unmade and now precisely specified:** key `typeShapes` by qualified name
(`IndexedTypeShape.Kind`), which needs no emitter change on either side — every emitter interpolates
the name verbatim, so `Foo.Kind(…)` already comes out right (`qualifiedNamesDisambiguateAndEmitCorrectly`
in the kit pins this). It would make `SemanticIndexEntry` derivable and stop 12 other names from
silently shadowing each other.

### The ledger, restated

| | Count |
|---|---|
| Default-tier candidates surveyed | 16 |
| Real verdicts | **13** (was 5) |
| Honest non-verdicts (`unsupported-*`) | 2 |
| Blocked by the upstream bare-name collapse | 1 |
| Verdicts that are **wrong** | **4** — the commutativity `bothPass`es, §9.1 |

Four wrong verdicts out of thirteen. Before the kit fixes there was one wrong verdict out of five,
and eight candidates that never ran at all. Repairing the codegen did not make the tool more correct;
it made it *more confident*, on the same unchanged generator. That is the honest reading, and it is
why §9.6 item 1 — the confident green — is still the open item that matters.

---

---

# §12 The stage I skipped — and it had already found F1

The loop is *lint → discover → run → harden*. I ran the linter with `--format pbt-seeds`, took the
manifest, and went straight to `discover`. I never read the linter's actual output. That is the first
stage of the adoption loop — **fix the blockers that make properties hard to write** — and I skipped
it wholesale.

What was there, on the run I did not read: 2,313 issues, 1,677 of them `testability`.

| Rule | Count | Kind |
|---|---|---|
| Pure Function Property-Test Candidate | 1,458 | "test this" |
| Pure Closure Property-Test Candidate | 199 | refactor: extract the closure |
| **Non-Injected Nondeterminism** | **18** | **refactor: inject the clock / RNG / UUID** |
| **Global Mutable State** | **1** | **refactor: instance-scope it** |
| **Extractable Pure Kernel** | **1** | **refactor: lift the kernel out** |

**Refactorings proposed: 20 concrete, plus 199 closure extractions. Refactorings made: zero.**

## The part that stings

The 18 `Non-Injected Nondeterminism` findings are not scattered. They land on the evidence-stamping
and decision-recording path:

```
VerifyInteractionPipeline+Evidence.swift:69      Date()   ← stamps VerifyEvidence.capturedAt
VerifyCommand+AllFromIndex+Persist.swift:16      Date()   ← persists verify evidence
ViewModelVerifyEvidence.swift:39                 Date()   ← same, MVVM path
OutputDeterminismVerifyEvidence.swift:36         Date()   ← same, output-determinism path
InteractiveTriage.swift:132                      Date()   ← stamps DecisionRecord.timestamp
MetricsCommand.swift:229                         Date()   ← the aggregation that CALLS merge
```

Those are **exactly** the fields whose ties make `merge` non-commutative — F1, the finding this whole
road test is built around. The linter's message says it outright:

> Non-injected nondeterminism: `Date()` makes this code unpredictable, so a property-based test can't
> pin the value or reproduce a failure.
> **Inject the source (a clock `() -> Date`, a `RandomNumberGenerator`, a UUID provider) so tests can
> control it.**

It said that eighteen times, in stage one, about the exact code. I skipped the stage, then spent the
session rediscovering the consequence by hand — and had to hand-build a two-value instant alphabet in
`MergeAlgebraPropertyTests` to reach the tie, which is the *test-side* workaround for precisely the
*source-side* fix the linter was asking for.

## Why this is a finding about the method, not the tool

Every other section here scores the tools. This one scores the operator, and it is the more
transferable result. The loop's stages are ordered for a reason: stage one removes the reasons a
property is hard to write, so stage two's properties are easy and stage three's runs are
reproducible. Skipping to `discover` is tempting because `discover` is the stage that produces
something that looks like output — a list of candidate laws — while the linter produces a list of
chores.

The §1 predictions have a matching blind spot, which is how I know this was not a one-off lapse: all
four are about *what `discover` would surface*. Not one of them is about what the linter would ask me
to change first. I framed the exercise as "point the discovery tool at the repo" rather than "run the
loop," and got the corresponding result.

**Still open.** The 20 refactorings are unmade. The 18 `Date()` injections are the ones that matter —
they would let the merge laws be stated over a controlled clock instead of a hand-narrowed generator,
and they are the source-side fix for F1's mechanism. The `Global Mutable State` finding
(`VerifyInteractionPipeline+Workdir.swift:18`) is the per-workdir build lock from cycle 129, which is
deliberate and probably a justified suppression rather than a fix.

## Correction

An earlier pass of this section reported the linter's JSON `locations` array as empty. That was my
parsing — the keys are `filePath` / `lineNumber`, not `file` / `line`. The JSON output is correct; no
linter defect there.

---

## §10 The one-sentence version

The tool found a real law and a real non-law on its own persistence layer and proposed both with equal
confidence, which is the case for having a verify path at all; and then its verify path, pointed at
the non-law, returned a confident green — because the generator it derives is built to cover the type
and nothing checks that it covers the *law*. Both halves of that sentence are the finding. Neither
was reachable by reading.

