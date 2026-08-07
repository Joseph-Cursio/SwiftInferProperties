# Road test: SwiftInferProperties on itself

> **Status:** `withdrawn` · **As of:** 2026-08-01


**Subject:** this repo, `SwiftInferProperties @ 89d1a21` (473 source files, 653 test files).
**Tools:** `SwiftProjectLint @ 6176101` (seed manifest) → `swift-infer` built from this checkout (discover) → `SwiftPropertyLaws` (run the laws).
**Date opened:** 2026-07-26.

This is the kit dogfooding on itself — Appendix C's "and so do the five tool packages above." It is
scored the same way as `docs/measurements/roadtest-swiftprojectlint.md`: **refutability, not suggestion count**
(Appendix C, "Score refutability, not suggestions"). A law counts only if some type-correct, plausible
implementation of the function is *rejected* by it. `f(x) == f(x)` scores zero.

---

> ## ⚠ MEASUREMENTS WITHDRAWN — 2026-08-01
>
> **Do not cite a number from this document.** The diagnoses stand; the measurements do not.
> They fail in two different ways, and the distinction is the point.
>
> **(a) RETRACTED — instrument error.** Every `measured-bothPass` verdict below was produced
> by a verifier whose Pass 2 was a hardcoded `print("VERIFY_EDGE_RESULT: PASS")` with
> `VERIFY_EDGE_TRIALS: 0` — nothing asserted, on every strategist-routed carrier (i.e. everything
> outside `Complex<Double>` / `Double`). See `docs/design/verify-edge-pass.md`, which measured **23 of 23
> `measured-bothPass` verdicts in one full gate run** going through it. `bothPass` in this document
> means *Pass 1 passed and Pass 2 was free*, which is not what the word claims.
> Affected: **§9.1, §9.3, §9.4, §11.1, §11.2.3, §13.1**.
>
> **(b) STALE — superseded by 59 commits.** Hand-counts and `discover` output that were correct
> when taken and no longer describe the repo or the tool. Affected: **§0, §2, §3, §14.2, §14.3**.
>
> **What this costs the headline.** §9.1's diagnosis — the alphabets are too wide, so the tie branch
> carrying the failure is unreachable — was measured directly (narrow only the two alphabets, the
> same stub fails at trial 5) and **still holds**. §13's fix for it shipped and is guarded by
> `CollisionPassTests`. What does *not* hold is the `bothPass` label the finding was built on: it was
> over-claiming for a **second, independent** reason this document never knew about. The finding's
> *lesson* is therefore under-determined between two causes, and CLAUDE.md's standing
> `measured-bothPass` design rule has been amended to say so.
>
> **What survives unaffected.** The diagnosis sections, which is why this file was not deleted —
> 19 live source and test sites cite them as their only recorded rationale:
> **§9.2** (three emitter defects → `StrategistDispatchEmitter+Header`, `VerifierWorkdir+KitPin`) ·
> **§11.1/§11.3/§11.3.2/§11.3.4** (type-shape reflection → `TypeDecl`, `IndexedTypeShape`,
> `EveryColumn`) · **§11.2/§11.2.1** (the hang and its bound → `VerifierTimeoutTests`) ·
> **§12** (the collision sweep → `CollisionPassTests`) · **§13.4** (`swift build` writes errors to
> stdout → `BuildDiagnostics`) · **§14.4** (`Process.terminationHandler` → `VerifierSubprocess`) ·
> **§15** (the metamorphic cost estimate — a design verdict, never a measurement) ·
> **§16** (the SeedFocus trap). A defect is fixed or it is not; that is checkable, not perishable.

---

## §0 The starting number (measured before any tool ran)

> **STALE (b).** Hand-counts via grep against `89d1a21`. Correct when taken; the repo has moved
> ~59 commits since. Re-count before citing.

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

> **STALE (b).** Both tables below are `discover` output from `89d1a21` against
> `SwiftProjectLint @ 6176101`. The catalog has since gained the two model-law families,
> `EqualityBodyShape`, `OrderedCarrierDiscriminator`, and the `Discover.strongestFirst` ordering,
> and the linter has re-sorted its seed kinds (§14.2 already caught the first of these). The counts
> are not wrong — they are no longer about this tool. **The §3 scoring below inherits this**, so
> "Prediction 1 was wrong, 21 not 15" is a claim about a tool that no longer exists.

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

> **RETRACTED (a) — the verdict, not the diagnosis.** `Decisions` is a strategist-routed carrier, so
> the `bothPass` reported here is `Pass 1 (100 real trials, missed the collision)` **+**
> `Pass 2 (hardcoded PASS, zero trials)`. This document attributed the whole miss to generator
> alphabet width. That cause is real and was confirmed by direct experiment below — but it was never
> the only one, and this section could not have known that. Read the alphabet analysis; do not read
> "`measured-bothPass`, 100 trials" as a characterisation of what the verifier did.
> See `docs/design/verify-edge-pass.md`.

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

> **RETRACTED (a) — the verdict table; the kit-resolution and type-shape findings stand.**
> Every `measured-bothPass` in the table below carries a free Pass 2. Note what that does to
> **prediction 2**, the *control*: "associativity builds and passes" was the row proving the §9.2
> fixes had not traded a false green for a false red, and a control whose second pass asserts
> nothing cannot carry that weight. The `build-failed` → *builds at all* transition is unaffected —
> a build either succeeded or it did not. `TypeDecl` cites this section for the type-shape
> reflection finding, which is orthogonal to the verdicts.

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

