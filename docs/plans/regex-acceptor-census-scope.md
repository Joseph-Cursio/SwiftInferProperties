# Does "the pattern a producer builds compiles" have a population? (#666)

> **Status:** `proposed` · **As of:** 2026-10-27

#666 asks for a law the catalogue does not have. For a producer `f` whose result the module passes to a
throwing regex acceptor `A`, the law is:

> `#expect(throws: Never.self) { try A(<the caller's argument expression, with f(x) in place>) }`

Two witnesses motivate it:

- **SwiftUMLStudio's `String.globPatternToRegex()`** feeds `NSRegularExpression` from
  `isMatching(searchPattern:)`. The law found G2 here, a real defect: a bare `}` at `111d8bd`, fixed in
  `8fc0cde`.
- **SwiftAssist's `GlobTool.translate(glob:)`** feeds it from the `glob` tool, wrapped as
  `"^" + translated + "$"`.

The only law the tool has been seen to offer either function is `idempotence`, and it is false. That was not
re-checked at `f4bfdad1`.

The issue sets a gate before anything is built, in three steps:

1. **Population.** Count producer functions with a qualifying caller, over the funnel repositories, the
   manifest corpora and nicklockwood/SwiftFormat.
2. **Precision.** Run each candidate's stub at HEAD under a balanced-bracket domain, and hand-check every
   refutation.
3. **Decision.** If the count stays near the grep's two, decline. Build only if the population clears the
   bar of `replacement-chain-idempotence-census.md`, and the in-domain refutations at HEAD are real or
   absent.

#666's grep found two such functions in 47 local repositories. This scope fixes the pass, the controls, the
predictions and the decision rule before the pass reads any subject.

**How it got here.**

- **A four-lens adversarial review** of the first draft found 55 problems, 13 of them blockers. It covered
  fidelity to #666, the pass rule, decision hygiene and the precision harness.
- **A dry run** of the draft pass on the two witness repositories found two more faults (§10).
- **A conformance check** of the revised text against both scripts found 33 more, 2 of them blockers.

Every one is folded in below. Nothing else in the population has been read.

## 1. The pass

A text census over masked source, written as `scripts/regex_acceptor_census.py`.

- **What the masker blanks**: comments, string-literal text and regex literals. It keeps the code inside
  every `\( … )` interpolation, recursively.
  - An extended regex literal `#/…/#` closes on `/` plus the same number of `#`.
  - A bare `/…/` literal counts as one only in expression-start position, when it is not followed by
    whitespace, `/`, `*` or `=`. Expression-start means after `(`, `[`, `,`, `:`, `;`, `=`, `{`, `!`, `&`,
    `|`, `?`, `+`, `-`, `*`, `<`, `>`, a line start, `return`, `in`, `try` or `await`. It closes at the next
    unescaped `/` on its line outside a `[…]` class.
- **The balance check.** After masking, each file's `()`, `[]` and `{}` must balance. A file that does not
  is **UNPARSED**, and it is reported by path along with its count of acceptor spellings. It enters no
  outcome count, no resolution and no population.

**Each row is one acceptor call site.**

### 1.1 Acceptor calls

Spellings match with any whitespace or newlines between tokens.

| kind | spelling | the pattern argument `E` |
|---|---|---|
| **throwing** | `NSRegularExpression(pattern:` and `NSRegularExpression.init(pattern:` | the `pattern:` argument |
| **throwing** | `Regex(`, `Regex<…>(` (also `.init(`) with an unlabeled first argument that is not a regex literal | the first argument |
| **silent** | a call whose first argument is labelled `of:` and whose `options:` argument contains `regularExpression`, such as `range(of:options:)` and `replacingOccurrences(of:with:options:)` | the `of:` argument |

- **Silent acceptors never throw.** Given `[`, they return `nil` or the string unchanged, as #666 checked. A
  producer that feeds one is still a candidate.
- **LITERAL-MODE.** A row whose options contain `ignoreMetacharacters` reads its pattern literally, so it
  licenses no producer.
- **A subject's own `Regex` type.** In a subject that declares a type named `Regex`, `Regex(` calls are not
  acceptors, and their count is reported.
- **Not matched**: `Regex(verbatim:)`, which escapes by construction, and regex literals. Two spellings are
  counted under R3 instead: `.init(pattern:` with no type name, and `NSPredicate(format:)` with `MATCHES`,
  which raises an Objective-C exception rather than throwing. R3 also counts silent calls whose `options:`
  is an identifier.

### 1.2 The value that reaches the call

**The scan set `S`** holds every call and every property read in `E`, including those inside interpolations
and closure literals. Two kinds of position are excluded:

- the argument list of `NSRegularExpression.escapedPattern(for:)`, because Foundation's escaper makes any
  input acceptable;
- the inside of subscript brackets: a `[` right after a word character, `)`, `]`, `?` or `!`.

An unapplied function reference passed to `map`, `compactMap` or `flatMap`, such as `ws.map(escape)`, counts
as a call of that name, with labels taken from a `(label:)` reference or else one unlabeled argument.

**Which identifiers are followed.** An identifier in `E`, or in a followed initializer, is followed unless it
is one of these:

- a member name after `.`;
- an argument label or a dictionary key: an identifier followed by `:` right after `(`, `,` or `[`;
- a ternary's condition: an identifier followed by a `?` that is not `??`, `?.` or `?[`;
- a capitalised name followed by `(`, `.` or `<`, which is a type.

`$0`-style closure arguments are followed like any other identifier.

