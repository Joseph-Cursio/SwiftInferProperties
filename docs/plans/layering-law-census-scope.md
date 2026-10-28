# Does the layering law have a population, and does it catch what a suite misses? (#667)

> **Status:** `shipped` · **As of:** 2026-10-28
>
> **Run 2026-10-28. Result: DECLINE (population), N = 2 over 1 repository. Written up in
> `docs/measurements/layering-law-census.md`.** The rule below is as frozen at `b9649973`. One dated amendment
> changed the kill arm's log reading, and no outcome rule.

#667 asks for a law the catalogue does not have. For a function that assigns each node of a directed graph a
layer, the law is:

> for every edge `u → v` the layering covers, with `v` unable to reach `u`, `layer(v) > layer(u)`.

It applies to a `graph -> [ID: Int]` map or to a layout's `centerY`. Reachability is computed over the input
graph, so the law says nothing about an edge on a cycle.

**What is already settled.** #667's witness was `ActivitySVGRenderer.computeRows` in SwiftUMLStudio's
`SwiftUMLBridge`. At `e36da59` it kept the first row it assigned to a node, so a join could sit level with or
above the end of its longer branch. #667 confirmed this by running a test. It was then filed as
SwiftUMLStudio#53 and fixed by that repository's PR #64 (merged 2026-10-13 as `6033a9f`). The fix lays rows out
by Kahn's algorithm over the edges a DFS from the start keeps. PR #64 also added `ActivityRowLayeringTests`,
whose `everyEdgeDescends` and `deadLoopIsIgnored` assert the law on #667's own example graphs. So #667's
step 1 is done, and the fix was the author's call, as #667 said it should be.

**What remains is #667's gate, steps 2 and 3:**

- **Step 2.** Prototype the law by hand and mutation-score it against a **fixed** `computeRows`, scoped to
  `ActivitySVGRenderer*.swift` and `ComponentSVGRenderer.swift`. The baseline must be green. Upstream now has
  the fix, so this scores it against SwiftUMLStudio `c6c82e3` (2026-10-27), which includes PR #64 (§5).
- **Step 3.** Census the population before building, as the census comment on #645 did (§1–§4).

This scope freezes both arms, the predictions and the decision before the census reads any subject and before
the law runs. §10 lists everything read, written and run before the freeze.

**The census counts layering producers its cues can reach.** A layout that turns layers into coordinates is
counted only when a cue names it (§9). The kill arm, by contrast, also scores the law over `centerY`.

---

## 1. The census pass

`scripts/layering_census.py`. Section numbers in its comments are this scope's.

### 1.1 The unit

The unit is each `func` with a body that the reused scanner finds (`budgeted_truncation_census`'s `FUNC`,
`DECL`, masking, `parameters()` and `result_head()`). Computed properties, subscripts and initialisers are not
units (§9). `class` followed by `func`, `var`, `let`, `subscript`, `init`, `static`, `final`, `override`, an
access level, `convenience`, `required` or `deinit` is a modifier, not a type, so it is never a function's
owner.

A function's **words** are what `budgeted_truncation_census.words()` makes of its base name: lowercased runs,
where a run of capitals before a capitalised word is one word (`DAGNode` → `dag`, `node`), and underscores and
digits separate (`layer_2Of` → `layer`, `2`, `of`).

### 1.2 Four cues

- **NAME.** A word that:
  - starts with `layer`, `rank`, `tier`, `stratif`, `topo`, `sugiyama` or `coffman`; or
  - is one of `row`, `rows`, `level`, `levels`, `depth`, `depths`, `stratum`, `strata`;

  or the adjacent words `longest` `path`.
- **SHAPE.** The result's head (a tuple's first element), with `?`, `!`, `throws`, `async` and `where`
  removed, is one of these:
  - `[K: I]` or `Dictionary<K, I>`;
  - `[I: G]` or `Dictionary<I, G>`;
  - `[G]` or `Array<G>`;
  - `[I]` or `Array<I>`.

  `I` is an integer type (`Int`, `UInt`, their sized forms, optionally `Swift.`-qualified). `G` is a group:
  `[T]` (not a dictionary), `Array<T>`, `Set<T>` or `OrderedSet<T>`. A container may be `Swift.`- or
  `Collections.`-qualified. Attributes, `some`, `any`, `inout`, `rethrows` and a typed `throws(E)` are removed
  too.
- **GRAPH.** A word of the parameter list's text (labels, names and types), of the result's text, or of the
  owner's name is one of: `graph`, `graphs`, `digraph`, `dag`, `edge`, `edges`, `node`, `nodes`, `vertex`,
  `vertices`, `dependency`, `dependencies`, `adjacency`, `successor`, `successors`, `predecessor`,
  `predecessors`, `arc`, `arcs`, `parent`, `parents`, `dependent`, `dependents`, `deps`, `prerequisite`,
  `prerequisites`. The owner is the innermost enclosing type or extension.
- **DOC.** A doc comment contains, ignoring case and runs of whitespace, one of: `longest path`,
  `longest-path`, `layering`, `layered`, `layer assignment`, `rank assignment`, `sugiyama`, `topological`,
  `coffman`, `network simplex`, `kahn`, `critical path`. A doc comment is the `///` run, or the one
  `/** … */` block, directly above the declaration, skipping attribute lines and blank lines. A block counts
  only when its own opener is `/**` and starts its line, so a plain `/* … */` is never a doc. There are two
  places to look:
  - **DOC-OWN** is the function's own doc comment.
  - **DOC-OWNER** is the owner's doc comment. When the owner is an extension, it also includes the doc of each
    `struct`, `class`, `enum` or `actor` of that name in the same repository, which means every subject sharing
    the git toplevel (§2). #667's witness has its evidence on the type.

  Nothing else is read: no `// MARK:` title, no body comment, no outer type's or protocol's doc (§9).

