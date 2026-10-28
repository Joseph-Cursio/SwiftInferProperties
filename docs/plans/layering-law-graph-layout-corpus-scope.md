# Does a graph-layout corpus hold the layering law's population? (#667's reopen condition)

> **Status:** `shipped` · **As of:** 2026-10-28
>
> **Run 2026-10-28. Result: DECLINE (gate precision).** N = 15 over 5 repositories, and the gate is right on 16
> of the 149 rows it admits. Written up in `docs/measurements/layering-law-census.md`, §"The reopen condition".
> The rule below is as frozen at `a330611b`, before any corpus subject was read. §8 lists what was read, written
> and run before the freeze. No amendment was made.

`layering-law-census-scope.md` measured #667's layering law and declined it on population. Over 36 decision
subjects it found 2 LAYERING ∧ EXPRESSIBLE groups, both in SwiftUMLStudio, against a bar of at least 5 across at
least 2 repositories (`docs/measurements/layering-law-census.md`). Its §8 kept #667 open on exactly one
condition, frozen before that run:

> at least 5 LAYERING ∧ EXPRESSIBLE groups across at least 2 repositories in a corpus of graph-layout packages.

None of that run's subjects was a graph-layout package. This scope builds such a corpus and tests the condition
over it, **the corpus alone**. It is #645's lexer-corpus step (`lexer-corpus-prediction.md`), done for #667.
Every rule it does not restate is the first scope's, unchanged.

---

## 1. What is unchanged

These hold as `layering-law-census-scope.md` states them:

- **§1, the pass:** the unit, the four cues (NAME, SHAPE, GRAPH, DOC), the candidate rule, the copy merge, and
  GATED.
- **§2's skip rule** for files.
- **§3's controls,** C1–C55, every one still asserted.
- **§4, the hand-check:** calibration first; packets of at most eight rows in seeded order; two blind judges per
  packet and a third on a split; the verdicts, EXPRESSIBLE, and the counting with its two merges. The one change
  is §4.1's sampling cap, below.
- **§8:** the figures, the bar, the outcomes in precedence order, and the sensitivity lines.

`fixtures/layering-law/judge-workflow.js` and `fixtures/layering-law/calibration.md` are used as they are.

**All decision candidates are judged, whatever their number.** The first scope's §4.1 sampled 40 rows from the
NAME ∧ GRAPH-only stratum above 300 decision candidates. Here that stratum is judged in full. A sampled-out row has
no verdict, so it cannot join §4.5's helper merge: two layerings that share an unjudged helper would count as two
groups. It also holds whole layerings, for example an in-place `longestPath(_ g: Graph)` with no doc comment. R4
keeps its cap of 40, because it feeds only a sensitivity line.

## 2. The universe

### 2.1 The corpus

These are 18 public packages, cloned `--depth 1` on 2026-10-28 into
`~/github_projects/graph-layout-corpus/<owner>__<repo>`, one directory each, and read at the revision shown. All
of them are the decision group. There is no unmet group and no wide group.

| package | revision | kind | why it is here (from its description) |
|---|---|---|---|
| lukilabs/dagre-swift | `92efb78` | layout | a port of dagre, a Sugiyama layered layout |
| lukilabs/elk-swift | `32f8042` | layout | a port of the Eclipse Layout Kernel, which includes ELK Layered |
| lukilabs/beautiful-mermaid-swift | `6a23a29` | layout | a native Mermaid renderer; Mermaid flowcharts are layered |
| 2389-research/MermaidKit | `64c19fb` | layout | native Mermaid, 30 diagram types |
| Australware/swift-mermaid | `ee4b50b` | layout | a pure-Swift Mermaid renderer |
| nmandica/DirectedGraph | `4aba725` | layout | a SwiftUI view of directed graphs |
| 1amageek/swift-flow | `538588e` | layout | a flow-diagram library |
| aaurelions/SwiftFlow | `3515701` | layout | a node graph editor modelled on ReactFlow |
| yahirvitelugardo/Graffle | `53b93b0` | layout | a diagramming app |
| Vithanco/SwiftGraphvizLayout | `083fb3c` | layout | Graphviz layout from Swift |
| Ryu0118/swift-module-graph | `86c7dde` | dependency | a target dependency graph, with work-span analysis |
| getyourguide/spmgraph | `47ad8ac` | dependency | visualises and analyses SwiftPM dependency graphs |
| simonbs/dependency-graph | `6c89d4b` | dependency | visualises package dependencies |
| leejungyeob/TuistSpider | `01aaa14` | dependency | explores Tuist dependency graphs by depth |
| GlitchLoom/SwiftDependencyGraphExplorer | `f93a343` | dependency | explores type-level dependencies |
| swift-compositions/swift-package-graph | `d783a2c` | dependency | dependents, closures, topological order |
| poolcamacho/Maple | `9255de9` | commit | a git client that draws the commit graph |
| tengla/GitGraphRender | `1197ce4` | commit | renders a commit history as a graph |

