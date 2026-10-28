# Does "the pattern a producer builds compiles" have a population? — No: three glob translators, one delegating to another (#666)

> **Status:** `measured` · **As of:** 2026-10-27

#666 asked for a law the catalogue does not have. When a producer's result is passed to a regex acceptor, the
caller's argument expression, with the producer's output in place, must compile. The law found G2, a real
defect, in SwiftUMLStudio's `globPatternToRegex` at `111d8bd`.

The issue set a gate before anything is built: **population, then precision, then a decision**. If the count
stays near the two functions its grep found, decline; build only if more than ten producers qualify and the
in-domain refutations at HEAD are real or absent.

This doc reports that gate. Everything it rests on was committed in this order:

| step | commit | what |
|---|---|---|
| scope | `28aece5f` | `docs/plans/regex-acceptor-census-scope.md`: the pass, 52 controls, the domains, the verdicts, 13 predictions and the decision rule, frozen before the pass read any subject beyond a disclosed dry run on the two witnesses |
| instruments | `3d008a27`, `810a1552` | `scripts/regex_acceptor_precision.py` (controls PC1–PC9) and `scripts/regex_acceptor_census.py` |
| census | `a0d92a7d` | `fixtures/regex-acceptor-census/census-2026-10-27.json` |
| hand-check | `d4c25e8d` | `fixtures/regex-acceptor-census/judgements.json`, sha256 `efa5aa7e…` logged before any stub ran |
| precision | `f873ec76` | the stubs, `precision-2026-10-27.json` and `refutation-judgements.json` |

```
DECISION: DECLINE (population)  N = 3 (bar: > 10)  population 3, all judged TRANSLATOR  stubbed 3 of 3
in-domain refutations at HEAD: 0 (D4 0, D4x 0)  N_wide 3  N_escape 3  N_unmet 0  concentration 2 of 3 (SwiftUMLStudio)
```

## The census

The pass starts at each acceptor call and follows the pattern argument through `let` bindings and unmutated
`var`s to whatever builds it. A producer is the function, or computed property, that the census resolves by
name and argument labels. The acceptors are `NSRegularExpression(pattern:)`, `Regex(_:)`, and the silent
APIs that take `options: .regularExpression`.

| group | repositories | files | acceptor calls | population |
|---|---:|---:|---:|---:|
| manifest corpora, read through their manifest source directories (the 5 that are also funnel repositories from their roots, §1.5) | 22 | 3,078 | 56 | 0 |
| the other funnel repositories, read from the root | 14 | 1,151 | 27 | **3** |
| upstream nicklockwood/SwiftFormat `75e09c0e`, `Sources/` | 1 | 193 | 9 | 0 |
| **#666's universe** | **37** | **4,422** | **92** | **3** |
| unmet subjects, outside the decision | 5 | 961 | 9 | 0 |

**What builds a regex pattern in this corpus is mostly a literal.**

| outcome | calls | what it means |
|---|---:|---|
| LITERAL | 68 | only literals reach the call |
| STORED | 14 | a stored property, a static constant, or a loop over one |
| WRAPPER | 9 | the enclosing function's own parameter, which makes it a wrapper acceptor |
| EXTERNAL | 5 | only a call outside the subject: 4 are Foundation's `escapedPattern(for:)` and 1 a `joined(separator:)` |
| QUALIFYING | 3 | a subject producer with String input and a rewriting operation |
| AMBIGUOUS | 2 | a name with several declarations (8 candidates on swift-format's row, 2 on SwiftProjectLint's), each a String property with no String input, so none would qualify |
| COMBINATOR, OTHER-INPUT, REWRITTEN, LITERAL-MODE | 0 | |

- **By acceptor:** 56 silent calls, 37 `NSRegularExpression`, 8 `Regex`. 47 of the 56 silent calls pass a
  literal.