### 1.3 Candidates and copies

A function is a **candidate** when any of these holds:

- NAME ∧ SHAPE;
- NAME ∧ GRAPH;
- DOC-OWN;
- DOC-OWNER ∧ (NAME ∨ SHAPE).

Each candidate records which cues held.

**Copies merge across the whole universe.** Two functions are copies when they have the same name, the same
argument labels, and the same masked body with whitespace collapsed. A copy counts once, at the first in this
order: group (decision, unmet, wide), then repository (git toplevel), subject, path and line. Every other copy is
listed on it.

### 1.4 The gate a template could read

A candidate is **GATED** when a name word starts with `layer` or `rank`, or when DOC-OWN or DOC-OWNER contains
`longest path`, `longest-path`, `layering` or `layered`. This is #667's own signal, applied mechanically:
*"`layer` or `rank` in the name, or a doc comment saying longest-path or layering. Never accept `level`,
`depth` or `distance` alone."*

GATED is computed for every candidate and never shown to the judges (§4). On the witness's own type it admits
`computeColumns(graph:rows:) -> [Int: Int]`, which returns columns. That is the look-alike #667 names as the
reason the shape is not enough. So §8 measures the gate's precision, not only its count.

## 2. The universe, frozen

A **subject** is the real path of its root. A **repository**, which the bar counts, is the real path of the
subject's git toplevel, or of its root when it has none. Four manifest corpora (`swift-infer-core`,
`planted-defect-arm`, `cycle27-surface`, `leaderboard-sort`) share one repository, this one.

The census reads three groups:

- **Decision (36 subjects).** These are the manifest (22) and funnel (19) groups of
  `regex_acceptor_census.FROZEN_UNIVERSE`, as `budgeted_truncation_census.subjects()` resolves them. Five
  subjects are in both groups, and each of those is read once, over the union of its scan roots. A manifest
  corpus is read through its manifest source directories, and every other subject from its root.
- **Unmet (5).** These are Euclid, swift-docc, OpenAPIKit, jwt-kit and swift-system. Each is read from its root
  and reported as **N_unmet**, outside the decision.
- **Wide (67 directories).** This is every other directory with Swift sources under `~/xcode_projects` and
  `~/github_projects`. (`~/GitHub_projects`, the manifest's spelling, is the same folder as `~/github_projects`
  on this case-insensitive disk.) Each is read from its root and reported as **N_wide**, outside the decision. #667's estimate grepped 53 local repositories, and this group makes the
  census at least that wide.
  - The list is deduplicated by `origin` URL, keeping the `~/github_projects` copy. Two entries have no remote
    and are identified by path.
  - It leaves out any directory whose `origin` is a decision or unmet subject's (`_mutated` copies,
    worktrees), and also `mutation-bench`, which holds copies of other repositories, and
    `MyPlayground.playground`.
  - The script holds the list, and the sha256 of its sorted entries is
    `c7ad7e6c379c03144bc370d778edc97632f09318219065b7155e723471d5f270`.

#666's upstream SwiftFormat clone lives in a scratchpad, outside these roots, and is in no group.

**Asserted.** The script exits non-zero with no population if:

- the resolved decision and unmet lists are not `FROZEN_UNIVERSE`'s;
- SwiftUMLStudio is not at `c6c82e3` with a clean working tree;
- the wide list's hash differs, or a wide directory is missing or has a different `origin`.

Every subject's revision, and whether its working tree is dirty, is recorded, but only SwiftUMLStudio's is
asserted.

**Skipped files.** A file is skipped when any directory component of its path below the subject root:

- is hidden;
- is `Tests`, `tests`, `test`, `validation-test`, `.build`, `build`, `DerivedData` or `checkouts`;
- is `Pods` or `Carthage`, ignoring case;
- ends with `Tests` or `UITests`.

That is `regex-acceptor-census-scope.md` §2's rule, with three names from the construction universe's
amendment 5 (`test`, `tests`, `validation-test`) and two dependency folders added. Three of the names are
subsumed by other rules: `Tests` and `UITests` by the `Tests` suffix, and `.build` by the hidden rule.

## 3. Controls for the census pass, asserted before any subject is read

`layering_census.py --self-test` asserts 208 checks in 55 families, C1–C55, each on a synthetic snippet or
synthetic census rows. It joins `make measurement-selftest`. The table-driven families check against the controls' own copies of the
frozen lists, so that dropping a word from the pass also fails a control.

