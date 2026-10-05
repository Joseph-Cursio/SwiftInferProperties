# Does the docstring advisory's reference-oracle scaffold compile? 0 of 88 before, 66 of 67 after

> **Status:** `measured` · **As of:** 2026-10-04

`discover`'s docstring advisory (on by default) prints, for a documented function whose doc states a
checkable contract, a block headed `── runnable reference oracle (fill the stub, then run it) ──`. It is
meant to be pasted into a test file, with one `fatalError` line replaced by the reference definition.
**At `f87bb241` (1.158.0) not one of them compiled, on either subject**: 0 of 88 and 0 of 48 on
SwiftAssist (seeded and unseeded runs), 0 of 35 and 0 of 43 on swift-format.

Two stacked changes followed. Branch `share-subject-call-plan` (`ad1b3e62`, `45b88af2`) moved the
determinism accept arm's call into `SubjectCallPlan` and `LiftedTestEmitter.agreementProperty`, with no
change to scaffold output. Branch `scaffold-calls-subject-like-accept` (`a047c2b0`, `a45ea19c`) built the
scaffold through them. It now spells the call the way `accept` does, declares a member's
`<name>_reference` in an `extension` of its type, and draws generators from the accept path's resolver.
Where nothing can compile, it prints `── no runnable reference oracle: <reason>` instead. This is the
census of what discover prints before and after, on the same two subjects with the same seed manifests.

| subject | run | before (`f87bb241`): printed / compile | after (`a45ea19c`): printed / compile / declined |
|---|---|---:|---:|
| SwiftAssist @ `a89e6e46` | seeded (707 seeds) | 88 / **0** | 67 / **66** / 21 |
| SwiftAssist | unseeded | 48 / **0** | 33 / **33** / 15 |
| swift-format @ `b15dd59f` | seeded (118 seeds) | 35 / **0** | 1 / **0** / 34 |
| swift-format | unseeded | 43 / **0** | 1 / **0** / 42 |

**Printed + declined equals the baseline's printed count in all four runs**, and discover's stdout
outside the scaffold blocks is byte-identical before and after. No scaffold appeared and none
vanished. Each one now compiles or was replaced by a named reason, except **3 per-run items that are
printed and still fail**: `WorkspaceIndexer.encodeSnapshot(_:)` in SwiftAssist's seeded run, an open
resolver defect (*Open, not decided*, below), and `Verbatim.prettyPrintingLength(maximum:)` in both
swift-format runs, the Swift 5 language-mode exception.

## Read before quoting a number

- ⚠ **These counts are per RUN, not distinct.** Seeded and unseeded runs share scaffolds. Distinct
  SwiftAssist scaffolds: 99 before (0 compile), 70 after (69 compile). Never add the two runs.
- ⚠ **State it as rows moved, never as laws gained.** On SwiftAssist, 66 seeded and 33 unseeded
  scaffolds moved from *does not compile* to *compiles*, and 21 and 15 moved from *printed and
  fails* to *declined with a reason*. A compiled
  scaffold still holds a `fatalError` the reader must replace. Nothing here ran a law, and nothing
  says a reference definition is right.
- ⚠ **"Compiles" means two things, both measured.** Each scaffold was compiled alone with SwiftPM's
  exact `swiftc` arguments for a test target, with `-emit-sil` so the SIL-stage concurrency checks run.
  Then all that passed were built together through SwiftPM. After the change, 69 of 69 built
  together, in one batch, first round.
- ⚠ **swift-format's 0 of 1 is the sanctioned exception, not a spelling defect.** Its one printed
  scaffold, `Verbatim.prettyPrintingLength(maximum:)`, fails with two errors of one cause: *'oneOf'
  is unavailable in Swift* and *'frequency' is unavailable in Swift*, the edge-biased draws of its
  `String` and `Int` arguments. The package builds in Swift 5 language mode (see *Out of scope*);
  with the census arguments' `-swift-version 5` changed to `6`, the same file compiles (exit 0).
  On swift-format the number to read is the decline count. 32 of its 35 seeded subjects are
  `private`.
