# Does a text-built XML document parse, and do its SVG references resolve? (#668)

> **Status:** `proposed` · **As of:** 2026-10-30

#668 asks for two laws the catalogue does not have, gated separately. For a pure, synchronous, non-throwing,
non-mutating function or computed property that builds an XML document as a `String`:

> **Law 1: the document parses.** On the complement of any early return that `guard-domain` owns,
> `XMLParser(data: Data(f(x).utf8)).parse()` is true.
>
> **Law 2 (SVG only): every same-document reference resolves.** Each `url(#X)`, `href="#X"` and `xlink:href="#X"`
> in the output names an element with `id="X"` in the same output.

**What is already settled.** #668's witness is SwiftUMLStudio's `SwiftUMLBridge`. Its confirmed defect, a source
folder named `Old--Code` making `SVGRenderer` write `<!-- Old--Code -->`, was filed as SwiftUMLStudio#56 and fixed
by that repository's PR #79 (merged 2026-10-13 as `ea315da`): labels are no longer copied into comments. A second
one, `xmlEscaped` passing through the C0 controls XML 1.0 forbids, was filed as #80 and fixed by PR #86
(`5877c17`), which walks Unicode scalars and replaces forbidden characters.

- **Those two PRs wrote Law 1 by hand into the witness's own suite.** PR #79 created a `WellFormedXML` test helper
  (`XMLParser(data:).parse()`), and the two PRs between them created a `*WellFormednessTests` suite for each of
  the four renderers. So at `9ad7631`, the revision this scope reads, Law 1 is asserted for every renderer over a
  fixed list of labels.
- **No test asserts Law 2.** `ComponentSVGRendererTests.swift:122` asserts that `marker-end="url(#arrow)"` is
  present, never that `id="arrow"` is defined. No test in the package collects ids or references.

**What remains is #668's step 0**: a census of each law's population, with the two laws gated separately (§1–§4),
and, as #667 and #669 did, the laws written by hand and mutation-scored on the witness (§5). #668 expects that Law 2,
which its grep found in one repository, may end in "a single-subject decline".

---

## 1. The census pass

`scripts/xml_emitter_census.py`. Section numbers in its comments are this scope's.

### 1.1 The unit

The unit is each of these, found by #669's scanner and owner rule (`layering_census.declarations`), with two
changes, both from the review (§10):

- **Units are bounded on `regex_acceptor_census.mask_code`'s view, not on #669's masker.** #669's masker ends a
  one-line literal at the first `"` even inside an interpolation, so `"<a>\(xs.map { "<b c=\"\($0)\"/>" }.joined())</a>"`
  leaked a brace and cut the unit short (X31). The packets' member lists use the same view.
- **Computed properties are units too**: a `var NAME: TYPE {` directly in a type body or at file scope whose block is
  a getter. A block is a getter unless it opens with `willSet`, `didSet` or `set`; a block that opens with `get`,
  `mutating get` or `nonmutating get` takes that getter's body and its effects. #668 names "a function or computed
  property"; #669 left computed properties out (its §9).

Initialisers, subscripts and closures are not units (§9). Stored properties are not units, but they can be hops.
An `import struct M.T` line declares nothing, so the type written after it keeps its own computed properties (X36).

**Two views of each unit.**

- **The code view** is `mask_code`'s: comments, literal text and regex literals blanked, each interpolation's code
  kept. Search-key positions, references, the signature and the purity tokens are read off it.
- **The literal view** lists every string literal in the unit's body, nested ones (inside an interpolation)
  included, in source order. Each entry is the literal's span and its content:
  - escapes resolved (`\"` → `"`, `\\` → `\`, `\n` → a line feed, `\t` → a tab, `\u{…}` → the scalar);
  - each interpolation replaced by one placeholder character, U+0001;
  - in a multi-line literal, a backslash that ends a line removed together with the line break, as Swift does.

  Raw strings (`#"…"#`) are read with their own delimiters, and their escapes and interpolations need the same
  number of `#`. A literal starts only where the code view keeps its opening quote, so a quote inside a regex
  literal (`/"/`) never opens one (X27). Every cue below except references, the signature and PURE is read off the
  literal view.

### 1.2 Cues

**Shared terms.**

- **Start tag.** `<` followed by an XML name, `[A-Za-z_:][A-Za-z0-9_.:-]*`. `</`, `<!` and `<?` do not start one.
  A tag whose name is the placeholder (`"<\(tag) xmlns=…"`) is not a start tag (C31). Text inside an XML comment
  (`<!--…-->`) or a CDATA section (`<![CDATA[…]]>`) is not markup: a tag or an end tag named there opens, roots and
  closes nothing (X34). One left open runs to the literal's end.
- **End tag of `R`.** `</R` followed by optional whitespace and `>` (X19: `</svg >` closes, `</svgs>` does not).
- **Same type.** Two units have the same type when their owners have the same base name, in any type body or
  extension of that name in the same repository (every subject that shares the git toplevel, §2). Two top-level
  units have the same type when they are in the same file.
- **Reference.** A name in the body's code view that some same-type member has: a call `name(`, or a read `name`
  that is bare or follows `self.`, `Self.` or the owner's own name and a dot. A bare read is not a reference when a
  local of the body (`let`, `var`, every name of a `for` pattern or a tuple binding, a closure parameter, typed or
  not, after a capture list or an attribute, with or without a result type) or a parameter of that name shadows it,
  or when it is an argument label (`name:` after `(`, `,` or `[`, blank lines between). A local declared anywhere in
  the body shadows the name everywhere in it, not by scope (X9, disclosed in §9). An explicit receiver is never
  shadowed, however many blank or comment lines stand between it and its dot, and any other receiver (`doc.header`,
  `Other.header()`) is not a reference (X8, X9, X10).
- **Hop.** Every same-type member of a referenced name, overloads included: a `func`, a computed property or a
  stored property. The unit itself is never its own hop, but an overload of its name is (X11, X12). **One level
  only**, as `PreconditionHelperHop` follows a precondition (`precondition-helper-hop.md`). A hop's literal view is
  its body's, or, for a stored property, its initialiser's; an initialiser runs, outside brackets, to a line that
  ends no operator (`+`, `=`, `,`, `(`) and is not followed by a line that starts with `.` or `+` (X6). A stored
  property at file scope is a top-level unit's hop (X7).
- **A hop's result reaches the text** when the hop is a `func` or computed property written `String` or
  `[String]` (or `Swift.String`, `[Swift.String]`, `Array<String>`, `Array<Swift.String>`), or a stored property
  typed so, or untyped and initialised by literals alone joined by `+`, read on the code view so that a trailing
  comment is not code (X7: `"…".count` is not; `= "<svg …>" // opener` is).
- **Search key.** A literal or a reference is a search key when it is:
  - an operand of `==`, `!=` or `~=`, the whole receiver chain of an explicit reference included (X13);
  - a `case` label (`case "<?xml":`);
  - or, walking outward through the brackets that enclose it up to the nearest `{`: an argument of a call named
    `hasPrefix`, `hasSuffix`, `contains`, `starts`, `range`, `ranges`, `firstRange`, `firstIndex`, `lastIndex`,
    `components`, `split`, `trimmingPrefix`, `trimPrefix`, `matches`, `wholeMatch`, `prefixMatch`, `firstMatch`,
    `replacing`, `replace`, `memcmp`, `strcmp` or `strncmp`, except a `replacing` or `replace` call's `with:`
    argument, which it writes; or an argument labelled `of:` of any call (`replacingOccurrences(of:`). So
    `data.starts(with: Array("<?xml".utf8))` is a key (X1).

  Anything else **flows**. This is #668's rule 4, "appended, concatenated, interpolated or returned", read as
  text: a literal that is not a search key is taken to reach the result. The judges see the whole body.
- **The stream.** The body's flowing literals and its flowing references to hops whose result reaches the text,
  in source order, each such hop contributing its own flowing literals in order. A hop read inside a literal's
  interpolation, and a literal nested there, sit at that interpolation's placeholder, in every flowing literal that
  holds them, outermost first, and each such literal is cut there. So `"\(header)\n<root>"` reads the hop before
  `<root>`, and `"\(flag ? "<?xml…?>\n" : "")<root>"` the declaration before it (X35). A literal's opening marker is
  still found in the whole literal, so a tag a placeholder interrupts (`<svg width="\(size)" xmlns=…>`) opens where
  it starts, and a marker opens only from the piece that holds it.

**The cues.**

- **The opening literal.** The first literal in the stream that holds an opening marker: `<?xml` (**XMLDECL**), or
  a **first** start tag that carries an attribute named `xmlns` or `xmlns:PREFIX` before the tag's next `>`, or
  before the literal's end when it has none (**XMLNS**; `svgHeader` closes its tag in a later literal).
  Placeholders may stand between them. An `xmlns` tag after another start tag in its literal is an element inside
  some other root (`<div><svg xmlns=…>`), not an opener (X15). Within the literal, whichever marker comes first
  decides. **Across literals the rule does not reach**: `html += "<div>"; html += "<svg xmlns=…>…</svg>"` opens with
  ROOT `svg`, and so is GATED. No text rule tells that from a chart that builds its body before its opener
  (`bars += "<g>…</g>"; return "<svg xmlns=…>" + bars + "</svg>"`), so both are pinned as they stand (X39) and §9
  lists the first as a route to a GATED row that does not owe the law.
- **OPEN.** The stream has an opening literal: in the body (**OPEN-BODY**) or in a hop (**OPEN-HOP**). #668's rules
  1 and 3.
- **ROOT.** The root's name.
  - For XMLNS, the name of the tag that carries `xmlns`.
  - For XMLDECL, the first start tag in the rest of the opening literal, up to the first cut the stream makes in it
    after the declaration's `?>` (so `"<?xml…?>\n\(svgOpen)\n<rect/>"` takes its root from the hop, X35, and a hop
    inside the declaration ends nothing); failing that, the first later start tag in the stream that carries
    `xmlns`; failing that, the first later start tag whose end tag some flowing literal
    of the body or of a hop writes; failing that, the first later start tag. So `"<?xml…?>" + root()` takes its
    root from `root()` (C34), and a `"<nopath>"` placeholder written before the root is passed over (X18).
  - **When the root is never closed, step 3 can take a child whose end tag is written.** A declaration header whose
    root has no `xmlns` and sits in its own literal, followed by a complete child (`"<?xml…?>\n" + "<rss …>\n<channel>\n"
    + "<title>…</title>"`), is GATED with the child as ROOT (X39). The judges read such a row as FRAGMENT: it enters
    gate precision as a miss and is listed as GATED not owing, and it never reaches N_gated, which counts owing
    groups only. The review's proposed fix (skip a tag whose end tag follows in its own literal) moved X18's shape,
    a true document, out of the gate, so the step stands.