| family | what it pins |
|---|---|
| C1–C6 | `computeRows(graph:) -> [Int: Int]` (NAME, SHAPE, GRAPH); `dependencyLevels(for:) -> [[String]]` (not GATED); `assignLayers` (GATED); `rank(of node:in dag:) -> Int` (NAME ∧ GRAPH, GATED); `topologicalSort(_ nodes:)` (NAME ∧ GRAPH); `depthFirstSearch(from:) -> [Int]` (NAME ∧ SHAPE, not GATED) |
| C7–C9, C13, C16 | not candidates: `indentationLevel(for:) -> Int`; `rows(in table:) -> [Row]`; `strategy(for:)`; a plain member under a layering type doc; a declaration inside a comment or a string |
| C10, C11, C25, C27, C37 | DOC-OWNER: through SHAPE (the `computeColumns` look-alike, GATED); through an extension to the same-name type in another file; through NAME alone; on a `class func`, whose owner stays the class |
| C12, C18, C26 | DOC-OWN: a `///` run, a `/** */` block, an attribute line between the doc and the declaration |
| C14, C28–C30 | copies: in one repository; across groups, attributed to the decision copy even when its repository sorts last; not merged across different names or different labels |
| C15 | every skip name, each under its own parent; `Sources/` and `Sources/Testing/` are read |
| C17, C17b | `layerOf(_ n: Node) -> CALayer` is a candidate and GATED (the judges reject it); `layerOf(_ n: N) -> CALayer` is not a candidate |
| C19, C24 | SHAPE, spelling by spelling, 24 spellings including tuples, `Swift.`-qualified integers, `Set` and `OrderedSet` groups, and the negatives `[String: String]`, `[[Int: Int]]`, `[Node]` and `Set<Int>` |
| C20–C23 | every NAME word and prefix, the `longest path` pair, and the near misses `layout`, `rowan`, `strategy`, `deep`, `leveler` and `longest`; every GRAPH word, through a label, the owner's name or the result; every DOC phrase, and the near miss `longest`; GATED for exactly #667's words and phrases |
| C31 | `DAGNode` splits to `dag`, `node`; `layer_2Of` has NAME |
| C32 | one-hop same-file callers and callees |
| C33 | SHAPE ∧ GRAPH without NAME or DOC is not a candidate, and is kept for R4 (§6) |
| C34, C35 | §4's sampling, under and over each cap |
| C36 | the wide list hashes to §2's sha256 and has 67 entries |
| C38–C45 | `decide`, §8's outcomes in precedence order: BUILD; DECLINE (population) on count and on one repository (with no sensitivity line); DECLINE (signal); DECLINE (gate precision) at 5 of 8 and 69 of 100, and passing at 7 of 10; UNMEASURED (kills) on a failed runner control, a missing summary or no kill report; DECLINE (kills); the helper merge, a namesake in another file, and the unmerged count; the third judge deciding a verdict split, an EXPRESSIBLE split and an unanswered EXPRESSIBLE; a split with no third verdict as UNDETERMINED |
| C46–C51 | `class` before each of its 17 modifiers is not a type; an extension reaches a same-name class's, enum's and actor's doc; every integer spelling, bare and `Swift.`-qualified; a blank line between doc and declaration; a phrase split by a run of spaces; a plain `/* */` comment, with a phrase or after an earlier `/** */`, is no doc; a copy in unmet and wide counts at the unmet copy |
| C52–C55 | `decide` refuses a judged row with no judgement, or a judgement for no judged row; `join` attaches ids and refuses a failed calibration and an unknown, repeated or missing label; each sensitivity line fires when its alternative clears both halves of the bar, and only then; N_wide is estimated from a sample |

**Every rule was broken before the freeze.** Each §1–§2 rule, each of §4's sampling rules and each of §8's
decision, join and sensitivity rules was broken one at a time in a scratch copy of the script: 175 breaks, one
per list member, disjunct, cap, bar and outcome. 172 made a control fail. The other three are the subsumed skip
names, which are equivalent breaks. An earlier audit of 129 breaks had claimed full coverage. The conformance
check (§10) then broke 33 more rules no control caught, and those controls are C46–C55. Weak controls found
along the way and fixed before the freeze:

- the table-driven families had iterated over the pass's own constants;
- C28's repository names had sorted in group order;
- C34 had too few rows to tell the capped path from the uncapped one, and compared counts with the cap's own
  constant;
- C50's plain comment held no phrase, and C43's helper and C54's sample could not tell a merge or an
  EXPRESSIBLE rate from their absence.

## 4. The hand-check

### 4.1 What is judged

- **Decision and unmet candidates are judged in full.** If there are more than 300 decision candidates,
  every decision candidate that is GATED or has SHAPE, DOC-OWN or DOC-OWNER is still judged in full, so N_gated
  and the gate's precision are exact. The rest, the NAME ∧ GRAPH-only stratum, is then sampled: 40 rows.
- **Wide candidates are judged in full up to 60**, and above that a sample of 60 is drawn the same way. N_wide
  is then an estimate, reported with its sample size.
- **R4's rows (§6) are judged in full up to 40**, and above that a sample of 40.

Each sample is drawn by its own `random.Random(20261027)` over the rows sorted by id.

### 4.2 Calibration, before any packet

Two judges first classify the eight items of `fixtures/layering-law/calibration.md`. A miss stops the arm until
the verdict text is amended, with a dated amendment, and calibration runs again. The items and their expected
answers, which only the workflow holds:

| item | expected |
|---|---|
| `computeRows` at `c6c82e3` | LAYERING, result kind: map, EXPRESSIBLE |
| `computeRows` at `e36da59` | LAYERING, flagged *body disagrees* |
| `dependencyLevels` at `c6c82e3` | LAYERING, result kind: levels, EXPRESSIBLE |
| `computeColumns` at `c6c82e3` | NOT-LAYERING |
| a breadth-first distance over a DAG (synthetic) | NOT-LAYERING |
| a Kahn topological sort (synthetic) | ORDERING |
| a parent-pointer depth over a tree (synthetic) | TREE-DEPTH |
| a longest-chain depth whose cache is shared across calls, over a graph with cycles (synthetic) | LAYERING, not EXPRESSIBLE |

### 4.3 Packets and judges

