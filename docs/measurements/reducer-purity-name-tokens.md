# Does `ReducerPurityAnalyzer` refute pure code by name?

> **Status:** `measured` · **As of:** 2026-11-12

**Yes, for `Effect` and `.run`, and only the `Effect` half is fixed.** `SoundPurity` now asks the analyzer a
purity question (`ReducerPurityAnalyzer.analyzeForPurity`). There, `Effect`, `EffectOf` and `EffectTask`
do not refute in a package that shows no sign of TCA (`TCAPresence`). Routing keeps `analyze`, unchanged.
On the pinned corpus this moves **6 verdicts, all in SwiftEffectInference, every one hand-checked pure**.
In rows: **0 against `main`, and 3 against the impure-veto branch (PR #721)**, the determinism laws
over `inferEffects`, `combine` and `nameGatedInference`. They are 3 of the 10 laws that branch withholds
on these name tokens; the other 7 rest on `.run`.

**`.run` is NOT narrowed, and that is a decision, not a gap.** 18 of its 19 survey hits were name
collisions. But dropping it re-admits `Process.run()`: for a `Process` passed in as a parameter, nothing
else refutes the spawn. And 8 of its 19 hits would have read `.pure` while impure, through calls neither
SEI nor the package join follows (a SourceKit request, file reads, a thread plus a global notice): the
token was the only thing refuting them. Reopen it only once the join can follow member calls or more than one hop.

## The question

`ReducerPurityAnalyzer` was written for **routing**. It decides whether a reducer runs in-process or in a
subprocess, and it matches by name: `Effect`, `EffectOf`, `EffectTask`, `Task`, `AnyCancellable`, any
`await`, and `.run`, `.send`, `.cancel` or `.fireAndForget` on any base. Its own doc accepts false
positives because they cost only a slower path.

`SoundPurity` reuses it as the first refuter of its meet with SEI. There a false positive becomes
`.refuted`, which the impure-subject veto (`TemplateRegistry.applyImpureSubjectVeto`) turns into a
withheld law. The veto's bypass paths, closed in PR #721, withheld 13 laws on this corpus, and 10 of
them rested on these name tokens.

## Method

- **Survey.** Every function body in the 116 source targets of #684's 19 pinned trees plus this repo's
  `Sources/` (12,035 functions) that `ReducerPurityAnalyzer` refutes and SEI's configured inferrer
  does not. 84 functions, grouped by the token that fired.
- **Classification.** One agent per token group read each function and called it *effect* or
  *collision*, and a second agent challenged every verdict. They agreed on all 84.
- **Verdicts.** The same 12,035 functions, the purity question against the routing question in its
  place, before the package join; then the post-join verdict of every flip, and every caller the join
  stops retracting because a flipped name no longer refutes.
- **Rows.** `discover --include-possible`, plain and seeded, over the 87 seeded source targets, by
  four binaries: `main` (`7e4d8e5e`), this branch, the impure-veto branch (`c8b3c9ed`, PR #721) and
  the two merged. 696 runs per pair of arms, every one exit 0.
- **Verification.** A workflow hand-checked every row the first (broader) build moved, challenged each
  verdict, and reviewed the diff and the TCA surface. Its findings are why this ships narrower.

## Results

### The survey: which tokens are names

| token | functions | real effect | collision |
|---|---|---|---|
| `Task` | 39 | 39 | 0 |
| `.cancel` | 15 | 15 | 0 |
| `await` | 6 | 6 | 0 |
| `.send` | 1 | 1 | 0 |
| static write (hidden mutability) | 1 | 1 | 0 |
| `.run` | 19 | 1 | 18 |
| `Effect` type name | 3 | 0 | 3 |

The `Effect` collisions are all SwiftEffectInference's own lattice enum, which is named `Effect`. The
`.run` collisions are `ParsingStack.run { }`, `LargeStackWorkers.run { }`, `generator.run(using:)`, a
private struct's `mutating run()`, and `MemberRunReader.run(inArrayLiteral:)`.

### The first build, and why it did not ship

The first build narrowed both: outside a file importing ComposableArchitecture, `Effect`-family names did
not refute, and `.run` refuted only on an implicit or `Effect`-family base. It flipped 22 verdicts, the 21
collisions plus `SyntaxStructureProvider.build`. Followed through the package join, the 22 were:

| subject | after the join | what it really does |
|---|---|---|
| SwiftUMLStudio `build` | `.pure` | a SourceKit request, two calls down |
| this repo's `forScan`, and `forJudging` through it | `.pure` | file reads, through member calls |
| SwiftUMLStudio `extract` ×6 | `.pure` | a 64 MB thread per call; on deep `[` nesting a global notice and an `os_log` line |
| `bound`, `layout` | `.refuted` | file and bundle reads, still caught one hop on |
| the rest, 12 | `.pure` | pure |

Three findings from the verification stopped it:
1. **`Process.run()`.** `func launch(_ process: Process) -> Bool { (try? process.run()) != nil }` read
   `.pure`: `Process` is only in the signature, which SEI's marker scan does not read, and the function
   does not throw. `RunLoop.run` is the same shape.
2. **The rows it freed were not safe.** Against the impure-veto branch it brought back 11 rows, and
   5 of them were the impure `extract`s above.
3. **A per-file TCA gate is blind to real TCA layouts:** `@_exported import ComposableArchitecture` in
   one file, an import inside `#if canImport(ComposableArchitecture)`, a kit that re-exports TCA.

### What shipped

`.run` refutes exactly as before. `Effect`, `EffectOf` and `EffectTask` do not refute when `TCAPresence`
finds no sign of TCA **anywhere in the package**: no import of ComposableArchitecture in any universe file,
at any `#if` depth, with any attribute or import kind; and no mention of `composable-architecture` in the
root's `Package.swift`, `Package.resolved`, or an Xcode project's resolved packages. One sign keeps the
routing answer for every file. `SoundPurity.tcaNamesAreTCAs` carries the decision and defaults to `true`,
so a caller that does not know keeps the old answer.

**Verdicts: 3 flip, 3 more through the join, 6 in all, all SwiftEffectInference, all pure.**

| function | how it moves | hand check |
|---|---|---|
| `BodyEffectInferrer.combine(calleeResults:)` | flips | `Effect.lub`, array reductions, a value init |
| `CallSiteEffectInferrer.nameGatedInference(…)` | flips | static-table lookups, syntax parent walks |
| `EffectSymbolTable.effectFromDeclarationShapes(callSite:)` | flips | dictionary lookups into a local set |
| `BodyEffectInferrer.inferEffects(in:parser:resolveCalleeEffect:)` | join stops retracting (`combine`) | in-memory syntax walks; calls only the closure passed in |
| `CallSiteEffectInferrer.resolve(call:imports:enabledFrameworks:)` | join stops retracting (`nameGatedInference`) | lookups and value construction |
| `EffectSymbolTable.effect(for:)` | join stops retracting (`effectFromDeclarationShapes`) | dictionary lookups |

**Rows**, keyed by suggestion identity per repository, target and mode:

| pair | removed | added | rescored |
|---|---|---|---|
| `main` → this branch | 0 | 0 | 0 |
| PR #721 → PR #721 + this branch | 0 | 3 | 0 |

The 3 are seeded `determinism` fallbacks in SwiftEffectInference: `inferEffects`
(`0x4625E86D10CD5ACE`), `combine` (`0xF2F37978163685D6`) and `nameGatedInference`
(`0x9C41E583F097657B`). **Nothing moves against `main` because `main` still has the bypass PR #721
closes:** a seeded subject the template veto suppressed earned the fallback anyway. Two of the three are
`private`, so their stubs cannot call them as written; that is the fallback's existing limitation, not
this change's.

The first build's A/B, for the record: 2 rows against `main` and 11 against PR #721, 5 of the 11 over
the impure `extract`s.

## Not answered

- **No TCA code in the corpus.** None of the 19 trees imports ComposableArchitecture, so "TCA's verdicts
  are unchanged" rests on the construction (one sign keeps the routing answer) and on unit tests of each
  import spelling and manifest, not on a measured TCA app.
- **A TCA re-export the package does not name.** A package that reaches TCA only through a dependency
  that re-exports it, without TCA in its own `Package.resolved`, is read as TCA-free. SwiftPM records
  transitive pins in `Package.resolved`, so this needs a package with no resolved file at all.
- **`.run`'s 18 collisions stay refuted**, 9 of them pure. They come back when the join can see the
  impurities the token now stands in for.
