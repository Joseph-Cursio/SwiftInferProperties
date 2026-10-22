# A corpus of real lexers — the tokenizer laws stay declined

> **Status:** `declined` · **As of:** 2026-10-22

The prediction this scores is `docs/measurements/lexer-corpus-prediction.md`, committed at
`0a70441d` **before** any of the ten packages below was opened or scanned, and before
`scripts/lexer_role_census.py` existed. It answers the one condition issue #645 was left open
on: *a corpus with real lexers (a code-highlighting or markup package) might change the
population.*

**Verdict: do not build either law.** The reopen criterion frozen in
`whole-to-parts-partition-declined.md` §6 (**≥ 5 whole-to-parts decompositions across ≥ 2
repositories, with an expressible text projection**) now reads **2 across 2**. The second
witness is the one lexer in ten whose author already wrote the law down, as a function and
as 331 hand-written examples. **4 of 5 predictions held**, and the one that missed missed by
being too generous.

---

## 1. The corpus

Ten public packages whose job is lexing, highlighting, templating or Markdown, cloned
`--depth 1` into `~/GitHub_projects/lexer-corpus/` on 2026-10-22. Only their sources were
read; nothing was built or run.

| package | SHA | kind |
|---|---|---|
| nicklockwood/SwiftFormat | `f09e539` | formatter on its own lexer |
| JohnSundell/Splash | `2e3f17c` | Swift highlighter |
| twostraws/Sourceful | `1ec0ed9` | code-editor highlighter |
| JohnSundell/Ink | `bcc9f21` | Markdown parser |
| SimonFairbairn/SwiftyMarkdown | `dde451a` | Markdown tokeniser |
| scinfu/SwiftSoup | `e7f85f4` | HTML tokeniser (jsoup port) |
| stencilproject/Stencil | `17af3ba` | template language |
| vapor/leaf-kit | `64cc0a5` | template language |
| hummingbird-project/swift-mustache | `50f8f69` | template language |
| nicklockwood/Expression | `e9a9623` | expression evaluator |

## 2. The two probes

**Shape probe**: `scripts/whole_to_parts_census.py`, unchanged since 2026-08-13. **62**
`(String|Substring) -> [T]` declarations, of which the element-type gate admits **48**: 24
SwiftFormat, 12 SwiftyMarkdown, 10 Sourceful, 2 SwiftSoup. As on the home corpora, they are
mostly not lexers. They are globs and path lists (`parsePaths`, `expandGlobs`), search results
(`indicesOf(_ keyword:)`, `ranges(of:)`), and Sourceful's per-language `generators(source:)`.
**3 of the 48 are lexer entry points.**

**Role probe**: `scripts/lexer_role_census.py`, new. It looks for every type named `…Lexer`,
`…Tokenizer`, `…Tokeniser` or `…Scanner`, and the token-returning methods beside it. **14
lexer types in 6 packages, 38 methods.** It misses SwiftFormat's free `tokenize(_:)`, which
sits beside no lexer-named type. Ink, swift-mustache and Expression have no token stream at
all: each parses straight to a tree or template.

## 3. Every lexer, hand-classified

Seven packages have a lexer entry point. A row is a **decomposition** if the returned elements'
text reproduces the argument for correct code. It is **expressible** if `map(\.member)`
type-checks against one `String` member that spans the whole lexeme.

| lexer | shape | shape probe? | decomposition? | expressible? |
|---|---|---|---|---|
| SwiftFormat `tokenize(_ source: String) -> [Token]` | free function | ✅ | ✅ **yes** | ✅ `\.string` (enum, computed) |
| Sourceful `getSavannaTokens(input:) -> [Token]` | protocol method | ✅ | ❌ sparse, overlapping highlight ranges | ❌ `range` only |
| SwiftyMarkdown `SwiftyTokeniser.process(_:) -> [Token]` | method | ✅ | ❌ drops markers and escapes | `inputString`, but stripped |
| Splash `segmentsByTokenizing(_:using:) -> AnySequence<Segment>` | internal, sequence | ❌ | in principle; `prefix` is cumulative | ❌ no single member |
| Stencil `Lexer(templateString:).tokenize() -> [Token]` | input held | ❌ | ❌ strips `{{ }}`, collapses whitespace | `contents`, but stripped |
| leaf-kit `LeafLexer.lex() -> [LeafToken]` | input held | ❌ | ❌ | ❌ payload-free cases, `.whitespace(length: Int)` |
| SwiftSoup `Tokeniser.read() -> Token` | one at a time | ❌ | ❌ decodes entities | ❌ |

**One decomposition in ten packages**, SwiftFormat's. With the 2026-08-13 witness
(SwiftFormatRuleStudio `tokens(inLine:)`) that makes **2 across 2 repositories**, against a
bar of 5. The vendored sample lexer under SwiftFormat's `Snapshots/Parsing/` (test input for
the formatter, not SwiftFormat's code) skips whitespace and parses numbers to `Double`. It is
not a decomposition either way.

## 4. The predictions scored: 4 of 5

**P1 — reopen criterion not met; 1–3 new decompositions in at most two packages. HELD.**
One new decomposition, in SwiftFormat, where the prediction expected it.