**Quiet following.** An identifier that is a call's receiver (followed by `.`, `(`, `?.` or `!.`) or sits in
a function call's argument list is followed **quietly**. It is followed through a `let` or an unmutated `var`
so that the calls and member reads in its initializer join `S`, as they would if written inline. It never
marks the row WRAPPER or REWRITTEN, and it never becomes a bare property read. A type initializer's
arguments, such as `String(…)`, are followed normally, because a conversion is not a producer.

A followed identifier is resolved this way, up to three bindings deep:

- **Where to look.** Bindings are searched in the brace blocks that enclose the call, out to the enclosing
  `func`, `init`, `subscript` or computed-property body. Closures are transparent. Bindings must start
  before the identifier's **position**:
  - for an identifier in `E`, the identifier's own offset;
  - for one inside a followed initializer, the start of that binding.

  So the `v` in `guard let v = v` or `if let v = v` resolves to the outer `v` or the parameter. The nearest
  binding wins. A binding inside a block that does not enclose the call is never used.
- **Properties are never bindings.** A `let` or `var` directly in a type body or at file scope is a property,
  wherever the call is.
- **Binding forms**:
  - `let`/`var v = I` and `v: T = I`;
  - `if`/`guard`/`while let|var v = I`, and any later clause of such a condition;
  - a deferred `let v: T` with no initializer, which binds every later `v = I` before the call. Each such
    `I` joins the chase.

  A deferred `var v: T` is REWRITTEN, because its assignments are mutations, and R5 reports their calls.
  `if let v` with no initializer is followed past to the outer `v`.
- **Where an initializer ends.**
  - At a depth-0 `;`, `,` or `else`.
  - At a depth-0 line break, unless the line ends with a binary operator, `(`, `try` or `await`, or the next
    line starts with `.` or a binary operator.
  - At a `{` only inside an `if`/`guard`/`while` condition. Elsewhere it opens a trailing closure.
- **`let`, or `var` never mutated** before the call: the calls and reads in `I` join `S`, and `I` is followed
  in turn.
- **`var`, mutated** before the call: `I` does not join `S`, and the row is marked REWRITTEN. `expandGlobs`'
  `var regex` at `e36da59` is this case (C2). At SwiftUMLStudio HEAD `b8b1520`, that call site binds
  `let regex = globRegexPattern(anchor:pattern:tokens:)` instead. That producer was added in `ee82090`,
  after #666 was written.
  - **A mutation** is any of: `v =`; `v op=`; `&v`; or `v.m(` or `v.m {`, where `m` is `append`, `insert`,
    `remove`, `removeAll`, `removeFirst`, `removeLast`, `removeSubrange`, `replaceSubrange`, `popLast`,
    `trimPrefix`, `replace`, `sort`, `reverse` or `shuffle`.
  - **Where it counts.** It counts between the binding and the call, or anywhere in a loop body that
    contains the call when the binding is outside that loop.
  - **Not mutations.** `replacingOccurrences(`, `replacing(` and `trimmingCharacters(` are reads.
- **A parameter of the enclosing scope**, with no nearer binding, marks the row WRAPPER.
- **Anything else** that is not bound is a property read, which joins `S`.

### 1.3 Resolving an element of `S`

- **Index.** The subject's declarations are indexed once over its file set, deduplicated by real path, so a
  file reached through two scan roots is indexed once.
- **Calls.** A call is resolved by name and argument labels (`_` for an unlabeled one) against every
  `func` with a body.
  - A declaration matches when the call's labels equal its labels in order, with defaulted parameters
    skipped.
  - A variadic parameter absorbs consecutive arguments.
  - A trailing closure fills the next function-typed parameter.
- **Property reads.** A property read resolves when two things hold:
  - the subject declares exactly one property of that name of any kind, counted after the `#if`-arm rule.
    "Any kind" means stored or computed, instance or static, directly in any type body or at file scope;
  - that property is a computed `String` or `String?` with a getter body.

  Two or more is ambiguous.
- **File scope.** A `private` or `fileprivate` declaration matches only reads from its own file. A member
  with no access modifier takes `private` or `fileprivate` from any enclosing extension or type, however
  deep. Swift makes this sound (`lift-caller-reach.md`).
- **`#if` arms.** Declarations with the same name and labels in different arms of one `#if` group count as
  one, resolved to the first arm, for calls and property reads alike.
- **Standard names.** A call named `joined`, `escapedPattern`, or any operation in the §1.4 list is EXTERNAL,
  whatever the subject declares. swift-foundation declares `replacingOccurrences`, for example.
- **The outcome.** Exactly one match is **resolved**, none is **external**, and two or more is
  **ambiguous**: the collision hazard that `lift-caller-reach.md` and `decoder-bypass-census.md` measured at
  this seam. The subject's file set counts as one module. That over-reports collisions across targets, and
  it can resolve a call to a target that cannot see the declaration.

### 1.4 Producers

A resolved declaration is a **producer** when its result is written `String` or `String?`. Its **input** is
one of:

- **RECEIVER**: `self` and every String-typed parameter, for a non-static member of an `extension` of
  `String`, `StringProtocol`, `Substring` or `Character`;
- **PARAM**: each String-typed parameter of any other declaration;
- **OTHER-INPUT**: neither of those. That includes a static member of a String extension with no String
  parameter.

A **String-typed** parameter is typed `String`, `Substring`, `Character`, `String?`, `[String]`,
`String...` or `some StringProtocol`, or is a generic constrained to `StringProtocol`.

**The transform rule is loose on purpose. The pass widens, and §5 narrows.** A producer has a **transform
read** when two things hold:

- its body reads an input;
- its body holds at least one rewriting operation, on any operand.

The review asked for a strict rule, in which the operation's operand must contain the input. That rule was
rejected for two reasons:

