# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository. **This file is a pointer-only index.** Per-cycle narratives live in `git log`, in `docs/archive/claude-md-narrative-history.md`, and in the road-test / design docs listed below. (This line used to send readers to `docs/calibration-cycle-N-findings.md`; those files no longer exist — they were folded into that archive, as the table below already said.) The pre-2026-07-26 changelog-style CLAUDE.md is archived verbatim there too — read it only when you need the story behind a specific shipped decision.

## What this repo is

**SwiftInferProperties** (`swift-infer`) — type-directed property inference for Swift. Reads code, proposes properties, **never applies anything**. Surfaces idempotence, round-trip pairs, algebraic structure (semigroup → ring, semilattice), and the five *interaction*-invariant families over reducer / MVVM carriers. All output is human-reviewed; nothing auto-executes.

One-way downstream in the five-package toolchain:

```
SwiftProjectLint ──▶ SwiftInferProperties ──▶ SwiftPropertyLaws ──▶ SwiftIdempotency
 lint + pbt-seeds      discover + stubs         run the laws         retry-safety
        ▲                      ▲
        └──── SwiftEffectInference (purity oracle; no CLI, runs inside both) ────┘
```

Sibling checkouts expected at `../SwiftPropertyLaws` and `../SwiftEffectInference`. `Package.swift` pins SwiftPropertyLaws `from: "2.5.0"` (verify path uses the opt-in `PropertyLawComplex` product; the main `PropertyLawKit` line keeps a zero `swift-numerics` footprint) and SwiftEffectInference by revision. Deferred kit-side: `Ring` (Numeric stays canonical, PRD §5.4 row 5), `CommutativeGroup`, `Group acting on T`.

## Current state

**v1.146.0.** Two disjoint surfaces, both discovered → surfaced → verified → promoted end to end:

- **Algebraic** — pure-function laws from signatures, cross-function pairs, and lifted test bodies. v1 corpus (`fixtures/cycle27-surface/`) is **100% measured** (53/53, cycle 151 — epic complete; zero false positives, zero coverage-pending). Further movement needs *new* public algebraic API, not filters or recipes.
- **Interaction** — five families (idempotence / cardinality / biconditional / referential-integrity / conservation) over reducer carriers (TCA, Elm, ReSwift, Mobius, Workflow, generic) and SwiftUI MVVM carriers. All five have a demonstrated measured-verify path; idempotence promotes `.likely → .verified` on measured execution, the rest default `.possible` behind `--include-possible`.

Consumers over the SemanticIndex, split by audience and trust bar: `query` (author, all tiers, raw rows) · `insights` (author, inferred cross-type structure) · `docc` (reader, **verified-only**). Async is admitted only via the `@ClockDeterministic` claim — bare `async` keeps a clean rejection that says how to make the claim.

Suites green at ~4,400 tests. **Flake note:** the long measured/calibration suites occasionally drop one issue under load — rerun before diagnosing.

## Where to look