- **CLOSE.** A flowing body literal holds the end tag of ROOT. #668's rule 2. **CLOSE-HOP**, reported for R2 and
  outside the gate, is a close that only a flowing hop in the stream writes: #668 lets only the opening literal sit
  one hop away (X19).
- **HTML.** A literal of the stream holds `<html` or `<!doctype html`, ignoring case: #668's rule 5, "does not also
  emit". A search key `"<html"` is not HTML (X20).
- **IDDEF.** A literal of the body or of a hop holds an attribute named exactly `id` with a quoted value: `id="` or
  `id='`, after whitespace or at the literal's start (X21). `data-id=`, `gid=` and an unquoted `id=` are not. This is
  #668's condition on Law 2: the subject's own literals, in its body or one hop away, define an `id=`.
- **REF.** A literal of the body or of a hop holds `url(#`, `href="#`, `href='#`, `xlink:href="#` or
  `xlink:href='#`. Reported; not in either gate. A reference two hops away is not seen (C4).
- **COMMENT.** A literal of the body or of a hop opens an XML comment (`<!--`). Reported, for the `--` hazard.
- **XMLDECL, XMLNS as reported.** Whether any literal of the stream holds each marker; the gates read OPEN.
- **Signature.** Read off the declaration.
  - **STRING**: the result is `String` or `Swift.String`, exactly. A computed property's type is its result.
  - **NOTHROW**: neither `throws` nor `rethrows` between the parameter list and the body (a parameter's closure type
    does not count, C38), and no `get throws`.
  - **SYNC**: no `async` there, and no `get async`.
  - **NONMUTATING**: no `mutating`, and no `mutating get`.
- **PURE.** No impurity token in the code view of the body or of a hop: `FileManager`, `ProcessInfo`,
  `Bundle.main`, `UserDefaults`, `URLSession`, `FileHandle`, `Process(`, `Date()`, `Date.now`, `.now()`, `UUID()`,
  `.random(`, `arc4random`, `CFAbsoluteTimeGetCurrent`, `DispatchTime.now`, `getenv(`, `fopen(`, `print(`,
  `NSLog(`, `currentDirectoryPath` (C12 pins each alone). The `print` of a call whose own argument is labelled
  `to:` (`print(x, to: &out)`) builds text and is not a token; tokens in its arguments still count, and a `to:`
  nested inside an argument (`print(a.distance(to: b))`) does not make it one (X28). #668's signal
  asks for "SEI verdict not refuted". The census does not run SEI, so this frozen list stands in for it; it cannot
  see impurity inside another type's call (#668's own example, `GitLabJUnitReporter`'s `relativeDisplayPath`), so
  the judges record **ambient** (§4.4) and §8 reports the signal without the rows they flag, and the gate's
  precision without PURE.

### 1.3 Candidates and copies

A unit is a **candidate** when either holds:

- a body literal holds one of #668's grep markers: `<?xml`, `xmlns`, `<svg`, `</svg>`, `<plist` or `</plist>`;
- OPEN-HOP holds and a body literal holds an end tag (`</` and a name) (X17).

`run` passes over a file or a unit whose raw text holds none of the grep markers, `</`, `\u{`, `\#u{` or `"""`; no
literal of it can then be a candidate, since an escape or a multi-line literal's joined lines are the only ways a
literal's content holds a marker its raw text does not. X37 pins that the prefilter changes no row.

**Copies merge across the whole universe**, as #669's §1.3 merges them, but on a key that sees the literals: same
name, same argument labels, the same code view of the body (interpolations kept) and the same literal contents,
whitespace collapsed. #669's key blanked literal text, and here the literals are the signal: two emitters that
differ only in the XML they write would have merged, and the first by path, not by gate, would have been judged
(X32). Owner and parameter types are not compared. A copy counts once, at the first in this order: group (decision,
unmet, layout, wide), then repository (git toplevel), subject, path and line (X33). Every other copy is listed on it,
with its group and its subject.

### 1.4 The gates a template could read

- **GATED** (Law 1) when STRING ∧ NOTHROW ∧ SYNC ∧ NONMUTATING ∧ PURE ∧ OPEN ∧ CLOSE ∧ ¬HTML. That is #668's
  signal, its five rules and its signature, applied mechanically. OPEN and CLOSE are flowing by definition, so rule
  4 is inside them. Where the opener is a declaration, "that root" is the census's reading (§1.2's ROOT), and X39
  pins the one shape where that reading closes a child instead of the root.
- **GATED2** (Law 2) when GATED ∧ ROOT = `svg` ∧ IDDEF.

Both are computed for every candidate and never shown to the judges.

## 2. The universe, frozen

The census reads #669's four groups, with these changes, all frozen here:

- **Decision (37 subjects).**
  - The manifest (22) and funnel (19) groups of `regex_acceptor_census.FROZEN_UNIVERSE`, with five subjects in
    both, each read from its root, as #669 read them.
  - **Plus SwiftLint**, at `~/github_projects/SwiftLint`, revision `ec4691d9e`, `origin` `realm/swiftlint`, clean.
    #668 names it: "Law 1 already has a second subject", SwiftLint's `CheckstyleReporter` and `JUnitReporter` at that
    revision. #666 brought the upstream SwiftFormat it named into its universe in the same way. **#667's and #669's
    universes held SwiftLint in the wide group**, so §8 prints N with SwiftLint left out, and prediction 1 says the
    population bar is expected to rest on it.
  - **SwiftUMLStudio is read at `9ad7631`**, its `origin/main` on 2026-10-30, with a clean tree. #669 read
    `c6c82e3`. The witness's fixes for #56 and #80 are in `9ad7631`, and the kill arm (§5) exports the same
    revision.
- **Unmet (13).** #669's five (Euclid, swift-docc, OpenAPIKit, jwt-kit, swift-system), and the eight unmet subjects
  #666's census could not find, which now resolve under `~/github_projects`: Harbeth, JiraKit, nocturne-swift,
  Open-Jellycore, scale-codec-swift, sora-ios-sdk, StripeKit and swift-codex. Read from their roots. **N_unmet**.
- **Layout (18).** #667's graph-layout corpus, asserted by `layering_census.corpus_universe()`: each clone at its
  frozen revision with a clean tree. **N_layout**.
- **Wide (67 directories).** Every directory with Swift sources directly under `~/xcode_projects` and
  `~/github_projects` that no other group holds, with its `origin`, re-taken on 2026-10-30 by #667's definition and
  hashed (`WIDE668`, sha256 `5ce9dbf9…`). That is #667's 67 less SwiftLint (now a decision subject) and less
  `Hudson_ProSwiftUI_1_1` and `IdempotencySpike`, which have no remote and live on another machine, plus three
  clones made since: `muter` (upstream), `scip-swift` and `swift-mutation-testing`. `Sitrep` is now the
  joseph-cursio fork. **N_wide**.

**How the universe was restored.** On 2026-10-30 this machine had lost `swiftlang-swift`, 63 of #667's wide
directories and the whole graph-layout corpus. With the user's approval they were cloned again that day, shallow:
the wide repositories and `swiftlang-swift` (`4f0569be`) at their default branch's head, as #667 froze the wide
group by `origin` alone, and the 18 corpus repositories at #667's frozen revisions. The two directories with no
remote were not restored.

**The asserts.** The script exits non-zero with no population if any fails:

- the decision and unmet lists resolve to exactly §2's;
- SwiftUMLStudio is at `9ad7631` and SwiftLint at `ec4691d9e`, each with a clean tree, SwiftLint with its `origin`;
- the wide list's hash matches, and each wide directory exists with its `origin`;
- each layout clone is at its revision with a clean tree.

**Skipped files** are #669's (§2 there): hidden directories; `Tests`, `tests`, `test`, `validation-test`, `.build`,
`build`, `DerivedData`, `checkouts`, `Pods` and `Carthage`; any component ending in `Tests` or `UITests`; any
`fixtures` component below a subject's root, ignoring case; and any file whose code view or literal view does not
finish within 10 s, listed by path as `unparsable` (C35).

## 3. Controls for the census pass, asserted before any subject is read

`xml_emitter_census.py --self-test` runs **318 checks** with no subject and no compiler, and joins
`make measurement-selftest`. `run` refuses to report when any fails. They are in five sets:

- **C1–C39**, the first draft's controls, one or more per rule. The witness's sources are embedded as excerpts of
  `9ad7631` (C1–C5) and `e36da59` (C6), each line verbatim apart from elided lines (two of C5's `renderMessage`
  lines are re-indented from 12 to 8 spaces where the `if`/`else` around them was elided, which changes no cue); §10
  records that the real files give the cues C1–C5 expect.
- **X1–X33** (there is no X22 or X30), added after the first review round (§10): one or more per rule that the round's rule-break audit found
  no control caught, and per shape its parser attack found misread.
- **X34–X40 and D28–D30, and further checks under earlier labels**, added after the second review round (§10):
  one or more per rule its rule-break audit found no control caught, per shape its parser attack found misread, and
  per decision line no control read.
- **Further checks under X8–X10, X17, X28, X34, X35, X37, X40, D16, D19, D21, D23, D24, D27 and D29**, added after
  the third review round (§10): ROOT's bound, the nested stream, and one or more per rule its audit found no control
  caught.
- **D1–D30**, the decision controls: every §8 outcome and its boundary for both laws, each law reading its own kill
  summary, the merges, `join`'s refusals and unions, the judge files, `usable`, the sensitivity sums and their
  rounding, the beside figures and the flag line, the caps and the seeded sample, R2's missed cues, calibration.