- **By handling:** of the 33 calls that do not compile a literal, 10 force-try (`try!`), 9 return `nil` on
  rejection, 2 catch it, 2 propagate it, 9 are silent and 1 could not be classified. Only 14 of the 42
  repositories make any acceptor call.
- **The whole of #666's universe has the same two functions its grep found.** The third producer is new. It was
  added after the issue, delegates to one of them, and substitutes tokens of its own.

## The population

| producer | subject at HEAD | input | evidence | its caller | verdict |
|---|---|---|---|---|---|
| `GlobTool.translate(glob:)` | SwiftAssist `6974842` | the `glob` parameter | a per-character loop (`glob[`) | `"^" + translated + "$"` in a `do`/`catch` | TRANSLATOR, glob |
| `String.globPatternToRegex()` | SwiftUMLStudio `b8b1520` | the receiver | a replacement (`replacingOccurrences`) | `isMatching(searchPattern:)`, `try?` | TRANSLATOR, glob, rule from its doc |
| `globRegexPattern(anchor:pattern:tokens:)` | SwiftUMLStudio `b8b1520` | `anchor` and `pattern` | its own token `replacingOccurrences`, and delegation to `globPatternToRegex` | `expandGlobs`, in a `do`/`catch` | TRANSLATOR, glob plus a literal path |

- **`globRegexPattern` is new since #666.** SwiftUMLStudio added it in `ee82090` (2026-10-13), and `expandGlobs`
  now builds its pattern through it. Before, `expandGlobs` rewrote a `var regex` in a loop: control C2 holds
  that case at `e36da59`.
- **N is 3.** The frozen thin-wrapper merge does not apply to `globRegexPattern`, because its own body
  substitutes tokens with `replacingOccurrences`. If it were merged into its delegate, N would be 2. Either
  way the bar is more than 10.
- **The side counts move nothing.** N with WIDE producers is 3, with ESCAPE-ONLY producers 3, unmerged 3, and
  over the unmet group 0.

## The hand-check

Four blind packets went to two independent judges each. Judge A read the declaration and its doc first;
judge B started from the call sites and callers. Neither saw the predictions, the decision rule, the census
JSON or the pass's labels. **They agreed on all four, so no tiebreak ran.**

**What the judges read beyond §5's list.** §5 lists the producer's source, its rows, its doc, its callers and
the definitions. Each judge could also read the two subject repositories, and some cited their tests, a tool
descriptor and a grep as corroboration. Every TRANSLATOR verdict also rests on the producer's own doc or
code.

- **The three population producers are TRANSLATORs from glob notation.** Each judge also recorded the input's
  well-formedness rule.
  - **`globPatternToRegex`'s rule is quoted from its own doc** (`String+Extensions.swift:88-93`): "An
    *unbalanced* `[` still produces an invalid pattern, and that is a malformed glob rather than a translation
    bug".
  - **The other two take the frozen default glob rule**, which neither one's doc nor caller states.
    `globRegexPattern`'s `anchor` takes the plain-path default, because its doc calls the anchor "a literal
    path".
- **The one COMBINATOR element is NOT-REACHING.** That is `ToolCall.string(_:)`, the argument lookup that feeds
  `translate(glob:)`. It reaches the pattern only through `translate`, so R7, translators the transform rule
  drops, is empty.

## Precision at HEAD

Every judged TRANSLATOR was stubbed and run: four stubs for three producers. Each producer's body is
byte-identical to its HEAD source, the stubs differing only in a shell type around `translate`.

**`globRegexPattern` was driven once through each String parameter**, with the other's representative
recorded in the stub. `tokens` was fixed to `[:]`, because at the call site it is not a literal. So its own
token substitution, the evidence that keeps it out of the thin-wrapper merge, never ran (see *Found in
review*).

Each stub was compiled with swift.org 6.4.1 against the macOS 27.0 SDK and run on macOS 27.2 (`26B123`),
after the harness controls PC1–PC9 held again.

