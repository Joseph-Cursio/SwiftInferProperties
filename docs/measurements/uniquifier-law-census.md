# Does #669's uniquifier law have a population? — Yes: 7 groups across 5 repositories, a gate right on 8 of the 9 rows it admits, and 5 kills the suite misses without the law's own examples: BUILD (#669)

> **Status:** `measured` · **As of:** 2026-10-28
>
> **Decision: BUILD** under `docs/plans/uniquifier-law-census-scope.md` §8. The population, the gate's
> signal, its precision and the kill count all clear. Under §8, #669 stays open, and building a template is a
> separate issue, not yet filed. #669's law as written is false on its fixed witness without a setup call (S0),
> which any build has to handle.

#669 asked for a law the catalogue does not have. For a **uniquifier**, a stateful function that hands out
names and remembers which ones it has handed out, the law is *one receiver, n calls, n distinct results*, apart
from a guard's sentinel. A **memoizing** uniquifier owes another form: equal keys give equal ids, and distinct
keys give distinct ids.

#669's witness was SwiftUMLStudio's `DiagramContext.uniqName(item:relationship:)`. At `e36da59` it suffixed a
repeated name with one diagram-wide counter and never re-checked the result, so `struct Foo0`, `struct Foo` and
`extension Foo` were all declared as `Foo0`. That was filed as SwiftUMLStudio#54 and fixed by its PR #65. The
second allocator #669 named, `LayoutGraphBuilder.uniqueId(for:existing:)`, was filed as #55 and fixed by PR #77.
So what remained was #669's gate before building:

- **step 1**: write the law by hand and mutation-score it against the fixed code;
- **a census** of the population across the corpora.

This doc reports both. Everything it rests on was committed in this order, on branch `uniquifier-law-census`:

| step | commit | what |
|---|---|---|
| scope | `36103bd7` | `docs/plans/uniquifier-law-census-scope.md`: the cues, the gate, the universe, 85 controls, the hand-check, the kill arm, 9 predictions and the decision rule, frozen before the census read any subject or the law ran |
| census instrument | `390ad888` | `scripts/uniquifier_census.py`, `fixtures/uniquifier-law/judge-brief.md`, `calibration.md` |
| kill-arm instrument | `eea64667` | `scripts/uniquifier_kill_arm.py`, `fixtures/uniquifier-law/UniquifierLawTests.swift` |
| results | `db1443f9` | `fixtures/uniquifier-law/census-2026-10-28.json`, `judgements.json`, `judge-workflow.js`, `judge-workflow-output.json`, `kill-arm-2026-10-28.json` |
| hand-check | `be140345` | `fixtures/uniquifier-law/handcheck-workflow.js`, `handcheck-2026-10-28.json`: the 7 body-disagrees rows and the unscored re-read |
| this doc | this commit | this doc, both index rows, and the scope's status |

**In short: BUILD, with conditions a template must meet.**

- **The population exists.** The decision universe holds **7** owing, EXPRESSIBLE groups across **5**
  repositories, against a bar of 5 across 2. The scope predicted 4 across 3 and a decline.
- **#669's gate is precise.** Applied mechanically, its three criteria admit 9 decision rows, and **8 owe the
  law (89%)**, against a bar of 70%. Six of the seven groups have a gated member, across 4 repositories.
- **#669's law, as written, is false on SwiftUMLStudio's fixed code.** With nothing called first, `uniqName`
  issues one alias twice in 146–200 of 1,000 drawn sequences per format (S0). Its contract asks for
  `reserveIdentifiers(drawing:)` first, and with that call the law holds (RC1). A template that states the law
  without the setup call proposes a false law on correct code.
- **The law on its witness.** The hand-written law catches 10 of 37 viable mutants, against the full suite's 37.
  All 10 are in the functions that decide which id is issued. Without the four suites written for the same
  defects, the law alone catches 5, all by assertion, so the decisive count is 5 (4 with `DiagramIdentifiersTests`
  kept). Against the full suite it catches none alone.
- **Seven rows break the law in their bodies, and two of those are reachable.** Every witness held when
  hand-checked and run. SwiftPlantUML's `uniqName` (#669's own defect, in the project SwiftUMLStudio
  descends from) and Yams's `UniqueAliasProvider` (silently wrong values after a YAML round trip) are worth
  filing. The other five are latent: no caller in their repositories reaches the witness.
