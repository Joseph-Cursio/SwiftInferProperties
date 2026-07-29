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
> suppressed.

#### Fixed — exemption 4, the codec-carrier carve-out

**The counter was re-measured before being touched, and it earns its keep.**
Neutralised to 0 across the reference corpora it lets through **1,380
cross-type pairs**: 1,310 with the degenerate `T -> T` shape (`index(after:)`
on one collection against `index(before:)` on another — every `Index -> Index`
function pairs with every other by type text alone), and most of the remaining
70 accidents like `ByteBufferAllocator.buffer(capacity: Int) -> ByteBuffer`
against `ByteBuffer.readerIndex: Int`. Deleting or weakening it wholesale was
never an option.

So the fix is a carve-out, not a re-weighting. `CodecCarrierPairing` asks
whether the two carriers name **mutually inverse roles** —
`Loader`/`Writer`, `Encoder`/`Decoder`, `Parser`/`Printer`, `Packer`/`Unpacker`
— by taking the last camelCase token of each carrier's last dotted component
and looking the pair up. When they do, the counter returns `nil`: its stated
reason ("property cannot type-check across distinct containing types") is a
codegen concern, and for a codec split it is exactly backwards — the round trip
is *designed* to span the two types.

**Two more obvious discriminators were measured and both failed:**

- *Shared stem* — `LintConfiguration`Loader and `LintConfiguration`Writer share
  one, so it looks decisive. It is a disaster: the top noise carriers are
  `BigString` × `BigString.UTF8View`, `BigSubstring` × `BigSubstring.UTF16View`,
  `BigString._Chunk` × `BigString` — 64 pairs on the worst single combination,
  **all sharing a stem**. A stem test re-admits the entire flood.
- *Domain ≠ codomain* — "a real transformation, not an `Index -> Index`
  coincidence". Admits 70 pairs, of which two are codecs.

Both are pinned as negative cases in `CodecCarrierPairingTests`, using carrier
names taken verbatim from the measurement, so the reasoning stays visible
rather than having to be rediscovered.

**Measured: +2, and they are the right 2.**

| corpus | before | after |
|---|---:|---:|
| SwiftProjectLint `Config` (`--include-possible`) | 6 | **8** |
| everything else (11 corpora) | — | **unchanged** |

The two new rows are `LintConfigurationLoader.load(from:)` ×
`LintConfigurationWriter.render(_:)` and its `load(projectRoot:)` sibling — the
genuine config round-trip this section opened with. Zero of the 1,380 noise
pairs came back.

They land at 35 (`Possible`), so they are visible under `--include-possible`
but not on a default run: `load`/`render` is not a curated *name* pair, so the
+40 of §3a does not apply. Getting them to `Strong` is a naming question, and
the clean answer is not more pairs but **verb classes** — {parse, load, read,
decode, deserialize} × {print, render, format, write, save, unparse} — which is
a redesign of §3a rather than part of this fix.

**One behaviour change worth flagging.** Exemption 4 overlaps exemption 3 and
wins where they disagree: an `Encoder`/`Decoder` pair with *mismatched*
`@Discoverable(group:)` is now exempt, where before the mismatch kept the
counter firing. That is the intended precedence — the annotation is one source
of evidence, not the only one — and it is pinned by
`codecCarriersExemptEvenWithMismatchedDiscoverableGroups`. Two existing tests
in `CrossTypeRoundTripTests` used `Encoder`/`Decoder` as incidental scaffolding
while testing exemption 3's own boundary; they were moved to neutral carrier
names so they still test what they were written to test.

§3b is now closed for codec-shaped carriers and open for everything else.

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

#### Fixed — and the survey's headline miss is closed

`FunctionPairing` now admits a **protocol-mediated printer half**: the concrete
codomain may *conform to* the printer's declaring protocol rather than equal
it. Same admissibility idea as §5's erased self-form — the two halves compose
because the conformance says they do.

**Measured on real swift-syntax** (SwiftParser + SwiftSyntax + SwiftBasicFormat
in one scan, so `SourceFileSyntax: SyntaxProtocol` resolves):

```
Template: round-trip    Score: 45 (Likely)
  ✓ parse(source:) (String) -> SourceFileSyntax — ParseSourceFile.swift:22
  ✓ description() () -> String — SyntaxProtocol.swift:531
  ✓ Type-symmetry signature: String -> SourceFileSyntax ↔ SourceFileSyntax -> String (+30)
  ✓ Curated inverse name pair: parse/description (+40)
  ✓ Cross-type round-trip pair: forward in Parser, reverse in SyntaxProtocol (-25)
```

That is `Parser.parse(source).description == source` — the law asserted at
`Tests/SwiftParserTest/Parser+EntryTests.swift:22`, and **the miss this survey
opened with**. It took three fixes composing: §3a supplied the `parse`/
`description` name pair (+40, without which the residue is 5 and suppressed),
§3b's work established the pattern, and §3c formed the pair.

**Measured cost: +1 row, corpus-wide.** Every single-module corpus is
byte-identical; the combined swift-syntax scan went 932 → 933, and the diff is
exactly the two halves of that one pair. Nothing was removed anywhere.

The gate that bought this is `isPrinterHalf` — nullary, instance, `-> String`,
named `description` or `debugDescription`. Relaxing "codomain conforms to the
other half's domain" *in general* would pair every `X -> Concrete` against
every `Protocol -> X` in the corpus, which is the combinatorial flood §3b's
counter exists to stop. Scoped to the two `CustomStringConvertible` names it
admits one extra shape and no more.

**A caveat shipped with it, because the law is not universally true.** It holds
for swift-syntax because that printer is full-fidelity; it is **false for any
lossy parser**, and false for correct code. Every printer-half pair now
discloses which of the three readings is meant — `parse(print(x)) == x` over
values (cheap, nearly always true), `print(parse(s)) == s` over source text
(the interesting one, full-fidelity only), or the normal-form law
`print(parse(print(parse(s)))) == print(parse(s))` for the lossy case. That
last is §3d's retract — **now built** as `normal-form` (below), so the caveat
points at a template rather than standing in for one. The caveat reaches 11
suggestions on the combined scan — the new pair plus ten pre-existing
concrete-printer pairs carrying the same ambiguity unremarked.

### Built — `NormalFormTemplate`, and round-trip keeps the conjecture