| # | snippet or rule | expected |
|---|---|---|
| C1 | `ComponentSVGRenderer+SVG.swift` at `9ad7631`: `renderSVG` | candidate; OPEN-HOP through `svgHeader`; ROOT `svg`; CLOSE; GATED; IDDEF through the computed property `arrowMarkerDefs`; GATED2; REF through `edgeSVGLine` |
| C1′ | C1 with `lines.append(arrowMarkerDefs)` removed | no IDDEF; GATED; not GATED2 |
| C2 | the same file: `svgHeader(width:height:)` | candidate; OPEN-BODY; no CLOSE; not GATED |
| C3 | `SVGRenderer.swift` at `9ad7631`: `render(_:)` | OPEN-BODY; CLOSE (`"\n</svg>"` in `svg +=`); GATED; IDDEF through `arrowMarkers()`; GATED2; REF through `renderEdge` |
| C4 | `ActivitySVGRenderer.swift` at `9ad7631`: `renderFromLayout` and `render(graph:)` | the first GATED and GATED2, IDDEF in its own body, no REF (its references are two hops away); the second no candidate |
| C5 | `SequenceSVGRenderer.swift` at `9ad7631`: `renderFromLayout` | GATED; GATED2; REF through `renderMessage` |
| C6 | `SVGRenderer.swift` at `e36da59`: `render(_:)`, with `renderNode`'s `<!-- … -->`; and C3, whose `renderNode` no longer writes it | GATED; COMMENT; C3 no COMMENT |
| C7 | a report built as `["<?xml version=\"1.0\"?>", "<checkstyle version=\"4.3\">", …, "</checkstyle>"].joined()` | XMLDECL; ROOT `checkstyle` from the next literal; CLOSE; GATED; not GATED2 |
| C8 | `text.hasPrefix("<?xml")`, `data.starts(with: "<?xml".utf8)` in a `-> String` | candidate; no OPEN; not GATED |
| C9 | `svg.replacingOccurrences(of: "</svg>", with: extra)` | the `of:` literal is a search key; no CLOSE |
| C10 | `"<!DOCTYPE html><html><body><svg xmlns=…>…</svg></body></html>"` | HTML; not GATED |
| C11 | a synthetic emitter with `throws`; with `async`; `mutating`; returning `String?`; returning `Data`; returning `[String]` | not GATED, each by its own cue |
| C12 | a synthetic emitter whose body reads `FileManager.default.currentDirectoryPath`; one whose hop reads `Date()`; each of the 20 tokens alone | PURE false; not GATED; that token only, each |
| C13 | `var svg: String { "<svg xmlns=\"…\">" + body + "</svg>" }`, and one with `get { … }` | units found; GATED |
| C14 | a stored property with a `didSet` observer, and a `set` block, holding `<svg xmlns=…>` | no unit |
| C15 | `xmlns` and `</svg>` only inside a comment and a doc comment | no cue, no candidate |
| C16 | a raw string `#"<svg xmlns="http://www.w3.org/2000/svg">"#` | XMLNS |
| C17 | a multi-line literal whose `<svg` and `xmlns=` are on two lines joined by a trailing `\` | XMLNS |
| C18 | OPEN `<svg xmlns=…>` with only `"</g>"` in the body | no CLOSE |
| C19 | `<?xml…?>` and `<rss version="2.0">` in one literal, `</rss>` in another | ROOT `rss`; CLOSE |
| C20 | a hop through another type's member, `Other.header()` | no OPEN-HOP |
| C21 | body → `a()` → `b()`, with `b` holding the `xmlns` tag | no OPEN-HOP: one level only |
| C22 | `static let defs = "<marker id=\"m\"/>"` read as `Self.defs` | IDDEF through a stored property |
| C23 | `data-id="x"`, `gid="x"`, `id = "x"` in Swift code | no IDDEF |
| C24 | `href="#a"`, `xlink:href='#a'`, `url(#a)` | REF, each |
| C25 | the opening literal in an extension of the owner in another file; in `extension Outer.Inner` | OPEN-HOP: same type across files, each |
| C26 | two top-level functions, the hop in the same file; and in another file | OPEN-HOP; none |
| C27 | `<?xml version="1.0"?><plist version="1.0">` … `</plist>` | ROOT `plist`; GATED |
| C28 | `"<!-- \(label) -->"` | COMMENT |
| C29 | a copy in the decision, layout and wide groups | one row, at the decision copy |
| C30 | `case "<?xml":`; `"</svg>" == tail`; `.contains("xmlns")` | no OPEN or CLOSE from them (each rule alone: X2) |
| C31 | `"<\(tag) xmlns=\"…\">"` | no XMLNS |
| C32 | `"<svg width=\"1\">…</svg>"` with no `xmlns` and no `<?xml` | candidate; no OPEN; not GATED |
| C33 | a body holding `try?` inside a non-throwing function | NOTHROW |
| C34 | `<?xml` in the body, the root start tag only in a hop the body calls after it | ROOT from the hop |
| C35 | a view that does not finish in time; a comment that never closes; an unterminated `\u{` | unparsable; parsable; parsable |
| C36 | a `func` in a doc comment above the signature | the body is the real one |
| C37 | a hop whose result is an `Int` (`"<svg xmlns=…>".count`) | no OPEN-HOP |
| C38 | `throws` inside a parameter's closure type, `(_ visit: () throws -> Void)` | NOTHROW; GATED |
| C39 | a local `let header` that shadows a member `header` | not a hop; no OPEN |
| X1 | `data.starts(with: Array("<?xml".utf8))`, calibration row 5's shape | a nested argument is still a search key; no OPEN |
| X2 | `s == "</svg>"`, `"</svg>" == s`, `!=`, `~=` beside an opener; `.contains(<svg xmlns…>)`; a `case` label; `replacing("</svg>", with:)`; `replacing(_:with: "</svg>")`; a literal after a `case` pattern's colon | each rule alone: no CLOSE, no OPEN, no OPEN, no CLOSE, CLOSE; GATED |
| X3–X4 | a hop reference used as a search key; a hop whose opener literal is a search key inside it | no OPEN, each |
| X5 | quoted markers in a line and a block comment; a quoted opener only in a comment | no CLOSE; no candidate |
| X6–X7 | a stored header wrapped after `=`, after `+`, continued on a `+` line and on a `.` line, over bracketed lines as `[String]`, typed `String`; untyped and literal-initialised, with and without a trailing comment, and the X17 shape commented; a commented doctype; a file-scope header; `"…".count` | GATED (ROOT checkstyle or svg), each; HTML, not GATED; GATED; no OPEN |
| X8 | `o.header()` and `Other.header()` beside an own `header()` that holds the opener; `doc.header` on a model value; `self.header`, `Emitter.header`, `Self.header`; a `Self.` read more than 256 characters into the body; a `Self` receiver more than 256 blank characters before its dot | no OPEN; no OPEN; GATED, each; ROOT checkstyle, GATED; GATED |
| X9 | a bare read shadowed by a parameter, a `for` variable, a `for` tuple's second name, a closure parameter (one, two, parenthesised, typed, with a result type, after a capture list or an attribute, with a type holding parentheses), a tuple binding, a local declared later in a loop; `let header = Self.header`; a ternary's first branch | no OPEN, each; GATED; GATED with ROOT plist |
| X10–X13 | an argument label named like a member, after `(`, `,` and `[`, and on its own line; an own-name overload; every overload of a name; `== Self.header` | no OPEN, each; GATED; GATED; no OPEN |
| X14–X16 | Apple's plist doctype; an end tag before the root; xmlns after a placeholder, `xmlns:atom`, `data-xmlns`, `xmlnsx`, `<div><svg xmlns>`; a later xmlns tag; `<?xml-stylesheet` after the tag; a later body tag; two openers | ROOT plist; ROOT root; GATED, GATED, none, none, no OPEN; ROOT rss; ROOT svg; ROOT feed; ROOT svg |
| X17–X18 | `<?xml` in a hop with the root in its next literal; a search-key tag carrying `xmlns` in a later hop, and among the opening hop's own later literals; a `<nopath>` placeholder before the root | ROOT checkstyle, a candidate by its end tag; ROOT root, each; ROOT checkstyle |
| X19 | the close only in a footer hop; `</svg >`; `</svgs>` | CLOSE-HOP, not GATED; GATED; no CLOSE |
| X20 | HTML by a doctype alone, upper case, XHTML, a hop; `"<html"` only as a search key; XHTML's `gated_without_pure` | HTML each; no HTML, GATED; false |
| X21, X23 | `id='m'`; an unquoted `id=`; `id=` at a literal's start; a line break and a tab before `id=`; an id with no close; an id in a non-SVG document | IDDEF; none; GATED2; GATED2; not GATED2; not GATED2 |
| X24–X26 | an observer block (`didSet`, `willSet`); a function-local computed property; a file-scope one; a function-local `let` named like a member; `get throws`, `get async`, `mutating get`; `Swift.String`, `rethrows`, an `async` closure parameter | no unit, each; no unit; GATED; no OPEN; not GATED, each; GATED, NOTHROW false, GATED |
| X27 | `\n`, `\t`, `\u{41}`; a raw string ending in `\`; `\(x)` and `\#(y)` in a raw string; a regex literal holding a quote | each resolves as §1.1 says |
| X28–X29 | `print(…, to: &out)`; `print(header(), to: &out)`; a subscript and a closure in print's own arguments; a plain `print(…)`; one followed by a later `to:` label; a `to:` nested in a plain print's argument; `Date()` inside a `print(…, to:)` argument; a hop returning `[String]`, and each of `[Swift.String]`, `Array<String>`, `Array<Swift.String>`, `Swift.String` | PURE; PURE, GATED; PURE, GATED; not PURE, each; GATED and GATED2; OPEN-HOP, each |
| X31 | a nested literal holding `\"` inside an interpolation's closure; a `//` URL in one; `gated_without_pure` on C12 and C2 | the unit is whole, GATED; the next member keeps its owner; yes and no |
| X32–X33 | units differing only in literals, or only in interpolation code; an HTML page and a GATED emitter of one name and shape; a verbatim computed property in two repositories; a copy re-indented and nested deeper, a re-indented multi-line literal, one body under two owners, and over two parameter types; the kept copy's order | two rows, two rows, two rows with the GATED one kept; one row; one row, each; decision first, then repository (toplevel), then subject name and path |
| X34 | a bracketed URL in a leading XML comment; a tag named in a comment after `<?xml`; a CDATA section holding a tag; `</svg>` only inside a comment; a comment spanning lines; a comment, and a CDATA section, left open to their literal's end | ROOT svg, GATED; ROOT checkstyle, GATED, each; no CLOSE; ROOT checkstyle, GATED, each |
| X35 | the declaration in a hop called before the body literal that holds the root; the same hop interpolated into that literal, as a property and as a call; a String hop interpolated inside the opening tag before its `xmlns`; a declaration hop interpolated before the body's svg tag; a header hop inside a ternary's nested literal, and a declaration written as one; a header hop after other text in a multi-line literal, before a checkstyle root and before an svg tag; a marker after a cut; a declaration in the body with the root's tag in an interpolated hop and a child after it, plain, with an id, and with the close only in another hop; a hop inside the declaration | OPEN-HOP, ROOT testsuites, GATED, each; OPEN-BODY, ROOT svg, GATED; OPEN-HOP, ROOT svg, GATED; ROOT testsuites, ROOT plist, GATED; ROOT checkstyle, GATED; OPEN-HOP not OPEN-BODY, ROOT svg; OPEN-HOP, ROOT report; ROOT svg, GATED; GATED2; ROOT root, CLOSE-HOP, not GATED; ROOT feed, GATED |
| X36 | `import struct Foundation.Date` above a type | its computed property keeps its owner: IDDEF through it, GATED2 |
| X37 | X17's source under the prefilter `run` uses; markers spelled with `\u{…}`, and with a raw string's `\#u{…}`; a 4,000-case icon catalog's `switch`; a closed `{…}` and a closed `[…]` inside a search call before the opener | the same rows; a candidate, GATED, each; GATED in under 10 s; OPEN, ROOT svg, CLOSE, GATED, each |
| X38 | each of §1.2's 22 search calls by its name alone, unlabelled; the list itself | OPEN, no CLOSE, each; §1.2's 22 |
| X39 | a split-literal declaration header whose root never closes; an `xmlns` tag after a `<div>` written in an earlier literal; a chart that builds its body before its opener | ROOT title, GATED; ROOT svg, GATED; ROOT svg, GATED (the first two are known false-positive classes, pinned) |
| X40 | a rendered packet row, and 17 judged rows and one unjudged written as packets | the owner's members whole, no cue, gate or group shown; three packets, 17 in the index beside them, no cue, and `sizes.json` beside them reading 8, 8, 1 |
| D1–D30 | §8's outcomes for each law at every boundary, each law reading its own kill summary and its own hand line, `join` (C's extra record's flags kept), the judge files, `usable`, the merges, the sensitivity sums and their rounding, the beside figures and the flag line, the H line with no summary, Law 2's list by subject, §4.1's caps and seeded sample (layout judged in full), R2, calibration against §4.2's table and the judge workflow's, a calibration record left unanswered | see `decision_controls()`, `round_two_decisions()` and `round_three_decisions()` |

**The rule-break audit.** Each rule of §1 (and §4.1, §4.5, §8 as coded) was switched off in turn, one break per
copy, and the controls run after each; every break must make at least one control fail, or be shown to change no
output, or to change one only on contrived input, each such break listed in §10 with its reason. §10 records the
three review rounds' audits.

## 4. The hand-check

### 4.1 What is judged

Every decision, unmet and layout candidate is judged, however many layout candidates there are (D26). If there are
more than 300 of them, the script stops, and this scope gets a dated amendment before any packet is written; that is
a stop, not a sample (D25).

Wide candidates are judged in full up to 60. Above that, a sample of 60 is drawn by `random.Random(20261030)` over
the rows sorted by id (D26 pins the draw). N_wide is then estimated over the judged share and reported with its
sample size.

### 4.2 Calibration, before any packet

Two judges first classify the ten rows of `fixtures/xml-emitter-law/calibration.md`, in a packet's own format.

- Rows 1 and 2 are SwiftUMLStudio's at `9ad7631`, rendered by `xml_emitter_census.py render`. The judges may read
  that repository, as they may any row's.
- Row 3 is SwiftUMLStudio's `SVGRenderer.render` at `e36da59`, text only, with the helpers it calls and its input
  types' declarations.
- Rows 4–10 are synthetic; row 6 shows its `Issue` type's declaration.

The expected answers are in the script (`xml_emitter_census.CALIBRATION`, which D23 holds to this table), in the
judge workflow (`EXPECTED`) and in this table, and D16 and D23 hold the three to one another; the judges may read
none of them, and the brief's record format names fields, never values. Each judge must match on every field listed
(the sentinel is free text and never matched), with each label exactly once and each record usable (a DOCUMENT record
answers every flag): a label missing, repeated or unusable is a miss, in the workflow's gate as in `calibrate`. A
miss stops the arm until the brief is amended, by a dated amendment, and calibration runs again. A calibration agent
that returns nothing (an error, not an answer) is asked again, once, as a fresh agent; the second answer stands.

For rows 1 and 2 the judges may read, in the repository they name, only the row's own file and the files that
declare the members and types it references; rows 3 to 10 are text only. At `9ad7631` the file at row 3's path holds
a comment that states row 3's answer, so this keeps a pass on row 3 evidence about the brief's comment rule.

| row | expected |
|---|---|
| 1. `ComponentSVGRenderer.renderSVG` at `9ad7631` | DOCUMENT, EXPRESSIBLE, law2 OWES, *body disagrees* false, *refs dangle* false |
| 2. `ComponentSVGRenderer.svgHeader` at `9ad7631` | FRAGMENT |
| 3. `SVGRenderer.render` at `e36da59`, with `renderNode`'s label comment | DOCUMENT, EXPRESSIBLE, *body disagrees* true (a node label holding `--`) |
| 4. an HTML page with an inline `<svg>` | HTML |
| 5. a function that reports whether data `starts(with: Array("<?xml".utf8))` | NOT-EMITTER |
| 6. a Checkstyle-style report that escapes every value | DOCUMENT, EXPRESSIBLE, law2 NOT-SVG, *body disagrees* false |
| 7. an SVG wrapper whose `inner` parameter is documented as SVG markup and interpolated raw | DOCUMENT, not EXPRESSIBLE |
| 8. an inline SVG icon whose `<use href="#icon-x"/>` names a sprite the host page defines | DOCUMENT (one complete root element), law2 EXTERNAL |
| 9. an SVG document with no references | DOCUMENT, law2 VACUOUS |
| 10. an RSS feed builder that interpolates its plain-text `title` without escaping | DOCUMENT, EXPRESSIBLE, *body disagrees* true |

### 4.3 Packets and judges

**Packets.** `xml_emitter_census.py packets` writes the judged rows in a seeded order (`random.Random(20261030)`
over the rows sorted by id), in packets of at most eight, into a directory that must be empty. The label index is
written beside that directory, not in it.

**Judges.** Two judges, **A** and **B**, judge each packet independently, run by
`fixtures/xml-emitter-law/judge-workflow.js`. Each is a subagent given only the brief
(`fixtures/xml-emitter-law/judge-brief.md`), its packet and its output instructions. **C**, a third judge, decides a
row when A and B disagree on the verdict, or, for DOCUMENT, on EXPRESSIBLE or law2, and a row where A's or B's record
is present but not usable. On a DOCUMENT row, each flag (*ambient*, *body disagrees*, *refs dangle*) is raised when any
judge whose record is a usable DOCUMENT raises it, C's record included, even a record C gave for a row A and B agreed
on, which decides nothing; every witness is kept (D17, D19).

**From the workflow to `join`.** The workflow takes each packet's row count (`args.sizes`: the `sizes.json` that
`packets` writes beside the packet directory, and prints). A judge whose records for a packet do not name each of its
labels exactly once and nothing else (for C, each row it was given) is asked again, once, as a fresh agent; the
second answer stands either way, and the workflow lists every retry. It returns each judge's raw records, never a
label map. `xml_emitter_census.py verdicts` then writes `A.json`, `B.json` and `C.json`, each the concatenation over
packets in order of that judge's raw records (`judged[i].records`), after re-checking both judges' calibration
records with `calibrate`; it refuses a stopped run and a packet whose judging returned nothing. So a repeat or a gap
that survives the retry reaches `join`, which refuses it (D29). **Any refusal by `verdicts` or `join` stops the arm
until a dated amendment**; none is worked around by hand.