- **It drops G2's own body.** At `111d8bd`, `"^\(self)$".replacingOccurrences(…)` rewrites a literal that
  only interpolates `self`.
- **Its cost runs the wrong way.** The loose rule's false positives cost judging time, because §5 removes
  them. A false negative never reaches a judge and lowers N silently.

The rewriting operations fall into three evidence kinds:

| kind | operations |
|---|---|
| **#666's three**: a replacement, an escape class, a per-character loop | `replacingOccurrences(`, `replacing(`, `stringByReplacingMatches(`; `map`, `flatMap`, `compactMap`, `reduce`, `forEach`, `unicodeScalars`, `utf8`, `utf16`, `indices`, `startIndex`, `endIndex`; `for … in <input>`, `<input>[` |
| **WIDE** | `filter`, `components(separatedBy:`, `split(`, `trimmingCharacters(`, `addingPercentEncoding(`, `applyingTransform(`, `lowercased(`, `uppercased(` |
| **ESCAPE-ONLY** | `NSRegularExpression.escapedPattern(for:)` |

A listed operation with no receiver counts for every input kind. For RECEIVER, it also counts as a read of
`self`, and so do `for … in self` and `self[`.

**Delegation.** Passing an input to a resolved subject producer counts as a transform read, at one level, and
it takes that producer's direct evidence kind. Passing can be by call or by property read, and the input can
be an argument or the receiver (`glob.regexEscaped`). For RECEIVER, a call with no receiver also counts.
Every delegate whose direct kind is #666's three is recorded, for §8's thin-wrapper merge.

**A producer's evidence kind** is the strongest it has: #666's three, then WIDE, then ESCAPE-ONLY. An
ESCAPE-ONLY producer cannot have G2's defect, a hand-rolled escape class missing a character. Its law can
fail only through a fixed literal wrapper.

### 1.5 Row outcome, population, identity

**Every element of `S` is recorded with its own class**: QUALIFYING, COMBINATOR, OTHER-INPUT, AMBIGUOUS (with
its candidate declarations) or EXTERNAL. QUALIFYING means it resolves to a producer with String input and a
transform read. COMBINATOR means String input and no transform read.

The row's outcome is the first rule that applies:

1. **QUALIFYING**: some element of `S` is QUALIFYING.
2. **COMBINATOR**: some element is COMBINATOR.
3. **OTHER-INPUT**: some element is OTHER-INPUT.
4. **AMBIGUOUS**: some element is ambiguous and at least one of its candidates is a producer.
5. **REWRITTEN**: the row is marked REWRITTEN.
6. **WRAPPER**: the row is marked WRAPPER.
7. **EXTERNAL**: `S` holds calls and none resolves to a producer.
8. **LITERAL**: `S` is empty. Nothing but literals reaches the call, directly or through bindings.
9. **STORED**: anything else: a property or static that does not resolve to a producer.

LITERAL-MODE rows are reported apart.

**Each row also records:**

- **The handling.** The governing keyword is the last `try`, `try?` or `try!` before the acceptor in the
  same statement, at any depth. `try?` is **HANDLES-NIL**. `try` inside a `do` with a `catch` is
  **HANDLES-CATCH**. `try` in a `throws` function with no local `catch` is **PROPAGATES**. `try!` is
  **ASSERTS**. A silent acceptor is **SILENT**. Anything else is **UNKNOWN**. Closure boundaries are not
  modelled, and handling enters no decision.
- The acceptor's full spelling and options.
- The argument expression and the bindings followed.
- Every element's resolution.

**Each judged producer also records** (§5):

- its full doc comment;
- its **callers**: every call or read the §1.3 resolver resolves to it, up to 50.

**A subject is a repository**, identified by the real path of its root. A repository reached by several
groups is scanned once, over the union of their scan roots. Its rows carry the first group's label, in the
order manifest, funnel, unmet, upstream.

**The population** is the union of QUALIFYING elements over all rows except LITERAL-MODE rows. **A producer is
identified** by its subject, the real path of its file, and the offset of its `func` or `var` keyword.

**Vendored copies.** Two producers are one, listed at every location, when their name, argument labels and
body are identical. The body is compared with comments removed and whitespace collapsed, and with literal
text kept, because a hand-rolled escape class lives in a literal.

## 2. The universe, frozen

The universe is the subjects `budgeted_truncation_census.subjects()` resolves on this machine on 2026-10-27,
plus one clone. **The script asserts this exact list**, and that SwiftUMLStudio and SwiftAssist are in it.
Otherwise it exits non-zero and reports no population. Revisions are recorded per subject.

- **manifest (22)**: swift-infer-core, swift-format, grdb, swift-collections, swift-syntax, swift-nio,
  swift-package-manager, swift-numerics, swift-algorithms, swift-argument-parser, swift-foundation,
  swiftlang-swift (`stdlib/public/core`), harmonize, swift-project-lint, swift-property-laws,
  swift-effect-inference, maccloud-client-ios, swiftlint-rule-studio, swiftformat-rule-studio,
  planted-defect-arm, cycle27-surface, leaderboard-sort. Each corpus is read through its manifest source
  directories.
- **funnel (19)**: LintStudioUI, MacCloud_client_MacOS, MacCloud_server, pbt-book, pbt-workbook-corpus,
  pbt-workbook-grader, pbt-workbook-sampler, pbt-workbook, SwiftAssist, SwiftCloneDetector,
  SwiftEffectInference, SwiftFormatRuleStudio, SwiftIdempotency, SwiftLintRuleStudio,
  SwiftLintRuleStudioTeam, SwiftMarkdownWiki, SwiftProjectLint, SwiftPropertyLaws, SwiftUMLStudio. Each is
  read from its root. Five of these are also manifest corpora and are scanned once (§1.5).