- ⚠ **Several emitted shapes have no population here.** No scaffold printed on either subject
  awaits an actor member, hops to `MainActor`, or calls an operator. All 6 async or actor-isolated
  SwiftAssist subjects declined: 5 because no generator derives their receiver, 1 as `private`.
  Those shapes are witnessed only by the compiled witnesses in the test targets
  (`ReferenceOracleScaffoldWitness`, `ReferenceOracleDiscoverWitness`), not by this census. What
  the census does exercise, over 70 distinct scaffolds: 68 member references in an extension,
  31 `(args: (…))` bindings with one `let` per argument, 13 drawn receivers (3 of them
  `Gen.always` over a stateless type), 3 `try?`, 3 `approximatelyEqual`, 2 `nonisolated`
  references and 1 Sendable shim.
- ⚠ **The type-check-timeout count is the compiler's.** It is a deterministic solver limit, but it
  is per compiler version. Every run here used Xcode 27's Swift 6.4 (`swiftlang-6.4.0.34.1`); the
  swift.org 6.3.3 toolchain the Makefile prefers was not installed.
- ⚠ **Counts move with the seed manifest, and not in one direction.** Both manifests came from
  SwiftProjectLint 1.0.0 and are pinned in `fixtures/reference-oracle-scaffold-census/`. Seeds gave
  SwiftAssist MORE scaffolds (88 against 48) and swift-format FEWER (35 against 43). Two effects pull
  opposite ways. A scaffold needs a surviving suggestion to take its generator and seed from, and the
  determinism law synthesized for a seeded pure function supplies one. But the seed focus also narrows
  the documented functions that can get a scaffold at all: 289 → 97 on SwiftAssist, 174 → 42 on
  swift-format.
- ⚠ **Dependency versions are pinned by the Package.resolved fixtures, not by any manifest.** The
  census target asks for SwiftPropertyLaws `from: "4.7.0"` and swift-property-based `from: "2.0.0"`
  (the funnel's `KIT_DEPENDENCY` and `ENGINE_DEPENDENCY`), swift-format asks for swift-syntax
  `branch: "main"`, and both subjects gitignore their Package.resolved. swift-format's verdict rests
  directly on swift-property-based's `@available(swift 6.2)`. A run without `--resolved` resolves
  whatever is newest, and is a different measurement.
- The test-file header does not move the result. The harness adds the declaring file's imports to
  stand in for accept's carrier imports. Re-run with only the fixed imports (`--bare-imports`),
  SwiftAssist gives the same 66 of 67 and 33 of 33.

## Method

`scripts/reference_oracle_scaffold_census.py`, once per subject and binary:

1. `swift-infer discover --target <T> --include-possible`, with and without `--seeds`, in a pristine
   detached worktree of the subject. `.swiftinfer/` is cleared before and after each run.
2. Every item of the *Reference definitions from docstrings* section is extracted: its scaffold, or
   its decline line with a category. The categories are **access** (*cannot be called from a
   test*), **generic**, **generator** (*no generator derives*), **equatable** (*no scanned
   declaration makes … Equatable*), and **plan** (everything else: what `SubjectCallPlan`
   declines, an initializer, an opaque or existential result).
3. Each subject's declaration is read from its source with a small lexer: static, instance or free;
   `throws`; `async`; global-actor isolation; access; generic parameters. This counts needs a
   compiler cannot report, such as a `try` behind a call that never resolves.
4. A second worktree gets a census test target, made by the funnel's own
   `corpus_funnel_stage5.rewrite_manifest` and checked with `verify_manifest`. swift-format's manifest
   defeats that text surgery, so for it the harness appends Swift that edits `package` instead. The
   target is built once holding only a sentinel file, and the exact `swiftc` command SwiftPM used is
   read off `swift build -v`.
5. Each distinct scaffold is compiled ALONE with those arguments, plus `-emit-sil`. The header is
   accept's fixed stub imports (Foundation, Testing, PropertyBased, PropertyLawKit,
   `@testable import <T>`) plus the declaring file's own imports.
