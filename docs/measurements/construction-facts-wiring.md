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
  SwiftProjectLint: root = nearest `Package.swift` ancestor of the scanned directory (symlinks
  resolved), self-contained under a rejected component (`Tests/Fixtures/X` is its own project),
  unioned with the scanned directory's own production files; production = `.swift`, not a
  manifest, no `Tests` / `*Tests` / hidden / `DerivedData` / `Pods` / `Carthage` /
  `node_modules` directory component; order = relative path, `String <`. Both repos assert their
  predicate over a byte-identical `construction-universe.tsv`, and `SEICrossRepoPinTests` asserts
  the two copies are equal.
- **`FunctionScanner.scanCorpus(directory:)` is two-phase** — build the project purity, then
  judge each file. `--target` / `--sources` decide what is JUDGED, never what feeds the table.
- **The census replica gains a `construction` cause**, read off SEI's first witness, and a
  classification guard (below).

---

## On this repo's `Sources/` — the facts-only delta

Configured against `.unconfigured` on **the same trees** at `c432f691` (SEI `f2ea8d6`):

| | unconfigured | configured |
|---|---:|---:|
| universe | 758 files | 758 files |
| refuted types | 0 | **3** |
| functions | 3,217 | 3,217 |
| `.pure` / `.pureButPartial` / `.refuted` | 2,839 / 37 / 341 | 2,839 / 37 / 341 |
| function verdict flips | — | **0** |
| accessor blocks flipped (of 225) | — | **0** |
| closure literals flipped (of 1,625) | — | **0** |
| rows re-witnessed (SEI's first witness changed) | — | **2** |
| witness-bearing / ignorance-only | 221 / 120 | **223 / 118** |
| `construction` cause (a **lower bound**) | 0 | 2 |
| summaries `.pure`, join applied (of 3,456) | 3,052 | 3,052 |

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
| swift-project-lint / `Packages` | 536 | 6 | **218** | 3 | **215** | 2,117 → 1,899 |
| harmonize (`41923397`) | 118 | 7 | 7 | 5 | 2 | 237 → 230 |
| swift-foundation / `FoundationEssentials` (`a211bea2`) | 373 | 73 | 21 | 21 (9 functions, 12 getters) | 0 | 3,440 → 3,419 |
| swift-nio / `NIOCore` (`d09ffc8a`) | 328 | 34 | 6 | 6 | 0 | 1,057 → 1,051 |
| swift-package-manager / `Basics` (`778e5678`) | 1,122 | 69 | 1 | 1 | 0 | 449 → 448 |
| swift-argument-parser (`efd239f0`) | 104 | 1 | 1 | 1 | 0 | 371 → 370 |
| grdb, swift-collections, swift-format, swift-syntax, SwiftPropertyLaws, SEI, MacCloud, this repo, the three fixtures, swift-project-lint / `Sources`, swiftlint-rule-studio / `UI` | — | 0–6 | 0 | 0 | 0 | unchanged |

**266 rows over 21 scan roots. No row anywhere moved toward `.pure`**
(`constructionFactsNeverPromote`, on every corpus and through the join).

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

The real cost is DequeModule: its universe is all of swift-collections (612 production files
against 46 judged), and the scan now parses it. +0.75 s in a debug build, inside the 4 s budget,
**with the parse parallel** — a serial parse of a universe that size was the risk the plan named.
The new row is the one that exercises a non-empty table on every verdict; the others' tables are
empty, and an empty table costs the inferrer nothing.

**A crash found on the way, and fixed: the stack-depth trap, in the product.** The first parallel
parse used `DispatchQueue.concurrentPerform`. The batch-2 census died with `SIGBUS` — 184 frames of
recursive descent on a GCD worker, parsing a manifest corpus's universe. A GCD worker and a
swift-testing thread have ~512 KB; a debug parse burns ~10 frames per nesting level and allows 20.
`parsing-catalog-gap.md` recorded the trap for a test; here it was the shipping code path, since
the CLI used to parse on the main thread's 8 MB. `LargeStackWorkers` now runs the parse and the
table build on 16 MB-stack threads, and `universeIsParsedOnLargeStacks` — a nesting-19 sibling
file — kills the test process with `SIGBUS` when the parse is put back on GCD.

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
- **A symlinked SIBLING target is not in the universe.** The walk never descends a symlinked
  directory (nor does SwiftProjectLint's), so a scan of `Sources/Lib` beside a symlinked
  `Sources/Model` misses `Model`'s types — the unsound direction, recorded rather than fixed,
  because following symlinks in one consumer only would break the shared universe. Scanning the
  symlinked target itself resolves it (`symlinkedTargetIsInUniverse`).
- **No SEI change.** SEI's alias resolution follows only the first target of a same-named alias,
  so the refuted set depends on input order; the fixed shared order makes the two consumers
  agree, not sound. Recommended upstream, with a public `isProductionSource` and a structural
  digest, so agreement becomes a property of the pin.

## One oracle, two consumers

`SEICrossRepoPinTests` used to say that an equal SEI pin means the linter and this engine consult
one oracle. With the table wired into both, **an equal pin is necessary and not sufficient**: the
same pin over two universes is one oracle configured two ways. The universe rule is written twice
and pinned by one byte-identical answer key; until SwiftProjectLint's side lands on its main, the
two consumers knowingly disagree, and the cross-repo table clause skips loudly where the sibling
carries no table.
