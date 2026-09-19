# Should a law draw its domain from a CORPUS instead of a generator?

> **Status:** `measured` · **As of:** 2026-09-19

Prompted by how swift-syntax tests: `Parser.parse(source:).syntaxTextBytes == fileContents`,
asserted over **real files**, 3,422 `assertParse` call sites, and only 8 test files mentioning
randomness at all — the one that generates edits disabled by default.

> **Answer: DECLINED on this corpus, and the decline is CONDITIONAL — the reason is what the
> manifest contains, not what the idea is worth.** Both routes were measured. Parsing real source
> for syntax nodes is **94% one repository**. Mining values from tests is **already built, can be
> enabled, and yields ZERO** across four repositories.

## Route 1 — parse real source, the swift-syntax shape

332 emitted stubs are blocked on a SwiftSyntax type, and **316 of them are `predicate`** — a
totality law over a visitor, which is precisely the shape swift-syntax itself tests by running
over a corpus.

| repository | stubs |
|---|---:|
| SwiftProjectLint | **315** |
| SwiftEffectInference | 14 |
| SwiftCloneDetector | 3 |

**94% is one subject's carrier vocabulary.** This is the third time this concentration has priced
a lever on the same population: #492's dependency-scanning wiring measured **3 rows across two
subjects** against 159 projected, and `generator-blocker-reasons.md` declined widening the scan
for the same reason.

## Route 2 — mine values the tests already construct

**The mechanism exists.** `MockGeneratorSynthesizer.synthesize(typeName:record:)` builds a
generator from a `ConstructionRecord` gathered by `SetupRegionConstructionScanner` over test
setup regions, and `LiftedSuggestionPipeline.applyMockInferredFallback` applies it to any
suggestion still at `.notYetComputed`.

⚠ **It fired 0 times across the whole 19-repository census — and the first explanation was
wrong.** The census never passes `--test-dir`, and that pipeline is the lifted path, which
early-returns without test artifacts. That looked like a wiring gap of the kind this repository
has now fixed twice.

**Measured with `--test-dir` supplied, same binary, four repositories:**

| repository | stubs w/o → w/ | `.todo` w/o → w/ | mined generators |
|---|---|---|---:|
| SwiftCloneDetector | 13 → 13 | 8 → 8 | **0** |
| SwiftMarkdownWiki | 45 → 45 | 13 → 13 | **0** |
| MacCloud_server | 13 → 13 | 6 → 6 | **0** |
| SwiftEffectInference | 33 → 33 | 21 → 21 | **0** |

The flag **does** activate the path — 33 lifted/mined mentions in the output against 0 without —
and then synthesis returns `nil` for every blocked type. **Not a wiring gap: the types that need a
corpus are not the types tests construct in a capturable setup region.** `URLRequest`,
`UserDefaults` and the SwiftSyntax nodes are obtained from a framework or a parse, not assembled
in a `let` a scanner can read.

## ⚠ Why the decline is conditional

Both routes fail on **corpus composition**, not on the mechanism. The manifest is Apple-adjacent
libraries plus one linter, and **the archetype for this idea — a parser whose real domain is a
body of existing inputs — is not in it.** swift-syntax is that archetype and is scanned as a
carrier corpus, never as a subject of this question.

This repository has paid for that distinction five times, most explicitly in
`throwing-codec-census.md`: *"the manifest is Apple-adjacent library code; every exhibit came from
schema and API-client code"*, and its recommendation was to run the census over the exhibit
subjects rather than to widen the manifest.

**The same recommendation applies here.** Adding two or three parser-shaped or
serialiser-shaped subjects and re-asking would price the idea; measuring it against this corpus
prices the manifest.

## What is NOT in doubt

The **strategy gap is real**, and it is recorded in `exhaustible-domain-census.md` from the other
end. Apple's two repositories answer the same question two ways and neither reaches for a random
generator:

| repository | method | uses | when it applies |
|---|---|---:|---|
| swift-collections | `withEvery…` exhaustive enumeration | 1,055 | small, structured domain |
| swift-syntax | `assertParse` over real source | 3,422 | huge, structurally constrained domain |

This catalogue has only the middle strategy — sample a generated domain — and the two ends are
where types like `FunctionCallExprSyntax` and `URLRequest` actually live.

## What would reverse this

A corpus containing parser-, serialiser- or format-handler-shaped subjects, where the population
is not one repository's AST vocabulary. Concretely: re-run route 1's count over such subjects and
show a non-concentrated population, or show a `ConstructionRecord` that captures the blocked types
on any subject at all.

Re-run: route 1 — count stubs whose marker reads *is not among the scanned types* for a `*Syntax`
name, grouped by repository. Route 2 — `discover --sources … --test-dir …` and count stubs whose
generator is mock-inferred.