**How they were chosen.** `gh search repos --language=swift` was run over the queries below, sorted by stars,
keeping the top 30 results of the first set and the top 20 of the second:

- `graph layout`, `sugiyama`, `layered graph`, `hierarchical layout`, `dag layout`, `directed graph`, `graphviz`,
  `dependency graph`, `flowchart`, `diagram`, `node editor`, `mermaid`, `graph drawing`, `DAG`, `topological`;
- `dagre`, `auto layout graph`, `hierarchical graph`, `git graph`, `commit graph`, `workflow graph`,
  `state machine diagram`, `pipeline graph`, `build graph`, `graph visualization`, `network diagram`,
  `flow chart`, `tree layout`, `DAG visualization`, `layout engine graph`. Two more, `d2 diagram` and `UML`,
  hit GitHub's rate limit and returned nothing.

Only each result's name, description, star count, size and last-push date were read.

A repository was proposed when its description says it does one of these:

- lays out, draws or renders a directed graph or a diagram of nodes and edges;
- analyses or visualises a dependency or build graph;
- draws a commit graph.

It was left out when it is any of these:

- a force-directed layout only, which has no layers (Grape, Force, ForceGraph and others);
- a DOT or Mermaid text emitter that leaves layout to another tool;
- a node editor that does not claim auto-layout;
- a tutorial, sample code, a fork, or archived.

The user approved all 18 before any was cloned. **Selection was by description, never by code.** No code search
was run, because choosing repositories by whether their code holds `layer` or `longestPath` would tune the corpus
to the cues.

**Kind** is read off the description:

- **layout:** the package lays out or draws graphs;
- **dependency:** it analyses or visualises dependency graphs;
- **commit:** it draws commit graphs.

The frozen condition names graph-layout packages. The dependency and commit kinds stretch that phrase, and §4
reports the layout kind alone beside the decision. Disclosure: the dependency kind was proposed partly because
the first run's only layering outside SwiftUMLStudio was sourcekit-lsp's `targetDepthsAndDependents`, a
build-target depth.

### 2.2 The witness is beside the decision, never in it

SwiftUMLStudio is not read again. Its two groups (`computeRows`, and `dependencyLevels` with `chainDepth`) are
known from the first run. Counting them would turn the frozen condition, 5 groups across 2 repositories, into
3 groups in any one corpus repository. They are reported beside the decision as **N + 2 over the repositories
+ 1**, computed by `witness_groups()` from the first run's own fixtures (`census-2026-10-28.json` and
`judgements.json`). `lexer-corpus-prediction.md` counted its corpus "plus the earlier witness", but its frozen
condition said "Today it is 1 across 1", and this one does not.

### 2.3 Asserted

`layering_census.py run-corpus` exits non-zero with no population if any of these holds:

- the corpus list does not hash to
  **`7272bb357b918c606dde71690763adf474d8c9034bcd2adfeae57177b6b45046`**. The hashed text is built like this:
  - one line per entry: `directory origin revision kind`, separated by single spaces;
  - `origin` written as `https://github.com/<owner>/<repo>`, lowercased, without `.git`;
  - the full 40-character revision;
  - lines sorted by directory ignoring case, joined by a newline, with no trailing newline;
- a clone is missing, has another `origin`, is at another revision, or has a dirty tree.

`decide-corpus` refuses a census that `run-corpus` did not write, under this label and for this hash. It also
refuses any kill report but `fixtures/layering-law/kill-arm-2026-10-28.json`, which it identifies by the
sha256 of the report's JSON with sorted keys:
`83aeacfa3ec829f133ef624b9379a1a0252f12ab6ca78f8ee40925bcfc235b0c`.

## 3. The pass

The pass is `scripts/layering_census.py`, with its §1 rules, `packets`, `join` and `decide` unchanged. It adds:

- **`run-corpus <out.json>`:** `run` over §2's universe, with every decision candidate judged (§1).
- **`decide-corpus <census.json> <judgements.json> <kill-arm.json>`:** prints `decide`'s decision line and
  sensitivity lines for the corpus, then the lines beside it (§4) and R5's list (§5).
