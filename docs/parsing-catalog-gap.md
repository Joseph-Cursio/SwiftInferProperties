# The parsing gap — a survey of the catalog against two parser subjects

**Date:** 2026-07-28 · **Tool:** `swift-infer discover` @ v1.146.0 (`aa79370`)
**Subjects:** `swiftlang/swift-syntax` @ `9d6e738` (11 modules, ~176k lines) and
`SwiftProjectLint` @ `6c88715` (7 packages, ~36k lines of first-party source).

Not a scored road test — there is no frozen answer key. This is a **catalog
survey**: point the finished tool at code whose domain the catalog was never
built for, read what comes back, and name what is structurally out of reach
versus what is a fixable defect.

The headline is not that the tool is quiet on parsers. It is that on the one
module where it is *loud* — 98 default-tier suggestions on `SwiftParser` — the
loudest family is **systematically false**, and none of the four laws a parser
actually owes are proposed at any tier.

---

## 1. What came back

`discover --sources <module>` per module. "Default" is a plain run; "possible"
adds `--include-possible`.

| Module | lines | default | +possible | notes |
|---|---:|---:|---:|---|
| SwiftSyntax | 120,308 | **474** | 801 | 268 idempotence, 471 predicate |
| SwiftParser | 28,026 | **98** | 164 | 53 idempotence *Likely* — see §2 |
| SwiftParserDiagnostics | 5,812 | 5 | 82 | 77 idempotence Possible |
| SwiftSyntaxBuilder | 5,939 | **0** | 23 | result-builder clique — see §7 |
| SwiftRefactor | 4,265 | 1 | 8 | |
| SwiftIfConfig | 3,352 | 10 | 14 | |
| SwiftLexicalLookup | 2,484 | 4 | 4 | |
| SwiftOperators | 2,001 | 1 | 3 | `flipped()` involution — a real hit |
| SwiftDiagnostics | 1,643 | **0** | 2 | |
| SwiftIDEUtils | 1,433 | **0** | 7 | |
| SwiftBasicFormat | 1,116 | 5 | 12 | see §4 |

| SwiftProjectLint package | lines | default | +possible |
|---|---:|---:|---:|
| Rules | 26,801 | 23 | 25 |
| Visitors | 4,762 | 16 | 18 |
| **Config** (3 hand-rolled parsers + 1 writer) | 1,365 | **2** | 6 |
| Engine | 1,031 | 1 | 1 |
| Models | 825 | 2 | 3 |
| Registry | 689 | **0** | 0 |

Read past the counts. On `SwiftParser` the 98 decompose as **53 idempotence
(Likely) + 44 predicate-totality (Possible) + 1 comparator**. The 44 totality
claims are real but say nothing about parsing — they are the same claim the tool
makes about any `-> Bool`. The 53 are false. Net parsing-specific true laws
proposed on Apple's Swift parser: **zero**.

---

## 2. Finding 1 — the loud family is wrong: cursor consumption read as idempotence

All 53 `Likely` idempotence suggestions on `SwiftParser` are `mutating` methods
lifted to `(Carrier) -> Carrier`, and every one of them **consumes input**:

```
Lexer.Cursor.advance()                       lifted to (Lexer.Cursor) -> Lexer.Cursor
Lexer.Cursor.advanceToEndOfLine()
Lexer.Cursor.lexNumber() / lexHexNumber() / lexIdentifier() / lexUnknown() …
Parser.Lookahead.consumeAnyToken()
Parser.Lookahead.consumeAttributeList()
Parser.Lookahead.skipSingle() / skipUntilEndOfLine()
Parser.Lookahead.canParseType() / canParsePattern() / canParseClosureSignature() …
TokenConsumer.consumeModuleSelectorTokensIfPresent()
```

`advance()` twice is not `advance()` once. That is the *definition* of a cursor.
The claim is false for all 53, it lands **above the default cut**, and it is the
first thing a reader of a parser codebase sees.