6. The scaffolds that compiled alone are built TOGETHER through SwiftPM in the census target. They
   are batched so that no two files declare the same `@Test` or Sendable shim, and the funnel's
   fixpoint rule applies.
7. Every compiler error is attributed to one cause. The before-run also ran three *counterfactual
   probes* that repair the call mechanically (qualify it, add `try`/`await`, hoist generators) and
   compile again, to show what each first blocker was hiding. Probes are not what discover printed.
   After the change they are a regression check. A probe that compiles where the printed scaffold
   does not is an emitter defect: **0 found, of 2 checked** (the 2 free functions). The other 68
   distinct scaffolds declare their reference in an extension, which the repairs cannot rewrite, so
   they are not checked and the zero says nothing about them; the compile census above is their
   evidence. The `call-repaired` probes that compiled alone are also built together through
   SwiftPM, as step 6 builds the scaffolds.

**Why one file at a time.** The first design built one census target to a fixpoint, holding one
file per distinct function name: 93, since the 99 distinct before-scaffolds share 93 names and a
module cannot declare two file-scope `<name>_reference` functions. It reported 4–7 files per round.
The build stops at the first failed compile job, and `-continue-building-after-errors` did not change
that. A declaration-level error in ANY file, such as *cannot find type 'Citation'* in a reference
signature, also stops the frontend from type-checking every body, even under `-wmo`. Twelve rounds
measured 45 of 93 files. Compiling per file with SwiftPM's own arguments, and then confirming in the
package, avoids both. **The two agreed both times, and the harness re-checks that on every run.**
Before the change no scaffold compiled alone, so the check falls to the probes: the 42 distinct
`call-repaired` probes that compiled alone also built together, 42 of 42, in two batches of one
round each (39 and 3 files: three function names, `parse`, `makeID` and `extractKeywords`, appear
twice). After it, all 69 scaffolds that compiled alone built together in one round, and so did the
2 probes the regression check compiled.

**Pinned:** SwiftAssist @ `a89e6e46d40e765e965544a0e96934ad6becd686`, target `SwiftAssist`.
swift-format @ `b15dd59fad`, target `SwiftFormat`. Seeds: `SwiftAssist-seeds.json` (707 rows) and
`swift-format-seeds.json` (118 rows). Dependencies: `SwiftAssist-Package.resolved` and
`swift-format-Package.resolved`, the files both census targets built against, passed with
`--resolved`. They hold SwiftPropertyLaws 4.9.3 and swift-property-based 2.0.1, and swift-format's
`branch: "main"` swift-syntax at `0f7a57c588`. The funnel's `KIT_DEPENDENCY` still reads
`from: "4.7.0"` while `VerifierWorkdir` pins 4.9.3; the fixture is what holds 4.9.3. Binaries, which
report only `1.158.0 (unattributable build)`: before, sha256 `243d2659c7793215…`, a release build of
`f87bb241`; after, `aea96bb835d2eaa6…`, a release build of `a45ea19c`'s sources. Each run's
results.json records the full hash and the checkout the binary sits in.

Every item's before and after is in `fixtures/reference-oracle-scaffold-census/items-2026-10-04.tsv`,
written by `scripts/reference_oracle_scaffold_rows.py` from the two runs' results.json. It has 214
rows and these columns: `subject`, `run`, `function`, `location`, `shape`, `access`, `before`
(`compiles` or `fails:<first blocker>`), `before_causes` (every cause the compiler reported),
`after` (`compiles`, `fails:<first blocker>` or `declined:<category>`) and `after_detail` (the
decline reason, or every compiler error of a printed scaffold that fails).

## SwiftAssist

**First blocker per scaffold, before.** Seeded: bare call to a static member 68, missing receiver
18, type-check timeout 2. Unseeded: bare call 28, missing receiver 20. The subjects split 68 static,
18 instance and 2 free functions (seeded), and 28 static and 20 instance (unseeded).

**Every cause the compiler reported** (a scaffold counts under each of its causes):