| Question | File |
|---|---|
| Product scope, milestones, success criteria | `docs/SwiftInferProperties PRD v1.0.md` (canonical) + ` v2.0.md` |
| Measured-verify design (the whole v2 interaction story) | `docs/measured-verify-architecture.md` — **read first** |
| **Why does `verify` decline so much?** | `docs/verify-carrier-reach-census.md` — the answer is **not** carrier support. Carrier is ~4% of declines and `String` was always supported; `supportedCarriers` gates Route 1 only. **Template reach is 65%**, half of it `predicate`. Also: the census's OK bucket is an upper bound (a stub still has to compile), and a census that forgets to thread `allShapes` invents a carrier problem two-thirds of which is the harness |
| Full historical changelog (every shipped cycle, verbatim) | `docs/archive/claude-md-narrative-history.md` |
| Per-cycle change story | `git log` (the per-cycle findings docs were folded into the archive above) |
| Road tests (third-party subjects) | `docs/roadtest-*.md` — SwiftProjectLint (the first *scored* one, frozen answer key), SwiftLintRuleStudio (out-of-catalog diagnosis + two retracted closures), MacCloud server / macOS client |
| **Self-dogfood** (the tools pointed at this repo) | `docs/roadtest-self-dogfood.md` — the `merge` commutativity refutation, the Finding-G gate suite, and the mutation corpus behind them |
| Where the catalog stops on **parsers** | `docs/parsing-catalog-gap.md` — the swift-syntax survey. **Ledger closed:** 7/7 defects shipped, holes 8/9/12 built (retract, differential/oracle, recursive generation), 10/11 probed and rejected. Still live *after* the ledger: the measured generator weaknesses (the `0 ..< T.max` idiom, edge values never drawn under a quantifier), "which templates are under-appreciated" as an open question, the `unsafe`/`unchecked` veto, and the SIGBUS stack-depth trap for the next corpus-scanning test |
| Historical **backtests** — does the catalog fire on code written before it? | `docs/backtest-apple-libraries.md` (Apple / Swift libraries, 2026-07-18) · `docs/backtest-codable-roundtrip-pressuretest.md` — the pressure test whose recommendation became the shipped `codable-round-trip` template |
| Would a **conformance-keyed** template earn its keep? | `fixtures/equatable-signal/README.md` — the measured answer for `Equatable` (2026-07-29; swift-numerics 2 conformances, swift-collections 49). **No:** conformance does not predict refutability, the `==` *body shape* does. When `==` is a **projection** of the stored fields it is still an equivalence relation however wrong it is, so the Equatable laws are *structurally* blind — 3 of 3 real projection bugs (`OrderedSet` order, `BitArray` padding, `Deque` head rotation) pass 4/4 laws and are caught by a **model law** (`left == right ⟺ model(left) == model(right)`) at trial ≤3. Propose the model law, not the Equatable laws, for projections. 18 arms, run by hand, not in any batch |
| **Five-repo adoption loop** — is the toolchain usable end to end? | `docs/PBT_TOOLCHAIN_FIX_PLAN.md` (2.7k lines) — scored against `MacCloud_client_iOS` @ `f3dbb6f` vs the `pbt-road-test-reference` answer key. **Caveat: it opens by naming a companion `PBT_ROAD_TEST.md` that does not exist in this repo** |
| Live follow-up trackers — what shipped, what is still open | `docs/tca-determinism-followups.md` — items 1/3/4 built, item 2 at 4 of 5 slices, only slice 3c (child recursion) deferred |
| Design records for **shipped** work | `docs/docstring-corroboration.md` (→ `DocstringPropertyCorroborator`) · `stateful-role-discoverer-design.md` (→ `StatefulRole`) · `tca-identified-action-slice3-design.md` (→ slice 3b) · `observable-carrier-m1prime-verify-milestone.md` |
| Investigations with a recorded **decision not to build** | `docs/bridge2-materialisation-spike.md` (fork B, 2026-07-18 — no code change) · `docs/rule-visitor-carrier-scoping.md` (recognition only; the determinism invariant is deliberately **not** emitted, and `RuleVisitorDiscoverer.swift:28` cites this decision — do not "fix" it by adding one) |
| Command docs | `docs/report-command.md`, `insights-command.md`, `docc-generation.md`, `prove-then-show.md`, `known-properties.md`, `stdlib-anchor.md`, `interaction-semantic-index.md` |
| End-user docs | `docs/user/{tutorial,guide,reference}.md` |
| Dogfood findings (own + sibling repos) | `docs/dogfood-new-templates-findings.md` |
| **swift.org property-style-test study** | plan: `docs/swiftorg-property-test-study-scope.md` · record: `docs/swiftorg-property-test-study-findings.md` · sampler: `scripts/swiftorg_sample.py` (seeded + stratified, so "sampled not cherry-picked" is checkable) · **frozen Q2 answer key**: `fixtures/swiftorg-study/q2-answer-key.json` + `scripts/swiftorg_answer_key.py`, committed BEFORE any `discover` run so the tool cannot grade its own homework. Corpus pinned at `swift` `408632e5`, and **every number carries its SHA** |
| Superseded cycle plans | `docs/v1.141 Calibration Plan.md` — the repo is v1.146; kept for the shrinking / replay-corpus rationale, not as a plan |
| Unbuilt proposals / design spikes | `docs/ideas/`, `docs/*-scope.md`, `docs/*-build-plan.md`, and `docs/production-assertion-discovery-signal.md` (an open scope with a cost estimate and no decision — the `*-scope.md` glob misses it by filename) |
| PropertyLawKit / PropertyLawMacro source of truth | The SwiftPropertyLaws repo, not this one |