A parse-print pair admits three laws with **different truth conditions**, and
until now the distinction lived only in caveat prose — caveat text doing a
template's job. So `round-trip` keeps the **conjecture** and `normal-form`
states the **entailment**. They coexist on purpose: the reader sees the strong
claim to check, and the one that holds either way.

`normal-form` is registered role-entailed (`Refutability.roleEntailedTemplates`)
— a correct pair cannot fail it, because failing means the printer emits text
its *own* parser reads back differently, which is a defect however lossy the
printer is meant to be. `input-totality` was added to that set at the same
time: it was documented as role-entailed when built and never marked, so it had
been carrying a "THIS LAW IS A CONJECTURE" caveat contradicting its own
rationale.

**The gate, and the mistake it corrects.** The first cut gated on **type shape
alone** — `text -> structure` against `structure -> text`. That fired **47
times** and the great majority were false, because plenty of functions have
those types and parse nothing:

| false firing | why |
|---|---|
| `ByteBufferAllocator.buffer(string:)` × `ByteBuffer.description` | a constructor, and that `description` is a debug dump (`ByteBuffer { readerIndex: 0, … }`) |
| `LintConfigurationLoader.load(projectRoot:)` × `render(_:)` | `load` takes a **path**, not content |
| `CleanExit.message(_:)` × four unrelated `description()` | a wrapper, paired across types |
| `generateHelp(screenWidth: Int) -> String` × `editDistance(to: String) -> Int` | pure type coincidence |

This is the fourth time in this survey that gating on type shape without name
evidence produced a flood, and it is worth stating plainly rather than quietly
fixing: **the pattern is the finding.** Adding the evidence the catalog already
had — an interpretation verb on the parse half, no location-shaped label,
`debugDescription` excluded as a developer dump — took 47 → **1**:
`Parser.parse(source:) × SyntaxProtocol.description()`, which now carries this
law alongside the fidelity claim §3c reached. Zero elsewhere.

One firing is thin, and it is the honest number: this law only *arises* where a
real parse-print pair exists, and the corpora contain exactly one.

Five caveats ship, the load-bearing one first: **if your printer is
full-fidelity, state the stronger law instead** — `print(parse(s)) == s` catches
everything this does and more, and this is the fallback for a printer that
normalises. The rest: the law is over the text `parse` accepts; it rests on
`parse(print(t)) == t` for trees `parse` produces; both halves must be
deterministic; and **generating parseable text is the hard part** — better to
generate the structure and print it, which is parseable by construction.

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

#### Fixed — the arm was carrying two arguments, not one

The veto bundled `_description*` and `format*` into one branch and applied the
**union of their triggers with neither of their conditions**. Split in two:

- **`_description*` — unconditional, no type gate.** Its argument is
  *structural wrapping*: `_description(type:)` prepends a type wrapper, so
  applying it twice prepends twice. That is a claim about what the function
  does to a value, so it holds at `String -> String` as much as anywhere — and
  `_description(type: String) -> String` is real code in swift-collections, so
  a uniform type gate would have wrongly released a genuine veto.
- **`format*` — gated on `param != return`**, which is what the type argument
  actually requires.

Measured on identical `String -> String` shapes: `format` went from suppressed
to **75 Strong**, `formatSource` from suppressed to 35, `normalize` unchanged at
75. The catalog had been crediting `format` +40 from `curatedVerbs` and then
vetoing it on the same name.

**Where the gate leaves `format*`, stated plainly.** Only two arms of
`typeSymmetrySignal` admit a parameter at all — the exact-equal form and the
optional-narrowing form (`func mergedWith(_ x: T?) -> T`) — so once gated,
`format*` fires on `(T?) -> T` and nothing else. On that one shape the original
*type* rationale is false as well: `format(format(x))` type-checks, because `T`
promotes back to `T?`, which is exactly why the optional-narrowing arm admits
the shape. The arm therefore now states the weaker claim that is true — a
function collapsing "absent" into a concrete value is *defaulting*, and the
second application asks a different question — and labels it a conjecture
rather than a type error. Deleting the arm outright is a defensible follow-on;
it is kept because narrowing a veto is a precision change and the measurement
shows keeping it costs nothing.

**Measured effect on the corpora: zero**, on all fifteen. Verified as genuine
absence rather than a broken fix: grepping every corpus for `format*` /
`_description*` declarations turns up six, and all six have `param != return`
(`format(completions: [String]) -> String`, `formatDimension(Double) -> String`,
`formatImports(in: String) -> SourceFileSyntax`, …), so none was ever admitted
by the shape gate. No corpus in the set has a same-type `format(T) -> T`. The
one that does reach the veto — swift-collections' `_description(type:)` — is
confirmed **still suppressed**, which is the evidence that the split preserved
what it needed to. Latent, like §3a.

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

> **Correction — there were two blockers here, not one.** Probing for the §5
> fix found that `formatted(using:)` is rejected on a *second* independent
> count: the self-form arm requires `parameters.isEmpty`, and `using format:`
> is a defaulted configuration knob, not an operand. Fixing only the erased
> return would have left the case exactly as unreachable. Both are closed
> below.

#### Fixed — the erased self-form, and the first live hit of the survey

`IdempotenceTemplate+ErasedSelfForm.swift` adds a fourth `typeSymmetrySignal`
arm, tried **last** so it can never shadow a concrete match. `Parameter` gained
`hasDefault` (scanner-populated) to tell an operand from a knob.

The law is well-formed for a checkable reason — `public struct Syntax:
SyntaxProtocol`, so `tree.formatted().formatted()` compiles. Weight **25**
rather than 30, per "lower-confidence variant"; with `formatted`'s curated +40
that lands at 70, `Likely`, visible on a default run without claiming `Strong`.
It carries a caveat the concrete forms do not: the law is checked on the
*erasure*, so a distinction the erased type drops is invisible to it.

**Measured on real swift-syntax** (SwiftSyntax + SwiftBasicFormat scanned
together, so the conformance resolves):

```
Score: 70 (Likely)
  ✓ formatted(using:) (BasicFormat) -> Syntax — SyntaxProtocol+Formatted.swift:21
  ✓ Type-symmetry signature: self -> Syntax on SyntaxProtocol (erased self-form …) (+25)
  ✓ Curated idempotence verb match: 'formatted' (+40)
```

That is **the first live hit of this survey** — the first fix that puts a real,
named law on the motivating subject rather than removing false ones (§2) or
landing latent (§3a, §4).

**Two tightenings, both forced by measurement.** The first cut admitted 11 new
rows across the corpora; nine were false, and each failure taught the rule:

- **A decorator is not an erasure.** `AsyncSequence.adjacentPairs() ->
  AsyncAdjacentPairsSequence<Self>` conforms to its carrier, so the conformance
  test admitted it — but applying it twice gives
  `AsyncAdjacentPairsSequence<AsyncAdjacentPairsSequence<S>>`, a *different*
  type, so `f(f(x)) == f(x)` does not type-check. Six of these
  (`adjacentPairs`, `compacted`, `joined`, `removeDuplicates`, `splitLines`,
  `splitUTF8Lines`). An erasure absorbs itself; a decorator nests — so the
  return must be **non-generic**.
- **A conformance is not an erasure.** `String` conforms to
  swift-argument-parser's `ExpressibleByArgument`, so
  `defaultValueDescription() -> String` passed every test — but `String` is not
  that protocol's erased form, it merely satisfies it, and a description of a
  description is not a fixed point. So the return must also be *named* as the
  erasure, by the two Swift conventions for it: `Syntax`/`SyntaxProtocol` and
  `AnyShape`/`Shape`.

**Final ledger: exactly 2 firings across all fifteen corpora, both true.**

| firing | tier | |
|---|---|---|
| `SyntaxProtocol.formatted(using:) -> Syntax` | 70 Likely | the target law |
| `SyntaxProtocol.root() -> Syntax` | 30 Possible | `node.root.root == node.root` — true, and unlooked-for |

Every other corpus is byte-identical to baseline.

**One interaction, found by the failure.** `formatted` carries the `format`
prefix, and its config parameter (`BasicFormat`) differs from its return
(`Syntax`) — so §4's freshly-added type gate vetoed precisely the case §5
exists to admit. The resolution is principled rather than an exception: that
gate's type argument is about the **operand**, and a defaulted parameter is not
one, so the veto now skips defaulted parameters. All of §4's own cases use
required parameters and are unaffected.

**Scope limit, stated rather than discovered.** The conformance lookup reads
the scanned corpus. `Syntax` is declared in `SwiftSyntax` while `formatted`
lives in `SwiftBasicFormat`, so scanning `SwiftBasicFormat` alone resolves
nothing and this arm stays silent — measured: 0 firings. Scanning both together
resolves it. Same cross-module limit `ProxyConstruction` and `EquatableResolver`
carry, and it fails in the conservative direction.

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

#### Measured, and rejected — the premise fails three times over

**1. The motivating example does not exist in the subject.** The table above
proposes `node.totalLength == node.children.map(\.totalLength).sum()` for
swift-syntax. `Syntax` has **no `[Syntax]` children member**: children come from
`func children(viewMode:) -> SyntaxChildren`, a computed sequence over opaque
raw storage. That shape was inferred from how ASTs usually look, and never
checked against the code.

**2. Nothing else in reach has the shape either.** A brace-matched scan for
non-static child collections across ten corpora — it took three attempts, the
first two producing artifacts from sibling members and `static let` singletons,
which is its own caution about surveys of this kind:

| corpus | true tree carriers | usable law |
|---|---:|---|
| swift-syntax, swift-collections, async-algorithms, SPL Models/Visitors, this repo | 0 | — |
| swift-nio | 1 | indirect enum, no witness members |
| swift-argument-parser | 2 | one false witness (`CommandInfoV0`), one tautology |
| SwiftProjectLint Config | 1 | `DirectoryNode.depth` relates to its *parent*, not `children.count` |
| SwiftProjectLint Rules | 1 | scanner artifact |

**5 carriers, 0 refutable laws.** The single plausible witness —
swift-argument-parser's `Tree` — is:

```swift
weak var parent: Tree?
var children: [Tree]
var isRoot: Bool { parent == nil }     // the "invariant" IS the implementation
```

`isRoot == (parent == nil)` holds by definition. That is the `f(x) == f(x)`
shape PRD §3.5 and Appendix C exist to exclude.

**3. And the machinery would not have transferred.** The paragraph above claims
"the scoring, rendering, and verify paths would not change". Wrong:
`ReducerCandidate` is action-centric (`actionTypeName`, `actionCases`,
`carrierKind`, `isAsync`), and downstream `ActionSequenceStubEmitter` emits
`for action in actions { … }` harnesses. A tree carrier has no actions, so this
was never "unlock the discoverers" — it would be a fresh template on the v1
surface. A fresh build, for zero firings.

### A guess outranked an assertion — measured, and fixed

Probed after the tree-carrier rejection, on the suspicion that today's
test-lifted work had exposed a ranking inversion. It had:

| law | where it came from | score |
|---|---|---|
| `normalize(normalize(d)) == normalize(d)` | a **guess** off the curated verb `normalize` | **75 Strong** |
| `mySort(x) == x.sorted()` | **asserted by a human**, executed 10,000× | **50 Likely** |

A name-derived conjecture outranking an executed, human-authored law by a full
tier is backwards — and the conjecture is the weaker claim by construction: PRD
§4.1's own counterexample for idempotence is a one-shot suffix strip, correct
code that fails the law. The lifted one had a person decide it holds for all
inputs and then run it.

Not a visibility problem — `.likely` (≥ 40) is already shown by default. The
**tier is the trust bar**: `docc` gates on it, `query` sorts by it, and a reader
believes it. It was pointing the wrong way.

`testBodyPattern` goes 50 → **80**. The signature side tops out at 75 (30
type-symmetry + 40 curated verb + 5 value-semantic carrier), and the lifted path
scores exactly one signal — so 75 would merely tie, leaving `query`'s
score-descending order arbitrary between a guess and an assertion. 80 makes the
assertion sort first.

Deliberately unqualified by test quality: the lift detects the *shape*, not how
thorough the test is. A one-example test still means a human decided the law
holds, which a curated verb never does.

Blast radius: ~23 lifted suggestions across this repo's three main targets, 0 on
SwiftProjectLint's Config package. Five test expectations pinned the old weight
and were updated — the calibration number changed deliberately, so the
assertions that recorded it had to follow.

### Road test — the swift.org suites the observation was about

