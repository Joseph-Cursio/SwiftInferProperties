# Does the layering law have a population? — No: two layerings in one repository, and #667's gate is right 1 time in 5 (#667)

> **Status:** `measured` · **As of:** 2026-10-28

#667 asked for a law the catalogue does not have. For a function that assigns each node of a directed graph a
layer, the law is: for every edge `u → v` the layering covers, with `v` unable to reach `u`,
`layer(v) > layer(u)`. Its witness was SwiftUMLStudio's `ActivitySVGRenderer.computeRows`, which at `e36da59`
kept the first row it assigned, so a join could sit level with or above the end of its longer branch.

That defect was filed as SwiftUMLStudio#53 and fixed by that repository's PR #64 (`6033a9f`, 2026-10-13). So
#667's step 1 was done before this pass began. What remained was the gate #667 set before building:

- **step 2**: prototype the law by hand and mutation-score it against the fixed code;
- **step 3**: census the population.

This doc reports both. Everything it rests on was committed in this order, on branch `layering-law-census`:

| step | commit | what |
|---|---|---|
| scope | `b9649973` | `docs/plans/layering-law-census-scope.md`: the cues, the universe, 208 controls, the hand-check, the kill arm, 8 predictions and the decision rule, frozen before the census read any subject or the law ran |
| census instrument | `ad183a2c` | `scripts/layering_census.py`, `fixtures/layering-law/calibration.md`, `fixtures/layering-law/judge-workflow.js` |
| kill-arm instrument | `a1f08f2d` | `scripts/layering_kill_arm.py`, `fixtures/layering-law/LayeringLawTests.swift`, `computeRows-e36da59.swift` |
| amendment 1 | `4bd7bbb3` | the kill arm reads a log that ends inside a UTF-8 character; it resumed after M070 |
| results | `062ce24c` | `fixtures/layering-law/census-2026-10-28.json`, `judgements.json`, `judge-workflow-output.json`, `kill-arm-2026-10-28.json` |
| equivalence | `02686596` | `fixtures/layering-law/equivalence-workflow.js`, `equivalence-2026-10-28.json` |
| this doc | this commit | this doc, both index rows, the scope's status, and F6's annotation in `roadtest-swiftumlstudio-mutation.md` |

**In short: DECLINE (population).**

- The decision universe of 36 subjects holds two layerings, both in SwiftUMLStudio, against a bar of 5 across
  2 repositories.
- The gate #667 proposed is right 1 time in 5.
- On its witness, the hand-written law catches 42 of 91 mutants, against the suite's 54.
- With PR #64's three law-derived tests left out, the law alone catches 4.

```
DECISION: DECLINE (population)  N = 2 over 1 local repositories (bar: ≥ 5 across ≥ 2)  N_gated = 1  gate precision 20%
law-only (reduced suite): 4 by assertion (1 layering, 3 placement), 0 by crash/timeout/memory
law-only (full suite): 1   law 42, suite 54, reduced 51, viable 91   N_unmet 0  N_wide 1  N_undetermined 0
```

## The census

The pass reads every `func` with a body and looks for four cues:

- a NAME word: `layer…`, `rank…`, `topo…`, `row`, `level`, `depth` and others;
- a result SHAPE that can carry a layer per node: `[K: Int]`, `[Int: [T]]`, `[[T]]`, `[Int]`;
- a GRAPH word in its signature or owner;
- a layering phrase in a doc comment.

A function is a candidate in three cases (scope §1):

- NAME holds together with SHAPE or GRAPH;
- its own doc carries a layering phrase;
- its owner's doc carries one, and NAME or SHAPE holds.

A blind hand-check then judges every candidate.