Every `docs/*.md` is reachable from a row above; that was swept on 2026-07-29 and
found eleven files no row reached. If you add a doc, add its row — an unreachable
doc is one nobody opens, and two of the eleven turned out to hold **standing
constraints on live code**. (It earned itself immediately: the study findings doc added
2026-07-30 would have been the twelfth.)

`scripts/` is study tooling, not product code — nothing in the shipped targets imports it,
and `make test` does not run it.

## Design decisions baked in (follow rather than re-litigate)

- **Conservative inference — high precision, low recall** (PRD §3.5). When in doubt, fewer suggestions.
- **Opt-in, human-reviewed output.** Never auto-applies, executes, or commits. CI mode emits warnings, not failures.
- **Avoid the Daikon trap.** Too many suggestions → raise thresholds, don't pile on filters.
- **Explainability is a first-class output.** Every suggestion ships "why suggested" *and* "why this might be wrong" (PRD §4.5).
- **Generator inference delegates to SwiftPropertyLaws.** Call `DerivationStrategist`; don't reimplement (PRD §11).
- **A refuter that fires first hides every refuter behind it.** Reading the code cannot tell you how many are queued up — measure after each fix. (Three passes each named "the remaining blocker" for `serialize` and each was wrong; see `docs/roadtest-swiftlintrulestudio.md`.)
- **Relaxed partial-exploration is allowed for `.tca` interaction verify.** A `measured-bothPass` may be established over the constructible-action subset, skipping non-derivable composition cases. **Guardrail:** every partial verdict MUST disclose the excluded set (`verified over M of N action types (excluded: …)`) in `detail` *and* render; the witness itself must be constructible.
- **A measured `bothPass` overrules the Finding-G `.possible` pin (cardinality / biconditional) ONLY at full action-space coverage.** A partial bothPass does not — cardinality's failure mode lives in exactly the action types relaxed exploration excludes. Static score alone never overrules; the carve-out is measured-evidence-only in `InteractionVerifyEvidenceScoring`, not a change to `tier(forScore:)`.
- **Purity gates must not relax to reach a target.** Removing the `throws` gate once re-admitted `Process`/`Pipe`/`FileHandle`/SQLite at once, with a subprocess-spawning function judged pure. A propagated `try` into a *dependency* is out of reach by design.
- **A tool may not grade its own homework.** On a scored road test, anything the tools find that the frozen answer key missed is recorded **unscored** — never folded into the key.
- **Score refutability, not suggestion count.** `f(x) == f(x)` passes "did discovery return > 0" and cannot fail. Count laws that some plausible implementation would be *rejected* by.
- **`measured-bothPass` means "no counterexample in the generated domain," not "the property holds."** A derived generator is tuned for coverage of the *type* and is silently mistuned for coverage of the *law*. Any property whose failure needs two generated values to **collide** — merge tie-breaks, cache-key collisions, dedup, key injectivity — is invisible to a generator drawing keys from a realistic domain. The self-dogfood road test measured this: `Decisions.merge` commutativity is **false**, and verify reported `bothPass` at 100 trials; narrowing only the identity/timestamp alphabets made the same stub fail at trial 5. When a candidate law is collision-dependent, narrow the generator's alphabet deliberately and say so in a comment.
- **The verifier's kit pin must equal this package's own.** `VerifierWorkdir.swiftPropertyLawsRequirement`, guarded by `VerifierWorkdirKitPinTests`. A `--corpus-module` survey resolves both in one graph; disjoint major ranges make *every* entry report `measured-error: build-failed`, which reads as an architectural limitation rather than a broken manifest. Never write the version as a literal in a mode arm — that is exactly how it drifted a full major version.