**Why the existing veto misses.** `IdempotenceTemplate+IteratorVeto` already
curates exactly the right verbs — `next`, `advance`, `step`, `findNext` — but
gates them on the *carrier* conforming to `IteratorProtocol` or being named
`Iterator` / `*.Iterator`. `Lexer.Cursor`, `Parser.Lookahead` and `TokenConsumer`
are none of those. The veto's fallback path requires **both** conditions, so the
whole family walks through.

`MutatorBlockedFromIdempotence` (the ungated list) covers `reverse`,
`removeFirst`, `pop`, `dropFirst`, involutions — the *collection* consumers. It
has no entry for the *stream* consumers.

**The internal contradiction worth noting.** `CompositionTemplate` already
curates `advance` and `step` as **additive** verbs — `op(by: a); op(by: b)` ==
`op(by: a+b)`. Additive is the precise opposite of idempotent. One template in
the catalog knows `advance` accumulates; another proposes it is a fixed point.

**The shape the veto is reaching for** is not `IteratorProtocol`; it is *a
position in a stream*. Two independent signals, either sufficient:

- **Carrier name** ends in / contains `Cursor`, `Lookahead`, `Scanner`, `Reader`,
  `Stream`, `Lexer`, `Tokenizer`, `Consumer`, `Parser`.
- **Method verb** in `{advance, skip, lex, eat, munch}` on any carrier — the same
  posture `MutatorBlockedFromIdempotence` already takes for `pop`/`removeFirst`.
  (`consume` was in this list until measurement removed it; see below.)

### Fixed — `StreamConsumption` + `streamConsumptionVeto`

Shipped as `Sources/SwiftInferCore/StreamConsumption.swift` and
`Sources/SwiftInferTemplates/IdempotenceTemplate+StreamConsumptionVeto.swift`,
chained (`else if`) with the V1.21.A iterator veto in `liftedCarrierVetoes` so a
carrier satisfying both renders one bullet.

**Measured, `discover --sources Sources/SwiftParser`:**

| | before | after |
|---|---:|---:|
| default-tier suggestions | 98 | **46** |
| idempotence at Likely | **53** | **1** |
| `--include-possible` idempotence | 111 | 59 |

The one survivor is the recorded residue: `RegexLiteralLexemes.Builder.
recordOpenSlash()`. It is non-idempotent because it *appends* — the accumulator
family — and claiming it under a veto whose stated rationale is stream
consumption would make that rationale false about one of its own firings. It is
pinned by a test so the boundary is visible rather than discovered later.

Three design points worth keeping:

- **Tier 2 has to be the broad one.** 20 of the 53 are query-*shaped* names on
  `mutating` methods (`canParseType()`, `atStartOfSwitchCase()`,
  `isAtModuleSelector()`). No verb list reaches those; only the carrier does. So
  tier 2 vetoes *any* non-restoring `mutating` method on a stream-position
  carrier — the same posture as the iterator veto's primary path, with a
  name-shaped carrier test standing in for the conformance.
- **Matching is camelCase-token-exact, not prefix.**
  `"lexicographicallyPrecedes".hasPrefix("lex")` is `true`, and
  `SwiftLexicalLookup` is a real module in the same corpus. Tokenizing first
  separates `lexNumber` from `lexicalLookup`; a prefix test cannot.
- **`peek`, `take` and `scan` are deliberately excluded from the ungated tier.**
  `peek` is the defining *non*-consuming lookahead. `take` is the `Option::take`
  idiom, which nils the storage and so genuinely *is* idempotent on the second
  call. `scan` reads both ways and is left to the carrier gate to settle.
  `reset`/`rewind`/`restore`/`seek`/`rollback`/`clear` are exempt from tier 2
  entirely — they move a position to a fixed point, so their idempotence holds.

### The over-reach control, and what it cost

The house rule is *verify a suppression by removing it and watching the rule
fire*. Run in the other direction here: the veto was disabled, the reference
corpora were measured with it off, and the two runs diffed — because the failure
mode a veto has is **silent**, and counting SwiftParser's 53 can only ever look
like success.

It found a real defect. `consume` had shipped in the ungated tier, and that cost
**four true laws**:

