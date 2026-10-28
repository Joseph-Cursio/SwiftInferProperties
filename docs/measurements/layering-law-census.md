# Does the layering law have a population? — In a graph-layout corpus, yes: 15 groups across 5 repositories; but #667's gate is right on about 1 row in 9 it admits (#667)

> **Status:** `measured` · **As of:** 2026-10-28
>
> **Two runs, both 2026-10-28.** The local universe gave DECLINE (population), with 2 groups in one repository.
> Its frozen reopen condition, a corpus of graph-layout packages, gave **DECLINE (gate precision)**: the
> population exists, but only 11% of the rows #667's gate admits (16 of 149) are layerings. §"The reopen
> condition" reports the second run. Under that scope's §4, #667 closes once the user approves.

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
| this doc | `8cad032c` | this doc, both index rows, the scope's status, and F6's annotation in `roadtest-swiftumlstudio-mutation.md` |
| corpus mode | `e4d7ad38` | `run-corpus`, `decide-corpus` and R5 in `scripts/layering_census.py`; 255 controls |
| corpus scope | `a330611b` | `docs/plans/layering-law-graph-layout-corpus-scope.md`: 18 clones, the corpus alone deciding, 8 predictions, frozen before any corpus file was opened |
| corpus results | `5cc86d1d` | `fixtures/layering-law/census-graph-layout-2026-10-28.json`, `judgements-graph-layout.json`, `judge-workflow-output-graph-layout.json` |
| corpus re-read | `f2e37d51` | `fixtures/layering-law/reread-workflow.js`, `reread-graph-layout-2026-10-28.json` |
| corpus write-up | this commit | §"The reopen condition", both index rows, and the corpus scope's status |

**In short: DECLINE, twice, for two different reasons.**

- **The local universe: DECLINE (population).** Its 36 decision subjects hold two layerings, both in
  SwiftUMLStudio, against a bar of 5 across 2 repositories. The gate #667 proposed is right 1 time in 5.
- **The graph-layout corpus, #667's reopen condition: DECLINE (gate precision).**
  - 18 packages hold 15 LAYERING ∧ EXPRESSIBLE groups across 5 repositories, or 12–13 after an adversarial
    re-read, so the population exists.
  - The gate is right on 16 of the 149 rows it admits.
  - The cues cannot see any of ELK's five working layerer classes.
- **The law on its witness.** The hand-written law catches 42 of 91 mutants, against the suite's 54. With PR
  #64's three law-derived tests left out, the law alone catches 4.