Everything above about hand-rolled property tests was validated on **synthetic
fixtures**. Pointing the finished tool at the real corpora
(`swift-foundation`'s FoundationEssentials: 239 source files, 51 test files)
found two defects in the same day's work, and confirmed the observation's
premise.

**The premise holds.** `roundtrip` appears 723 times across `swift`'s Swift
sources and 329 across `swift-foundation` — property-shaped testing, written
without a framework. The tool lifts **51 suggestions** from those test bodies.

**Defect 1 — the slicer unwrap fired on ZERO real tests.** It required the
repetition loop to be the body's *only* statement. In the real suite:

| shape | count |
|---|---:|
| lone-loop body (unwrap fired) | **0** |
| setup line(s) then the loop (unwrap missed) | **10** |

Real property-style tests set up a generator or fixture first:

```swift
@Test func randomVersionAndVariant() {
    var generator = SystemRandomNumberGenerator()   // ← setup statement
    for _ in 0..<10000 {
        let uuid = UUID.random(using: &generator)
        #expect(uuid.versionNumber == 0b0100)
    }
}
```

The synthetic probe had a bare loop, so it confirmed a shape that does not
occur in the wild. Widened to *loop-last, bindings-before* — leading bindings
flow into the slice's setup region, which is what that region is for. Result:
51 lifted suggestions and a **new true differential firing** that had been
invisible.

**Defect 2 — the one real differential firing was FALSE.** Before the widening,
`differential-equivalence` fired exactly once on Foundation:

```swift
#expect(originalAttributes.merging(overlapping, mergePolicy: .keepCurrent)
        == originalAttributes.testDouble(4.3))
```

Both sides are methods on the same receiver, so the shared-input test passes and
the orientation rule read `testDouble` as the oracle. It is not: `testDouble` is
an AttributedString **attribute key**, and the right-hand side is the expected
container being *built*. The literal `4.3` is the tell — a reference computation
consumes the shared input (`contains(c)`) or nothing (`input.sorted()`); a
constructed expectation carries literals. A literal argument on the reference
side now rejects the pair.

**After both fixes, one differential firing on Foundation, and it is true:**
`isAllowedCodeUnit(c)` against `allowedSet.contains(c)` — a fast lookup checked
against a reference set, which is exactly the law this family exists for.

**A third form remains out of reach, and it is not a defect.**
`swift/test/stdlib/sort_integers.swift` is a **lit + FileCheck** test:

```swift
let sort_verifier: ([Int]) -> Void = { … if y[i] > y[i+1] { print("Error: \(y)") } }
permute(7, sort_verifier)          // EXHAUSTIVE, not random
//CHECK-NOT: Error!
```

There is no assertion function to anchor on — the property is expressed as
print-on-failure plus a FileCheck directive — and it quantifies *exhaustively
over permutations*, which is stronger than random sampling rather than weaker.
Reaching it would mean teaching `AssertionAnchor` about a second, non-assertion
verification idiom. Recorded, not attempted.

**The lesson, which is the same one twice.** Both defects came from validating
against fixtures I wrote myself. A synthetic probe confirms that the code does
what I intended; only real code says whether what I intended is the shape that
exists. The catalog's own rule — *score refutability, not suggestion count* —
has a sibling: **validate against found code, not authored code.**

### The generators are the weak half — measured

The road test above establishes that the *laws* in these suites are real. The
obvious follow-on question is whether the **generators** feeding them are, and
the answer is no — in a specific, fixable way. This matters because it decides
what the toolchain is actually *for* on this corpus.

**The explicit generator.** `swift/test/stdlib/sort_integers.swift` rolls its
own:

```swift
var N = 1
for _ in 0..<size { N = N * 19 % 1024; … arr.append(N) }
```

That is a multiplicative LCG mod 2^10. Its reachable state is bounded by
λ(1024) = 256, so:

| property | value |
|---|---|
| distinct values reachable, ever | **256** |
| range | 1…1019 — **all odd**, never negative, never zero |
| `randomize(1900)` | 2,524 elements, 489 distinct — **19% unique** |

For a sorting test that is a precise blindness profile: no `Int.min`/`Int.max`
(where comparator-overflow bugs live), no negatives, no evens. But note the
collision rate — 19% unique means heavy duplication, which by this repo's own
collision lesson (CLAUDE.md, `Decisions.merge`) is accidentally the *right*
tuning for stability and tie-break laws and the wrong one for range coverage.
The generator is not so much bad as **untuned and unaware of which way it is
tuned**, which is the failure mode a derived generator exists to remove.

**The idiom-level miss, and it is systematic.** Every `.random(in:)` range in
the test files:

```
8 ×  .random(in: 0 ..< UInt16.max)        ← excludes UInt16.max
1 ×  .random(in: Int8.min ..< Int8.max)   ← excludes Int8.max
2 ×  .random(in: .min ... .max) / (.min ..< .max)   ← the only two that don't
…    the rest are interior: 10..<100, 1..<42, 0..<1000, 0.0 ..< 1.0
```

Someone reaching for "the whole range" writes `0 ..< UInt16.max` and gets
everything **except the one value most likely to break the code** — eight times.
This is not carelessness. It is the half-open interval being the wrong default
for this one job, and no reviewer catches it because the line reads correctly.

**Edge cases are tested — just never under the quantifier.** Splitting the test
files into function bodies (crude regex split, so treat as approximate):

| | count |
|---|---:|
| test functions using `.random(` | 7 |
| …that also name an edge value | 4 |
| test functions naming an edge value with **no** randomness | **40** |

`.nan` appears 50 times, `.infinity` 28. The edge cases are covered
*thoroughly* — by hand-picked examples, in different functions from the random
loops. The two populations barely meet. Nobody drew NaN from a generator; they
wrote a test named for NaN.

**What this makes the toolchain for on this corpus.** The division of labour
falls out favourably:

- The human supplied **the law** — the judgment part, the part no tool does
  reliably. A hand-rolled property test is someone who already decided the
  invariant holds universally and committed to it executably. That is why
  `testBodyPattern` carries weight 80 rather than the 50 it launched with:
  measured evidence beats a naming heuristic.
- The **generator** is the mechanical part, and it is the part measured weak
  above.

So conversion is close to pure gain: keep the law verbatim, replace the
generator with one that weights NaN/±∞/±0/subnormals/`.max` into the *same*
distribution the loop draws from, and pick up shrinking and seed reproducibility
for free. Today a `UUIDTests` failure at iteration 7,432 hands you nothing.

**The bias to name before leaning on this.** The corpus is the set of laws
people *already thought of*, and its shape shows it: `roundtrip` appears 723×
across `swift` and 329× across `swift-foundation`, because round-trip is the one
property shape every developer recognises. Nobody hand-rolls a conservation or
referential-integrity test. The corpus is therefore a ceiling on **human
property vocabulary**, not on the catalog — which makes lifting and
source-inference complementary rather than redundant: lifting confirms what
people know, inference proposes what they do not.

It also makes the corpus a measuring instrument pointed *back* at the catalog.
Templates that show up hand-rolled everywhere have proven demand. Templates that
never appear hand-rolled are either useless or under-appreciated, and the corpus
alone cannot say which. That is the open question.

### What the defects/holes split turns out to be worth

Two of the three holes probed so far have not survived contact: libFuzzer
harnesses (premise false for a Swift source analyser — the real fuzzers are
C++) and this one. The differential/oracle family did survive, and it was the
one with **two independently observed witnesses** rather than a reasoned shape.

That tracks a real difference in how the two lists were built. Every one of the
seven **defects** was a firing observed in tool output, and all seven closed.
The **holes** were reasoned from reading, and read just as plausibly. Weight the
remaining ones accordingly: prefer a hole with an observed witness over one with
a compelling argument.

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

### Built — `DifferentialTemplate`

`VariantMarkers` (vocabulary) → `VariantPairing` (the pass) →
`DifferentialTemplate` (scoring and caveats). Fires on the motivating case at
**65/Likely**, resolving the projection correctly:

```
Template: differential-equivalence    Score: 65 (Likely)
  ✓ parse(source:) (String) -> SourceFileSyntax
  ✓ parseIncrementally(source:parseTransition:) (String, IncrementalParseTransition?) -> IncrementalParseResult
  ✓ Variant-implementation name pair: `parse` is the reference … marked `Incrementally` (+35)
  ✓ `parseIncrementally` accepts everything `parse` does … plus the extra state (+20)
  ✓ `parseIncrementally` returns a wrapper whose `tree` is exactly `parse`'s result (+10)
```

**Named first, shaped second**, and that order is the safety story. A
shape-first pass ("two functions with compatible signatures") is the same flood
§3b's counter exists to stop — type symmetry alone produced 1,380 candidates.
The marker is the evidence; the signature check only confirms the two can be
compared.

**Reach was measured before building, and it is thin.** Across ~5,900 distinct
function names in seven corpora the marker vocabulary matches **12 pairs**
(0.2%), and the template fires on **1**. That denominator is stated rather than
buried, because "it fires once" needs its eleven rejections accounted for —
and all eleven are correct:

| rejected | why |
|---|---|
| 9 × `unchecked*` (swift-collections) | `mutating`, `Void`-returning, on unsafe-handle carriers (`_UnsafeDequeHandle`) the carrier resolver correctly refuses. A lifted-shadow path would buy **zero** here — checked before deciding not to build it. |
| `_ensureFreeCapacity` / `…Slow` | the reference **guards and delegates to** the variant — a cold branch, not a second implementation |
| `_addHTTPClientHandlers` / `…Fallback` | side-effecting pipeline mutation, `Void` |

**The delegation case taught the sharpest caveat.** `_ensureFreeCapacity`
returns early when capacity already suffices and otherwise calls
`_ensureFreeCapacitySlow`, which reallocates unconditionally — so the two
*deliberately* differ on every input the guard catches, and the law would be
false for correct code. Only the `Void`-return gate rejected it, by luck rather
than design. Every emitted suggestion now carries that hazard by name, because
the same shape with non-`Void` returns would sail through.

Four other caveats ship with it: the law runs in **one direction** (a
counterexample blames the variant); it is a conjecture from naming, not an
entailment; a precondition-eliding variant's trap is **not a refutation**; and —
the one that matters most here — **the extra argument is where the property
lives**. swift-syntax already has this as an example test with one recorded
transition. What makes it a property is generating that transition, biased
toward the states the fast path treats specially.

### The test-side route — built, and it needed a slicer fix too

`AssertReferenceEquivalenceDetector` is TestLifter's seventh positive detector
and the first that reaches a law the catalog could **not** already state from
signatures. It promotes into `differential-equivalence`, which is precisely why
the template had to come first: a lifted record needs somewhere to land.

**The shape, and how it is told apart from the other six.** All the
equality-shaped detectors look at `assertEqual(A, B)`; what separates them is
the relation between the sides:

| detector | shape |
|---|---|
| round-trip | one side is the **bare input** — `g(f(x)) == x` |
| double-apply | **same callee** both sides — `f(f(x)) == f(x)` |
| symmetry | same callee, **swapped arguments** |
| **reference equivalence** | **different callees**, shared input, neither side bare |

The shared input is load-bearing: `f(a) == g(b)` with no identifier in common
is a fixture assertion, not a law.

**Direction is resolved structurally where possible.** If one side is a method
on the shared input (`input.sorted()`) and the other takes it as an argument
(`mySort(input)`), the latter is the subject — the library's answer is the
oracle, yours is the implementation. When both sides have the same form the
record says the direction is a guess, and the rendered line says so too, because
a counterexample gets attributed to the subject.

**A second, mechanical blocker turned up mid-build.** The detector worked inline
and through bindings but scored nothing on the shape the whole exercise is
about:

```swift
func testSortIsCorrectOnRandomArrays() {
    for _ in 0..<10_000 {
        let input = (0..<50).map { _ in Int.random(in: -1000...1000) }
        XCTAssertEqual(mySort(input), input.sorted())
    }
}
```

`AssertionAnchor` scans **top-level** statements, and here the only top-level
statement is the `for`. Isolated by measurement — the identical assertion
scored a finding flat and nothing wrapped, with no other difference. So
`Slicer` now unwraps a body that is *one* repetition loop: the loop **is** the
quantifier. Deliberately narrow — only when the body reduces to a single
`for`/`while`/`repeat`, so a loop that merely builds a fixture before a later
assertion is untouched, and not recursively, because a doubly-nested loop is a
table-driven test rather than a quantifier.

That change touches all seven detectors; the full suite is green, which is the
regression check that mattered.

**Measured:** the quote's exact shape now yields
`differential-equivalence` at **50/Likely**, naming `mySort` as the subject and
`sorted` as the reference.

What this closes is the finding that mattered most from the TestLifter probe —
every prior detector was keyed to a template the catalog already had, so the
lifter corroborated what it knew and discarded what it did not, including cases
where a human had already done the hard part. (One correction to that finding:
lifted records **do** originate suggestions via `LiftedSuggestionPromotion`'s
`+50 testBodyPattern` signal — the gap was detector coverage, not the
mechanism.)

### libFuzzer harnesses — measured, and deliberately NOT built

The obvious next step was a detector for `LLVMFuzzerTestOneInput`. Measured
first, and the premise does not hold for a Swift source analyser:

| | |
|---|---|
| Swift `LLVMFuzzerTestOneInput` definitions, all repos in reach | **2** |
| …that call a library function | **0** |
| The fuzzers the observation named (demangler, reflection) | **C++** |

The two Swift ones are `validation-test/Sanitizers/fuzzer.swift`, which
*deliberately crashes* to prove the fuzzer runtime works, and
`test/Driver/fuzzer.swift`, an empty body testing driver flags. Neither has a
subject to attribute totality to. `utils/sourcekit_fuzzer/sourcekit_fuzzer.swift`
is a driver script with no harness at all. A detector would have fired twice, on
noise, in the entire Swift monorepo — and reached none of the valuable fuzzers,
because they are in a language the tool cannot read.

Recorded here rather than built, because "we shipped a detector" would have
read as coverage.

### Built instead — `InputTotalityTemplate`

The *law* a fuzz harness asserts needs no harness. A function handed arbitrary
bytes owes **totality** — a value or a thrown error for every input, never a
trap — whether or not anyone wired a fuzzer to it. And those are plentiful
where harnesses are not.

Scored **role-entailed rather than conjectured**: nothing about "interpret these
bytes" admits "unless the bytes are strange". The same argument
`ProxyConstruction` already makes for syntax predicates.

**Two admission routes, and three traps that measurement found.**

- **Byte-typed parameter** (`Data`, `[UInt8]`, `UnsafeRawBufferPointer`, …) —
  content by construction; nobody passes a filename as `[UInt8]`.
- **Text parameter plus an interpretation verb** (`parse`, `decode`, `lex`,
  `tokenize`, …) — a bare `String` is far more often a *name* than a payload,
  so the verb carries the claim.

The traps, each caught by looking at real firings rather than reasoning:

1. **`read` and `load` are not interpretation verbs.** They take *locations* as
   often as content — `readlink(_ path: String)`, `load(projectRoot:)`.
   Excluded.
2. **A location-shaped argument label vetoes the function outright.** This is
   the discriminator between two functions of identical type shape in one
   package: SwiftProjectLint's `load(projectRoot: String) -> LintConfiguration`
   versus `parse(fileContent: String) -> [SuppressionDirective]`.
3. **Egress verbs.** The byte route needs no verb, which admitted the wrong
   *direction of travel*: swift-nio's `write(pointer:)` and
   `sendmsg(pointer:destinationPtr:…)` are syscall wrappers whose buffer is
   data being **transmitted**. Those were four of the first eighteen firings —
   and every false one. A type filter cannot tell ingress from egress; only the
   verb can.

**Measured: 18 firings → 14 after the egress veto**, and they sit exactly where
hostile input arrives:

| corpus | firings | |
|---|---:|---|
| swift-syntax (Parser+Syntax+Format) | 9 | `parse(source:)` ×2, `parseIncrementally` ×4, `parseTrivia` ×2, `internSourceBuffer` |
| swift-nio | 2 | `_readCInt(data:)` — a kernel control message — and `buffer(data:)` |
| swift-async-algorithms | 1 | `parse(_:theme:location:)`, a test-DSL parser |
| SwiftProjectLint Config | 1 | `parse(fileContent:)` |
| collections, argument-parser, Rules, Visitors, SyntaxBuilder | **0** | no flood |

The one weak firing is `internSourceBuffer` — an arena interner rather than an
interpreter. Defensible (it should be total for any buffer) but not a parser;
recorded rather than filtered, since filtering it would also lose `buffer(data:)`
and `_readCInt`.

**Three caveats ship with it**, because this law behaves unlike the others:
throwing is **not** a violation (it is the correct answer to invalid input); a
violation **crashes the test process** rather than shrinking to a tidy
counterexample, which is what a trap is and why fuzzers exist; and **a generator
of realistic input will never find one** — the counterexamples live in the empty
value, invalid UTF-8, lone surrogates, unbalanced delimiters and pathological
nesting, and have to be generated on purpose. That last is the collision-generator
lesson from CLAUDE.md in a different costume.

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

The law is proposed at the highest confidence tier and is unrunnable — the
worst combination available, because a Strong suggestion is the one a reader is
least likely to re-check.

> ### CORRECTION — this section was wrong twice, and both halves were fixed by building it
>
> The original text continued: *"Recursive generation with a size/depth budget
> (`Gen.recursive`-style, halving the budget at each level) is a standard
> generator-engine feature and its absence blocks the entire domain."* Neither
> clause survived contact with a probe.
>
> **It is not an engine gap.** Recursion is expressible on the *shipped*
> `swift-property-based` 1.2.0 with no new combinator:
>
> ```swift
> func genExpr(_ budget: Int) -> Generator<Expr, AnySequence<Any>> {
>     let leaf = Gen<Int>.int(in: -50...50).map(Expr.lit).eraseToAny()
>     guard budget > 0 else { return leaf }
>     let sub = genExpr(budget - 1)                       // budget = termination
>     return Gen<Expr>.frequency(
>         (1.0, leaf),
>         (1.0, zip(sub, sub).map(Expr.add).eraseToAny()),
>         (1.0, sub.map(Expr.neg).eraseToAny())
>     ).eraseToAny()                                      // makes the type nameable
> }
> ```
>
> Built against the exact `Expr` above, it compiles, runs, and — against a
> mutant that strips one level of double negation without recursing — **refutes
> with the minimal counterexample**, `.neg(.neg(.neg(.neg(.lit(0)))))`, shrunk
> from `.lit(-9)` in one iteration. `Gen.frequency`, `zip`, `map` and
> `eraseToAny()` were all already there.
>
> The real wall was a deliberate refusal, three lines of it:
> `GeneratorResolver.swift` returned `nil` on cycle detection, which pinned the
> type at `.todo`. A refusal in the *emitter*, not a hole in the *engine*.
>
> **It does not block "the entire domain" either.** A brace-matched scan of
> ~1,840 source files across swift-foundation, swift-syntax,
> swift-argument-parser / swift-nio and SwiftProjectLint found **two** genuinely
> recursive data types:
>
> | type | shape |
> |---|---|
> | `DirectoryNode.children: [DirectoryNode]` | recursive tree |
> | `CommandInfoV0.subcommands: [CommandInfoV0]?` | recursive tree |
> | ~~`Tree.parent: Tree?`~~ | `weak` back-pointer — a cycle, not a tree |
> | ~~`__JSONEncoder.ownerEncoder`~~ | private encoder impl, back-pointer |
>
> The claim that "every hand-written parser's AST is one of these two shapes" is
> false for the flagship case: **swift-syntax's `Syntax` is arena-backed**
> (`SyntaxDataArena` + `SyntaxDataReference`), not a recursive enum. Zero
> self-referential `indirect enum`s in any corpus.
>
> Two earlier passes of that scan returned 283 and 96, both inflated by the same
> sibling-member attribution bug (a fixed-size window running past the closing
> brace into the next declaration) that broke the tree-carrier scanner three
> times on the same day. Fourth occurrence of one bug; the counts only became
> adjudicable once the scan matched braces.
>
> **Shipped anyway, for integrity rather than reach.** `Strong` + `.todo` is a
> promise the tool cannot keep, and two types is still two more than zero. The
> kit now emits a depth-budgeted helper `func` (`RecursiveGeneratorEmitter`,
> SwiftPropertyLaws) for recursion sitting under a collection or optional
> wrapper — which is the shape **both** measured types have.
>
> One trap dictated the design and is worth carrying forward: `Gen.array(of:)`
> evaluates its element generator **eagerly**. A budget check written inside the
> expression (`.array(of: budget > 0 ? 0...8 : 0...0)`) still *constructs*
> `helper(budget - 1)` in order to pass it, which constructs `helper(budget - 2)`,
> past zero, forever — infinite recursion at generator-*construction* time,
> before a value is drawn. It presents as a **hang**, not an error. The base case
> has to be a real early return with its recursion points collapsed to `[]` /
> `nil`, which is why the *wrapper* is what supplies the terminal and why a bare
> `indirect enum` payload (no wrapper) is still refused.
>
> The lesson matches the one the swift.org road test produced the same day:
> reasoning about a hole predicted an engine gap and a whole blocked domain;
> a two-hour probe found neither. **Holes get reasoned about; defects get
> observed.** This is the fourth reasoned hole to shrink on contact.

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

~~Appendix C's QuickCheck ledger names one capability-class omission — higher-order
generation. On this evidence there is a **second**: recursive / size-controlled
generation. QuickCheck ships it (`sized`, `frequency` + recursion); the Swift
stack does not. That belongs in the ledger next to `Fun`.~~

**RETRACTED — the ledger keeps one omission, not two.** The correction in (a)
above is what withdraws this: `swift-property-based` ships `frequency`, and a
plain depth-parameterised Swift `func` supplies what QuickCheck's `sized` does,
so there is no missing *capability* — only a resolver that declined to use it,
now fixed. QuickCheck's `sized` is more ergonomic and threads the budget
implicitly; that is an ergonomics gap, and ergonomics gaps do not belong in a
capability ledger next to `Fun`, which names something the stack genuinely
cannot express.

**Higher-order generation remains the one real entry**, and is now the only
unprobed item on this list — worth holding to a higher standard of evidence
than this section met, given it is the last claim here that has been reasoned
about rather than built.

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

#### Fixed — and the attribute half of that sentence was wrong

`ResultBuilderMethods` curates the compiler's own list (SE-0289 plus SE-0348's
`buildPartialBlock`), matched **exactly** — never by a `build` prefix, since
`buildRequest` / `buildURL` / `buildIndex` are ordinary functions that may own
real laws. `FunctionPairing.isPairable` rejects them outright, and
`IdempotenceTemplate` gets a matching veto.