- **R5,** a recall probe (§5).

C56–C61 are the new controls; the self-test now runs 255 checks:

| family | what it pins |
|---|---|
| C56 | the corpus list hashes to §2.3's sha256; it has 18 entries; each directory is its `origin`'s `owner__repo`; each revision is a full SHA; the kinds are 10 layout, 6 dependency and 2 commit |
| C57 | `decide_corpus`. Three corpus groups and the witness's two give DECLINE (population), and the witness line reads 5 over 2. Five groups in two lukilabs repositories clear the bar, and the owner count is 1. Three layout and two dependency groups clear the bar: layout only is 3 over 1, the groups by kind are 3, 2 and 0, and the verdict tally is 5 LAYERING. A dependency tool's group with a copy in a layout package is in the layout line, at the layout repository. Three same-name lukilabs groups plus two MermaidKit groups are N 5 over 4, and owner-merged 3 over 2. It refuses: no label and no hash, the label with another hash, the hash under another label, a missing kill report, and a kill report other than the frozen one. It reads the frozen one (decisive 4, every runner control passed). A *body disagrees* flag from either agreeing judge counts; a flag the third judge overruled, or one on a row whose final verdict is not LAYERING, does not |
| C58 | role names, by their last words. These are role names: `LongestPathLayerer`, `NetworkSimplexLayerer`, `CoffmanGrahamLayerer`, `MinWidthLayerer`, `Layering`, `NodeRanker`, `GraphRanking`, `LongestPath`, `LayerAssigner`, `LayerAssignment`, `RankAssigner`, `RankAssignment` and the plurals `Rankers`, `Layerers`, `Layerings` and `NodeRankings`. These are not: `LayeringStrategy`, `NetworkSimplexPlacer`, `NetworkSimplex`, `SimplexNoise`, `RankingService`, `LongestPathFinder`, `PathLongest`, `LongestSimplePath`, `LayerView`, `CALayer`, `RankedList`, `SugiyamaLayout`, `Assignment`, `Path`, and the top level |
| C59 | R5 over two files lists six declarations: a documented `LongestPathLayerer` class with an `init`, a nested `Frame` type and a `process` method that nests `visit`; a `NodeRanker` protocol; a `Layering` class with only a computed property; two `GraphRanking` namesakes; and an extension of `LongestPathLayerer`. Each declaration lists only the functions declared directly in it, and the candidates among them. `LayerView` is not listed |
| C60 | with no cap, every one of 400 decision candidates is judged; with §4.1's cap, 40 are |
| C61 | the witness line reads the first run's own verdicts: two groups in one repository, `computeRows` and `dependencyLevels` |

**Every new rule was broken before the freeze**, one at a time in a scratch copy, with the fixtures beside it. The
final audit made 42 breaks:

- each of R5's 13 role endings;
- matching an ending anywhere in the name, and matching it in either order;
- dropping the nested-function rule, and taking the outermost declaration instead of the innermost;
- marking every function a candidate;
- each half of the universe refusal;
- the missing kill report, the kill report's identity, and the identity's hash value;
- for the layout line: first copies only, copies ignored, and the first copy's repository;
- the owner count, and the owner-merged line keyed by name only or by repository;
- both halves of the witness line;
- the by-kind tally, and the verdict tally;
- `body_flags` keeping only A's flag, ignoring the final verdict, and keeping an overruled flag;
- the cap;
- a kind, the hash without the kinds, a revision, and a directory;
- the witness line reading every repository.

Every break made the self-test fail. One break, of the by-kind tally, made it fail by crashing a control rather
than by a failed assertion. Getting there took three rounds and two reviews:

- in the first audit, one break hit the identical `("longest", "path")` in NAME_PAIRS, and two did not match the
  file's line wrapping;
- the second review found the two halves of the universe refusal untested, each alone.

`corpus_universe`'s disk assertions have no control; the run itself exercises them.

## 4. The decision

**The corpus decides.** §8 of the first scope applies as written, with these 18 packages as the decision
universe. The kill arm is not re-run: `decide-corpus` reads `fixtures/layering-law/kill-arm-2026-10-28.json`,
whose decisive count is 4 and whose runner controls all passed. That arm measured, on the witness, whether the
law catches what a suite misses, and the corpus does not change it.

The outcome is the first that applies:

1. **DECLINE (population):** N < 5, or fewer than 2 repositories.
2. **DECLINE (signal):** N_gated < 5, or fewer than 2 repositories.
3. **DECLINE (gate precision):** precision below 70% over the judged GATED candidates.
4. **UNMEASURED (kills):** the report has no summary, or a runner control failed. Neither holds for the frozen
   report, and `decide-corpus` refuses any other (§2.3).
