# Do #668's XML emitter laws have a population, and do they catch what a suite misses? — Two declines, each resting on what the instrument cannot see: Law 1's population clears and it catches nothing the suite misses; Law 2 has one decision subject, and three in all (#668)

> **Status:** `measured` · **As of:** 2026-10-30
>
> **Decision: both laws DECLINE** under `docs/plans/xml-emitter-census-scope.md` §8, and each decline crosses a
> sensitivity line, as §8 requires this paragraph to say.
>
> - **Law 1: DECLINE (kills).** Its population clears, N1 = 8 over 3 repositories (SwiftUMLStudio, SwiftLint,
>   swift-foundation), and #668's gate is right on 7 of the 7 rows it admits. But on the witness the law catches no
>   generated mutant the suite misses without the tests written from the law's own findings: a decisive count of 0.
>   **That rests on the generated operators' blindness to literal text**: with the six hand mutants counted, the
>   count is 2, #56's and #80's own defects, which clears the kills bar.
> - **Law 2: DECLINE (population: a single subject).** All 4 owing groups in the decision universe are
>   SwiftUMLStudio's, though the law catches the one mutant both suites miss (F5's `arrowMarkerDefs`; decisive 1).
>   **That rests on the universe's boundary**: the graph-layout corpus holds 4 more owing SVG emitters, in
>   beautiful-mermaid-swift and Graffle, so the population over every group is 8 over 3 repositories, which clears.
>
> Under §8, #668 was closed as not planned on 2026-10-30, with the user's approval, carrying the two reopen conditions it froze. **Separately,
> 14 of the 18 owing groups in every group break Law 1** (all but SwiftUMLStudio's four, already fixed), each
> witness run. Six repositories hold a reachable defect, each filed upstream on 2026-10-30 with the user's
> approval and tracked in #700.

#668 asked for two laws the catalogue does not have, gated separately, for a function that builds an XML document
as text:

- **Law 1: the document parses.** Apart from a sentinel a guard returns, the result is a well-formed XML document:
  `XMLParser(data: Data(result.utf8)).parse()` returns true.
- **Law 2 (SVG only): every same-document reference resolves.** Each `url(#X)`, `href="#X"` and `xlink:href="#X"`
  in the result names an `id="X"` in the result.

Its witness is SwiftUMLStudio's `SwiftUMLBridge`. Two of its defects are already fixed: SVGRenderer wrote a node's
label into an XML comment, so `Old--Code` broke the document (SwiftUMLStudio#56, PR #79), and `xmlEscaped` let the
characters XML forbids through (#80, PR #86). What remained was #668's step 0: a census of each law's population,
with the two laws gated separately; a GitHub code-search estimate for Law 1; and a single-subject decline for Law 2
unless a second emitter of same-document references turned up.

This doc reports the census, a kill arm on the witness, and a hand-check of every row the census flagged.
Everything it rests on was committed in this order, on branch `xml-emitter-census`:

| step | commit | what |
|---|---|---|
| freeze | `7300102e` | `docs/plans/xml-emitter-census-scope.md` (the cues, the gates, the universe, 318 controls, the hand-check, the kill arm, 11 predictions and the decision rule), with the census pass, the kill arm, the laws, the judging brief, the calibration and the judge workflow, after three review rounds; frozen before the census read any subject or either law ran |
| results | `4bc2a629` | the census, the R5 search, the judges' records and joined verdicts, the hand-check of the flagged rows, the kill arm's report and the survivors' reading, in `fixtures/xml-emitter-law/` |

## The census

`scripts/xml_emitter_census.py run` read the frozen universe on 2026-10-30, after its 318 controls passed: 37
decision subjects (the manifest and funnel groups of #666's universe, SwiftLint at `ec4691d9e` and SwiftUMLStudio
at `9ad7631`), 13 unmet, #667's 18-package graph-layout corpus and 67 wide directories. That is 28,844 Swift files
in 2 min 23 s, with no file dropped as unparsable.

A unit (a `func` with a body, or a computed property) is a **candidate** when one of its body's literals holds one
of #668's grep markers (`<?xml`, `xmlns`, `<svg`, `</svg>`, `<plist`, `</plist>`), or when its opening literal is
one hop away and its body writes an end tag. The census found **33 candidates**, none of them copies of another:

| group | candidates | subjects | GATED | GATED2 |
|---|---:|---:|---:|---:|
| decision | 16 | 5 | 7 | 4 |
| unmet | 0 | 0 | 0 | 0 |
| layout | 11 | 4 | 2 | 0 |
| wide | 6 | 4 | 0 | 0 |

**GATED** is #668's signal applied mechanically: the result is a `String`, the unit neither throws, awaits nor
mutates, its body holds no impurity token, an opening literal (`<?xml`, or a first start tag carrying `xmlns`)
flows into the result from the body or one hop away, a body literal writes that root's end tag, and nothing writes
`<html` or `<!doctype html`. **GATED2** adds an `svg` root and an `id="…"` attribute in the unit's own literals
or one hop away.

Every candidate was judged, blind, by two judges, with a third on any split (§4 of the scope). Both judges passed
the ten-row calibration on the first run. They split on 2 of the 33 rows, both on whether the unit can be reached
by a test (EXPRESSIBLE), and judge C settled both. No judge needed the workflow's retry.

### The decision group

| subject | unit | GATED | verdict | EXPRESSIBLE | law2 | flags |
|---|---|---|---|---|---|---|
| SwiftUMLStudio | `ComponentSVGRenderer.renderSVG` | GATED2 | DOCUMENT | yes | OWES | |
| SwiftUMLStudio | `SVGRenderer.render` | GATED2 | DOCUMENT | yes | OWES | |
| SwiftUMLStudio | `ActivitySVGRenderer.renderFromLayout` | GATED2 | DOCUMENT | yes | OWES | |
| SwiftUMLStudio | `SequenceSVGRenderer.renderFromLayout` | GATED2 | DOCUMENT | yes | OWES | |
| SwiftUMLStudio | `ComponentSVGRenderer.svgHeader` | | FRAGMENT | | | |
| SwiftLint | `CheckstyleReporter.generateReport` | GATED | DOCUMENT | yes | NOT-SVG | body disagrees |
| SwiftLint | `JUnitReporter.generateReport` | GATED | DOCUMENT | yes | NOT-SVG | body disagrees |
| SwiftLint | `GitLabJUnitReporter.generateReport` | GATED | DOCUMENT | yes | NOT-SVG | body disagrees, ambient |
| swift-foundation | `Writer.serializePlist` (XML plists) | | DOCUMENT | yes | NOT-SVG | body disagrees |
| swift-foundation | `PropertyListDecoder.findXMLTagOpening`, `XMLPlistScannerEventSource.dispatchOpenTag` | | NOT-EMITTER (a sniffer, a parser) | | | |
| swift-package-manager | `XUnitGenerator.generate`, `generateResourceInfoPlist` | | NOT-EMITTER (written to disk) | | | |
| swiftlang-swift | `SchemeGenerator.writeScheme`, `disableAutoCreationIfNeeded`, `WorkspaceGenerator.write` | | NOT-EMITTER (written to disk) | | | |

So **N1 = 8 over 3 repositories**: SwiftUMLStudio's four renderers, SwiftLint's three reporters and swift-foundation's
XML property-list writer, each a group of its own. **N2 = 4 over 1**, all SwiftUMLStudio's.

### The outer groups

- **Layout (11 candidates over 4 repositories).** Eight are DOCUMENT and EXPRESSIBLE. Four of them owe Law 2:
  beautiful-mermaid-swift's class, flowchart and sequence renderers, and Graffle's SVG export (`Writer.document`),
  which writes `url(#gradN)` and `url(#shadowN)` for the gradients and shadows it defines. MermaidKit's and
  swift-mermaid's SVG renderers are GATED; neither writes a reference. beautiful-mermaid-swift's renderers miss the
  gate because their opening tag is built by a top-level function in another file (`svgOpenTag`, judged FRAGMENT),
  and §1.2 follows a top-level unit's hops only within its own file (C26); Graffle's because `Writer` is a struct
  whose `document` is `mutating`. Graffle's other two candidates are a self-test harness and its steps (NOT-EMITTER).
- **Wide (6 over 4).** Two are DOCUMENT and EXPRESSIBLE: XcodeProj's `AEXMLDocument.xmlXcodeFormat` and soto-core's
  `Document.xmlString`. soto-core's `Node.xmlString` and swift-testing's `JUnitXMLRecorder._record` (one piece of a
  streamed report per call) are FRAGMENT; soto-core's S3 middleware and a sourcekit-lsp test helper are NOT-EMITTER.
- **Unmet: none.**

## The gate #668 names

**Law 1's gate is right on all 7 decision rows it admits** (7/7: SwiftLint's three reporters and SwiftUMLStudio's
four renderers), and so is Law 2's (4/4). Without PURE, the same 7 and 4. It misses one owing decision group,
swift-foundation's `serializePlist`, which returns bytes, throws and mutates its writer (R2: it misses STRING,
NOTHROW, NONMUTATING, OPEN and CLOSE).

The judges flagged one GATED decision row **ambient**: `GitLabJUnitReporter` reads the working directory through
`relativeDisplayPath`, #668's own example of what a text purity check cannot see. Without it, N_gated is 6 over 2,
which still clears.

## Rows that break the law, hand-checked and run

Scope §8 requires every row flagged *body disagrees* or *refs dangle* to be hand-checked and run before it is
listed. The judges flagged 15: 14 *body disagrees* in 8 repositories, and one *refs dangle*.
`fixtures/xml-emitter-law/handcheck-workflow.js` gave each repository to one agent, which ran each witness at the
census revision (a built package, a verbatim extraction, or, for swift-foundation, the shipping macOS
`PropertyListEncoder`, which is the same code), judged the output with `XMLParser`, and read the default branch
upstream. **Every witness held, and every one was run.**

| repository | unit | what breaks the document | reachable | upstream default branch |
|---|---|---|---|---|
| SwiftLint | `CheckstyleReporter`, `JUnitReporter`, `GitLabJUnitReporter` | `escapedForXML` passes C0 controls through (`XMLParser` code 9); `GitLabJUnitReporter` also writes the rule identifier unescaped | **yes**: the shipping 0.65.1, with only the default rules, on a file that compiles with an escape character in a `TODO` comment; a custom rule's key or message | same (HEAD is the census revision) |
| swift-foundation | `Writer.serializePlist` | `appendEscaped` escapes `<`, `>`, `&` and rejects only NUL, so 30 forbidden code points (U+0001–U+0008, U+000B, U+000C, U+000E–U+001F, U+FFFE, U+FFFF) go into `<string>` and `<key>` raw | **yes**: any `Codable` string, through `PropertyListEncoder` with `.xml` | same |
| 2389-research/MermaidKit | `SVGRenderer.svg` | C0 controls and noncharacters pass through; a `<` or `&` followed by a combining mark is another `Character`, so it passes unescaped | **yes**: from plain Mermaid source | same |
| Australware/swift-mermaid | `MermaidScene.svgString` | `escapeText` escapes only `&`, `<`, `>`, so C0 controls pass through | **yes**: user-typed diagram labels, through `Mermaid.render` | same |
| yahirvitelugardo/Graffle | `SVGExport` `Writer.document` | `SVGExport.escape` escapes only `&`, `<`, `>`, `"`, so a control character in a layer name, shape text or label reaches an attribute or a `<tspan>` | **yes**: user-typed names | same |
| tuist/XcodeProj | `AEXMLDocument.xmlXcodeFormat` | control characters through AEXML's `xmlEscaped` into attribute values; element names and attribute keys unescaped | **yes**: an environment variable value, a script's text or a path in a scheme | same |
| lukilabs/beautiful-mermaid-swift | five renderers | `buildStyleBlock` writes the font name raw into `<style>`, and colours go raw into the root's `style` attribute; some `data-*` attributes skip escaping | no caller sets them: **latent** | same |
| soto-core | `Document.xmlString` | attribute values, version, encoding and comments unescaped | **no**: what SotoXML serialises comes from its own encoder | same |

The one *refs dangle* row, beautiful-mermaid-swift's flowchart renderer, holds as stated: a node whose
`inlineStyle` sets `fill: url(#missing)` is copied through. But that is the diagram author's own CSS, not a
reference the unit made; every reference it generates resolves. The hand-check recommends against filing it, and
it shows Law 2's limit: a pass-through style is outside what the unit owes.

**Six of the eight repositories hold a reachable defect worth an upstream issue** (SwiftLint, one issue for all
three reporters; swift-foundation; MermaidKit; swift-mermaid; Graffle; XcodeProj). Scope §8 offered them for filing,
and each was filed on 2026-10-30 with the user's approval, after being reproduced at upstream `main` as a test that
fails there and passes with a proposed patch (`fixtures/xml-emitter-law/upstream-repro/`): realm/SwiftLint#6965,
swiftlang/swift-foundation#2393, 2389-research/MermaidKit#119, Australware/swift-mermaid#2,
yahirvitelugardo/Graffle#1 and tuist/XcodeProj#1198, tracked in #700. The common cause is one #80 already fixed in
SwiftUMLStudio: escaping the five predefined entities is not enough, because XML 1.0 forbids most C0 controls
outright, even as a character reference. Preparing the filings found a second cause in four of the six (SwiftLint,
MermaidKit, swift-mermaid, Graffle), which the hand-check did not record: escaping by `Character` misses a `<`, `&` or
`"` followed by a combining mark, because the two scalars form one `Character`.

## The kill arm

The laws were written by hand as `fixtures/xml-emitter-law/XMLEmitterLawTests.swift`, for SwiftUMLStudio's four
renderers: **P-C, P-S, P-A, P-Q** (Law 1) and **R-C, R-S, R-A, R-Q** (Law 2), 1,000 SplitMix64 draws each from a
narrow pool of names and a text alphabet that holds `<`, `>`, `&`, `"`, `'`, `-`, `]`, U+0001 and U+FFFE. Only
`renderSVG` has a guard, and its `""` for a layout with no components is the one sentinel, decided from the input.

`scripts/xml_emitter_kill_arm.py` ran every mutant of the laws' call trees in a fresh `git archive 9ad7631`, under
Xcode's Swift 6.4.2 (`swiftlang-6.4.2.1.9`), four ways (scope §5.4): under Law 1, under Law 2, under the full
suite less the laws (1,839 tests), and under the **reduced** suite, which also drops the 23 tests PR #79 and PR #86
added for #56 and #80 (1,816 tests). **Every runner control held**, so both kill counts are measured:

| control | what it checks | result |
|---|---|---|
| RC1 | the unmutated export | all eight properties pass; reach R-C 282, R-S 605, R-A 359, R-Q 707 of 1,000; P-C's sentinel 215; the full suite passes 1,839 tests and the reduced suite 1,816 |
| RC2 | `lines.append(arrowMarkerDefs)` removed (F5's site) | Law 2 fails R-C by assertion; Law 1 and both suites pass |
| RC3 | `svg += "\n</svg>"` removed from `SVGRenderer.render` | Law 1 fails P-S by assertion |
| RC4 | a statement that does not compile | UNVIABLE |
| RC5 | the export's tree after the run | hashes as before |
| RC6 | both laws twice | the same eight lines |
| RC7 | #56's `<!-- label -->` given back to `renderNode` | Law 1 fails P-S by assertion; **the reduced suite passes** |
| RC8 | a loop that never ends in `renderSVG` | Law 1 TIMEOUT at 120.5 s, and nothing naming the export left running |

**125 mutants on the laws' call trees; 114 viable** (11 arithmetic mutants, in `svgHeader`, `edgeSVGLine`,
`boxRect` and `renderNode`, do not compile). The Activity and Sequence files' layout code holds 69 more, counted
and not run (scope §5.3).

| | viable | Law 1 | Law 2 | full suite | reduced suite |
|---|---:|---:|---:|---:|---:|
| detected | 114 | 6 | 5 | 42 | 40 |
| by assertion | | 3 | 2 | 41 | 39 |
| by crash | | 3 | 3 | 1 | 1 |

- **Law 1 detects 6 mutants, and the suite detects all 6**: `renderSVG`'s inverted guard (M001), its root start
  tag removed (M002) and its `"</svg>"` removed (M006), each by assertion on P-C; and three in `SVGRenderer.renderEdge`
  (M065, M066, M073) that crash the law's draws and that the suite catches by assertion. **The decisive count is 0,
  and so is the law-only count against the full suite.** The three by assertion are the three generated mutants
  scope §5.3 said could make the output malformed.
- **Law 2 detects 5, and one of them alone: M003, `lines.append(arrowMarkerDefs)` removed from `renderSVG`**, F5's
  survivor and #668's motivating case. No test in either suite notices that every edge's `url(#arrow)` dangles.
  **The decisive count is 1**, and the law-only count against the full suite is 1 too. The other four are suite
  kills as well: M068 negates `!markerId.isEmpty`, so an association writes `url(#)` and every other edge loses its
  arrow; M065, M066 and M073 crash the draws.
- **The suite detects 36 mutants Law 1 misses** (38 for Law 2), mostly geometry it pins by value: 14 in
  `ComponentSVGRenderer`'s `edgePoint`, 6 in `SVGRenderer.renderEdge`. Two of its kills are made only by a derived
  test, *a forbidden character in any text slot is replaced, leaving the document well-formed* (M072 and M111, in the
  Activity renderer's edge code), so the reduced suite misses them, and neither law sees them.
- **Flakes.** Six suite assertion detections sat beside a law detection; each was run again under the flake rule
  and repeated, with failures in common. None was disjoint.
- **Single failing tests.** Eleven suite kills were made by one failing test, most by *SVG dimensions include
  margin* (4).
- **71 mutants survived both laws and the full suite.** §5.6 reads them for equivalence
  (`fixtures/xml-emitter-law/equivalence-workflow.js`, six agents reading each in its function). **None is
  equivalent, and neither law could see any of them**: 56 move only numbers (a coordinate, a size, a path point), 10
  add, drop or reshape a complete element (a header band, a square-off rect, a message drawn as a self-call loop),
  and 5 change only a colour, a dash pattern or which of two defined arrowheads an edge names. Each leaves a
  well-formed document whose references all resolve. That is what the two laws are blind to by design, and what
  the suite pins only where a test asserts a value.

**The hand mutants**, which scope §5.3 put outside the decisive count because the generator never mutates literal
text or the computed property `xmlEscaped`:

| | change | Law 1 | Law 2 | reduced suite | full suite |
|---|---|---|---|---|---|
| H1 | `xmlEscaped`'s `case "&"` removed | assertion | survived | assertion | assertion |
| H2 | `case "<"` removed | assertion | survived | assertion | assertion |
| H3 | `case ">"` removed | assertion | survived | assertion | assertion |
| H4 | `case "\""` removed (a raw `"` in text is legal) | survived | survived | survived | assertion |
| H5 | the C0 range removed, #80's defect | assertion | survived | **survived** | assertion |
| H6 | `renderNode`'s `<!-- label -->` restored, #56's defect | assertion | survived | **survived** | assertion |

**With H1–H6 counted, Law 1's decisive count is 2: H5 and H6, the two defects the law was written from.** The
reduced suite misses both because the only tests that catch them are the ones PR #79 and PR #86 added after the
defects were found. Against the full suite, Law 1 adds nothing, here or among the generated mutants.

## The decision

`xml_emitter_census.py decide` over the census, the joined judgements and the kill arm's report:

```
LAW 1 DECISION: DECLINE (kills)  N1 = 8 over 3 local repositories (bar: ≥ 5 across ≥ 2)  N_gated = 7  GATED precision 7/7 (100%)
law 1-only (reduced suite): 0 by assertion, 0 by crash/timeout/memory   law-only (full suite): 0   law 6, suite 42, reduced 40, viable 114
law 1 beside: unmerged 8  N_unmet 0  N_layout 8  N_wide 2 (6 of 6 judged, estimate 2.0)  N_undetermined 0  GATED precision without PURE 7/7
law 1 without EXPRESSIBLE: N 8  N_unmet 0  N_layout 8  N_wide 2 (estimate 2.0)
law 1 GATED not owing: none
law 1 R2 (owing, no GATED member): swift-foundation:Sources/FoundationEssentials/PropertyList/XMLPlistEncodingFormat.swift:732 (EXPRESSIBLE True, missed CLOSE, NONMUTATING, NOTHROW, OPEN, STRING)
SENSITIVITY law 1 N + N_unmet + N_layout + N_wide: 18 over 9 repositories — clears the population bar
SENSITIVITY law 1 N + N_undetermined: 8 over 3 repositories — clears the population bar
SENSITIVITY law 1 N without EXPRESSIBLE: 8 over 3 repositories — clears the population bar
SENSITIVITY law 1 N without SwiftLint: 5 over 2 repositories — clears the population bar
SENSITIVITY law 1 N_gated without rows judged ambient: 6 over 2 repositories — clears the signal bar
SENSITIVITY law 1 decisive count with H1–H6 counted: 2 — clears the kills bar (more than 0)
law 1 hand mutants: H1 law ASSERTION, reduced ASSERTION, full ASSERTION; H2 law ASSERTION, reduced ASSERTION, full ASSERTION; H3 law ASSERTION, reduced ASSERTION, full ASSERTION; H4 law SURVIVED, reduced SURVIVED, full ASSERTION; H5 law ASSERTION, reduced SURVIVED, full ASSERTION; H6 law ASSERTION, reduced SURVIVED, full ASSERTION
LAW 2 DECISION: DECLINE (population: a single subject)  N2 = 4 over 1 local repositories (bar: ≥ 5 across ≥ 2)  N_gated = 4  GATED2 precision 4/4 (100%)
law 2-only (reduced suite): 1 by assertion, 0 by crash/timeout/memory   law-only (full suite): 1   law 5, suite 42, reduced 40, viable 114
law 2 beside: unmerged 4  N_unmet 0  N_layout 4  N_wide 0 (6 of 6 judged, estimate 0.0)  N_undetermined 0  GATED2 precision without PURE 4/4
law 2 without EXPRESSIBLE: N 4  N_unmet 0  N_layout 4  N_wide 0 (estimate 0.0)
law 2 GATED2 not owing: none
law 2 R2 (owing, no GATED2 member): none
law 2 repositories with an owing SVG emitter in any group: SwiftUMLStudio, lukilabs__beautiful-mermaid-swift, yahirvitelugardo__Graffle
SENSITIVITY law 2 N + N_unmet + N_layout + N_wide: 8 over 3 repositories — clears the population bar
SENSITIVITY law 2 N + N_undetermined: 4 over 1 repositories — does not clear the population bar
SENSITIVITY law 2 N without EXPRESSIBLE: 4 over 1 repositories — does not clear the population bar
SENSITIVITY law 2 N without SwiftLint: 4 over 1 repositories — does not clear the population bar
SENSITIVITY law 2 N_gated without rows judged ambient: 4 over 1 repositories — does not clear the signal bar
SENSITIVITY law 2 decisive count with H1–H6 counted: 1 — clears the kills bar (more than 0)
law 2 hand mutants: H1 law SURVIVED, reduced ASSERTION, full ASSERTION; H2 law SURVIVED, reduced ASSERTION, full ASSERTION; H3 law SURVIVED, reduced ASSERTION, full ASSERTION; H4 law SURVIVED, reduced SURVIVED, full ASSERTION; H5 law SURVIVED, reduced SURVIVED, full ASSERTION; H6 law SURVIVED, reduced SURVIVED, full ASSERTION
body disagrees: (the 14 rows above)   refs dangle: (the 1 row above)   unparsable files dropped 0
```

**Law 1 is DECLINE (kills)**: the first three steps clear (8 groups over 3 repositories; 7 gated groups over 2;
precision 7/7), and its decisive count is 0. **Law 2 is DECLINE (population: a single subject)**: its 4 groups are
all SwiftUMLStudio's. Six sensitivity lines are printed for each law. Two cross the bar the decision turned on, and
the first paragraph says so: Law 1's decisive count with H1–H6 counted (2), and Law 2's N with the outer groups
(8 over 3). The others hold the decision where it is. For Law 1 every population line clears, the one without
SwiftLint included (5 over 2), and N_gated without the ambient `GitLabJUnitReporter` is 6 over 2. For Law 2 every
line but the outer groups' stays at 4 over 1.

Under §8's disposition, both laws declining, **#668 was closed as not planned on 2026-10-30**, with the user's
approval, a result comment and the two reopen conditions frozen before the run:

- **Law 2**, #668's own: a repository not among those this census reports, with an owing SVG emitter; or a later
  census with at least 5 owing groups over at least 2 repositories. This census reports SwiftUMLStudio,
  beautiful-mermaid-swift and Graffle.
- **Law 1**, since its decline is on kills: a kill arm whose operators mutate literal text or computed properties,
  or a second subject's kill arm.

## What else the census saw

- **R1, the outer groups**, are above: Law 2 has four owing groups in the layout corpus, over two repositories,
  and none in the wide group.
- **R2.** Law 1's only owing decision group with no GATED member is swift-foundation's `serializePlist` (above).
  Law 2 has none.
- **R3, #668's named sites.** All four SwiftUMLStudio renderers and SwiftLint's `CheckstyleReporter`,
  `JUnitReporter` and `GitLabJUnitReporter` are GATED candidates; `render(graph:)` and
  `render(traversedEdges:entryType:entryMethod:)` hold no literal and are read, not candidates, as predicted.
  SwiftLint's twelve other reporters were read and are not candidates. swift-package-manager's `XUnitGenerator.generate`
  and `generateResourceInfoPlist` are candidates, judged NOT-EMITTER: both write their document to disk and
  return nothing. SwiftFormat's `XMLReporter.write`, #668's near miss, is outside the universe (§2) and was not
  read.
- **R4, #668's grep re-taken:** 50 non-test files in 18 subjects hold `<?xml`, `<svg`, `</svg>`, `<plist` or
  `</plist>` in a literal. They include every file #668 lists as a `String`-returning emitter (SwiftUMLStudio's four
  renderer files and SwiftLint's three reporters). The rest are muter's HTML report resources (three clones),
  swift-docc's static HTML resources, a Mermaid web view, and the plist, scheme and xUnit writers above.
- **R5, GitHub code search** (2026-10-30T17:56Z, files, test files included):

  | query | files | top repositories by matching files, first 100 results |
  |---|---:|---|
  | `"<?xml version" language:Swift` | 9,920 | pointfreeco/pointfreeco, tgu/RosSwift, whyisjake/today |
  | `"xmlns=" "</svg>" language:Swift` | 2,724 | avatune/avatune, pointfreeco/pointfreeco, Shpigford/clearly |
  | `"url(#" language:Swift` | 1,160 | EFPrefix/EFQRCode, dagronf/QRCode, miataru/miataru-ios-client |
  | `"<!DOCTYPE html" language:Swift` | 12,688 | velox-apps/velox, Shpigford/clearly, lukakerr/Pine |
  | `"</checkstyle>" language:Swift` | 16 | ictechgy/cartograph, Lore-Hex/QuillCode, realm/SwiftLint |
  | `"</testsuites>" language:Swift` | 90 | juntaki/mutantkit, arconsis/derived-data-tool, terminaloutcomes/bleat |

  These are files that hold the text, not functions that owe a law. HTML outnumbers standalone SVG about 4.7 to 1.
  Two QR-code generators lead `url(#`: candidates for Law 2 outside this universe, unread, which R5 cannot count
  toward N2 (§8).
- **Dirty checkouts.** SwiftUMLStudio and SwiftLint were asserted clean at their revisions, and every layout clone
  at its own. Six other subjects had local changes and were read as they were; none holds a candidate.

## The predictions, scored

| # | prediction (scope §7) | result | blind? |
|---|---|---|---|
| 1 | Law 1's population clears and rests on SwiftLint: N1 5–8 over 2, and N without SwiftLint does not clear | **half**: N1 = 8, but over 3 repositories, and without SwiftLint it is 5 over 2, which clears. swift-foundation's XML plist writer is the group no one named | partly |
| 2 | Law 1's gate precision ≥ 70% | **held**: 7/7 | partly |
| 3 | Law 1's decisive count is 0, so DECLINE (kills) | **held**: the law's 6 detections are all suite detections | no |
| 4 | Law 2 is DECLINE (population: a single subject), N2 = 4 over 1 | **held** | partly |
| 5 | Law 2's decisive count is 1 or 2: `lines.append(arrowMarkerDefs)` removed, and perhaps `!markerId.isEmpty` negated | **held**: 1, M003; the negation (M068) is a suite kill too | no |
| 6 | RC1 holds; each reach within 100 of the model (R-C ≈ 300, R-S 600, R-A 350, R-Q 730); P-C's sentinel ≈ 200 | **held**: 282, 605, 359 and 707; 215 | no |
| 7 | RC7 holds: the law finds #56's defect put back | **held**, by assertion on P-S; the reduced suite misses it | no |
| 8 | no decision row is flagged *body disagrees* or *refs dangle* | **missed**: four decision rows, SwiftLint's three reporters and swift-foundation's plist writer, all confirmed and reachable | partly |
| 9 | Law 1 detects H1, H2, H3, H5 and H6, and H4 survives both laws; the reduced suite detects H1–H3 but not H5 or H6; the decisive count with H1–H6 counted is 2 | **held**, to every cell; the full suite catches H4 | no / partly |
| 10 | R4 finds every file #668 lists as a `String`-returning emitter | **held** | partly |
| 11 | Q4 (HTML) counts more files than Q2 (standalone SVG) | **held**: 12,688 against 2,724 | blind |

## Disclosures and instrument limits

- **Three review rounds before the freeze** (scope §10), run as workflows with a skeptic on every blocking finding:
  ten findings were confirmed blocking (six, three and one), and each was fixed before any subject was read,
  among them a copy key blind to literals, a judge workflow that collapsed repeated labels before `join` could
  refuse them, and a ROOT that read past an interpolated hop.
- **The hand-check and the kill arm shared the machine.** The hand-check's agents built packages and ran scratch
  harnesses with `-j 4`. Each mutant's runs took about 30 s against limits of 120 s and 300 s, and the six suite
  detections the flake rule re-ran all repeated.
- **One subject for the kill arm.** Its counts are SwiftUMLStudio's, against a suite that already holds Law 1's
  examples. They are not a rate.
- **The generated operators cannot reach most of Law 1's defects** (scope §5.3): they never mutate literal text,
  and the defects the census found are all in what a literal or an escape writes.
- **Hand-written generators.** The laws' draws are written by hand, with a narrow alphabet that includes the
  characters XML forbids. A template would need the kit to draw such text for a struct's member (#668's item 4).
- **The census finds only what its cues reach** (scope §9). It missed beautiful-mermaid-swift's renderers, whose
  opener is a top-level function in another file, and Graffle's mutating `Writer.document`; both owe the laws and
  were judged because they are candidates.
- **The universe was restored, not kept**: the wide and corpus clones were re-made on 2026-10-30 (scope §2).

## So what

- **Both laws decline under the frozen rule, and #668 is closed as not planned.** Neither
  decline is a finding that the law is wrong or that its population is empty. Each rests on a boundary the scope
  drew before the run, and each boundary is printed above.
- **Law 1 is right, about real code, at a high rate.** Across every group, 18 groups owe it, and 14 of them break
  it. The 4 that hold are SwiftUMLStudio's renderers, fixed after #56 and #80. Most of the other 14 share #80's
  defect, escaping the five predefined entities without removing the characters XML 1.0 forbids; the rest leave a
  field unescaped. Every witness was run. Six repositories hold a reachable case, among them SwiftLint's three
  reporters with the shipping 0.65.1 and default rules, and the shipping macOS `PropertyListEncoder`. A kill arm on
  one subject cannot see this: the witness's suite already holds the law's examples, and the generated operators
  never touch the literal text and escapes where these defects live. The two hand mutants that are #56 and #80
  themselves are exactly what the law catches and the suite, without its post-hoc tests, misses.
- **The frozen reopen condition for Law 1 points at the next step: a second subject's kill arm.** SwiftLint's
  reporters are the natural one: they are GATED, their `escapedForXML` is the defect, and their tests pin canned
  golden files (#668).
- **Law 2 catches the one mutant both suites miss** (F5's `arrowMarkerDefs`, #668's motivating case), but its
  population in the decision universe is SwiftUMLStudio alone. Two more repositories with owing SVG emitters sit in
  the layout corpus, beautiful-mermaid-swift (three renderers) and Graffle, and every reference either generates
  resolves. Its one *refs dangle* row was
  pass-through author CSS, outside what a unit owes. R5's `url(#` leaders, two QR-code generators, are unread.
- **What a build would have to get right, as measured here:**
  - **Forbidden characters in the generator.** Most defects found are reached only by a draw holding a C0 control
    or a noncharacter, and the rest by a `<`, `&` or `"` in a field the emitter does not escape. #668's item 4 (the
    kit drawing escaped text for a struct's member) is the prerequisite.
  - **Openers the cues miss.** beautiful-mermaid-swift builds its opening tag in a top-level function in another
    file, Graffle's writer is `mutating`, and swift-foundation's writer returns bytes and throws. Each owes Law 1,
    each was judged only because it is a candidate, and none is GATED.
  - **HTML.** HTML outnumbers standalone SVG about 4.7 to 1 on GitHub (R5), and the brief reads an HTML-vocabulary
    card as HTML. Law 1 states nothing about it.
- **Upstream.** The six reachable defects were filed on 2026-10-30 (SwiftLint, one issue for its three reporters;
  swift-foundation; MermaidKit; swift-mermaid; Graffle; XcodeProj), tracked in #700.

## Reproducing

```bash
python3 scripts/xml_emitter_census.py run census.json
python3 scripts/xml_emitter_census.py search search.json
python3 scripts/xml_emitter_census.py packets census.json judging/packets/   # writes judging/index.json and sizes.json
# copy fixtures/xml-emitter-law/judge-brief.md and calibration.md into judging/brief/, then run
# fixtures/xml-emitter-law/judge-workflow.js with args {judging: "judging/", sizes: <sizes.json>}, and save its
# result as judging/workflow-output.json
python3 scripts/xml_emitter_census.py verdicts judging/workflow-output.json judging/verdicts/
python3 scripts/xml_emitter_census.py join judging/index.json judging/verdicts/ judgements.json
git -C ~/xcode_projects/SwiftUMLStudio archive 9ad7631 | tar -x -C export/
python3 scripts/xml_emitter_kill_arm.py run export/ kill-arm.json
python3 scripts/xml_emitter_census.py decide census.json judgements.json kill-arm.json
# then run fixtures/xml-emitter-law/handcheck-workflow.js over the rows flagged body disagrees or refs dangle
```

The census needs the frozen universe (scope §2) on this machine, and the kill arm needs Xcode's Swift 6.4.2
(`swiftlang-6.4.2.1.9`).