**The attribute gate would not have worked**, which is worth recording because
the sentence above proposed it first. swift-syntax declares

```swift
public protocol ListBuilder { … }        // no @resultBuilder anywhere
```

— the attribute goes on the *conforming* types elsewhere, while the methods and
their default implementations live on the bare protocol. An attribute gate
reaches **none** of the 21 rows. The names are the better gate anyway, because
they are not a heuristic: the compiler calls exactly this list, and a type that
spells one of them means the builder method or means nothing.

**Scope widened past the triage line, deliberately.** Row 6 said "veto from
type-symmetry *pairing*", which covers the 8 round-trip + 8 inverse-pair rows.
But the same file also produced **5 idempotence** rows on the same methods, and
those are worse than false — they are *unrefutable*.
`buildEither(first component: Component) -> Component { component }` is the
identity, so `f(f(x)) == f(x)` holds by construction and no implementation
could fail it. That is the `f(x) == f(x)` shape PRD §3.5 and Appendix C's
"score refutability, not suggestion count" exist to keep out. Vetoing the pair
while keeping the idempotence on the same method would have been an arbitrary
half-measure.

**Measured: SwiftSyntaxBuilder 23 → 2, and the 2 are the right 2** —
`Indenter.visit(_:)` and `ensuringTrailingComma()`, the only non-builder
subjects in the module. Every other corpus byte-identical; the lone `+1` on
this repo's own `SwiftInferCore` is the tool scanning the new file's own
`isBuilderMethod` predicate, the same self-scan artifact §2 produced.

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
3. ~~Re-scope the cross-type −25 so it does not suppress `Loader`/`Writer`-style
   pairs.~~ **Shipped** as a carve-out, not a re-weighting — the counter was
   re-measured first and suppresses 1,380 pairs, nearly all noise. +2 true
   positives, 0 of the 1,380 re-admitted. Closed for codec-shaped carriers;
   open for everything else. *(§3b)*