**The consumer-side fix is now made — see §11.2.** Key `typeShapes` by qualified name
(`IndexedTypeShape.Kind`), which needs no emitter change on either side — every emitter interpolates
the name verbatim, so `Foo.Kind(…)` already comes out right (`qualifiedNamesDisambiguateAndEmitCorrectly`
in the kit pins this).

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

# §11.2 Fixing the collapse, and the hang it uncovered

The consumer-side fix from §11.1 shipped: `TypeDecl.qualifiedName`, `TypeShapeBuilder` grouping by it,
and `resolvedSpelling` resolving member spellings innermost-scope-outward (source writes `kind: Kind`
inside `IndexedTypeShape`, so qualifying the shape *names* without the *references* would have traded
a wrong answer for no answer).

**The collapse was worse than §11.1 reported.** It is not only the `[String: IndexedTypeShape]`
dictionary — `TypeShapeBuilder.shapes` grouped `TypeDecl`s by bare name and took
`group.first(where: { $0.kind != .extension })` as the primary. So the eight `Kind`s were *merged into
one group* whose primary was whichever file was scanned first, and same-file extension merging could
graft one type's conformances onto another's namesake.

Measured effect: **218 → 230 shape entries** (the 12-entry gain is the count of types the collapse was
destroying), 35 of them qualified, bare `Kind` gone, and suggestions 85 → 93 because carriers that used
to dead-end now derive. `make batch4` green 7/7 in 368s — the frozen corpus is undisturbed.

## §11.2.1 The fix worked, and exposed a hang

`SemanticIndexEntry` now compiles and **runs**. It does not terminate.

The strategist picks `.rawRepresentable(.string)` for `IndexedTypeShape.Kind` — a `String`-raw enum
that is *not* `CaseIterable` — and that recipe emits:

```swift
Gen<Character>.letterOrNumber.string(of: 0...8).compactMap { IndexedTypeShape.Kind(rawValue: $0) }
```

Random alphanumeric strings, filtered for ones that happen to spell `struct` / `class` / `enum` /
`actor`. The odds are effectively zero, so `compactMap` retries forever. Two such binaries were found
spinning at 99.9% CPU for 46 and 71 minutes while the survey reported nothing at all.

**This is a nastier class than the two codegen defects of §9.2, and fixing those is what exposed it.**
A stub that fails to build is loud, and lands as `measured-error`. A stub that compiles, runs, and
hangs produces no verdict, no error and no output — the survey simply stops, and the operator
concludes it is slow. It was diagnosed only by noticing that no build process was running while the
wall clock advanced.

## §11.2.2 The bound

`VerifierSubprocess.runVerifierBinary` now takes a 300s ceiling (the slowest legitimate run in this
repo is well under a minute). Three details earn their place:

- **SIGTERM then SIGKILL.** A generator stuck in a tight retry loop ignores SIGTERM; terminate-only
  would leave the process alive and the CPU pegged after the survey moved on, which is how two of them
  accumulated an hour.
- **Pipes drained concurrently.** The previous code read both pipes *after* `waitUntilExit`, which
  deadlocks whenever a child outfills the 64 KB buffer — a hang indistinguishable from the one above,
  and one the timeout would then mis-report as a non-terminating property.
- **Classified as `measured-error`, not `architectural-coverage-pending`.** A timed-out run is a
  defect in what we generated, not a coverage boundary. Filing it under "pending" would read as *out
  of scope, nothing to fix* — which is precisely how the §9.2 codegen bugs stayed invisible.

`VerifierTimeoutTests` (6 tests) pins all three against real subprocesses, because every interesting
part is real-process behaviour. The pipe test's load-bearing assertion is that *partial stdout
survives* — had the reader deadlocked, the diagnostic would be empty.

## §11.2.3 The survey, measured

> **RETRACTED (a) — the `measured-bothPass` rows.** The non-pass outcomes survive and are the
> reason this section is cited: `timed-out` on `SemanticIndexEntry` (the bound working as designed),
> `unsupported-carrier`, `unsupported-template`. Those are verdicts the broken Pass 2 could not
> manufacture — it could only ever add a PASS.

| Template | Outcome |
|---|---|
| `codable-round-trip` ×8 | 5 × `measured-bothPass`, 2 × `unsupported-carrier`, **1 × `timed-out`** |
| `commutativity` ×4 | 4 × `measured-bothPass` |
| `associativity` ×4 | 4 × `measured-bothPass` |
| `comparator` ×1 | `unsupported-template` |

`SemanticIndexEntry` reports `measured-error: timed-out: the verifier ran longer than 300s and was
killed` — a verdict, in bounded time, naming the cause. That is the whole value of the bound: the
answer is still "we could not check this," but it arrives in five minutes with a diagnosis instead of
never.

Two new candidates appeared (`SeedRole`, from upstream work merged mid-session) and both report
`unsupported-carrier` — honest boundaries.

### The ledger at the time (superseded by §11.3.1)

| | Count |
|---|---|
| Candidates surveyed | 17 |
| Real verdicts | **13** |
| Honest non-verdicts (`unsupported-*`) | 3 |
| Diagnosed failures (`timed-out`) | **1** — was an unbounded hang |
| Verdicts that are **wrong** | **4** — the commutativity `bothPass`es, §9.1 |

The headline has not moved and should not be allowed to: four of thirteen verdicts are wrong, for the
generator reason in §9.1, which nothing in §9.2, §11.2 or §12 touches. Everything shipped since has
improved the tool's *reach* and its *honesty about failure*. None of it has improved its *correctness*.

## §11.2.4 Still open

