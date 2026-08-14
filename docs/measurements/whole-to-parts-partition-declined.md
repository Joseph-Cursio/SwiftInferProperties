# A whole-to-parts partition form — measured NO

> **Status:** `declined` · **As of:** 2026-08-13

The prediction this scores is `docs/measurements/whole-to-parts-partition-prediction.md`,
committed at `ca9c706` **before** `scripts/whole_to_parts_census.py` existed, so "not tuned to
the answer" is checkable in `git log`.

**Verdict: do not build it.** The gate scores **~4%** against a bar frozen at 70%, the true
positives are **1 emittable declaration in 1 corpus** against a clause that says population
concentrated in one corpus is a decline whatever the precision, and the reason is structural
rather than a tuning gap.

---

## 1. What was proposed

`PartitionTemplate` states *the parts must reconstitute the whole* and fires **zero times** on
every measured corpus. Its gate wants an index-based tiler — `(Int) -> Range<Int>` or
`(C, Int) -> C`. `SwiftCodeTokenizer.tokens(inLine: String) -> [Token]` is neither: whole → all
parts at once, no index. The proposal was a third form, `.wholeToParts`, emitting

```swift
f(x).map(\.<textMember>).joined() == x
```

## 2. The census

`scripts/whole_to_parts_census.py` over ten corpora: **208** declarations shaped
`(String|Substring|SyntaxText) -> [T]`. The P2 gate — *the element type is not itself a text
type* — admits **137**.

| corpus | admitted |
|---|---:|
| SwiftInferProperties | 56 |
| Harmonize | 38 |
| SwiftProjectLint | 14 |
| swift-syntax | 9 |
| SwiftLint | 8 |
| SwiftFormatRuleStudio | 8 |
| swift-argument-parser | 2 |
| swift-format · swift-nio | 1 each |

Hand-classified against *does `map(\.text).joined() == x` actually hold*, the true positives
are: `tokens(inLine:)` (the witness), `parseTrivia(_:position:)` ×3 overloads and
`parseIndentationTrivia(text:)` in swift-syntax. **Precision ≈ 5/137 = 4%.**

## 3. The predictions scored: 1 of 5, and the one that held is moot

**P1 — dominant false positive is the lossy splitter. WRONG.** It is the **filter**:
`withName(_ name: String) -> [Element]`, `withPrefix(_:)`, `conforming(to:)`,
`violatingRanges(for pattern:)`, `match(pattern:)`. These take a `String` as a **search term**
and return matching elements from *some other* collection — the argument is a query, not
content, and the law is not merely false for them, it is **meaningless**. Harmonize alone
contributes 38, almost entirely this shape.

**P2 — the element type separates tokenizer from splitter. WRONG, and wrong because P1 was.**
The gate was designed against lossy splitters, which do return `[String]`. Filters return
user-defined types exactly like tokenizers do, so the element-type test is blind to the class
that actually dominates. Same failure as `same-name-differential-pairing.md` §2.2: *the
exclusion was designed against the wrong class*, and the precision prediction fails as a
consequence rather than independently.

**P3 — population 15–40. WRONG (137).** The number is larger and *worth less*: it counts
filters.

**P4 — precision 50–70%. WRONG (~4%).**

**P5 — the emitted law needs the element's text member by name.** Held, and is moot.

## 4. The finding that outlives the decline: the law is not in the signature

These two are the **same shape**, and one tiles while the other does not:

```swift
func tokens(inLine line: String) -> [Token]           // parts tile the line
func parse(_ output: String) -> [ParsedRuleEntry]     // entries SUMMARISE the output
```

Both take a content-labelled text parameter, both return an array of a user struct carrying
`String` members. Nothing at the signature level distinguishes *the parts are a partition of
the input* from *the parts are a selection or summary of it*. Tightening the gate to
`HostileInputEntryPoints`' content-label machinery does not rescue it — that admits
`parse(fileContent:) -> [SuppressionDirective]` and `findMarkedRanges(in text:) -> [Marker]`,
both of which return a **sparse** subset, so the tight gate is still under 50%.

That makes this a **statability gap** in the glossary's sense — real law, real population,
cannot be written down generically from shape — and not a catalog or reach gap. It is the same
verdict `TriviaInsensitivityExperimentTests` reached for the metamorphic family, arrived at
independently.

## 5. The second witness cannot express the law anyway

`parseTrivia` is a genuine lossless decomposition and looked like the corpus-independence this
needed. It is not usable: `RawTriviaPiece` is an **enum with associated values**, several of
them counts rather than text (`.spaces(Int)`), so `map(\.text)` does not typecheck against it
at all. Reconstructing the source from a trivia piece needs a length-aware projection the
template cannot synthesise.

So the emittable true-positive population is **1 declaration, in 1 corpus** — which trips the
prediction's own abandon clause before precision is even reached.

## 6. What would reopen it

**Not a smarter gate.** The separating signal is **dataflow**, not shape: a true decomposition
constructs every returned element from a *slice of its own argument*, and a filter or summary
does not. That is a body analysis, and the same conclusion `fixtures/domain-transfer-signal`
reached — *"the signal is dataflow, not shape"* — for a different template.

Deferred on a **witness**, not a symbol, since no name settles whether the population exists
(the falsifier-naming rule for exactly this case): reopen when a corpus shows **≥ 5
whole-to-parts decompositions across ≥ 2 repositories**, with element types whose text
projection is expressible. Today it is 1 across 1.

## 7. Method notes

**The prediction was committed first and it mattered.** Scoring 1 of 5 is only meaningful
because the predictions could not be edited after the census; the temptation to retrofit P1 to
"filters" once the output was on screen was real.

**A census that counts the wrong population reads as success.** 137 admitted rows looks like
ample justification to build. It is 137 reasons not to.
