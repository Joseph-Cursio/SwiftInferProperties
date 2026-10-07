# Construction facts, wired in — what the table moved

> **Status:** `measured` · **As of:** 2026-10-07

**The third step in this repo that moves purity verdicts, and the first by configuration rather
than by an SEI pin bump.** SEI `f2ea8d6` already shipped `ConstructionFacts` — a table of what
constructing each of a package's types runs — and an inferrer that consults it
(`PurityInferrer(constructionFacts:)`). This repo built neither: `SoundPurity` made a fresh
unconfigured `PurityInferrer()` on every call, so `func make() -> Item { Item() }` read as
`.pure` while `Item` declared `let id = UUID()` in another target. That is the shape of the
motivating defect — SwiftLintRuleStudio's `generateRecommendations` and `analyze` were advised
`/// @lint.effect pure`, and they mint a `UUID` per recommendation and per report.

Re-derivable at any time — `make batch2` runs both arms:

- `PurityRefutationCensusMeasuredTests` → *census — what the construction table moves on
  Sources/, on the same trees* (this repo, configured against `.unconfigured` over one parse);
- `PackagePurityJoinMeasuredTests` → *census — rows the construction table moves, per manifest
  corpus* (every manifest scan root, `withoutConstructionFacts` against the root's purity, one
  parse, join applied).

> **Revised 2026-10-06, after an adversarial review of the wiring** — read
> [*The review's fixes*](#the-reviews-fixes--what-each-moved) before quoting a figure. The universe
> rule gained the shared spec's two amendments (nested packages bounded by what the root compiles,
> the root found from the path as given, smallest-path dedup, strict UTF-8, a pinned build order),
> and every table below was re-taken at `5a491298` (SEI `9d0bf6d`) and again, rebased onto
> `a09c5d56`, at `e06ec8e9` (SEI `64a905c`), the two agreeing to the digit. **The table's effect did
> not move**: the same 3 refuted types and 0 flips here, the same 266 rows over 21 roots, row for row.