The judged rows are put in a seeded order (`random.Random(20261027)` over the rows sorted by id) and grouped
into packets of at most eight, by `layering_census.py packets`. The packets and the calibration file are copied
into a directory that holds nothing else; the census report and the packets' label index stay elsewhere.
`fixtures/layering-law/judge-workflow.js` runs the calibration, then two judges on each packet, independently.
A third judge decides any row where the two disagree on the verdict or on EXPRESSIBLE, or where either gives
LAYERING without answering EXPRESSIBLE, as `regex-acceptor-census-scope.md` §5 did.

`layering_census.py join` maps the workflow's labels to row ids through the index. It refuses a failed
calibration and any unknown, repeated or missing label. `decide` refuses unless every judged row has exactly one
judgement, so a dropped packet can never read as rows that are not layerings. A row whose final record is not a
usable verdict is UNDETERMINED.

A judge sees:

- the function's full text, its doc comment, and its owner's name and doc;
- the file path, and the repository's name and path;
- the same-file functions it calls, and those that call it;
- the verdict set below.

A judge does not see:

- the cues, GATED, the group or the stratum;
- this scope's predictions, §8's bar and outcomes;
- any running count, or the other judge's verdict.

A judge may read only its packet and, for context, source files under the row's own repository path. It may
never open, list or search a `docs`, `scripts` or `fixtures` directory of this repository (a row here is read
through its own file only), any `.json` file or any other packet, and never search for a function's name
outside the row's own repository. The workflow's rules say so in those words.

### 4.4 Verdicts

- **LAYERING.** The function gives each node of a directed graph an integer layer or a position along one
  axis, or groups the nodes into an ordered list of levels. Its contract is that across every edge not on a
  cycle, among the nodes it layers, the layer strictly increases in one consistent direction.
  - The graph must admit a node with two or more predecessors.
  - A contract stated by the name or the documentation is enough. A body that contradicts it is still
    LAYERING, flagged *body disagrees*, and is listed for upstream filing.
  - A longest-path depth (one plus the maximum over predecessors, or over successors) is LAYERING, whichever
    way it counts.
  - An ordered list of groups (`[[T]]`, `[Set<T>]`, `[Int: [T]]`) is LAYERING when every off-cycle edge goes
    from an earlier group to a strictly later one, or the reverse throughout.
- **TREE-DEPTH.** The same, over a tree, where each node has at most one parent. The law holds there, but as
  `depth(child) = depth(parent) + 1`. Outside the population.
- **ORDERING.** A **flat** sequence of the nodes, in an order meant to respect the edges: a topological sort or
  its reverse. Outside the population.
- **NOT-LAYERING.** Anything else, with a short reason. Examples: breadth-first or shortest-path distance (on
  `r → a, r → b, a → b` it gives `d(a) == d(b)`); syntax nesting depth; indentation; table rows; a sort's rank;
  a `CALayer`. A function that only reads or forwards a layering computed elsewhere is NOT-LAYERING with the
  reason *reads a layering*.
- **UNDETERMINED.** The text does not decide it.

For LAYERING, the judge also records:

- the result kind: map, per-node query, coordinate or levels;
- the edge direction it claims;
- which nodes it leaves out, such as unreachable ones;
- **EXPRESSIBLE**, which is yes when all three of these hold:
  - the edges can be enumerated from the function's inputs;
  - the root, if the layering needs one, can be identified from the inputs;
  - the law holds for the function called by itself, without a cache or state shared with other calls.

  This is `whole-to-parts-partition-declined.md` §6's *expressible* clause, restated for this law.

### 4.5 Counting

**N** counts the final verdicts LAYERING ∧ EXPRESSIBLE in the decision universe, as **merged groups**.

- Copies merge as §1.3 says.
- A LAYERING function also merges with a LAYERING function in the same file that it calls, or that calls it.
  That holds one hop at a time, and transitively, by name. So a per-node helper and the function that uses it
  count once.

The **unmerged count**, reported beside N, is the LAYERING ∧ EXPRESSIBLE decision functions with every copy
counted, before either merge. A repository counts toward the bar only if it holds a merged group's first copy.

## 5. The kill arm (#667 step 2)

`scripts/layering_kill_arm.py`.

### 5.1 The subject

SwiftUMLStudio `c6c82e3`, package `SwiftUMLBridge`, is exported with `git archive` into this session's
scratchpad and never built in the user's checkout. The export's whole tree is kept, because some tests walk up
to the repository's `TestFixtures/`.

It is built with Xcode 27's Swift 6.4, found by `xcrun --find swift`, and the runner refuses to start unless
`swift --version` names `swiftlang-6.4.0.34.1`. That is the toolchain the road test used, run directly rather
than through swiftly's proxy, which adds a process group the watchdog would have to chase. There is no override. Unmutated, the export built in 50 s, and `SwiftUMLBridgeFrameworkTests` passed
1,823 tests in 31 s.

### 5.2 The law, prototyped by hand

`fixtures/layering-law/LayeringLawTests.swift` (sha256 `30f40cf787c953db…`) is copied into the export's
`SwiftUMLBridgeFrameworkTests` target, never into SwiftUMLStudio itself. It holds three properties, each run
over 1,000 graphs from a SplitMix64 generator with a fixed seed:

- **L1 (rows).** `ActivitySVGRenderer.computeRows(graph:)`. For every edge `u → v` with `u` reachable from
  the start node and `v` unable to reach `u`: `rows[v] > rows[u]`.
- **L2 (activity `centerY`).** The same edges, over `ActivitySVGRenderer.computeLayout(from:)`:
  `centerY(v) > centerY(u)`.