| group | subjects | repositories | files | candidates | LAYERING ∧ EXPRESSIBLE groups |
|---|---:|---:|---:|---:|---:|
| **decision** (#666's manifest and funnel subjects) | 36 | 33 | 4,263 | 23 | **2** |
| unmet | 5 | 5 | 961 | 4 | 0 |
| wide (every other local Swift directory) | 67 | 67 | 12,907 | 16 | 1 |
| **all** | **108** | **105** | **18,131** | **43** | **3** |

44 candidates were found before copies merged. The one copy is `isTopLevel`, which SwiftProjectLint repeats
in two visitors.

**The decision universe holds two layerings, both in SwiftUMLStudio:**

- **`ActivitySVGRenderer.computeRows(graph:) -> [Int: Int]`**, #667's witness, at `c6c82e3`. It is now the
  Kahn layering PR #64 wrote. Judged LAYERING (map), EXPRESSIBLE.
- **`ComponentSVGRenderer.dependencyLevels(for:) -> [[String]]`**, with its helper `chainDepth(of:adjacency:cache:)`.
  The two are judged LAYERING and merge into one group (scope §4.5). `dependencyLevels` is EXPRESSIBLE, with
  result kind *levels*. `chainDepth` is not EXPRESSIBLE, because its depth cache is shared across the calls
  `dependencyLevels` makes. #667 named this function as its control.

So N = 2 over 1 repository, against a bar of at least 5 across at least 2. Two more figures are reported
beside it (scope §8):

- **The unmerged count is also 2.** No layering had a copy.
- **N without EXPRESSIBLE is also 2.** The one non-EXPRESSIBLE layering, `chainDepth`, merges into
  `dependencyLevels`' group.

**The wide group holds the third: sourcekit-lsp's `BuildServerManager.targetDepthsAndDependents`**
(`Sources/BuildServerIntegration/BuildServerManager.swift:1448`, at `a463483a`). Its doc states the law in its
own words: *"The root targets of the project have depth of 0 and all target dependencies have a greater depth
than the target itself."* The judges read it as LAYERING (map), EXPRESSIBLE, with targets unreachable from a root
left out.

- **The cues that found it.** `depths` (NAME) and `[BuildTargetIdentifier: Int]` (SHAPE, the tuple's first
  element) made it a candidate. `dependents` (GRAPH), a word the scope review added, also fired.
- **The gate does not reach it.** Its name has no `layer` or `rank`, and its doc says neither *longest path*
  nor *layering*.

No sensitivity line fires. Adding unmet and wide to N gives 3 groups over 2 repositories. No verdict was
UNDETERMINED. R4's eight SHAPE ∧ GRAPH rows were all judged NOT-LAYERING, and no stratum was sampled.

## The gate #667 names

#667 wrote down the signal a template would read: *"`layer` or `rank` in the name, or a doc comment saying
longest-path or layering. Never accept `level`, `depth` or `distance` alone."* Applied mechanically, it marks 5
decision candidates GATED, and **1 of the 5 is a layering**:

| GATED row | why GATED | verdict |
|---|---|---|
| SwiftUMLStudio `ActivitySVGRenderer.computeRows` | its type's doc: "longest-path layering" | **LAYERING** |
| SwiftUMLStudio `ActivitySVGRenderer.computeColumns` | the same type doc | NOT-LAYERING: it reads the rows and spreads each across columns |
| SwiftUMLStudio `TypeLookup.memberRank` | `rank` in the name | NOT-LAYERING: which lookup scope a name ranks by |
| SwiftAssist `SkillGraphStore.modelTierForSkill` | its type's doc says *layered* | NOT-LAYERING: a database lookup of a model tier |
| SwiftAssist `SkillGraphStore.upsertModelTier` | the same type doc | NOT-LAYERING: a database upsert |

The wide group repeats the pattern: 7 GATED rows, none a layering. exhaust's `ChoiceGraph` doc calls it *a layered
multigraph*, which gates three of its members. `rootLayer` and `buildLayeredContainer` build generators,
`rankedEdges` sorts edges by a score, and lottie-ios's `makeGroupLayers` builds `CALayer`s. The one wide
layering, sourcekit-lsp's, is not GATED.

The gate's precision is **20%**, against the 70% bar `inverse-name-vocabulary.md` used. On the witness's own
type it admits `computeColumns`, the look-alike #667 cited as the reason the shape alone is not enough. The
evidence lives on the type, so the gate passes it to every `[Int: Int]` member of that type. The two
layerings it misses, `dependencyLevels` and sourcekit-lsp's `targetDepthsAndDependents`, both state the law,
but not in #667's words.

## The hand-check

**Calibration first.** Two judges classified the eight items of `fixtures/layering-law/calibration.md` before
any packet, and both matched every expected answer (scope §4.2). That includes the EXPRESSIBLE answer (yes on
items 1 and 3, and no on item 8, the shared-cache depth) and the *body disagrees* flag on the pre-fix
`computeRows`.

**Then 51 rows in 7 packets.** These were the 43 candidates and R4's 8 rows. Two judges read each packet blind,
**and they agreed on every row's verdict and EXPRESSIBLE answer**, so no third judge was needed. No LAYERING
row was flagged *body disagrees*, so nothing is listed for upstream filing (scope §8).

| | LAYERING | TREE-DEPTH | ORDERING | NOT-LAYERING | UNDETERMINED |
|---|---:|---:|---:|---:|---:|
| decision (23) | 3 | 1 | 0 | 19 | 0 |
| unmet (4) | 0 | 0 | 0 | 4 | 0 |
| wide (16) | 1 | 1 | 0 | 14 | 0 |
| R4 (8) | 0 | 0 | 0 | 8 | 0 |

The NOT-LAYERING rows fall into these kinds. Scope §4.4 anticipated syntax nesting, table rows and a
`CALayer`; it did not predict the others.

- **database records named for tiers**: SwiftAssist's model tiers;
- **SwiftUI rows**: `referenceRow`, `symbolRow`, ViewInspector's `listRow…`;
- **syntax and YAML nesting**: `isTopLevel`, `collectTopLevelKeyValues`;
- **depth-first traversals**: swift-package-manager's three `depthFirstSearch` and swift-docc's two;
- **generator "layers"**: exhaust's `rootLayer`;
- **a `CALayer`**: lottie-ios's `makeGroupLayers`;
- **graph colourings**: R4's five pbt-workbook-corpus colourers. The cues did not admit them (SHAPE ∧ GRAPH,
  no NAME and no doc).

