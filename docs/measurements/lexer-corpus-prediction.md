# Prediction — does a corpus of REAL lexers reopen the tokenizer laws?

> **Status:** `superseded` · **As of:** 2026-10-22
>
> **SCORED AND DECLINED — see `docs/measurements/lexer-corpus-census.md`.** 4 of 5 predictions
> held. Kept unedited below this header: it was committed at `0a70441d`, before the census, and
> editing it would destroy the evidence that the census was not tuned to the answer.

**Committed BEFORE any of the ten corpora below was read or scanned**, so "not tuned to the
answer" is checkable in `git log` — the practice `whole-to-parts-partition-prediction.md` and
`same-name-differential-pairing.md` established. The repositories were cloned, and their SHAs
recorded, before this file was written; nothing in them has been opened.

## Why this exists

Issue #645 asks for two laws on a `String -> [T]` tokenizer whose element carries a `String`
field:

1. **Conservation**: `f(s).map(\.text).joined() == s`.
2. **Single-lexeme round trip**: text that is one token of class K tokenizes to exactly that
   token, scaffolded as one `@Test` per case of the element's `Kind` enum, with the generator
   left to the author.

Both were measured against the home corpora twice and declined both times:
`whole-to-parts-partition-declined.md` (1 emittable declaration in 1 corpus, ~4% precision) and
the issue's own census comment (23 shape matches over 47 repositories; the law holds on one).
The issue was left open on one condition: *a corpus with real lexers (a code-highlighting or
markup package) might change the population.* None of the 47 was one. This measures that
condition.

## The corpus

Ten public packages whose job is lexing, highlighting, templating or markup, cloned
`--depth 1` into `~/GitHub_projects/lexer-corpus/` on 2026-10-22:

| package | SHA | why it is here |
|---|---|---|
| nicklockwood/SwiftFormat | `f09e539` | a Swift formatter built on its own lexer |
| JohnSundell/Splash | `2e3f17c` | a Swift syntax highlighter |
| twostraws/Sourceful | `1ec0ed9` | a code-editor highlighter with a lexer |
| JohnSundell/Ink | `bcc9f21` | a Markdown parser |
| SimonFairbairn/SwiftyMarkdown | `dde451a` | a Markdown tokeniser |
| scinfu/SwiftSoup | `e7f85f4` | an HTML tokeniser (a jsoup port) |
| stencilproject/Stencil | `17af3ba` | a template language with a lexer |
| vapor/leaf-kit | `64cc0a5` | a template language with a lexer |
| hummingbird-project/swift-mustache | `50f8f69` | a template language |
| nicklockwood/Expression | `e9a9623` | an expression evaluator |

## The bar, frozen now (inherited, not invented)

The reopen criterion `whole-to-parts-partition-declined.md` §6 froze on 2026-08-13: **≥ 5
whole-to-parts decompositions across ≥ 2 repositories, with element types whose text
projection is expressible.** Counted over these ten plus the earlier witness. "Decomposition"
means hand-checked: concatenating the returned elements' text reproduces the argument for
correct code. "Expressible" means `map(\.member)` type-checks against a `String`-typed member,
stored or computed — an enum with a `var string: String` counts; an enum whose cases carry
counts, or a token holding only a range, does not.

The single-lexeme scaffold needs the same population plus a `Kind`-like enum on the element,
so it **cannot** reopen if conservation does not.

## Instrument

Two probes, both written after this file:

- **Shape probe** — `scripts/whole_to_parts_census.py` unchanged: `func f(…: String|Substring)
  -> [T]` in non-test sources. This is what a signature-keyed template could reach.
- **Role probe** — new: every type whose name ends `Lexer`, `Tokenizer`, `Tokeniser` or
  `Scanner`, and every method on it returning `[T]` or a `Sequence`/`IteratorProtocol` of
  tokens, whatever its parameters. This is where the lexers are if the shape probe misses them.

## Predictions

**P1 — the reopen criterion is NOT met.** 1–3 new hand-checked decompositions in total, in at
most two packages (SwiftFormat most likely). With the earlier witness, under 5.

**P2 — the shape probe misses most real lexers.** The dominant lexer shape in these packages is
an **object holding its input**, with a parameterless `tokenize()` / `lex()` / `next()`, or a
`Sequence` — not a free `(String) -> [T]`. Predicted: the role probe finds at least twice as
many lexers as the shape probe admits.

**P3 — the text projection is not expressible on most real lexers' tokens.** They are enums
with payloads, or ranges into the source. Predicted: under half of the lexers the role probe
finds have an element with a `String`-typed member that spans the whole lexeme.

**P4 — templating lexers are lossy by design.** Stencil, leaf-kit and swift-mustache strip
their delimiters (`{{ }}`, `#(…)`) from token contents, so conservation is **false for correct
code** there — the issue's "false law about correct code" failure, not a population gain.

**P5 — the single-lexeme scaffold's population is at most 1 outside SwiftFormatRuleStudio.**
It needs `text` and a kind enum on one struct; the element types predicted in P3 are mostly the
kind *as* the enum, with the text inside a payload.

## What would make me build it

P1 failing: **≥ 5 decompositions across ≥ 2 repositories** with an expressible projection. Then
the template is conservation over the shape-probe population, gated by the body dataflow test
§6 names (every element built from a slice of the argument) — never by a name list.