- **Four layering defects, reproduced and filed upstream.** Reading the corpus turned up four. Each then
  reproduced on the real code at upstream HEAD, and is filed (tracked in #687):
  - **lukilabs/dagre-swift#1:** a porting defect in the undirected `setEdge`, which leaves a network-simplex
    DAG edge at equal or reversed rank, and shows through `layout()`;
  - **2389-research/MermaidKit#102:** C4 rows, where an edge below a cycle points up;
  - **#103:** clustered flowcharts, which draw an edge upward, perhaps by design;
  - **#104:** a latent defect in `assignLayers`, whose doc says self-edges are ignored when they are not.

The first run's decision line:

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
- **Local clones only.** The local universe has no dedicated graph-layout package. That was the reopen
  condition, measured in §"The reopen condition".
- **One subject for the kill arm.** Its counts are SwiftUMLStudio's, against a suite that already holds PR
  #64's examples and `GraphWalkParityTests`. They are not a rate. They compare within this run, not with the
  road test's 1,300 mutants (scope §9).
- **Hand-written generators.** The law's generators are written by hand: 1–9 activity nodes, 1–8 components
  and 0–3 interfaces, drawn by SplitMix64. They are not composed by `DerivationStrategist`. A template's reach
  depends on what it can compose, and this arm does not measure that (scope §9). M057, M058 and M090 are
  misses of this generator.

## The reopen condition: a graph-layout corpus (2026-10-28)

The first run's §8 kept #667 open on one frozen condition: at least 5 LAYERING ∧ EXPRESSIBLE groups across at
least 2 repositories in a corpus of graph-layout packages. `docs/plans/layering-law-graph-layout-corpus-scope.md`
built that corpus and was frozen at `a330611b`, before any corpus file was opened. Two adversarial reviews
reshaped it first. Its rules differ from the first run's in four places:

- **The corpus alone decides.** SwiftUMLStudio's two groups are reported beside the decision, never in it.
- **Every candidate is judged.** There is no sampling above 300.
- **Lines beside the decision:** the layout packages only, the groups by kind, and the owners, with
  same-owner, same-name groups merged.
- **R5,** a list of role-named declarations.

### The corpus

These are 18 public packages, found by a GitHub search that read names and descriptions only. The user approved
them, and they were cloned `--depth 1` on 2026-10-28 (scope §2.1):

- **10 layout packages:** dagre-swift and elk-swift (lukilabs), beautiful-mermaid-swift (lukilabs), MermaidKit,
  swift-mermaid, DirectedGraph, swift-flow, SwiftFlow, Graffle and SwiftGraphvizLayout;
- **6 dependency tools:** swift-module-graph, spmgraph, dependency-graph, TuistSpider,
  SwiftDependencyGraphExplorer and swift-package-graph;
- **2 commit-graph drawers:** Maple and GitGraphRender.

```
DECISION: DECLINE (gate precision)  N = 15 over 5 local repositories (bar: ≥ 5 across ≥ 2)  N_gated = 11  gate precision 11%
law-only (reduced suite): 4 by assertion (1 layering, 3 placement), 0 by crash/timeout/memory
law-only (full suite): 1   law 42, suite 54, reduced 51, viable 91   N_unmet 0  N_wide 0  N_undetermined 0
```

The kill lines are the first run's report. The scope pins it by hash and reads it unchanged (scope §2.3).

**What the census found:**

- **Files read:** 1,270 after the skip rule.
- **Candidates:** 208 before the copy merge and 188 after, in 9 of the 18 packages. All 188 were judged, with
  R4's 24 rows, in 27 packets.
- **Calibration** passed, and one row went to a third judge, on EXPRESSIBLE.
- **Final verdicts:** 161 NOT-LAYERING, 22 LAYERING, 3 ORDERING, 2 TREE-DEPTH, 0 UNDETERMINED. R4 has no
  layering.
- **The copy merge:** it merged 20 rows.
  - **18 are dagre-swift's.** swift-mermaid vendors dagre-swift under `Vendor/MermaidLayoutDagre/`, and
    `Vendor` is not a skipped folder. Every one of dagre-swift's 18 candidates is byte-identical to its vendored
    copy, so each counts once. `Australware__swift-mermaid` sorts first, so dagre's longest-path and
    network-simplex rankers count under swift-mermaid's name.
  - **2 are MermaidKit's.** Its ER and state-diagram `layout` wrappers (`DiagramLayoutBoxDiagrams.swift:103`
    and `:188`) are textually identical to the class-diagram one at `:22`, although each forwards to its own
    overload.

### The population exists

| repository | group (functions) | kind | GATED | re-read (below) |
|---|---|---|---|---|
| MermaidKit | `assignLayers`, `longestPathLayers`, `networkSimplex` | map | yes | holds; `assignLayers` flagged *body disagrees* (self-edges), one EXPRESSIBLE dissent on `networkSimplex` |
| MermaidKit | `layeredRoutes` | coordinate | yes | holds |
| MermaidKit | `layout`, class diagrams (the ER and state wrappers merged as copies) | coordinate | yes | holds |
| MermaidKit | `layout`, Sankey | coordinate | yes | holds |
| MermaidKit | `layout`, swimlane | coordinate | no | holds |
| MermaidKit | `layout`, C4 | coordinate | yes | holds, *body disagrees* |
| MermaidKit | `layout`, flowchart | coordinate | yes | **disputed**, *body disagrees* |
| swift-mermaid | `assignRanks` (its own flowchart ranker) | map | yes | holds |
| swift-mermaid | dagre's `LongestPath.run` | map | yes | holds |
| swift-mermaid | dagre's `NetworkSimplex.run` | map | no | holds, *body disagrees* (a defect, below) |
| swift-module-graph | `depthLevels`, `depth` | levels | no | holds |
| elk-swift | `OrthogonalRoutingGenerator.topologicalNumbering` | coordinate | no | holds |
| elk-swift | `NetworkSimplex.execute()` | map | yes | **refuted** |
| elk-swift | `NetworkSimplex.execute(_:)`, `balance` | map | yes | **refuted** |
| Graffle | `GraphLayout.layered`, `depth` | map | yes | holds |

The lines beside the decision all clear the population half too, so scope §4 asks the decision paragraph to
disclose nothing:

- with the witness's first-run groups: 17 over 6;
- layout packages only: 14 over 4;
- by kind: 14 layout, 1 dependency, 0 commit;
- repositories counted by owner: 5;
- same-owner, same-name groups merged: 9 over 5 owners.

The unmerged count is 21. N without EXPRESSIBLE is 17.