- **L3 (component `centerY`).** `ComponentSVGRenderer.computeLayout(_:)`. For every dependency `u → v` with `v`
  unable to reach `u`: `centerY(v) > centerY(u)`. This is #667's control, predicted to HOLD.

Reachability is computed in the test, by its own search over the input edges. **A covered edge whose endpoint
has no row (L1) or no positioned node or component (L2, L3) counts as a failure.** Each property prints one
summary line, `LAYERING-LAW L<n> trials=… edges=… failures=…`, and records one issue on its first
counterexample.

**The generators.**

- **Activity graphs.** They have 1 to 9 nodes with distinct ids drawn from `0..<64` and exactly one `.start`.
  Every other node's kind is drawn from the eight other kinds. Each non-start node gets one edge from a node
  drawn before it, so the start reaches every node. Then 0 to n more edges are drawn between any two drawn ids,
  so self-loops, back-edges and parallel edges all occur. The node list and the edge list are shuffled,
  because edge order is what the old defect turned on.
- **Component models.** They have 1 to 8 components with distinct names, a random kind, and 0 to 3 provided
  interfaces of random length. Then 0 to 2n dependencies are drawn between drawn names, with cycles and
  self-loops allowed, and shuffled.

The generators are hand-written. A built template would compose `DerivationStrategist`'s element generators
instead, as CLAUDE.md requires. This prototype is evidence for whether to build one, and is not that template.

### 5.3 The mutants

swift-mutation-testing, the road test's tool, is not installed here. So `layering_kill_arm.py` generates the
same experimental tier, as the road test recorded it in
`fixtures/mutation-check/roadtest-swiftumlstudio-2026-10-10.jsonl`:

| operator | rewrite |
|---|---|
| arithmetic | binary `+`→`-`, `-`→`+`, `*`→`/`, `/`→`*`, `%`→`*`, including an operator passed as a function (`reduce(0, +)`); never a compound assignment |
| relational | `<`→`<=` and `<`→`>`; `<=`→`<` and `<=`→`>=`; `>`→`>=` and `>`→`<`; `>=`→`>` and `>=`→`<=`; `==`→`!=`; `!=`→`==` |
| negate-conditional | a boolean clause `c` of an `if`, `guard` or `while` → `!(c)`; never a `let`, `var`, `case` or `#available` clause |
| logical | `&&`↔`||` |
| boolean-literal | `true`↔`false` |
| swap-ternary | `c ? a : b` → `c ? b : a` |
| remove-side-effects | a statement that is only a call, such as `ready.append(target)`; never a function's or closure's only expression, which is its value |

A binary operator is one written with a space on each side, so `->`, `..<`, a prefix `-`, a generic `<T>` and
`String?` never match. Code is masked first, so comments and string literals, interpolations included, are
never mutated.

**Parity, checked before the freeze.** `layering_kill_arm.py parity` runs this generator over `e36da59`'s three
scoped files and compares the result with the road test's 128 recorded mutants there, as (file, line,
operator, tokens). 118 are shared. Every difference is one of three kinds:

- **9 are inside string interpolations** in render functions, off the call tree. The tool mutates those, and
  this generator masks them.
- **1 is a ternary recorded on its condition's line.** The tool records the ternary at `ComponentSVGRenderer`
  :155 and this generator at :156. It is the same mutant.
- **1 is `fromRow + 1` at `e36da59`:138**, which this generator mutates and the tool did not. #667 noted that
  quirk.

**The mutated functions** are the bodies on the law's call tree inside #667's scoped files:

- in `ActivitySVGRenderer.swift`: `computeLayout(from:)`, `computeRows(graph:)`, `forwardEdges(from:in:)`,
  `computeColumns(graph:rows:)` and `nodeSize(kind:)`;
- in `ComponentSVGRenderer.swift`: `computeLayout(_:)`, `dependencyLevels(for:)`,
  `chainDepth(of:adjacency:cache:)` with its nested `enter(_:)`, `boxSize(for:)` and
  `stereotypeLabel(for:)`.

That is **91 mutants**. The scoped files' other **39** are counted by function and not run: the render
functions, and all of `ActivitySVGRenderer+Shapes.swift`, which no law over a layout reaches. Callees outside
the scoped files, such as `ActivityGraph.startNode`, are not mutated.

### 5.4 Each mutant

1. Write the mutant.
2. Run `swift build --build-tests`, with a 600 s limit. If it fails or runs past the limit, the mutant is
   **UNVIABLE**.
3. Run the **law**: `swift test --skip-build --filter '\.LayeringLawTests/'`, with a 120 s limit.
4. Run the **full suite**: `swift test --skip-build --filter '^SwiftUMLBridgeFrameworkTests\.' --skip
   '\.LayeringLawTests/'`, with a 300 s limit, about ten times its baseline. This is c6c82e3's hand-written suite
   as it stands. It includes `GraphWalkParityTests` (in `GraphWalkDepthTests.swift`, added for #149 after the
   road test), which compares `dependencyLevels` with a recursive reference over 2,000 random graphs.
5. Derive the **reduced suite**: the full suite less PR #64's three tests that assert the law on its own
   examples, `everyEdgeDescends`, `deadLoopIsIgnored` and `whileLoopHasOneBackEdge`. The last counts dashed
   edges, and an edge is dashed exactly when its target's `centerY` is not below its source's, so it asserts L2
   on the while-loop graph. PR #64's fourth test, `forwardEdgesDropsBackEdges`, unit-tests the helper the fix
   added and stays. The reduced suite is read off the full run in two cases:
   - when the full run survived;
   - when the full run failed by assertion and named a failing test other than those three.

   Otherwise it is run with the same command plus `--skip
   'ActivityRowLayeringTests/(everyEdgeDescends|deadLoopIsIgnored|whileLoopHasOneBackEdge)'`.