The two TREE-DEPTH rows are swift-collections' `_HeapNode.level` (a binary-heap slot's depth) and exhaust's
`ReorderingQuery.nodeDepth` (a parent-pointer depth).

## The kill arm

The law was written by hand as `fixtures/layering-law/LayeringLawTests.swift`. It has three properties, each
checked over 1,000 SplitMix64-drawn graphs:

- **L1**: `computeRows`.
- **L2**: Activity's `computeLayout` `centerY`.
- **L3**: Component's `computeLayout` `centerY`.

`scripts/layering_kill_arm.py` copied it into an export of SwiftUMLStudio at `c6c82e3` and ran every mutant
three ways: under the law, under the full suite less the law, and under the **reduced** suite, which also
drops PR #64's three law-derived tests (scope §5.4). The runner used Xcode 27's Swift 6.4
(`swiftlang-6.4.0.34.1`).

**Every runner control held**, so the run is measured:

| control | what it checks | result |
|---|---|---|
| RC1 | the unmutated export | the law passes: L1 and L2 over 4,145 covered edges, L3 over 2,314. The suite passes 1,823 tests |
| RC2 | `computeRows`' pre-fix body from `e36da59` | the law fails L1 on 538 covered edges and L2 on 405. The full suite fails only PR #64's *a join sits below every predecessor in a loop-free body*. **The reduced suite's 1,820 tests pass**: without PR #64's examples, nothing in the suite sees #53 |
| RC3 | an equivalent `max` swap | both survive |
| RC4 | an unviable edit | reported UNVIABLE, not counted as a kill |
| RC5 | the export's `Sources/` and `Tests/` after the run | hash as before |
| RC6 | the law's summary lines, twice | identical |
| RC7 | a planted hang | TIMEOUT under both |

The run stopped once, after M070, on a log that ended inside a UTF-8 character. The fix and the resume are the
scope's amendment 1. M001–M070 were not run again. M071, which the crash cut short, was run again from the
start.

**91 mutants on the law's call tree, all viable.** The scoped files' other 39 sit in render functions no
layout law reaches, and are counted, not run.

| | mutants | law | full suite | reduced suite |
|---|---:|---:|---:|---:|
| **layering logic**: `computeRows`, `forwardEdges`, `dependencyLevels`, `chainDepth` (with `enter`) | 38 | 37 | 37 | 36 |
| **placement**: both `computeLayout`s, `computeColumns`, `boxSize` | 53 | 5 | 17 | 15 |
| **all** | **91** | **42** | **54** | **51** |

`nodeSize` and `stereotypeLabel` hold no operator the tier rewrites.

- **Law and suite together.** 41 mutants are detected by both, 13 by the suite only, and 36 by neither.
- **Mechanisms.** The law detects 28 by assertion, 11 by crash, 2 by timeout and 1 by memory. The suite's
  figures are 41, 10, 2 and 1.
- **Which properties fail.** Of the law's 28 assertion kills, 14 fail L1 and L2 together, 10 fail L3, and
  4 fail L2 alone.
- **Flakes.** Under §5.4's flake rule, every suite assertion detection beside a law detection was run again,
  and every one repeated. No detection was a flake.

**Law-only against the reduced suite: 4, all by assertion. That is the decisive count.**

| mutant | function | edit | class | full suite |
|---|---|---|---|---|
| M017 | Activity `computeLayout` | `centerY = topMargin + row * …` → `topMargin - row * …` | placement | caught by PR #64's examples only |
| M018 | Activity `computeLayout` | `Double(row) * rowSpacing` → `/ rowSpacing` | placement | caught by PR #64's examples only |
| M020 | Activity `computeLayout` | `height / 2` → `height * 2` in `centerY` | placement | **survives** |
| M035 | `forwardEdges` | `onStack.remove(top.nodeId)` deleted | **layering** | caught by PR #64's example only |