### The gate admits too much

#667's gate admits 149 decision rows, and 16 are LAYERING: **10.7% precision**, against a bar of 70%. It does
reach most of the population: 11 of the 15 groups have a GATED member, over 4 repositories, so the signal half
clears. Precision decides. In the 10 layout packages alone, the gate admits 129 rows, of which 16 are layerings
(12.4%). It admits two kinds of look-alike:

- **elk-swift:** 98 GATED rows, 4 of them judged LAYERING, and the re-read refutes 2 of those. ELK's layered pipeline is built around a `Layer` type, so its
  setters, sweeps, port ranks and crossing-minimisation steps are all named for layers.
- **TuistSpider:** 20 GATED rows, none LAYERING. There, "layer" is an architecture-layer label a user assigns to a
  module.

Of the 133 GATED rows that are not LAYERING, the judges gave 48 the reason *reads a layering*. The first run's
gate was right on 1 row in 5 it admitted. On a corpus chosen for graph layout it is right on 1 in 9. Layout code
names much of its API after layers, and one dependency tool uses "layer" as an architecture label.

### What the census cannot see: ELK's layerers (R5)

R5 lists 22 role-named declarations. Twenty of them belong to nine distinct elk-swift type names that end in
`Layerer`:

- **Five are implemented:** `LongestPath`, `LongestPathSource`, `NetworkSimplex`, `Interactive` and
  `BreadthFirstModelOrder`. Each does its layering in a `process(_:)` method that mutates an `LGraph`.
- **Four are unported stubs:** `CoffmanGraham`, `MinWidth`, `StretchWidth` and `DepthFirstModelOrder`. Each
  class holds only an `init`, and its `process` is an empty body in an extension.

**None of the nine `process` methods is a candidate:** none has NAME or SHAPE, and none has a layering phrase in
its own doc comment. ELK's layering reached the census only twice:

- through an orthogonal-routing slot numbering, `topologicalNumbering`;
- through its general network-simplex solver, which the re-read refutes.

The other two R5 declarations are dagre's `LongestPath` enum and its vendored copy, which the census does reach.
In the corpus's richest layout engine, then, a template keyed on these cues would see none of the five working
layerers, although the gate admits 98 of ELK's other functions. This is the first scope's §9 limit, measured.

### The re-read, beside the decision

Three refuters re-read each of the 17 rows judged LAYERING ∧ EXPRESSIBLE, and two counterexample builders took
each row on the *body disagrees* line (`fixtures/layering-law/reread-workflow.js`). They could read the row's
repository and run Python models, but never build or run its code.

| outcome | rows |
|---|---|
| **confirmed by all three** | 10: MermaidKit's `longestPathLayers`, `layeredRoutes` and the class, Sankey and swimlane `layout`s; swift-mermaid's `assignRanks` and dagre's `LongestPath.run`; `depthLevels`; `topologicalNumbering`; Graffle's `layered` |
| **confirmed by all three, and all three flag *body disagrees*** | MermaidKit's `assignLayers`. Its doc says self-edges are ignored, but it passes them to `longestPathLayers`, which then cannot keep an off-cycle edge strict. The defect is latent, because every caller strips self-loops first |
| **confirmed, with one dissent** | MermaidKit's `networkSimplex`. One refuter says EXPRESSIBLE fails, because the function needs a feasible ranking on entry |
| **LAYERING with *body disagrees*, all three** | MermaidKit's C4 `layout`, voted UNSURE ×3, each vote saying the classification stands with the flag; and dagre's `NetworkSimplex.run`, voted CONFIRMED, UNSURE, CONFIRMED, where all three found the same defect (below) |
| **refuted, all three** | both rows of ELK's `NetworkSimplex.execute`. It is a general difference-constraint solver, with `layer(t) − layer(s) ≥ delta` and `delta ≥ 0`, and ELK uses it for node placement as well as layering. Its contract is not strict |
| **disputed, three votes NOT-LAYERING** | MermaidKit's flowchart `layout`. A chart with subgraphs takes `layoutClustered`, which breaks the layering the doc states. The refuters would judge `layoutFlat` instead. Under the first scope's §4.4, a stated contract whose body contradicts it stays LAYERING, flagged |

Two consequences:

- **After the re-read, N is 12 or 13, over the same 5 repositories.**
- **Gate precision falls to 13 or 14 of 149** over the rows the re-read covered. ELK's `balance` and
  `layeringTopologicalNumbering` are GATED LAYERING rows of the same solver, under the same `delta ≥ 0`, but
  were not re-read because they are not EXPRESSIBLE. Carrying the refutation to them gives 11 or 12, about 8%,
  and none of ELK's 98 GATED rows a layering.