- **upstream (1)**: nicklockwood/SwiftFormat, shallow-cloned at `75e09c0e` (2026-10-27), with the user's
  approval. It is read through `Sources/`. Its `Snapshots/` holds other projects' code kept as formatting
  fixtures, so it is not read. The script asserts that exactly this clone is given, at this revision. It is
  text-scanned and never built or run.
- **unmet (5)**: Euclid, swift-docc, OpenAPIKit, jwt-kit, swift-system. These are scanned and reported as
  **N_unmet**, outside the decision, because #666's universe is the first three groups. Eight more unmet
  subjects of the earlier censuses are not checked out here.

**Skipped files.** A file is skipped when any directory component of its path relative to the subject root
is:

- hidden;
- named `Tests`;
- named with the suffix `Tests` or `UITests`;
- `.build`, `build`, `DerivedData` or `checkouts`.

The review measured 333 Xcode test-target files and one generated file that the old walk let through. The
report gives, per subject, the files scanned and the files skipped, each skipped file counted once by its
real path.

## 3. Controls for the pass, asserted before any subject is read

The controls' sources are embedded in the script. They need no sibling checkout and run in
`make measurement-selftest`. A failing control exits non-zero, and no population is reported.

| # | source | expected |
|---|---|---|
| C1 | SwiftUMLStudio `e36da59`, verbatim: `globPatternToRegex`, `isMatching(searchPattern:)` | QUALIFYING, RECEIVER, HANDLES-NIL |
| C2 | the same commit, verbatim: `expandGlobs` | REWRITTEN, HANDLES-CATCH. The three silent literal-pattern calls in the two files (two in `expandGlobs`, one in `globPatternToRegex`) are LITERAL, SILENT |
| C3 | SwiftAssist `12b0e90`, verbatim: `translate(glob:)` and `execute`'s call | QUALIFYING, PARAM, HANDLES-CATCH, argument `"^" + translated + "$"` |
| C4 | `MarkRule`-style `"(?:\(pattern))"` combinator | COMBINATOR |
| C5 | two non-private `escape(_:)` in two types | AMBIGUOUS |
| C6 | `NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: s))`, `s` a parameter; and the same around `escape(s)` | EXTERNAL, PROPAGATES, both: the producer inside `escapedPattern(for:)` is not in `S` |
| C7 | `try! NSRegularExpression(pattern: "a+")` | LITERAL, ASSERTS |
| C8 | `func compile(_ p: String) throws -> NSRegularExpression { try NSRegularExpression(pattern: p) }` | WRAPPER, PROPAGATES |
| C9 | `text.range(of: glob.toRegex(), options: [.regularExpression, .caseInsensitive])` | QUALIFYING, SILENT |
| C10 | `try Regex(translate(x))` | QUALIFYING, `Regex` |
| C11 | `var p = f(x); p += "$"` before the call | REWRITTEN |
| C12 | a `private` producer called from its own file and from another | QUALIFYING; EXTERNAL |
| C13 | `NSRegularExpression(pattern: "^\(escape(name))$")` | QUALIFYING through the interpolation |
| C14 | `let e = escape(x); let p = "^\(e)$"` then the call | QUALIFYING, two bindings deep |
| C15 | the spelling inside a comment and inside a string | no row |
| C16 | `let pattern = #"…"#` then the call | LITERAL (dry-run fault 1, §10) |
| C17 | `for pattern in Self.patterns { … NSRegularExpression(pattern: pattern) }` | STORED |
| C18 | SwiftUMLStudio `111d8bd`, verbatim: wrap-then-rewrite `globPatternToRegex` and its `isMatching` | QUALIFYING, RECEIVER, #666's three |
| C19 | `func group(_ p: String) -> String { "(?:\(p))" }` beside `flags.map(…)` | COMBINATOR, loose rule notwithstanding |
| C20 | `NSRegularExpression.init(pattern: f(x))`, `Regex<Substring>(f(x))`, `s.replacingOccurrences(of: f(x), with: "", options: .regularExpression)` | QUALIFYING ×3 (the last SILENT) |
| C21 | `s.range(of: f(x))` with no options; `Regex(verbatim: f(x))`; `/a+/`; `#/a{2}/#`; `.init(pattern: f(x))`; `NSPredicate(format: "SELF MATCHES %@", f(x))` | no row; R3 counts 1 bare `.init` and 1 `NSPredicate` |
| C22 | `var p = f(x)` never mutated; then `p.append("$")`; then `g(&p)` | QUALIFYING; REWRITTEN; REWRITTEN |
| C23 | `escape(_:)` beside `escape(html:)`, called `escape(x)`; `translate(_:anchored: Bool = true)` called `translate(x)` | QUALIFYING; QUALIFYING |
| C24 | `extension String { var asRegex: String { replacingOccurrences(of: "*", with: ".*") } }`, read `glob.asRegex` | QUALIFYING, RECEIVER |
| C25 | `NSRegularExpression(pattern: escape(x), options: .ignoreMetacharacters)` | LITERAL-MODE, and `escape` is not in the population |
| C26 | a bare regex literal with a `"` and an unbalanced `(`, and an extended literal `#/\{"/#`, before a WRAPPER call | WRAPPER (masker holds) |
| C27 | `func esc(_ s: String) -> String { NSRegularExpression.escapedPattern(for: s) }` feeding the acceptor | QUALIFYING, ESCAPE-ONLY |
| C28 | a subject whose scan roots are `Sources` and `Sources/Core`, producer in `Sources/Core` | QUALIFYING, not AMBIGUOUS |
| C29 | the same producer in two arms of one `#if` | QUALIFYING, not AMBIGUOUS |
| C30 | a file whose braces do not balance after masking | UNPARSED, no rows |
| C31 | a subject declaring `extension String { func lowercased() -> String { … } }`, then `NSRegularExpression(pattern: x.lowercased())` | EXTERNAL: a standard name never resolves to the subject |
| C32 | `NSRegularExpression(pattern: words.map(escape).joined(separator: "\|"))` | QUALIFYING through the unapplied reference |
| C33 | `NSRegularExpression(pattern: table[escape(key)] ?? "")`, `table` a parameter | WRAPPER: a subscript key is not the pattern |
| C34 | `func translate(glob: String) -> String { "^" + escape(glob) + "$" }` feeding the acceptor | QUALIFYING, by delegation to `escape` |
| C35 | `if let p = g { … NSRegularExpression(pattern: p) }`; `if let a = g, let p = String(a) {…}`; `guard let glob = glob else {…}` | WRAPPER ×3: a later condition clause, a conversion, and same-name rebinding |
| C36 | a String-extension `var asRegex: String {…}` beside `struct Other { let asRegex: Int }`, read `glob.asRegex` | AMBIGUOUS |
| C37 | `var p = escape("a")`, then a loop that calls the acceptor and then does `p = x` | REWRITTEN: a mutation later in the loop body counts |
| C38 | `var p = escape(x)`, then `p.replacingOccurrences(…)` and `p.trimmingCharacters(…)` read into other lets | QUALIFYING: reads, not mutations |
| C39 | a multi-line `private extension String { func esc() … }` called from another file | EXTERNAL |
| C40 | `func alt(_ parts: String...) -> String` called `alt(a, b)` | QUALIFYING: variadic absorption |
| C41 | `func tr(_ s: String, each: (Character) -> String) -> String` called `tr(a) { … }` | QUALIFYING: the trailing closure fills `each` |
| C42 | `let p: String; if c { p = escape(x) } else { p = "a" }` then the call | QUALIFYING: the deferred `let` |
| C43 | `let p = escape(x)`, then `pattern: String(p)` | QUALIFYING: a type initializer's argument is followed |
| C44 | a subject declaring `struct Regex`, then `Regex(escape(x))` | no row; the `Regex(` call is counted |
| C45 | `s.lowercased().map {…}`; a producer whose only operation is `filter` | evidence #666's three; WIDE |
| C46 | `let v: String? = escape(x); if let v { … pattern: v }` | QUALIFYING: `if let` shorthand follows the outer `v` |
| C47 | `extension String { static func star() -> String {…} }` feeding the acceptor | OTHER-INPUT: a static member is not RECEIVER |
| C48 | the producer in `Sources/CoreTests/` | EXTERNAL; the file is counted as skipped |
| C49 | `let p = items.map { escape($0) }.joined(separator: "\|")` then the call | QUALIFYING: a trailing closure inside an initializer |
| C50 | `private enum Outer { enum Inner { static func esc(_:) … } }` called from another file | EXTERNAL: `private` from an outer type |
| C51 | `let globalPattern = escape("a")` and `let compiled = try! NSRegularExpression(pattern: globalPattern)` at file scope | STORED, ASSERTS: a file-level `let` is a property, not a binding |
| C52 | `NSRegularExpression(pattern: strict ? "a+" : "b+")`, `strict` a parameter | LITERAL: a ternary's condition is not part of the value |