| stub | D4 (11,177) | D4x (31,115) | RAW2 (273) | FREE3 (2,955) |
|---|---:|---:|---:|---:|
| `translate(glob:)`, wrapped as its caller wraps it | 0 | 0 | 32, all `[` | 0 |
| `globPatternToRegex()` | 0 | 0 | 32, all `[` | 0 |
| `globRegexPattern`, driving `pattern` | 0 | 0 | 32, all `[` | 0 |
| `globRegexPattern`, driving `anchor` | 0 | 0 | 0 | 0 |

- **No in-domain refutation, no trap, no declined input, no EMPTY group.** Clause 2 holds, with refutations
  absent, but clause 1 has already failed.
- **The balanced domain does on HEAD what #666's transcription said it does on the two witnesses.** Every D4
  and D4x input compiles on all four stubs. Unfiltered, RAW2 rejects exactly its 32 inputs that contain `[`
  on the three stubs that drive a glob, and none on the `anchor` stub. All 32 lie outside the balanced domain,
  and each shrinks to the single input `[`.

**The `[` groups were judged as §4.3 prescribes, though §8 does not read them.**

- **Calibration first.** Before any candidate group, two judges classified the two calibration groups and
  matched #666 on both: `111d8bd`'s D4 `{a}` is REAL, and `e36da59`'s RAW2 `[` is MALFORMED-INPUT.
- **Then the three `[` groups.** Each went to two judges, who agreed: **MALFORMED-INPUT**, an unbalanced
  bracket in a glob. The rule comes from `globPatternToRegex`'s own doc, and from the frozen default for the
  other two.
- **The patterns that reach the acceptor** are `^[$` and `^\/repo\/Sources\/[$`.

The verdicts are in `refutation-judgements.json`.

## The predictions, scored

| # | prediction | result | |
|---|---|---|---|
| 1 | the pass and harness controls hold | 52 controls and PC1–PC9 | ✅ |
| 2 | ≤ 10 population producers over #666's universe | **3** | ✅ |
| 3 | both witnesses in the population, and SwiftUMLStudio contributes `globPatternToRegex` and `globRegexPattern` | yes | ✅ |
| 4 | ≥ 70% judged TRANSLATOR | 3 of 3 | ✅ |
| 5 | ≥ 60% of N in funnel repositories | 3 of 3 | ✅ |
| 6 | COMBINATOR rows outnumber QUALIFYING rows | **0** against 3 | ❌ |
| 7 | ≥ 1 AMBIGUOUS row | 2 | ✅ |
| 8 | ≥ 80% of stubbed producers in N have no D4 group but EMPTY | 3 of 3 | ✅ |
| 9 | 0 REAL in-domain groups at HEAD | 0 | ✅ |
| 10 | R1 adds no more producers than the population | 0 | ✅ |
| 11 | upstream SwiftFormat contributes 0 | 0 | ✅ |
| 12 | ≥ 1 producer in R7 | **0** | ❌ |
| 13 | ≥ 1 UNPARSED file | **0** | ❌ |

**10 of 13 held, but three of them were not blind.**

- **Prediction 3** restates the disclosed dry run.
- **Predictions 8 and 9** were settled for two of the three producers before the freeze. Their HEAD bodies are
  byte-identical to the PC3 and PC4 control bodies, which ran then with D4 = D4x = 0. The third producer's
  stub, with `tokens = [:]`, reduces to the second behind an escaped literal prefix.

**Two of the misses share a cause.** The scope expected combinators: `MarkRule`-style wrappers that
interpolate a regex fragment. The corpus has no COMBINATOR row (6), and so no R7 producer (12). **The third
miss (13) is separate:** no file's regex literals defeated the masker.

## What else the census saw

None of this enters N.