5. **DECLINE (kills):** cannot apply, since the decisive count is 4.
6. **BUILD.**

**Beside the decision**, never deciding it:

- **with the witness:** N + 2 over the repositories + 1;
- **layout packages only:** the groups with a member or a copy in a layout package, each counted at its first
  such repository, and the number of those repositories;
- **the groups by kind,** at each group's first copy;
- **the repositories counted by owner:** lukilabs owns three of the corpus repositories;
- **owner-merged N:** groups whose first copies share an owner and a function name count once, and the owners
  they span. A layout lightly edited between one owner's repositories is two groups the copy merge cannot join,
  and this line joins it when the name was kept;
- **the final verdicts on the judged decision candidates,** after the copy merge, R4 excluded;
- ***body disagrees*:** the decision rows whose final verdict is LAYERING and which a judge holding that final
  verdict flagged. That means A or B when they agree, and the third judge otherwise. `decide`'s own list reads
  only A's record when A and B agree, so it can miss B's flag.

**The decision paragraph must say so** whenever the population half (N ≥ 5 across ≥ 2) comes out differently on
any of these than in the decision:

- with the witness;
- on layout packages only;
- with repositories counted by owner;
- on owner-merged N, across at least 2 owners.

Under DECLINE (population), it reports §8's sensitivity lines too.

**Disposition:**

- **DECLINE (population)** answers the reopen condition no. The first scope allows no further reopen condition,
  so #667 closes.
- **Any other DECLINE** also closes #667. The population exists, but the gate #667 proposes cannot find it.
- **BUILD** keeps #667 open; the build is a separate issue.

Closing the issue and commenting on it are the user's to approve. The measurement says which disposition applies,
not that it was carried out.

**Under every outcome:**

- a dated section is added to `docs/measurements/layering-law-census.md`;
- both index rows are updated;
- every row on the *body disagrees* line above is listed with its revision and offered for upstream filing.

## 5. Recall probe R5

R5 lists the type, extension and protocol declarations in the corpus whose name is a **role name**. That covers
13 endings: the last word is one of `layerer`, `layering`, `ranker` or `ranking`, or a plural of one; or the last
two words are `longest path`, `layer assigner`, `layer assignment`, `rank assigner` or `rank assignment`. A
strategy enum, a placer, a solver and a view are not role names, even when they hold one of those words.

R5 sees a declaration as the census's scanner does, so a declaration whose `{` falls more than 3 lines after its
name is not listed. A long, multi-line conformance list can hide one.

For each declaration it lists:

- the functions declared directly in it, which leaves out functions in a nested type and functions nested in
  another `func` that starts on an earlier line. A function nested in an `init`, an accessor or a closure is
  counted as the type's own;
- which of those functions are candidates.

**R5 is a list to read, not a figure.** It is never judged, never enters N, and never makes a sensitivity line.
It exists because the first scope's §9 says the cues read a function's own name. A layering written as a type,
`LongestPathLayerer` with a `process(_:)` method, reaches the census only through the method's own doc comment
(DOC-OWN), or through its type's doc comment when the method also has NAME or SHAPE. A role-named declaration
whose layering method is not a candidate is a place where the census cannot see. Prediction 5 fixes how the list
is scored.

The first scope's R2–R4 run too. R1, the wide group, has nothing to read.

## 6. Predictions, frozen

None of the corpus's code has been read. These rest on the repositories' descriptions and, where marked, on what
the projects they port are known to do. The witness's figures are known from the first run (2 groups, 1
repository, and 1 LAYERING of 3 GATED rows), and no prediction counts them.

1. **The population clears on the corpus alone:** N ≥ 5 across ≥ 2 repositories, with N between 5 and 12.
   - *Partly blind:* dagre's JavaScript ranks by longest path and by network simplex, and Mermaid renderers
     commonly lay out flowcharts by layer. Whether these ports keep those as separate functions with NAME was
     not checked.
   - The dependency kind was proposed partly because of sourcekit-lsp's hit (§2.1).
2. **The population also clears on layout packages only, and with repositories counted by owner.** *Blind.*
3. **The gate's precision is below 70%.**
   - *Partly blind:* dagre and ELK carry many functions named for ranks or layers that read a layering rather
     than compute one, such as rank normalisation and layer sweeps. Those are GATED, and judged NOT-LAYERING
     with *reads a layering*.
