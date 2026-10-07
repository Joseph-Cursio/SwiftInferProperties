# Construction facts, wired in — what the table moved

> **Status:** `measured` · **As of:** 2026-10-06

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
  SwiftProjectLint: root = nearest `Package.swift` ancestor of the scanned directory **found from
  the path as given** (resolved only afterwards, as a key), self-contained under a rejected
  component (`Tests/Fixtures/X` is its own project), unioned with the scanned directory's own
  production files under the link's spelling; a nested package only when the root compiles it (the
  closure of its `.package(path:)` literals — any computed path in the closure, or no root manifest,
  takes every one); one entry per file on disk, the smallest relative path kept; strict UTF-8;
  production = `.swift`, not a manifest, no `Tests` / `*Tests` / hidden / `DerivedData` / `Pods` /
  `Carthage` / `node_modules` directory component; order = `buildOrder`, relative path, `String <`.
  Both repos assert their predicate over a byte-identical `construction-universe.tsv`, and their
  manifest reader and order over a byte-identical `construction-universe-cases.json`;
  `SEICrossRepoPinTests` asserts both pairs of copies are equal.
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
  universe; an Xcode app's sibling folders are not read (`swiftlint-rule-studio / UI`).
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
repo did neither, so one root gave two tables. Both clauses skip loudly where the sibling carries
no copy; until SwiftProjectLint's side lands on its main, the two consumers knowingly disagree.

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
