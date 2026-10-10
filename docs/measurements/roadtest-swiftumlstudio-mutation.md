# Mutation road test: the generated property laws vs SwiftUMLBridge (2026-10-10)

> **Status:** `measured` · **As of:** 2026-10-10
> **Question:** where do the generated property laws fail to catch a bug, and which part of the toolchain is responsible?

## Instrument

| | |
|---|---|
| SwiftProjectLint | `2567f79f` (clean, = origin/main), `CLI` debug |
| SwiftInferProperties | `f4bfdad1` (clean, = origin/main), `swift-infer` release |
| swift-mutation-testing | `3be0c11`, release, `--operator-tier experimental` (7 operators) |
| Subject | SwiftUMLStudio `e36da59`, package `SwiftUMLBridge` (98 files, 10.3k lines) |
| Swift | 6.4 (swiftlang-6.4.0.34.1), Xcode toolchain |

## Method

1. `scripts/corpus_funnel.py` over SwiftUMLStudio, **with `NO_COLOR=1`** (finding F1; the driver now sets it itself), in a scratch worktree.
   Result: 336 seeds → 185 any-law / 43 refutable → 50 stubs → 40 compiled → 35 pass, 5 fail. The 5 failing stubs were set aside so the mutation baseline is green.
2. **Run 1 (generated laws only):** mutation run over all 1,300 mutants, testing only `SwiftInferCensusTests`, the 35 passing laws.
3. **Run 2 (hand-written suite):** the same mutants, testing only `SwiftUMLBridgeFrameworkTests`. The sandbox needed three workarounds (finding M1), and 8 tests that cannot pass in a sandbox were disabled.
4. Each mutant was attributed to its innermost enclosing function. That function's furthest funnel stage was read from the seed manifest, the `index` output and each stub's `// Source:` line.
5. **A/B:** a "reaches both outcomes" test was added beside each `predicate` stub, and run 1 was repeated (finding F2).

## Headline

| | Detected | Score |
|---|---|---|
| Run 1: generated laws only (35) | 16 / 1,274 viable | **1.3%** |
| Run 1 + 3 reach tests | 20 / 1,274 | 1.6% |
| Run 2: hand-written framework suite (882 enabled) | 770 / 1,274 | **60.4%** |

Overlap: both suites kill 14 mutants. The hand-written suite alone kills 756, and the generated laws alone kill 2: `compactText`'s truncation branch, which no hand-written test checks. 502 viable mutants survive both suites.

### Bearing on toolchain exit criterion A

[`toolchain-exit-criteria.md`](../design-internal/toolchain-exit-criteria.md) states A-quality as *≥1 emitted law kills a mutant the subject's own tests miss*. This run has two such mutants, both from tool-generated mutants rather than planted ones, and both in `ActivityGraphBuilder.compactText` L200 (`> 80` negated, and `>` → `<`). They are killed by its idempotence law; the hand-written suite has no test of the truncation branch. With the reach check added (F2), a third: `conformsToGRDBRecord` L192 `false` → `true`.

**This is evidence and does not settle the criterion.** The laws ran at the stub default of 100 trials, not the stressed budget A-reach requires. And the hand-written run excluded 8 tests that cannot pass in the mutation sandbox (M1), so "the subject's own tests" is the suite minus those 8. None of the 8 exercise `compactText`.

### Where each mutant's function stopped in the funnel

| Stage | Mutants | Killed by generated laws | Killed by hand-written suite |
|---|---|---|---|
| Not seeded by SwiftProjectLint | 588 | 3 (indirectly) | 360 |
| Only a `determinism` Advisory, so no stub | 460 | 0 | 255 |
| Seeded, nothing proposed | 104 | 0 | 72 |
| Stub written, did not compile or failed | 59 | 0 | 33 |
| Law proposed (Possible), no stub | 38 | 0 | 10 |
| **A law passes** | **51** | **13** | 40 |