| cause | seeded before | seeded after | unseeded before | unseeded after |
|---|---:|---:|---:|---:|
| bare call to a static member (`fileName(…)` for `SandboxLedger.SourceKind.fileName(…)`) | 68 | 0 | 28 | 0 |
| type-check timeout (*unable to type-check this expression in reasonable time*) | 45 | 0 | 24 | 0 |
| missing generator (`T.gen() /* TODO */`) | 19 | 0 | 13 | 0 |
| missing receiver (instance method called bare) | 18 | 0 | 20 | 0 |
| consequential (`Input` uninferable after an unresolved call) | 13 | 0 | 4 | 0 |
| nested type unqualified in the reference signature | 4 | 0 | 3 | 0 |
| `Self` copied into a file-scope reference | 2 | 0 | 1 | 0 |
| a derived generator that does not type-check | 0 | **1** | 0 | 0 |

In the before-run's probes, qualifying the call removed 27 of the 45 seeded timeouts, and moving
each generator into its own statement before the check removed the other 18. After the change
there are none, with no generator moved out of the check: the scaffold's sample is now the
determinism emitter's, one `let` per argument inside the sample closure.

**Where the 88 seeded scaffolds went:**

| subject shape (before) | compiles | fails | declined: access | declined: generator |
|---|---:|---:|---:|---:|
| static member, 68 | 53 | 1 | 10 | 4 |
| instance method, 18 | 11 | 0 | 3 | 4 |
| free function, 2 | 2 | 0 | 0 | 0 |

Unseeded, the 48 split: static 28 → 23 compile, 3 access, 1 generator, 1 equatable; instance 20 →
10 compile, 3 access, 7 generator.

- **Every scaffold the before-run's repair probe predicted now compiles as printed**, matched by file,
  line and name: all 43 seeded, all 19 unseeded.
- **The `private` subjects all decline as access, with the remedy:** 13 seeded (10 static, 3
  instance; one through a `private` enclosing type) and 6 unseeded.
- **The 27 seeded scaffolds that carried a `.gen() /* TODO */` placeholder** (the table's 19 are
  those the compiler reported it for; each of the other 8 reported a type-check timeout instead):
  13 now derive every draw and compile, 7 decline as access, 6 decline as generator, and 1 derives a
  generator that does not type-check. Every scaffold with a placeholder over a type the scan does
  not declare (`Range<Int>`, `String.Index`, `[[Any]]`, `[String: Any]`, a labelled-tuple array)
  now declines: as generator, or as access when the subject is `private`.
- **Effects** (all in the unseeded run; the seeded subjects need none): the 3 subjects that throw
  and are neither async nor actor-isolated print with `try?` and compile
  (`CoverageReport.parse(from:)`, `WorkspaceJail.resolve(_:)`,
  `SwiftLintConfigParser.parse(configFileURL:)`). All 6 async or actor-isolated subjects decline,
  as above.

**The one printed scaffold that fails: `WorkspaceIndexer.encodeSnapshot(_:)`.** It fails with *no
exact matches in call to initializer*, its only error, inside the generator for
`SemanticMap.FileSymbolInfo`. The resolver derived `SemanticMap.SymbolSummary` through
`init(from symbol: Symbol)`, where `Symbol` is SwiftSourceKitClient's type (`SemanticMap.swift`
imports that module). It spelled that `Symbol` as `XcodeDocument.Symbol`, the only scanned type of
that name. This generator comes from the accept path's resolver (`projectTypeGenerator`, over
SwiftPropertyLaws' `GeneratorResolver`), so accept draws the same text. It is a resolver defect
shared with accept, not a scaffold spelling. **It is open, not out of scope** (see *Open, not
decided*): `docs/user/reference.md` lists it among the `--docstring-advice` known exceptions, and
`docs/design-internal/open-threads.md` row 78 tracks the fix.

**Declines, after:**

| category | seeded | unseeded | what they are |
|---|---:|---:|---|
| access | 13 | 6 | `private` subjects; one `private` enclosing type |
| generator | 8 | 8 | no generator derives a receiver (for example `ModelRouter.RouteResult`, and classes or actors such as `ResourceGovernor` and `PolicyGraphStore`) or an argument (`Range<Int>`; `CodeSandbox.PatternDef`, whose init takes a closure; `ModelStack`; `Scip_Occurrence`; an array of labelled tuples) |
| equatable | 0 | 1 | `SkillLinterFixer.fix(…)` returns `FixResult?`, and nothing makes `FixResult` Equatable |