4. **The outcome is DECLINE (gate precision).** It follows from 1 and 3 when N_gated clears its own bar. *Blind*
   on N_gated.
5. **R5 lists at least 3 distinct elk-swift type names ending in `Layerer`, and for at least 3 of them a
   function named exactly `process` appears in one of that name's declarations, and is not a candidate.** Type
   names are counted, not declarations, so a class and its extensions count once.
   - *Not blind to ELK's design:* ELK Layered writes its layerers (`LongestPathLayerer`,
     `NetworkSimplexLayerer`, `CoffmanGrahamLayerer`, `MinWidthLayerer` and others) as classes with a `process`
     method. Whether the port kept those names was not checked.
6. **ORDERING ≥ 3** on §4's verdict line: final verdicts on judged decision candidates, after the copy merge, R4
   excluded. They come from topological sorts in the layout engines and the dependency tools. *Blind.*
7. **More than 300 decision candidates after the copy merge** (run-corpus's decision line), **all of them
   judged.**
   - *Partly blind:* ELK names much of its API after layers, and layout code passes nodes and edges almost
     everywhere.
8. **N_undetermined ≤ 3, and §4's *body disagrees* line is empty.** *Blind.*

## 7. What this does not answer

- **One kill arm.** The kill counts stay SwiftUMLStudio's (§4). A BUILD here would not show the law catching a
  defect in a corpus package.
- **The cues' reach.** Everything the first scope's §9 lists still holds. R5 shows one part of it on this
  corpus.
- **A search-defined corpus.** These 18 are what the search found and described as graph layout. They are not a
  sample of anything, and their figures are counts, not rates.
- **Lineage beyond the copy merge.** Byte-identical copies merge. A lightly edited copy, or two ports of one
  design, count twice. The owner-merged line joins only copies that kept their name, within one owner.
- **Ports.** dagre-swift and elk-swift port JavaScript and Java. A layering in them is one Swift author's reading
  of another project's design, and it counts like any other.

## 8. Disclosures before the freeze

**Read:**

- GitHub search results: names, descriptions, star counts, sizes and last-push dates;
- each clone's `origin`, `HEAD`, working-tree status, Swift-file count and disk size.

The clones hold about 1,530 `.swift` files before the skip rule, from `Vithanco__SwiftGraphvizLayout`'s 12 to
`lukilabs__elk-swift`'s 436.

**Run, on synthetic inputs and the first run's fixtures only:**

- the census self-test, now 255 checks;
- the 42-break audit of §3;
- the kill arm's self-test, unchanged;
- `make test-fast`, green.

**The review before the freeze.** Two adversarial reviewers read an earlier draft and the script diff, never the
corpus, and two verifiers checked their 15 findings. The design above answers the 11 confirmed:

- **The witness was in the decision group,** which loosened the frozen bar. It could also tip gate precision
  either way. It is now beside the decision (§2.2).
- **Sampling could split a merge,** or drop a whole layering, above 300 candidates (§1).
- **Lineage and kind:** near-copies across the three lukilabs repositories, and dependency tools in a "graph-layout"
  corpus, are now reported beside the decision (§4).
- **R5 was keyed by name and read only through functions.** It missed protocols, types with no `func`, and
  namesakes, and its role words admitted strategies and placers (§5).
- **R5 rules no control pinned,** and an inconsistent break count (§3).
- **Prediction labels** that did not disclose the witness's known figures, and a prediction that could be scored
  either way (§6).
- **The corpus-alone line's leaks,** from an earlier design.

**Three findings judged not to be defects were adopted anyway:**

- the sha256 is now written in this text (§2.3);
- `decide-corpus` refuses a census of another universe and a missing kill report;
- the witness is no longer re-judged.

**A second review** checked the reworked text against the code: two reviewers and two verifiers, with the
same rules. They confirmed 14 of 15 findings, and the text and code above answer all 15:

- each half of the universe refusal was untested;
- `rankings` was missing from the role endings;
- R5's 3-line scanner cutoff and its nesting rule went unstated, and its DOC-OWN path was misstated;
- prediction 5 had no scoring rule, and predictions 6 and 7 did not say what they count;
- outcome 4's condition was misstated, and the kill report was not pinned;
- the owner line could not bound near-copies in N, hence owner-merged N;
- the layout line depended on which copy came first, which the capitalisation of an owner's name decides;
- `decide`'s *body disagrees* list reads only A's record when A and B agree;
- the hashed text's newline and URL form were unstated.

**Not opened:** any corpus file, and SwiftUMLStudio beyond what the first scope's §10 lists.