**Only 51 of 1,300 mutants (4%) sit in a function that has a passing law.** Where a law does exist, it kills 13 of 51 (25%); the hand-written suite kills 40 of the same 51.

### How strong each template's law is, in the functions that carry it

| Template | Mutants in those functions | Killed by the law |
|---|---|---|
| guard-domain | 22 | 8 |
| idempotence | 15 | 8 |
| **predicate** | **16** | **0** |
| input-totality | 1 | 0 |
| rewrite-postcondition | 1 | 0 |

---

## Findings: SwiftInferProperties

### F1. The funnel compiles 0 stubs on Swift 6.4 (harness defect, high priority)

`scripts/corpus_funnel_stage5.py:376`, `_ERROR = r"^(/[^:]+\.swift):(\d+):(\d+): error: (.+)$"`.
Swift 6.4 colors its diagnostics **even when output is piped**: `…swift:37:92: \e[1;31merror: \e[1;39m'buildCandidates' is inaccessible…`. The regex never matches, so `build_to_fixpoint` finds no stub to blame and returns `unattributed`. The whole package then records `compiled 0 passed 0`.

- Without the fix: `stubs 50 compiled 0 passed 0`. With `NO_COLOR=1`: `stubs 50 compiled 40 passed 35`.
- **Every `XCODE_REPOS` subject in a census taken on Swift 6.4 is suspect.** Swift.org 6.3.3 subjects may not be affected; that is untested.
- **Fixed alongside this doc:** every SwiftPM call in the funnel now goes through `corpus_funnel_stage5.swift_environment`, which sets `NO_COLOR=1`. `corpus_funnel.environment`, and with it `mutation_check.py`, delegates to that helper. This also covers the stage-5 test-output regexes (`_STARTED` / `_PASSED` / `_FAILED`).

### F2. `predicate` emits a totality law, and its generators never reach `true` (high priority)

The `predicate` stub's property is `_ = f(x); return true`. It is labelled ENTAILED, which is true, but for a `Bool` result only a trap can fail it, so it **killed 0 of 16 mutants** in its subjects.

A/B: a test beside each stub, with the same generator, seed and 100 trials, asserting both `true` and `false` were returned:

- **7 of the 10 fail on unmutated code, all returning only `[false]`**: `isStaticOrClass`, `isStatic`, `isAddTaskCall`, `isTaskGroupName`, `hasAttribute`, `isMatching`, `isExcluded`. The generator never produces an input for which the predicate is true. For example, `SwiftInferSyntaxCorpus.gen(DeclModifierListSyntax.self)` never yields `static` or `class`, and the syntax corpus never yields an `addTask` call.
- The 3 that pass (`hasModelAttribute`, `conformsToGRDBRecord`, `pathContainsGlobSyntax`) took run 1 from **16 → 20 kills**, losing none. One new kill, `conformsToGRDBRecord` L192 `false`→`true`, **survives the hand-written suite as well**.

Suggested:
1. Emit an outcome-reach check with every `predicate` stub. Label it a generator-reach claim rather than a law, so a red result reads "generator never reached `true`" and not "bug".
2. Fix reach at the source: seed the syntax-corpus generators with the tokens the predicate body compares against (`.keyword(.static)`, `"addTask"`, `"withTaskGroup"`, attribute names). These are literal operands found in the body, the same signal as F4.

### F3. Idempotence passes for functions that became a constant or the identity

`dedupe(relationships:)`: removing `seen.insert(key)` turns the function into the identity, negating `!seen.contains(key)` makes it return `[]`, and removing `result.append` also returns `[]`. All three mutants pass `f(f(x)) == f(x)`, and the hand-written suite kills them. The same pattern shows up in `sanitizeType` L178 (SwapTernary makes it constant `"Unknown"`).

There is also a generator problem. `dedupe`'s key is built from random `letterOrNumber` strings of 0–8 characters, so **duplicate keys essentially never occur**: the input the function exists for is never generated.