6. Restore the file.

**Outcomes.** A run is SURVIVED, or a detection by one of four mechanisms:

- **ASSERTION**: the run's own *test run … failed* line;
- **CRASH**: a non-zero exit without that line;
- **TIMEOUT**: past the limit;
- **MEMORY**: the run's own process tree and every process naming the export together hold more than 6 GiB
  resident.

**The flake rule.** The suite holds wall-clock assertions (`elapsed < .seconds(2)` and others), and the machine
is shared, so a flake could hide a law-only kill. When the law detects a mutant and the full or reduced suite
detects it by ASSERTION, that suite runs once more, and the detection stands only if the rerun detects too. A
detection that does not repeat is recorded as a flake with its failing tests, and the count of flakes is
reported. RC1's and RC3's suite runs are confirmed the same way.

**The watchdog** writes output to a file and polls every 0.5 s. When it stops a run, it kills the started
process's whole descendant tree, collected before any kill. It also kills every live process whose command line
names the export. That catches the test helper, which is otherwise reparented to launchd and keeps running.
After every run it waits up to 5 s for anything naming the export to leave the process table.

### 5.5 Controls for the runner

| # | control | expected |
|---|---|---|
| RC1 | the unmutated export | builds; L1–L3 hold over 1,000 graphs each (three summary lines, `failures=0`); the full suite passes at least 1,800 tests |
| RC2 | `computeRows` replaced by its pre-fix body from `e36da59` (`fixtures/layering-law/computeRows-e36da59.swift`) | the law detects it by ASSERTION, with L1 and L2 failing; the full suite detects it |
| RC3 | `max(rows[target] ?? 0, nextRow)` → `max(nextRow, rows[target] ?? 0)` | both SURVIVE |
| RC4 | a statement `let _: Int = "x"` in `computeRows` | UNVIABLE |
| RC5 | after the run | the export's `Sources/` and `Tests/` hash as before the run |
| RC6 | the law run twice on the unmutated export | the same three summary lines (compared as a set: the properties run in parallel and print as they finish) |
| RC7 | `while let nodeId = ready.popLast()` → `while let nodeId = ready.last` (a hang) | law and full suite both TIMEOUT, each within its limit plus 45 s, and no process naming the export survives the 5 s grace |

RC1–RC4, RC6 and RC7 run first. If any fails, the runner writes no summary. RC5 is checked after the last
mutant, and if it fails, the summary is void. A run resumes from its report only when the law's file and the
source tree hash as the report recorded; otherwise the runner refuses and a fresh report is started. `layering_kill_arm.py --self-test` asserts the operator rewrites
on a fixture snippet without a compiler and joins `make measurement-selftest`.

**If RC1 fails**, the first counterexample is hand-checked:

- **A law or generator error** is fixed by a dated amendment before any mutant runs.
- **A real defect in SwiftUMLStudio** is listed with its revision and offered to the user for filing upstream.
  The arm is then scored against a hand-fixed body, in a fresh report, and the doc says so.

UNMEASURED (kills) applies only when neither is done.

### 5.6 What is counted

Over the viable mutants, the runner counts what the law detects, what the full suite detects, and what the
reduced suite detects. It counts **law-only** detections both ways, against the full suite and against the
reduced one. Each law-only row records:

- its mechanism;
- the properties that failed (L1, L2, L3);
- its class: **layering**, if the mutated function decides layers (`computeRows`, `forwardEdges`,
  `dependencyLevels`, `chainDepth`), or **placement**, if it only turns layers into coordinates and sizes (both
  `computeLayout`s, `computeColumns`, `nodeSize`, `boxSize`, `stereotypeLabel`).

**The decisive count** is law-only detections **by ASSERTION** against the **reduced** suite:

- **Why ASSERTION.** A crash or timeout under random graphs is something any generator-driven test would
  catch, with no layering assertion involved.
- **Why the reduced suite.** The full suite holds the law's own examples, written because the law found #53.
  Scored against them, the law gets no credit for its finding.

The full-suite figure is reported beside it. A placement kill counts, because #667 states the law over
`centerY`, but the decision line shows the split.

Also reported:

- every mutant that survived both, read for equivalence (reported apart, and kept in the raw denominator);
- the suite-only count;
- each mechanism's count;
- for every suite kill by a single failing test, which test that was.

## 6. Recall probes

These are reported beside the census and never enter N:

- **R1.** The wide group itself (§2): does a layering function live outside the corpora the toolchain has
  read?
- **R2.** Every non-candidate function in a file that holds a candidate, by name. It shows what the cues saw
  next to a hit.
- **R3.** Every decision candidate that has DOC-OWN or DOC-OWNER but no NAME: the rows the name rule would miss.
- **R4.** Every decision function with SHAPE ∧ GRAPH that is not a candidate, which means no NAME and no doc.
  For example, `generations(of graph: Graph) -> [[Node]]` or `coffmanGraham`-style names the NAME rule would
  miss. They are judged as §4.1 says, and any LAYERING among them is reported as a sensitivity line.

## 7. Predictions, frozen

Each says whether it is blind and, if not, what informed it.

1. **N = 2 merged groups**, both in SwiftUMLStudio, so 1 repository: DECLINE (population).
   - The groups are `computeRows`, and `dependencyLevels` merged with `chainDepth`. `chainDepth` is a per-node
     longest-chain depth whose cache is shared across calls. It will be judged LAYERING, but not EXPRESSIBLE
     on its own (a reviewer found a fresh-cache counterexample), and it merges with `dependencyLevels`, which
     calls it.
   - *Not blind:* both files were read (§10).