## Build & test

- `swift package clean && swift test` on session start.
- **Use the Makefile** — `make test-fast` (regex-skip fast path, ~6s) · `make test` (fast suite + sequential subprocess batches, fail-fast) · `make batch1`…`batch7` · `make clean-temp` · `make help`. Prefer `make test` over a bare `swift test`: the batches bound peak temp-disk and avoid §13 perf-budget contention flakes. A killed-mid-run subprocess suite skips its cleanup `defer` and can leak tens of GB of TCA build workdirs to `$TMPDIR` — that's what `make clean-temp` is for. It also sweeps `.swiftinfer/verify-workdir/`, where `verify --all-from-index` puts one full SwiftPM workdir *per suggestion* (a survey of this repo's own 85-entry index left **3.4 GB** there; it's gitignored, so it accumulates silently).
- Fast path is `swift test --skip 'MeasuredTests|MeasuredExecutionTests|VerifyPipeline'`. `--skip` takes a **regex against the test ID**, so that one alternation covers every `.tags(.subprocess)` suite and is self-maintaining. **Don't enumerate suite names** — the old per-name list silently missed four `VerifyPipeline*` suites and the "fast" command ran for ~90 min. A new subprocess suite is auto-covered only if named `*MeasuredTests` or `VerifyPipeline*`; otherwise widen the regex.
- **A new `*MeasuredTests` suite must also be added to a Makefile BATCH by hand**, or `make test` silently skips it.
- **The §13 perf suites run alone, via `make perf`** — skipped by the fast path (`PERF_RE`) and run serially (`--no-parallel`) in their own target. They assert wall-clock and peak-RSS budgets, so sharing a box with ~4,300 other tests measures the machine: one loaded run read 3.65s against a 2s budget and 1008 MB against an 800 MB one, with all five passing at 6.1s / 167 MB immediately afterwards in isolation. Same orphaning trap as the batches — a suite matched by `PERF_RE` that isn't run by `perf` is never run at all; keeping the `*PerformanceTests` suffix keeps it auto-covered by both.
- SwiftLint config at `.swiftlint.yml`. **`make test-fast` runs a lint gate first and it is green** (swept 2026-07-27, `d95d5d7`; the backlog peaked at 49 `--strict` errors). Keep it that way — `swiftlint lint --quiet --strict` must stay at zero.
- **`orphaned_doc_comment` is on, and the comment order it wants is load-bearing.** The convention is `swiftprojectlint:disable:next` directive, then any maintainer note, then the `///` block sitting directly on its declaration. Do not reorder these: SwiftProjectLint's `disable:next` skips comments to reach the declaration only as of SwiftProjectLint `6c88715` — before that it broke 14 suppressions silently, with both linters reporting clean. **Verify a suppression by removing it and watching the rule fire** (strip all 14 → `Parallel List Drift` ×8); the five `parallel-enum-shape` directives currently suppress nothing and are kept only as guards.
- **`MemoryCeilingPerformanceTests` §13 row 4 flakes under full-suite parallel load** — ~150 MB in isolation against an 800 MB budget, ~4800 MB when it trips, at the same rate with an unrelated change stashed. It is a process-wide peak-RSS reading, so it reflects whatever swift-testing scheduled alongside it. Rerun before blaming your edit.
