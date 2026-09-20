# What did generators for the unbuildable buy? The funnel, re-run

> **Status:** `measured` · **As of:** 2026-09-20

**Fourth run of the corpus pipeline walk**, repeating
[2026-09-19](corpus-funnel-census-2026-09-19.md)'s pipeline over the same 19 repositories with
the same harness (`scripts/corpus_funnel.py` + `scripts/corpus_funnel_stage5.py`). Census binary:
SwiftInferProperties `cce43fc5`, **one binary for all 19** — see § *One repository had to be
re-run* for the only departure and why it is not a second arm.

> **Answer: compiles 219 → 553 and passes 150 → 471, on stubs that FELL 924 → 915.** Two
> generators for things nothing could derive — SwiftSyntax nodes and class receivers — plus the
> `private` widenings those generators made worth doing, and six emitter fixes.

## The funnel

| stage | 16 Sep | 19 Sep | **20 Sep** | vs 19 Sep |
|---|---:|---:|---:|---:|
| named seeds | 2,723 | 2,730 | **2,738** | +8 |
| any law proposed | 2,080 | 1,915 | **1,921** | +6 |
| refutable law proposed | 1,019 | 937 | **939** | +2 |
| stub file written | 980 | 924 | **915** | −9 |
| **stub compiles** | 183 | 219 | **553** | **+334** |
| **law passes** | 67 | 150 | **471** | **+321** |

**The three upstream stages move by single digits and that is the instrument check.** They are
the stages this cycle's work should not touch, and they do not: +8, +6, +2 on populations of
thousands. The movement they do show is real rather than noise — 56 `private` helpers became
`internal` across five repositories, and visibility is an input to discovery, so a handful of
rows appear that could not before.

**Stubs fell while compiles more than doubled.** The gates keep withdrawing rows a correct
implementation could not owe (`monotonicity` over an unordered carrier, −9 here), and the stubs
that survive now have generators for the arguments they always needed.

## Where the movement is

| repo | stubs | compiles | passes | 19 Sep (stub/comp/pass) |
|---|---:|---:|---:|---|
| SwiftProjectLint | 434 | **251** | **248** | 434 / 31 / 30 |
| pbt-book | 127 | 104 | 57 | 134 / 74 / 43 |
| SwiftAssist | 76 | 48 | 38 | 77 / 34 / 26 |
| SwiftPropertyLaws | 45 | 38 | 33 | 45 / 22 / 20 |
| SwiftMarkdownWiki | 35 | 28 | 24 | 35 / 11 / 9 |
| SwiftEffectInference | 33 | 26 | 24 | 33 / 5 / 3 |
| SwiftLintRuleStudio | 41 | 19 | 16 | 41 / 15 / 12 |
| SwiftFormatRuleStudio | 19 | 17 | 16 | 19 / 15 / 14 |
| SwiftCloneDetector | 14 | 6 | 6 | 12 / 1 / 1 |
| MacCloud_server | 13 | 8 | 6 | 11 / 3 / 3 |

⚠ **SwiftProjectLint is 45% of the corpus's stubs and nearly half its compiles, and this cycle's
two generators were built for exactly its shape.** A tool that analyses Swift takes SwiftSyntax
nodes and visitor classes; most packages do not. Read 553 as *what the toolchain reaches on this
corpus*, not as a rate — the four repositories outside it that gained anything gained 3 to 21
compiles each.

## What the two generators were

**SwiftSyntax nodes, from the package's own test snippets.** No generator derives a
`FunctionDeclSyntax`, and a random one would not be a meaningful input. A tool that analyses
Swift tests itself by parsing small snippets — SwiftProjectLint's tests call `Parser.parse(source:)`
610 times over ~2,960 multi-line literals — so the corpus is those snippets, harvested when they
carry no interpolation and parse without error.
`docs/measurements/corpus-domain-declined.md` declined the other route at a measured zero: it
mined the VALUES tests construct, and nodes are obtained from a parse, never bound to a
capturable `let`. Harvesting the text the parse consumes is what that decline left open.

**Class receivers, from the constructions the tests already write.** Memberwise derivation is
structs-only by design, and SwiftProjectLint's visitors take a `SyntaxPattern` that holds a
metatype — a member no derivation can synthesise at all. The tests build them anyway
(`LawOfDemeterVisitor(patternCategory: .architecture)`), and that expression is copied when every
name in it resolves in a generated file. `Visitor(pattern: pattern)` is the common shape and is
refused: a test-local has no binding in the stub.

