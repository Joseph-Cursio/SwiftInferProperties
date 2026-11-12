# Does #673's emitter presence law have a population? E = 14, but 9 of them in this repository: DECLINE (#673)

> **Status:** `measured` · **As of:** 2026-11-12
>
> **Decision: DECLINE (concentration)** under `docs/plans/emitter-presence-census-scope.md` §7.
> - E = 14 clears the bar of 5, and precision is 31/41 = 75.6% against the 70% bar.
> - But this repository's own CLI and core renderers hold **9 of the 14**. Without them, E is 5, and SwiftUMLBridge
>   holds 4 of those.
>
> The kill arm turned #673's REASONED kills into a run. Template presence kills all six element-line mutants, bare
> presence kills four, and determinism kills none. At SwiftUMLStudio HEAD, the law #673 wrote for its survivor is
> **false**: the fix for SwiftUMLStudio#52 made the emitters' encoder a stateful uniquifier.

#673 counts 39 `RemoveSideEffects` mutants in SwiftUMLBridge.
- Each one deletes the per-element `append` inside an emitter's `for` loop.
- Generated laws executed none of them.
- Two of them survive the hand-written suite too.

**The proposed law is a characterisation law read from the body.** Each element the loop visits owes its line. The
law states that line as the element's interpolation together with the literal text written around it.

Before the run, the user chose the rule **BUILD only if all three hold**:
- `|E| ≥ 5`;
- no repository holds more than half of E;
- at least 70% of admitted rows are true as read, `whole-to-parts-partition-prediction.md`'s bar.

The reader, universe, controls, predictions and decision were frozen in the scope (`8c51f2c4`) before the harness
read any subject.

## Instrument

| piece | where |
|---|---|
| scope, frozen first | `docs/plans/emitter-presence-census-scope.md` (`8c51f2c4`; amendments A and B at `648f4bd7`, before the run) |
| kill arm | `fixtures/emitter-presence/kill-arm/`, run by `scripts/emitter_presence_kill_arm.py` → `fixtures/emitter-presence/kill-arm-2026-11-11.json` |
| census harness | `fixtures/emitter-presence/census-run/` (the reader `R`, a per-repository function index for helper hops, controls), committed at `648f4bd7` before it read the universe |
| subjects, census | `fixtures/emitter-presence/subjects-2026-11-12.json`, `fixtures/emitter-presence/census-2026-11-12.json` |
| hand-check | `fixtures/emitter-presence/handcheck-2026-11-12.json` |
| sensitivity run | `fixtures/emitter-presence/census-strict-tail-2026-11-12.json` (see *Recorded after the first report*) |
| report | `python3 scripts/emitter_presence_census.py report fixtures/emitter-presence/census-2026-11-12.json fixtures/emitter-presence/handcheck-2026-11-12.json` |

## Step 1: the kill arm