- **An unscored re-read agrees with the judges on 5 of 6 decision rows.** It finds this repository's
  `uniqueCaseName` not EXPRESSIBLE, because it is `private`. Without it N is 6 across 4, which still clears.

The decision line:

```
DECISION: BUILD  N = 7 over 5 local repositories (bar: ≥ 5 across ≥ 2)  N_gated = 6  gate precision 8/9 (89%)
law-only (reduced suite): 5 by assertion, 0 by crash/timeout/memory   law-only (full suite): 0
law 10, suite 37, reduced 31, viable 37   N_setup 1  N_unmet 0  N_layout 0  N_wide 6 (24 of 24 judged, estimate 6.0)  N_undetermined 0  unparsable files dropped 0
without EXPRESSIBLE: N 12  N_unmet 0  N_layout 5  N_wide 7
SENSITIVITY N + N_setup: 8 over 5 repositories — clears the population bar
SENSITIVITY N + N_unmet + N_layout + N_wide: 13 over 11 repositories — clears the population bar
SENSITIVITY N + N_undetermined: 7 over 5 repositories — clears the population bar
SENSITIVITY decisive count with DiagramIdentifiersTests kept: 4 (resting on its exclusion: M039)
```

## The census

The pass reads every `func` with a body and looks for the cues of scope §1.2. Each is read off the body, with
comments and literal text blanked but interpolations kept:

- **TEST**: the body tests something against a collection (seven forms, from `.contains(` to
  `.insert(…).inserted`);
