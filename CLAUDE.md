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

**v1.149.0.** Two disjoint surfaces, both discovered → surfaced → verified → promoted end
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

Suites green at **5,620 tests — 5,508 fast + 112 across `perf` and the eight batches**
(last full `make test` verified green 2026-08-15 at `4fac986`, ~22 min, when it read
5,493 + 83; both halves re-counted 2026-08-17 by running `test-fast` and `batch2`
directly — the other batches and `perf` are unchanged arithmetic, not a fresh full run.
The batch half moved 92 → 112 as the four purity censuses joined batch2;
the fast half did not move, which is the regex doing its job).
**Quote both halves, never the total alone**: a new `*MeasuredTests` suite that never
reached a batch shows up here as the fast count rising while the batch count stands
still. **Flake note:** the long measured/calibration suites occasionally drop one issue
under load — rerun before diagnosing.

**The `SEICrossRepoPinTests` red is CLEARED (2026-08-17).** Both repos now pin SEI
`c66fceb` — the joint bump that carried the default-argument purity refuter
(SwiftEffectInference #13) out to its two consumers, which is what "a deliberate joint
act" is for. Keep them equal: disjoint pins mean the linter and the inference engine are
not consulting one purity oracle, and that guard is the only thing that can say so.

## Where to look

One line per row. **The full annotation for every row is in
`docs/reference/index-annotations.md`** — go there before quoting a number or re-opening a
decline, because the hook states the verdict and the annotation states what was measured.

| Question | File | Hook |
|---|---|---|
| **Why is this file short, and where did the reasoning go?** | `docs/reference/index-annotations.md` | The long form of every row below, verbatim. Moved out 2026-08-17 so the index stops costing 158 KB of context per session |
| **What does the package build but never call?** | `make dead-code` (`scripts/dead_public_api.py`) | Reachability at **file** granularity; `test-only` is the verdict that matters. Deliberately does not gate the build |
| **How is `docs/` organised, and what does a doc's status mean?** | `docs/README.md` | Two independent axes: directory = what a doc *is*, status header = where it is in its life |
| **What does this word mean?** (template, carrier, decline, composer-supported, reach, latent, Daikon trap…) | `docs/design-internal/glossary.md` | Vocabulary keyed to the code that owns it. Read the `Daikon trap` entry before proposing a filter |
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
| **Is an unrecognised callee safe to wave through?** | `docs/measurements/purity-unrecognised-callee-census.md` | **Measured: no — a subprocess spawn is judged `.pure`.** But the allowlist fix costs 65% of `.pure`; the 18 real rows are one hop inside the package. §5's default-argument hole is FIXED — 13 false `pure` advisories retracted |
| **Is `PurityVerdict.refuted` evidence, or the analyzer reporting its own blindness?** | `docs/measurements/purity-refuted-bucket-census.md` | **Measured 54% ignorance, then 45% hours later** — check which SEI pin a figure belongs to. Rankable ceiling **135, not 152** |
| **Would a blocking-callee index earn its keep?** | `docs/measurements/purity-blocking-callee-census.md` | **Measured NO, twice over.** 13–31 rows of leverage behind a 135-row population, all landing in a tier nothing reads. The index's top entry is `String(contentsOf:)` |
| **Does purity propagate through a higher-order call?** | `docs/measurements/purity-higher-order-census.md` | **Premise measured FALSE** — chains sail through, 9 of 10 shapes `.pure`. The real gap is an over-claim, 27 rows, base rate unmeasurable |
| Full historical changelog (every shipped cycle, verbatim) | `docs/archive/claude-md-narrative-history.md` | The rest of `docs/archive/` is shipped-then-archived design records. Archived ≠ superseded — read for reasoning, never for counts |
| Per-cycle change story | `git log` | The per-cycle findings docs were folded into the archive above |
| Road tests (third-party subjects) | `docs/measurements/roadtest-*.md` | SwiftProjectLint (first scored, frozen key), SwiftLintRuleStudio, MacCloud server / client |
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
| **Is the hand-written `OrderedSet` generator any good?** | `fixtures/ordered-set-generator/README.md` | 101 reachable values, 3 mutants exhaustively unreachable. Widening was the wrong lever for the order projection — a pair sampler is |
| **Should `inverse-pair` and `identity-element` get composers?** | `docs/plans/inverse-pair-identity-element-composers-scope.md` | **Measured NO, including via the projection route.** Shipped `UnverifiableCause.carrierNotEquatable` instead |
| **What does the toolchain reach on a subject it has NEVER met?** | `docs/measurements/exploratory-swiftformat-grdb.md` | 87/159 laws on the home corpus against 1/129 and 5/307. Five instrument defects; state gains as **rows moved**, never laws gained |
| **What IS the measurement corpus, and can a run be reproduced?** | `fixtures/corpora/manifest.json` | 21 subjects, four kinds, six apparatuses. The pinned revision belongs to the RUN; cannot-check is a third state |
| **Can two survey runs be compared at ROW level?** | `fixtures/verify-runs/README.md` | They can now; for four runs they could not. A change of decline **cause** is reported as loudly as a bucket change |
| **How many laws actually RUN, across all templates?** | `fixtures/whole-corpus-survey/` | 139 of 281 execute. **Read the tier cut, not the total** — all 4 real bugs are `Likely`, all 5 `Possible` refutations are false laws |
| **Does the TEMPLATE predict whether a refutation is a bug?** | `fixtures/planted-defect-arm/README.md` | **Measured NO.** Planted evidence has no base rate — it falsifies, it cannot estimate precision |
| **Can a veto for the idempotence miss class be built?** | `fixtures/domain-transfer-signal/` + `DomainTransferSignalExperimentTests` | **Measured NO**: recall 4/5, precision 4/12. Score a candidate veto against the laws that HELD |
| Superseded cycle plans | `docs/archive/v1.141 Calibration Plan.md` | Kept for the shrinking / replay-corpus rationale, not as a plan |
| **Catalog health census — 15% of templates are DEAD** | `docs/measurements/swiftorg-property-test-study-findings.md` §10 | Read §10.5 before quoting the zero row: a census's zero cannot be read without its corpus list. Four remain **unwitnessed, not inert** |
| **The `[reference]` rows are the standing catalog backlog — now 15, not 49** | `docs/measurements/swiftorg-property-test-study-findings.md` §9 + §11 | The 49 was over-reported 3×. Success is measured in carriers reached *outside* the catalog |
| **The 9 known-properties TRAPS are a false-positive test set — run them FIRST** | `docs/measurements/swiftorg-property-test-study-findings.md` §8.9 | Executable false-law witnesses; found a real Strong-tier false positive in one run |
| **Working the swift.org gap list** — what the 19 `gap-with-witness` rows became | `docs/measurements/swiftorg-property-test-study-findings.md` §8 | Seven families, not 19 problems. Tally: 4 shipped, 1 declined, 2 open |
| **Is a METAMORPHIC law family worth building?** (the parse-tree catalog gap) | `Tests/SwiftInferCoreTests/TriviaInsensitivityExperimentTests.swift` | A test file whose header carries a standing verdict. Population is not the blocker — this is a *statability* gap |
| **The interaction-invariant taxonomy — settled, and its last two items were DECLINED not built** | `docs/design/Interaction Invariant Taxonomy.md` | Settled; its last two items were DECLINED, not built — one on measurement, one on evidence model |
| **Can a verify stub import a carrier its dependency declares?** | `docs/plans/dependency-carrier-imports-scope.md` | **Scoped, recommendation is DON'T** — population is 2 rows; fix the label instead. A degenerate `nil`-only domain is rejected outright |
| Unbuilt proposals / design spikes | `docs/ideas/`, `docs/plans/*-scope.md`, `docs/plans/*-build-plan.md`, `docs/plans/production-assertion-discovery-signal.md` | The last one is an open scope the `*-scope.md` glob misses by filename |
| **Road-testing `scaffold-kit-suites` against swift.org** | `docs/plans/kit-suite-backtest-plan.md` | Backtest at **`<fix>^`, never `HEAD`** — these libraries are correct at HEAD, so all-green cannot be told from blind |
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

- `swift package clean && swift test` on session start.
- **Use the Makefile** — `make test-fast` (regex-skip fast path, ~6s) · `make test` (fast suite + sequential subprocess batches, fail-fast) · `make batch1`…`batch8` · `make perf` · `make clean-temp` · `make help`. Prefer `make test` over a bare `swift test`: the batches bound peak temp-disk and avoid §13 perf-budget contention flakes.
- A killed-mid-run subprocess suite skips its cleanup `defer` and can leak tens of GB to `$TMPDIR` — that is what `make clean-temp` is for. It also sweeps `.swiftinfer/verify-workdir/`, which is gitignored and accumulates silently.
- Fast path is `swift test --skip 'MeasuredTests|MeasuredExecutionTests|VerifyPipeline'` — a **regex against the test ID**, so it is self-maintaining. **Don't enumerate suite names**; the old per-name list missed four suites and the "fast" command ran ~90 min.
- **A new `*MeasuredTests` suite must also be added to a Makefile BATCH by hand**, or `make test` silently skips it — four recurrences, nine suites orphaned at once in the worst. `SubprocessBatchCoverageTests` now reads `SUBPROCESS_RE` and the `BATCH*` values **out of the Makefile** and asserts **both** directions: matched-but-unbatched never runs, `.subprocess`-but-unmatched runs inside the ~6s fast path. Cheap subprocess suites are allowlisted rather than batched, and the allowlist has its own staleness test.
- **The §13 perf suites run alone, via `make perf`** — skipped by the fast path (`PERF_RE`), serial, own target. They assert wall-clock and peak-RSS budgets, so sharing a box with ~4,300 other tests measures the machine. Keep the `*PerformanceTests` suffix and both are auto-covered.
- SwiftLint config at `.swiftlint.yml`; `swiftlint lint --quiet --strict` must stay at **zero**, and `make test-fast` gates on it.
- **`orphaned_doc_comment` is on, and the comment order it wants is load-bearing**: `swiftprojectlint:disable:next` directive, then any maintainer note, then the `///` block on its declaration. Do not reorder. **Verify a suppression by removing it and watching the rule fire** — five current `parallel-enum-shape` directives suppress nothing and are kept only as guards.
- **`MemoryCeilingPerformanceTests` flakes under full-suite parallel load** — ~150 MB in isolation against an 800 MB budget, ~4800 MB when it trips. It is a process-wide peak-RSS reading. Rerun before blaming your edit.