**Refusals.** `join` refuses an unknown label, a label repeated in the index **or in one judge's records**, a
missing A or B record, and a disagreement C has not judged (D18, D20). `decide` refuses unless every judged row has
exactly one judgement (D14, D15). A record whose verdict is unknown is UNDETERMINED, and so is a DOCUMENT record
that leaves a flag unanswered or names an unknown law2 (D16).

**What a judge sees:** the unit's full text and doc comment; its owner's name, kind and doc; the owner's other
members in its repository, as signatures without bodies, with their doc comments, the row's own file first and at
most 200 lines; the file path and the repository's name and path; the same-type members it references, each with
its text cut at 120 lines, and the same-type members that reference it, by name; and the brief.

**What a judge does not see:** the cues, GATED, GATED2, the group; this scope's predictions, §8's bars and
outcomes; any count; the other judge's verdict.

**What a judge may read.** The brief's rules say this in those words:

- **Allowed:** the packet, and, for context, source files under the row's own repository path.
- **Forbidden:** any `docs`, `scripts` or `fixtures` directory of this repository; any `.json` file; any other
  packet or judge output; and any search for a unit's name outside the row's own repository.
- **Required:** reading the row's whole file, and every same-type member it references, before answering
  EXPRESSIBLE, *ambient*, law2, *body disagrees* or *refs dangle*.

### 4.4 Verdicts

The brief's text is the definition. In short:

- **DOCUMENT.** On every input its contract admits, apart from a sentinel, it returns a complete XML document built
  as text: an optional prolog and exactly one root element. A result that is one complete root element is a
  DOCUMENT even when callers embed it in a larger page, unless that element is HTML's.
- **FRAGMENT.** It returns markup meant to sit inside a larger document and that is not one complete root element:
  a start tag, a header, a `<defs>` block, several sibling elements.
- **HTML.** It returns an HTML page, or markup in HTML's vocabulary meant for one (`<div>`, `<p>`, `<span>`,
  `<br>`, a doctype), even if an SVG sits inside it and even when the markup would also parse as XML.
- **NOT-EMITTER.** Anything else: the XML text is a search key, a constant the unit does not return, a parser's or
  decoder's input, or a file written to disk. A unit that takes no input and reads no state that varies returns one
  constant text, and is NOT-EMITTER (constant): a law over it is one example, not a property. #668 puts the
  constant SVGs in swift-docc and muter outside the emitters for this reason.
- **UNDETERMINED.**

For DOCUMENT, the judge also records:

- **EXPRESSIBLE.** A test can draw every input from what the module offers (internal API through `@testable
  import` included), call the unit, and state the law over those inputs, whether or not the body satisfies it. It is
  false when an input cannot be built, when the state it reads cannot be made fresh, or when an input's own contract
  requires well-formed markup (a fragment parameter: #668's item 5, "a fragment parameter is correct by contract").
- ***ambient*.** The result depends on state outside the unit's inputs and its owner's stored properties: the
  working directory, the clock, the environment, files, a random source, or other process-wide state, read directly
  or through a call into another type. This is what SEI would refute and PURE's token list cannot see (§1.2).
- **sentinel.** What a guard returns instead of a document, documented or not, or `none`. A sentinel is never a
  *body disagrees* witness.
- ***body disagrees*.** An input allowed by the contract on which the output is not well-formed XML. Give the input
  in `witness`. A crash or a trap is not *body disagrees*. Each such row is hand-checked, then run, and listed with
  its revision for upstream filing.
- **law2.** One of:
  - **OWES**: the root is `svg`, and the output's same-document references name ids the unit's own output defines;
  - **VACUOUS**: the root is `svg`, and the unit never writes a same-document reference;
  - **EXTERNAL**: the root is `svg`, and its references name ids defined outside the document by design;
  - **NOT-SVG**: the root is not `svg`.
- ***refs dangle*.** For OWES: an input allowed by the contract on which a reference names an id the output does
  not define. Give it in `witness`.

### 4.5 Counting

- **N1** counts the decision rows judged DOCUMENT and EXPRESSIBLE, as **merged groups**: copies merge as §1.3
  says, and an owing row also merges with an owing row of the same type (§1.2: same repository and owner, or the same
  file for top-level units) that it references or that references it, transitively, by name (D12). This is wider than
  #669's same-file merge: a renderer's convenience entry point often lives in another extension file.
- **N2** counts the same, restricted to rows whose law2 is OWES.
- A repository counts toward a bar only if it holds a merged group's first row. The **unmerged count**, reported
  beside each N, counts every owing decision row and its copies in the decision group (D21).

## 5. The kill arm

`scripts/xml_emitter_kill_arm.py`. It imports #667's mutant generator, watchdog, patching and outcome rules
(`layering_kill_arm.py`) and #669's watchdog rebinding pattern, and binds them to this subject, these laws, these
suites and these controls.

### 5.1 The subject

SwiftUMLStudio `9ad7631`, package `SwiftUMLBridge`, exported with `git archive` into this session's scratchpad
and never built in the user's checkout. The runner refuses a fresh report unless the export's `Sources/` hashes as
`git archive 9ad7631` writes it (`SOURCES_SHA256`, `6dfe3807…`), so a mutant left behind by a killed run can never
become the base.

It is built with Xcode's Swift, found by `xcrun --find swift`; the runner refuses to start unless `swift --version`
names **`swiftlang-6.4.2.1.9`**. Xcode updated itself to 27.2 (Swift 6.4.2) on this machine at 09:46 on 2026-10-30,
before §10's baseline was taken. #667's and #669's kill arms ran on `swiftlang-6.4.0.34.1`, so these counts are
not toolchain-matched to theirs.

### 5.2 The laws, prototyped by hand

`fixtures/xml-emitter-law/XMLEmitterLawTests.swift` is copied into the export's `SwiftUMLBridgeFrameworkTests`
target, never into SwiftUMLStudio itself. Its sha256 is recorded in the report. It holds two suites, so that a
detection is attributed to one law:

- **`XMLEmitterLaw1Tests`**, Law 1 on each of the four renderers: `ComponentSVGRenderer.renderSVG` (**P-C**),
  `SVGRenderer.render` (**P-S**), `ActivitySVGRenderer.renderFromLayout` (**P-A**) and
  `SequenceSVGRenderer.renderFromLayout` (**P-Q**). **The sentinel is decided from the input**: only `renderSVG`
  has a guard, which returns `""` for a layout with no components, and those draws are counted and not checked.
  On every other draw, `""` is a failure like any other malformed output, so the mutant that inverts the guard is
  caught (the review's finding, §10).
- **`XMLEmitterLaw2Tests`**, Law 2 on the same four (**R-C**, **R-S**, **R-A**, **R-Q**): each `url(#X)`,
  `href="#X"` and `xlink:href="#X"` in the output names an `id="X"` in the output. The same draws as Law 1, from the
  same seeds.

Each property runs 1,000 trials from a SplitMix64 generator with a fixed seed, and prints one summary line,
`XML-EMITTER-LAW <property> trials=… sentinel=… reach=… failures=…`. `sentinel` counts the draws the guard rejects;
`reach` counts the outputs that hold at least one reference. The first failure names the drawn input and the output,
and the runner keeps a detecting run's output from the first failing test's issue on (up to 20,000 characters), so
the counterexample §5.5 hand-checks is in the report; when that cut drops the output's end, its last 1,500
characters are kept too, where a crash's cause is printed.

**The draws.** Hand-written; a built template would compose `DerivationStrategist`'s generators instead.

- **Names that resolve.** Component names and dependency endpoints are drawn from one pool, `a`, `b`, `c` and `""`,
  so an edge renders whenever both ends name a drawn component. This is #668's item 3: "the robust route is a
  narrow member alphabet", not the one collision the recorded generator's reach rests on. Activity edges are drawn
  among node ids 0–4 over nodes 0–3, so some ends dangle and draw no edge. Sequence messages draw `fromX` and `toX`
  from three values, so self-calls occur.
- **Text the subject escapes.** Every text value these renderers write (labels, names, interfaces, titles,
  compartment items, notes, stereotypes) goes through `xmlEscaped`. So, as #668's item 5 asks, text is drawn half
  the time from letters and half the time from `a`, `<`, `>`, `&`, `"`, `'`, `-`, `]`, a space, U+0001 and U+FFFE.
  The last two are characters XML forbids, which `xmlEscaped`'s own doc promises to replace (#80).
- **Finite dimensions.** Coordinates are drawn from −10,000…10,000 and sizes and totals from 0…2,000, inside the
  range #668's item 6 found safe for every `Int(…)` conversion.
- **The sentinel.** About one component draw in five is empty.

### 5.3 The mutants

#667's generator's operators (`layering-law-census-scope.md` §5.3): arithmetic, relational, negate-conditional,
logical, boolean-literal, swap-ternary and remove-side-effects. Code is masked first, so comments and literals,
interpolations included, are never mutated. The generator reads `func` bodies only, so computed properties
(`arrowMarkerDefs`, `xmlEscaped`) carry no generated mutant.

**The mutated functions** are the bodies on the laws' call trees in five files:

- `Model/ComponentSVGRenderer+SVG.swift`: `renderSVG`, `svgHeader`, `edgeSVGLine`, `componentSVGLines`, `boxRect`,
  `textElement`, `edgePoint` and `format`: **42** mutants;
- `Emitters/SVGRenderer.swift`: `render`, `arrowMarkers`, `renderNode`, `renderCluster`, `moduleHue`,
  `renderEdge` and `fmt`: **31**;
- `Emitters/ActivitySVGRenderer.swift`: `renderFromLayout` and `fmt`: **1**;
- `Emitters/ActivitySVGRenderer+Shapes.swift`: every function: **37**;
- `Emitters/SequenceSVGRenderer.swift`: `renderFromLayout`, `renderParticipantBox`, `renderMessage`, `renderNote`
  and `fmt`: **14**.

That is **125 mutants**, the listing of §10; the runner refuses to start on any other count. Off the call trees,
and not run: the layout code of the Activity and Sequence files (`computeLayout`, `computeRows`, `forwardEdges`,
`computeColumns`, `collectParticipants`, `buildMessages`: 69 mutants), because the laws draw layouts; and three
helpers on the call trees but outside the five files, `ComponentLayout.component(named:)`,
`ActivityLayout.node(withId:)` and `ComponentSVGRenderer.stereotypeLabel(for:)`, with 2 mutants between them, a
`==` → `!=` in each of the first two (`stereotypeLabel(for:)` has none), which change which edge renders but never a
marker's id.

**F5's five sites are among them.** `renderSVG`'s `lines.append(…)` statements are remove-side-effects mutants:
the root start tag, `arrowMarkerDefs`, an edge, a component's lines and `"</svg>"`. The `svg += …` renderers
carry no removal mutant, because the generator removes call statements only, as #668 suspected.

**Only three viable generated mutants can make the output malformed**, all in `renderSVG`: the guard inverted (now
caught as `""`), the root start tag removed, and `"</svg>"` removed. The generator never mutates literal text, so it
cannot reach what Law 1 is for: escaping, a comment's contents, a frame literal's text. §7 and §8 say what follows.

**Hand mutants H1–H6, reported apart and never in the decisive count.** swift-mutation-testing generates no mutant
in escaping code (#668, and the *Measured* section of `laws-from-mutation-survivors.md`), and #667's generator
never reaches `xmlEscaped`, a computed property. H1–H5 each remove one arm of `xmlEscaped`'s `switch`, so that
scalar falls to `default` and is appended raw. **H6 is RC7's patch**, #56's label comment given back to
`renderNode`, the defect Law 1 found.

| # | change | what the laws can see |
|---|---|---|
| H1 | `case "&"` removed | a raw `&` |
| H2 | `case "<"` removed | a raw `<` |
| H3 | `case ">"` removed | a raw `>`, malformed only as `]]>` |
| H4 | `case "\""` removed | a raw `"` in text content, which is legal |
| H5 | the C0 range removed | a raw U+0001 |
| H6 | `renderNode`'s `<!-- label -->` restored | a `--` in a comment |

### 5.4 Each mutant

This is #669's §5.4, with these suites:

- **Law 1:** `swift test --skip-build --filter '\.XMLEmitterLaw1Tests/'`, with a 120 s limit.
- **Law 2:** `--filter '\.XMLEmitterLaw2Tests/'`, with a 120 s limit.
- **The full suite:** `--filter '^SwiftUMLBridgeFrameworkTests\.' --skip '\.XMLEmitterLaw[12]Tests/'`, with a 300 s
  limit.
- **The reduced suite:** the full suite less **every test this law family's findings produced**, by provenance:
  - every test SwiftUMLStudio's PR #79 (for #56) and PR #86 (for #80) added, by suite and function, read from their
    merge commits' diffs: 6 from #79 (`DepsSVGTests.doubleHyphenModuleNameIsWellFormed`, three in
    `SVGRendererWellFormednessTests`, one each in `ClassDiagramGeneratorTests` and `DependencyGraphGeneratorTests`)
    and 17 from #86 (one in each of the four `*WellFormednessTests` suites and two more in the Activity one, seven
    `StringExtensionsTests` that start `xmlEscaped`, one each in `ClassDiagramGeneratorTests` and
    `DependencyGraphGeneratorTests`, and the two it created `ActivityGraphBuilderCompactTextTests` with);
  - any other test whose body calls `WellFormedXML`, the helper PR #79 created (none at `9ad7631`).

  **Not whole suites**, unlike #669: `ActivityGraphBuilderCompactTextTests` has since gained eight tests for
  SwiftUMLStudio#63, which call no renderer, and `SVGRendererTests.noClustersNoClusterBox` is an older test PR #79
  renamed and re-asserted, not one it added. Both stay in the reduced suite, which errs against the law.

  This is #669's rule by provenance: the full suite holds the law's own examples, so scored against them the law
  gets no credit for its own findings. The runner reads the derived tests and their display titles from the export,
  and refuses to start unless there are **23**. A failed test is matched to a derived one by its title, with or
  without its argument. The reduced suite is read off the full run as #669's is.

The outcome rules are #667's: ASSERTION, CRASH, TIMEOUT and MEMORY (6 GiB) are detections, and anything else is
SURVIVED. So are the watchdog (with #669's rebinding, so the runner never kills itself) and the restore after every
mutant. **The flake rule** is #667's with changes from the reviews: when either law detected the mutant (#667's
condition; a suite-only detection is not re-run), a suite detection by ASSERTION is run once more and stands only if
the rerun detects too. Then only the failures both runs name are kept, so a coincident flake in a non-derived test
cannot decide the reduced suite's read-off; and two assertion runs that name no failure in common are a flake each
time, so the suite SURVIVED, marked `disjoint`. A rerun that crashes or times out stands. A failed test is named by its
title, or, for an untitled one, by its function name with its parentheses, as the derived-test reader titles it. Each
law is run whatever the other did.

### 5.5 Controls for the runner

| # | control | expected |
|---|---|---|
| RC1 | the unmutated export | builds; all eight properties `failures=0`; each R-property's `reach` above 0; the full suite passes at least 1,839 tests, and did not fail twice on different tests; the reduced suite, run under the flake rule, passes exactly 23 fewer |
| RC2 | `lines.append(arrowMarkerDefs)` removed from `renderSVG` (F5's site L18) | Law 2 detects it by ASSERTION, R-C failing; Law 1 survives |
| RC3 | `svg += "\n</svg>"` removed from `SVGRenderer.render`, a removal the generator does not make | Law 1 detects it by ASSERTION, P-S failing |
| RC4 | a statement `let _: Int = "x"` in `renderSVG` | UNVIABLE |
| RC5 | after the run | the export's `Sources/` and `Tests/` hash as before the run |
| RC6 | both laws run twice on the unmutated export | the same eight summary lines, compared as a set |
| RC7 | `SVGRenderer.renderNode`'s `<g>` opener given back the label comment it had at `e36da59` (#56's defect) | Law 1 detects it by ASSERTION, P-S failing |
| RC8 | `renderSVG` given a loop that never ends | Law 1 TIMEOUT within its limit plus 45 s, and nothing naming the export survives the 5 s grace |

RC1 and RC6 run first, then RC2–RC4, RC7 and RC8. The runner's self-test (26 checks) pins the read-off, the flake
rule's intersection, its empty one and a crashing rerun, Law 2 alone confirming a suite detection, the hand mutants'
count (by ASSERTION only, against the reduced suite), one cell per file for a function name in two files, a decisive
kill's `disjoint` reduced suite shown, the counterexample kept, and the failed-test names read. If any control fails, the runner writes no summary. RC5 is
checked after the last mutant and the hand mutants, and a failure voids the summary. The suites' outcomes on the
controls are recorded, not asserted, except RC1's full-suite and reduced-suite passes. A run resumes from its report only when the law's
file and the source tree hash as the report recorded.

**If RC1 fails**, the first counterexample is hand-checked. A law or generator error is fixed by a dated amendment
before any mutant runs. A real defect in SwiftUMLStudio is listed with its revision and offered to the user for
filing upstream; the arm is then scored against a hand-fixed body, in a fresh report, and the doc says so. That
also needs a dated amendment: the runner refuses any `Sources/` that does not hash to `6dfe3807…`, so the amendment
re-pins the hash, and the 125-mutant count too if the fix touches the five files. UNMEASURED (kills) applies only
when neither is done. An RC1 failure that leaves no counterexample (a test count off, or a suite failure that
repeats only under load) is diagnosed and answered with a fresh report, never scored, and the doc says so.

### 5.6 What is counted

For each law, over the viable mutants: what the law detects, what the full suite detects, and what the reduced
suite detects. **The decisive count** is law-only detections **by ASSERTION** against the **reduced** suite, for
#667's reasons: a crash or a timeout is something any test with random inputs would catch, and the full suite holds
the law's own examples.

Reported beside it: the law-only count against the full suite; every mutant that survived both laws and the full
suite, read for equivalence; the suite-only count; each mechanism's count; each function's, by file and name
(`renderNode`, `renderEdge` and `renderFromLayout` each live in two files); for each law-only kill, whether its
reduced suite failed twice on different tests; for every suite kill by
a single failing test, which test; and the H-mutants' outcomes, apart, with **the decisive count with H1–H6
counted** (a hand mutant counts when a law detects it by ASSERTION and the reduced suite does not).

## 6. Recall probes

Reported beside the census; none enters N.

- **R1.** The unmet, layout and wide groups (§2).
- **R2.** The owing groups of the decision universe, EXPRESSIBLE or not, with no GATED member (Law 1) or no GATED2
  member (Law 2), each with its EXPRESSIBLE flag and the cues its first row missed: any of STRING, NOTHROW, SYNC,
  NONMUTATING, PURE, OPEN, CLOSE and HTML; CLOSE-HOP when the close is only in a hop; and, for Law 2, ROOT≠svg and
  ¬IDDEF (D27). These are what a gate misses that the candidate rule reached. `decide` prints them, and the GATED
  rows that do not owe their law.
- **R3.** #668's named sites, by repository, owner and name: `renderSVG`, `SVGRenderer.render`, both
  `renderFromLayout`s, `render(graph:)`, `render(traversedEdges:entryType:entryMethod:)`, `generateReport` (each
  SwiftLint reporter that has one), swift-package-manager's `generate(at:detailedFailureMessage:)` and
  `generateResourceInfoPlist`, and SwiftFormat's `XMLReporter.write`, #668's near miss. Each is reported as a
  candidate with its cues, as read but no candidate with its cues, or as **not read**: no unit of that name in the
  files §2 reads, or a repository outside §2 (SwiftFormat: #666's upstream clone is not part of this universe).
- **R4.** #668's local grep, re-taken over §2's files: the non-test Swift files whose literals hold `<?xml`,
  `<svg`, `</svg>`, `<plist` or `</plist>`, by subject. #668's grep read a different universe (it included packages
  under `.build/checkouts`, which §2 skips), so this is a comparison, not a check.
- **R5. GitHub code search**, #668's "size Law 1 with GitHub code search … and report the result as a grep
  estimate". Each query is run once, through `gh api search/code`, and reported with its `total_count`, the date,
  and the ten repositories with the most matching files among the first 100 results:

  | # | query |
  |---|---|
  | Q1 | `"<?xml version" language:Swift` |
  | Q2 | `"xmlns=" "</svg>" language:Swift` |
  | Q3 | `"url(#" language:Swift` |
  | Q4 | `"<!DOCTYPE html" language:Swift` |
  | Q5 | `"</checkstyle>" language:Swift` |
  | Q6 | `"</testsuites>" language:Swift` |

  GitHub counts files, test files included, case-insensitively (Q3 also counts `URL(#`), and its counts are
  approximate. The endpoint matches quoted punctuation literally: a review skeptic measured `"url(#"` against bare
  `url` on another language, 9,872 files against 3,624,960 (§10). A count is an estimate of files that hold the
  text, not of functions that owe a law.

## 7. Predictions, frozen

Each says whether it is blind and, if not, what informed it.

1. **Law 1's population clears the bar, and rests on SwiftLint: N1 between 5 and 8 over 2 repositories**, and
   *N without SwiftLint* does not clear. SwiftUMLStudio's four renderers are four groups (`render(graph:)` and
   `render(traversedEdges:…)` hold no literal and are not candidates). SwiftLint's `CheckstyleReporter` and
   `JUnitReporter` are two more. *Partly blind:* SwiftLint's reporters were not opened; their shapes come from
   #668's text.