- **The frozen outcome does not move.**
- **Two instrument quirks, pulling opposite ways.**
  - ELK's `execute()` only forwards to `execute(_:)`. The helper merge works by name, and a function never
    counts its own name as a callee, so two overloads never merge. Read as one row, N would have been 14 before
    the re-read.
  - The copy merge joins MermaidKit's three identical `layout` wrappers, so only the class-diagram one was
    judged. Judged separately, the ER and state wrappers might have added up to 2 groups. That was not measured.

### Defects the law points at, reproduced and filed

All four came from reading and from Python models. On 2026-10-28, with the user's approval, each was reproduced
by an XCTest on a scratch copy of its package, built with Swift 6.4 (Xcode 27). Every control passed. The
revisions are the corpus scope's §2.1 revisions, which were still upstream HEAD. The tests and the patches are in
`fixtures/layering-law/upstream-repro/`. All four are filed, and Joseph-Cursio/SwiftInferProperties#687 tracks
them.

1. **dagre-swift, `Graph.setEdge` on an undirected graph**: lukilabs/dagre-swift at `92efb78`,
   `Sources/SwiftDagre/Graph/Graph.swift:246–276`. Also in Australware/swift-mermaid at `ee4b50b`,
   `Vendor/MermaidLayoutDagre/Graph/Graph.swift`.
   - **The defect.** It normalises the edge id to `(min, max)`, then appends that id under the endpoints as
     passed: `_out[v]`, `_in[w]`. graphlib's JavaScript reassigns `v` and `w` from the normalised edge first.
     So a tree edge added with `v > w` drops out of `neighbors`, and `removeEdgeById` clears the wrong lists.
   - **Why ranks go wrong.** Network simplex works on an undirected tight tree. With the tree walked as a
     forest, cut values go stale, `enterEdge` can pick a tree edge, and `updateRanks` can leave a DAG edge at
     equal or reversed rank.
   - **Evidence.** All three refuters of dagre's `NetworkSimplex.run` found it independently, each with its own
     counterexample:
     - a 7-node DAG on which `a → h` ends at equal rank;
     - a 9-node DAG on which `b → c` ends at equal rank;
     - a 9-node DAG on which `rh → fz` goes from rank −1 to −2.

     Their Python models of the port give 5 violations in 150,000 random DAGs, 1 in about 9,800, and 2 in
     6,000. With the adjacency fixed, the first model gives none.
   - **Reproduced.** All three DAGs give exactly the refuters' ranks.
     - `neighbors()` misses a reversed undirected edge, and `removeEdge` leaves it behind.
     - Through the public `layout()`, the second DAG draws `b` and `c` at one height (y 290).
     - With graphlib's reassignment (a 3-line patch), every case comes out feasible, and all 89 tests pass: the
       package's 83 and the 6 new ones.
     - Random graphs hit it in none of 20,000 rank runs and none of 3,000 layouts.
   - **Filed** as lukilabs/dagre-swift#1. swift-mermaid's vendored `Graph.swift` is byte-identical, and is not
     filed separately.
   - **Why it matters.** This is the layering law pointing at a real defect in a corpus subject, and at a low
     rate. A generated test would need the right shape of graph to see it.
2. **MermaidKit's C4 `layout`**: 2389-research/MermaidKit at `64c19fb`,
   `Sources/MermaidLayout/DiagramLayoutC4.swift:66`. Rows are longest-path depths, capped so that cycles
   terminate. On `a → b`, `b → a`, `b → c`, the off-cycle edge `b → c` does not descend. Both counterexample
   builders found it.
   - **Reproduced.** C sits at y 28, above B at 142. Without `b → a`, the rows are A 28, B 142, C 256.
   - **The fix** is to drop DFS back edges first, as flowcharts do. With it, C4 descends and the rest of
     `MermaidLayoutTests` passes.
   - **Filed** as 2389-research/MermaidKit#102.
3. **MermaidKit's flowchart `layout`**: MermaidKit at `64c19fb`,
   `Sources/MermaidLayout/DiagramLayoutFlowchart.swift:102`. Take `flowchart TD` with a subgraph `S` holding `X`
   and `Y`, and edges `X → A → Y`. `layoutClustered` draws an edge upward. Both builders found it. It may be a
   known limit of cluster layout rather than a bug.
   - **Reproduced.** A sits at y 12, with X and Y at 136. Flat, the rows are 12, 102 and 192.
   - **Filed** as MermaidKit#103, as a question with no fix.