**P2 — the shape probe misses most real lexers; the role probe finds at least twice as many.
HELD, at the boundary.** The role probe finds 6 lexer entry points; the shape probe admits 3 of
the 7 that exist. Four of the seven hold their input or yield one token at a time: the
object-with-`tokenize()` shape, plus a sequence and an iterator. **A signature-keyed template
reaches under half the lexers there are**, before precision is asked.

**P3 — under half the lexers have an expressible whole-lexeme text member. HELD.** 3 of 7
have any `String` member (SwiftFormat, SwiftyMarkdown, Stencil), and only SwiftFormat's spans
the lexeme as written. The rest are ranges (Sourceful), counts (leaf-kit), or no member at all
(Splash, SwiftSoup). This is `RawTriviaPiece`'s `.spaces(Int)` problem again, now in a
templating engine.

**P4 — the templating lexers are lossy by design, so conservation is false for correct code.
HELD for both that have a token stream.** Stencil and leaf-kit strip delimiters. swift-mustache
has no token array, so it does not score.

**P5 — the single-lexeme scaffold's population is at most 1 outside SwiftFormatRuleStudio.
MISSED, and in the safe direction.** SwiftFormat's enum `Token` admits the law case by case
(`tokenize("foo") == [.identifier("foo")]`), so the population is exactly 1. But the
prediction's shape argument failed. **The issue's `Token { text, kind }` struct occurs here
once, as Stencil's `Token { contents, kind }`, and on that one the law is false for correct
code**: `{{ x }}` tokenizes to `contents == "x"`, not `"{{ x }}"`. The scaffold's own key shape
matches a lossy lexer, which is §4 of the earlier decline (*the law is not in the signature*)
reached from the other law.

## 5. The second witness already owns its law

SwiftFormat is the one true positive, and it needs nothing from this tool.

- **It ships the inverse.** `public func sourceCode(for tokens: [Token]?) -> String` is
  `(tokens ?? []).map(\.string).joined()`, so conservation there is the round trip
  `sourceCode(for: tokenize(s)) == s`, a pair the catalogue already has a template for.
  **`discover --include-possible` does not propose that pair** (run at `33c35d37` over
  `Sources/`, 2026-10-22). The visible difference is the inverse's `[Token]?` parameter
  against `tokenize`'s `[Token]` return, but this run did not establish that as the cause. Of
  the 25 `round-trip` lines it does print, eight pair `wordsToIdentifier(upperCamelCase:)
  (Bool) -> String` with a `String -> Bool` predicate such as `isMacro()`. That is the
  type-symmetry pairing `round-trip-pairing-evidence.md` already measured, not new.
- **It already tests the single-lexeme law by hand**: 331 `XCTAssertEqual(tokenize(input),
  output)` examples in `Tests/`, one per token shape. An author with a lossless lexer had
  already written both laws down.

So the population that would gain a test is **SwiftFormatRuleStudio's `tokens(inLine:)`,
alone**, which is where #645 started.

### 5.1 Found in passing: a trap in the body withdraws `input-totality`

`tokenize(_ source: String) -> [Token]` passes `input-totality`'s gate: it leads with the
interpretation verb `tokenize`, and `source` is a content label. **It still draws no
`input-totality` row.** Bisected with five one-line bodies under the same signature: `return
[]` alone draws the row. The same body after any one of `assert(true)`,
`precondition(!source.isEmpty)`, `fatalError()`, `source.first!` or `Int(source)!` draws
nothing. SwiftFormat's real body holds six `assert`/`assertionFailure` calls.

The path: SEI's `TotalityChecker` counts `assert` and the other trap functions as partiality.
A non-throwing function cannot be `.pureButPartial`, so it is `.refuted` with a witness, and
`TemplateRegistry.applyImpureSubjectVeto` withdraws every law on a witness-refuted subject. Confirmed by the control: the same
`assert(true)` body declared `throws` is `.pureButPartial`, escapes the veto's
`!summary.isThrows` clause, and draws the row again. For
most templates that is the intended veto. **For `input-totality` it inverts the evidence**: a
visible trap is the strongest static sign that the totality law can fail. The law is withdrawn
on exactly the subjects it is most likely to refute, and silently, because a vetoed row is not
printed. `purity-veto-precision.md` priced `input-totality` removals together with every other
template's, without separating trap witnesses from side-effect witnesses. Not fixed here; the
fix needs its own A/B over the manifest corpora.

## 6. What would reopen it

Unchanged, and now tested against the corpus the issue named: **≥ 5 whole-to-parts
decompositions across ≥ 2 repositories, with an expressible text projection**, found by
someone *not* looking for this law. A twentieth highlighter will not supply them. What these
ten packages show is that a real lexer either keeps its input (and its author writes the
inverse), or drops it by design. The other route to reopening is the body-dataflow gate §6 of
the earlier decline named (every element built from a slice of the argument), which would
also find the decompositions this signature probe cannot reach. That is a gate with no
population to justify building it.

## 7. Method notes

**The issue's own law-killing evidence still stands.** This census does not touch what the
mutation run found: conservation is necessary and not sufficient, and the single-lexeme law
killed all three survivors. It only measures how many functions could be offered that law, and
the answer is the one function the law was written for.

**The hang caveat shipped separately** (`0a0e811f`, `InputTotalityTemplate`): non-termination
is a totality violation, reported as a timeout. That was the part of #645 with a population,
since it applies to every parser `input-totality` proposes.