2. **Law 1's gate precision is at least 70%.** *Partly blind:* the gate's controls were written from the witness.
3. **Law 1's decisive count is 0, so Law 1 is DECLINE (kills).** Only three viable generated mutants can make the
   output malformed (§5.3). The root start tag and `"</svg>"` are both asserted by
   `ComponentSVGRendererSVGTests.basicShape`, outside the derived tests, and the inverted guard's `""` fails
   `escapesSpecialCharacters`, which renders a non-empty model. *Not blind:* reasoned from the listing, #668's
   table and the review.
4. **Law 2 is DECLINE (population: a single subject): N2 = 4 over 1 repository.** *Partly blind:* #668's grep found
   `url(#` in SwiftUMLStudio only.
5. **Law 2's decisive count is 1 or 2**: `lines.append(arrowMarkerDefs)` removed (RC2's site, among the generated
   mutants), and perhaps `!markerId.isEmpty` negated in `SVGRenderer.renderEdge`, which writes `url(#)`. *Not
   blind:* reasoned from the listing.
6. **RC1 holds, and each R-property's reach is within 100 of a model of the draws**: R-C about 300, R-S 600, R-A
   350 and R-Q 730 of 1,000 (§10). P-C's sentinel count is about 200. *Not blind:* computed from the draw
   distributions, never from a run of the laws.
7. **RC7 holds**: the law finds #56's defect when it is put back. *Not blind.*
8. **No decision row is flagged *body disagrees* or *refs dangle*.** *Partly blind:* the witness's fixes are read;
   SwiftLint's escaping is #668's description.
9. **Law 1 detects H1, H2, H3 (a draw holds `]]>`), H5 and H6; H4 survives both laws.** The reduced suite detects
   H1, H2 and H3 (`escapesSpecialCharacters` pins `A<B>C` and `Foo&Bar`) but not H5, whose tests are all derived,
   nor H6. So the decisive count with H1–H6 counted is 2 for Law 1, and §8's first-paragraph caveat applies. *Not
   blind* for H1–H5; H6's reduced-suite outcome is *partly blind*: which non-derived tests assert a node's exact
   text was not checked.
10. **R4 finds every file #668 lists as a `String`-returning emitter** (SwiftUMLStudio's four renderer files and
    SwiftLint's reporters). *Partly blind.*
11. **Q4 (HTML) counts more files than Q2 (standalone SVG).** *Blind* to Swift on GitHub; #668's local grep found
    HTML the commoner shape.

## 8. The decision, fixed now

The figures, for each law:

- **N**: §4.5's merged groups in the decision universe.
- **N_gated**: those groups with a GATED member (Law 1) or a GATED2 member (Law 2).
- **Gate precision**: over the judged decision candidates that are GATED, the share judged DOCUMENT, EXPRESSIBLE or
  not (Law 1); over those that are GATED2, the share judged DOCUMENT with law2 OWES (Law 2). Every gated row that
  does not owe its law is listed.
- **The decisive count**: §5.6, for that law.