## What is not measured, and why

| repo | stubs | reason |
|---|---:|---|
| SwiftUMLStudio | 43 | kit 2.x vs a library-code pin of swift-property-based 1.x |
| pbt-workbook-corpus | 20 | same |
| pbt-workbook-sampler | 4 | same |
| pbt-workbook | 1 | same |
| MacCloud_client_MacOS | 0 | Xcode project, no SwiftPM manifest |
| SwiftLintRuleStudioTeam | 0 | Tuist, no SwiftPM manifest |

The four dependency conflicts are the limit the 16 September census recorded and deliberately
left standing. **68 stubs are emitted there and compiled nowhere**, exactly as in the two
previous runs, so the comparison is like-for-like.

⚠ **SwiftFormatRuleStudio's hang reproduced, and the harness attributed it unaided.** The
bisection named `SwiftCodeTokenizer_tokens_input_totality` — the same law over the same real
non-termination defect the 19 September census diagnosed — set it aside, and the repository
reports 17 compiles and 16 passes rather than a repo-wide *no verdict*.

### ⚠ One repository had to be re-run, and the cause is worth keeping

SwiftPropertyLaws first reported **75 stubs and a package that did not build**:
`multiple producers … Compiling Swift Module 'SwiftInferCensusTests' (75 sources)`. The accept
path's chosen test target put `Generated/SwiftInfer` inside a directory an existing target
already claims, so SwiftPM saw the same files under two targets. Re-run on a fresh tree with the
**same binary** it reports **45 / 38 / 33**, the stub count every other run of this repository has
produced.

**Which target the accept path ranks first is not stable across runs**, and where it lands decides
whether the census target is legal. That is a product observation, not a harness one, and it is
recorded rather than worked around.

### ⚠ A defect this census found in the census's own subject

42 stubs across five repositories failed with `expected ',' separator` or `unterminated string
literal` — a **syntax** error in code the reader did not write. The constructed receiver's
qualifier is an expression (`File(name: "test", path: "test", userID: UUID())`), and the failure
label is spliced into a string literal, so the quotes closed it early. Fixed before this census
was published (the label is the parsed signature, and every label is escaped), which is why the
fix's own binary is the one all 19 ran on.

✅ **Escaping the label also fixed a LATENT defect a golden test was pinning**:
`invariant-preservation` writes its keypath into the message, and `"\.isValid"` is an invalid
escape sequence in the emitted file. The golden encoded output that could not compile.

## A pass still means what it meant

**No planted violator was run against any passing law**, in this census or its three
predecessors. A pass is *no counterexample in the generated domain*, which CLAUDE.md is explicit
is not *the property holds*. The 471 is a yield figure.

⚠ **And the class of law behind most of the gain is the one that has never refuted anything
here.** The stubs these generators unblocked are overwhelmingly `predicate` and totality over
syntax nodes: `template-refutation-rates.md` measures that arm at **0 refutations of 102**. What
they establish is that the rules do not crash on realistic Swift, which is worth having and is
not bug-finding.

## What is stopping the rest

308 stubs were set aside. Classified from the stub's own header and markers, not from the first
compiler error alone:

| cause | stubs |
|---|---:|
| the subject is `private` or `fileprivate` | 190 |
| no generator for an argument | 91 |
| everything else | 27 |

Of the 91, **48 name a type that is neither a syntax node nor a class** — the long tail
`missing-generator-census.md` measured — **37 are a class the tests never construct usably**, and
**11 are a syntax node absent from the harvested corpus**.

⚠ **The `private` bucket is not one decision.** 56 helpers were widened this cycle *because a
generator existed for their arguments*; the 190 that remain mostly still have no generator, so
widening them would change a subject's code and free nothing. Access and derivation have to fall
in that order.

## Reproducing

```
python3 scripts/corpus_funnel.py <out-dir> <swift-infer> <SwiftProjectLint CLI> <repo>...
```

Resumable: each repository writes `result-<repo>.json` and is skipped when that file exists.
Per-repository toolchain — Xcode's for the SwiftUI-shaped subjects, swift.org's for the rest.
This run: 19 repositories, ~1h20m, one binary.