1. ~~The confident green (§9.1)~~ — **fixed, see §13.**
2. ~~The kit's `.rawRepresentable` recipe generates a non-terminating filter~~ — **fixed kit-side in
   v3.19.0, and unreachable through the index. See §11.3.**
3. **`build` is still unbounded.** Only the run is capped; a wedged `swift build` would still hang a
   survey.

---

# §11.3 The same shape, a third time

SwiftPropertyLaws v3.19.0 fixes the hang at source: `.enumCases` now takes precedence over
`.rawRepresentable`, so a raw-valued enum whose cases are known is *enumerated*
(`Gen.oneOf(Gen.always(T.a), …)`) rather than filtered. Mutation-tested, suite green at 720, and the
test that asserted the old precedence was inverted — the third green test in this arc that was green
because it pinned the bug.

**Re-running the survey against v3.19.0: `SemanticIndexEntry` still times out.**

The reason is visible in the index:

```json
"IndexedTypeShape.Kind": {
  "kind": "enum",
  "inheritedTypes": ["String", "Codable", "Sendable", "Equatable"],
  "storedMembers": [], "initializers": [], "hasUserGen": false
}
```

No `enumCases`. `IndexedTypeShape` — the consumer's persisted mirror of the kit's `TypeShape` — **has
no such field at all**. The case list exists in `TypeDecl`, is carried by `TypeShape`, and is dropped
on the way into `.swiftinfer/index.json`. So `enumCasesStrategy` returns `nil`, the raw fallback
fires exactly as designed, and the fix cannot engage.

## This is now a pattern, and the repetition is the finding

Three times in this road test a kit-side defect has been correctly fixed and found unreachable,
because the consumer had already discarded what the fix needed:

| # | Kit fix | Why it could not fire |
|---|---|---|
| 1 | `GeneratorResolver` refuses an ambiguous bare name (v3.18.0) | `IndexStore.typeShapes` is keyed on the bare name, so the ambiguity was collapsed before the kit saw it (§11.1) |
| 2 | `.caseIterable` emits a compilable expression (v3.18.0) | *did* fire — the one that worked |
| 3 | `.enumCases` beats `.rawRepresentable` (v3.19.0) | `IndexedTypeShape` carried no `enumCases`, so there was nothing to enumerate — **closed in §11.3.1** |

Two of three. The shared mechanism is that **the kit reasons over a projection the consumer
controls**, and every field the projection omits silently disables whichever kit tier depends on it —
with no error at either end. The kit's tests pass. The consumer's index looks complete. Only running
the pipeline end to end shows the tier is dead.

It also rhymes with the road test's own earlier lesson, recorded before any of this: *three passes
each named "the remaining blocker" for `serialize` and each was wrong* (`docs/measurements/roadtest-swiftlintrulestudio.md`).
A refuter that fires first hides every refuter behind it, and reading the code cannot tell you how
many are queued up. That was said about purity gates; it turns out to describe cross-repo projections
just as well.

## §11.3.1 The fix, and what it actually closed

`enumCases` added to `IndexedTypeShape` — a mirror `EnumCase` type, populated in both directions of
the `TypeShape` projection, `decodeIfPresent` so existing index files decode to `[]` unchanged (no
schema bump). 50 shapes now carry cases; `IndexedTypeShape.Kind` arrives as
`["`struct`", "`class`", "`enum`", "`actor`"]`, keyword escapes intact — which matters, because they
are interpolated straight into `Kind.`struct`` in the emitted generator and stripping them yields
`Kind.struct`, which does not parse.

**The survey went from 5 verdicts to 8 of 8 `measured-bothPass`.**

| Carrier | Before | After |
|---|---|---|
| `SemanticIndexEntry` | `timed-out` (300s) | `measured-bothPass` |
| `SeedKind` | `unsupported-carrier` | `measured-bothPass` |
| `SeedRole` | `unsupported-carrier` | `measured-bothPass` |
| the other five | `measured-bothPass` | unchanged |

The part worth noting is the two `unsupported-carrier` rows. Those had been filed as *honest
boundaries* — the one outcome class this write-up has repeatedly treated as trustworthy. They were
the same bug wearing a different label: enums whose cases were dropped, reported as "we don't support
this carrier" rather than "we discarded the data that would have supported it." One missing JSON field
was producing three different failure modes, two of which read as by-design.

That is the sharpest version of §11.3's lesson. A lossy projection does not announce itself as a
defect; it announces itself as a *limitation*, and a limitation is something a reader files away
rather than investigates.

## §11.3.2 The guard

`IndexedTypeShapeParityPropertyTests` — 6 tests, 3 randomized round-trip laws over generated shapes.
The mirror must preserve the kit shape, preserve it through JSON, and — the law that would have caught
the original omission — **must not change which strategy the kit derives**. A field added to
`TypeShape` and forgotten in the mirror surfaces there as a different derivation tier, which is exactly
what happened when `.enumCases` silently became `.rawRepresentable`.

Four mutants, all killed, including the two that matter: dropping `enumCases` on the way in
(reproducing the original bug verbatim) and the subtler one where the field survives conversion but is
never encoded.

## §11.3.3 Extending the guard — and finding it was the wrong shape

`IndexProjectionParityPropertyTests` (11 tests) extends parity to the rest of the persisted index:
`updated(from:)` on both entry types, `Codable` round trips with every column populated, the `Index`
container, and `upsert`'s documented behaviour (preserve `firstSeenAt`, keep history, sort by identity,
merge shapes, leave the sibling surface alone).

