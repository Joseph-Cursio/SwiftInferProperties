# Corpus funnel census — every seed, every repository (2026-09-14)

> **Status:** `measured` · **As of:** 2026-09-14
> **Method:** a breadth pass over [`docs/plans/corpus-pipeline-walk-scope.md`](../plans/corpus-pipeline-walk-scope.md)'s pipeline

The walk has so far gone deep on three subjects, one function at a time. This asks the
breadth question it cannot: **of every seed SwiftProjectLint emits across the corpus, how
many become a property test that compiles and passes — and where do the rest stop?**

## What this is and is not

**It measures yield, not refutability.** The walk's commitment 1 — predict each law before
running — was waived for breadth, because hand-predicting 2,716 functions is not a census.
So this page can say *how many laws got through each stage*; it cannot say whether a
proposed law was the one worth having.

**A pass is weak.** No planted violator was run against any passing law. A green result
here means *no counterexample in 100 draws*, and SwiftMarkdownWiki's `mimeType_idempotence`
(#453) already shows a false law passing.

## Instrument

| | |
|---|---|
| SwiftProjectLint | `eebf93de` (clean) |
| SwiftInferProperties | `8e460d41` (clean, binary rebuilt at HEAD — the `.build` one was stale) |
| SwiftPropertyLaws | `076f6db` (clean) |
| SwiftEffectInference | `1b62e76` (clean) |
| Swift | 6.3.3 (swiftlang-6.3.3.1.3) |

Subjects, all clean: SwiftMarkdownWiki `46cb4a9` · SwiftProjectLint `eebf93de` ·
SwiftAssist `e06d15e` · SwiftPropertyLaws `076f6db` · SwiftUMLStudio `f4b5cab` ·
SwiftLintRuleStudio `246a3f5` · pbt-workbook-corpus `ca12ee1` · pbt-book `6f77d55` ·
SwiftFormatRuleStudio `1b51c68` · SwiftEffectInference `1b62e76` ·
SwiftLintRuleStudioTeam `284456f` · MacCloud_client_MacOS `a7376fd` ·
SwiftCloneDetector `b097dcc` · pbt-workbook-sampler `ee66e95` · LintStudioUI `41d1d4c` ·
MacCloud_server `65cdc08` · SwiftIdempotency `91cd82f` · pbt-workbook `fd9b5e4` ·
pbt-workbook-grader `8f112a8`.

Excluded on the scope doc's principle: MacCloud_client_iOS (frozen fixture) and
SwiftInferProperties (tool under test). SwiftProjectLint, SwiftPropertyLaws and
SwiftEffectInference are **included and marked toolchain** — they are tools under test too,
and partly grade their own homework.

## Pipeline — identical for every repository

1. Detached `git worktree` of HEAD. Nothing was written to any subject repository.
2. `CLI . --format pbt-seeds --include-nested-packages` (the sweep's configuration).
3. Each seed is placed in the SwiftPM package + target whose directory holds its file.
   Seeds under no SwiftPM target are grouped by top-level directory and **emitted but not
   compiled**.
4. Per target: `swift-infer index --target … --seeds` for structured suggestions, then
   `discover --sources … --seeds --include-possible --interactive --output-dir` with every
   prompt answered `A`.
5. Per package: existing test targets dropped; one census test target per scanned module,
   depending on the module, `PropertyLawKit` and `PropertyBased`. `swift build --build-tests`;
   every stub file carrying an error is set aside with its first error, repeated to a
   fixpoint. Survivors run serially with `--no-parallel`; a crash is attributed to the last
   test started and the run resumes past it.
6. Joins by `(file, line)`: seed → index entry → stub `// Source:` header. Law class from
   `Refutability.swift`'s template sets, **not** the stub's `Law class:` header (#466).

### Adjustments, and why each is not a thumb on the scale

- **An existing SwiftPropertyLaws dependency** (SwiftLintRuleStudioCore pins 3.x) was
  replaced by HEAD — the stubs are v4 code.
- **A `swift-property-based` 1.x pin used only by test targets** (SwiftProjectLint root,
  MacCloud_server) was dropped with those targets. Where a *library* target uses it, the
  conflict was left standing and recorded.
- **A swift-syntax resolution conflict** retried against a trimmed kit copy
  (`PropertyLawKit` + `PropertyLawCore`, no swift-syntax). Two packages needed it.
- **Two manifests name their package variable `kPackage`** and needed the injected block
  addressed to it.

### Validation

- **The pilot reproduced the SwiftMarkdownWiki ledger exactly** — 103 seeds, 55 stub files,
  7 compiled, and the same seven verdicts as its §S7 run (two fail, `mimeType` passes while
  false, four pass). Re-run under the final harness recipe: identical.
- **All 975 joined stubs match their seed's symbol by file name.** 0 mismatches.
- Decline notes (stderr) are paired to suggestion blocks (stdout) by prompt order; on the
  pilot every note's template matched its block's.

## Result

### The funnel, over named seeds

682 of 3,398 seeds are `extractable-kernel` — a closure inside a larger function. They are
Queue B by the scope doc: no law can attach until someone extracts them.

| stage | all 19 | excluding 5 book repos |
|---|---:|---:|
| named seeds | 2,716 | 2,346 |
| any law proposed | 2,079 | 1,781 |
| a **refutable** law proposed | 1,010 | 780 |
| a refutable stub file written | 309 | 243 |
| that stub compiles | 92 | 46 |
| a law passes | **71** | **38** |
| an **entailed** law passes | **28** | **15** |

Book repos: pbt-book, pbt-workbook, -corpus, -sampler, -grader — teaching code, some
deliberately broken.

**The loss is at emission and compilation, not proposal.** 1,010 seeds had a refutable law
proposed; 309 got a file.

### Verdicts, over stubs that ran

Stubs, not seeds, and including 12 compiled laws on functions the linter never seeded — kept
because the code's role owes them (the "manifest SHOULD have named it" rescue).

| class | passed | failed | crashed |
|---|---:|---:|---:|
| entailed | 39 | **0** | 0 |
| conjecture — non-book repos | 23 | 9 | 0 |
| conjecture — book repos | 23 | 8 | 15 |

**Entailed: 39 run, 0 false** — the class split the walk found on two subjects holds at
corpus scale.

**All nine non-book conjecture failures are false laws on correct code**, and none is a bug.
Seven read for this census, two already adjudicated in the SwiftMarkdownWiki ledger:

| subject | law | why it is false of correct code |
|---|---|---|
| `SkillSigner.sha256(_:)` | idempotence | a hash of a hash is a different hash |
| `ThinkingRecipeIngester.makeID(from:)` | idempotence | prepends `idPrefix` every time |
| `PatternMarkdownParser.extractValue(from:)` | idempotence | `"a: b: c"` → `"b: c"` → `"c"` |
| `TokenEstimator.estimateTokens(in:)` | monotonicity | ordered by `String <`, not by word count — `Refutability`'s own `"aa" < "b"` example |
| `RawType.swiftStringLiteral` | idempotence | a literal of a literal escapes again |
| `CLIToolActor.escapeShellArgument(_:)` | idempotence | quoting a quoted argument re-quotes it, by design |
| `LintConfigurationLoader.load(projectRoot:)` | round-trip with `render` | pairs a path with YAML text, and the loader reads the filesystem |
| `highlight`, `strippingHeadingMarkers` | idempotence | SwiftMarkdownWiki ledger §S7 |

**The 15 crashes are `Ch17Templates` and are real traps, not harness artifacts.** Run in
isolation, `add_isCommutative()` starts and the process dies: `add(_:_:)` is `lhs + rhs` over
full-width `Gen<Int>.int()`, which overflows. One attempt over that chapter ran 677 s. This
is **deliberate emitter policy, not a defect** — `boundedDeterminismGenerator`'s comment:
*"Other templates keep full-range generators, where extremes do matter."* A trap is a genuine
totality failure of `add`. Recorded because it is the cost of that policy on arithmetic
subjects: 15 red tests whose message is a crash, not the law named in the test.

Four `replay-idempotence` stubs are TODO scaffolds that `Issue.record` on purpose; they are
excluded from every law count.

## Where the rest stop

Counts are suggestions or stubs as labelled, overlap, and do not sum to the funnel.

| count | cause | owner | filed |
|---:|---|---|---|
| **732** suggestions | stub declined on arity — the subject is an instance method or takes more arguments than the template applies. **497 are entailed** (`predicate` 457, `input-totality` 40), for which arity is not meaningful | swift-infer | **#464** |
| **1,069** seeds | the only proposal is `f(x) == f(x)` — scored a miss | swift-infer catalogue | — |
| **481** stubs | determinism stub calls the subject by bare name — `cannot find '<subject>' in scope` | swift-infer | **#465** |
| all determinism stubs | header labels the tautology `CONJECTURE` | swift-infer | **#466** |
| **637** seeds | nothing proposed at all | swift-infer catalogue (S3) | — |
| **244** suggestions | no stub writer for the template — **148 entailed** (`guard-domain` 62, `normal-form` 39, `caseiterable-key-injectivity` 20, `filter-subset` 13, `comparator` 6, `state-machine` 6, …) | swift-infer | **#468** |
| **120** refutable stubs | subject `private` / `fileprivate` — the stub's `Access:` header says so (84 entailed) | subject code | — |
| **120** stubs | overwritten — same-named functions on different types share `<template>/<function>_<template>.swift` (16 entailed, 16 conjectures, 88 determinism) | swift-infer | **#467** |
| **76** refutable stubs | no derivable generator — `.todo` marker (44 entailed) | SwiftPropertyLaws · swift-infer | — |
| **3** repositories | `swift-property-based` 1.2 in library code vs the kit's 2.x — 145 seeds with a refutable proposal never got a stub | SwiftPropertyLaws | not filed |
| **27** refutable stubs | code outside any SwiftPM target (Xcode-only, Tuist, app and plugin directories) — a limit of this harness | census harness | — |

### Not filed, and why

- **The swift-syntax footprint.** SwiftUMLBridge (swift-syntax 600) and SwiftLint (a 605
  prerelease) could not resolve SwiftPropertyLaws, though `PropertyLawKit` never imports
  swift-syntax — SwiftPM resolves the whole package graph. A consumer-side finding for
  SwiftPropertyLaws, which owns the fix (a separate package for the syntax-dependent
  products, or looser pins). Left for that repository's own decision.
- **The `swift-property-based` 1.2 conflict** is the book repos' pin, not a defect.
- **Full-width `Int` generators** — deliberate, see above.
- **308 determinism stubs whose first error names a type** (`LintIssue`, `RuleIdentifier`,
  `JSValue`) rather than the subject — cross-module carriers. Not characterised here.

## By repository

`passed (E)` = named seeds with at least one passing law (with an entailed one).

| repository | kind | seeds | named | refutable | stub | compiles | passed (E) | note |
|---|---|---:|---:|---:|---:|---:|---:|---|
| SwiftProjectLint | toolchain | 1,029 | 746 | 409 | 95 | 14 | 14 (4) | 276 receiver-form declines |
| SwiftAssist | app/library | 438 | 326 | 73 | 24 | 11 | 7 (5) | |
| SwiftPropertyLaws | toolchain | 327 | 287 | 52 | 28 | 6 | 5 (1) | |
| SwiftLintRuleStudio | app/library | 292 | 234 | 63 | 15 | 1 | 1 (1) | SwiftLint's swift-syntax pin |
| SwiftUMLStudio | app/library | 284 | 238 | 47 | 22 | 3 | 3 (2) | swift-syntax 600; app outside SwiftPM |
| pbt-workbook-corpus | book | 194 | 186 | 125 | 0 | 0 | 0 | dependency conflict |
| pbt-book | book | 152 | 144 | 84 | 64 | 46 | 33 (13) | 15 overflow traps |
| SwiftFormatRuleStudio | app/library | 147 | 113 | 18 | 6 | 2 | 2 (1) | |
| SwiftEffectInference | toolchain | 114 | 103 | 32 | 13 | 1 | 1 (0) | |
| SwiftMarkdownWiki | app/library | 103 | 84 | 26 | 17 | 4 | 2 (0) | +3 entailed passes on unseeded parsers |
| SwiftLintRuleStudioTeam | app/library | 102 | 80 | 13 | 2 | 0 | 0 | Tuist — not compiled |
| SwiftCloneDetector | app/library | 72 | 42 | 15 | 8 | 1 | 1 (1) | |
| MacCloud_client_MacOS | app/library | 44 | 43 | 17 | 5 | 0 | 0 | Xcode only — not compiled |
| pbt-workbook-sampler | book | 26 | 25 | 19 | 1 | 0 | 0 | dependency conflict |
| LintStudioUI | app/library | 24 | 24 | 7 | 3 | 3 | 2 (0) | |
| SwiftIdempotency | app/library | 16 | 12 | 6 | 4 | 0 | 0 | replay laws are scaffolds |
| MacCloud_server | app/library | 14 | 14 | 2 | 1 | 0 | 0 | |
| pbt-workbook | book | 12 | 8 | 1 | 1 | 0 | 0 | dependency conflict |
| pbt-workbook-grader | book | 8 | 7 | 1 | 0 | 0 | 0 | |

For SwiftMarkdownWiki, SwiftUMLStudio, MacCloud_client_MacOS and SwiftLintRuleStudioTeam, the
suggestion counts for groups with no `Package.swift` come from the emit transcript, because
`index --target` has nothing to resolve against.

## What this says about the walk

1. **The walk's first subject was not representative, and now we know by how much.**
   SwiftMarkdownWiki's "proposes 48, emits 21, runs 9" was flagged as an upper bound; the
   corpus rate from refutable proposal to a compiling stub is 92 / 1,010 seeds.
2. **The binding constraint is emission, and it falls hardest on the laws that cannot cry
   wolf.** 497 entailed laws declined on arity and 148 on missing writers, against 39 entailed
   laws that ran. #464 and #468 are the two changes with the largest effect on entailed yield.
3. **No failing law found a bug.** Nine false conjectures, zero entailed failures. Totality
   passing 39 of 39 is what the class predicts and says nothing about whether the corpus has
   trap bugs — no violator was planted.
4. **Stage S7 is unmeasured at this scale.** 85 passing laws, none shown to be able to fail.
   That is the next thing a census would need, and it cannot be done by counting.

## Reproducing

The driver, harness, re-harness and aggregation scripts were run from a session scratchpad and
are not in this repository. The pipeline above is complete enough to rebuild them; the
decisions that change a number are all listed under *Adjustments*.