**Each rule has a control that fails when the rule is broken.** This was checked by breaking the script one
rule at a time, 43 breaks, and running the controls after each. Three times it found rules with no failing
control:

- five after the first draft;
- fifteen named by the conformance check;
- four more when the check was re-run after that.

C34–C52 and the second cases of C6, C26 and C38 now cover them.

## 4. The precision arm

It runs after §5's verdicts are frozen and committed, whatever the population outcome.

### 4.1 Domains

| domain | definition | inputs |
|---|---|---|
| **D4** | every string of length ≤ 4 over `a . ( ) + \| ^ $ { } \ * ? / [ ]` in which: every `[`, `(` and `{` is closed by its partner; each pair encloses one or more characters, all of them letters or digits, so pairs cannot nest; no closer stands alone. The empty string is included | **11,177** |
| **D4x** | the same, with `- z :` added | **31,115** |
| **RAW2** | every string of length ≤ 2 over the 16 characters, unfiltered | 273 |
| **FREE3** | every string of length ≤ 3 over the 14 characters other than `[` and `]` | 2,955 |

**§8 reads only D4 and D4x.** RAW2 and FREE3 rejections get the same shrinking and verdicts. They are
reported as what the domain avoids and what it hides, and never read by §8.

### 4.2 The stub

**Which producers get a stub.** Every population producer that §5 judges TRANSLATOR gets one, with no
sample. Producers §5 judges otherwise are not stubbed. The witnesses at HEAD are stubbed by this procedure,
like every candidate.

**The stub's header.** Each stub starts with `// @producer-id <ident>`, the census JSON's `producers` key
verbatim, and `// @rows <file>:<line>[, …]`, the QUALIFYING rows it covers. The runner refuses a stub
without them. A stub may also carry `// @domain length-1`, for a `Character` input.

**What a stub holds:**

- **The producer's declaration, verbatim.** Helpers it calls are copied verbatim too. A shim for an
  unrelated dependency is allowed, and each one is recorded. A `static func` sits in a shell type of the
  same name.
- **One stub per distinct combination** of acceptor spelling, options and inlined argument text among the
  producer's QUALIFYING rows.
  - **The argument.** It is the acceptor's argument with every binding §1.2 followed inlined, so text that
    a `let` adds is kept.
  - **Other operands.** Each operand other than the producer call takes the call site's value when that
    resolves to a literal through the same chain. Otherwise it takes a representative recorded in the stub.