- **R1, one hop through the 9 wrapper acceptors: 0 producers.** The fixture records only producers. By hand:
  - **The in-subject callers** pass literals, stored patterns, or their own parameter:
    - swift-foundation's `_range(of:options:)` forwards its search string into
      `RegexPatternCache.regex(for:)`;
    - SwiftFormatRuleStudio's `firstCapture` forwards its `pattern` into `allCaptures`.

    Both are second hops, which R1 does not follow.
  - **Harmonize's three `containing regex: String` filters** are public API with no caller in its source
    directory.
  - **`MarkRule`'s path**, #666's named case, is in SwiftLint, which no group holds.
- **R2, name and doc:** 5 String producers whose name or doc says `regex`, `regexp` or `pattern` but that feed
  no acceptor. They are `normalize`, `plainStringContent`, `makeID`, `patternMarkdown` and
  `processKebapCaseRegex`. The last is also a wrapper acceptor: it compiles its own `pattern` parameter, and
  its output feeds no acceptor.
- **R3, spellings the pass does not match:** 6 silent calls pass their options through a variable, 5 in
  swift-foundation and 1 in SwiftFormat. There are no bare `.init(pattern:` calls and no `NSPredicate` with
  `MATCHES`.
- **R4, R5 and R6 are empty.** Neither AMBIGUOUS row has a candidate that would qualify, so R4 judged nothing.
  No REWRITTEN row exists, and no OTHER-INPUT row exists.
- **Upstream SwiftFormat** translates globs inline in `expandGlobs` and compiles with `try!` (`Globs.swift:118`).
  As #666 said, no producer function exists for this template to see. The row reads STORED, not REWRITTEN,
  because of an instrument limit given below.
- **Two interpolations into a regex**, seen in passing, not judged, and both safe as written:
  - swift-docc's `DataAssetManager` builds `"(?!^)\(self.darkSuffix)(?=[.$]|@)"` from
    `private let darkSuffix = "~dark"`, a literal with no metacharacter;
  - SwiftProjectLint's `DefaultIsolationDetector` builds `#"\b\#(name)\b"#` from a closure parameter that holds
    a Swift identifier, which cannot carry a regex metacharacter.

## Found in review: a brace glob SwiftUMLStudio cannot compile

This is outside the census. It is outside D4, because the stubs fix `tokens = [:]`, and it was not judged. It
is listed so it can be filed.

**The defect.** `expandGlobs`' brace step (SwiftUMLStudio `b8b1520`, `Glob.swift:160-167`) escapes each brace
option with the pre-fix class `[.+(){\\|]`, and it never expands the option's own wildcards. With the tokens it
builds, `globRegexPattern` turns the well-formed glob `{*.swift,*.h}` into `^\/repo\/Sources\/(*\.swift|*\.h)$`.
ICU rejects that: nothing to repeat. `expandGlobs`' `catch` logs the error and falls back to a literal path,
so the glob matches nothing. This was verified by compiling HEAD's brace step and `globRegexPattern`
together.

**The related defect #666 noted is still there.** `{a^b,c}` becomes `(a^b|c)`, which compiles and never
matches `a^b`. `{a,b}.swift` and `{a.b,c}` are fine.

## Disclosures and instrument limits

- **Before the freeze**, the draft pass was dry-run on the two witness repositories, and their rows were read
  (scope §10).
- **The first run crashed** in `run()`'s bookkeeping, on a field the conformance fix had renamed, before it
  wrote anything. The per-subject tallies it had printed were seen: the 22 manifest corpora and 8 funnel
  repositories, all with population 0.
- **Four bookkeeping fixes followed, that one among them.** Each later run was diffed against the first run
  to write output: rows, population, probes and every producer field except `callers` are identical. The
  other three:
  - R2's delegates and the upstream root changed from absolute to relative paths;
  - the caller lists' paths did the same;
  - **the caller lists changed.** A filter §1.3 does not have now drops each declaration's own line, and any
    implicit-member or enum-case use that shares a method's name. `ToolCall.string(_:)` went from 50 callers,
    the cap, including `.string(…)` enum constructions, to 31. The three translators lost only their own
    declaration lines.