4. ~~Make the `format`-prefix veto fire only when param type ≠ return type.~~
   **Shipped** — the arm was carrying two arguments, so it split: `_description`
   keeps its unconditional veto (structural wrapping is type-independent),
   `format` takes the gate. `format(String) -> String` suppressed → 75 Strong.
   Latent: zero corpus delta, verified as genuine absence. *(§4)*
5. ~~Admit type-erasing returns (`Self -> Syntax`, `Self -> any P`) to the
   `T -> T` templates as a lower-confidence variant.~~ **Shipped**, and it
   needed a second gate the survey had missed (defaulted config parameters).
   **The survey's first live hit**: `SyntaxProtocol.formatted(using:)` now
   proposes formatter idempotence at 70/Likely on real swift-syntax. Two
   firings across all corpora, both true, after two measurement-forced
   tightenings (a decorator is not an erasure; a conformance is not an
   erasure). *(§4)*
6. ~~Veto `@resultBuilder` `buildX` methods from type-symmetry pairing.~~
   **Shipped**, scope widened to idempotence as well — the same methods
   produced 5 *unrefutable* identity laws. SwiftSyntaxBuilder 23 → 2. The
   attribute gate this row proposed would have caught none of them;
   `ListBuilder` carries no `@resultBuilder`. *(§8)*
