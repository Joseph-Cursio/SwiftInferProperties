# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository. **This file is a
pointer-only index**, and deliberately short: it loads into context every session, so it
carries the hook and the target, never the reasoning.

**The reasoning lives in `docs/reference/index-annotations.md`** — the long form of the
index below, one annotation per row, matched by the Question column. Every row's
measurements, rejected alternatives and standing constraints are there verbatim; read it
before acting on a row, and update it when you update a row. Per-cycle narrative lives in
`git log` and `docs/archive/claude-md-narrative-history.md`.

## What this repo is

**SwiftInferProperties** (`swift-infer`) — type-directed property inference for Swift.
Reads code, proposes properties, **never applies anything**. Surfaces idempotence,
round-trip pairs, algebraic structure (semigroup → ring, semilattice), and the five
*interaction*-invariant families over reducer / MVVM carriers. All output is
human-reviewed; nothing auto-executes.

One-way downstream in the five-package toolchain:

```
SwiftProjectLint ──▶ SwiftInferProperties ──▶ SwiftPropertyLaws ──▶ SwiftIdempotency
 lint + pbt-seeds      discover + stubs         run the laws         retry-safety
        ▲                      ▲
        └──── SwiftEffectInference (purity oracle; no CLI, runs inside both) ────┘
```

Sibling checkouts expected at `../SwiftPropertyLaws` and `../SwiftEffectInference`.

**Read the dependency pins from `Package.swift`, never from prose.** SwiftPropertyLaws is
a `from:` requirement (`Package.swift:112`); SwiftEffectInference is pinned by revision
(`Package.swift:122`, SEI carries no version tags). Prose copies of both have gone stale
by a full major version and by 15 commits. `VerifierWorkdir.swiftPropertyLawsRequirement`
must equal the package pin and is guarded by `VerifierWorkdirKitPinTests`. Generated
stubs import the opt-in `PropertyLawComplex` product; the main `PropertyLawKit` line
keeps a zero `swift-numerics` footprint.

## Current state

**v1.160.0.** Two disjoint surfaces, both discovered → surfaced → verified → promoted end
to end:

- **Algebraic** — pure-function laws from signatures, cross-function pairs, and lifted
  test bodies. v1 corpus (`fixtures/cycle27-surface/`) is **100% measured** (53/53); further
  movement needs *new* public algebraic API, not filters or recipes.
- **Interaction** — five families (idempotence / cardinality / biconditional /
  referential-integrity / conservation) over reducer carriers (TCA, Elm, ReSwift, Mobius,
  Workflow, generic) and SwiftUI MVVM carriers. Idempotence promotes `.likely → .verified`
  on measured execution; the rest default `.possible` behind `--include-possible`.

Consumers over the SemanticIndex, split by trust bar: `query` (author, all tiers) ·
`insights` (author, inferred cross-type structure) · `docc` (reader, **verified-only**).
Async is admitted only via the `@ClockDeterministic` claim.