**The subject** is `ComponentScript.buildPlantUMLText` and `buildMermaidText`, verbatim from SwiftUMLStudio
`e36da59` (the mutation run's revision).
- **Mutants:** the nine recorded `RemoveSideEffects` mutants, six on element lines and three on frame lines (`}`,
  `@enduml`, `end`).
- **Trials:** 100 on one seed.
- **Generators:**
  - **naïve:** the run's own stub. `letterOrNumber.string(of: 0...8)` names, endpoints drawn independently;
  - **disciplined:** #673's stub requirements. Distinct, non-overlapping names per kind, and endpoints drawn from
    the drawn components.

| law | naïve: element lines | naïve: frame lines | disciplined: element lines | disciplined: frame lines |
|---|---|---|---|---|
| determinism (the run's advisory) | 0/6 | 0/3 | 0/6 | 0/3 |
| bare presence (`contains(name)`) | 6/6 | 0/3 | **4/6** (misses L55, L87) | 0/3 |
| template presence (#673's law) | **6/6** | 0/3 | **6/6** | 0/3 |

- **The original passes every law under both generators**, so the control held. This includes `ComponentScript.swift:82`, the
  mutant that survives both suites: template presence kills it.
- **Bare presence missed the wrong lines.**
  - The scope predicted it would miss L48 and L80, because a component name recurs in aliases and edges.
  - It missed the **edge** lines (L55, L87) instead. Under the disciplined generator, endpoints are drawn component
    names, which the component lines already print.
  - It killed L48 and L80 whenever some component had no edge.
  - Either way the point #673 made stands: bare presence is blind where names repeat, and the line template is not.
- **The naïve generator lost no kills.** The prediction allowed "the same", but the mechanism #673 feared did not
  bite here. Empty names were frequent (32 of 100 draws), yet every mutant still had a non-empty witness in the
  draw.
- **A law-writing note.** Foundation's `contains("")` answers `false`, so bare presence written naïvely fails on the
  *original* whenever the generator draws an empty name. The arm states it as `isEmpty || contains`.

## Step 2: the census

The universe is #670's 39 roots plus this repository's `Sources/`: 33,725 functions in 4,668 files over 40
subjects, the same universe #671 and #672 read.

| funnel | rows |
|---|---|
| recall pool (shape passes, a `for` and an `append`/`+=` in the body) | 351 |
| admitted by `R` | **41** (SwiftUMLBridge 16, this repository 14, SwiftPropertyLaws 5, GRDB 2, one each in SwiftLintRuleStudio, SwiftFormatRuleStudio, pbt-workbook-grader and SwiftAssist) |
| of which helper tier (≥ 1 resolved hop) | 16 (25 as-written) |
| emittable candidates by syntax (not private) | 24 |
| reader defects (hand-check: `law` or `read` false) | **10** |
| precision | **31/41 = 75.6%** |
| **E** (candidates passing `law`, `read`, `emittable`) | **14**: this repository 9, SwiftUMLBridge 4, SwiftAssist 1 |

**Why the pool's 310 refusals were refused:**

| reason | rows |
|---|---|
| no obligation | 102 |
| a return other than the accumulator | 86 |
| accumulator not of §2.2's forms | 44 |
| obligations but none statable | 39 |
| no accumulator | 27 |
| a tail mutation | 10 |
| an exit in the loop | 2 |

**The widenings, priced, not counted:**
- **W1** (a `sorted()` / `enumerated()` / `filter` source) appears in 12 rows. It would make up to 5 more rows statable,
  across 5 repositories, none of them hand-checked.
- **W2** (`String?` returns) would admit no row.
- **W3** (`appendAsNewLine`) is 2 rows, both SwiftUMLBridge's.

### E, row by row

| repository | rows in E |
|---|---|
| SwiftInferProperties (9) | `EffectAnnotationRenderer.render`, `SuggestionRenderer.renderGeneratorRecipes`, `DocstringAdvisoryRenderer.render`, `InteractionBridgeWriter.emit`, `renderConventionRoleSummary`, `renderStableIdentitySummary`, `Query.renderEntries`, `Query.renderCombined`, `SuggestRefactors.renderClusters` |
| SwiftUMLBridge (4) | `SVGRenderer.render`, `SequenceSVGRenderer.renderFromLayout`, `ComponentSVGRenderer.renderSVG`, `componentSVGLines` |
| SwiftAssist (1) | `XMLToolCallProtocol.renderToolCatalog` |

**Every one of the 9 in this repository has a hand-checked derivable generator.** They are library-target functions
over value types of strings, integers, dates and `CaseIterable` enums. So the concentration is not an artefact of
emittability being judged leniently here. This repository writes many small text renderers over its own value
types, and the toolchain's other repositories mostly do not.

### Not emittable

| rows | why |
|---|---|
| GRDB's 2 (`FTS4`/`FTS5.moduleArguments`) | take `Database` and table-definition **classes** |
| SwiftPropertyLaws' 4 candidates | sit in the `PropertyLawDiscoveryTool` **executable target**, which §2.8 excludes |
| `ViewModelVerifyInteractionSurvey.render` | its `FoldBack` holds an array of tuples |
| the 17 private rows | 11 of SwiftUMLBridge's 16 are `private extension` builders, and are surfaced with widening advice, never counted |

### The 10 reader defects

Each is a misread by the prototype reader. Each counts against precision, as §9 requires.

| row | defect |
|---|---|
| SwiftUMLBridge `ComponentScript.buildPlantUMLText` / `buildMermaidText`, `DepsScript.buildMermaidText` | `ids.id(for:)` read as a one-argument **encoder**. `ids` is a local `var DiagramIdentifiers`, a stateful uniquifier, so the id depends on every name claimed before (see below). |
| `DepsScript.buildNomnomlText` | a let bound to a two-argument helper call followed as a helper, whose write is conditional (`if let stereotype`) and escaped (`nomnomlEscaped`) |
| `ActivityScript.buildPlantUMLText`, `ActivitySVGRenderer.renderFromLayout` | the helper's write sits behind an `if let` or a different branch (`[*]` for start and end nodes; `if let label`) |
| `ActivityScript.buildMermaidText`, pbt-workbook-grader `Grade.render`, `ViewModelVerifyInteractionSurvey.render` | an early return that is not a literal (or that guards one loop's source but not another's) drops loops without being read as a guard |
| `renderDefensiveCopySummary` | the helper site chosen is a ternary's false arm, with its condition unrecorded |

**SwiftUMLBridge's own emitters read worst:** 7 of its 16 admitted rows are defects (44%). All but one is a helper or
encoder misread. The subject the law was written for is exactly where a body reader has to follow the most
code.

### The law #673 wrote for the survivor is false at SwiftUMLStudio HEAD

#673 sketched the survivor's law calling the encoder:

```swift
#expect(text.contains("\(ComponentScript.safeAlias(dependency.from)) -.-> \(ComponentScript.safeAlias(dependency.to))"))
```

**At `e36da59` that law is true.** The kill arm ran it, and the original passed.

**At HEAD `9ad7631` it is false.** SwiftUMLStudio's `363168e`, *Stop two names that sanitize alike from merging into
one diagram node* (the SwiftUMLStudio#52 fix), routes every alias through `DiagramIdentifiers`. That type claims
identifiers in walk order and suffixes later collisions with `_2`, `_3`.
- **Counterexample (from the hand-check, read off `DiagramIdentifiers`):** components `a b` then `a_b`. HEAD emits `as a_b_2`, while the template
  evaluates `safeAlias("a_b")` to `a_b`.

**The point is general.** A presence law that restates an encoder is only as good as the encoder staying pure. The
`DiagramIdentifiers` shape (a `var` whose method mutates it, called in the loop) has to be read as a cut, which is
what §2.4's rule for vars assigned in the loop already intends. The `component.name` part of the line (`["…"]`)
still holds at HEAD.

## Predictions, scored

| prediction (§6) | outcome |
|---|---|
| kill arm, template presence 6/6 element, 0/3 frame | **held** |
| kill arm, bare presence misses L48 and L80 | **missed**: it missed L55 and L87 instead |
| kill arm, naïve generator kills no more than disciplined | held (equal) |
| admitted about 40–70 | held (41) |
| emittable candidates about 25–40 | just under (24) |
| E about 6–12 | **missed** (14) |
| this repository holds more than half of E | **held** (9 of 14) |
| precision ≥ 70% | held (75.6%) |
| DECLINE on concentration | **held** |

## Recorded after the first report

**1. The tail rule (§2.5) was implemented only at the top level.**
- **Found by:** the adversarial pass. The harness's tail check looked only at top-level statements after the last
  qualifying loop, so it missed non-literal appends nested in a later `if`, `for` or `switch`.
- **Sensitivity run:** `EMITTER_STRICT_TAIL=1`, `census-strict-tail-2026-11-12.json`, refuses 6 more rows. All six
  had been hand-checked law-true and read-true:
  - GRDB's 2;
  - `InteractionBridgeWriter.emit`;
  - SwiftLintRuleStudio `changeSections`;
  - SwiftPropertyLaws `summaryLines`;
  - SwiftUMLBridge `DepsScript.buildPlantUMLText`.

  Only `emit` was in E.

| reading | precision | E | this repository's share | decision |
|---|---|---|---|---|
| frozen run (the decision of record) | 31/41 = 75.6% | 14 | 9 | DECLINE (concentration) |
| strict tail, the 6 rows not admitted | 25/35 = 71.4% | 13 | 8 | DECLINE (concentration) |
| strict tail, the 6 rows counted as defects | 25/41 = 61.0% | 13 | 8 | DECLINE (concentration and precision) |

**The rule itself is over-strict.** An append after the loop cannot remove a line the loop wrote. A shipped reader
would refuse only removing or rewriting statements.

**2. A top-level `if let` wrapping a loop was not marked call-guarded.** That broke `ViewModelVerifyInteractionSurvey`.
It is already among the 10 defects.

**3. The decision is close on one rule, §2.8's executable-target exclusion.**
- SwiftPM lets a test target `@testable import` an executable target, and SwiftPropertyLaws has
  `PropertyLawDiscoveryToolTests`.
- If its 4 candidates counted and all derived, this repository would hold 9 of 18. That is exactly half, which
  clears the rule.
- It is not clear that all four derive:
  - `emit` takes a `ConformanceMap.Entry` whose `DerivationStrategy` payload is unchecked;
  - `summaryLines` is refused under the strict tail.

  On the frozen rule the decision is DECLINE, and it is recorded as close.

## What this does not answer

- **The dispatch-arm lift.** SwiftUMLBridge's 11 private builders would need it. It contests
  `docs/measurements/lift-caller-reach.md` and needs its own measurement.
- **The count form, and `map { … }.joined()` emitters.** Both are outside the reader.
- **`+=` renderers' mutants.** swift-mutation-testing generates none.
- **Encoder collisions.** That is #674. The `DiagramIdentifiers` finding above shows the fix moved the collision
  out of the emitted text, and moved a presence law's restated encoder out of reach with it.

## Reproduce

```bash
python3 scripts/emitter_presence_kill_arm.py fixtures/emitter-presence/kill-arm-2026-11-11.json
python3 scripts/emitter_presence_census.py controls fixtures/emitter-presence/subjects-2026-11-12.json
cd fixtures/emitter-presence/census-run && swift run -c release EmitterCensus run ../subjects-2026-11-12.json ../census-2026-11-12.json
python3 scripts/emitter_presence_census.py report fixtures/emitter-presence/census-2026-11-12.json fixtures/emitter-presence/handcheck-2026-11-12.json
```