4. **MermaidKit's `assignLayers`**: MermaidKit at `64c19fb`, `Sources/MermaidLayout/DiagramLayoutLayering.swift:19`.
   - **The defect.** Its doc says self-edges are ignored, but it passes them to `longestPathLayers`, which
     relaxes a self-edge on every pass. On ids `[x, y]` and edges `x → y`, `x → x`, it returns `x = 3`, `y = 3`.
   - **Why it is latent.** Every caller strips self-loops first.
   - **Evidence.** All three refuters flagged it.
   - **Reproduced.** It returns `{x: 3, y: 3}`, and `{n0: 0, n1: 1, n2: 1}` on three ids. The public flowchart
     layout with self-loops is unaffected.
   - **The fix** is to skip self-edges in `longestPathLayers`, one line. With it, `MermaidLayoutTests` passes.
   - **Filed** as MermaidKit#104.

Items 2 and 3 are the two rows on the frozen *body disagrees* line. Items 1 and 4 come from the re-read.

### The corpus predictions, scored

| # | prediction (corpus scope §6) | result |
|---|---|---|
| 1 | the population clears on the corpus alone, with N between 5 and 12 | **missed on the range**: it clears, but N = 15 (12–13 after the re-read) |
| 2 | it also clears on layout packages only, and with repositories counted by owner | **held**: 14 over 4, and 5 owners |
| 3 | gate precision below 70% | **held**: 10.7% |
| 4 | DECLINE (gate precision) | **held** |
| 5 | ≥ 3 elk-swift `…Layerer` type names, ≥ 3 of them with a `process` that is not a candidate | **held**: 9 and 9 under its frozen rule; 5 and 5 if only the implemented layerers count |
| 6 | ORDERING ≥ 3 | **held**: 3 |
| 7 | more than 300 decision candidates | **missed**: 188 |
| 8 | N_undetermined ≤ 3, and an empty *body disagrees* line | **missed**: 0 undetermined, but 2 rows flagged |

Five of eight held. Prediction 7 overrated how often layout code puts a layering cue on a function. R5 is one
instance of that, since ELK's layerers carry the cue on their type. But it accounts for a few dozen functions at
most, not the 112 by which the prediction missed.

### Disposition

**DECLINE (gate precision).** The reopen condition's population exists: 15 groups across 5 repositories, or 12–13
after the re-read. But the gate #667 proposes is right on 16 of the 149 rows it admits, and the cues reach none
of ELK's five working layerers. Under the corpus scope's §4, #667 closes. Closing it and commenting on it are
the user's to approve.

**Not answered here:**

- the kill arm's counts are still SwiftUMLStudio's alone;
- the corpus figures are counts over what a search found, not rates;
- the four defects were reproduced only on the inputs shown; no rate is claimed for any of them.

## So what

- **No template.**
  - **Locally, there is no population.** The local universe has two layerings, both in SwiftUMLStudio. The wide
    group adds a third, sourcekit-lsp's, outside the decision.
  - **In a graph-layout corpus there is one.** It has 15 groups across 5 repositories (§"The reopen
    condition"), 14 across 4 in the layout packages alone.
  - **The gate is what fails.** It admits four look-alikes for every layering locally, and eight for every one
    in the graph-layout corpus (seven in its layout packages). Its cues reach none of ELK's five working
    layerers.
  - **#667 closes under the corpus scope's §4.** A template for this law would need a different gate: one that
    reads a layering's role off its type, or off the graph it mutates, not off a function's name.
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

The graph-layout corpus (corpus scope §2.1) reruns as:

```bash
python3 scripts/layering_census.py run-corpus census.json   # the 18 clones at their frozen revisions
python3 scripts/layering_census.py packets census.json packets/
# judge as above, then join
python3 scripts/layering_census.py decide-corpus census.json judgements.json fixtures/layering-law/kill-arm-2026-10-28.json
# then run fixtures/layering-law/reread-workflow.js over the rows judged LAYERING and EXPRESSIBLE
```

The four defects reproduce from `fixtures/layering-law/upstream-repro/`. Copy each `.swift` file into that
package's test target, at `92efb78` for dagre-swift (`Tests/SwiftDagreTests/`) and at `64c19fb` for MermaidKit
(`Tests/MermaidLayoutTests/`). Run `swift test --filter` on its class, then again with the patch beside it
applied.

The census needs the frozen universe (scope §2) on this machine, or the 18 clones for the corpus, and the kill
arm needs Xcode 27's Swift 6.4.