Discover's other 9 seeded and 241 unseeded documented functions printed no scaffold before and print
the same text after.

## swift-format

**Before.** Seeded subjects: 22 instance methods, 12 free functions and 1 static member. 32 of the 35
are `private`. First blocker: missing receiver 22, private subject 12, bare static call 1. Every
cause: missing generator 24, receiver 22, private 12, consequential 6, timeout 4, generic signature
copied into a non-generic reference 3, `Gen.frequency` unavailable 1, bare call 1, a private type 1,
an `@_spi` type 1. 31 of the 32 `.gen()` placeholders were over SwiftSyntax types or generic
parameters standing for them, and one over a project type. Unseeded: 43
scaffolds, first blocker receiver 34, private 7, timeout 1, bare call 1. Every repair probe compiled
**0**.

**After.** Seeded: 1 printed (fails as above), 34 declined (access 32, generator 2). Unseeded: 1
printed, 42 declined (access 36, generator 5, plan 1).

- Access: 32 seeded and 36 unseeded, exactly the before-run's `private` subjects. 8 of each are members
  of `private` enclosing types (`TokenStreamCreator`, `RuleStatusCollectionVisitor`, `Line`), whose
  remedy says widening the member alone is a no-op.
- Generator: SwiftSyntax receivers (`DeclModifierListSyntax` twice, `WithAttributesSyntax`,
  `AttributeSyntax`) and `GitIgnorePattern`, whose initializers do not support derivation.
- Plan: `parseAndEmitDiagnostics(…)` takes a function-typed parameter.

## Out of scope, by decision

- **Swift-5-language-mode packages.** swift-property-based 2.0.1 marks `Gen.oneOf` and `Gen.frequency`
  `@available(swift 6.2)` (its `Sources/PropertyBased/Gen+Frequency.swift`, lines 35, 67, 130
  and 170). swift-format declares
  `swiftLanguageModes: [.v5]` (its `Package.swift:150`), so any scaffold drawing a numeric or
  `String` edge-biased value fails there. Every generator recipe shares this, and so does accept's
  determinism stub. Of the printed-but-failing causes the design put out of scope, it is the only one
  with a member in this census.
- **SwiftSyntax node generators.** The accept path draws SwiftSyntax nodes from `SyntaxCorpusSource`,
  which needs a support file only `accept` writes. The scaffold does not, so a SwiftSyntax receiver
  or argument declines as generator. 31 of swift-format's 32 seeded placeholders were over
  SwiftSyntax types before the change.
- Shared with accept and documented beside `--docstring-advice` in `docs/user/reference.md`: a
  receiver of a global-actor-isolated type built through its isolated initializer, and a
  `.defaultIsolation(MainActor)` target. Pasting several scaffolds into one file can declare
  `approximatelyEqual` or a Sendable shim twice.

## Open, not decided

- **`encodeSnapshot(_:)`'s generator** (SwiftAssist, seeded; *The one printed scaffold that fails*,
  above) is a defect awaiting an owner call, tracked as row 78 of
  `docs/design-internal/open-threads.md`. Nobody put it out of scope. The rewire was built to
  *everything printed must compile*, and the design's out-of-scope list (Swift 5 mode, SwiftSyntax
  generators, global-actor receivers and `.defaultIsolation(MainActor)` targets, `@_spi` names,
  pasted duplicates, among others) names no resolver mis-derivation. That accept draws the same text
  makes it a shared defect, not an accepted one.

## Predictions, and what happened

Written down before the scaffold change was built, from the before-run's probes and declaration
facts.