```swift
// swift-nio, NIOCore/ConvenienceOptionSupport.swift:149
public mutating func consumeAllowLocalEndpointReuse() -> …ConvenienceOptionValue<Void> {
    defer { self.allowLocalEndpointReuse = false }
    return .init(flag: self.allowLocalEndpointReuse)
}
```

"Consume" there means *read the flag and clear it*. The **state** after two
calls is the state after one, so the lifted `(T) -> T` shadow **is** idempotent
— which is the exact argument that had already excluded `take` one row above it.
Two nio siblings and swift-collections' `RangeReplaceableContainer.consumeAll()`
have the same shape.

`consume` was demoted to the carrier-gated tier. Nothing was lost on the
motivating subject: all seven of `SwiftParser`'s `consume*` methods sit on
`Parser.Lookahead` or `TokenConsumer`, so tier 2 still catches every one. The
lesson is the design one — **the verb alone does not decide; the carrier does**
— and the only reason it is in the shipped code rather than in a later bug
report is that the control was run.

**Final ledger, against a veto-off baseline:**

| corpus | baseline | after | delta |
|---|---:|---:|---|
| SwiftParser (default tier) | 98 | **46** | −52, all false `Likely` |
| swift-collections | 750 | 748 | −2, both true positives ¹ |
| swift-nio | 329 | **329** | 0 |
| swift-argument-parser | 60 | 60 | 0 |
| swift-async-algorithms | 10 | 10 | 0 |
| SwiftProjectLint (6 packages) | — | — | 0 |
| the other 10 swift-syntax modules | — | — | 0 |

¹ `BorrowingIteratorProtocol_.next()` and `.nextSpan_()` — genuine iterator
advances the V1.21.A veto missed because `"BorrowingIteratorProtocol_"` does not
`hasSuffix("Iterator")`. The token-based carrier test catches them; a bonus, not
a target.

Full suite green (4,334 fast tests + all 7 subprocess batches, `make test` exit
0), `swiftlint --strict` at zero.

**And these functions are not lawless.** The right law for a cursor is
**monotone progress**, which is refutable and which `SwiftParser` itself already
names in code (`Cursor.hasProgressed(comparedTo:)`, surfaced by the tool as a
bare predicate at Possible):

```
c.advance()  ⟹  c.position > old.position  ∨  c.isAtEnd
```

and for lookahead specifically, the **restoration** law — a `Parser.Lookahead`
must leave the real parser's position untouched. Both are proper templates, and
both are what the 53 slots should have contained.

---

## 3. Finding 2 — parse/print fidelity is Possible-tier at best, unreachable at worst

The flagship law of `swift-syntax` is **absolute fidelity**, asserted in
`Tests/SwiftParserTest/Parser+EntryTests.swift:22`:

```swift
XCTAssertEqual(tree.description, source)     // Parser.parse(source:).description == source
```

It is not proposed at any tier, on any module. Grepping every suggestion across
all 11 modules for a mention of `parse`, `formatted`, `foldAll` or a
parse↔print pairing returns exactly one row — `Trivia.description()`, standing
alone, paired with nothing.

Three separate causes, each independently sufficient:

### 3a. The curated inverse list has one parse-ish entry

`RoundTripTemplate.curatedInversePairs` contains `("parse", "format")` and
nothing else in the neighbourhood. Measured on a synthetic probe with identical
type shapes:

| pair | score | visible by default? |
|---|---:|---|
| `parse` / `format` (same type) | **75 Strong** | yes |
| `parse` / `print` | 35 Possible | **no** |
| `parse` / `render` | 35 Possible | **no** |

`parse`/`print`, `parse`/`unparse`, `parse`/`description`, `parse`/`render`,
`tokenize`/`join`, `lex`/`text`, `read`/`write`, `load`/`save`,
`decode`/`toString` are all the same law wearing a different name, and all sit
below the cut. This is the `intersect`/`intersection` stale-stem failure from
Appendix C, reproduced: the dictionary is missing the word, so the tool never
checks it, and the silence reads as a clean bill of health.

#### Fixed — the text↔structure block