- **SUFFIX**: it decorates with a counter;
- **TIED**: a decoration is tied to a test (#669's "on a hit decorates the candidate");
- **RETEST**: a `while` re-tests a value its body reassigns;
- **FRESH**: a stored counter decorates a returned name, with no test (the counter-only generator);
- **NAME**: a word of the name starts with `uniq`, `fresh` or `disambig`.

A function is a candidate when TEST ∧ (TIED ∨ RETEST), or FRESH, or NAME ∧ (TEST ∨ SUFFIX) holds. A blind
hand-check then judges every candidate.

| group | subjects | repositories | files | candidates | GATED | owing (UNIQUIFIER or MEMOIZING) | owing ∧ EXPRESSIBLE groups |
|---|---:|---:|---:|---:|---:|---:|---:|
| **decision** (#666's manifest and funnel subjects, read from their roots) | 36 | 33 | 7,338 | 44 | 9 | 12 | **7** |
| unmet | 5 | 5 | 961 | 8 | 0 | 0 | 0 |
| layout (#667's graph-layout corpus) | 18 | 18 | 1,270 | 23 | 2 | 6 | 0 |
| wide (every other local Swift directory) | 67 | 67 | 12,879 | 24 | 2 | 7 | 6 |
| **all** | **126** | **123** | **22,448** | **99** | **13** | **25** | **13** |

105 candidates were found before copies merged. Four rows carry copies: two OpenAPIKit functions repeated
across its `OpenAPIKit` and `OpenAPIKit30` modules, and swift-mermaid's vendored dagre port, whose `uniqueId`
and `uniqueReverseId` are copies of lukilabs/dagre-swift's. No file was dropped as unparsable.

**The seven decision groups:**

| repository | function | verdict | GATED | body |
|---|---|---|---|---|
| SwiftUMLStudio | `DiagramIdentifiers.id(forKey:sanitizing:)` | MEMOIZING | yes | keeps the law |
| SwiftUMLStudio | `LayoutGraphBuilder.NodeIdAllocator.issue(for:)` | UNIQUIFIER | yes | keeps the law |
| swift-syntax | `BasicMacroExpansionContext.makeUniqueName(_:)` | UNIQUIFIER | yes | keeps the law |
| swift-syntax | `PluginMacroExpansionContext.makeUniqueName(_:)` | UNIQUIFIER | yes | keeps the law |
| swift-foundation | `DebugStringConversionState.addCapture(_:)` | UNIQUIFIER | no | keeps the law |
| swift-package-manager | `DOTManifestSerializer.label(for:)` | UNIQUIFIER | yes | **breaks it** (latent) |
| this repository | `ViewModelActionEnumEmitter.uniqueCaseName(for:taken:)` | UNIQUIFIER | yes | keeps the law |

The scope named four of them in advance. The other three are swift-foundation's `addCapture`, a counter-only
generator that names a predicate's captured values; SwiftPM's `label(for:)`, which labels a build manifest's
jobs for `swift build --print-manifest-job-graph`; and SwiftUMLStudio's `NodeIdAllocator`, the allocator PR #77
wrote to replace `uniqueId`. Prediction 1 flagged that last one as unchecked.

Five more decision groups owe the law but are not EXPRESSIBLE:

- **`DiagramContext.uniqName`**: SETUP, because its contract requires `reserveIdentifiers(drawing:)` first;
- **swift-foundation's `NSPredicateConversion.makeLocalVariable`**: a `fileprivate` type in a file built only
  under `FOUNDATION_FRAMEWORK`;
- **swift-nio's `ChannelPipeline.nextName()`**: `private`;
- **swift's `AsyncDemotion` `nameOf`**: a function nested inside another;
- **swift's `PropertyListSerializer.id(of:)`** (in `swift-dev-utils`): `fileprivate`, and its body breaks the
  law (below).

So N without EXPRESSIBLE is 12, and the unmerged count of owing, EXPRESSIBLE decision rows is 7.

**Outside the decision universe**, the wide group holds 6 EXPRESSIBLE groups: SwiftPlantUML's `uniqName`,
XcodeProj's `ReferenceGenerator.fixReference`, Yams's `uniqueAlias`, apollo-ios's `requestId`, supabase-swift's
`makeRef` and swift-crypto's ARC presentation `update`. The layout group holds 5 owing groups and none
EXPRESSIBLE: each is `private`, nested or static.

**Sensitivity**, as `decide` prints it. Every sum clears the bar, and so does N alone:

- N + N_setup: 8 across 5 repositories;
- N + N_unmet + N_layout + N_wide (its estimate, every wide candidate judged): 13 across 11;
- N + N_undetermined: 7 across 5. No verdict was UNDETERMINED.

## The gate #669 names

#669 wrote down three criteria a template would read: state kept across calls and a returned name; a test of a
candidate against the names already issued, decorating it on a hit; and a write back to that state. Applied
mechanically as STATE ∧ RETURNS ∧ TEST ∧ (TIED ∨ RETEST) ∧ WRITE (scope §1.4), the gate marks 9 decision rows,
and **8 of them owe the law**:

| GATED row | verdict |
|---|---|
| SwiftUMLStudio `DiagramIdentifiers.id` | MEMOIZING, EXPRESSIBLE |
| SwiftUMLStudio `NodeIdAllocator.issue` | UNIQUIFIER, EXPRESSIBLE |
| SwiftUMLStudio `DiagramContext.uniqName` | UNIQUIFIER, SETUP |
| swift-syntax `makeUniqueName`, twice | UNIQUIFIER, EXPRESSIBLE |
| swift-package-manager `DOTManifestSerializer.label` | UNIQUIFIER, EXPRESSIBLE |
| this repository's `uniqueCaseName` | UNIQUIFIER, EXPRESSIBLE (the re-read says not, below) |
| swift's `PropertyListSerializer.id(of:)` | MEMOIZING, not EXPRESSIBLE |
| swift-foundation `AutoDictionary.insert` | **NOT-UNIQUIFIER**: a pool that hands a released key out again |

The one miss is a shape the judging brief excludes by name, a recycling pool. Outside the decision universe the
gate admits 4 more rows, and all 4 owe the law: MermaidKit's `registerCluster` and `openSubgraph`, SwiftPlantUML's
`uniqName` and swift-crypto's `update`. So the gate is right on 12 of the 13 rows it admits anywhere.

**What the gate misses (R2).** Four owing decision groups have no GATED member: `addCapture`, `makeLocalVariable`,
`nextName` and `nameOf`. The first three are counter-only generators, which have no test for the gate's TEST
conjunct to find, as scope §9 expected. `nameOf` memoizes through a dictionary local to its enclosing call. Only
`addCapture` is EXPRESSIBLE, so N_gated is 6 against N's 7.

## The hand-check

**Calibration first.** Two judges classified the nine items of `fixtures/uniquifier-law/calibration.md` before
any packet, and both matched every expected answer (scope §4.2). That includes SETUP on `uniqName` at `c6c82e3`,
the *body disagrees* flag on its `e36da59` body, LOOKUP on `e36da59`'s `uniqueId`, BATCH, and three
NOT-UNIQUIFIER look-alikes.

**Then 99 rows in 13 packets.** Two judges read each packet blind, and they agreed on 96 rows' verdict,
EXPRESSIBLE and SETUP. The three splits were all on EXPRESSIBLE: each time one judge counted a `private` or
`fileprivate` function as reachable, and judge C, reading the brief's `@testable` rule, said it was not.

| | UNIQUIFIER | MEMOIZING | BATCH | LOOKUP | NOT-UNIQUIFIER | UNDETERMINED |
|---|---:|---:|---:|---:|---:|---:|
| decision (44) | 9 | 3 | 0 | 0 | 32 | 0 |
| unmet (8) | 0 | 0 | 5 | 0 | 3 | 0 |
| layout (23) | 5 | 1 | 2 | 0 | 15 | 0 |
| wide (24) | 7 | 0 | 0 | 3 | 14 | 0 |

The NOT-UNIQUIFIER rows fall into these kinds:

- **deduplication**, which #669 warned a NAME cue mostly finds: `uniqued`, `appendUnique`, `orderedUnique` and
  their kin;
- **formatting and parsing**: summary and report text, diagram parsers;
- **predicates and graph walks**: `hasUniqueAttribute`, `isFreshConstruction`, ancestor walks;
- **graph colourings**, which repeat colours by design;
- **statistics counters**;
- **one recycling pool**, `AutoDictionary.insert`.

The five BATCH rows in the unmet group are all swift-docc's link disambiguation, which makes a whole set of
paths distinct in one call. The three LOOKUP rows (Quick's selector names and exhaust's `availableLocalName`)
compute a free name and leave the registering to their caller, as `e36da59`'s `uniqueId` did.

## Seven bodies that break the law, hand-checked

The judges flagged 7 rows *body disagrees*: a call sequence the contract allows on which the body returns one
result twice. Scope §8 requires each to be hand-checked before it is listed. One agent per row traced the
witness on the census revision, ran it, and read the default branch through `gh api`. Every witness held, and
every default branch still holds the census body.

| row | group | witness run on | reachable | recommendation |
|---|---|---|---|---|
| SwiftPlantUML `PlantUMLContext.uniqName` (`0f5875e`) | wide | the package and its CLI | **yes** | **file** |
| Yams `UniqueAliasProvider.uniqueAlias` (`df801bc`) | wide | the package, end to end | **yes** | **file** |
| swift-package-manager `DOTManifestSerializer.label` (`d274b83`) | decision | a verbatim transcription | no | mention |
| swift `PropertyListSerializer.id(of:)` (`e739e65`) | decision | its sources, with one import stubbed | no | mention |
| MermaidKit `DOTParserImpl.registerCluster` (`64c19fb`) | layout | the module | no | mention |
| swift-mermaid `GraphUtil.uniqueId` (`ee4b50b`) | layout | the vendored target | no | mention |
| Graffle `SVGExport.Writer.id` (`53b93b0`) | layout | a verbatim transcription | no | mention |

**Five of the seven are #669's own defect: a decoration that is never checked against the names already
issued.** The other two, Yams's and swift's, take a caller's name verbatim beside the names they generate, and
never check either against the other.

**The two reachable ones:**

- **SwiftPlantUML's `uniqName`** is the pre-#65 body of #669's witness, in the project SwiftUMLStudio descends
  from. It checks only the undecorated name, and its decoration `name + index` is never checked or recorded. With
  the CLI's default `--show-extensions`, `struct Vector`, `Vector2` and `Vector3`, each with an extension, give
  `extension Vector` the alias `Vector2`. The script then binds two elements to one PlantUML alias, attaches the
  extension's members to `Vector2`, and draws a false `Vector <.. Vector2 : ext`. The repository looks dormant
  (last push 2024-05-07), and no issue covers it.
- **Yams's `UniqueAliasProvider`** returns a value's own `yamlAnchor` unchanged, and issues counter anchors `1`,
  `2`, … without checking either set against the other. Yams's own auto-aliasing writes numeric anchors. Reading
  such a file into `YamlAnchorCoding` types captures those names, and re-encoding with a new repeated value
  issues a counter anchor equal to a captured one. The emitted `*N` then points at the wrong node, and
  `YAMLDecoder` silently returns the wrong values, under both public aliasing strategies. No issue covers it.

**The five latent ones** break the law only on inputs no caller in their repository passes:

- **SwiftPM's `label(for:)`** counts only undecorated tool names, so a tool named `phony 1` would collide with
  the second `phony` job's label. Every tool in an `LLBuildManifest` has a fixed name, none ending in ` <n>`.
- **swift's `PropertyListSerializer.id(of:)`** gives a custom id `OBJ_2` and a later generated id the same
  string. Every custom id in the repository is `TARGET_<name>`, and the clash would make `generatePlist` throw
  (or trap in a debug build), not corrupt its output.
- **MermaidKit's `registerCluster`** decorates a repeated id as `§sub<n>` without checking it. Its only caller
  passes names that start with `cluster`, which never equal a decoration.
- **swift-mermaid's `uniqueId`**, and its copy in lukilabs/dagre-swift, join a prefix and a counter with no
  separator, as lodash's `uniqueId` does: `uniqueId("a1")` at 1 and `uniqueId("a")` at 11 both give `a11`. Every
  caller passes a literal prefix with no trailing digit, and a 200,000-call control over those prefixes gave
  200,000 distinct ids. The judges called its static counter impossible to make fresh, but
  `resetIdCounter()` ("for testing") resets it. That is a setup call, so the row stays non-EXPRESSIBLE.
- **Graffle's `Writer.id`** has the same no-separator shape. Its two callers pass `grad` and `shadow`.

The reachable two were offered for upstream filing (scope §8). Both now reproduce at upstream HEAD as tests with
minimal patches, in `fixtures/uniquifier-law/upstream-repro/` (tracked in #691). So does the GRDB `resolvedNames`
collision #669 had reasoned about without running it. With the user's approval all three were filed on 2026-10-28:
MarcoEidinger/SwiftPlantUML#87, jpsim/Yams#490 and groue/GRDB.swift#1892. Results and
the agents' traces are in `fixtures/uniquifier-law/handcheck-2026-10-28.json`, from
`fixtures/uniquifier-law/handcheck-workflow.js`.

## The re-read, beside the decision

Scope §8 takes the judges' verdicts. Because the outcome turned on them, the six decision groups the body check
did not cover were read again, by two agents with the same rubric, and reported **unscored**. Each also built or
modelled its rows and fuzzed them.

- **They agree with the judges on 5 of the 6.** Both `makeUniqueName`s survived over 400,000 calls each
  (adversarial names, fuzzing, and 105,000 repeats of names that start with digits), `addCapture` 26,000 on a
  verbatim copy, `DiagramIdentifiers` every sequence of up to four pairs over a 5×5 alphabet under
  six sanitizers (2,441,400), and `NodeIdAllocator` every reserved subset of a seven-name alphabet with up to
  five issues (228,704), with no repeat.
- **They disagree on `uniqueCaseName`'s EXPRESSIBLE.** It is `private static`, and `@testable import` lifts
  `internal`, not `private`. Both judges marked it EXPRESSIBLE anyway, against the brief. The law can be stated
  only one hop up, on `emit(typeName:actions:)`. **Without it, N is 6 across 4 repositories, which still
  clears.**
- **`NodeIdAllocator`'s law has a dependent domain.** It holds only for names reserved through
  `init(reserving:)`; `issue` on an unreserved name can repeat (`A`, `A`, `A_1` gives `A`, `A_1`, `A_1`). The
  reservation is an initialiser argument, not a separate call, so SETUP is false, but a generator must draw the
  inputs from what it reserved.
- **`uniqueCaseName` has a near miss the string law does not see.** Swift-syntax's raw token text keeps
  backticks, so ``func `add`()`` and `func add(x:)` give the case names `` `add` `` and `add`: two strings, one
  Swift identifier. That needs a needlessly backticked overload, and nothing in the corpora writes one.

## The kill arm

The law was written by hand as `fixtures/uniquifier-law/UniquifierLawTests.swift`. Its two properties each run
over 1,000 sequences drawn by SplitMix64:

- **U1**, in each of the four formats: after `reserveIdentifiers(drawing:)`, `uniqName` issues no declared alias
  twice. Half the draws are 1–16 items named `a` or `b`, bare or followed by `0`, `1`, `2`, `10`, `11` or `_2`.
  The other half are dense, 11–24 items over `a`, `a1`, `b` and `b1`, so the counter reaches `10` within one
  sequence.
- **M1**: `DiagramIdentifiers(sanitize: DepsScript.mermaidId)` gives equal keys equal ids and distinct keys
  distinct ids, over keys built from `a`, `_`, `.`, `-` and `2`.

**U0**, #669's law exactly as written, with no setup call, ran once as S0 on the unmutated export and never in
the kill loop.

`scripts/uniquifier_kill_arm.py` copied the law into an export of SwiftUMLStudio at `c6c82e3`. It ran every
mutant three ways (scope §5.4):

- under the law;
- under the full suite less the law, 1,823 tests;
- under the **reduced** suite, which also drops the four suites written from the law's own findings:
  `DiagramContextAliasTests`, `ClassDiagramAliasTests` and `ClassDiagramEdgeIdTests` (PR #65, for #54) and
  `DiagramIdentifiersTests` (PR #52, for a sanitizer collision). That is 39 tests out, 1,784 left.

The runner used Xcode 27's Swift 6.4 (`swiftlang-6.4.0.34.1`). **Every runner control held**, so the run is
measured:

| control | what it checks | result |
|---|---|---|
| RC1 | the unmutated export | the law passes U1 in all four formats and M1; the suite passes 1,823 tests |
| RC2 | `uniqName`'s pre-#65 body: one suffix from the counter, never re-checked | the law fails U1 in every format (406–554 sequences per 1,000) and passes M1. The full suite fails 20 tests. **The reduced suite still fails 2**: *a suffix never takes a conformance that only a merged extension's edge names* and *an extension that takes the next free suffix draws its edge from it* |
| RC3 | an equivalent edit, `contains(name)` → `firstIndex(of: name) != nil` | both survive |
| RC4 | an edit that does not compile | reported UNVIABLE, not counted as a kill |
| RC5 | the export's tree after the run | hashes as before |
| RC6 | the law's summary lines, twice | identical |
| RC7 | a planted hang: `suffix += 1` removed from `DiagramIdentifiers` | TIMEOUT under both |

**S0: #669's law as written fails on the fixed code**, as prediction 6 said. With nothing called first,
`uniqName` issues one alias twice in 146 (Mermaid), 150 (Nomnoml), 167 (SVG) and 200 (PlantUML) of 1,000
sequences. The first Mermaid counterexample is `class a1`, `macro a`, `class b2`, `protocol b0`, `extension a`,
`macro b0`, `class a`, `struct a2`: the repeated `class a` takes the suffix `a2`, and the first declaration of
`struct a2` then keeps its own name unchecked. `reserveIdentifiers` exists to prevent exactly this, and its doc
says it must run "before the first alias is issued". So the law holds only after the setup call, and a template
that cannot see that call would propose a false law on correct code.

**39 mutants on the law's call tree; 37 viable.** The other two, M020 and M037, apply `-` to two `String`s and
do not compile. `DiagramContext`'s other functions (`addLinking`, `text`, `collectNestedTypeConnections`,
`supertypeEnd`) hold 27 more mutants that no alias reaches, which are counted, not run.

| | mutants | law | full suite | reduced suite |
|---|---:|---:|---:|---:|
| **issuing**: `declaresIdentifier`, `reserveIdentifiers`, `uniqName`, `linkTarget`, `id` | 24 | 10 | 24 | 18 |
| **edges**: `addExtensionEdge`, `drawsExtensionEdge`, `nomnomlEdge` | 13 | 0 | 13 | 13 |
| **all** | **37** | **10** | **37** | **31** |

- **By function**, the law catches `declaresIdentifier` 3 of 3, `id` 2 of 2, `uniqName` 3 of 7,
  `reserveIdentifiers` 2 of 8 and `linkTarget` 0 of 4.
- **Law and suite together.** The suite catches all 37 and the law 10, so no mutant survives both, and none
  needed an equivalence reading (scope §5.6).
- **Mechanisms.** The law detects 9 by assertion and 1 by timeout. That is M038, where a negated
  `taken.contains(candidate)` loops forever on a new key. The suite's figures are 36 and 1.
- **Flakes.** Under §5.4's flake rule, every suite assertion detection beside a law detection was run again (13),
  and every one repeated.
- **Single failing tests.** Every suite kill made by one failing test was made by *uniqName appends plantuml style
  to extension connection when dependency style is configured* (M034 and M035, in `addExtensionEdge`).

**Law-only against the reduced suite: 5, all by assertion and all issuing. That is the decisive count.**

| mutant | function | edit | the law fails | full suite |
|---|---|---|---|---|
| M013 | `reserveIdentifiers` | `declaresIdentifier(of: item)` negated, so the declared names go unreserved | U1, all four formats (120–225 per 1,000) | 9 tests, all in the four derived suites |
| M014 | `reserveIdentifiers` | `takenIdentifiers.insert(fullName)` removed, so no drawn name is reserved | U1, all four (136–225) | 8 |
| M025 | `uniqName` | `declaresIdentifier(of: item)` negated, so an issued alias goes unrecorded | U1, all four (128–179) | 4 |
| M026 | `uniqName` | `takenIdentifiers.insert(newName)` removed | U1, all four (123–179) | 4 |
| M039 | `DiagramIdentifiers.id` | `taken.insert(candidate)` removed | M1 (198) | 6, `DiagramIdentifiersTests` among them |

**With `DiagramIdentifiersTests` kept, the decisive count is 4**: M039 rests on that suite's exclusion. Scope §8
asks the first paragraph to say so only if the count were 0.

**Against the full suite, the law catches nothing alone (0).** Every one of its 10 detections is also a suite
detection. The four derived suites hold the law's own examples, as #667's PR #64 tests did.

**The reduced suite misses a sixth mutant, M018**, which drops the reservation of a hidden parent's name. The law
cannot see it, because U1's draws carry no nesting. The law's other 26 misses are where scope §9 said they
would be:

- the 13 edge mutants, by design;
- `linkTarget`'s 4, which change an edge's target text;
- 5 more in `reserveIdentifiers`, which reserve edge ends (supertypes, raw types, hidden parents) or record the
  type an extension extends, none of which U1 draws;
- 4 in `uniqName`: M019 (negating `uniqElementNames.contains` suffixes every name, which stays distinct), and
  M022–M024 in its extension-edge branch.

## The predictions, scored

| # | prediction (scope §7) | result | blind? |
|---|---|---|---|
| 1 | N = 4 across 3 repositories, so DECLINE (population); `uniqName` UNIQUIFIER with SETUP, so N + N_setup = 5 | **missed**: N = 7 across 5. All four named groups are there; `addCapture`, SwiftPM's `label` and SwiftUMLStudio's `NodeIdAllocator` are the other three. `uniqName` was judged as predicted, so N + N_setup = 8 | partly |
| 2 | N_gated = N, and gate precision ≥ 70% | **half**: precision 89% held; N_gated is 6, because `addCapture` is a counter-only generator with no test to gate | partly |
| 3 | no decision row is *body disagrees* | **missed**: SwiftPM's `label` and swift's `PropertyListSerializer.id`, both latent | partly |
| 4 | R3 finds both `makeUniqueName`s and `uniqueCaseName` as candidates; `resolvedNames` not read; swift-foundation's `unique(_:)` read, not a candidate | **held** | partly |
| 5 | a dagre port's counter is UNIQUIFIER in the layout group; if static, N_layout = 0 and it shows without EXPRESSIBLE | **held**: swift-mermaid's static `uniqueId` and `uniqueReverseId`; N_layout 0, 5 without EXPRESSIBLE | partly |
| 6 | RC1 holds, and S0 fails in every format | **held**: 146–200 failures per 1,000 | no |
| 7 | the reduced suite does not detect RC2, the pre-#65 body | **missed**: two tests outside the four derived suites catch it, *a suffix never takes a conformance that only a merged extension's edge names* and *an extension that takes the next free suffix draws its edge from it* | partly |
| 8 | decisive count 1–8, every decisive kill issuing; full-suite law-only 0; the `DiagramIdentifiers` kill rests on leaving its suite out | **held**: 5 (M013, M014, M025, M026, M039), all issuing; full-suite law-only 0; M039 rests on `DiagramIdentifiersTests`' exclusion. The three `declaresIdentifier` mutants it listed as candidates are caught by the reduced suite too | no |
| 9 | the law detects ≤ 12 of 39, the suite ≥ 25 | **held**: 10 and 37, of 37 viable | no |

## What else the census saw

- **R3, #669's grep sites by name.** The census recorded all 16 `func`s with one of #669's names. Both
  swift-syntax `makeUniqueName`s and `uniqueCaseName` are GATED candidates. GRDB's `resolvedNames` is not a
  `func` and was not read. swift-foundation's `unique` (`BPlistEncodingFormat`) was read and is not a candidate.
  Neither is a third swift-syntax `makeUniqueName` (`MacroExpansion.swift`), swift-testing's, or GRDB's two
  `unique` methods: each carries NAME, and none a TEST or a SUFFIX.
- **Dirty checkouts.** SwiftUMLStudio was asserted clean at `c6c82e3`, and every layout clone at its revision.
  Thirteen other subjects had local changes and were read as they were, among them SwiftPlantUML and swift-sdk
  (wide). The hand-check read SwiftPlantUML's row at its revision with `git show`, and the default branch holds
  the same file.

## Disclosures and instrument limits

- **Not blind.** Predictions 1–5 and 7 are partly blind, resting on #669's text and on what was read before the
  freeze; 6, 8 and 9 rest on code read before the freeze, as scope §7 says.
- **The judges erred once against the brief**, on `uniqueCaseName`'s EXPRESSIBLE, and the frozen rule counts
  their verdict. The re-read reports it; the decision does not change on it.
- **The hand-check and re-read ran while the kill arm ran.** Their agents built four packages and several
  single-file probes in scratch directories, so the kill arm shared the machine. The law's assertions do not
  depend on timing, and every suite assertion beside a law detection repeated on its rerun.
- **One subject for the kill arm.** Its counts are SwiftUMLStudio's, against a suite that already holds the law's
  examples (PR #65's three suites and PR #52's `DiagramIdentifiersTests`). They are not a rate.
- **Hand-written generators.** The law's draws are written by hand and narrowed on purpose, so a drawn name can
  equal another plus a suffix. A template would need a generator that collides like that, and would need to
  build `SyntaxStructure` (scope §9).
- **The census finds only what its cues reach** (scope §9): no computed property, subscript, initialiser or
  closure; nothing whose counter is static state read through a helper.

## So what

- **The gate passes: under scope §8, #669 stays open, and building a template is a separate issue.** All three
  measures clear:
  - 7 groups across 5 repositories (6 across 4 on the re-read);
  - #669's own gate is right on 8 of 9 decision rows;
  - 5 decisive kills.
- **What a template would have to get right, as measured here:**
  - **The setup call.** #669's law as written is false on SwiftUMLStudio's correct code (S0: 15–20% of draws),
    and the gate admits that function. A template must decline a GATED subject whose contract names a call that
    must come first, or state the law after that call. That is one of the 9 GATED decision rows.
  - **Visibility.** Four of the five non-EXPRESSIBLE decision groups are `private`, `fileprivate` or nested,
    and the judges missed a fifth, `uniqueCaseName`. The template must read access level, as other templates'
    declines do (`visibility-widenability.md`).
  - **Collisions.** The law fails only when one drawn name equals another plus a suffix. A generator drawing
    realistic names never collides, so the template's generator must narrow its alphabet on purpose (CLAUDE.md's
    rule for collision-dependent laws). This prototype's draws were written by hand to do that.
  - **Two forms.** A memoizing uniquifier, one with an early return of a stored id, owes the memoizing law, and
    the plain law is false on it. One of the 7 groups is memoizing.
  - **A dependent domain.** `NodeIdAllocator`'s law holds only over the names it reserved when it was built.
  - **The counter-only generator is outside the gate.** `addCapture` owes the law and is EXPRESSIBLE, but has no
    test for the gate to find. The gate is precise because it requires one, so it misses this shape.
- **As a test SwiftUMLStudio could own, the law adds nothing today.** It catches nothing the full suite misses.
  Its 5 decisive kills are caught by the suites PR #65 and PR #52 wrote for the same defects. Without those
  suites, it catches 5 of the 6 issuing mutants the rest of the suite misses. That matches #667.
- **The law paid off outside its witness.** Reading the population turned up two reachable defects in other
  repositories: SwiftPlantUML's (#669's own shape) and Yams's (a caller's names beside generated ones). Both are
  now filed upstream, with a GRDB alias collision #669 had only reasoned about.

## Reproducing

```bash
python3 scripts/uniquifier_census.py run census.json
python3 scripts/uniquifier_census.py packets census.json judging/packets/   # writes judging/index.json
# copy fixtures/uniquifier-law/judge-brief.md and calibration.md into judging/brief/, run
# fixtures/uniquifier-law/judge-workflow.js with J set to judging/, and write each judge's records to
# judging/out/packet-NN.{A,B,C}.json
python3 scripts/uniquifier_census.py join judging/index.json judging/out/ judgements.json
git -C ~/xcode_projects/SwiftUMLStudio archive c6c82e3 | tar -x -C export/
python3 scripts/uniquifier_kill_arm.py run export/ kill-arm.json
python3 scripts/uniquifier_census.py decide census.json judgements.json kill-arm.json
# then run fixtures/uniquifier-law/handcheck-workflow.js over the rows flagged body disagrees and the other
# EXPRESSIBLE decision rows. No mutant survived both the law and the suite, so there was nothing to read for
# equivalence.
```

The census needs the frozen universe (scope §2) on this machine, and the kill arm needs Xcode 27's Swift 6.4.