| # | prediction | result | |
|---|---|---|---|
| 1 | SwiftAssist seeded compiles a value in [43, 75], equal to the number printed | **66**, of 67 printed | in range ✅; equal ❌ (`encodeSnapshot`: an open resolver defect shared with accept, open-threads row 78) |
| 2 | the 43 visible, placeholder-free static scaffolds the probe compiled all compile, by name | 43 of 43 | ✅ |
| 3 | the 13 `private` subjects decline as access (10 static, 3 instance) | 13 (10, 3) | ✅ |
| 4 | the foreign-only placeholders (`Range<Int>`, `String.Index`, `[[Any]]`) decline | all decline | ✅ |
| 5 | the 9 seeded fallback items with no scaffold render unchanged | byte-identical | ✅ |
| 6 | unseeded compiles ≥ 19 (with `CoverageReport.parse(from:)` under `try?`), equal to printed; 6 access | 33 of 33; 6 | ✅ |
| 7 | swift-format seeded: access ≥ 32, generator ≥ 1, at most 2 printed, failing only on Swift 5 mode | 32, 2, 1 printed, `'oneOf'` and `'frequency'` unavailable | ✅ |
| 8 | swift-format unseeded: about 36 access | 36 | ✅ |

## Cost of the harness

| | before (`f87bb241`) | after (`a45ea19c`) |
|---|---|---|
| SwiftAssist run, wall | ~94 s; 115 s and 101 s on the re-runs, which add the probe package build | 29 s; 26 s on both re-runs |
| — per-file compiles | 99 files in ~49 s at 9 parallel; median 0.9 s, max 11.7 s | 70 files in ~2 s; median 0.3 s, max 0.5 s |
| — package confirm | nothing compiled alone | 69 files, one round: 9.5 s; 6.1 s and 5.7 s on the re-runs |
| — repair probes | 297 compiles, ~35 s | 6 compiles, ~1 s |
| — probe package build | 42 probes in two batches: 11 s and 5 s, then 5 s and 4 s | 2 probes, 5 s |
| swift-format run, wall | ~27 s; 29 s and 27 s on the re-runs | 7 s; 5 s and 4 s on the re-runs |

These are warm runs. There were two re-runs, both with the pinned Package.resolved files and the
probe package build: one on 2026-10-04, and one on 2026-10-05 with the harness exactly as committed.
Each reproduced every count. Before the first run: the release `swift-infer` build takes about
157 s. The census target's first build of SwiftAssist and its dependencies took 1 min 26 s. The two
build worktrees take 3.3 GB. Discover itself takes about 3 s per SwiftAssist run and 1.3 s per
swift-format run.

## Reproduce

From this repository, after `swift build -c release --product swift-infer`:

```
F=fixtures/reference-oracle-scaffold-census
scripts/reference_oracle_scaffold_census.py --swift-infer .build/release/swift-infer \
    --subject <SwiftAssist checkout> --ref a89e6e46d40e765e965544a0e96934ad6becd686 \
    --target SwiftAssist --seeds $F/SwiftAssist-seeds.json \
    --resolved $F/SwiftAssist-Package.resolved --out <work dir> --label after
scripts/reference_oracle_scaffold_census.py --swift-infer .build/release/swift-infer \
    --subject <swift-format checkout> --ref b15dd59fad --target SwiftFormat \
    --seeds $F/swift-format-seeds.json \
    --resolved $F/swift-format-Package.resolved --out <work dir> --label after
scripts/reference_oracle_scaffold_rows.py --out <work dir> --before baseline --after after \
    SwiftAssist swift-format > items.tsv
```

Each run writes `runs/<label>-<Name>/summary.txt` and `results.json` under the work directory. A run
labelled `baseline` in the same work directory, made with a `f87bb241` binary, is what the
*printed + declined* check compares against (`--baseline-label` names another). Re-running both
binaries through the committed harness with `--resolved` on 2026-10-05 reproduced every count above,
discover's stdout byte for byte, and the items table byte for byte. A run without `--resolved`
builds against whatever the subject checkout last resolved, which is not this measurement.

The subject repositories are not edited, but each run registers two worktrees in them
(`<work dir>/subjects/<Name>` and `<work dir>/build/<Name>`). Remove them with
`git -C <checkout> worktree remove` when done. `--reclassify` re-attributes a saved run at the
revision it measured, and refuses a `--ref` that names another.