2. **N_gated = 1** (`computeRows`, through its type's "longest-path layering").
   - `dependencyLevels`'s documentation states the law ("each row's components depend only on components in
     *later* rows"), but not in #667's words.
   - **The gate's precision over the judged decision universe is below 70%**, with `computeColumns` GATED and
     NOT-LAYERING.
   - *Not blind* for the witness file. Partly blind for the rest of the universe.
3. **N_unmet = 0, and N_wide ≤ 2.** *Partly blind:* #667's grep found only `computeRows` in 53 local
   repositories.
4. **ORDERING ≥ 3** in the decision universe, most of them in swift-package-manager. *Blind.*
5. **RC1 holds.** *Not blind:* a reviewer's Python model of `c6c82e3` found L1–L3 hold over 20,000 drawn
   graphs each.
6. **RC2 holds, and the reduced suite does NOT detect the pre-fix body.** *Partly blind:* at `e36da59` the
   suite was green with the defect in it. Whether the 299 commits since added another test that sees it was not
   checked.
7. **The decisive count is at least 1, and every decisive kill is placement, none layering.**
   - Against the full suite, law-only layering kills are 0. PR #64's examples and `GraphWalkParityTests`
     already pin the layering logic.
   - *Not blind:* a reviewer traced `height / 2` → `height * 2` in Activity's `centerY`, which reorders a
     decision above a fork on the next row, and found no activity test that asserts `centerY`.
8. **Law detections < 0.5 × full-suite detections**, over the viable mutants of §5.3's functions, with any
   mechanism counted as a detection. The law is blind to x-coordinates and `computeColumns`, and to sizes
   except through L2's `height / 2`. *Not blind:* computeLayout was read.

## 8. The decision, fixed now

The figures:

- **N**: §4.5's merged groups in the decision universe.
- **N_gated**: those groups with a GATED member.
- **Gate precision**: |GATED ∧ LAYERING| / |GATED| over the judged decision candidates that are GATED, with
  every GATED ∧ ¬LAYERING row listed.
- **The decisive count**: §5.6.

Reported beside them, none entering the decision:

- the unmerged count;
- N without EXPRESSIBLE;
- N_unmet and N_wide;
- **N_undetermined**, the decision candidates whose final verdict is UNDETERMINED;
- R4's LAYERING rows;
- the full-suite law-only count.

The bar is **at least 5 across at least 2 repositories**. `whole-to-parts-partition-declined.md` §6 froze it
for the tokenizer laws, and `lexer-corpus-census.md` applied it, expressibility clause included, to both the
conservation and the single-lexeme law. The parallel is this: #645's obstacle was that the law is not in the
signature, and #667's is that the shape is not enough. The single-lexeme law, like this one, also needs a
generator its types do not give.

`layering_census.py decide` computes all of this from the census, the judgements and the kill arm's report.

**The outcome is the first that applies:**

1. **DECLINE (population)**: N < 5, or N spans fewer than 2 repositories.
2. **DECLINE (signal)**: N_gated < 5, or it spans fewer than 2 repositories.
3. **DECLINE (gate precision)**: gate precision < 70%, the bar `inverse-name-vocabulary.md` used. A template
   reading the gate would propose a false law on most of what it admits.
4. **UNMEASURED (kills)**: any one of these:
   - a runner control fails;
   - RC5 fails;
   - the run did not finish every planned mutant;
   - RC1 failed and §5.5's path was not taken.

   A run with no summary is never read as zero kills.
5. **DECLINE (kills)**: the decisive count is 0.
6. **BUILD**: otherwise. The gate passes, and the build is a separate issue.

**Every arm runs, and every arm is reported, under every outcome.** The decision line is:

```
DECISION: <outcome>  N = <n> over <r> local repositories (bar: ≥ 5 across ≥ 2)  N_gated = <g>  gate precision <p>
law-only (reduced suite): <k> by assertion (<layering> layering, <placement> placement), <x> by crash/timeout/memory
law-only (full suite): <f>   law <a>, suite <b>, reduced <c>, viable <v>   N_unmet <u>  N_wide <w>  N_undetermined <d>
```

When wide was sampled, N_wide is printed with the judged and total counts and an estimate (count × total /
judged).

**Sensitivity.** The doc's first paragraph says so when any of these would clear, on both halves (count and
repositories), a bar the decision failed:

- N + N_unmet + N_wide, the estimate when wide was sampled (the decline rests on the universe's boundary);
- N + N_undetermined, or N_gated + the undetermined GATED rows (it rests on unsettled verdicts);
- N + R4's LAYERING ∧ EXPRESSIBLE groups (it rests on the cues);
- N + the unjudged rows of a sampled stratum at the judged rows' LAYERING ∧ EXPRESSIBLE rate (it rests on the
  sample). The repositories half counts every unjudged row's repository, as an upper bound.

**Disposition:**

- **Under DECLINE (population)**, #667 stays open on one frozen condition: at least 5 LAYERING ∧ EXPRESSIBLE
  groups across at least 2 repositories in a corpus of graph-layout packages. That corpus is the named
  follow-up, as #645 stayed open on a lexer corpus. Building it needs clones, so it needs the user's approval.
- **Under every other DECLINE**, #667 closes with the PR.
- **Under UNMEASURED or BUILD**, it stays open.

No reopen condition may be added after the run.

**Under every outcome:**