**M035 re-creates #53 by another route.** With the line deleted, a node the depth-first search has finished
stays marked as on the stack. An edge into it, such as a diamond's second branch reaching its join, then reads
as a back edge and is dropped. The join's row then comes from one branch only, which is #53's symptom. In the
full suite, only PR #64's *a join sits below every predecessor in a loop-free body* catches it.
`GraphWalkParityTests` and every other test pass.

**M020 is the one law detection that no test in the full suite makes.** It is the edit the scope's reviewer traced:
height now moves `centerY` by twice the height instead of half, four times as much. Rows are 92 points apart,
a decision node is 60 tall and a fork or join bar is 8. So under M020 a decision sits 12 points *below* a bar
in the next row. No activity test names `centerY`. PR #64's examples see centre order only through the rendered
SVG, which must draw no dashed back-edge, and that check does not fire on their four graphs. M017 and M018
reverse or flatten the rows themselves, and those examples catch both.

**Every suite kill made by one failing test**, by that test:

- *single component is centered horizontally with non-zero size*: 7;
- *layout totalWidth and totalHeight are non-zero*: 2;
- *columns are symmetric around zero for single-node rows*: 2;
- *a join sits below every predecessor in a loop-free body*: 1;
- *two-level dependency places leaf below dependent*: 1;
- *box width scales with the longest label (header or interface)*: 1.

**The 36 mutants neither caught, read for equivalence.** Two readers read each function's survivors
(`fixtures/layering-law/equivalence-workflow.js`; results in `equivalence-2026-10-28.json`), and they agreed on
every one. A refuter then tried to break every EQUIVALENT verdict and every claimed law witness, and failed
each time.

- **2 are equivalent.**
  - M014 removes a `reserveCapacity`.
  - M078 removes `onPath.remove` in `chainDepth`. A node the walk has finished is always answered from the
    cache before `onPath` is read.

  Both stay in the denominator of 91 (scope §5.6).
- **31 change something the law cannot see:**
  - canvas or total size: 13;
  - x-position: 9;
  - box width or height: 3;
  - a centre y whose order across every edge is kept: 5, one of them M021's uniform −40;
  - M019's centre y, whose order flips only between two nodes in one row, which no covered edge joins: 1.
- **3 change a centre-y order the law reads, but only on inputs its generator never draws.** These are M057,
  M058 and M090, and the refuter recomputed one witness for each.
  - M058 needs at least 7 provided interfaces on a component in the dependent's row.
  - M090 needs at least 13 across two adjacent rows, with every component in both rows carrying some.
  - M057 needs at least 14 on a component in the dependency's row.

  The generator draws 0–3. It would have to draw up to 14 for the law to see all three. This is a gap in what
  the generator draws, as in `mutation-reach.md`, not a blind spot of the law.

## The predictions, scored

| # | prediction (scope §7) | result | blind? |
|---|---|---|---|
| 1 | N = 2 merged groups in 1 repository; `chainDepth` LAYERING, not EXPRESSIBLE, merged with `dependencyLevels`: DECLINE (population) | **held** | no |
| 2 | N_gated = 1; gate precision < 70%, with `computeColumns` GATED and NOT-LAYERING | **held** (20%) | no for the witness file; partly for the rest of the universe |
| 3 | N_unmet = 0 and N_wide ≤ 2 | **held** (0 and 1) | partly |
| 4 | ORDERING ≥ 3 in the decision universe, most in swift-package-manager | **missed**: 0. SwiftPM is read only through its manifest target `Basics`, whose three candidates are `depthFirstSearch` traversals. Its topological sorts, in `PackageGraph` and `swift-bootstrap`, are outside the read roots. The `topo` NAME prefix would have admitted them | yes |
| 5 | RC1 holds | **held**: the law passes on all three properties at `c6c82e3`, and the suite passes 1,823 tests | no |
| 6 | RC2 holds, and the reduced suite does NOT detect the pre-fix body | **held**: the law fails L1 on 538 covered edges and L2 on 405. The full suite catches the pre-fix body only through PR #64's *a join sits below every predecessor in a loop-free body*, and the reduced suite's 1,820 tests pass | partly |
| 7 | decisive count ≥ 1; every decisive kill placement, none layering; full-suite law-only layering kills = 0 | **missed**: 4 decisive, and 0 layering kills against the full suite, but M035, a decisive kill, is in `forwardEdges`, so it counts as layering | no |
| 8 | law detections < 0.5 × full-suite detections | **missed**: 42 against 54 (78%). The law is blind to placement as predicted, catching 5 of 53, but 38 of the 91 mutants sit in layering logic, where the law and the suite each catch 37 | no |