Two mechanisms carry the risk, and neither announces itself. **`updated(from:)` rebuilds field-by-field
through an initializer whose optionals and `Bool`s all have defaults**, so omitting a field compiles
and silently reverts it on the next re-index. This repo already learned that once — the archived note
on `InteractionInvariantSuggestion.with(…)` says it outright: *"a single site that still rebuilds
field-by-field still drops any field it forgets, silently, because the initialiser's parameters have
defaults. Mutating a copy cannot."* Both index entries still rebuild. And **hand-written `Codable`**
loses a field with no error at either end.

**Then the obvious problem with all of it.** Every guard written so far — including
`IndexedTypeShapeParityPropertyTests` — is *field-by-field*. It catches the fields someone thought to
name, and this bug is by definition the field nobody thought about. `enumCases` was absent for the
entire life of the type and no test failed, because no test knew to look for a field that did not
exist. **A field-by-field guard is a list of the things we already remembered.**

## §11.3.4 The guard that does not need updating

`FieldCoverageReflectionTests` asks the *type itself* what fields it has and compares that against
what survives encoding:

```swift
let stored  = Set(Mirror(reflecting: value).children.compactMap(\.label))
let encoded = Set(encodedTopLevelKeys(of: value))
#expect(stored.subtracting(encoded).isEmpty)
```

Staged against the exact future scenario — add a stored property, add it to the initializer, forget it
in `CodingKeys` — it reports:

```
`IndexedTypeShape` has stored property `newColumn` that never reaches the encoded
form — add it to `encode(to:)` and `CodingKeys`.
```

**Nobody wrote a test for `newColumn`.** Set that against how the same class presented the first three
times: a hung verifier, an `unsupported-carrier`, and an `architectural-coverage-pending` — every one
of them several layers downstream of the cause, and every one of them reading as a *limitation*.

Five types covered, plus a control fixture with a deliberately lossy encoder, because a coverage check
that cannot fail is worse than none. That control earned itself immediately: the first mutation
attempt came back **silent**, and the reason was that it broke the build rather than staging the bug —
a false negative that would have made the whole suite look validated.

### What reflection does not reach, and three options that would

`Mirror` sees the encode side. It cannot see a field that encodes correctly but is dropped by a
*converter* (`updated(from:)`, `init(from kitShape:)`) — which is precisely where `enumCases` died.
Three ways to close that, none taken here:

1. **Delete the defaults.** Give converters a no-defaults initializer and a forgotten field becomes a
   *compile error* — strictly better than any test. Costs one extra initializer per type.
2. **Mutate a copy instead of rebuilding.** A forgotten field then keeps the old value rather than
   reverting to a default. This repo already did exactly this for `InteractionInvariantSuggestion`;
   the index entries have `let` properties, so it is a real change.
3. **Generate the converters.** A macro removes the class outright.

## §11.3.5 Option 1, taken: the converter half is now a compile error

The defaults are load-bearing in tests (93 construction sites) and barely used in `Sources` (1–2 per
type), so removing them outright was not on. Instead each type gained an **exhaustive** initializer —
every parameter required, marked by `EveryColumn.required` — and:

**the exhaustive initializer is the designated one.** It assigns the stored properties; the ergonomic
defaulted initializer delegates *to it*; every converter calls it.

That direction is the entire mechanism, and getting it backwards is easy — the first version of this
change had exhaustive delegating to ergonomic, under which a field added only to the ergonomic
initializer breaks nothing and the guard does literally nothing. Adding a stored property now fails at
the exhaustive initializer:

```
Sources/SwiftInferCore/SemanticIndexEntry.swift:338:5: error: return from
initializer without initializing all stored properties
```

…and once a parameter is added there, every converter fails until the author answers the question the
default was silently answering: on a refresh, does this column come from the existing record or the
fresh one?

Verified by staging the realistic mistake on each type — add the property, add it to the ergonomic
initializer with a default, touch nothing else:

| Type | Result |
|---|---|
| `IndexedTypeShape` | caught at compile time |
| `SemanticIndexEntry` | caught at compile time |
| `InteractionIndexEntry` | caught at compile time |

`ExhaustiveInitializerAgreementTests` (3) pins the structural precondition — the exhaustive
initializer exists, agrees with its ergonomic sibling, and the ergonomic defaults equal what the
exhaustive one takes explicitly. If the delegation were ever flipped back, the build-time guard would
stop working while every other test still passed, which is exactly what happened during development.

### Two false negatives, and what they cost

Both came from checking the check, and both would have shipped a wrong conclusion:

1. **The backwards delegation** surfaced only because `InteractionIndexEntry` came back `NOT CAUGHT`.
   Without staging the mistake, three types would have carried a guard that did nothing.
2. **`SemanticIndexEntry` also reported `NOT CAUGHT`, and that one was the *staging* being wrong** —
   the property is declared `public var`, not `public let`, so the pattern matched nothing and no
   field was ever added. One step from reporting a working guard as broken.

That is three times in this road test that verifying the verifier changed the answer: the control
fixture in §11.3.4, and both of these. The pattern is worth naming — **a check that reports "no
problem" carries no information until you have watched it report a problem** — and it is the same
claim the whole document makes about `measured-bothPass`.

### The ladder, complete

| Layer | Catches | When |
|---|---|---|
| Compile error (`EveryColumn`) | a field dropped by a **converter** | build |
| `FieldCoverageReflectionTests` | a field dropped by **`encode(to:)`** | test, automatic for new fields |
| Parity suites | the specific columns and merge semantics | test, field-by-field |