- **The judges read the filtered caller lists.** Their packets were built from a re-run after that fix. Their
  declarations, rows and callers are the committed fixture's. The fixture was committed after the judges
  launched. No verdict could move: `ToolCall.string(_:)` was judged NOT-REACHING on its row.
- **Frozen limits (scope §9).** A text census reads both arms of an `#if`. A producer behind a stored or static
  constant, or more than one wrapper hop away, is invisible, so the 14 STORED rows say nothing about what
  built their constants. A hand look at several found only literals.
- **Instrument limits found by the run.** Neither moves N.
  - **Closure parameters.** The pass reads a closure parameter as a property read: the SwiftProjectLint row
    above is AMBIGUOUS between two unrelated `name` properties.
  - **Multi-name declarations.** It does not follow a name bound in `var a = …, b = …`: SwiftFormat's
    inline-translation row is STORED where it is REWRITTEN.
- **The universe is narrower than #666's grep.** The grep searched whole repositories: 47 of them, 13,353
  non-test files, SwiftLint among them.
  - **#666's universe here** is 37 repositories and 4,422 files, or 42 and 5,383 with the unmet group.
  - **How it reads them.** It reads 17 manifest corpora through their manifest source directories, the
    convention every census here uses, and the rest from their roots or `Sources/`.
  - **What it cannot see.** A producer outside those 17 corpora's source directories is invisible. So is any
    producer in a repository the grep read that no group holds, such as SwiftLint.

## So what

- **DECLINE, on population.** Outside two glob tools, no subject hand-translates another notation into a regex.
  - **The two glob tools.** The 37 repositories of #666's universe hold three translators, all glob tools, one
    of which delegates to another.
  - **Everywhere else**, a pattern is a literal (68 of 101 calls) or a stored constant (14). Otherwise it is a
    regex the caller supplies (9 wrapper acceptors) or data escaped with Foundation's `escapedPattern(for:)`
    (4).
  - **The pattern matches escaping.** Translating into a regex is application code here, as escaping for
    output formats was (`replacement-chain-idempotence-census.md`).
- **Nothing in the population is rejected in-domain at HEAD.** G2 was fixed in `8fc0cde`.
  - **In the domain**, none of the three rejects an input under the balanced domain.
  - **On RAW2**, each rejects only inputs containing `[`, which its doc or the default glob rule calls
    malformed.
  - **The bounds.** The claim is bounded by the domain and by the `tokens = [:]` representative. The brace
    glob above shows what lies past both.
- **What would reopen it** is a corpus with more than ten translators into an acceptor's language. More glob
  tools would do, or generated-pattern code that does not write patterns as literals. The decline covers
  regex translators only. #668 is the same law with `XMLParser`, a separate population, and URL, UUID and
  JSON were dropped by #666's grep.
- **What it leaves standing.** Both witnesses were last seen offered a false `idempotence`. That was not
  re-checked at HEAD, and this census does not touch it. Withdrawing it is the domain-transfer veto measured
  NO in `fixtures/domain-transfer-signal/RESULT.md`, and out of scope here.

## Reproducing

```
python3 scripts/regex_acceptor_census.py --self-test
python3 scripts/regex_acceptor_census.py run census.json SwiftFormat=<a clone of nicklockwood/SwiftFormat at 75e09c0e>
python3 scripts/regex_acceptor_census.py packets census.json packets/ SwiftFormat=<the clone>
python3 scripts/regex_acceptor_precision.py controls
python3 scripts/regex_acceptor_precision.py run precision.json fixtures/regex-acceptor-census/stubs/*.swift
```

The run asserts the frozen universe of scope §2. It needs the manifest corpora, the funnel repositories and
the unmet subjects checked out where `budgeted_truncation_census.subjects()` finds them, so on another machine
the assertion names what differs.