## What else the census saw

- **R3, the rows only a doc cue admitted:** one, `computeColumns`, through its type's doc.
- **R2, the neighbours:** 349 non-candidate functions share a file with a candidate. They are listed by id in
  the census JSON and were not judged.
- **Dirty checkouts:** SwiftUMLStudio was asserted clean at `c6c82e3`. Thirteen other subjects had local
  changes, and they were read as they were: swift-collections, harmonize and swift-effect-inference (decision),
  jwt-kit and swift-system (unmet), and eight wide directories. None of their candidates is a layering.

## Disclosures and instrument limits

- **Not blind.** Predictions 1, 2 and 5–8 rest on code read before the freeze, as scope §7 says.
- **The kill arm's tool.** swift-mutation-testing is not installed here. The kill arm re-implements its
  experimental tier, and `parity` shares 118 of its 128 recorded mutants in the scoped files, with the rest
  accounted for (scope §5.3).
- **The cues reach only what they name.** A layering inside a larger function, or in a computed property, is
  missed, as is a coordinate layout named `layout` (scope §9).
- **Local clones only.** The universe has no dedicated graph-layout package, which is the corpus most likely to
  hold the population. That is the reopen condition (§"So what").
- **One subject for the kill arm.** Its counts are SwiftUMLStudio's, against a suite that already holds PR
  #64's examples and `GraphWalkParityTests`. They are not a rate. They compare within this run, not with the
  road test's 1,300 mutants (scope §9).
- **Hand-written generators.** The law's generators are written by hand: 1–9 activity nodes, 1–8 components
  and 0–3 interfaces, drawn by SplitMix64. They are not composed by `DerivationStrategist`. A template's reach
  depends on what it can compose, and this arm does not measure that (scope §9). M057, M058 and M090 are
  misses of this generator.

## So what

- **No template.** #667's law has no population in the decision universe: two layerings, both in
  SwiftUMLStudio. The wide group adds a third, sourcekit-lsp's, outside the decision. The gate it proposes admits four look-alikes for every layering. Under §8, #667 stays open on one
  frozen condition: at least 5 LAYERING ∧ EXPRESSIBLE groups across at least 2 repositories in a corpus of
  graph-layout packages. That corpus needs clones, so it needs the user's approval.
- **As a test SwiftUMLStudio could own, the law is close to redundant today, and the margin it has is real.**
  - It catches 37 of the 38 layering-logic mutants, and so does the suite. Only one of the suite's 37, M035,
    depends on the examples PR #64 wrote for #53. Without them the suite catches 36.
  - Without those examples, the law alone catches M035, a second route to #53's symptom.
  - With them, it alone catches M020, which every test in the full suite misses.
  - Whether to adopt it is SwiftUMLStudio's call. Its file stands alone.
- **The law is blind mostly where the scope said it would be.** It catches 5 of 53 placement mutants. Of the
  34 non-equivalent survivors, 31 change x, sizes or an order the law cannot see. F6's other candidate laws
  (no overlap, endpoints on nodes, size bounds) are what would reach those, and they are still unmeasured. The
  other 3 change a centre-y order the law reads, through component sizes, and its generator never draws large
  enough components. So the scope's "blind to sizes" was too broad.
- **Prediction 8 was wrong in an informative way.** The law is not mainly a placement check that misses. On
  layering logic it matches the suite exactly: 37 to 37. Its weakness is mostly the axis it was never meant to
  cover, plus a generator-reach gap on the y axis it does cover.

## Reproducing

```bash
python3 scripts/layering_census.py run census.json
python3 scripts/layering_census.py packets census.json packets/
# copy packets/packet-*.md and fixtures/layering-law/calibration.md into an otherwise empty directory,
# then run fixtures/layering-law/judge-workflow.js over it and save its result as workflow.json
python3 scripts/layering_census.py join packets/index.json workflow.json judgements.json
git -C ~/xcode_projects/SwiftUMLStudio archive c6c82e3 | tar -x -C export/
python3 scripts/layering_kill_arm.py run export/ kill-arm.json
python3 scripts/layering_census.py decide census.json judgements.json kill-arm.json
# then run fixtures/layering-law/equivalence-workflow.js over the mutants neither the law nor the suite caught
```

The census needs the frozen universe (scope §2) on this machine, and the kill arm needs Xcode 27's Swift 6.4.