Suites green at **6,671 tests — 6,447 fast + 224 across `perf` and the eight batches**
(**a genuine full `make test`, verified green 2026-10-05** at `186bb8b8` (the 1.159.0 release branch)
on **swift-property-based 2.0.1 / SwiftPropertyLaws 4.9.3 / SEI `1b62e764`**, Xcode 27 / Swift 6.4 —
every stage counted from that one run, and the run was UNPIPED (`make test > log 2>&1`, exit **0**):
fast **6,447** · perf 8 · batches 4 · 111 · 31 · 7 · 14 · 4 · 9 · 36.
**The batch half stood still at 224, every batch to the digit**, across everything merged since
`5dd4e88f`: tuple determinism declines, docstring advice outside the seed focus, and the
reference-oracle scaffold rebuilt on accept's call plan — ⚠ **but the corpus-surveying batches assert
floors (`> 1_000` rows), so 224 green is not an A/B; the row dumps in `fixtures/` are.**
**The fast half moved 6,241 → 6,447, +206**: +60 up to 1.158.0, then +75 (#623, the shared
determinism call plan) and +71 (#624, the reference-oracle scaffold); #625 is docs, scripts and
fixtures.
**Timings** (an M5 Pro; batch boundaries read off the log every 5 s): `batch3` 112s; `batch2` 342s;
`batch5` 695s; `batch1` 106s, `batch4` 86s, `batch6` 50s, `batch7` 81s, `batch8` 287s; fast suite 84s,
whole run 1,865s.
**Every earlier reading is SUPERSEDED HISTORY and lives in `docs/reference/index-annotations.md` § *Superseded test-count readings*** — kept there because each records what its verdict was decided on; read it for the reasoning behind a past verdict, never for a current count.
**Quote both halves, never the total alone**: a new `*MeasuredTests` suite that never
reached a batch shows up here as the fast count rising while the batch count stands
still. **Flake note:** the long measured/calibration suites occasionally drop one issue
under load — rerun before diagnosing.

**Both repos pin SEI `1b62e764` (bumped 2026-09-12, `44a23e1c`), and `SEICrossRepoPinTests`
is green as of the 2026-09-17 full run** — the guard compares this manifest against
SwiftProjectLint's, so green means they agree, and the figures below were taken at `3ea25f2`.
Bumped as a joint act across all four manifests, which is what the guard exists to enforce:
disjoint pins mean the linter and the inference engine are not consulting one purity
oracle, and that guard is the only thing that can say so.

**`3ea25f2` is the first SEI bump that MOVES VERDICTS in this repo** — every earlier one
was additive. It closes the non-throwing half of the I/O hole (`FileHandle` / `Process` /
`Pipe` joined `sideEffectMarkers`; `FileHandle.standardError.write(_:)` does not throw, so
the `try` gate never reached it) and makes `hasRefutingMarker` consult
`NondeterminismSources` as a **union** with the token set, never a replacement. **What
this costs when bumping SEI again:** every purity census's numbers are computed against
the pinned oracle, and `PurityRefutationCensusMeasuredTests` re-derives SEI's `private`
refuters to attribute causes. `verdictAgreesWithSoundPurity` is the guard —
**a drifted replica voids the census rather than misattributing quietly**, and it caught
this bump with 8 named mismatches before any figure was touched. Expect `make batch2` to
go red on an SEI bump, and treat that as the apparatus working. Re-take the counts; never
extrapolate them.

## Where to look

One line per row. **The full annotation for every row is in
`docs/reference/index-annotations.md`** — go there before quoting a number or re-opening a
decline, because the hook states the verdict and the annotation states what was measured.

| Question | File | Hook |
|---|---|---|
| **Why is this file short, and where did the reasoning go?** | `docs/reference/index-annotations.md` | The long form of every row below, verbatim. Moved out 2026-08-17 so the index stops costing 158 KB of context per session |
| **What does the package build but never call?** | `make dead-code` (`scripts/dead_public_api.py`) | Reachability at **file** granularity; `test-only` is the verdict that matters. Deliberately does not gate the build |
| **How is `docs/` organised, and what does a doc's status mean?** | `docs/README.md` | Two independent axes: directory = what a doc *is*, status header = where it is in its life |
| **Does `make docs-drift` check what you think it checks?** | `docs/measurements/docs-drift-coverage-boundary.md` | **No — 9 of 91 docs, and 49 unchecked ones make cross-repo claims.** The summary was a count with no denominator |
| **What does this word mean?** (template, carrier, decline, composer-supported, reach, latent, Daikon trap…) | `docs/design-internal/glossary.md` | Vocabulary keyed to the code that owns it. Read the `Daikon trap` entry before proposing a filter |
| **What would "the toolchain is in shape" MEAN — and is it in shape?** | `docs/design-internal/toolchain-exit-criteria.md` | **Criterion A is the bar (B–E do not gate), split into A-reach (MET, swift-system) and A-quality** — A-quality's `ToolChoice` basis is CONTESTED since 2026-08-30; read §6 |
| **Where does a decision go when it has no other home?** | `docs/design-internal/open-threads.md` | The residue file: open rows, conversation decisions, standing observations. Live work is rows 65, 70, 72, 76; recount the table before quoting a count |
| **What does a SIBLING repo actually do, and what crosses the seam?** | `docs/design-internal/` | One doc per toolchain repo, each pinning its subject's SHA; `make docs-drift` reports which have moved |
| **When `verify-interaction` reports a refutation, what actually trapped?** | `docs/measurements/interaction-trap-attribution-census.md` | Measured: 10 refutations, 10 invariant-check, 0 subject-code — on reducer corpora only |
| **Can a stale summary be caught mechanically?** | `docs/measurements/stale-summary-guard-declined.md` | **Measured NO, four designs.** We correct by annotation, so a fixed doc fires forever |
| **Why does a falsifier go inert, and which kind?** | `docs/measurements/falsifier-naming-failure-modes.md` | Name what the fix must EXPOSE; sibling-scoped falsifiers are sound, invented local names are not |
| **A deferral must name what would refute it** | `DeferralFalsifierTests` + `docs/README.md` | A falsifier annotation beside the claim names the symbol whose existence would refute it, and the test fails the day it resolves. `docs/README.md` spells the form |
| Product scope, milestones, success criteria | `docs/SwiftInferProperties PRD v1.0.md` (canonical) + ` v2.0.md` | — |
| Measured-verify design (the whole v2 interaction story) | `docs/design/measured-verify-architecture.md` | **Read first** |
| **The verify edge pass** (why `bothPass` used to under-claim) | `docs/design/verify-edge-pass.md` | Pass 2 was a zero-trial sentinel; boundary values belong in an **advisory** pass, swapped at the rendered expression |
| **Why is 88% of `discover`'s default output `predicate`?** | `docs/design/predicate-display-order.md` | Fixed by **ordering**, not hiding — a law the code owes is never hidden |
| **Why does `verify` decline so much?** | `docs/measurements/verify-carrier-reach-census.md` | **Not** carrier support: carrier is ~4% of declines, template reach is 65% |
| **Is an unrecognised callee safe to wave through?** | `docs/measurements/purity-unrecognised-callee-census.md` | **Measured no — a subprocess spawn is judged `.pure`**, but the allowlist fix costs 65% of `.pure`. Verdict unchanged at SEI `3ea25f2` |
| **Is `PurityVerdict.refuted` evidence, or the analyzer reporting its own blindness?** | `docs/measurements/purity-refuted-bucket-census.md` | **Measured 54% ignorance, then 45%, now 43%** — check which SEI pin a figure belongs to. Rankable ceiling **133**; it has been 152 and 135. Every refuter added anywhere shrinks this bucket |
| **Would a blocking-callee index earn its keep?** | `docs/measurements/purity-blocking-callee-census.md` | **Measured NO, twice over** — 13–31 rows of leverage behind 133, landing in a tier nothing reads |
| **Does the toolchain need to run in a LOOP — would a refuting-direction fixpoint pay?** | `docs/measurements/purity-refuting-fixpoint-census.md` | **BUILT as `PackagePurityJoin` (retracts 16); the loop itself is unbuilt.** 18 rows at one hop, 29 at fixpoint; a hand-check killed the first answer |
| **Does purity propagate through a higher-order call?** | `docs/measurements/purity-higher-order-census.md` | **Premise measured FALSE** — chains sail through. The real gap is a 26-row over-claim; item 42 closed |
| **Is there anything for a `.pureButPartial` consumer to consume?** | `docs/measurements/partial-purity-consumer-declined.md` | **Measured NO — ceiling is 2 suggestions over 363 throwing functions.** No template gates on `purityVerdict`; closes items 31–34 |
| **Does taking the `pure` advice change anything?** | `docs/measurements/pure-advisory-round-trip.md` | **Measured NO — 3,250 annotations, 0 suggestions moved.** The channel is live (`non_idempotent` vetoes); `pure` is the inert tier |
| **Does moving from `throws` to `Result` put more code within a law's reach?** | `docs/measurements/result-carrier-reach.md` | **Measured NO.** Quote the performable refactor, **−53** — never −218 or −66. One in six throwing functions cannot change signature |
| **Would refactoring toward purity put more code within a law's reach?** | `docs/measurements/purity-refactoring-reach.md` | **Measured NO at a ceiling — zero suggestions moved**; read back, 22 of 921 rest on a witness-refuted subject, so the signal's use is a veto |
| **What would a purity veto cost?** | `docs/measurements/purity-veto-precision.md` | **Affordable when witness-scoped; SHIPPED as `applyImpureSubjectVeto`.** The scoped arm is unpriceable post-veto; priced from the pre-veto key, 3 of 10 |
| **Why was a MUTABLE property offered as a law subject?** | `docs/measurements/modify-accessor-misclassification.md` | `isReadOnlyGetter` missed mutating accessors — now an allowlist, **6 → 0** admitted |
| Full historical changelog (every shipped cycle, verbatim) | `docs/archive/claude-md-narrative-history.md` | The rest of `docs/archive/` is shipped-then-archived design records. Archived ≠ superseded — read for reasoning, never for counts |
| Per-cycle change story | `git log` | The per-cycle findings docs were folded into the archive above |
| Road tests (third-party subjects) | `docs/measurements/roadtest-*.md` | SwiftProjectLint (first scored, frozen key), SwiftLintRuleStudio, MacCloud server / client, SwiftMarkdownWiki |
| **Corpus pipeline walk** — where does a predicted property test fail to arrive, and at which stage? | `docs/plans/corpus-pipeline-walk-scope.md`, `docs/measurements/roadtest-swiftmarkdownwiki.md` | **Method + first subject**: stage taxonomy S0–S8, prediction written before the run. #414 fixed; it bought 0 running laws |
| **What did four stub writers actually buy — the funnel, re-run?** | `docs/measurements/corpus-funnel-census-2026-09-16.md` | **Stubs 309 → 980, compiles 92 → 183, passes 71 → 67** — the binding constraint moved from *no writer* to *does not compile* |
| **What did generators for the unbuildable buy? The funnel, re-run** | `docs/measurements/corpus-funnel-census-2026-09-20.md` | **Compiles 219 → 553, passes 150 → 471** — both generators built for SwiftProjectLint's shape; read as this corpus, never a rate |
| **What did three days of fixes buy? The funnel, re-run** | `docs/measurements/corpus-funnel-census-2026-09-19.md` | **Passes 67 → 150, compiles 183 → 219, stubs 980 → 924.** SwiftProjectLint is the control row; the tokenizer hang is a real subject defect |
| **Should a law draw its domain from a CORPUS instead of a generator?** | `docs/measurements/corpus-domain-declined.md` | **DECLINED on this corpus, conditionally** — 94% of the population is SwiftProjectLint, and test-value mining yields zero |
| **Should the catalogue EXHAUST a small domain instead of sampling it?** | `docs/measurements/exhaustible-domain-census.md` | **Declined on population (30 refutable rows of 5,127)** — but exhausting would make `bothPass` a whole-domain claim; two cheap exceptions recommended |
| **Why does no generator derive?** | `docs/measurements/generator-blocker-reasons.md` | **Five causes; 92% should not be built** — half is SwiftSyntax nodes in one repo, 41% classes by design. Actionable remainder ~35 stubs |
| **What is behind the wall — why do stubs fail to compile now?** | `docs/measurements/missing-generator-census.md` | **The generator: 1,326 of 2,058 stubs (64%) carry an underived `.gen()`** — a long tail with no head worth fixing; causes measured by probe |
| **Is the funnel's *nothing proposed* stage a catalogue gap?** | `docs/measurements/nothing-proposed-decomposition.md` | **Measured NO — 527 of 639 are seeds the `determinism` fallback rejects**, mostly computed properties; widening it moves zero refutable laws |
| **Does `scaffold-kit-suites`' live/commented count mean the file COMPILES?** | `docs/measurements/exploratory-swiftformatrulestudio.md` | **Measured NO — FIXED 2026-08-13** (`TargetIsolation`): a package's `defaultIsolation` blocks every conformance |
| **Why did a rule-name predicate get a PATH generator?** | `CollisionBias.collidingString` / `pathShapedNames` | One recipe served every `String` parameter; path-prose 110 → 3 on this repo, rows unchanged |
| **Why does TestLifter miss a round-trip test a human wrote?** | `FunctionCallExprSyntax.consumedValueExpression` + `ExprSyntax.stableValueReferenceText` | Two independent causes, both blind to *house style*: value through the receiver, and `Self.sample` |
| **Can the tokenizer's conservation law be templated?** | `docs/measurements/whole-to-parts-partition-declined.md` | **Measured NO, ~4% against a 70% bar.** The law is not in the signature — reopens on a witness |
| **Why does totality fire on `parse` and not on `tokens`?** | `HostileInputEntryPoints.resultNouns` | The gate wanted a verb. The noun route is deliberately stricter; the obvious fix was measured and rejected at 50% |
| **Where does a measured REFUTATION show up?** | `RefutationRenderer` | It did not, anywhere, until 2026-08-13 — a `REFUTED BY MEASUREMENT` block on stdout. The veto is unchanged |
| **Self-dogfood** (the tools pointed at this repo) | `docs/measurements/roadtest-self-dogfood.md` | **Every measurement WITHDRAWN 2026-08-01** — read its header. 19 live sites cite its diagnoses, which stand |
| **Self-dogfood, second pass** — point the toolchain at this repo and *land tests* | `docs/measurements/roadtest-self-dogfood-2026-08-08.md` | The longest annotation by far: test-target scoping, lifted-row provenance, the `+20` seam, and the stale-evidence soundness hole and its fix |
| **Can the same-name duplication miss be templated?** | `docs/measurements/same-name-differential-pairing.md` | **Measured NO, 40% against a ≥50% bar.** The dominant FP is undeclared *role* interfaces |
| Where the catalog stops on **parsers** | `docs/measurements/parsing-catalog-gap.md` | Ledger closed 7/7; the generator weaknesses and the SIGBUS stack-depth trap are still live |
| Historical **backtests** — does the catalog fire on code written before it? | `docs/measurements/backtest-apple-libraries.md` · `docs/measurements/backtest-codable-roundtrip-pressuretest.md` | The pressure test's recommendation became the shipped `codable-round-trip` template |
| Would a **conformance-keyed** template earn its keep? | `fixtures/equatable-signal/README.md` | **No** — conformance does not predict refutability, the `==` *body shape* does. Propose the model law for projections |
| **What does a hand-written `==` actually DO?** | `EqualityBodyShape` / `EqualityBodyClassifier` | Three shapes read off real bodies; took the sequence-view law from 7 Strong to exactly the 3 refutable ones |
| **When is a carrier's iteration order part of its VALUE?** | `OrderedCarrierDiscriminator` | 0 false positives over 20 documented-order types. Ordered is not enough — the value must be *determined by* its elements |
| **Five-repo adoption loop** — is the toolchain usable end to end? | `docs/plans/PBT_TOOLCHAIN_FIX_PLAN.md` | Scored against `MacCloud_client_iOS`; its answer key lives in the fixture repo. Interaction step added 2026-08-01 |
| **The TCA determinism follow-up track — closed, and it under-reported itself for a month** | `docs/design/tca-determinism-followups.md` | Closed — all four complete. It under-reported itself for a month; a doc's self-reported status is a claim, not evidence |
| Design records for **shipped** work | `docs/design/docstring-corroboration.md` · `docs/design/stateful-role-discoverer-design.md` | The MVC tail is a recorded *decline*; the per-declaration `RolePolicy` engine was deleted 2026-08-07 |
| Investigations with a recorded **decision not to build** | `docs/design/bridge2-materialisation-spike.md` · `docs/design/rule-visitor-carrier-scoping.md` | The determinism invariant is deliberately **not** emitted — do not "fix" it |
| **Why `Signal+Kind.swift` has an overflow file** | `docs/design/signal-kind-rationales.md` | The enum cannot split across files and hit its 400-line cap. Move the next-longest rationale out; never trim a new one |
| **`--sources` — which commands can open an Xcode project** | `TargetDirectory` + `XcodeSourcesReachTests` | On four commands now. `verify-interaction` deliberately does NOT get it — it would fail later, saying less |
| **Is the coverage veto's premise true?** | `ProtocolCoverageAudit` | Measured: the veto is close to a no-op (1 suggestion in ~300). Three states, and `wasExercised` alone cannot separate two of them |
| **Are the coverage claims TRUE, law by law?** | `docs/measurements/protocol-coverage-law-drift.md` | **13 of 56 `(key, law)` claims were false.** Both defects fixed and A/B'd; `Self` resolution still open, deliberately |
| **Kit results feeding back into inference** | `KitEvidence` / `KitEvidenceScoring` / `KitEvidenceStore` | Kit refutation demotes −45, never vetoes; passing is score-neutral provenance. Three measured exclusions |
| Command docs | `docs/reference/report-command.md`, `census-command.md`, `insights-command.md`, `docc-generation.md`, `prove-then-show.md`, `known-properties.md`, `stdlib-anchor.md`, `interaction-semantic-index.md` | — |
| End-user docs | `docs/user/{tutorial,guide,reference}.md` | — |
| Dogfood findings (own + sibling repos) | `docs/measurements/dogfood-new-templates-findings.md` | — |
| **swift.org property-style-test study** | `docs/archive/swiftorg-property-test-study-scope.md` · `docs/measurements/swiftorg-property-test-study-findings.md` | Seeded stratified sampler; frozen answer key committed **before** any `discover` run. Every number carries its SHA |
| **A legible end-to-end example** — what does the tool actually do to a sort? | `fixtures/leaderboard-sort/README.md` | ⚠ Scorecards **WITHDRAWN** — read the header. The mutant matrix, the `next()` template defect and the comparator name gate stand |
| **Is a weak generator worth converting?** — Q4's before/after | `fixtures/integer-division-generator/README.md` | **Yes — report it in refutation units**: 2/8 → 8/8 mutants killed, with two interior controls |
| **Why does the `Strong` tier run nothing, and what did that cost?** | `TemplateName` + `DifferentialVerifySupportTests` | `differential-equivalence` FIXED 2026-08-08; `invariant-preservation` deferred. Five enumerations of the vocabulary must agree |
| **Does deriving the second operand buy refutations a bigger budget cannot?** | `fixtures/collision-pairing/README.md` | **Lever real on a WIDE domain, population absent — recommendation retracted.** Quote the key-space row |
| **Is the hand-written `OrderedSet` generator any good?** | `fixtures/ordered-set-generator/README.md` | 101 reachable values, 3 mutants exhaustively unreachable. Widening was the wrong lever for the order projection — a pair sampler is |
| **Should `inverse-pair` and `identity-element` get composers?** | `docs/plans/inverse-pair-identity-element-composers-scope.md` | **Measured NO, including via the projection route.** Shipped `UnverifiableCause.carrierNotEquatable` instead |
| **Is the POSTCONDITION law worth a template?** — BUILT | `docs/measurements/postcondition-law-declined.md` + `RolePostconditionTemplate` | **Postcondition kills 4/4 where idempotence kills 1/4.** Shipped via role-supplied predicates; verifiable for `lowercased`/`uppercased` only |
| **Which property actually refutes a NORMALISER's bugs, and is the pairing template worth building?** | `fixtures/branch-reaching-generator/README.md` §4–5 | **Postcondition 4/4 · idempotence 1/4.** Pairing template declined on population; the body-guard route is unmeasured |
| **Does widening the generator's character class reach the branch a law is about?** | `fixtures/branch-reaching-generator/README.md` | **Reach is necessary, not sufficient** — the lever is a NARROW alphabet, not a wider one |
| **A-quality on a SHORT-CHAIN subject — answered YES, by a REAL defect** | `docs/measurements/criterion-a-quality-mcp.md` | **Met on `mcp-swift-sdk` by `ToolChoice`, no mutant planted** — the finding is now CONTESTED (OpenAPIKit's maintainer ruled the shape intended) |
| **A-quality — does an emitted law kill a mutant the subject's own tests miss?** | `docs/measurements/criterion-a-quality-swift-system.md` | **NO at N=100, YES at N ≥ 500 — default raised to N=1000.** Verify is compile-bound; the 10× budget costs ~0.14% per row |
| **Criterion A on a second unmet subject — does a law kill a mutant?** | `docs/measurements/criterion-a-swift-system.md` | **Still fails on swift-system**; the first diagnosis was wrong (a module-resolution bug). SPL 4.1.0 gave the first executing laws; NUL stays in `asciiScalar()` |
| **Does the tool propose laws that cannot be WRITTEN?** | `docs/measurements/availability-gate.md` | **Yes, and FIXED** — gate on `unavailable` + `obsoleted:` only; 19 rows name an uncallable subject, 35 removed. Costs no laws |
| **Does an emitted law kill a mutant the subject's own tests miss?** (criterion A) | `docs/measurements/criterion-a-unmet-subject.md` | **Not answered — 89% of laws did not compile** (three emitter defects, since fixed). The planted mutant preserved idempotence; see §3.1 |
| **What does the toolchain reach on a subject it has NEVER met?** | `docs/measurements/exploratory-swiftformat-grdb.md` | 87/159 laws on the home corpus against 1/129 and 5/307. Five instrument defects; state gains as **rows moved**, never laws gained |
| **What IS the measurement corpus, and can a run be reproduced?** | `fixtures/corpora/manifest.json` | 21 subjects, four kinds, six apparatuses. The pinned revision belongs to the RUN; cannot-check is a third state |
| **Can two survey runs be compared at ROW level?** | `fixtures/verify-runs/README.md` | They can now; for four runs they could not. A change of decline **cause** is reported as loudly as a bucket change |
| **How many laws actually RUN, across all templates?** | `fixtures/whole-corpus-survey/` | **65% of runnable-tier entries execute — quote runnable tiers, never the total.** A 10× budget moved one row; all refutations hand-check false |
| **Does the TEMPLATE predict whether a refutation is worth reading?** | `docs/measurements/template-refutation-rates.md` | **Partly.** Totality: 0 refutations of 102. Idempotence: ~21.5%, all hand-checked false. `codable-round-trip`: not a rate |
| **Can "1 real of 19" be turned into a RATE?** | `docs/measurements/refutation-rate-second-subject.md` | **NO — zero refutations on two unmet subjects.** Selection needs `Codable` ∩ `Equatable` on one type; a `SymbolJoinKey` suppression bug was fixed |
| **Was the blocker really RECURSION?** | `docs/measurements/module-qualified-leaf-spelling.md` | **NO — leaf spelling (`Swift.String`), not recursion.** 0 → 15 of 55 rows execute; moved upstream as SwiftPropertyLaws 4.2.0 |
| **Can the rate be obtained — attempt two?** | `docs/measurements/refutation-rate-third-fourth-subject.md` | **Still not a rate**; `jwt-kit`'s `UserDetectionStatus` is a second real codable defect — counterexample quality and finding reality are independent axes |
| **Is there a fifth subject — and what stops the richest one found?** | `docs/measurements/fifth-subject-screen.md` | **Eight screened, none viable** — `turf-swift` stops on a missing `CLLocationCoordinate2D` generator. A zero from an unread subject is not evidence |
| **Which candidate subjects are left, and is the pool really exhausted?** | `docs/measurements/candidate-screening-pass.md` | **Pool measured exhausted (63 screened).** OpenAPIKit `OpenAPI.XML` was ruled INTENDED upstream (#509) — tally 3 real of 42. Quote both pre-check readings |
| **What does the toolchain reach on the richest subject screened — and is every real defect the same shape?** | `docs/measurements/subject-swift-docc.md` | **swift-docc: 49 verdicts, 13 refutations**; `CatalogFeatureFlags` decode THROWS — a fourth defect, latent, and a different shape |
| **What runs on a subject that is NOT a JSON format — and does the algebraic half of the catalogue work?** | `docs/measurements/subject-euclid.md` | **Euclid: 84 verdicts, 31 refutations, ~0 real** — the algebraic templates fire on shape, not property (row 69); round-trip pairs on signature alone (row 70) |
| **What is a passing law worth — does it notice a planted bug?** | `docs/plans/funnel-mutation-check-scope.md` | **`proposed`, not run** — scores mutants KILLED / DIVERGED / UNEXERCISED over 60 stratified laws |
| **What did the mutation check find — does a passing law notice a planted bug?** | `docs/measurements/funnel-mutation-check.md` | **Laws caught 9 of 34 output-changing mutants (14 on re-score)**; totality 1 of 18. Passes split 126 behaviour + 451 does-not-crash — quote both |
| **Is `idempotence` false for an escaper — and how many escapers are there?** | `docs/measurements/replacement-chain-idempotence-census.md` | **10 chains, 5 not idempotent**, decided by evaluating the chain; `ReplacementChainClassifier` gate BUILT |
| **Should a generator draw the subject's own literals?** | `docs/plans/subject-literal-generation-scope.md` | **BUILT (kit 4.8.0 + `SubjectLiterals`)** — found the `RuleDocView.parseBlocks` hang, a real defect. Literals make passes honest, not more discriminating |
| **Can every subject in the corpus even be BUILT — and does the last stage add up?** | `docs/measurements/corpus-funnel-census-2026-09-20-all-resolve.md` | **Compiles 597 → 634 with no toolchain change** — every repo now resolves; a stub never attempted is not a law waiting |
| **What did 42 widenings buy — and does the funnel's last stage add up?** | `docs/measurements/corpus-funnel-census-2026-09-20-after-widening.md` | **Compiles 553 → 597, exactly one repo moved.** The last stage now reconciles: crashes are a third outcome |
| **Is the compiler's FIRST error the blocker — what is really stopping a set-aside stub?** | `docs/measurements/set-aside-stub-decomposition.md` | **NO — 118 of 171 stubs are `private`**, not 42; widen only where a generator exists. 70 of 72 widenings converted |
| **What does refusing a test-local cost, and what is behind it?** | `docs/measurements/receiver-construction-local-inlining.md` | **+2 compiles; 54 stubs changed blocking reason**, 42 of them to `private` subject — the widenable set named |
| **Does a CHARACTERISATION law catch an edit — and what does `guard-domain`'s writer reach?** | `docs/measurements/guard-domain-stub-writer.md` | **WRITTEN** — a characterisation law: it pins the guarded answer, not the guard; the coverage guard reports `NOT APPLIED`. Reach quoted two ways |
| **What did the template MATCH — and can `guard-domain`'s writer be built?** | `docs/measurements/template-match-payloads.md` | **`Suggestion.match: TemplateMatch?`** carries what four templates computed and dropped; 83% of guard-domain sites bindable |
| **Does an accepted `filter-subset` suggestion actually WRITE a test — and can the law it writes fail?** | `docs/measurements/filter-subset-stub-writer.md` | **WRITTEN — 10 of 10 write, 3 of 10 fully derived; quote both.** The law can fail; `DropFirstKeeper` passing is the informative cell |
| **Is the NAME really the contract — and what does role-entailment oblige a template to do?** | `docs/measurements/subset-name-contract-gate.md` | **The standard was right, the gate wrong** — connective/transform tails rejected; cost exactly −1 row, the false law |
| **Should `normal-form` or `state-machine` get a stub writer?** | `docs/measurements/normal-form-state-machine-writers.md` | **`normal-form` DECLINED** (vacuous generators); **`state-machine`'s blocker is false pairings**, not the writer |
| **Is a survey refutation a real bug, and does the TIER predict it?** | `docs/measurements/refutation-hand-check.md` | **15 of 15 false laws; tier does not predict** — re-asked on four subjects, two disagree in direction. Count the denominator per tier |
| **What would widening access actually buy?** | `docs/measurements/visibility-widenability.md` | **918 widenable rows (20 corpora), 87% the false-law head.** `internalOrSPI` blocks nothing — counting it inflates the lever 2.7× |
| **Can a `private`-subject law name the caller to lift it to?** | `docs/measurements/lift-caller-reach.md` | **Yes — 260 of 373 visibility declines name a visible caller.** A caveat, not a row mover; auto-lifting declined |
| **Do commutativity/associativity fire on operands that cannot be swapped?** | `docs/measurements/parameter-role-declined.md` | **Declined — 2 role-distinct of 118 binary ops across 17 corpora**; the first run's precision was a corpus artifact |
| **Is cross-type round-trip pairing worth acting on?** | `docs/measurements/cross-type-roundtrip-census.md` | **No action** — cross-type is 1.1% elsewhere vs 96% on the one corpus |
| **Does the TEMPLATE predict whether a refutation is a bug?** | `fixtures/planted-defect-arm/README.md` | **Measured NO.** Planted evidence has no base rate — it falsifies, it cannot estimate precision |
| **Can a veto for the idempotence miss class be built?** | `fixtures/domain-transfer-signal/` + `DomainTransferSignalExperimentTests` | **Measured NO**: recall 4/5, precision 4/12. Score a candidate veto against the laws that HELD |
| Superseded cycle plans | `docs/archive/v1.141 Calibration Plan.md` | Kept for the shrinking / replay-corpus rationale, not as a plan |
| **What is `monotonicity`'s largest blocker, and why does it hit the template's only TRUE laws?** | `docs/measurements/instance-method-shape-census.md` | **Both parts BUILT 2026-09-23 + `Deque`** — 12 true laws now run; 17 rows need per-carrier recipes. Below: the original diagnosis |
| **Does the throwing-codec shape have a population where the FINDINGS came from?** | `docs/measurements/throwing-codec-exhibit-subjects.md` | **Shape A: 1 new candidate across four exhibit subjects; Shape B: 0 real** — the template split stays unproposed |
| **Does the THROWING codec shape — the only one whose findings survived — have a population?** | `docs/measurements/throwing-codec-census.md` | **The manifest holds none of the exhibits, so it cannot answer**; 1 in 172 encoders in general libraries. No split proposed |
| **How many laws does the tool propose for code that is NOT IN THE BUILD?** | `docs/measurements/inactive-if-config-census.md` | **138 rows (2.4%) presumed inactive, 109 confirmed** — superseded by the built evaluator, next row |
| **Does evaluating `#if` stop laws about code that is not in the build?** | `docs/measurements/inactive-if-config.md` (scope: `docs/plans/inactive-if-config-scope.md`) | **Yes — built with `SwiftIfConfig`**: 279 rows removed, 10 relocated, the funnel unchanged |
| **What are `monotonicity`'s 339 subjects — at 20 corpora rather than 10?** | `docs/measurements/monotonicity-subject-census.md` | **The declined gate's premise is false at full scope — 26 of 339 rows are trig/hash**, concentrated in two corpora |
| **Does a `monotonicity` row ever reach a verdict — and does the reopened gate buy anything?** | `docs/measurements/monotonicity-verify-reach.md` | **BUILT as `applyNonMonotonicSubjectExclusion`, −26 rows, 0 laws gained.** No verdicts reached; the value is author-facing output |
| **The census universe went 17 → 20 — which figures moved?** | `docs/measurements/census-universe-17-to-20.md` | **Rows 5,544 → 5,892** — what did not move (`internalOrSPI` 1,392, four unwitnessed templates) is the useful half |
| **Which templates fire on NOTHING — re-taken at 17 corpora? And what SHAPE are the carriers?** | `docs/measurements/catalog-health-census.md` | **Carriers are 88% userDefined, 2% collection; four templates unwitnessed.** No trustworthy runtime catalogue — it is supplied |
| **Catalog health census — 15% of templates are DEAD** | `docs/measurements/swiftorg-property-test-study-findings.md` §10 | Read §10.5 before quoting the zero row: a census's zero cannot be read without its corpus list. Four remain **unwitnessed, not inert** |
| **The `[reference]` rows are the standing catalog backlog — now 15, not 49** | `docs/measurements/swiftorg-property-test-study-findings.md` §9 + §11 | The 49 was over-reported 3×. Success is measured in carriers reached *outside* the catalog |
| **The 9 known-properties TRAPS are a false-positive test set — run them FIRST** | `docs/measurements/swiftorg-property-test-study-findings.md` §8.9 | Executable false-law witnesses; found a real Strong-tier false positive in one run |
| **Working the swift.org gap list** — what the 19 `gap-with-witness` rows became | `docs/measurements/swiftorg-property-test-study-findings.md` §8 | Seven families, not 19 problems. Tally: 4 shipped, 1 declined, 2 open |
| **Is a METAMORPHIC law family worth building?** (the parse-tree catalog gap) | `Tests/SwiftInferCoreTests/TriviaInsensitivityExperimentTests.swift` | A test file whose header carries a standing verdict. Population is not the blocker — this is a *statability* gap |
| **The interaction-invariant taxonomy — settled, and its last two items were DECLINED not built** | `docs/design/Interaction Invariant Taxonomy.md` | Settled; its last two items were DECLINED, not built — one on measurement, one on evidence model |
| **Can a verify stub import a carrier its dependency declares?** | `docs/plans/dependency-carrier-imports-scope.md` | **Scoped, recommendation is DON'T** — population is 2 rows; fix the label instead. A degenerate `nil`-only domain is rejected outright |
| **Can the soundness arm's sandbox be built from what the toolchain has?** | `docs/measurements/sandbox-detector-mechanism.md` | **Cost premise false, recommendation survives** — `sandbox-exec` works; denied exec reports `ENOENT`, so attribution needs differential profiles |
| **Does the soundness-arm sandbox separate impure subjects from pure ones?** | `docs/measurements/soundness-arm-probe.md` | **Yes — 4 of 9 trip, 0 of 3 controls**, but the findings have no consumer (0 suggestions rest on them) |
| **Can the soundness arm reach its own frozen prediction?** | `docs/measurements/soundness-arm-reach.md` | **14 of 17 callable, 9 need nothing constructed** — reach is a precondition, not a result |
| **What do the backtest's blind spots cost this corpus?** | `docs/measurements/blindspot-base-rates.md` | **Bucket 1 zero; bucket 2 two rows, a smell not a bug** — the oracle is still wrong about hash order |
| **Does the purity oracle flag REAL historical purity bugs?** | `docs/measurements/purity-backtest.md` | **0 hits of 3, 0 false alarms** — blind to hash-order nondeterminism and instance `self` writes |
| **How often is a module-state mutation judged pure?** | `docs/measurements/module-state-base-rate.md` | **Home arm 0; cross-corpus 5 of 20,526, all in swiftlang-swift — read both** |
| **Does a `nonisolated` TYPE need its own isolation opt-out?** | `docs/measurements/nonisolated-type-declined.md` | **Declined on population** — 20 types, 5 suggestions, zero refutable |
| **Do `consuming` / `borrowing` carry purity evidence?** | `docs/measurements/ownership-premise-declined.md` | **Measured NO** — no verdict clause reads parameters, and the corpus declares none |
| **Should the toolchain infer `final`, ownership, and a `@Pure` negation?** | `docs/plans/declaration-claims-plan.md` | **`proposed`** — three families split by *can the tool be wrong*; `final` is gated on item 34 |
| **Error laws — which ones does a LINTER owe, and which do PROPERTY TESTS owe?** | `docs/ideas/error-law-instrument-split.md` | **`proposed`** — one-declaration syntax → linter; two declarations, a value or an execution → property test |
| Unbuilt proposals / design spikes | `docs/ideas/`, `docs/plans/*-scope.md`, `docs/plans/*-build-plan.md`, `docs/plans/production-assertion-discovery-signal.md` | The last one is an open scope the `*-scope.md` glob misses by filename |
| **Road-testing `scaffold-kit-suites` against swift.org** | `docs/plans/kit-suite-backtest-plan.md` | Backtest at **`<fix>^`, never `HEAD`** — these libraries are correct at HEAD, so all-green cannot be told from blind |
| **Is the kit-evidence surface real — and does it COMPILE?** | `docs/measurements/kit-scaffold-conversion.md` | **The generated suite now COMPILES and COMPLETES** — 240 errors were three render defects; the delegation-gate refinement was sized and declined |
| **Can a law over a method on a CONFIGURATION object be written — and what does it free?** | `docs/measurements/held-receiver-laws.md` | **BUILT (`HeldReceiver`)** — behaviour passes 151 → 222, but outside the teaching repos only +4; false laws now run instead of declining |
| **What is behind *cannot find in scope* — the second-largest set-aside cause?** | `docs/measurements/cannot-find-in-scope-decomposition.md` | **Mostly `private` again — 53 of 84**; ~9 stubs emitter-fixable, no large lever |
| **Where do BEHAVIOUR laws die — and is there a lever left?** | `docs/measurements/behaviour-law-funnel.md` | **Mostly correct declines and a long tail** — levers left are the catalogue and discrimination, not reach |
| **Do generated inputs reach a boundary bug?** | `docs/measurements/boundary-reach.md` | **7 of 13 unexercised boundary mutants sit under totality and can never be killed**; `[String]` elements now draw like Strings |
| **Which laws would have caught the bugs our laws MISSED?** | `docs/measurements/law-blind-mutants.md` | **No large family behind one law** — cheapest real law: read the ternary into `guard-domain` |
| **Does reading a TERNARY into guard-domain catch what it was built for?** | `docs/measurements/ternary-guard-domain.md` | **Yes — BUILT; both targeted law-blind mutants killed.** A characterisation law |
| **Does a REWRITE-POSTCONDITION law catch what idempotence and totality missed?** | `docs/measurements/rewrite-postcondition.md` | **Yes — BUILT; all three targeted mutants killed.** Claims single characters only, after a bounded-search rule proposed a false law |
| **Does a passing law notice a planted bug on subjects the catalogue NEVER met?** | `docs/measurements/mutation-check-new-subjects.md` (scope: `docs/plans/mutation-check-new-subjects-scope.md`) | **3 of 20 caught (15%)**; relational got one mutant — answered by the arithmetic run |
| **What did scoped aliases and operator stubs buy the funnel?** | `docs/measurements/corpus-funnel-census-2026-09-27.md` | **Compiles 938 → 940 — one repo, two stubs**; zero operator subjects in the corpus |
| **Do relational laws notice an ARITHMETIC bug?** | `docs/measurements/mutation-check-arithmetic.md` (scope: `docs/plans/mutation-check-arithmetic-scope.md`) | **Yes — 11 of 11 exercised arithmetic mutants killed**; reach is the other half |
| **Does generator REACH bound what a law can kill?** | `docs/measurements/mutation-reach.md` (scope: `docs/plans/mutation-reach-scope.md`) | **Yes — killed 35 → 58 on 97 frozen BigInt mutants**; kit 4.9.3; 0 of 943 corpus stubs changed |
| **How often does a derived generator draw only a CORNER of its type?** | `docs/measurements/generator-diversity.md` (scope: `docs/plans/generator-diversity-scope.md`) | **Once in 433 probes** — generator degeneracy is not a funnel lever |
| **What licenses a `round-trip` pairing?** | `docs/measurements/round-trip-pairing-evidence.md` (scope: `docs/plans/round-trip-pairing-evidence-scope.md`) | **96% rest on type symmetry alone; a require-a-name gate is CLOSED.** Found: bare-type-name pairing |
| **Does pairing by the type a name MEANS remove the bare-name collisions?** | `docs/measurements/bare-name-pairing.md` (scope: `docs/plans/bare-name-pairing-scope.md`) | **Yes, no true pairing lost** — round-trip rows 2,372 → 838 |
| **Would structural name rules name the round trips the vocabulary misses?** | `docs/measurements/inverse-name-vocabulary.md` (scope: `docs/plans/inverse-name-vocabulary-scope.md`) | **DECLINED — 60% precision against a 70% bar** |
| **Does a fresh subject turn up real defects — and what stops it?** | `docs/measurements/subject-harbeth.md` | **Harbeth: 8 failures, 0 real; a latent decode crash** found from a generator trap and posted upstream (Discussion #55) |
| **Does following a precondition one hop through a helper stop the generator traps?** | `docs/measurements/precondition-helper-hop.md` (scope: `docs/plans/precondition-helper-hop-scope.md`) | **Yes, on Harbeth only** — traps 7 → 2, funnel unchanged; wired into discover |
| **Do decoders skip the validation their own initializers make?** | `docs/measurements/decoder-bypass-census.md` (scope: `docs/plans/decoder-bypass-census-scope.md`) | **Only in Harbeth — 4 true of 38 flagged.** Not a template route |
| **Would a PRECISE delegation gate recover generators?** | `docs/measurements/delegation-gate-census.md` | **DECLINED** — 10 types in one corpus gain a generator; on Euclid it recovers 0 |
| **Does the docstring advisory's reference-oracle scaffold COMPILE?** | `docs/measurements/reference-oracle-scaffold-census.md` | **0 of 88 before; 66 of 67 printed now compile (SwiftAssist, seeded), 21 decline with a reason** — the 1 failure is an open resolver defect (`open-threads.md` row 78); swift-format's one printed fails only on Swift 5 mode. Harness: `scripts/reference_oracle_scaffold_census.py` |
| **Is budgeted truncation (fix 4: prefix, fits, maximal) a role with a population?** | `docs/measurements/budgeted-truncation-census.md` (scope: `docs/plans/budgeted-truncation-census-scope.md`) | **No — 20 STRICT sites, 15 on unsafe buffers or spans, 4 a test can draw, 3 of those in SwiftAssist itself.** Not a template route; a multibyte `String` arm has one subject |
| **Does "nil means the default" (fix 5: `f(p: nil) == f(p: D)` for `p ?? D`) have a population?** | `docs/measurements/nil-default-census.md` (scope: `docs/plans/nil-default-census-scope.md`) | **Yes, but thin — 64 HOLDS of 296 over 18 corpora (95% on re-read); about 14 a generated test reaches and draws today, ~34 with derived generators.** The law only catches edits, like the one that left Euclid's `cone` doc stale (though that code read MIXED before the edit) |
| **Did the emitted kit suites catch a real projection bug?** | `docs/measurements/kit-suite-backtest-arms-2-3.md` | **MISS** — but the laws are not structurally blind; it is a generator-domain failure, and this repo owns it. The baseline is not green |
| **Are the property tests a codebase ALREADY has any good?** | `docs/plans/existing-property-test-audit-scope.md` | Scoped, **not built**. The cheap lint version measures 0 hits and would ship a green bill of health |
| PropertyLawKit / PropertyLawMacro source of truth | The SwiftPropertyLaws repo, not this one | — |

The table indexes **docs**, with one deliberate exception: the metamorphic-law row points
at a *test file*, because its header carries a standing constraint on live design
decisions and no doc restates it.

**If you add a doc, add its row** — an unreachable doc is one nobody opens, and the last
sweep found eleven, two of which held standing constraints on live code. **Sweep
`docs/**/*.md`, not `docs/*.md`**: the non-descending glob is exactly how seven
`design-internal/` docs stayed invisible.

`scripts/` is study tooling, not product code — nothing in the shipped targets imports
it, and `make test` does not run it.

## Design decisions baked in (follow rather than re-litigate)

- **Conservative inference — high precision, low recall** (PRD §3.5). When in doubt, fewer suggestions.
- **Opt-in, human-reviewed output.** Never auto-applies, executes, or commits. CI mode emits warnings, not failures.
- **Avoid the Daikon trap.** Too many suggestions → raise thresholds, don't pile on filters.
- **Explainability is a first-class output.** Every suggestion ships "why suggested" *and* "why this might be wrong" (PRD §4.5).
- **Generator inference delegates to SwiftPropertyLaws.** Call `DerivationStrategist`; don't reimplement (PRD §11).
- **A refuter that fires first hides every refuter behind it.** Reading the code cannot tell you how many are queued up — measure after each fix.
- **State a gain as ROWS MOVED, never LAWS GAINED.** A decline-reason count is an upper bound on what a fix frees; the measured ratio is ~5:1 against.
- **Relaxed partial-exploration is allowed for `.tca` interaction verify.** **Guardrail:** every partial verdict MUST disclose the excluded set (`verified over M of N action types (excluded: …)`) in `detail` *and* render; the witness itself must be constructible.
- **A measured `bothPass` overrules the Finding-G `.possible` pin (cardinality / biconditional) ONLY at full action-space coverage.** A partial bothPass does not — cardinality's failure mode lives in exactly the action types relaxed exploration excludes. Static score alone never overrules.
- **Purity gates must not relax to reach a target.** Removing the `throws` gate once re-admitted `Process`/`Pipe`/`FileHandle`/SQLite at once. A propagated `try` into a *dependency* is out of reach by design.
- **A tool may not grade its own homework.** On a scored road test, anything the tools find that the frozen answer key missed is recorded **unscored** — never folded into the key.
- **Score refutability, not suggestion count.** `f(x) == f(x)` passes "did discovery return > 0" and cannot fail. Count laws some plausible implementation would be *rejected* by.
- **`measured-bothPass` means "no counterexample in the generated domain," not "the property holds."** Any property whose failure needs two generated values to **collide** — merge tie-breaks, cache-key collisions, dedup, key injectivity — is invisible to a generator drawing from a realistic domain, as is any branch keyed on realistic *content*. When a candidate law is collision-dependent, narrow the generator's alphabet deliberately and say so in a comment.
- **The verifier's kit pin must equal this package's own** (`VerifierWorkdir.swiftPropertyLawsRequirement`, guarded). Disjoint ranges make *every* entry report `measured-error: build-failed`, which reads as an architectural limitation rather than a broken manifest. Never write the version as a literal in a mode arm.

## Build & test

- **This package needs the swift.org Swift compiler toolchain, not Xcode's.**
  (*Toolchain* elsewhere in this file means the five-package PBT toolchain — every use in
  this section means the Swift compiler.) Under Xcode's
  (`swiftlang-6.3.3.1.3`) every source file compiles and then the post-build plugin stage —
  `Applying swift-infer`, `Applying soundness-probe` — fails with
  `Internal Error: DecodingError.dataCorrupted … Corrupted JSON` followed by `error: fatalError`.
  Under swift.org's `swift-6.3.3-RELEASE` it builds in ~55s. The two report the same version
  number; `swiftlang-` in `swift --version` is the tell. ⚠ **The `Corrupted JSON` line ALONE is
  NOT the tell — the plugin stage ABORTING is.** Measured 2026-09-17 on the swift.org toolchain: a
  clean `make test` printed that exact `Internal Error: DecodingError.dataCorrupted … Corrupted
  JSON` line **23 times**, interleaved with `Compiling SwiftInferCLITests`, with no `fatalError`
  after it — and all ten stages went green. ⚠ **The very next full run, 2026-09-18 on the same
  toolchain, printed it ZERO times and was equally green**, so the message is intermittent and
  tracks nothing about the outcome. A session that greps for it and stops will misdiagnose a
  healthy run.

  The Makefile handles this: `SWIFT` defaults to
  `~/Library/Developer/Toolchains/swift-6.3.3-RELEASE.xctoolchain/usr/bin/swift` when present, so
  `make test` works regardless of what `swift` resolves to. Override with `make test SWIFT=…`.
  **It also puts that toolchain's directory on `PATH`**, because choosing `SWIFT` only decides what
  runs the tests — `TestTargetScope` and two others shell out to `swift package dump-package`
  through `DrainedProcess.standardOutputViaEnv`, which resolves the name on PATH on purpose.

  **`.swift-version` pins the toolchain for swiftly users**, so a bare `swift` in this repo is the
  swift.org one and Xcode's stays the default everywhere else — which is what lets SwiftMarkdownWiki
  keep the opposite requirement. Without one of those two, a bare `swift test` fails if your
  `swift` is Xcode's.

  ⚠ **The failure does not look like a toolchain problem.** Measured 2026-09-16: PATH's `swift`
  resolved the SDK to `/Library/Developer/CommandLineTools` (27.0, built with Swift 6.4) and could
  not compile ANY `Package.swift` — *"this SDK is not supported by the compiler"*. `dump-package`
  failed, no test target was found, and `GeneratedStubDestinationTests` went red with 8 issues —
  a suite whose whole job is catching #414, stubs written where no target builds them. **It reads
  as the defect it guards against.**

  This is the opposite constraint to SwiftMarkdownWiki, which needs Xcode's toolchain because the
  swift.org one cannot see SwiftUI cross-import overlay types. No single toolchain builds both.
- `swift package clean && swift test` on session start — with the toolchain caveat above.
- **Use the Makefile** — `make test-fast` (regex-skip fast path; the Makefile says ~35s and runs on 2026-09-23 took ~50–70s) · `make test` (fast suite + sequential subprocess batches, fail-fast) · `make batch1`…`batch8` · `make perf` · `make clean-temp` · `make help`. Prefer `make test` over a bare `swift test`: the batches bound peak temp-disk and avoid §13 perf-budget contention flakes.
- A killed-mid-run subprocess suite skips its cleanup `defer` and can leak tens of GB to `$TMPDIR` — that is what `make clean-temp` is for. It also sweeps `.swiftinfer/verify-workdir/`, which is gitignored and accumulates silently.
- Fast path is `swift test --skip 'MeasuredTests|MeasuredExecutionTests|VerifyPipeline'` — a **regex against the test ID**, so it is self-maintaining. **Don't enumerate suite names**; the old per-name list missed four suites and the "fast" command ran ~90 min.
- **A new `*MeasuredTests` suite must also be added to a Makefile BATCH by hand**, or `make test` silently skips it — four recurrences, nine suites orphaned at once in the worst. `SubprocessBatchCoverageTests` now reads `SUBPROCESS_RE` and the `BATCH*` values **out of the Makefile** and asserts **both** directions: matched-but-unbatched never runs, `.subprocess`-but-unmatched runs inside the ~6s fast path. Cheap subprocess suites are allowlisted rather than batched, and the allowlist has its own staleness test.
- **The §13 perf suites run alone, via `make perf`** — skipped by the fast path (`PERF_RE`), serial, own target. They assert wall-clock and peak-RSS budgets, so sharing a box with ~4,300 other tests measures the machine. Keep the `*PerformanceTests` suffix and both are auto-covered.
- SwiftLint config at `.swiftlint.yml`; `swiftlint lint --quiet --strict` must stay at **zero**, and `make test-fast` gates on it.
- **`orphaned_doc_comment` is on, and the comment order it wants is load-bearing**: `swiftprojectlint:disable:next` directive, then any maintainer note, then the `///` block on its declaration. Do not reorder. **Verify a suppression by removing it and watching the rule fire** — five current `parallel-enum-shape` directives suppress nothing and are kept only as guards.
- **`MemoryCeilingPerformanceTests` flakes under full-suite parallel load** — ~150 MB in isolation against an 800 MB budget, ~4800 MB when it trips. It is a process-wide peak-RSS reading. Rerun before blaming your edit.