Reported beside them, none entering the decision: the unmerged count (decision rows and their decision copies,
EXPRESSIBLE); N without EXPRESSIBLE; N_unmet, N_layout and N_wide (with its judged and total counts and its
estimate), each also without EXPRESSIBLE, N_wide's estimate included; N_undetermined; the law-only count against the
full suite; each hand mutant's outcome under its law, the reduced suite and the full suite; the unparsable files
dropped; the gate's precision without PURE; R2; and, for Law 2, every subject in any group that holds an owing SVG
emitter or a copy of one.

The bar is **at least 5 across at least 2 repositories**, as #667 and #669 used it.

**Law 1's outcome is the first that applies:**

1. **DECLINE (population)**: N1 < 5, or N1 spans fewer than 2 repositories.
2. **DECLINE (signal)**: N1_gated < 5, or it spans fewer than 2 repositories.
3. **DECLINE (gate precision)**: Law 1's gate precision < 70%.
4. **UNMEASURED (kills)**: a runner control fails, RC5 fails, the run did not finish every planned mutant and hand
   mutant, or the summary has no decisive count. A run with no summary is never read as zero kills.
5. **DECLINE (kills)**: Law 1's decisive count is 0.
6. **BUILD**.

**Law 2's outcome is the first that applies:**

1. **DECLINE (population: a single subject)**: N2's groups span exactly one repository. This is #668's own
   condition: "Build it only if the search finds a second emitter of same-document references. Otherwise record a
   single-subject decline." The search it counts is this census's decision universe, as #667's and #669's bars
   count; R5 judges no rows and cannot satisfy it, and owing SVG emitters elsewhere are printed beside.
2. **DECLINE (population)**: N2 < 5, or no repository at all (D2).
3. **DECLINE (signal)**, **DECLINE (gate precision)**, **UNMEASURED (kills)**, **DECLINE (kills)**, **BUILD**: as
   for Law 1, with N2, GATED2 and Law 2's decisive count.

`xml_emitter_census.py decide` computes both from the census, the judgements and the kill arm's report, and prints
each law's decision line first. **Every arm runs, and every arm is reported, under every outcome.**

**Sensitivity.** `decide` prints a `SENSITIVITY` line for each of these, for each law, with its count and
repositories and whether it clears its bar. The doc's first paragraph says so whenever a line crosses the bar the
decision turned on, in either direction:

- **N + N_unmet + N_layout + N_wide (its estimate, rounded by Python's `round`, half to even)**: a population
  decline rests on the universe's boundary;
- **N + N_undetermined**, each UNDETERMINED row a group of its own: it rests on unsettled verdicts;
- **N without EXPRESSIBLE**: it rests on the judges' reading of the inputs;
- **N without SwiftLint**: a population that clears rests on the subject #668 named, which #669's universe held in
  the wide group;
- **N_gated without rows judged ambient**: a signal that clears rests on PURE's blind spot, impurity inside another
  type's call;
- **the decisive count with H1–H6 counted**, against the kills bar (more than 0): a DECLINE (kills) rests on the
  generated operator set's blindness to literal text (escaping, a comment's contents, a frame literal), which is
  where Law 1's defects live.

**Disposition:**

- **If both laws DECLINE**, #668 closes as not planned once the user approves, with a result comment. Two reopen
  conditions are frozen now, and no other may be added after the run:
  - **Law 2**, #668's own: a repository not among those this census reports, with an owing SVG emitter; or a later
    census with at least 5 owing groups over at least 2 repositories.
  - **Law 1**, if its decline is on kills: a kill arm whose operators mutate literal text or computed properties, or
    a second subject's kill arm.
- **If either law is UNMEASURED or BUILD**, #668 stays open, and a build is a separate issue.

**Under every outcome:**

- the measurement doc, `xml-emitter-census.md`, is written in `measurements/`;
- both indexes get a row, and `laws-from-mutation-survivors.md` entry 1 gets a dated annotation;
- every row flagged *body disagrees* or *refs dangle* is hand-checked and run, then listed with its revision and
  offered for upstream filing.

## 9. What this does not answer

- **One subject for the kill arm.** The kill counts are SwiftUMLStudio's, against a suite that already holds Law 1's
  examples. They are not a rate.
- **The generated operators cannot reach Law 1's defects** (§5.3). The hand mutants show what a literal-text
  operator would; they are six, chosen by hand, and never a rate.