7. ~~Pair against `CustomStringConvertible.description` as a printer half.~~
   **Shipped — and it closes the survey's headline miss.**
   `Parser.parse(source).description == source` is now proposed on real
   swift-syntax at 45/Likely, with a caveat naming which of the three
   directions is meant. Cost: +1 row corpus-wide. *(§3c)*

**Holes (new templates / new discovery):**

8. ~~**Normal-form retract** — `print ∘ parse` is idempotent.~~ **Built** as
   `normal-form`, registered role-entailed and coexisting with `round-trip`,
   which keeps the conjecture. 47 firings on type shape alone → 1 once name
   evidence was required. *(§3d)*
9. ~~**Differential / oracle equivalence** — `fast(previous, edit) ==
   slow(rebuilt)`.~~ **Built.** `DifferentialTemplate` + `VariantPairing` +
   `VariantMarkers`. Fires on `Parser.parse` × `Parser.parseIncrementally` at
   65/Likely — the law swift-syntax states in its own test utilities and
   writes as an example harness. One firing across 22 corpora; the eleven
   other marker pairs are all correctly rejected. *(§6)*
10. **Monotone progress** — a cursor advances or stops, never retreats; the true
    law for the 53 functions §2 currently mislabels. *(§2)*
11. ~~**Tree-carrier interaction discovery.**~~ **Probed and NOT built** — the
    premise fails twice over. See §5's "measured, and rejected" note. *(§5)*
