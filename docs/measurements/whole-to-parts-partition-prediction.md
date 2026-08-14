# Prediction — a whole-to-parts partition form

> **Status:** `superseded` · **As of:** 2026-08-13
>
> **SCORED AND DECLINED — see `docs/measurements/whole-to-parts-partition-declined.md`.**
> 1 of 5 predictions held, and the one that did is moot. Kept unedited: its value now is that
> it was wrong in a checkable way, and editing it would destroy the only evidence that the
> census was not tuned to the answer.

**Committed BEFORE the census script exists**, so "not tuned to the answer" is checkable in
`git log` rather than asserted — the practice `same-name-differential-pairing.md` established.

## The candidate

`PartitionTemplate` states *the parts must reconstitute the whole* and fires **zero times** on
every measured corpus. Its gate wants an **index-based** tiler:

```swift
func byteRange(ofChunk index: Int) -> Range<Int>   // .range
func chunk(of data: Data, at index: Int) -> Data   // .slice
```

`SwiftCodeTokenizer.tokens(inLine: String) -> [Token]` is neither: it is **whole → all parts at
once, no index**. Proposed third form:

```swift
func tokens(inLine line: String) -> [Token]        // .wholeToParts
```

with the law `f(x).map(\.<textMember>).joined() == x`.

**The template has made this mistake once already**, in its own words: *"The template was keyed
on the signature the reference implementation happened to use, and the reference is the
outlier."* This would be the second reference to key on, so the prediction below is about
whether a THIRD form is genuinely general or is the tokenizer's own shape wearing a template.

## Predictions

**P1 — dominant false positive: the lossy splitter.** `split(separator:)`,
`components(separatedBy:)`, `lines(of:)` all have shape `(String) -> [T]` and **legitimately
fail** the law, because the separator is discarded. A gate that admits on shape alone proposes
a false law for every one of them. This is the failure mode to design against, not a tuning
detail.

**P2 — the separating signal is the ELEMENT TYPE, not the name.** A lossless tokenizer returns
`[T]` where `T` is a user struct carrying a text member *plus a classification* (`Token { text,
kind }`); a lossy splitter returns `[String]` / `[Substring]` directly. So: require the element
to be a user-defined type with exactly one `String`-typed stored member. Predicted to be the
whole gate.

**P3 — population.** `(String|Substring) -> [UserType]` across the eight reachable corpora:
**15–40** declarations.

**P4 — precision of the P2 gate on that population: 50–70%.**

**P5 — the emitted law needs the element's text member by name**, so a type with two `String`
members is ambiguous and must decline rather than guess.

## The bar, frozen now

Ship only if the P2 gate scores **≥ 70% precision** on hand-classified census rows, with a
population of **≥ 5**. Below either, record the decline and do not widen with a name list —
`same-name-differential-pairing.md` §2.2 measured that route and it is structural, not a tuning
gap.

**Rationale for 70% rather than the 50% used for `same-name-differential-pairing`:** that bar
was for a *pairing* rule whose worst case is a redundant test. This law's worst case is a
**false law about correct code** — the tool telling a reader their correct splitter is broken —
which `fixtures/planted-defect-arm` measured as the failure that discredits a refutation.

## What would make me abandon it

If the population is dominated by a single repo, this is the tokenizer's own shape again and
should be declined on the same ground the index forms were nearly declined on. **Population
concentrated in one corpus is a decline, whatever the precision.**