Suggested:
1. Pair idempotence with an observed non-triviality check: some drawn `x` has `f(x) != x`, and `f` is not constant over the draws. Again, this is a reach claim.
2. For `dedupe` / `unique` / `distinct` names, and array-of-composite parameters in general, apply `CollisionBias` at the element level: draw from a small pool, or duplicate drawn elements.

### F4. Generators miss the boundary values in the subject's own comparisons

| Subject | Body comparison | Generator | Survivor |
|---|---|---|---|
| `compactText` | `collapsed.count > 80` | strings of length 0 to roughly 12 | `>` → `>=` (survives both suites) |
| `renderEdge` | `edge.points.count >= 2` | `LayoutEdge(sourceId:targetId:label:style:)`, never sets `points` | 10 of 13 mutants, 3 of them survive both suites |

`renderEdge`'s guard-domain law only ever exercises the early return, because `points` is always empty. Suggested: a boundary pass that reads integer literals compared against `.count` or parameters in the body and draws `n-1, n, n+1`. The verify edge pass already has this idea in its advisory pass; it is not in the stubs. For a `var` that no initializer sets, the composite generator should assign it after construction.

### F5. Guard-domain checks only the guarded branch

`renderSVG`'s guard-domain law checks the empty-layout early return. Every `lines.append(…)` RemoveSideEffects mutant in the non-guarded path survives (1 survives both suites: `lines.append(arrowMarkerDefs)`). This is the expected behavior of the template; it is listed so it is not mistaken for coverage.

### F6. The layout and render functions get only a `determinism` Advisory (460 mutants)

`computeLayout`, `computeRows`, `edgePoint`, `componentSVGLines`, `renderMessage`, `renderForwardEdge`/`renderBackEdge`, `buildMermaidText`, `traverse`. This is the largest single stage and the core of the library; the hand-written suite kills 255 of these mutants. No template proposes anything refutable for geometry. Candidate laws: node rectangles do not overlap, every edge endpoint lies on a node, total size bounds every node, output order is stable under input permutation. This is a catalogue gap, not a filter problem.

### F7. Smaller items

- A stub for a `private` subject was still emitted (`StateMachineExtractor.buildCandidates`, `sorted-output`). The fixpoint set it aside, but with F1 present it took the whole package down.
- 38 mutants sit in functions with only a Possible-tier proposal (`mutator-idempotence`, `idempotence`), which `--interactive` never offered. Examples: `DagreLayoutEngine.fallbackLayout`, `sizeNodes`, `applyEdgePoints`.

## Findings: SwiftProjectLint (seeding)

588 mutants (45%) are in functions with no seed, and the hand-written suite kills 360 of them. The largest unseeded functions fall into four groups. These shapes are observed; **the rule that refuses each one was not traced**.