The first two need no maintenance when a field is added. That was the goal: turn a class of bug that
presented three times as an unrelated-looking *limitation* into something the build refuses.

---

## §10 The one-sentence version

The tool found a real law and a real non-law on its own persistence layer and proposed both with equal
confidence, which is the case for having a verify path at all; and then its verify path, pointed at
the non-law, returned a confident green — because the generator it derives is built to cover the type
and nothing checks that it covers the *law*. Both halves of that sentence are the finding. Neither
was reachable by reading.


---

# §13 Fixing the confident green

§9.1's finding — `verify` reporting `measured-bothPass` on a law that is false — was the one item
every subsequent section left untouched, and the only one that was about *correctness* rather than
reach. It is now closed.

## §13.1 The result

> **PARTIALLY RETRACTED (a).** The `commutativity ×4 → measured-defaultFails` row **stands** — a
> refutation is a refutation, and the collision sweep that produced it shipped and is guarded by
> `CollisionPassTests`. The `associativity ×4 → measured-bothPass` **control row does not**: its
> Pass 2 was the hardcoded PASS. The argument it was making ("a fix that refuted associativity would
> have traded a false green for a false red") is still *sound* — associativity on these folds is
> genuinely true — but it was not *measured* to the standard this table claims. Re-run it against
> the shipped edge pass before citing it as a control.

| Template | Before | After |
|---|---|---|
| `commutativity` ×4 | `measured-bothPass` (**wrong**) | **`measured-defaultFails`** |
| `associativity` ×4 | `measured-bothPass` | `measured-bothPass` (**control**) |

The second row is the load-bearing one. Associativity on these folds is genuinely *true*, so a fix
that refuted it would have traded a false green for a false red — worse, under a project whose stated
posture is high precision (PRD §3.5). The counterexample the sweep reports is the real one: two
`Decisions` logs holding records that share `identityHash` and `timestamp` and differ elsewhere,
exactly the tie `MergeAlgebraPropertyTests` pins by hand.

`make batch4` green 7/7 — the frozen corpus sees no new failures.

## §13.2 The mechanism, and why it is at the RNG

The obvious fix — rewrite the recipe so key-like leaves draw from a small pool — needs structural
surgery on an expression this layer only holds as a **string**, plus a heuristic for which leaves are
"key-like". Both are guesswork, and the second is the same kind of name-based guessing this project
elsewhere refuses.

Every leaf generator instead draws from the same `RandomNumberGenerator`. **Narrowing the RNG narrows
every field at once** — string lengths, characters, dates, enum indices, array counts — with no recipe
parsing, no heuristics, and no knowledge of the carrier's shape. It works on a type nobody has seen.

It cannot produce a false positive, which is what makes it safe to run by default: the narrowed values
still come out of the *same generators*, so every operand is a legitimate value of the carrier. A
counterexample found there is a genuine refutation.

It is **not** a completeness claim. It raises the probability of reaching a collision-dependent branch
from ~zero to high. A law that survives both sweeps is still only "no counterexample in the generated
domain" — the honest reading §9.4 asked for, now with a much larger domain.

## §13.3 It was wrong twice, and both wrong versions were green

**Masking is not a small domain.** The first version narrowed with `next() & 0x3`. That collapses
every *derived* value toward zero, so `.array(of: 0...8)` produced a count of `0` on every draw and
both operands came out **empty** — and commutativity on two empty logs is trivially true. The sweep
ran, reported a clean pass, and reached nothing.

It was caught by probing the generated stub — printing the record counts it was actually producing —
not by reading it. The corrected design draws from a pool of well-spread constants: a small *number*
of possibilities, but varied values, so lengths and dates stay realistic while collisions stay common.
The pool size rotates across trials (`2, 3, 4, 6, 8`) because a single size is either so small that
both operands are identical or so large that collisions vanish.

**Then a stale binary made the fix look like a failure.** An earlier `cd` into a verifier workdir
persisted across commands, so a `swift build -c release` ran in the wrong package and the survey
executed the previous emitter. The redesign appeared not to work, and the next step would have been to
abandon it.

That is the fourth time in this road test that a green result meant nothing until the mechanism was
watched producing a red one — after the lossy-encoder control (§11.3.4), the backwards initializer
delegation, and the broken staging pattern (§11.3.5). It is the same claim the document makes about
`measured-bothPass`, and it keeps applying to the work of fixing it.

## §13.4 Guards

`CollisionPassTests` (7) pins the properties that make the sweep non-degenerate rather than merely
present: the RNG draws from the spread pool and never masks, the pool size rotates, the state advances
between trials, the sweep precedes the `PASS` print, and a collision failure reports through the
ordinary `VERIFY_DEFAULT_*` markers because it is the ordinary verdict.

Four mutants, all killed — including one that initially **survived** because the guard checked for the
literal string `& mask` rather than the operation, so a mutant masking by a different variable name
slipped straight through. The assertion had to be about what the code *does*, not how it is spelled.

## §13.5 Still open

1. **§2's seed-manifest numbers are stale.** `SwiftProjectLint` is 26 commits ahead of the pinned
   `6176101`, including `Stop seeding functions no test can call` and `Emit what the code IS in the
   seed manifest` — both change the manifest those figures came from. Re-running would change §2 and
   possibly §3's prediction scoring; per the freeze rule the original numbers stay as recorded and a
   re-run belongs in a new section.
2. ~~The sweep covers binary and ternary laws only~~ — **closed, see §13.6.**
3. **`swift build` in the verifier is still unbounded** (§11.2.4 item 3).
4. ~~The `SeedFocus` idempotence SIGTRAP~~ — **closed, see §16.**

---

# §14 Re-running the loop against the current linter

§2's figures are pinned to `SwiftProjectLint @ 6176101`. The linter is now **28 commits** ahead, and
several of those commits change the seed manifest directly — `Stop seeding functions no test can
call`, `Emit what the code IS in the seed manifest`, `Require kind when decoding a seed manifest`,
`Seed computed properties, which the manifest could not see at all`, `Tell a private candidate what to
do, and stop withholding it`.

Per the freeze rule §2 is **not edited**. This is a fresh measurement against
`SwiftProjectLint @ 4e54aa3`, recorded alongside the original rather than replacing it.

## §14.1 Prediction, logged before the re-run

1. **Total seeds fall.** Two commits explicitly *remove* seeds (`Stop seeding functions no test can
   call`, and the restricted-seed work), against one that adds them (computed properties). I predict
   a net decrease from 1,657, and that the `pure-function` count drops most.
2. **A new seed kind or field appears.** `Emit what the code IS` and the `role` field imply the
   manifest carries more than `{file, line, symbol, kind}` now.
3. **`discover`'s default-tier count is unchanged at 21.** Nothing in the linter feeds `discover`
   unless `--seeds` is passed, and §2's run did not pass it. If this moves, my model of the coupling
   is wrong.
4. **The `Non-Injected Nondeterminism` count is 6, not 18** — twelve were fixed in §12, and nothing
   since should have reintroduced them.

*(Results appended below as measured.)*

## §14.2 Result — measured against `SwiftProjectLint @ 4e54aa3`

> **STALE (b).** Seed and linter counts against `4e54aa3`, and `discover` output from a catalog that
> has since changed substantially. **§14.3 scores predictions against these numbers and inherits the
> staleness.** The *method* finding this section exists for — that the seeds did not fall, they were
> re-sorted into a new kind, and the prediction was wrong on direction — is a fact about what
> happened and is unaffected. **§14.4 is a diagnosis** (`Process.terminationHandler`, cited by
> `VerifierSubprocess.swift:350`) and is not covered by this notice.

### Seeds

| Kind | §2 (`6176101`) | now (`4e54aa3`) | Δ |
|---|---|---|---|
| `pure-function` | 1,457 | 926 | **−531** |
| `restricted-function` | — | **633** | *new kind* |
| `extractable-kernel` | 200 | 217 | +17 |
| **Total** | **1,657** | **1,776** | **+119** |

### Linter findings

| Rule | §12 | now | |
|---|---|---|---|
| Pure Function Property-Test Candidate | 1,458 | 1,559 | |
| Pure Closure Property-Test Candidate | 199 | 208 | |
| Extractable Pure Kernel | 1 | **9** | the path-derivation shape |
| Non-Injected Nondeterminism | 6 *(after §12's fix)* | **10** | see below |
| Thread Sleep | — | **2** | *new rule* |
| **Total issues** | 2,313 | 2,441 | |

### `discover`

| Target | §2 default tier | now |
|---|---|---|
| SwiftInferCore | 16 | 22 |
| SwiftInferTemplates | 3 | 5 |
| SwiftInferCLI | 2 | 5 |
| SwiftInferTestLifter | 0 | 2 |
| **Total** | **21** | **34** |

## §14.3 Scoring the re-run predictions

| # | Prediction | Outcome |
|---|---|---|
| 1 | Total seeds fall | **Wrong on direction** — 1,657 → 1,776. The `pure-function` half was right (−531). |
| 2 | A new seed *field* appears | **Wrong in kind** — the record keys are unchanged. A new *`kind`* appeared instead. |
| 3 | `discover` default tier unchanged at 21 | **Wrong** — 34. The *reasoning* held; the arithmetic did not. See below. |
| 4 | `Non-Injected Nondeterminism` is 6 | **Wrong** — 10. |

Four for four wrong, which is worth more than four for four right would have been.

**Prediction 1 — the seeds did not fall, they got *sorted*.** `Stop seeding functions no test can call`
does not delete those seeds; it reclassifies 531 of them into a new `restricted-function` kind. That
is a strictly better manifest: it separates "pure and reachable from a test" from "pure but nothing
can call it," which the old single `pure-function` bucket conflated. I predicted a *deletion* because
the commit subject says "stop seeding" — reading a changelog is not reading a diff.

**The consumer already handles it.** `SeedKind.restrictedFunction` is a first-class case in
`SeedManifest.swift`, with `isAnalysable == false` — so the 633 are correctly excluded from
`--seeds` focus rather than silently narrowed. Had it *not* been handled, `SeedKind.unrecognised`
would have caught it and also reported `isAnalysable == false`: the forward-compatibility case
`PersistenceRoundTripPropertyTests` pins, doing its job on a kind that genuinely did not exist when
that test was written.

**Prediction 3 — right reasoning, wrong number.** The claim was that the linter cannot move
`discover`'s count without `--seeds`, and that holds. What moved the number is that *this repo's own
source changed* — the upstream work merged mid-session plus the files added by §11–§13 — so
`idempotence` and `invariant-preservation` now fire where they did not before. I predicted a
comparison against a moving baseline and forgot that I was the one moving it.

**Prediction 4 — the new linter sees more than the old one.** §12 left 6 sites. Four of the extra
four are in `VerifierSubprocess.swift`, which did not exist in that form when §12 ran.

## §14.4 The linter caught code written in this session

The four new `Non-Injected Nondeterminism` hits and both `Thread Sleep` hits land on
`VerifierSubprocess.waitForExit` — the timeout added in §11.2, hours old:

```swift
let deadline = Date().addingTimeInterval(timeout)
while process.isRunning, Date() < deadline {
    Thread.sleep(forTimeInterval: 0.05)
}
```

The criticism is correct, and it is the same criticism §12 was about. The deadline reads the wall
clock directly and the poll busy-waits, so the timeout cannot be tested deterministically — which is
exactly why `VerifierTimeoutTests` had to spawn *real* subprocesses and wait *real* seconds. That
suite takes ~3.5s of pure sleeping, and its assertions are bounds (`elapsed < 20`) rather than
equalities, because there is no injected clock to pin.

**Fixed.** `waitForExit` now waits on `Process.terminationHandler` signalling a
`DispatchSemaphore`, with the deadline expressed as `.now() + timeout` — event-driven, no wall-clock
read, no spin. (One subtlety the rewrite has to handle: a child that exits between `run()` and the
handler being installed would never signal, so `isRunning` is checked once explicitly.)

| | before | after |
|---|---|---|
| `Non-Injected Nondeterminism` | 10 | **6** — exactly §12's residue |
| `Thread Sleep` | 2 | **0** |
| `VerifierTimeoutTests` | 5.1s | 3.5s |

**The finding is not the fix, it is that §12's lesson did not stick.** I fixed twelve `Date()` sites,
wrote up the mechanism at length, and then introduced four more within the same session — in code
whose entire purpose is to make a *timing* behaviour testable, and whose tests had to spawn real
subprocesses and sleep real seconds precisely because of it. The loop caught it; I did not. That is
the argument for running the linter every time rather than once, and it is the same shape as
§12 itself: the tool said it first, in the stage that is easy to skip.


## §13.6 The single-value case

The binary sweep makes two *operands* collide. It says nothing about elements colliding **inside one
generated value** — two records in one `Decisions` log sharing an `identityHash`, two entries sharing
a key. That is the same class one level down, and it is where the original finding actually lived:
`merge`'s tie is reachable because a *log* can hold colliding records, not merely because two logs can.

The mechanism needed no new idea. A collection generator draws its elements from the same RNG, so
narrowing the RNG makes the elements of one collection collide with each other exactly as it makes two
independent draws collide. `CollisionPass.unarySweep` is wired into `idempotence` and
`codable-round-trip`.

**It found nothing, and that is the honest result.** All eight `codable-round-trip` picks still pass;
idempotence is 6 `measured-bothPass` and 12 `architectural-coverage-pending`. The round trip genuinely
holds with colliding elements. The class is now *reachable* — the capability is real — but on this
corpus there was no collision-dependent unary law to catch. A null result from a mechanism that
demonstrably works elsewhere is worth more than a mechanism that was never pointed at anything.

Two things it did surface, neither a property failure:

**A bug I introduced.** The emitted body was `if \(functionCall)(…) != …`, and `functionCall` can be a
closure literal — so `if { … }(x) != …` parses as `if` with a trailing closure: *"missing condition in
'if' statement"*. The default pass binds locals first for exactly this reason; the sweep now does too.
Following the existing shape would have avoided it.

**A pre-existing trap it unmasked.** `SeedFocus` idempotence over `[Suggestion]` exits with SIGTRAP.
Verified as *not mine* by excising the sweep entirely and watching it still trap — the syntax bug above
had been masking it as `build-failed`. Diagnosing it took two attempts: the first used `print`, which
is block-buffered when redirected and loses everything on a trap, so the crash appeared to be earlier
than it was. Unbuffered stderr showed the truth. Left open — it is an existing defect in the
idempotence emitter for array carriers, not collision work.

Guarded by 9 tests (`CollisionPassTests`) and 5 mutants, all killed: sweep removed from either
template, drawing two values instead of one, failing to advance the RNG state, and reverting to the
low-bit mask.

## §15 Experiment — is a metamorphic law family worth building?

§3 measured the out-of-catalog problem exactly: **715 seeds in `SwiftInferCLI`
produced two default-tier picks.** The catalogue names value-semantic shapes
(`(T) -> T`, `(T, T) -> T`, round-trip pairs) and a scanner is
`SourceFileSyntax -> [Finding]`, which matches none of them.

The family that fits parser-adjacent code is *metamorphic*: not "f(x) equals
this value" but "f(x) and f(W(x)) are related, for a semantics-preserving
rewrite W". The cheapest W is **trivia**, because it is supposedly not
semantics, so no judgement about Swift is needed to know the rewrite is safe.

Run as an experiment before any machinery — five subjects, hand-written, in
`Tests/SwiftInferCoreTests/TriviaInsensitivityExperimentTests.swift`. If a
scanner failed, the direction was proven for an afternoon's work. If all passed,
that was learned far more cheaply than by building the template kind first.

### §15.1 Result

**All three structural scanners are trivia-insensitive** over 120 files / 322
function summaries / 232 type shapes / 10 rule visitors. No defect found.

That is the smaller half. The larger half is what the law cost to *state*, and
every item below is a cost a template kind pays on every carrier:

| # | Obstacle | Consequence for a template kind |
|---|---|---|
| 1 | **Type text is a source spelling.** `[String: Int]` and `[String:  Int]` name one type and differ as strings. | Needs whitespace normalisation per field. Without it the law "fails" on 12 files — every one a space inside a type spelling, not one a scanner defect. |
| 2 | **Locations are coordinates into the text.** `RuleVisitorCandidate` carries `"File.swift:214"`; reformatting moves line 214. | Positional fields must be projected away per output type. A template cannot tell a coordinate from a fact about the code. |
| 3 | **Trivia is not non-semantic in Swift.** Inside `"""…"""` the newlines are the string's *value*. | The *rewrite* needs a carve-out. Without it the inflater silently changed what two files meant — and both scanner laws passed anyway, because neither looks inside a literal. A passing law over an unsound rewrite. |

Obstacle 3 was found only by the token-stream guard — an assertion that the
rewrite changes nothing but trivia. It is the direct descendant of §13.3: the
mechanism was watched producing a red before its green was believed.

And two scanners are trivia-sensitive **on purpose** — `FunctionSummary.docComment`
reads prose, `SkipMarkerScanner` reads `// swiftinfer: skip <hash>` as an
instruction. A blanket "scanner output is invariant under trivia rewriting"
entry would be flatly wrong for both.

### §15.2 Verdict

The honest catalogue entry is not *"scanner output is trivia-insensitive"* but
*"trivia-insensitive **modulo a per-output-type projection**"* — and that
projection is hand-written curation, three of them for three scanners here.

**The direction is real; it is not free.** This is the same shape as §12's
central finding one level up: there, a derived generator was tuned for coverage
of the *type* and silently mistuned for coverage of the *law*. Here, a rewrite
is sound for the *language* and unsound for the *literal*, and a projection is
right for the *type shape* and wrong for the *candidate with a line number*.
Both times the gap sits between a generic mechanism and a specific claim, and
both times it is invisible from a green result.

Not built. The experiment cost an afternoon and returns a cost estimate rather
than a feature, which is what it was for.

---

# §16 The SeedFocus trap, diagnosed

The `[Suggestion]` idempotence entry (`0xC54D…`, `SeedFocus.seedIndependent(in:)`)
had produced three readings across three investigations — a SIGTRAP, a masked
build failure, then a closure-inference error — and each looked like a different
kind of problem. Three separate defects were stacked, and the second is why the
first and third took so long to see.

## §16.1 What was actually wrong

**1. An immediately-applied closure literal cannot infer its parameter.**
`functionCalls` is sometimes a bare reference and sometimes a closure literal —
the form a labelled call takes. The emitter applied it inline,
`{ SeedFocus.seedIndependent(in: $0) }(value)`, leaving `$0` nothing to infer
from; on a large derived generator the compiler gives up. Now bound once with an
explicit type. The existing emitter test *pinned the broken form*, so it had to
change — a test that pins the bug is worse than no test.

**2. `swift build` writes compile errors to stdout, and both failure paths read
only stderr.** Measured on this workdir: exit 1, **235 `error:` lines on stdout,
zero bytes on stderr.** Every build failure therefore printed `Last 20 lines of
stderr:` followed by nothing, and survey mode printed `build-failed: exit=1` —
the exit code being the least informative part of a build failure, since it is
always 1. The evidence naming defect 1 was captured and then discarded at the
last step, and "(no stderr captured)" reads as *the compiler said nothing*.

**3. The trap itself.** With both fixed and the corpus module wired in by hand,
the stub builds and the original SIGTRAP reproduces. Under lldb:

```
stop reason = Swift runtime failure: arithmetic overflow
frame #1: … implicit closure #3 in Score.init() at Score.swift
```

`Score.init(signals:)` sums `Signal.weight` with `.reduce(0, +)`. The strategist
derives `Gen<Int>.int()` for that field — the full 64-bit range — so two drawn
weights overflow. **The law was never evaluated.** `seedIndependent` is neither
confirmed nor refuted.

## §16.2 Why this is the same finding again

`Int` is the type of `weight`. Nothing in the type says that eight of them must
sum inside an `Int` — that is a fact about `Score.init`, not about `Signal`. So
this is §12's finding in a third costume: a derived generator is tuned for
coverage of the **type** and silently mistuned for the **law** (§12, the
confident green), for the **collision** (§13), and here for the **domain**.

There is no general fix. Narrowing `Gen<Int>.int()` globally would mask real
overflow defects and is exactly the "pile on filters" move `CLAUDE.md` warns
against. What *can* be fixed is that the trap was illegible.

## §16.3 What shipped

- A trapped run is classified as a crash, never a refutation — the law was not
  evaluated, so a counterexample would be fabricated. Guarded in both
  directions: signal exits must not refute, and an ordinary exit-1 failure must
  still refute.
- The reason names the signal, states the law was neither confirmed nor
  refuted, points at the generator's domain as the usual cause, quotes the
  runtime's own message when it survives, and carries whatever the stub flushed.
- Stubs set `setvbuf(stdout, nil, _IONBF, 0)`. `print` is block-buffered into a
  pipe, which is how the verifier is run, so a trap discarded every marker
  before it — the reason diagnosing this cost two attempts.
- `BuildDiagnostics` takes whichever stream carries `error:` lines rather than
  swapping one for the other, and prefers located `file:line: error:` lines
  over a positional tail: a 235-line log ends in `error: fatalError` and
  `Build failed`, neither of which names a cause.

**Measured honestly:** `setvbuf` recovered nothing *for this entry*, because the
trap fires on the first generator draw, before any marker is printed. It is
correct for traps that happen later and was kept on that basis, not because it
helped here.

**Still open:** the single-suggestion verify path does not wire the corpus
module, so a carrier internal to the package under test cannot resolve —
`--corpus-module` is documented for `--all-from-index` only. The end-to-end CLI
run for this entry therefore stops at `cannot find type 'Suggestion' in scope`
(now legible, which is the point). The trap classification above is verified by
unit tests and by the hand-wired workdir, not by that CLI path.