- the measurement doc, `layering-law-census.md` in `measurements/`, is written beside
  `regex-acceptor-census.md`;
- both indexes get a row;
- F6 of `roadtest-swiftumlstudio-mutation.md` gets a dated annotation;
- every LAYERING row flagged *body disagrees* is listed with its revision and offered for upstream filing.

Joseph-Cursio/SwiftInferProperties#675's box laws are not scored here, although #667 says one run could serve
both. That is #675's own gate.

## 9. What this does not answer

- **One subject for the kill arm.** The kill counts are SwiftUMLStudio's, against a suite that already has
  PR #64's examples and `GraphWalkParityTests`. They are not a rate.
- **The census only finds what its cues reach.** It misses:
  - any function with no NAME word and no DOC-OWN, unless it has DOC-OWNER together with SHAPE;
  - a NAME function with neither SHAPE nor GRAPH nor a doc;
  - a SHAPE ∧ GRAPH function with no NAME, which R4 samples instead;
  - computed properties, subscripts and initialisers;
  - layering done inside a larger function;
  - a coordinate layout named `layout` or `computeLayout`, or one returning `CGFloat`s or a layout struct,
    unless its own doc or a NAME word reaches it.

  DOC reads only the doc comment directly above the function and above its innermost owner, plus same-name
  types for an extension. MARK titles, body comments, and outer types' and protocols' docs are not read. So
  `computeRows`' body comment, "Kahn's algorithm … a join always lands below its longest branch", counts for
  nothing.
- **Local clones only.** There is no dedicated corpus of graph-layout packages, which is the corpus most likely
  to hold the population. That is §8's reopen condition.
- **Hand-written generators.** The prototype is not a template. A template's reach depends on the generators it
  can compose, and this arm does not measure that.
- **A re-implemented tool.** The operators match the road test's tool on 118 of its 128 mutants in these files,
  and §5.3 accounts for the rest. Kill counts are comparable within this run, not with the road test's 1,300.

## 10. Disclosures before the freeze

**Read, beyond #667 itself:**

- SwiftUMLStudio#53's title, and PR #64's description and file list.
- At `c6c82e3`:
  - `ActivitySVGRenderer.swift` lines 1–240, including `computeLayout`, `computeRows`, `forwardEdges` and
    `computeColumns`;
  - `ComponentSVGRenderer.swift` lines 1–240, including `computeLayout`, `dependencyLevels`, `chainDepth` and
    `boxSize`;
  - the declarations in `ActivityGraph.swift`, `ComponentModel.swift`, `ComponentKind.swift`,
    `ComponentLayout.swift` and `ActivityLayout.swift`;
  - `ActivityRowLayeringTests.swift` in full;
  - the names of the test files that mention either renderer, and of `GraphWalkDepthTests.swift`'s suites.
- At `e36da59`: the pre-fix `computeRows`, now the RC2 fixture, and the parity check's lines.
- The road test's mutant record, `roadtest-swiftumlstudio-2026-10-10.jsonl`.

**The scope review.** A four-lens adversarial review, with an adversarial verifier per lens, read the draft,
both scripts, the export's sources and tests, and SwiftUMLStudio's history. It ran Python models of
`c6c82e3`'s `computeRows` and `chainDepth`. It found 41 issues, every one folded in here. Its findings made
predictions 5 and 7 not blind, as they say. No reviewer opened a census subject other than SwiftUMLStudio.

**Run before the freeze, on the export only:**

- the baseline build and suite (§5.1), and twice more to check filters;
- the full suite with the anchored filters, with the law's file present but skipped. It passed 1,823 tests in
  208 suites. A SwiftUMLBridge test that diagrams its own test sources now reads the law's file, and still
  passes.
- `swift test list`, which names the law's three tests and PR #64's;
- the law's file compiled by `swift build --build-tests`, **never run**;
- `layering_kill_arm.py mutants`, a listing.

**Read-only in the user's SwiftUMLStudio checkout:** `layering_kill_arm.py parity`, which reads `e36da59`'s files
with `git show`. Nothing was built or written there.

**Run without a subject:** both self-tests, `make test-fast` (green, 218 s), and the rule-break audit of §3.

**The conformance check and a second adversarial read.** Two more agents compared this text with both
scripts, the fixtures and the workflow, and re-read the revised freeze for anything that could still make the
decision wrong. They found 33 issues, all folded in. Among them:

- 33 rules no control caught (now C46–C55);
- judges who could have reached this scope's predictions and the calibration answers (now forbidden, §4.3);
- no frozen join of labels to ids, and a missing judgement that would have read as "not a layering";
- sensitivity lines that ignored the repositories half of the bar;
- a stray `/* */` read as a doc;
- RC6 comparing lines whose order depends on which test finishes first;
- no rule for timing flakes;
- a third law-derived test, `whileLoopHasOneBackEdge`.

Neither agent ran the census or the law.

**Not opened:** any other subject in the universe. The wide group's membership came from directory listings
and `origin` URLs. #667's grep result came from #667.

## Amendments

**1 — 2026-10-28: a test log that ends inside a character.** The kill arm stopped after M070, with every
runner control before it passed. While reading M071's reduced-suite log, `_run` raised `UnicodeDecodeError`,
because the log ended inside a UTF-8 character, as a run killed mid-write can. `_run` now reads the log with
bad bytes replaced, and a self-test check covers it; with the fix removed, the check fails. No outcome rule,
mutant, law, or control changed. The run resumed from its report, which §5.5 allows only when the law's file
and the export tree hash as before, and that guard held. M001–M070 were not re-run.