- **The census finds only what its cues reach.** It misses:
  - an emitter written as an initialiser, a subscript or a closure;
  - XML built through `XMLDocument`, `XMLElement` or a DOM library, which never shows a literal (and is
    well-formed by construction for everything but raw-string injection);
  - a root tag whose name is interpolated (C31);
  - an opening literal more than one hop away, or a close in a helper (CLOSE-HOP, reported by R2);
  - a reference more than one hop away (C4's REF);
  - a member read the body also declares as a local anywhere, even in another scope (shadowing is whole-body, X9).
- **The gate admits two shapes that do not owe Law 1** (X39): an `xmlns` tag written after a start tag in an earlier
  literal (an HTML fragment's inline icon, which the brief reads as HTML), and a split-literal declaration header
  whose root never closes. Each lowers the measured gate precision, by name, and neither reaches N_gated.
- **Two contrived shapes the stream misreads**: a literal that also holds a `\u{1}` escape, which the placeholder
  count cannot tell from an interpolation, so the literal is not cut; and `print(flag ? to : from)`, a local named
  `to` before a ternary's colon, read as `print(…, to:)`.
- **PURE is a text stand-in for SEI**, and flow a text stand-in for data flow. The judges read the whole body and
  record *ambient*; the gates do not see it. A `print(…, to:)` argument's tokens count, so an impure value printed
  into the report is seen, but a call into another type is not.
- **The universe was restored, not kept.** The wide and corpus clones were re-made on 2026-10-30, the wide group at
  its default branches' heads; `Hudson_ProSwiftUI_1_1` and `IdempotencySpike` are on another machine and unread.
- **Hand-written generators.** The prototype is not a template. Its escaped-text alphabet is what #668's item 4
  says the kit cannot draw for a struct member today; the kit change it names is not filed (#668: "only if step 0
  passes").
- **`FoundationXML` on Linux is unchecked**, as #668 says.
- **Mermaid and PlantUML marker balance** are out of scope, as #668 says.
- **A re-implemented tool, on a newer compiler.** The mutants are #667's operator set, comparable within this series
  only, and the build is Swift 6.4.2, not the 6.4.0 of #667's and #669's arms.

## 10. Disclosures before the freeze

**Read, beyond #668 itself:**

- SwiftUMLStudio#56 and #80: titles, states, and the pull requests that closed them. PR #79 and PR #86: titles,
  merge commits, file lists, and the `@Test` titles and function names their diffs add.
- At `9ad7631`:
  - `ComponentSVGRenderer+SVG.swift`, `SVGRenderer.swift`, `ActivitySVGRenderer.swift`,
    `ActivitySVGRenderer+Shapes.swift` and `SequenceSVGRenderer.swift`, in full; `ComponentSVGRenderer.swift`
    lines 1–80; `String+Extensions.swift` lines 1–80;
  - the layout model types: `LayoutGraph.swift`, `ComponentLayout.swift`, `ComponentModel.swift` lines 30–60,
    `ComponentKind.swift`, `ActivityGraph.swift` lines 1–80, `ActivityLayout.swift`, `SequenceLayout.swift`;
  - `Tests/…/EmitterTests/WellFormedXML.swift`, in full;
  - a grep of the package's tests for `url(#`, `#arrow` and `href`, and for files naming `WellFormedXML`;
  - a grep of the repository's non-test sources for `<svg`, `</svg>`, `<?xml` and `xmlns`, as file names.
- At `e36da59`: `SVGRenderer.swift` lines 1–140.
- The witness's `git log` head and its `origin/main`.
- SwiftLint's revision and clean status only. **Its reporters were not opened.**
- #666's, #667's and #669's scopes, scripts, briefs and judge workflows, whose parts this scope reuses.

**Run before the freeze, on the export only** (Swift 6.4.2, `swiftlang-6.4.2.1.9`):

- the build with the law's file in the test target: 28 s, warm package cache. **The law's file was compiled, never
  run**, before and after the review's sentinel fix;
- `swift test list`: 1,847 tests in `SwiftUMLBridgeFrameworkTests`, 8 of them the laws';
- the full suite with both law suites skipped: 1,839 tests passed in 12 s;
- `xml_emitter_kill_arm.py derived`: 23 derived tests, all added by PR #79 or #86; none is derived by the
  `WellFormedXML` rule alone. The reduced suite: 1,816 tests passed in 12 s. (The first draft's whole-suite rule gave
  32 and 1,807; the review moved it, §5.4.)
- `xml_emitter_kill_arm.py mutants`: 125 on the call trees, 69 off them; `layering_kill_arm.all_mutants` over the
  three outside helpers' files: 2;
- `sources_hash` over the export and over a fresh `git archive 9ad7631`: both `6dfe3807…`;
- a text check that each control's and hand mutant's patch matches the export's source exactly once;
- `census()` over the export's `Sources/`: five candidates, the four renderers GATED and GATED2 and `svgHeader` not,
  the cues C1–C5 expect from their excerpts; the same after the second round's fixes, in 0.11 s over 126 files.

**Run without a subject:**

- both self-tests (318/318 and 26/26), and the universe's asserts (`xml_emitter_census.py universe`, which reads
  revisions and origins, never a source file);
- `xml_emitter_census.py render` on `ComponentSVGRenderer+SVG.swift` at `9ad7631` (calibration rows 1 and 2) and on
  `SVGRenderer.swift` at `e36da59` (row 3);
- **the reach model behind prediction 6**, worked by hand from §5.2's draws. R-C: an edge renders when both its
  ends name a drawn component, so with *c* components of four pool names, one edge renders with probability
  (1 − (3/4)^*c*)², and over 0–4 edges a draw holds a reference about 30% of the time. R-S: an edge writes a marker
  when it has at least two points and is not an association (3/5 × 4/5), over 0–4 edges: about 60%. R-A: an edge
  renders when both its ids name one of 0–4 drawn nodes, over 0–5 edges: about 35%. R-Q: a message writes a marker
  unless it is an unresolved note (3/4), over 0–4 messages: about 73%.

**The universe, restored with the user's approval** (§2): 80 clones on 2026-10-30, all of them succeeding. Only
`git` metadata (revision, `origin`, status) was read from them, by the asserts.

**The first review round**, run as a workflow before the freeze (47 agents): five lenses, each finding marked
BLOCKING then given to a skeptic who tried to refute it.

- **Conformance** (15 findings), **decision hygiene** (12), **the kill arm** (6), **a parser attack** with
  hand-written Swift (11), and **a mechanical rule-break audit** (32 findings over 228 breaks).
- **Confirmed blocking, and fixed:** the copy key could not see literals (§1.3, X32); a judge repeating a label was
  last-wins (§4.3, D20); units were cut short by a nested literal inside an interpolation (§1.1, X31); a bare read in
  a ternary's first branch, or one behind an explicit receiver, was dropped as a label or a shadow (§1.2, X9);
  Law 1's sentinel was read off the output, so the inverted guard passed (§5.2); the runner pinned a toolchain the
  machine no longer had (§5.1). The audit's breaks of the comment rule, stored-property initialisers, the same-type
  rule and hop naming were confirmed blocking too, and each now has controls.
- **Refuted as blocking, and folded in anyway:** Law 2's single-subject rule was clarified (§8); R5's queries were
  kept, because the skeptic measured that the endpoint matches punctuation; Law 1's kill outcome being nearly
  settled by the operator set became §5.3's paragraph, H6, the caveat's wording and a frozen reopen condition (§8);
  ROOT's source-order rule became §1.2's four-step rule (X18).
- **The audit:** of 228 single-rule breaks, 104 were caught by a control and 3 by a self-test crash; 121 were not.
  Of those, 110 changed an output on a hand-written input, and each was given a control among X1–X33 and D1–D27
  (the second round found five of those controls inert; see below). The
  other 11 change no output, for the reason given: `\\` left unresolved (no cue reads a backslash); a continuation
  without trailing blanks (changes a cue only on an unindented line); a `{ get }` requirement kept as a unit (it has
  no literals); OPEN dropped from GATED (CLOSE needs ROOT, which needs an opener); the merge reading only
  `referenced_by` (it holds the same edges as the hops); the judged filter off in the merge (unjudged rows have no
  verdict); a truthy EXPRESSIBLE (`usable` demands a bool); repositories counted from every row (the merge key holds
  the toplevel); A's witness only, and C's unusable record kept raw (`decide` maps both the same way); and CLOSE-HOP
  forced false (no consumer then; R2 now reads it, D27).
- **Every minor finding was folded in**, among them: HTML read off the stream only; IDDEF at a literal's start;
  `print(…, to:)` as pure; `[String]` hops; `replacing`/`replace` as search calls; the search key walking outward;
  only a literal's first start tag opening with `xmlns`; R2's printed listings and CLOSE-HOP; C-decided rows keeping
  A's and B's flags; the unmerged count over decision copies only; the zero-repository label for Law 2; the flake
  rule keeping only reproduced failures; the frozen `Sources/` hash; the provenance rule by added test; the
  calibration rows' input types and the brief's tie-breaks (one complete root element is a DOCUMENT; an undocumented
  guard's `""` is a sentinel; a trap is not *body disagrees*; a constant is NOT-EMITTER); the `ambient` flag; the
  three on-tree helpers outside the five files; SwiftLint's move from the wide group, with its sensitivity line;
  SwiftFormat's `XMLReporter` as an R3 site not read.

**The second review round**, run as a workflow before the freeze (35 agents): four lenses, conformance, a
mechanical rule-break audit, a parser attack and the kill arm, each BLOCKING finding given to a skeptic.

- **54 findings**: 31 marked BLOCKING, 3 of them surviving their skeptic.
- **Confirmed blocking, and fixed:**
  - The judge workflow turned each judge's records into a label map, last-wins, before `join` could see a repeat.
    Its calibration gate keyed by label too, so a judge giving a row twice passed if the last copy was right. The
    first round's fix had reached `join` only. The workflow now returns raw records, counts a repeat as a
    calibration miss, retries a judge whose packet answer does not name each label once, and `verdicts` writes the
    judge files from the raw records (§4.3, D29).
  - X8 could not see the receiver rule: the owner's own `header()` was empty, so following `o.header()` to it added
    nothing. It now holds the opener, and `doc.header` on a model value is a second control (§1.2).
  - `literal_only` read the gaps between a stored initialiser's literals off the raw text, so a trailing comment
    made a literal constant non-literal: OPEN-HOP lost, a candidate lost through X17's route, and a commented
    doctype's HTML lost. It reads the code view now (X6–X7).
- **Found by a skeptic, and fixed:** a hop interpolated into the literal that holds the root sorted after that whole
  literal, so `"\(xmlHeader)\n<testsuites>…"` lost its ROOT. The stream now cuts the literal at the hop (X35).
- **Refuted as blocking, and fixed anyway:** `print(…, to:)` blanked its arguments' tokens and took any nested
  `to:` for its own (X28); the prefilter could pass over a marker spelled with `\u{…}` (X37).
- **Refuted as blocking, and kept as it stands, disclosed:** a split-literal declaration header whose root never
  closes takes a closed child as ROOT. The proposed rule moved X18's true document out of the gate, so the shape is
  pinned (X39) and listed in §9.
- **Minor from the start, folded in:** a tag inside an XML comment opened or rooted (X34); `import struct M.T` took
  the following type's properties (X36); typed closure parameters and a `for` tuple's later names did not shadow
  (X9); the search-key walk cost the square of a body's length, 23.5 s on a 4,000-case icon catalog against 0.3 s
  now (X37); the kill arm's flake rule let two assertion runs with no failure in common stand, keyed functions by
  name across files, and stored only the last 1,500 characters of a detecting run (§5.2, §5.4, §5.6); the decision
  lines gained the H count's bar verdict, each hand mutant's outcome, N_wide's estimate without EXPRESSIBLE, and the
  copies' subjects for Law 2's list (§8); the brief's example record, which was calibration row 1's answer word for
  word, now names fields, never values. An `xmlns` tag after a start tag in an earlier literal still opens, since
  the proposed rule lost a chart that builds its body first; it is pinned (X39) and listed in §9.
- **The audit:** 450 single-rule breaks; 253 caught by a control and 7 by a self-test crash; 190 not. Of those, 81
  moved an output on a realistic input. They are 27 control gaps, each in code that already does what §1 says, so
  no frozen figure moved; four were first-round fixes whose controls were inert (SO1, HP2, LO5 and LF7). Every one
  now has a control. The other 109 move an output only on contrived input or not at all; among them RT6's (X17's
  search-key tag), now pinned by a key that carries `xmlns`, and the cheap ones got one-line controls (`willSet`,
  four hop spellings, three grep markers alone, XHTML's `gated_without_pure`, the named subject and the calibration
  table as literals). Then 63 breaks, of the audit's and of this round's own new code, were applied to the fixed
  script, and each fails at least one control: X34–X40, D28–D30, and new or changed checks under C11, C12, C25, X2,
  X6–X10, X17, X20, X21, X24, X28–X29, X32–X33, D5, D7, D8, D16, D19, D21–D24, D26 and D27.
- **The kill arm's runner** went from 19 checks to 22, three added and one widened, each re-checked to fail when its
  rule is broken, and RC1 now runs the reduced suite once and requires exactly 23 fewer tests than the full.

**The third review round**, run as a workflow before the freeze (18 agents), on the second round's fixes only: five
lenses, the new cue code (with a differential against the pre-fix script over SwiftUMLStudio's 3,071 units), the
judge path, a rule-break audit of the new code, conformance and the record, and the kill arm.

- **43 findings**: 13 marked BLOCKING, 1 surviving its skeptic, found by two lenses.
- **Confirmed blocking, and fixed:** ROOT's step 1 read the whole opening literal past an interpolated hop, so
  `"<?xml…?>\n\(svgOpen)\n<rect/>…"` took `rect` as its root: GATED lost, GATED2 lost with an id-carrying child, and a
  root closed only in a hop read as closed. Not a regression (the pre-fix script did the same); the second round's
  cut had reached the stream and OPEN, not ROOT. Step 1 now stops at the first cut after the declaration's `?>`
  (§1.2, X35).
- **Refuted as blocking, and fixed anyway:** a literal nested in an interpolation (a ternary's optional header)
  sorted after its whole enclosing literal; the stream now places nested literals and hops at their placeholder in
  every enclosing flowing literal (§1.2, X35). The other eleven were control gaps in code that does what §1 says, each
  now pinned: the cut at a placeholder above 0 and a function hop interpolated (X35), brackets closed inside a search
  call (X37), a subscript or closure in print's own arguments (X28), a comment spanning lines or left open (X34), a
  label on its own line (X10), a `Self.` read far into the body (X8), Law 2's list leaving out a NOT-SVG row (D27),
  Law 2's own hand line (D24), and N_wide's estimate without EXPRESSIBLE and the H line with no summary (D21, D24).
- **Minor, folded in:** the receiver read without a 256-character window (X8); closure heads with a capture list, an
  attribute, a result type or parenthesised types (X9); the prefilter's `\#u{…}` (X37); `packets` writing
  `sizes.json` for the workflow (§4.3, X40); `join` keeping the flags of a record C gave for an agreed row (D19);
  calibration demanding usable records, retrying an agent that returned nothing, and limiting what rows 1 and 2 may
  read, since row 3's answer stands in a comment at its own path (§4.2, D23); the workflow's verdicts, law2 values
  and expected answers checked against the script's (D16, D23); `verdicts` refusing a null packet, and any refusal
  stopping the arm until an amendment (§4.3, D29); the brief reading an HTML-vocabulary card (`<div>…<svg>…</div>`)
  as HTML (§4.4); the kill arm keeping a cut counterexample's tail, marking and showing a `disjoint` flake, failing
  RC1 on one, running RC1's reduced suite under the flake rule, letting a crashing rerun stand, and naming untitled
  tests (§5.2, §5.4–§5.6); §3's audit gate now admitting contrived-only breaks listed here, and the record above
  corrected (RT6 among the 109; the refuted and the minor findings told apart; the runner's 19 → 22; the 63 breaks
  described as they were).
- **The audit:** 143 single-rule breaks of the new code and controls; 72 caught by a control and 2 by a crash; 69
  not. Of those, 17 moved an output on a realistic input, the eleven gaps above; 28 move one only on contrived input
  or only an unconsumed field, and 24 change none, each listed by the review with its reason (among them the two
  contrived shapes now in §9). After the fix, 40 breaks (the 17, the nested stream, the new rules and this round's
  own code) were applied again, and each fails at least one control; the second round's 63 still do.
- **The differential**, current against pre-fix, over SwiftUMLStudio's Sources and Tests (3,071 units): the only
  change is the wider closure locals, and no cue moves. The export's census is still five candidates, the four
  renderers GATED and GATED2 and `svgHeader` not.

**Not opened:** any census subject other than SwiftUMLStudio.

## Amendments

None.