- **Which input the domain drives.** It drives one input per stub:
  - for RECEIVER, the receiver, then each String-typed parameter in turn;
  - for PARAM, each String-typed parameter in turn.

  There is one stub per driven input, with the other inputs taking the call site's argument or a recorded
  representative.

  The conversions are `Substring(x)`, `Optional(x)`, `[x]` for `[String]`, and `x` for
  `some StringProtocol`. A `Character` input runs over the length-1 inputs only, marked
  `// @domain length-1`, and that count is recorded. **A producer is refuted if any of its stubs is.**
- **The acceptor, by its full spelling and options**, with any generic argument kept. It lives in
  `accepts(_:)`, which is the stub's last declaration.
  - **Typed `Regex`.** A rejection by a typed `Regex<…>` or `Regex(_:as:)` that the untyped `Regex(_:)`
    would accept is **CAPTURE-TYPE**. Whether the acceptor is typed is read from `accepts(_:)`'s own code.
  - **Silent acceptors.** A silent acceptor is tested with the parser its API uses, measured on macOS 27.2
    and asserted by PC6:
    - `range(of:…)` on a `String` or `Substring` parses with Swift `Regex`, and with ICU when that throws, so
      it rejects only a pattern both reject. The stub tests
      `(try? Regex(p)) != nil || (try? NSRegularExpression(pattern: p, options: [])) != nil`;
    - `replacingOccurrences(of:with:options:…)` and any `NSString` receiver use ICU alone, so the stub tests
      `NSRegularExpression(pattern: p, options: [])`.

    `String.CompareOptions` are dropped.
- **`nil` or a throw** from the producer is **DECLINED-BY-PRODUCER**. That is not a rejection, and its count
  is reported. A `?? literal` at the call site is part of the inlined argument and is evaluated.

**How it is built and run.** It is compiled with the pinned toolchain's
`swiftc -O -sdk $(xcrun --sdk macosx --show-sdk-path)` and run over all four domains. The driver streams
each input's outcome, so one input's failure never loses another's. The run records `sw_vers -buildVersion`,
the SDK and `swiftc --version`.

- **TRAPPED.** An input on which the stub's process dies by a signal, or makes no progress for 60 seconds,
  is TRAPPED. The runner records it and resumes at the next input. TRAPPED inputs are shrunk and grouped
  apart from rejections, and each group gets a §4.3 verdict and enters §8 as a rejection group would. A
  trap fails `#expect(throws: Never.self)` as surely as a throw does.
- **UNSTUBBABLE.** A stub that does not compile with recorded shims is UNSTUBBABLE, and its first compiler
  error is recorded. The run goes on to the next stub. So is a producer whose receiver or arguments cannot
  be built.
- **Hard errors.** A positive exit code, or a crash before any input, is a hard error for that stub. It is
  recorded and never counts as zero rejections.

The runner is `scripts/regex_acceptor_precision.py`, and the stubs are kept in
`fixtures/regex-acceptor-census/stubs/`.

**Controls for the harness**, re-asserted on the machine that runs the candidates before any candidate stub
is read. They reproduce #666's JavaScript-transcription numbers with a second instrument: compiled Swift
running the real body.

| # | stub | expected |
|---|---|---|
| PC1 | the four enumerators | 11,177 · 31,115 · 273 · 2,955 |
| PC2 | `globPatternToRegex` at `111d8bd`, ICU | D4 **22** rejected, each containing `}`, shrinking to the one group `{a}`. D4x **58**, shrinking to `{a}` (29) and `{z}` (29) |
| PC3 | `globPatternToRegex` at `e36da59`, ICU | D4, D4x, FREE3: 0. RAW2: **32**, exactly the inputs containing `[`, shrinking to `[` |
| PC4 | `translate(glob:)` at `12b0e90`, wrapped as its caller wraps it, ICU | D4, D4x, FREE3: 0. RAW2: **32**, as PC3 |
| PC5 | `translate(glob:)` without the wrapper | D4's one rejection is `""` |
| PC6 | the run machine's parsers | `range(of:)` accepts `{a}`, which ICU rejects. `replacingOccurrences` leaves `x{a}y` unchanged for `{a}`. `try Regex("$+")` throws, yet `String` and `Substring` `range(of: "$+")` match `"a"` (the ICU fallback). `"aK".range(of: "\\K")` matches, because ICU reads `\K` as `K`. `"a\\".range(of: "a\\")` is `nil`, because both parsers reject it |
| PC7 | typed `Regex` | `111d8bd` under `try Regex(_:)`: D4 **0**, because Swift `Regex` accepts a bare `}`. `e36da59` under `try Regex<Substring>(_:)`: D4 **3,492**, all CAPTURE-TYPE and none syntax |
| PC8 | a producer that traps on `{a}` | D4: TRAPPED `[{a}]`, and the run resumes. The rest is rejected only at `""` |
| PC9 | a stub that does not compile | UNSTUBBABLE, with its first error, and the run goes on |

### 4.3 Refutations

**Shrinking.** Each failing input is shrunk mechanically:

1. Delete one character at a time, leftmost first.
2. Keep the first deletion whose result is non-empty, still in the same domain, and still failing the same
   way.
3. Repeat until no deletion applies.

Every domain is exhaustive over its lengths, so "still failing" is read from the run. Each class is shrunk
and grouped within itself, by its minimal input: syntax rejections, CAPTURE-TYPE rejections and TRAPPED
inputs. The empty input is its own group, EMPTY.