12. ~~**Recursive, size-controlled generation** — without it, laws 8/10/11 and
    the two already firing at Strong on `Expr`/`Node` are all `.todo`. This is a
    generator-engine gap, not a catalog gap, and belongs in Appendix C's
    QuickCheck ledger next to higher-order generation.~~ **Built — and the
    diagnosis in this row was wrong on both counts.** Not an engine gap: the
    shipped backend expresses recursion with `Gen.frequency` + `zip` +
    `eraseToAny()` and a depth-parameterised `func`, no new combinator. Not a
    ledger entry either, so Appendix C keeps *one* omission rather than two.
    The wall was `GeneratorResolver` refusing cycles; it now emits a
    depth-budgeted helper (SwiftPropertyLaws v3.21.0). Reach is **2 types**
    across ~1,840 files, not "the entire domain" — shipped for integrity, since
    Strong + `.todo` is a promise the tool cannot keep. *(§7)*

### Probe — higher-order generation, the last unbuilt claim

Recursive generation was written up here as a missing engine capability and
turned out to be neither missing nor blocking. Higher-order generation had the
same provenance — reasoned about, never built — and it is the headline claim of
Appendix C's QuickCheck ledger, so it was probed before it hardened.

**Result: the ledger entry survives, but it is mis-stated.** The omission is not
*generating* functions. It is *shrinking and displaying* them.

**Generation works today, with no new combinator.** A pure function is a seed
plus a hash, and a plain `map` closes over the seed — `flatMap`, which the
backend does not have, is not needed:

```swift
Gen<Int>.int(in: 0...65_535).map { seed in
    let f: @Sendable (Int, Int) -> Bool = { a, b in
        var h = Hasher(); h.combine(seed); h.combine(a); h.combine(b)
        return h.finalize() % 2 == 0
    }
    return f
}.eraseToAny()
```

That compiles, runs, and produces genuinely distinct functions. So `Gen<(A) -> B>`
is expressible on shipped `swift-property-based` 1.2.0.

**The proposed dual is real, and quantifies over garbage.** Appendix C names the
missing dual of the comparator work: *for all* generated comparators, `sort` is a
faithful permutation. Measured over 500 generated `(Int, Int) -> Bool`:

| | |
|---|---:|
| generated comparators that are strict weak orderings | **0 / 500** |

Not a low rate — **zero**. An arbitrary boolean function of two arguments is
essentially never irreflexive, asymmetric *and* transitive. That does not sink
the law, because "a sort must not drop or duplicate elements" holds even under a
garbage comparator, and the probe confirmed it refutes a real
treat-incomparable-as-duplicate bug ( `[5,3,9,1,7,2]` → `[5,3,9]` ). But it does
sink any law needing a *valid* ordering — "the output is sorted" is
unstatable against arbitrary comparators, because sort owes nothing there.

The fix is to generate validity by construction: compare by a generated **key**
function, inheriting the ordering laws from `<` on the key. Measured
**500 / 500** valid, and the stronger law becomes statable.

**What is genuinely absent is the report.** Force a failure and compare:

```
Failure occured with input (Function).   (shrunk down from (Function) after 1 iteration)
Failure occured with input 0.            (shrunk down from 76 after 1 iteration)
```

The first is a function-valued generator; the second quantifies over the **seed**
and derives the function inside the body. The seed form is displayable,
replayable, and shrinks. The function form tells you only that some function
failed.

**And the seed workaround does not fully close it.** A smaller seed is not a
*simpler* function — `hash(0, x)` is no more comprehensible than `hash(76, x)`,
so shrinking is nominal: it minimises an `Int` that happens to index a function,
not the function itself. QuickCheck's `Fun` shrinks toward a smaller *table* —
fewer distinguished input points — and prints that table, which is what makes a
failing function readable. That is the capability, and it is genuinely not here.

**So the corrected ledger entry** is not "the stack cannot generate functions"
but: *the stack can generate functions and cannot shrink or show them, so a
function-valued counterexample is unactionable; quantify over a seed instead and
recover replay, but not minimisation.*

Nothing built. The catalog proposes laws over the code it reads, and a
generated-comparator law is a law the **user** writes about their own sort — it
has no discovery surface here. Recorded so the ledger claim is accurate.

**Honesty note.** The subject choice is uneven. `swift-syntax` is a genuine
parser and the right subject. `SwiftProjectLint` is *not* a parser — it consumes
`swift-syntax` — and its only first-party parsing is config/suppression-directive
loading in one 1.4k-line package. Findings drawn from it (§3b, §8) are about
serialization round-trips and pairing noise, not about parsing proper, and are
labelled as such above. Neither subject had a frozen answer key, so nothing here
is scored; the claims are either measured tool output or a reading of the
subject's own asserted invariants.