`curatedInversePairs` now carries `parse`/`print`, `parse`/`unparse`,
`parse`/`render`, `parse`/`description`, `tokenize`/`join`, `read`/`write` and
`load`/`save`, grouped by *why* each group is a round trip
(`RoundTripTemplate+InverseNames.swift`; the file was split out when the
addition pushed the template past the 400-line cap). `InversePairTemplate`
reads the same list at its own weight, so the widening lands on both.

`read`/`write` and `load`/`save` are the same shape but their round trip runs
through a **store**, so they carry a caveat saying the law is conditional on
that store and false against a live filesystem for reasons unrelated to the
code under test. Surfacing them without that note would hand a reader a
`Strong` claim that real I/O routinely breaks.

**Measured effect on the corpora: zero, in both directions.** Default-tier
counts are byte-identical before and after on swift-collections, swift-nio,
swift-argument-parser, swift-async-algorithms, all four measured swift-syntax
modules, and all six SwiftProjectLint packages. No over-reach — the generic
verbs `read`/`write`/`join` produced no flood, because the type filter still
gates every pair. And no gain either: the widening adds a name *signal* to
pairs the type filter already produced; it does not create pairs, and none of
these corpora has a same-type parse/print-shaped pair to promote.

So the fix is real but **latent** — verified on synthetic shapes (`parse`/`print`
35 → 70/75, `parse`/`format`'s score), not on a live subject. That is worth
saying plainly rather than letting a green diff imply reach it did not buy.

### 3b. The cross-type penalty kills the pair precisely where parsing puts it

`RoundTripTemplate` applies **−25** for a pair whose halves live in different
containing types ("property cannot type-check across distinct containing
types"). But in real code the parser and the printer are *almost always* split:
`Loader`/`Writer`, `Parser`/`Printer`, `Decoder`/`Encoder`, `Lexer`/`Renderer`.

Measured on a probe with non-curated names (`render` / `load`):

- same type (`Codec.render` + `Codec.load`) → 35, Possible
- **different types (`Writer.render` + `Loader.load`) → suppressed entirely**

This is exactly `SwiftProjectLintConfig`'s shape:
`LintConfigurationWriter.render(_:) -> String` and
`LintConfigurationLoader.load(from:) -> LintConfiguration`. A package built
around a config serializer gets **no round-trip proposal for it at any tier** —
and instead gets a spurious `String -> String` pairing of two unrelated path
helpers (§7).

The −25 is a *code-generation* concern (where does the emitted test live), not a
*truth* concern. It is currently applied as if it were the latter.

> **Partly relieved by the §3a fix, and only for curated names.** With
> `parse`/`print` curated, the cross-type arithmetic becomes 30 + 40 − 25 = 45,
> which clears the cut — so `Reader.parse` × `Printer.print` is now visible
> where it used to be suppressed outright at 5. That is a side effect, not a
> substitute: a cross-type pair whose names are *not* in the list is still
> suppressed. §3b stays open.

### 3c. The print half is declared on a protocol extension

`SourceFileSyntax`'s printer is `var description: String` on an `extension
SyntaxProtocol` — declared once, generically. `FunctionPairing` matches on type
*text*, so the scanner records the domain as `SyntaxProtocol`, and
`SyntaxProtocol -> String` never meets `String -> SourceFileSyntax`.

**Corrected after measurement.** This section first said "the print half is
usually not a function", blaming computed properties. That is wrong, and a
probe falsified it: the scanner *does* surface computed properties, and a
`var description: String` on the **concrete** type pairs fine with `parse` —
50/Likely once the §3a names landed. The blocker is narrower and more specific:
a printer declared on a **protocol extension**, whose domain type-text is the
protocol rather than any conforming type. That is swift-syntax's exact shape,
and it is why the fidelity law is still unreachable there. Pinned by
`ParsePrintInverseNameTests.protocolExtensionPrinterStillCannotPair`.

### 3d. The deeper gap: no notion of *which direction*, and no law for lossy parsers

Even fixed, the catalog would still be modelling this wrong. A parse/print pair
has two round-trips and they are not equally true:

- `parse(print(t)) == t` — the **tree** domain. Holds for essentially every
  parser. Cheap; rarely where bugs are.
- `print(parse(s)) == s` — the **text** domain. Holds *only* for a full-fidelity
  parser and is **false for every lossy one**. This is the interesting,
  refutable direction, and it is a claim about the parser's design.

The template emits one law over the value domain and has no vocabulary for the
distinction. And for the lossy case — the common case — the true law is not
either of these. It is the **retract / normal-form** law:

```
print(parse(print(parse(s)))) == print(parse(s))       i.e.  print ∘ parse is idempotent
```

Every lossy parser owes this and nothing else. **There is no template for it.**
It is arguably the single most-used property in the parsing literature and the
catalog cannot express it, because `idempotence` requires one function of shape
`T -> T` and this is a *composition* of two functions that is `T -> T`.

---

## 4. Finding 3 — formatter idempotence is vetoed by name prefix

`format`/`formatted` is in `IdempotenceTemplate.curatedVerbs` (+40). But
`IdempotenceTemplate+ShapeDisambiguationVeto` pattern 2 vetoes any name with
prefix `format` or `_description`. Measured, on identical `String -> String`
shapes:

| function | result |
|---|---|
| `normalize(_ s: String) -> String` | **75 Strong** |
| `format(_ s: String) -> String` | **suppressed** |
| `formatSource(_ s: String) -> String` | **suppressed** |
| `Doc.formatted() -> Doc` (self-form) | 75 Strong |

The veto's stated rationale is type-based — *"format returns String for
non-String input"* — but the veto is applied on the name prefix alone, so it
also fires on `String -> String`, where the rationale does not hold and where
idempotence is the canonical law a source formatter owes. The fix is to make the
veto do what its own comment says: only fire when the parameter type differs
from the return type.

Independently, `swift-syntax`'s real formatter misses on a **second** count:

```swift
extension SyntaxProtocol {
  public func formatted(using format: BasicFormat = BasicFormat()) -> Syntax
}
```

`Self -> Syntax` is not `T -> T`, so the shape gate rejects it before naming is
consulted. Type-erasing returns (`Syntax`, `AnyView`, `any P`) are a general
blind spot for every `T -> T` template, and AST libraries erase constantly. A
probe confirms: `Doc.formatted() -> Doc` fires Strong, `Doc2.formatted() ->
AnyDoc` fires nothing.

---

## 5. Finding 4 — three of the five interaction families are the right shape and are locked to reducers

This is the largest structural opportunity in the report.

`ConservationInteractionTemplate` emits `state.<aggregate> ==
state.<collection>.count`. `BiconditionalInteractionTemplate` emits
`state.<bool> == (state.<optional> != nil)`. `CardinalityInteractionTemplate`
counts. These are exactly the invariants a syntax tree and a parse *result* owe:

| family, as written for reducers | the same law on a parse tree |
|---|---|
| `state.total == state.items.count` | `node.totalLength == node.children.map(\.totalLength).reduce(0,+)` — the span-tiling law |
| `state.total == state.items.count` | `tree.description.utf8.count == tree.totalByteSize` |
| `state.flag == (state.opt != nil)` | `diagnostics.isEmpty == !tree.hasError` — the diagnostics/tree biconditional |
| referential integrity | every `node.parent`'s children contain `node`; every position lies within its parent's range |

All five families take a `ReducerCandidate`. The *templates* are already
carrier-agnostic — `InteractionTemplateFamily.analyze` only needs a candidate
and a witness. It is the **discoverers** (`ReducerDiscoverer`,
`ViewModelDiscoverer`) that are reducer-shaped. There is no *recursive-tree
carrier* and no *result-record carrier*.

A `TreeCarrierDiscoverer` — a type with a self-referential `[Self]` member, plus
a numeric or optional-and-bool member pair — would let conservation, cardinality
and biconditional fire on ASTs, JSON documents, file hierarchies, layout trees,
and scene graphs. The witness detectors would need a recursion-aware variant;
the scoring, rendering, and verify paths would not change.

---

## 6. Finding 5 — no differential / oracle-equivalence family

`swift-syntax` documents its most valuable property in
`Sources/_SwiftSyntaxTestSupport/IncrementalParseTestUtils.swift:26`:

> verify that incrementally parsing the edited source based on the original
> source produces the same syntax tree as reparsing the post-edit file from
> scratch.

That is **fast path ≡ reference path** — a cheap optimized implementation must
agree with an obviously-correct slow one, for all inputs. The catalog has no
template for it. The nearest thing, `dual-style-consistency`, is gated to
`formX`/`X` / `X`/`Xing` / `X`/`Xed` naming pairs on a single carrier — a Swift
API-convention rule, not the general shape.

This family is far bigger than parsing. Its instances include memoization vs
recompute, an index vs a linear scan, a denormalized cache vs a join, a SIMD
path vs a scalar path, an incremental diff vs a full recompute. The recognizable
signature is a function taking a *previous result* plus a *delta* and returning
the same type as the from-scratch function:

```
fast(previous: R, edit: E) -> R    ∧    slow(input: I) -> R    ⟹   fast(slow(i), e) == slow(apply(e, i))
```

`Parser.parseIncrementally(source:parseTransition:)` next to
`Parser.parse(source:)` is precisely this, in the subject, public, and
un-proposed. Of everything in this document, this is the template I would build
first — it generalizes furthest beyond the domain that surfaced it.

---

## 7. Finding 6 — the generator wall, and why `ProxyConstruction` only solves half of it

`ProxyConstruction` (from the SwiftProjectLint road test) is the right idea and
it solves the **AST-consumer** case: a linter whose kernels take
`FunctionDeclSyntax` gets a recipe that generates source text, parses it, and
walks the tree. Good.

It does not solve the **AST-producer** case, and there are three distinct holes:

**(a) Recursive types dead-end.** Measured:

```swift
indirect enum Expr { case lit(Int), add(Expr, Expr), neg(Expr) }
struct Node { var name: String; var kids: [Node] }
```

`simplify(Expr) -> Expr` → proposed Likely, `Generator: .todo`.
`normalize(Node) -> Node` → proposed **Strong**, `Generator: .todo`.

Every hand-written parser's AST is one of these two shapes, and neither ends in
`Syntax`, so `ProxyConstruction` does not reach them either. The law is proposed
at the highest confidence tier and is unrunnable. Recursive generation with a
size/depth budget (`Gen.recursive`-style, halving the budget at each level) is a
standard generator-engine feature and its absence blocks the entire domain.

**(b) The proxy corpus is a fixture, not a generator.**
`ProxyConstruction.sourceFragments` is **12 hardcoded strings** consumed by
`Gen.element(of:)`. A 100-trial `propertyCheck` therefore explores 12 distinct
inputs, with replacement. For a *consumer* of syntax that is a defensible
starting corpus; the doc comment is honest that the malformed entries are the
point. But it should say so — a reader sees `propertyCheck` and infers coverage
that is not there. Composing fragments (a `Gen<[Fragment]>` joined by newlines,
with nesting) would cost little and change the arithmetic.

**(c) The direction parsing actually needs is generate-AST → print → parse.**
The way you property-test a parser is: build a well-formed tree from a grammar,
pretty-print it, feed the text back in, compare. That requires (a). Nothing in
the stack supplies it, and it is the reason the fidelity law of §3 would still
be unrunnable even if it were proposed.

Appendix C's QuickCheck ledger names one capability-class omission —
higher-order generation. On this evidence there is a **second**: recursive /
size-controlled generation. QuickCheck ships it (`sized`, `frequency` +
recursion); the Swift stack does not. That belongs in the ledger next to `Fun`.

---

## 8. Finding 7 — type-symmetry pairing degenerates on builder DSLs and helper modules

Road-test finding 7 ("a spurious round-trip pairing still gets through — two
unrelated `String -> String` functions paired on type symmetry alone") reproduces
on both subjects, and on `SwiftSyntaxBuilder` it is not a stray pair but a
clique. Every `@resultBuilder` method has shape `(Component) -> Component`, so:

```
round-trip:   buildBlock(_:)      ↔ buildEither(first:)
round-trip:   buildBlock(_:)      ↔ buildEither(second:)
round-trip:   buildEither(first:) ↔ buildEither(second:)
round-trip:   buildEither(first:) ↔ buildLimitedAvailability(_:)
inverse-pair: (the same four again)
```

That is the entirety of `SwiftSyntaxBuilder`'s 23 `--include-possible`
suggestions minus the idempotence rows: 8 round-trip + 8 inverse-pair, all
noise, all from one `ListBuilder.swift`. `buildEither(first:)` and
`buildEither(second:)` are the two arms of a conditional — the least
inverse-related pair imaginable.

`@resultBuilder` is an attribute the scanner can see, and the `buildX` method
names are a closed, compiler-defined set. A veto here is cheap and exact.

In `SwiftProjectLintConfig` the same mechanism produces
`extractSwiftBasename(from:)` ↔ `realPath(_:)` as a round-trip — two unrelated
path helpers — which is, notably, the **only** round-trip proposed in a package
that contains three real parsers and a writer.

---

## 9. Summary — what is a defect and what is a hole

**Defects (fixable inside the existing catalog):**

1. ~~Stream-consumption veto: extend the iterator veto to cursor/lookahead/scanner
   carriers and consume/advance/skip/lex verbs, ungated by `IteratorProtocol`.~~
   **Shipped.** 53 false `Likely` claims on `SwiftParser` → 1 (the recorded
   accumulator residue). *(§2)*
2. ~~Widen `curatedInversePairs`: `parse`/`print`, `parse`/`unparse`,
   `parse`/`description`, `parse`/`render`, `tokenize`/`join`, `read`/`write`,
   `load`/`save`.~~ **Shipped**, with a store caveat on the persistence pairs.
   Latent — verified on synthetic shapes, zero delta on every measured corpus.
   Partly relieves §3b for curated names; does **not** reach the swift-syntax
   fidelity law, which §3c still blocks. *(§3a)*
3. Re-scope the cross-type −25 so it does not suppress `Loader`/`Writer`-style
   pairs, which is where serializer round-trips actually live. *(§3b)*
4. Make the `format`-prefix veto fire only when param type ≠ return type, as its
   own comment describes. *(§4)*
5. Admit type-erasing returns (`Self -> Syntax`, `Self -> any P`) to the `T -> T`
   templates as a lower-confidence variant. *(§4)*
6. Veto `@resultBuilder` `buildX` methods from type-symmetry pairing. *(§8)*
7. Pair against `CustomStringConvertible.description` as a printer half. *(§3c)*

**Holes (new templates / new discovery):**

8. **Normal-form retract** — `print ∘ parse` is idempotent. The law every lossy
   parser owes, expressible today by nothing in the catalog. *(§3d)*
9. **Differential / oracle equivalence** — `fast(previous, edit) ==
   slow(rebuilt)`. Generalizes far past parsing; the highest-value single
   addition on this evidence. *(§6)*
10. **Monotone progress** — a cursor advances or stops, never retreats; the true
    law for the 53 functions §2 currently mislabels. *(§2)*
11. **Tree-carrier interaction discovery** — unlock conservation, cardinality
    and biconditional (which are already carrier-agnostic as templates) for
    recursive types. *(§5)*
12. **Recursive, size-controlled generation** — without it, laws 8/10/11 and the
    two already firing at Strong on `Expr`/`Node` are all `.todo`. This is a
    generator-engine gap, not a catalog gap, and belongs in Appendix C's
    QuickCheck ledger next to higher-order generation. *(§7)*

**Honesty note.** The subject choice is uneven. `swift-syntax` is a genuine
parser and the right subject. `SwiftProjectLint` is *not* a parser — it consumes
`swift-syntax` — and its only first-party parsing is config/suppression-directive
loading in one 1.4k-line package. Findings drawn from it (§3b, §8) are about
serialization round-trips and pairing noise, not about parsing proper, and are
labelled as such above. Neither subject had a frozen answer key, so nothing here
is scored; the claims are either measured tool output or a reading of the
subject's own asserted invariants.