**CAPTURE-TYPE groups** are reported apart, and listed like REAL groups for filing upstream. They enter
neither side of §8. The producer's output is valid regex syntax, and the gated law is about syntax.

**Verdicts.** Each group gets one verdict, ordered:

1. **STUB**: the stub omitted or altered a named element of the call site, quoted with file and line. The
   element can be the acceptor, the options, the wrapper text, an argument literal, or a guard on the
   input's path to the call. The fix adds exactly that text. It never changes the producer, the domain or
   the acceptor. Each fix is recorded with its rejection counts before and after. After two STUB rounds the
   producer is UNSTUBBABLE.
2. **EMPTY-PATTERN**: the group is EMPTY and the pattern that reaches the acceptor is `""`. It is reported
   and enters neither side of §8. A built generator would drop `""`, and that is decided now, not after
   the data.

The two remaining verdicts read the input's well-formedness rule, which §5 records for each producer:
3. **REAL**: the minimal input is well-formed under the producer's recorded well-formedness rule (§5), and
   the pattern is rejected. The bug is the producer's.
4. **MALFORMED-INPUT**: the minimal input is malformed under that rule. In-domain examples are a trailing
   `\` where the notation reads `\` as an escape, and a glob brace the notation leaves unbalanced. A reversed
   range and an unknown POSIX class cannot occur in D4 or D4x.

**The judges.** Two independent judges decide each group, and a third decides where they disagree.

- **Evidence.** A REAL or MALFORMED-INPUT verdict quotes the rule it applies.
- **Calibration.** Before any candidate group is read, the judges classify two calibration groups, which
  must come out as #666 found them. `111d8bd`'s D4 `{a}` is REAL; its doc says "escape regex
  metacharacters". `e36da59`'s RAW2 `[` is MALFORMED-INPUT; its doc says "An *unbalanced* `[` … is a
  malformed glob". A miss stops the arm.
- **Ties.** A disagreement about how a rule applies resolves toward MALFORMED-INPUT, the side that blocks a
  build.

## 5. The hand-check of the pass

**Every population producer is judged, with no sample.** Each is shown with all of its QUALIFYING rows.

**COMBINATOR producers** are judged the same way: every distinct producer that is a COMBINATOR element of any
row in #666's universe, with vendored copies merged. If there are more than 40, the sample is
`random.Random(20261027).sample(L, 40)`, where `L` is that list sorted by subject, path relative to the
subject root, and line.

**AMBIGUOUS-Q rows** are judged too, as recall probe R4: every AMBIGUOUS row with at least one candidate that
would qualify.

**"Every caller"** in the verdicts below means every call the §1.3 resolver resolves to the producer, as the
census JSON lists them.

**Blindness.** The judges see:

- the producer's source;
- its rows;
- its doc comment and callers;
- these definitions.

They do not see §7 or §8, the pass's outcome label, running counts or precision results. QUALIFYING and
COMBINATOR producers are shuffled together in seeded order. Two independent judges decide each one, and a
third decides where they disagree.

**One ordered verdict set**, at producer level:

1. **NOT-A-PRODUCER**: the resolved declaration is not the callee.
2. **NOT-REACHING**: on no row does the output become part of the acceptor's pattern. An interpolation
   segment or a `+` operand counts as reaching.
3. **REGEX-INPUT**: by the doc, or by every caller's argument, the input is already in the acceptor's
   language. This is a combinator.
4. **TRANSLATOR**: by the doc, or by every caller's argument, the input is another notation, whether or not
   the body escapes it. Examples are a glob, plain text, a name, a path or a list of names.
5. **UNDETERMINED**: neither the doc nor the callers settle it.

**The well-formedness rule.** For each TRANSLATOR, the judges also record the input notation's
well-formedness rule. It is quoted, with file and line, from the doc comment or a caller. Failing that, a
default applies:

- for plain text, names and paths, every string is well-formed;
- for a glob, `[ ] { }` are syntax, and a bracket or brace the notation's own reading leaves unbalanced is
  malformed. Every other character is literal;
- for any other notation, or one the judges cannot name, the characters the producer's body reads
  non-literally are its syntax: a `case` arm, a replacement's `of:` text, a split separator. An opener among
  them left unclosed, or a trailing escape character, is malformed, and every other string is well-formed.
  The judges record which characters they took as syntax, quoting the body's lines.

The rules are frozen with the verdicts, before any stub runs.

## 6. Recall probes

These are reported, never added to N.

| probe | what it counts |
|---|---|
| **R1**, one hop through a wrapper | for each WRAPPER row whose enclosing scope is a `func`: its resolved callers' argument at each wrapped parameter's position, matched by walking the labels, classified by §1.2–§1.5. It counts producers reached only this way. An `init` or `subscript` wrapper is not followed. `MarkRule` is #666's named case, though it also runs through a static constant |
| **R2**, name and doc | String-result producers with String input and a transform read, whose name or doc contains `regex`, `regexp` or `pattern`, with no QUALIFYING caller |
| **R3**, unmatched spellings | bare `.init(pattern:`; `NSPredicate(format:)` with `MATCHES`; silent calls whose `options:` is an identifier |
| **R4**, AMBIGUOUS-Q | judged by §5; for each, whether the colliding declarations sit in different top-level targets. If N ≤ 10 < N + R4's TRANSLATORs, the doc says so in its first paragraph |
| **R5**, builder `var`s | for each REWRITTEN row, the calls in the binding's initializer and its mutations (`v += translate(part)`) that resolve to producers with String input and a transform read |
| **R6**, wrapped translators | for each OTHER-INPUT row, whether the resolved producer's body holds a listed operation and reads a stored `String` property declared in any type body of its owner's name |
| **R7**, what the transform rule drops | COMBINATOR-row producers §5 judges TRANSLATOR: plain text interpolated with no rewrite |

## 7. Predictions

A ratio whose denominator is 0 is scored n/a, with the reason.

| # | prediction |
|---|---|
| 1 | the pass and harness controls hold |
| 2 | the pass finds **≤ 10** population producers over #666's universe, vendored copies merged |
| 3 | both witnesses are in the population; SwiftUMLStudio at HEAD contributes `globPatternToRegex` (via `isMatching`) and `globRegexPattern` (via `expandGlobs`) |
| 4 | **≥ 70%** of population producers over #666's universe are judged TRANSLATOR |
| 5 | **≥ 60%** of N is in repositories the funnel group lists (a repository in both groups counts as funnel), as replacement chains were |
| 6 | over #666's universe, COMBINATOR rows outnumber QUALIFYING rows |
| 7 | **≥ 1** AMBIGUOUS row |
| 8 | under D4, after STUB fixes, **≥ 80%** of the stubbed producers in N have no D4 group other than EMPTY, on any stub |
| 9 | **0** REAL in-domain groups at HEAD |
| 10 | R1's producers, those with no direct QUALIFYING row, number no more than the population |
| 11 | upstream SwiftFormat contributes **0** population producers |
| 12 | **≥ 1** producer in R7 |
| 13 | **≥ 1** UNPARSED file in the universe |

## 8. The decision, fixed now

**N** is the number of population producers, over #666's universe (manifest, funnel and upstream), that
§5 judges TRANSLATOR and whose transform evidence is #666's three, directly or by delegation. Two kinds are
merged:

- vendored copies (§1.5);
- a producer whose #666's-three evidence comes only by delegation to another counted producer. It merges
  into a counted producer among its delegates, the first in source order if several are counted. So a
  translator and its thin wrappers count once.

N is also reported four other ways, none of which enters the decision:

- with WIDE producers (**N_wide**);
- with ESCAPE-ONLY producers (**N_escape**);
- unmerged;
- over the unmet group (**N_unmet**).

**BUILD** requires both of #666's conditions:

1. **N > 10.** That is the bar `replacement-chain-idempotence-census.md` set when it held a ten-function
   law as the Daikon trap, and it counted functions.
2. **Every in-domain refutation at HEAD of a stubbed producer in N hand-checks REAL, or there is none.**
   EMPTY-PATTERN groups are reported apart. At least two thirds of N's producers must be stubbed and run.
   Otherwise the outcome is **DECLINE (precision unmeasured)**.

**The outcome is the first that applies:**

1. **DECLINE (population)**: N ≤ 10.
2. **DECLINE (domain)**: some in-domain group of a stubbed producer in N is MALFORMED-INPUT. Then the balanced
   domain does not separate notation syntax from defects beyond the two witnesses.
3. **DECLINE (precision unmeasured)**: 3 × (N's producers stubbed and run) < 2 × N.
4. **BUILD**: otherwise.

**Concentration is reported, not gated.** It is the share of N in the largest repository. #666 sets no such
condition. The review flagged a draft clause that added one.

**Under every outcome:**

- the measurement doc, `regex-acceptor-census.md` in `measurements/`, is written beside `decoder-bypass-census.md`;
- `laws-from-mutation-survivors.md` entry 3 gets a dated annotation;
- both indexes get a row.

Under DECLINE, #666 closes with the PR. Under BUILD, it stays open for the build. Every REAL group is listed
in the doc with its subject revision, under any outcome, and offered to the user for filing upstream.

## 9. What this does not answer

- **A text census, not a parse.** Both arms of an `#if` are read. A producer behind a static constant or
  more than one wrapper hop is invisible: `MarkRule`'s path is both.
- **Acceptance is not correctness.** A pattern that compiles and matches the wrong thing passes. The
  companion law, "a glob with no glob syntax matches itself and nothing else", is out of scope, as #666
  says.
- **The balanced domain hides a symmetric miss.** ICU accepts `^(a)$` and `^[a]$`, so a translator that
  escapes neither half of a pair passes.
- **The false `idempotence` stays.** Withdrawing it is a domain-transfer veto, measured NO in
  `fixtures/domain-transfer-signal/RESULT.md`, and out of scope.
- **Where a generator would live is not decided**, and the gate does not need it.
- **Regex acceptors only.** #668 (`XMLParser`) and the URL, UUID and JSON arms #666 dropped are separate.
- **The OS's parsers are not pinned by the toolchain.** NSRegularExpression, Swift `Regex` and `String.range`
  come from the run machine's Foundation and `libswift_StringProcessing`. PC6 and PC7 pin what they did on
  the day of the run.

## 10. Disclosures before the freeze

- **The dry run.** The draft pass was run on the two witness repositories, SwiftUMLStudio `b8b1520` and
  SwiftAssist `6974842`, before the review. Their rows were read. It found two faults, fixed in the rule
  text above:
  1. `let pattern = #"…"#` came out STORED, because LITERAL read `E`'s own text rather than what reaches
     the call (C16);
  2. a parameter read inside an external call's arguments (`escapedPattern(for: s)`) marked the row
     WRAPPER (C6).
- **What the dry run showed.** SwiftUMLStudio's HEAD carries `globRegexPattern`, the third producer named
  in prediction 3. SwiftAssist's QUALIFYING row is `translate(glob:)`'s, as C3 expects.
- **Since the review**, the harness controls PC1–PC9 have been run, and they hold. The pass controls have
  been run, and so have the 43 rule-breaks of §3. No other subject has been read.

## Amendments

None yet. Amendments made before the pass reads any subject beyond §10's dry run are dated here, and none is
made after.