| Shape | Example | Mutants the hand-written suite kills |
|---|---|---|
| Method on a `class` that reads its configuration | `DiagramContext.relationshipLabel(for:)`, `addLinking` | 14 + 6 + 12 |
| Method with no parameters on a value type (`self` is the input) | `PageTexts.plantuml()` | 20 |
| Constrained extension on a stdlib type | `extension Array where Element == SyntaxStructure { mergeExtensions }` (same family as #214) | 8 + 7 |
| Function with a class-typed parameter | `SyntaxStructure.renderableMember(from:context: DiagramContext)` | 17 |

`PageTexts.plantuml()` and `mergeExtensions` look like the clearest seeding gaps: both are pure value transforms.

## Findings: swift-mutation-testing

- **M1. The sandbox breaks suites that use fixtures.**
  1. The sandbox symlinks every unchanged file (`SandboxFactory.writeFile`). SwiftPM's `.copy("TestData")` keeps those links, so a test that enumerates fixture `.swift` files finds none (5 `FileCollectorTests`).
  2. Only the package directory is copied, so tests that walk up from `#filePath` to repo-level fixtures fail (14 tests). Worked around by copying `TestFixtures/` to `$TMPDIR/swift-mutation-testing/`.

  Suggested: an option to copy resource directories instead of linking them, and an option to include paths from outside the package (or to sandbox from the git root). The baseline error already names `#filePath`; it could also name the symlink cause.
- Progress output is buffered when piped, so a background run shows nothing until testing starts.

## Findings: SwiftUMLBridge (the subject)

- 3 Glob/FileCollector tests fail when the package path goes through a symlink (`/tmp` → `/private/tmp`), even outside the sandbox. They pass in the real checkout. The likely cause is a glob or path prefix comparison that is not canonicalized. Related to, but distinct from, the escape-class defect in [`roadtest-swiftumlstudio.md`](roadtest-swiftumlstudio.md).
- `compactText`'s truncation at 80 characters has no hand-written test. The generated idempotence law is the only thing that kills mutants there.

## What would move the numbers most

1. **F1** (fixed here): re-take any census run on Swift 6.4 before trusting its compile counts.
2. **F6 + seeding gaps**: 1,048 of the 1,300 mutants are in unseeded or determinism-only functions. Laws that kill are worth little while only 4% of mutants sit near one.
3. **F2 / F3 / F4 together** are one idea: *a law must be shown to reach the inputs that make it bite*. Each comes with a cheap check (outcome reach, non-triviality, boundary draw), and the A/B shows the check pays off immediately where the generator already reaches both outcomes.

Ten candidate laws aimed at this run's survivors are in [`docs/ideas/laws-from-mutation-survivors.md`](../ideas/laws-from-mutation-survivors.md).

## Reproduce

**The per-mutant attribution is kept** in [`fixtures/mutation-check/roadtest-swiftumlstudio-2026-10-10.jsonl`](../../fixtures/mutation-check/roadtest-swiftumlstudio-2026-10-10.jsonl): one row per mutant, 1,300 rows, the source of the funnel-stage table above. Each row has these fields:

- `file`, `line`: where the mutant is, relative to `SwiftUMLBridge/`.
- `func`, `funcStart`: its innermost enclosing function, found by brace matching (`null` when there is none).
- `operator`, `original`, `replacement`: the mutation.
- `status`: the run 1 outcome, against the 35 passing generated laws.
- `baseline`: the run 2 outcome, against the hand-written suite. A `Timeout` counts as detected.
- `stage`: the furthest funnel stage the enclosing function reached.
- `seedKinds`, `laws`, `passingStubs`, `otherStubs`: what that stage was read from.

The reach A/B (run 1 with the 3 reach tests added) is not in it. The rest of the run's artifacts lived in a session scratchpad and are **not** kept: the two mutation reports, the logs, the stubs and the attribution script. To repeat it:

1. `python3 scripts/corpus_funnel.py <scratch> $PWD/.build/release/swift-infer <abs path to SwiftProjectLint>/.build/debug/CLI SwiftUMLStudio`
2. Move the stubs that fail out of `<scratch>/trees/SwiftUMLStudio/SwiftUMLBridge/Tests/SwiftUMLBridgeFrameworkTests/Generated/SwiftInfer/`, then in `SwiftUMLBridge/` run
   `swift-mutation-testing . --sources-path Sources --operator-tier experimental --target SwiftInferCensusTests --no-cache --output pbt.json`
3. In a second clean worktree, run the same with `--target SwiftUMLBridgeFrameworkTests`. First copy `TestFixtures/` to `$TMPDIR/swift-mutation-testing/` and disable the 8 sandbox-incompatible tests named under M1 and the subject findings.
4. Attribution: map each mutant's `location.start.line` to its innermost enclosing function, then join on the seed manifest (`file` + line within the function), the `index` entries (`location`) and each stub's `// Source:` line. The script that did this was not committed.