> **Revised again 2026-10-07, after a joint follow-up review of both consumers** — read
> [*The follow-up review's fixes*](#the-follow-up-reviews-fixes--amendments-3-and-3b). The shared
> spec gained amendments F–R (what a manifest is, an Xcode project beside it, dependency paths by
> value and canonical location, the closure read by path, judged packages, version-specific
> manifests, target paths, the scanned path's letter case, `UF_HIDDEN`), and the nested-package
> closure is now one text in both repos. Re-taken at `7fbc7baa` (SEI `64a905c`): **the table's
> effect did not move** — 3 refuted types and 0 flips here, the same 266 rows over 21 roots, every
> moved row identical. Two corpus universes grew under the new rules and moved no row.

> **Revised a third time 2026-10-07, after the final review of PR #635** — read
> [*The final review's fixes*](#the-final-reviews-fixes--two-regressions-and-amendment-4). Two
> performance regressions fixed (`covers` and the walk into `Tests/`), and amendment 4: a manifest
> is what SwiftPM loads (S), a target path reaches the nested packages under it (T). Re-taken at
> `a4e68820`: **nothing moved** — the same 3 refuted types, 0 flips, 266 rows over 21 roots, every
> moved row identical; this repo's universe is 746 (one new source file).

---

## What was built

- **`SoundPurity` is a value**, holding one `PurityInferrer` configured with one table. The
  unconfigured oracle is `internal`; `PurityConfigurationInventoryTests` reads `Sources/` and
  fails if a `PurityInferrer` is built anywhere but `SoundPurity`, a table anywhere but
  `PackagePurity`, or `.unconfigured` is named in production.
- **`PackagePurity`** — one project's oracle, built once per scan from its **construction
  universe** and owning the parsed trees. A file in the universe is judged on the very tree the
  facts were built from: SEI types an assignment by node identity, so a re-parse answers more
  refutingly (`scanJudgesOnTheFactsOwnNodes` pins it).
- **`ConstructionUniverse`** — the cross-repo rule, implemented with the same names in
  SwiftProjectLint: root = nearest ancestor of the scanned directory holding a **manifest** (a
  `Package.swift` SwiftPM would load as one — a tools-version comment on its first non-blank line,
  or below other lines from 6.0 — amendments F, S and S′), **found from the path
  as given, in its on-disk letter case** (amendment L; resolved only afterwards, as a key),
  self-contained under a rejected component (`Tests/Fixtures/X` is its own project), unioned with
  the scanned directory's own production files under the link's spelling; a nested package only
  when the run reaches it — the closure of every manifest's `.package(path:)` values (escapes
  processed, raw strings allowed) and of the nested packages holding its targets' `path:`s,
  across each `Package.swift` and the `Package@swift-*.swift` beside it, followed **by path** to
  manifests under `Tests/`, hidden and pruned directories too, every location compared resolved
  and canonical (amendments H, I, O, P, Q); any computed path in the closure, an unreadable
  manifest, no root manifest, or an Xcode project beside it takes every one (amendment G); and a
  nested package holding a JUDGED file is in with its own closure (amendment J); one entry per file
  on disk, the smallest relative path kept, bounded first; strict UTF-8; production = `.swift`,
  not a manifest, no `Tests` / `*Tests` / dot-prefixed / `DerivedData` / `Pods` / `Carthage` /
  `node_modules` directory component, the `UF_HIDDEN` flag ignored (amendment M); order =
  `buildOrder`, relative path, `String <`. Both repos assert their predicate over a byte-identical
  `construction-universe.tsv`, and their manifest reader (dependencies and target paths) and order
  over a byte-identical `construction-universe-cases.json`; `SEICrossRepoPinTests` asserts both
  pairs of copies are equal.
- **`FunctionScanner.scanCorpus(directory:)` is two-phase** — build the project purity, then
  judge each file. `--target` / `--sources` decide what is JUDGED, never what feeds the table.
- **The census replica gains a `construction` cause**, read off SEI's first witness, and a
  classification guard (below).

---

## On this repo's `Sources/` — the facts-only delta

Configured against `.unconfigured` on **the same trees**, first at `c432f691` (SEI `f2ea8d6`) and
re-taken after the review's fixes at `5a491298` (SEI `9d0bf6d`) and at `e06ec8e9` (SEI `64a905c`),
which agree on every figure:

| | unconfigured `c432f691` | configured `c432f691` | unconfigured `5a491298` / `e06ec8e9` | configured `5a491298` / `e06ec8e9` |
|---|---:|---:|---:|---:|
| universe | 758 files | 758 files | 743 files | 743 files |
| refuted types | 0 | **3** | 0 | **3** |
| functions | 3,217 | 3,217 | 3,232 | 3,232 |
| `.pure` / `.pureButPartial` / `.refuted` | 2,839 / 37 / 341 | 2,839 / 37 / 341 | 2,852 / 37 / 343 | 2,852 / 37 / 343 |
| function verdict flips | — | **0** | — | **0** |
| accessor blocks flipped (of 225) | — | **0** | — | **0** |
| closure literals flipped (of 1,625 → 1,635) | — | **0** | — | **0** |
| rows re-witnessed (SEI's first witness changed) | — | **2** | — | **2** (the same two) |
| witness-bearing / ignorance-only | 221 / 120 | **223 / 118** | 223 / 120 | **225 / 118** |
| `construction` cause (a **lower bound**) | 0 | 2 | 0 | 2 |
| summaries `.pure`, join applied (of 3,456 → 3,471) | 3,052 | 3,052 | 3,065 | 3,065 |

**Read the two right-hand columns as the same experiment on a later tree, not as a movement.**
The universe went 758 → 743: this pass's two new files in, and **17 files of ten `fixtures/*/`
packages out**, because this repo's manifest names no local package and amendment B bounds a
nested package by what the root compiles (760 − 17 = 743). None of those 17 declared a refuting
type, so the 3 refuted types are the same three. Every other change between the column pairs is
this pass's new code (`ConstructionUniverse+NestedPackages`, `FunctionScanner+Declarations`,
`PackagePurity.forJudging`, …) being counted, and it moves the census docs' self-arms the same way —
their head figures stay labelled `c432f691`, where they hold.

**Re-taken after the follow-up review's fixes, at `7fbc7baa`** (same SEI pin): universe **745**
files (743 + this pass's two new source files, `ConstructionUniverse+Manifests` and
`+Location`); the same **3** refuted types, **0** function flips, **0** of 225 accessor blocks, **0**
of 1,646 closure literals, the same **2** re-witnessed rows; witness-bearing / ignorance-only 227 /
120 unconfigured and **229 / 118** configured; functions 3,255, `.pure` 2,871 / 37 / 347 in both
arms; summaries 3,494, `.pure` 3,083 in both arms. Every difference from the column pair above is
this pass's new code being counted. The ignorance-only denominator and its rankable ceiling, 118,
hold.

The 3 refuted types all refute through a defaulted `Date`: `InteractiveTriage.Context`
(`clock:`), `InteractionInteractiveTriage.Inputs` and `InteractionBridgeInteractiveTriage.Inputs`
(`now:`). The 2 re-witnessed rows — `dispatchSideOrchestrator` and `runInteractiveBranch` — were
already refuted, by `propagatedTry`; their first witness is now the construction. **Both throw,
so neither seeds `PackagePurityJoin`** (its witness proxy is `.refuted && !isThrows`), which is
why the join's retractions do not move: 22 at the head, configured or not.

### What the PR's own new code moved, kept apart

Against main `67f77e54`'s census (same SEI pin), the head moved further — but by the code this
PR added to `Sources/` (`ConstructionUniverse`, `PackagePurity`, `FunctionScanner+Package`,
`LargeStackWorkers`, `TypeShapeCarriers`), not by the table:

| | main `67f77e54` | head, unconfigured | head, configured |
|---|---:|---:|---:|
| functions | 3,189 | 3,217 | 3,217 |
| `.pure` / `.pureButPartial` / `.refuted` | 2,821 / 37 / 331 | 2,839 / 37 / 341 | 2,839 / 37 / 341 |
| witness-bearing / ignorance-only | 215 / 116 | 221 / 120 | 223 / 118 |
| bucket a consumer reads | 335 | 345 | 345 |
| computed properties (`.pure` · `.refuted`) | 234 (230 · 4) | 239 (235 · 4) | 239 (235 · 4) |
| blocking-callee denominator (ignorance rows) | 116 | 120 | 118 |
| refuting-direction fixpoint, retracted | 26 of 2,821 | 28 of 2,839 | 28 of 2,839 |
| `PackagePurityJoin`, self, `.pure` before → after | 3,052 → 3,032 (−20) | 3,074 → 3,052 (−22) | 3,074 → 3,052 (−22) |

**Read the middle column as the baseline for the table's effect, never the left one.** Every
other batch-2 census over this repo (allowlist, higher-order, ownership, backtest, blind spot,
module state, refactoring reach, veto precision, advisory round trip, partial consumer) moved
between main and head **only** in its first two columns; the configured and unconfigured head
agree on every printed figure except the classification and the blocking-callee denominators
above.

---

## Across the manifest corpora — rows moved, join applied

Per scan root, `.pure` advice the unconfigured arm gives and the configured arm withdraws.
**Direct** = the row's own per-file verdict moved; **via the join** = only the one-hop
`PackagePurityJoin` moved it. Taken at `c432f691` with every corpus clean on its default branch
except SwiftProjectLint, which another session was editing (`858e1530` plus 2 uncommitted files
during both arms).

| corpus / scan root | universe | refuted types | moved | direct | via join | `--effect-annotations` advice |
|---|---:|---:|---:|---:|---:|---|
| swiftlint-rule-studio / `SwiftLintRuleStudioCore` (`01d7a8e4`) | 91 | 20 | **11** | 10 | 1 | 299 → 288 |
| swiftformat-rule-studio / `SwiftFormatRuleStudioCore` (`aba99191`) | 41 | 1 | 1 | 1 | 0 | 273 → 272 |
| swift-project-lint / `Packages` | 536 → 538 | 6 | **218** | 3 | **215** | 2,117 → 1,899 (2,132 → 1,914 re-taken) |
| harmonize (`41923397`) | 118 | 7 | 7 | 5 | 2 | 237 → 230 |
| swift-foundation / `FoundationEssentials` (`a211bea2`) | 373 | 73 | 21 | 21 (9 functions, 12 getters) | 0 | 3,440 → 3,419 |
| swift-nio / `NIOCore` (`d09ffc8a`) | 328 → **310** | 34 → **33** | 6 | 6 | 0 | 1,057 → 1,051 |
| swift-package-manager / `Basics` (`778e5678`) | 1,122 → **598** | 69 → **67** | 1 | 1 | 0 | 449 → 448 |
| swift-argument-parser (`efd239f0`) | 104 | 1 | 1 | 1 | 0 | 371 → 370 |
| grdb, swift-collections, swift-format, swift-syntax, SwiftPropertyLaws, SEI, MacCloud, this repo, the three fixtures, swift-project-lint / `Sources`, swiftlint-rule-studio / `UI` | — | 0–6 | 0 | 0 | 0 | unchanged |

**266 rows over 21 scan roots. No row anywhere moved toward `.pure`**
(`constructionFactsNeverPromote`, on every corpus and through the join).

**Re-taken at `5a491298` (SEI `9d0bf6d`) with the nested-package bound, and again at `e06ec8e9`
(SEI `64a905c`): the same 266 rows, every direct and every joined row identical**, and the A/B now fails on a root it could not compare
rather than dropping it (it dropped none). Where two figures are shown, the first is `c432f691`'s
and the second the re-take's. The bound shrank five universes, each by nested packages its root
manifest does not name — **swift-package-manager 1,122 → 598** (`Fixtures/`, `Examples/`,
`Benchmarks/`, `Utilities/`; its `.package(path:)` dependencies all point outside the root, where
the universe never goes), **swift-syntax 481 → 338** (`CodeGeneration/`, `Examples/`,
`SwiftParserCLI/`, `SwiftSyntaxDevUtils/`; refuted types 1 → 0), **swift-collections 612 → 575**
(`Benchmarks/`, `Utils/`), **swift-nio 328 → 310** (`Benchmarks/`, `dev/`), **SwiftPropertyLaws
176 → 172** (`Validation/`) — **and moved no row.** SwiftProjectLint's root names all seven
`Packages/` by path, so its universe kept them; its figures moved with its tree (538 files, 2,174
summaries, the same 218 rows).

**Re-taken after the follow-up review's fixes, at `7fbc7baa`** (SEI `64a905c`): **the same 266
rows over 21 roots, every direct and every joined row identical** to `e06ec8e9`'s, and no root
dropped. Two universes moved, by the new rules and correctly: **swift-collections 575 → 612** —
its manifest gives targets a computed `path:` (`kind.path(for: directory)`), which amendment P
reads as doubt, so every nested package is in again (`Benchmarks/`, `Utils/`) — and
**swift-package-manager 598 → 599** — `.target(path: "Examples/package-info/Sources/package-info")`
lies inside the nested `Examples/package-info` package, which amendment P now reaches. Neither
moved a row: the 37 and the 1 files declare no refuting namesake. SwiftProjectLint's universe read
539 (was 538) and its `Packages` advice 2,143 → 1,925 (was 2,132 → 1,914) because its tree moved
(another session's branch) — the same 218 rows; this repo's own 743 → 745 is this pass's two files. GRDB's
`GRDB.xcworkspace` beside its manifest (amendment G) takes every nested package, and its universe
did not move (181).

**The motivating rows, with SEI's witness.** In SwiftLintRuleStudio's Core, `analyze` is direct —
*"constructs `ConfigHealthReport`, and the default value of its stored property `id` references
the nondeterminism marker `UUID`"*. `generateRecommendations` constructs nothing itself; it is
moved **via the join**, through four `inout` helpers — `appendOptInRecommendation`,
`appendPathRecommendation`, `appendBalanceRecommendation`, `appendCoverageRecommendations` —
each of which *"constructs `HealthRecommendation`, and the default value of its stored property
`id` references the nondeterminism marker `UUID`"*. The CLI agrees with the library arm: `swift-infer
discover --sources …/SwiftLintRuleStudioCore --effect-annotations` printed *Pure-effect
annotations (299 functions)* at main and **(288 functions)** at the head, the 11 rows above and
no others; neither `generateRecommendations` nor `analyze(config:knownRules:)` is advised.

**What the table does to SUGGESTIONS, not only to advice.** The impure-subject veto suppresses
a suggestion whose subject is witness-refuted, so a moved row can also withdraw a law. Measured
with the two CLIs back to back (`discover --sources <root> --include-possible`, main `67f77e54`
against head `c432f691`): **swift-package-manager `Basics` 164 → 163** (idempotence over
`InMemoryFileSystem.copy()`, whose construction runs a `DispatchQueue` default) and
**SwiftProjectLint `Packages` 526 → 523** (two `guard-domain` laws and one `predicate` over
visitor methods the join retracted for calling `addIssue`). Re-taken after the review's fixes
(main `27be57ad` against `5a491298`, SwiftProjectLint's tree having moved): `Packages` **529 →
526**, the same three laws; against the wired `a09c5d56`, `e06ec8e9` moves none (523 = 523 on
SwiftProjectLint's `main`, `4d7bce7b`). Every other root measured is
byte-identical in its suggestions: SwiftLintRuleStudio Core (its 11 moved rows are advice only),
swiftformat-rule-studio, Harmonize, swift-foundation, swift-nio, swift-argument-parser, GRDB,
swift-format, and this repo's `SwiftInferCore` — and on this repo the table moves no verdict in
any target, so the veto it feeds cannot move either. **So the committed survey row dumps cannot
move by the table**: `fixtures/verify-runs` (`SwiftInferCore`, GRDB, `SwiftFormat`) and
`fixtures/whole-corpus-survey` (this repo's library targets) are over subjects whose suggestions
it leaves unchanged. They were not re-run; a re-run would measure the PR's new code, not the
table.

**The join amplifies, and it is reported apart for that reason.** SwiftProjectLint's 218 rows are
3 direct — `addIssue` twice and `applyOverrides`, each constructing `LintIssue` (`id = UUID()`) —
and 215 visitor methods retracted one hop away because they call `addIssue`. One refuted helper
retracts every pure caller it has. The 215 are true (a visitor that appends a `LintIssue` mints
an identity) but they are the join's arithmetic, not 215 separate findings.

**Over-refutation, the sound direction, is visible and named.** swift-nio's `NIOCore` moves 6
rows, every one through `ChatHandler` — a class the `NIOChatServer` / `NIOChatClient` *example*
executables declare with a `DispatchQueue` default — because a package's example and tool targets
are production by the shared rule, and a type is matched by name. swift-argument-parser's 1 row is
the same shape: `Tools/generate-manual`'s `GenerateManual`, whose `date` defaults to `Date()`.
swift-foundation's `build_Arg` is refuted because `Date(timeIntervalSince1970:)` resolves to the
package's own `Date`, whose initializer names the `Date` marker. SEI's *any doubt refutes*
accepts all of these; a finer universe would cost the true flips the shared rule exists to keep
(`createTestViolation` in SwiftLintRuleStudio's `…TestSupport` target was the SEI map's witness).

---

## The census apparatus: what the old guard could not see

`verdictAgreesWithSoundPurity` re-assembles every verdict from the replica and compares. **On this
repo the table flips 0 verdicts, so that guard stayed green** — while an unchanged replica would
have filed the 2 re-witnessed rows as actionable ignorance. That is the *misattributing quietly*
the guard was written to prevent, arriving through a door it does not watch. So:

- the replica's `construction` cause is **consulted, not re-derived** — SEI's
  `refutation(constructingIn:)` is internal, and ~1,400 lines re-derived would be the drift the
  census exists to catch — and is a **lower bound**: SEI checks markers, file reads and the
  nondeterminism classifier first, so a function that also reads the clock is counted under
  `marker`. The witness/ignorance split stays exact.
- **`classificationAgreesWithSEIWitness`** compares the replica's filing with SEI's own first
  witness, row by row. Its control, `constructionBlindReplicaIsDetected`, hands the replica an
  unconfigured inferrer and sees it misfile exactly the 2 rows; a snippet control does the same
  without depending on `Sources/`. The mutant `census-replica-blind-to-construction` is killed
  by the guard and survives `verdictAgreesWithSoundPurity`.
- With the oracle forced unconfigured over the same trees, the three construction controls fail
  (the two above and the SwiftLintRuleStudio pin) and every other census in the batch passes.

---

## Cost

`make perf`, serial, this machine (M5 Pro); DequeModule is skipped in-repo here because the
sibling checkout is not at `../swift-collections`, so its row was taken from worktrees beside a
`swift-collections` link (`98ef3c98`).

| §13 row | budget | main `67f77e54` | head |
|---|---|---:|---:|
| Discover pipeline, 100 test files | 6.0s | 2.639s | 2.667s |
| TestLifter.discover, 100 files | 4.0s | 0.419s | 0.447s |
| Discover, 50-file corpus | 2.0s | 0.518s | 0.476s |
| …with decisions-load active | 2.0s | 1.672s | 1.656s |
| **NEW** 50-file package, refuting constructions | 2.0s | — | 0.722s |
| swift-collections DequeModule (worktree) | 4.0s | 1.325s | **2.070s** |
| Drift re-run | 0.5s | 0.454s | 0.465s |
| `--interactive` first prompt | 1.0s | 0.753s | 0.770s |
| 500-file corpus, peak RSS delta | 800 MB | 357.3 MB | 373.1 MB |

Near idle (load 1.6 and 2.7 at start; another session was benchmarking SwiftProjectLint on the
same machine, so not idle). The DequeModule cells are worktree runs at load 3–4, two each: 1.245 /
1.325s at main, 2.065 / 2.070s at head. A loaded head run (load 5.2, a `swift-frontend` at 100%)
read within 70 ms of the head column on every row. Every budget green in every run.

**Re-taken after the review's fixes**, `make perf` alone, three runs per side alternated, each
started below load 5 (1.9–4.8) beside a `swift-collections` link so the DequeModule row runs
in-tree: the wired main `a09c5d56` against `e06ec8e9`, both at SEI `64a905c`:

| §13 row | budget | `a09c5d56` | `e06ec8e9` |
|---|---|---:|---:|
| Discover pipeline, 100 test files | 6.0s | 2.523 · 2.549 · 2.525 | 2.557 · 2.577 · 2.562 |
| TestLifter.discover, 100 files | 4.0s | 0.424 · 0.426 · 0.421 | 0.421 · 0.425 · 0.425 |
| Discover, 50-file corpus | 2.0s | 0.467 · 0.467 · 0.467 | 0.469 · 0.477 · 0.470 |
| …with decisions-load active | 2.0s | 1.582 · 1.579 · 1.583 | 1.582 · 1.592 · 1.571 |
| 50-file package, refuting constructions | 2.0s | 0.641 · 0.640 · 0.636 | 0.641 · 0.648 · 0.645 |
| swift-collections DequeModule | 4.0s | 2.021 · 2.015 · 2.006 | 1.932 · 1.943 · 1.917 |
| Drift re-run | 0.5s | 0.448 · 0.444 · 0.485 | 0.442 · 0.458 · 0.462 |
| `--interactive` first prompt | 1.0s | 0.746 · 0.742 · 0.745 | 0.746 · 0.737 · 0.739 |
| 500-file corpus, peak RSS delta | 800 MB | 373.4 · 373.8 · 373.4 MB | 373.1 · 373.6 · 373.6 MB |

**Two rows moved past the noise, both small.** DequeModule is ~0.08 s faster: its universe is 575
files, not 612, since swift-collections' `Benchmarks/` and `Utils/` packages are out. The 100-file
pipeline is ~0.03 s (1%) slower in all three pairs, within its own spread and not attributed.
Every budget green in every run; none was raised. (A first re-take at SEI `9d0bf6d`, under load
10–19, read the same within noise; there the `--interactive` row failed once at 1.186 s inside a
loaded `make test` and passed alone straight after, on both sides of the A/B.)

**Re-taken after the follow-up review's fixes**, `make perf` alone at `7fbc7baa`, three runs
back to back, each started below load 5 (4.4, 3.6, 2.9) beside the `swift-collections` link so the
DequeModule row runs in-tree; the `e06ec8e9` column is the previous re-take's, on the same machine:

| §13 row | budget | `e06ec8e9` | `7fbc7baa` |
|---|---|---:|---:|
| Discover pipeline, 100 test files | 6.0s | 2.557 · 2.577 · 2.562 | 2.534 · 2.522 · 2.543 |
| TestLifter.discover, 100 files | 4.0s | 0.421 · 0.425 · 0.425 | 0.422 · 0.422 · 0.425 |
| Discover, 50-file corpus | 2.0s | 0.469 · 0.477 · 0.470 | 0.471 · 0.469 · 0.471 |
| …with decisions-load active | 2.0s | 1.582 · 1.592 · 1.571 | 1.585 · 1.578 · 1.595 |
| 50-file package, refuting constructions | 2.0s | 0.641 · 0.648 · 0.645 | 0.645 · 0.644 · 0.643 |
| swift-collections DequeModule | 4.0s | 1.932 · 1.943 · 1.917 | **2.051 · 2.060 · 2.051** |
| Drift re-run | 0.5s | 0.442 · 0.458 · 0.462 | 0.444 · 0.435 · 0.445 |
| `--interactive` first prompt | 1.0s | 0.746 · 0.737 · 0.739 | 0.743 · 0.743 · 0.743 |
| 500-file corpus, peak RSS delta | 800 MB | 373.1 · 373.6 · 373.6 MB | 373.1 · 373.7 · 373.0 MB |

**One row moved, and it is the universe growing back**: DequeModule is ~0.12 s slower because
swift-collections' universe is 612 files again, not 575 — its manifest's computed target `path:`
is doubt under amendment P, so `Benchmarks/` and `Utils/` are in — which puts it back at
`a09c5d56`'s 2.02 s, before the bound. Every other row is within run-to-run noise, every budget
green in every run, and none was raised. Inside the full `make test` (load up to 105 while batches
2 and 3 ran beside another session's build) all nine passed too.

The real cost is DequeModule: its universe is all of swift-collections (612 production files
against 46 judged), and the scan now parses it. +0.75 s in a debug build, inside the 4 s budget,
**with the parse parallel** — a serial parse of a universe that size was the risk the plan named.
The new row is the one that exercises a non-empty table on every verdict; the others' tables are
empty, and an empty table costs the inferrer nothing.

**A crash found on the way, and fixed: the stack-depth trap, in the product.** The first parallel
parse used `DispatchQueue.concurrentPerform`. The batch-2 census died with `SIGBUS` — 184 frames of
recursive descent on a GCD worker, parsing a manifest corpus's universe. A GCD worker and a
swift-testing thread have ~512 KB; a debug parse burns ~10 frames per nesting level and allows 20.
`parsing-catalog-gap.md` recorded the trap for a test; here it was the shipping code path.
`LargeStackWorkers` now runs the parse and the table build on 16 MB-stack threads, and
`universeIsParsedOnLargeStacks` — a nesting-19 sibling file — kills the test process with `SIGBUS`
when the parse is put back on GCD.

⚠ **Corrected after the review: the CLI never had the main thread's 8 MB**, as this paragraph first
said. Every `AsyncParsableCommand`'s `run()` is `async` and runs on a Swift-concurrency cooperative
thread (~512 KB). Measured with `f({ g(…) })` nested 26 and 80 times in a judged file: default
`discover` `SIGBUS`es (rc 138) at both depths on the unwired main `27be57ad`, on the wired `a09c5d56`
and on `e06ec8e9` alike, because **TestLifter's parse still runs on the cooperative stack**; with
`--test-dir` pointed at an empty folder both wired builds survive at 80 and `27be57ad` still dies at
26. What moved to `LargeStackWorkers` is
the universe parse, the table build, the out-of-universe re-parse in
`scanCorpus(file:purity:)`, and the declarations-only scan.

---

## What this does not do, deliberately

- **The seed path is not gated.** `discover --seeds` synthesizes the generic determinism law for
  any seeded function without reading this repo's verdict (`Discover+GenericLaws.swift`); a seed
  from a linter without the table still produces one. Gating `qualifiesForDeterminism` on a
  witness-refuted verdict is its own verdict-moving A/B.
- **The `!isThrows` proxy stays.** The join and the veto still establish a witness from
  `.refuted && !isThrows`; a throwing construction-refuted function (the 2 rows above, and
  whatever the manifest corpora hold of the same shape — not counted here) carries a witness they
  cannot see.
  Carrying SEI's witness on `FunctionSummary` would retract more rows — another A/B.
- **No Xcode-root fallback.** A scan whose directory has no `Package.swift` ancestor is its own
  universe; an Xcode app's sibling folders are not read (`swiftlint-rule-studio / UI`). An Xcode
  project BESIDE a root manifest takes every nested package (amendment G), and nothing more: the
  project file is not read.
- **Accepted gaps of the shared rule, recorded rather than fixed** (each in `ConstructionUniverse`'s
  doc too): a source file named `Package.swift`, or a `Tests` / `*Tests` folder, inside a target is
  dropped by the predicate though the target compiles it — SwiftPM as well as Xcode, which builds
  `Sources/App/Models/Package.swift` and `Sources/App/HelperTests/H.swift` into `App` — because the
  predicate reads names; **a symlinked package's own relative dependencies resolve from its
  canonical target**, not from the link's location as SwiftPM resolves them (amendment 4, V); a scan
  of an NFC-named directory spells its own members NFD (Swift compares canonically, so no verdict
  moves); **namesakes across modules in one universe over-refute** — SEI matches a constructed type by
  name, so once two modules share a universe (a judged package under amendment J, every nested
  package of a manifest-less or Xcode root) one module's `Row` refutes another's `Row(n:)` it never
  imports, the sound direction; and **a symlinked sibling directory is not walked** (next bullet).
- **A manifest-less WORKSPACE root is one universe, and since SEI `64a905c` it costs about the sum
  of its packages.** The same rule makes `discover --sources ~/src` — a folder of several packages
  with no `Package.swift` of its own — one universe with every nested package in (amendment B: no
  manifest says what is compiled, so any doubt includes). At SEI `9d0bf6d`, `ConstructionFacts.build`
  re-walked the member-type graph per decode site and per fixpoint pass; the review measured
  swift-collections + swift-nio + swift-argument-parser + swift-algorithms + swift-syntax side by side
  at ~17× main's CPU and ~7× its peak RSS, ~14× the five packages scanned one by one, and here the
  same build `SIGBUS`ed after ~14 s even on a 16 MB stack (the `Self`-alias loop SEI #24 also ends).
  **SEI #24 (`64a905c`) memoises it**: timing `PackagePurity.forScan(of:)` alone, the folder (1,553
  files) builds in **16.0 s, 77 s CPU, 744 MB peak**, against **7.5 s, 61 s CPU, at most 383 MB** for
  the five packages one by one (1,355 files — each bounded to what its root compiles). Partitioning
  per nested package here would drop the constructions an app makes from its own local packages —
  the under-refuting direction — so it is still not done.
- **A symlinked SIBLING target is not in the universe.** The walk never descends a symlinked
  directory (nor does SwiftProjectLint's), so a scan of `Sources/Lib` beside a symlinked
  `Sources/Model` misses `Model`'s types — the unsound direction, recorded rather than fixed,
  because following symlinks in one consumer only would break the shared universe. **A scanned
  symlinked target is handled since the review** (amendment D): its root is found from the path
  as given, so it is judged under the package holding the link, with that package's real sibling
  targets, and its own files join under the link's spelling
  (`symlinkedTargetSeesItsRealSiblings`, `linkIntoAnotherPackageIsJudgedWhereTheLinkIs`). Before,
  the root was found from the link's destination — that destination's package, or the target
  alone — and `make()` was advised pure while a real sibling target's `Item` minted a `UUID`.
- **No SEI change here; the one this branch recommended has since landed.** SEI resolved a
  same-named alias by its first target only, so the refuted set depended on input order, and the
  fixed shared order made the two consumers agree, not sound. SEI #23 (`9d0bf6d`) reads an alias
  where it is written and follows every alias a name may mean where that is in doubt, so which
  types refute no longer depends on order; the shared order still decides which witness is
  reported first. Re-taken at `9d0bf6d` (`make batch2`, 2026-10-06), the `Sources/` delta and the
  per-corpus table above came out identical, every printed figure to the digit — and again at
  `64a905c` (SEI #24, which memoises how the table is built and changes nothing it says). Still
  recommended upstream: a public `isProductionSource` and a structural digest, so agreement
  becomes a property of the pin.

## One oracle, two consumers

`SEICrossRepoPinTests` used to say that an equal SEI pin means the linter and this engine consult
one oracle. With the table wired into both, **an equal pin is necessary and not sufficient**: the
same pin over two universes is one oracle configured two ways. The universe rule is written twice
and pinned by two byte-identical answer keys — `construction-universe.tsv` for the predicate,
`construction-universe-cases.json` for the manifest reader and the build order. **The first key
alone was not enough, and the review showed it**: the two `.tsv`s were byte-identical while
SwiftProjectLint already bounded nested packages and deduplicated by the smallest path and this
repo did neither, so one root gave two tables. **The two keys were not enough either**: the
follow-up review found the two closures written from one amendment text and differing in four
places, so since amendment 3b `ConstructionUniverse+NestedPackages.swift` is SwiftProjectLint's file
line for line below its header, and a third clause (`nestedPackageClosureMatchesSwiftProjectLint`)
compares the two bodies. All three clauses skip loudly where the sibling carries no copy; until
SwiftProjectLint's side lands on its main, the two consumers knowingly disagree.

---

## The review's fixes — what each moved

An adversarial review of the wiring (2026-10-06) confirmed 17 findings; every one is fixed here,
each with a test that fails with its fix reverted (and, for each mechanism, a mutant in
`mutants/manifest.json`). **Rows moved, CLI A/B**, `discover --sources <root>` with
`--effect-annotations` (advice) and `--include-possible` (suggestions), main `27be57ad` ·
pre-review head `5499fbb4` · `5a491298`:

| subject | advice: main → pre-review → now | suggestions: main → pre-review → now |
|---|---|---|
| SwiftLintRuleStudio Core | 299 → 288 → **288** | 2,137 lines identical in all three |
| SwiftProjectLint `Packages` | 2,132 → 1,914 → **1,914** | 529 → 526 → **526** |
| the review's `Demo/` scenario (an uncompiled nested package's `Row`) | 1 → 0 → **1** (`make(n:)`) | 0 → 0 → 0 |

So the fixes moved **one advice row, the false withdrawal**, and nothing on either real subject:
the pre-review branch and this one print byte-identical output on SwiftLintRuleStudio Core and on
SwiftProjectLint's `Packages`. **Re-taken after the rebase**, wired `a09c5d56` (the pre-review
wiring at SEI `64a905c`) against `e06ec8e9`: SwiftLintRuleStudio Core 288 → 288 advice and 60 → 60
suggestions, byte-identical; SwiftProjectLint `Packages` (its `main`, `4d7bce7b`) 1,899 → 1,899 and
523 → 523, byte-identical; `Demo/` 0 → **1** advice, `make(n:)`.

| finding | fix | pinned by |
|---|---|---|
| shared-spec amendment 1 not implemented: an unrelated nested package refuted the root's namesakes | nested packages bounded by the root's `.package(path:)` closure (`localPackageDependencies(manifest:)`, the doubt rule), smallest-path dedup, strict UTF-8 | `ConstructionUniverseNestedPackageTests`, `ConstructionUniverseCasesTests`, `deduplicationKeepsTheSmallestPath`, `nonUTF8FileIsNotInTheUniverse`, `unreferencedNestedPackageIsNotWatched` |
| a symlinked `Sources/<target>` judged at its destination | root found from the path as given (amendment 2 D) | `symlinkedTargetSeesItsRealSiblings`, `linkIntoAnotherPackageIsJudgedWhereTheLinkIs`, `linkFromOutsideEveryPackageFindsItsPackage` |
| the order was unpinned; the cross-repo guard saw only the predicate | `ConstructionUniverse.buildOrder`, the shared cases file, byte-compared across repos (amendment 2 E) | `universeOrderIsStringLessThan`, `buildOrderIsTheSharedOrder`, `universeCasesMatchSwiftProjectLint` |
| `suggest-refactors --speculative` compared a full-universe baseline with a `Sources/`-only snapshot | the snapshot copies every universe member | `SpeculativeUniverseTests` (a `Core/` custom-path target, an `Examples/` namesake) |
| `--scan-dependencies` and the refint gate built tables they never read | `FunctionScanner.scanTypeDecls(directory:)` | `declarationsOnlyScanMatchesTheFullScan`, `declarationsOnlyCallersBuildNoTable` |
| `discover-reducers`, `verify-value-semantics`, `census` built a purity with nothing to judge | `PackagePurity.forJudging(directory:)` | `purityIsBuiltOnlyForAJudgedSet`, `purityIsBuiltOnlyThroughTheGuard` |
| the getter path survived its own mutant | — (tests) | `getterConstructingASiblingTypeIsRefuted`, `constructionFacts_refuteEveryAnswer` |
| `scanReusesTheFactsTrees` could not tell reuse from a re-parse | the node-identity subject, through both overloads | itself, killing `scan-reparses-universe-trees` alone |
| the per-corpus A/B swallowed its own misalignment guard | failures recorded and asserted empty | `constructionFactsNeverPromote` |
| wrong docs: the CLI's stack, `--resolve-effects`, `CensusCommand`'s example, the stale `9d0bf6d` items | corrected; `--resolve-effects` re-measured (+5% to +23% wall, < 2 MB RSS, no row moved) | — |
| a manifest-less workspace root's facts build was superlinear | documented; fixed upstream by SEI #24 (`64a905c`), re-measured above | — |

**And one addition the bound made necessary**: the index's staleness probe now watches the
manifests that decide it, so adding `.package(path:)` for a nested package marks the index stale.

---

## The follow-up review's fixes — amendments 3 and 3b

A joint follow-up review of both consumers (2026-10-07) confirmed 24 findings, and its critic added
four fixtures; the shared spec gained amendments F–N and O–R, implemented here and in
SwiftProjectLint. Every fix has a test that fails with it reverted, and a mutant
(`mutants/README.md`, the third construction batch).

| amendment | what was wrong here (review id) | fix | pinned by |
|---|---|---|---|
| F — what a manifest is | a source file named `Package.swift` inside `Sources/App/Models/` made a package boundary and dropped its target's other files (`spl#1`); a dangling `Ghost/Package.swift` link was doubt and let an unrelated `Demo/` in, where SwiftProjectLint read no package (`agreement#4`); a directory named `Package.swift` made a root | a manifest is a regular file whose first line is `// swift-tools-version` (BOM allowed); one that cannot be read as UTF-8 is a manifest and doubt | `ConstructionUniverseManifestTests` |
| G — Xcode beside the manifest | a root manifest beside `App.xcodeproj` bounded the universe to its own closure, dropping the local package only the app links (`spl#2`) | a direct-child `*.xcodeproj` / `*.xcworkspace` takes every nested package | `xcodeProjectBesideTheManifestTakesEveryNestedPackage` |
| H — the literal's value, resolved | `"Pack\u{61}ges/A"` named no package; an absolute literal through `/private`, a symlinked prefix or another letter case missed one (`sip#3`, `agreement#2`, `spl#3`) | `representedLiteralValue`; standardise, then resolve symlinks, compare resolved | `manifestCasesHold`, `ConstructionUniverseDependencyPathTests` |
| I — the closure by path | the closure stopped at a package under `Tests/`, `*Tests`, a hidden or a pruned directory, which SwiftProjectLint follows (`agreement#0`, `tests#0`, `sip#4`) | each dependency followed to `<dir>/Package.swift` on disk; one with no manifest passes nothing on and is no doubt; the walk enters `Tests/` for the packages it holds, as SwiftProjectLint's does | `closurePassesThroughAnUnwalkedPackage`, `doubtInAnUnwalkedPackageIncludesEveryNestedPackage`, `dependencyOnNoManifestIsNoDoubt`, `packageUnderTestsIsANestedPackage` |
| J — judged packages | `--sources Examples` over an uncompiled `Examples/Demo` judged Demo without its own types and proposed a law the base vetoed (`robustness#1`) | the walked packages owning a judged file seed the closure (`reported:`); `covers` compares members, not roots | `ConstructionUniverseJudgedPackageTests`, `judgedPackageSeedsTheClosure` |
| K — large stack | a 1,000-arm `else if` in a nested manifest `SIGBUS`ed `discover` (`robustness#3`) | the closure runs on `LargeStackWorkers` at its one call site, as SwiftProjectLint's does | `deepManifestIsReadOnALargeStack` |
| L — on-disk letter case | a mis-cased `--sources` made the predicate case-sensitive on a case-insensitive volume, both ways, and spelled members after the typing (`sip#1`, `agreement#3`) | `onDiskSpelling(of:)` before the root search | `ConstructionUniverseLetterCaseTests` |
| M — hidden is a name | the scanned directory's own files came through `SwiftSourceFiles`, which skips `UF_HIDDEN`; for a scanned symlinked target nothing else reaches them | the union walks the scanned directory like the root | `hiddenFlagIsNotHiddenName` |
| N — the shared order | the shared `buildOrder` could not tell `String <` from a per-component sort (`tests#5`) | the cases file's `Sources/A-B/X.swift` / `Sources/A/X.swift` pair | `buildOrderIsTheSharedOrder`, `sharedOrderDiscriminates` |
| O — `Package@swift-*.swift` | a dependency named only in `Package@swift-6.0.swift` was never read (critic `s6v`) | the union over a directory's manifests, in name order, whatever its `Package.swift` is; doubt in any is doubt; the watch list holds them | `versionSpecificManifestIsRead`, `versionSpecificDoubtIsDoubt`, `versionSpecificManifestWithoutPackageSwiftIsRead` |
| P — target paths | `.target(name: "Core", path: "Core/Sources/Core")` inside a nested `Core/` left its files out (critic `s7`) | `localTargetPaths(manifest:)`; every walked package a closure manifest's resolved target path equals or lies in is reached | `targetPathInsideANestedPackageReachesIt`, `targetPathsAcrossTheClosure`, `targetPathCasesHold` |
| Q — canonical locations | a dependency through a symlinked package directory never met the walked package (critic `s11`) | both sides standardised, then `realpath(3)`, and compared by location | `symlinkedPackageDirectoryReachesTheWalkedPackage` |
| R — the cases file | target paths had no shared answer key | a `localTargetPaths` section, byte-identical | `targetPathCasesHold`, `universeCasesMatchSwiftProjectLint` |
| — | `suggest-refactors --speculative` skipped every candidate over one unreadable universe file outside `Sources/`, and leaked a snapshot per failure (`sip#2`, `robustness#2`) | unreadable members skipped, as `PackagePurity` skips them; a failed snapshot removed | `unreadableUniverseFileIsSkipped`, `failedSnapshotIsRemoved` |
| — | "bound, then deduplicate" was unpinned (`tests#4`) | — (test) | `boundBeforeDeduplicating` |

**The closure is one text now, not two.** Each repo first implemented the amendments from their
wording, and the two closures differed in four places — what a target path reaches, what seeds a
judged package, when a version-specific manifest is read, how a location is canonicalised. So
`ConstructionUniverse+NestedPackages.swift` is SwiftProjectLint's file from
`extension ConstructionUniverse {` to its end, readers and closure alike, and
`nestedPackageClosureMatchesSwiftProjectLint` (`SEICrossRepoPinTests`) compares the two bodies the
way the `.tsv` and the cases file are compared. The edges the amendments leave open follow
SwiftProjectLint's reading too: a `Package.swift` that is not UTF-8 is a manifest that cannot be
read (doubt only where the closure reads it), and any direct child named `*.xcodeproj` counts. (The
tools-version line was then matched case-sensitively on the first line alone; amendment 4's S and
4b's S′ have since replaced that with what SwiftPM loads — see the last section.)

**Rows moved, CLI A/B** — `discover --sources <root>` with `--effect-annotations` (advice) and
`--include-possible` (suggestions), the archived pre-fix head `6bc89a0c` against `7fbc7baa` (both
debug builds, SEI `64a905c`; binaries and outputs in the session's scratch, not committed):

| subject | advice `6bc89a0c` → `7fbc7baa` | suggestions |
|---|---|---|
| SwiftLintRuleStudio Core | 288 → 288, byte-identical | 60 → 60, byte-identical |
| SwiftProjectLint `Packages` (its `main`, `4d7bce7b`) | 1,899 → 1,899, byte-identical | 523 → 523, byte-identical |
| the `Demo/` namesake scenario (`Sources/Lib`) | 1 → 1 (`make(n:)`), byte-identical | 0 → 0 |
| `--sources Examples` over an uncompiled `Examples/Demo` (`robustness#1`) | 2 → **1** — `normalized(_:)` no longer advised pure; `clamp` stays | 3 → **2** — the idempotence law over `normalized` withdrawn |
| the critic's `s6v` / `s7` / `s11` (`discover --target App`) | 1 → **0** each — `tokenCount` no longer advised pure | 0 → 0 |
| the critic's `s6c` (the control) | 0 → 0, byte-identical | 0 → 0 |

So the fixes moved exactly the rows they were written for, and nothing on either real subject.

---

## The final review's fixes — two regressions and amendment 4

The final review of PR #635 (2026-10-07) measured two performance regressions the amendment-3
work introduced, a guard gap, and an NFD note; and the shared spec gained amendment 4 (S–V),
implemented identically in SwiftProjectLint. Timings below are release builds on this machine,
medians of five, the reviewer's `6bc89a0c` and `c6fadde4` binaries against `7888bed4` (both
performance fixes, before amendment 4).

| measurement | `6bc89a0c` (base) | `c6fadde4` | `7888bed4` |
|---|---:|---:|---:|
| `discover-reducers --sources` swift-package-manager `Sources/Basics` | 0.93 s | 1.78 s | **0.80 s** |
| `discover-reducers --sources` `SwiftInferCore` | 0.61 s | 1.15 s | **0.64 s** |
| `covers`, built-for directory (Basics · SwiftInferCore) | 0.1 · 0.1 ms | 277 · 150 ms | **0.0 · 0.0 ms** |
| universe, Basics · SwiftInferCore | 215 · 86 ms | 278 · 149 ms | **196 · 95 ms** |
| universe, `fx/snap` `Sources/App` (50,000 PNGs under `Tests/`) | 0.4 ms | 2,443 ms | **247 ms** |
| `discover-reducers --sources Sources/App`, `fx/snap` | 0.01 s | 9.68 s | **0.26 s** |
| `discover --sources Sources/App`, `fx/snap` (default test dir) | 0.36 s | 2.86 s | **0.61 s** |

- **`covers` answers from its record** (`7888bed4`): the directory a purity was built for is
  covered by construction; another root is foreign by `root(forScanOf:)` alone; any other
  directory is compared in full once and remembered. `discover-reducers` is back at base.
- **The walk reads attributes only where they decide** (`031b4c0c`): a dot-prefixed or pruned
  name, and a production `.swift` path. `fx/snap` is ~10× faster than `c6fadde4`, and still
  ~250 ms over base, which pruned `Tests/` outright and so disagreed with SwiftProjectLint (whose
  own walk takes ~0.8 s there): entering `Tests/` for its packages costs one directory entry each.
- **Two §13 rows pin both** (`ConstructionUniversePerformanceTests`): 20,000 files under `Tests/`
  walked in 0.111–0.113 s against 0.5 s (0.986 s with the per-entry read put back), and three
  `covers` asks in 0.0000 s. ⚠ **Corrected after the review of #636**: that row's budget was 0.05 s
  and its package 5,000 files, so once 031b4c0c made a universe cheap (~25 ms in debug) the memo
  alone answered asks 2 and 3 and the row passed without the built-for shortcut — the one
  `discover-reducers` and `verify-value-semantics` use. The 0.674 s first recorded here as "computed
  every time" included the walk 031b4c0c reverted. The row now prices the FIRST ask: 20,000 files,
  a 0.02 s budget — 0.0000 s with the shortcut, **0.112 s without it, 0.318–0.320 s** with all of
  `covers` reverted — and `Coverage.universesComputed` pins it structurally (0 for the built-for
  directory, 0 for another root, 1 for another directory asked twice).
- **S — a manifest is what SwiftPM loads.** `isManifest(_:)` is the spec's reference
  implementation: the first non-blank line, the label in any case, or a later line naming 6.0 or
  more. The reviewer's `fx/blank` (`// Swift-Tools-Version:5.9`) is 2 members and `make` refuted
  again, as at base; `c6fadde4` advised `make` pure. The cases file's `isManifest` section (U, 19
  cases) is the arbiter. **S′ (amendment 4b)** corrects S's spacing — `\h` and `isWhitespace`, as
  SwiftPM's parser reads it, where S's `[ \t]` refused `//\u{00A0}swift-tools-version` — and puts a
  label check in front of rule (b)'s regex (a 20,000-line comment file: 0.042 s, 1.401 s without
  it, in debug); the section has 28 cases. Only truly empty lines load before the comment at every
  version; lines of whitespace, CRLF blank lines among them, need 5.4.
- **T — a target path reaches the nested packages under it**, not only the ones holding it:
  `.target(name: "All", path: "Packages")` compiles `Packages/A`'s sources. The closure body is
  SwiftProjectLint's text again, byte for byte. **T′**: a root target's `path: "."` resolves to
  the root, `""`, which no prefix test matches (`package.hasPrefix("" + "/")` is false), so T's
  first body reached none of the packages under it, contrary to the spec's own note. Found here,
  fixed in the shared body (SwiftProjectLint `1bd48dec`, copied byte for byte at `13714773`): the
  comparison opens with `location.isEmpty ||`. Pinned by `rootTargetPathReachesEveryNestedPackage`
  (all three expectations fail without the clause) and the mutant `target-path-root-reaches-nothing`.
- **V** — the docs no longer imply SwiftPM leaves a `Package.swift` or `*Tests` folder out of a
  target, and record that a symlinked package's own relative dependencies resolve from its
  canonical target. **T-gaps (4b)**, documented, not extended: a target with no `path:` holding a
  nested package (SwiftPM's default `Sources/<name>`) is not reached, and neither is a symlink below
  a target path to a package walked elsewhere (`path: "Packages"`, `Packages/A → ../Real/A`).

**Re-taken at `a4e68820`: nothing moved.** On `Sources/`: universe 746 (745 +
`ConstructionUniverse+Bound.swift`), 3 refuted types, 0 function flips, 0 of 225 accessor blocks, 0 of 1,650 closure literals, the same 2 re-witnessed rows, 229 / 118 configured; functions
3,256 and summaries 3,495, `.pure` 3,084 in both arms. Across the corpora: the same 266 rows over 21
roots, every direct and joined row identical to `7fbc7baa`'s, every universe the same size but this
repo's own. S and T could move verdicts in principle; on these trees they move none.

`make perf` alone at `a4e68820`, three runs at load below 4: every row within noise of the round
above (DequeModule 2.030–2.034 s, pipeline 2.535–2.553 s, peak RSS delta 371 MB), the two new
rows as above, every budget green, none raised.

**Re-taken after T′, at `ec0f1d3a`: nothing moved again** — the same `Sources/` figures (746, 3
refuted types, 0 flips, 2 re-witnessed, 229 / 118) and the same 266 rows over 21 roots, every root
line and every moved row identical to `a4e68820`'s; no corpus scan root sits under a root target
whose `path:` is `"."`. `make perf` was not re-run alone: T′ adds one boolean test per target path
and nested package to a closure that already compares their prefixes, and the full `make test`'s
own perf stage passed all 11 rows.

**After the adversarial review of #636 (round 4).** Four findings fixed and amendment 4b (S′, the
T-gaps) taken, at `5fe7c179`–`461472e6`:

- **The `covers` row now guards the shortcut it was written for**: the first ask, priced on a
  20,000-file package against 0.02 s (0.112 s without the built-for shortcut, 0.318–0.320 s with all
  of `covers` reverted), plus `Coverage.universesComputed`, which must stay 0 for the built-for
  directory and for another root.
- **The root guard is pinned** by an identical layout under another root — what a speculative
  snapshot is — which `covers` must refuse without a walk.
- **S′**: `isManifest` is amendment 4b's reference verbatim (identical to SwiftProjectLint's):
  `\h` and `isWhitespace`, and a label check in front of rule (b)'s regex — a §13 row, 20,000
  comment lines in 0.039–0.041 s against 0.25 s (1.401 s without the check). The shared cases file
  holds 29 `isManifest` cases; reverting the `isNewline` split, the later-line label's case, `\h`,
  the label check's `drop(while:)` or rule (b)'s leading `\h*` each fails `manifestTextCasesHold`.
- **Docs**: the stale first-line wording retired; the T-gaps recorded; "blank lines at any version"
  corrected to empty lines only.

**Re-taken at `22853fb0`: nothing moved** — `Sources/` universe 746, 3 refuted types, 0 flips, the
same 2 re-witnessed rows, 229 / 118; the same 266 rows over 21 roots, every root line and moved row
identical (this repo's own advice 764 → 766 is new code). `make perf` alone, three runs at load
2.7–4.2: all 12 rows green, none raised — walk row 0.115–0.116 s, `covers` 0.0000 s, `isManifest`
0.039–0.041 s, DequeModule 2.06–2.08 s, pipeline 2.59–2.60 s, peak RSS delta 369 MB.
