# Road-test — SwiftMarkdownWiki (2026-09-11)

> **Status:** `measured` · **As of:** 2026-09-11
> **Method:** [`docs/plans/corpus-pipeline-walk-scope.md`](../plans/corpus-pipeline-walk-scope.md)

First subject of the corpus pipeline walk. The question is not *can the loop find
bugs* — it is **where does a property test we predicted fail to arrive, and at
which stage did it die** (S0–S8 in the scope doc).

The subject has **no property tests of any kind**: zero hits for `propertyCheck`,
`PropertyLawKit` or `forAll` across 184 source and 61 test files. Nothing here has
been tuned against the toolchain.

## Instrument

| | |
|---|---|
| SwiftProjectLint | `e9b01846` (clean) |
| SwiftInferProperties | `e3f714ed` (see note) |
| SwiftPropertyLaws | `3d31fc2` (clean) |
| SwiftEffectInference | `1b62e76` (clean) |
| **Subject** | SwiftMarkdownWiki `c71c47b` (clean) |
| Swift | 6.3.3 (swiftlang-6.3.3.1.3), arm64-apple-macosx26.0 |

**Note on the SwiftInferProperties pin.** The session-start check reported one
dirty path in that repository and **did not record its name**; by the end of the
walk the tree was clean at the same HEAD apart from this document and its plan.
The file cannot now be identified. Nothing in the walk reads that repository's
working tree — every `swift-infer` invocation ran the committed binary at
`.build/debug/swift-infer` — so no measurement here depends on it. Recorded
because a pin with an unidentified modification is a weaker pin than one without,
and the next walk should capture `git status` in full rather than a line count.

## The seed manifest

`CLI ~/xcode_projects/SwiftMarkdownWiki --format pbt-seeds` — 56s, exit 0,
**101 seeds**, schema version 2.

| field | distribution |
|---|---|
| `rule` | Pure Function Property-Test Candidate 83 · Pure Closure Property-Test Candidate 17 · Extractable Total Kernel 1 |
| `kind` | pure-function 42 · restricted-function 41 · extractable-kernel 18 |
| `role` | *(none)* 59 · predicate 22 · normalizer 14 · comparator 4 · transform 2 |

**Two observations to carry into the walk, both recorded before any `swift-infer`
run.**

**(a) All four comparator seeds are `extractable-kernel`.** They are anonymous
closures — `$0.title.localizedStandardCompare($1.title) == .orderedAscending` and
friends — and the manifest names them by their *enclosing function*
(`buildNodes`, `sources`, `enumerateNotes`, `sortNotes`). So the scope doc's
"comparators first" instruction does not survive contact with this subject: the
strict-weak-ordering law has no named subject to attach to, and focusing
`swift-infer` on `buildNodes` focuses it on a function that is not a comparator.
This is a Queue B confound, not a Queue A row, and the scope doc is corrected
accordingly. Walked separately below as its own finding.

**(b) Three of those four closures are the same comparator, written out three
times** — `GraphData.swift:40`, `BacklinkIndex.swift:34`, `VaultManager.swift:243`
all spell `localizedStandardCompare(…) == .orderedAscending`. Independent of any
tool: `localizedStandardCompare` is case- and width-insensitive, so two notes
titled `README` and `readme` compare `.orderedSame`, become an incomparable pair,
and their relative order falls to a sort Swift does not promise is stable. That is
the identical shape the corpus sweep has now found six times in
SwiftInferProperties (a comparator that stops at `line` and ignores `column`).
**Predicted before running anything; unverified.**

---

## Subject 1 — `WikilinkParser.parse`

`SwiftMarkdownWiki/Linking/WikilinkParser.swift:5` · seeded as `pure-function`,
role *(none)* · internal `enum`, reachable from tests via `@testable import`.

```swift
static func parse(_ source: String) -> [WikilinkRef] {
    source.matches(of: WikilinkPattern.regex).map { match in
        WikilinkRef(target: String(match.output.1),
                    alias: match.output.2.map(String.init),
                    range: match.range)
    }
}
```

`WikilinkRef` is `{ target: String, alias: String?, range: Range<String.Index> }`,
`Equatable`. The grammar is shared with the renderer via `WikilinkPattern.regex`,
`/\[\[([^\]\[|]+)(?:\|([^\]\[]+))?\]\]/`.

### Prediction — written 2026-09-11, before any `swift-infer` invocation

| # | Predicted law | Refutable? | A plausible implementation it rejects |
|---|---|---|---|
| **L1** | **Range fidelity.** For every `r` in `parse(s)`: `s[r.range] == "[[" + r.target + (r.alias.map { "\|" + $0 } ?? "") + "]]"` | **yes** | One returning the *inner* range (brackets excluded), or trimming whitespace off `target` while keeping the outer range — both leave every field individually plausible and the triple inconsistent |
| **L2** | **Document order, no overlap.** Ranges strictly ascending and pairwise disjoint | **yes** | Any implementation routing matches through a `Set`/`Dictionary`, or one that rescans from `startIndex` per match |
| **L3** | **Capture hygiene.** `target` contains none of `[`, `]`, `\|`; `alias` contains none of `[`, `]` | **yes** | A hand-rolled parser splitting on the *last* `\|` rather than the first |
| **L4** | **Cross-function: rendering consumes every link.** `WikilinkParser.parse(WikilinkHTMLRenderer(…).render(s)).isEmpty` | **yes** | `replaceWikilinks` using `firstMatch` instead of `matches`, or emitting a `displayText` that can itself re-form `[[…]]` |
| — | `parse(s) == parse(s)` (determinism) | **no** | *nothing.* Recorded here so that if the tool returns only this, the row scores as a **miss**, per the scope doc |

**L4 is the one I most expect the pipeline to miss**, because its subject is a
*pair* of functions in different types and neither one alone owes it.

**A hazard noticed while reading, not a predicted law:** `WikilinkRef` is
`Equatable` over a `Range<String.Index>`, which is only meaningful relative to the
string it was derived from. Two refs from different sources can compare equal or
unequal for reasons having nothing to do with the wikilinks. Not scored; recorded
because it is the kind of thing a value-semantics check should have an opinion on.

### Result — 0 of 4

`swift-infer discover --sources SwiftMarkdownWiki --include-possible` · 3.1s ·
exit 0 · **43 suggestions** over the whole subject. `parse` received exactly
**one**:

| template | score | tier |
|---|---|---|
| `input-totality` | 30 | Possible (shown by default — role-entailed) |

*"`parse` leads with the interpretation verb `parse` and takes a `String` — it
reads the argument as a structure, so it owes TOTALITY over every string that
type admits."* The law is **does not trap**.

| predicted | proposed? |
|---|---|
| L1 range fidelity | **no** |
| L2 document order, no overlap | **no** |
| L3 capture hygiene | **no** |
| L4 rendering consumes every link | **no** |

**Stage: S3 (catalog gap), with an S4 rider that is the real finding.** The three
laws worth having here relate the *output's* fields back to the input — a slice
equals a known reconstruction, ranges ascend and do not overlap, a sibling
function consumes what this one finds. None is expressible as a signature
pattern over `(String) -> [WikilinkRef]`, and the catalog is signature- and
verb-driven. `input-totality` is the only law a shape-matcher can reach here,
and the tool's own warning on it says so out loud: *"A GENERATOR OF REALISTIC
INPUT WILL NEVER FIND THIS."*

---

## Finding 1 — the docstring stated L2 verbatim, and a weaker law suppressed it

`parse`'s docstring is *"Parses all wikilink references from raw Markdown source,
**in document order**."* That sentence is L2. `discover` runs
`--docstring-advice` **on by default**, printed a *"Reference definitions from
docstrings"* section for **86 functions** in this subject — and `parse` is not
one of them.

Read from `DocstringAdvisor.advisory(forFunctionWith:suggestions:)`, not inferred
from the output:

1. gate — `isContract(doc)` — **passes**: the cue list contains `"parses"`.
2. `referenceDefinitionHungryTemplates` is `["predicate", "comparator"]` — no match.
3. lifted-test origin — none.
4. `!suggestions.contains(where: Refutability.isWorthSurfacingBelowCut)` — **false**,
   because `isWorthSurfacingBelowCut == isRefutable && isRoleEntailed`, and
   `input-totality` is in `roleEntailedTemplates`.
5. → branch 4: *"A self-contained role-entailed law already serves the function.
   Repeating the docstring would only cost trust."* **No advisory.**

**The generalisation is the finding, and it is structural rather than a tuning
miss.** `input-totality` fires on *every* interpretation-verb function — that is
its trigger. So for the whole parse / decode / read family, branch 4 always wins
and **the docstring advisory can never fire**. That is the one family where a
reference definition is most needed, because it is the family whose real laws
(fidelity, ordering, round-trip) the templates cannot name.

Measured across all four `input-totality` subjects in this run:

| function | docstring states a contract? | in the 86-function advisory? |
|---|---|---|
| `WikilinkParser.parse` | yes — *"in document order"* | **no** |
| `FrontMatter.parse(from:)` | yes — *"the document body with the front matter stripped"* | **no** |
| `PluginManifest.decode(from:)` | yes (weak) — *"Decodes and validates…"* | **no** |
| `SearchService.parseQuery` | no docstring | no (correctly — gate 1) |

Four of four suppressed; three of four have contract-cue docstrings; two of those
state genuinely refutable contracts the templates did not reach.

The branch-4 comment is right that repeating a docstring next to a law that
already serves the function costs trust. The premise is what fails: "does not
trap" does not serve a parser. **Owed is not the same as informative**, and
`isWorthSurfacingBelowCut` is being asked to carry a distinction it was not built
to make — it exists to keep a *conjecture* from crying wolf, and here it is
gating a *strictly stronger owed law* out of the report.

Filed as
[#420](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/420), after
Subject 4 supplied the positive control that narrowed it.

---

## Finding 2 — seeding traded 8 conjectures for 34 tautologies

The same run, focused through the 101-seed manifest:

| | suggestions | determinism (`f(x) == f(x)`) |
|---|---|---|
| unseeded | 43 | 0 |
| `--seeds smw-seeds.json` | **69** | **34** |

Focusing the run **raised the count by 60%** and every added row is the
tautology. Set difference, both directions:

**Lost by focusing (8), and every one of them is a conjecture — no role-entailed
law was lost:**

| template | subject | worth losing? |
|---|---|---|
| `associativity` / `binary-idempotence` / `commutativity` | `union(_:_:)` `(NSRange, NSRange) -> NSRange` | all three true of the code, but it is `private` — the unseeded run said no test can call it. Defensible loss. |
| `idempotence` | `htmlEscaped` | **a gain.** `&` → `&amp;` → `&amp;amp;`: escaping is *not* idempotent, so this law is false of correct code. |
| `idempotence` | `SplitMix64.next()` | **a gain**, same reason — an RNG step is not idempotent. |
| `idempotence` | `filtered(_:)` `([PluginLogEntry]) -> [PluginLogEntry]` | plausibly true and refutable. **A real loss.** |
| `measure-non-negativity` | `visibleNodeCount` | true but near-vacuous (`.count` is ≥ 0 by construction). |
| `role-postcondition` | `clamped(to:)` | result within bounds — the law that type exists for. **A real loss.** |

So the honest accounting is **not** "8 refutable laws destroyed": it is two real
losses, two gains, three defensible, one vacuous — and **34 rows that no wrong
code can fail**. The cost of seeding here is the inflation, not the deletion. A
reader handed 69 suggestions of which 34 cannot fail is worse off than one handed
43.

This is the §16.6.1 shape (a focus filter returning tautologies in place of
content) recurring in a milder form, and it is worth recording precisely *because*
it is milder: the earlier instance discarded the only refutable law in the run.

---

## Finding 3 — the linter is blind to extensions on types it does not declare

Two of the eight lost suggestions — `htmlEscaped` and `clamped(to:)` — were lost
because they are **not in the manifest at all**. Both live in the subject's only
two files that extend a non-project type:

- `Editor/HTMLEscaping.swift` — `extension String { var htmlEscaped: String }`
- `Editor/NSRange+Clamp.swift` — `extension NSRange { func clamped(to:) -> NSRange }`

**Both contribute zero of the 101 seeds.**

Root cause, read from
`PropertyTestCandidacy.enclosingTypeContainer(of:knownValueTypes:)`: for an
`ExtensionDeclSyntax` it returns a container with
`isValueType: knownValueTypes.contains(extendedBase)`, and `knownValueTypes` is
documented as *"project types declared as `struct` or `enum`"*. `String` and
`NSRange` are declared in the standard library and in Foundation, so
`isValueType` is **false**, `TypeStoredPropertyCollector` finds no declaration to
read stored properties from, and `SelfAccessAnalyzer` has no basis to resolve the
`self` access — the candidate is dropped.

**The bias runs exactly the wrong way.** An extension on `String`, `NSRange`,
`Array` or `Int` is the *easiest* possible property subject: the carrier is a
value type, a generator is trivially derivable, and the function is pure by
construction because there is nowhere impure to reach. Those are precisely the
ones a project-declared-types-only gate cannot see.

n = 2 in this subject, so the corpus evidence is thin — but the claim rests on
the mechanism in the source, not on the two cases, and it predicts the same
silence in all 26 repositories. **Worth measuring against the corpus before
filing**, which is the next step rather than a conclusion.

---

## Running tally

| stage | rows | note |
|---|---|---|
| S0 | 2 | extensions on non-project types never seeded |
| S3 | 4 | L1–L4 on `parse` — no template names an output-to-input relation |
| S4 | 1 | docstring advisory suppressed for the whole parse/decode family |
| S1 | 0 | |
| S2, S5–S8 | 0 | not reached — nothing got as far as emission |

**Nothing has been emitted, compiled or run yet.** Stages S5–S8 are untested on
this subject, and no claim here touches them.

---

## Subject 2 — `FrontMatter.parse(from:)`

`SwiftMarkdownWiki/Editor/FrontMatter.swift:17` · `(String) -> (frontMatter: Self, body: String)`
· internal `struct`, reachable via `@testable import`.

```swift
/// Parses YAML front matter delimited by `---` lines.
/// Returns the parsed fields and the document body with the front matter stripped.
static func parse(from source: String) -> (frontMatter: Self, body: String)
```

Chosen as the second row because it is the same family as Subject 1 — so
Finding 1 gets a second data point — and because its docstring states a
**partition** claim ("the document body with the front matter stripped") that is
stronger than anything a signature matcher can reach. Unlike Subject 1, this row
is walked **all the way to S8**: the predicted laws get written, compiled and
run.

> **Declared contamination.** At prediction time I already knew, from Finding 1's
> cross-check, that this function received an `input-totality` suggestion and is
> absent from the 86-function docstring advisory. I did **not** know whether it
> received anything else. The predictions below are therefore honest about the
> laws and not about the count.

### Prediction — written 2026-09-11, before reading its suggestion block

| # | Predicted law | Refutable? | A plausible implementation it rejects |
|---|---|---|---|
| **P1** | **Guard-path identity.** `!s.hasPrefix("---")` ⟹ `parse(from: s) == (FrontMatter(), s)` — the body is the source *unchanged* | **yes** | One that normalises, trims or re-joins the body on the no-front-matter path |
| **P2** | **Body is a suffix of the source.** `s.hasSuffix(parse(from: s).body)` for every `s` | **yes** | Trimming the body, re-joining with `\r\n`, or dropping *all* leading blank lines rather than one. **This is the docstring sentence made checkable.** |
| **P3** | **Tag hygiene.** No tag is empty, and every tag equals its whitespace-trimmed self | **yes** | Dropping the `.filter { !$0.isEmpty }` or the per-element trim |
| **P4** | **Title is unquoted.** `title` never begins or ends with `"` or `'` | **yes** | Dropping the quote trim, or trimming only one of the two characters |
| — | idempotence on the body | **not a law** | Predicted **false**: a body that itself begins with `---` gets a second block stripped. Recorded in advance so that if a template proposes it, that is a cry-wolf rather than a find. |

**Suspected defect, predicted before running anything and separate from the tool
measurement:** `parseFields` reads `tags` only in the inline form
`tags: a, b, c`. The block form —

```yaml
tags:
  - swift
```

— gives `rawValue == ""` (so `tags == []` after the empty filter) and the `- swift`
lines carry no colon, so they `continue`. Block-form tags are **silently dropped**
by a function whose docstring says "YAML". Claim about the code, not about the
pipeline; adjudicated below.

### Result — 0 of 4, and Finding 1 reproduces exactly

One suggestion, identical in kind to Subject 1:

| template | score | tier |
|---|---|---|
| `input-totality` | 30 | Possible (role-entailed) |

P1–P4: **none proposed.** Absent from the 86-function docstring advisory, for the
branch-4 reason established in Finding 1. Two subjects, two identical outcomes,
same mechanism — the parse/decode family gets "does not trap" and nothing else.

### S5–S8: the laws written by hand, walked, and mutated

The tool proposed nothing to emit here beyond the totality law, so **S5 and S6
are still untested on this subject** — what follows exercises S7 and the verdict
stage only, and does it with hand-written laws rather than emitted ones.

`SwiftMarkdownWikiTests/FrontMatterPropertyLawTests.swift`, new, untracked. The
document space is a product of four choices — 6 heads × 6 YAML blocks × 4 closers
× 7 bodies = **1008 documents, walked exhaustively**, so the laws say *holds*
rather than *held for a thousand draws*. The subject has no property-testing
dependency and needed none at this size. Every law carries a vacuity guard
asserting its antecedent actually fired; all four fired.

**P1–P4 all pass.**

**Then the violators, because a green law is a claim.** Four reversible patches
to `FrontMatter.swift`, each run against both the new laws and the seven
pre-existing example tests:

| mutant | killed by the laws | killed by the 7 examples |
|---|---|---|
| guard path trims the body | `documentWithoutFrontMatterIsReturnedUnchanged`, `bodyIsAlwaysASuffixOfTheSource` | **survived** |
| body re-joined with `\r\n` | `bodyIsAlwaysASuffixOfTheSource` | `stripsBodyCorrectly` |
| empty tags not filtered | `tagsAreTrimmedAndNonEmpty` | **survived** |
| only `"` trimmed from a title, not `'` | `titleIsUnquoted` | **survived** |

**4 of 4 to the laws; 1 of 4 to the examples.** The three survivors are the
shape the examples were always going to miss: `noFrontMatterReturnsSourceUnchanged`
uses a source with no leading whitespace, `parsesTags` uses a list with no empty
component, and `quotedTitleIsUnquoted` uses a double quote. Each example is
correct and each is one point in a space where the bug lives somewhere else.

**The fourth mutant survived the first run, and that is recorded rather than
smoothed over.** The original space had no single-quoted title, so
`charactersIn: "\"'"` and `charactersIn: "\""` were indistinguishable to every
law in the file. Adding `["title: 'Single'"]` to `yamlBlocks` (1008 documents,
was 840) kills it. The comment at the space says so, because a reader tidying
that entry away would silently retire a law.

---

## Finding 4 — the real defect is one no predicted law caught

`parseFields` reads `tags` by splitting `rawValue` on `","`. YAML spells a
sequence three ways, and the function understands one:

```
tags: math, demo      ->  ["math", "demo"]     inline    ✓
tags: [math, demo]    ->  ["[math", "demo]"]   flow      ✗ brackets kept
tags:                 ->  []                   block     ✗ silently empty
  - math
```

**The flow form is live in shipped data.** `ExampleVault/Math Notes.md` and
`ExampleVault/Syntax Demo.md` both write `tags: [math, demo]`, so the app's own
sample vault produces tags reading `[math` and `demo]`, which flow into
`GraphData`'s tag set and the graph's tag filter. The block form fails silently
because `- math` carries no colon, so `parseFields` `continue`s past it.

**P3 passes on this.** "No tag is empty, and every tag equals its trimmed self"
is perfectly satisfied by `["[math", "demo]"]`. The law I predicted, wrote,
confirmed refutable with a mutant, and watched go green is **true of a function
with a live bug in the exact field it quantifies over.** That is the
`Quaternion.canonicalizedTransform` shape from Appendix C arriving from the
other direction: a law that holds, over a defect it is simply not about.

What found it was the docstring's own word. *"Parses YAML front matter"* names a
reference definition, and YAML's spelling of a sequence is a matter of public
record — so the law is metamorphic: **the three spellings must agree.**

```swift
#expect(flow.tags == inline.tags)   // ["[math", "demo]"] != ["math", "demo"]
#expect(block.tags == inline.tags)  // []                 != ["math", "demo"]
```

This is exactly the technique Appendix C says reaches the shapeless bugs the
catalog cannot name, and it is exactly what Finding 1's branch-4 suppression
withholds from the reader. **The tool had this docstring in hand, classified it
as a contract, and declined to print it — because "does not trap" was already
serving the function.** Findings 1 and 4 are the same finding seen from two ends.

Recorded in the subject's test suite as `withKnownIssue` naming the defect and
the two vault files, so the suite stays green and the fix has a guard waiting.
Full subject suite: **462 tests, 71 suites, passing, 2 known issues.**

---

## Running tally, after two subjects

| stage | rows | note |
|---|---|---|
| S0 | 2 | extensions on non-project types never seeded |
| S3 | 8 | L1–L4 and P1–P4 — no template names an output-to-input relation |
| S4 | 2 | docstring advisory suppressed on both parse-family subjects |
| S7 | 1 | **P3 passes over a live defect in the field it quantifies over** |
| S1, S2, S5, S6, S8 | 0 | S5/S6 still not reached — the tool has proposed nothing worth emitting |

**Three rows across two subjects on S3 and two on S4** — the scope doc's
threshold for "worth a fix" is met for S4 (one mechanism, two subjects, verified
in source). S3 is a catalog gap, which is a roadmap item rather than a defect.

---

## The fix — `parseFields` learns the other two YAML spellings

`SwiftMarkdownWiki/Editor/FrontMatter.swift`, +46 −5. Two behaviours added and one
design decision made explicit.

**Block form** needs one bit of state: a `tags:` line with nothing after the colon
opens a sequence, and every following `- item` line belongs to it. Any line that
is not an item closes it, so `tags:` followed by `title: X` still parses the
title.

**Flow form is deliberately not distinguished from the inline form.** Rather than
detect `[…]` and strip the pair, each element is trimmed of whitespace, quotes and
flow brackets after the split. That makes the malformed spellings — `[a, b` with
no closing bracket, `a], b` with only a closing one — behave the same as the
well-formed one, and it makes the postcondition clean instead of conditional.

The reasoning is written at the code because it is a judgement call and the
opposite one is defensible: **a tag is a user-facing label and this function has
no channel to report a bad one through.** Given no error channel, the choice is
between a tag named `[math` showing up in the graph's filter and a lenient parse.
An earlier draft required both brackets before stripping either, and it forced P6
to be conditional on well-formedness — a weaker law guarding a worse outcome.

### Mutation matrix after the fix

Seven reversible patches, each run against the six laws and against the seven
pre-existing example tests.

| # | mutant | killed by the laws | by the 7 examples |
|---|---|---|---|
| 1 | guard path trims the body | P1, P2 | **survived** |
| 2 | body re-joined with `\r\n` | P2 | `stripsBodyCorrectly` |
| 3 | empty sequence elements not filtered | P3 | **survived** |
| 4 | title keeps a single quote | P4 | **survived** |
| 5 | flow brackets not trimmed | **P6, P5** | **survived** |
| 6 | block sequence never opens | P5 | **survived** |
| 7 | empty block item appended | P3 | **survived** |

**7 of 7 to the laws, 1 of 7 to the examples.** Mutants 5–7 are the new code, and
each is killed by a different law, so none of the three new behaviours rests on a
single assertion.

Mutant 5 is the one worth reading twice: it is the original defect, re-planted.
**P6 kills it over the whole 1 680-document space, and P3 does not** — which is
the point Finding 4 was making, now pinned by a patch rather than by an argument.

### State

| | |
|---|---|
| space | **1 680** documents (6 heads × 10 YAML blocks × 4 closers × 7 bodies), walked |
| laws | 6, all passing, every vacuity guard firing |
| `withKnownIssue` | **gone** — P5 is a guard now, not a record |
| subject suite | **463 tests, 71 suites, passing, 0 known issues** |
| swiftlint | exit 0 on both changed files |
| working tree | `FrontMatter.swift` modified (+46 −5), `FrontMatterPropertyLawTests.swift` new. **Uncommitted.** |

**One process note, because it cost a run.** The first mutation sweep reverted
each patch with `git checkout -- FrontMatter.swift`, and the fix was uncommitted
— so the first patch's cleanup threw the fix away and every row after it was
measured against the *old* code. Rows 3–7 failed to find their anchors, which is
the only reason it was caught; row 2 had already produced a plausible-looking
result that was wrong. **A mutation harness that reverts with `git checkout`
silently measures the wrong subject whenever the fix under test is not yet
committed.** The sweep now restores from a file snapshot taken after the fix.

---

## Subject 3 — `EditorFormatter.strippingHeadingMarkers(from:)` — the control arm

`SwiftMarkdownWiki/Editor/EditorFormatter.swift:35` · seeded `pure-function`, role
**`normalizer`** · `static` on a `@MainActor @Observable final class`.

```swift
/// Removes a leading ATX heading marker (`#`…`###### ` plus its trailing spaces/tabs) so a
/// heading command *replaces* an existing level instead of stacking markers — turning
/// `## Title` into `# Title` rather than `# ## Title`. A `#` without a following space (e.g. a
/// `#tag`) is left intact. A trailing newline in `line` is preserved.
static func strippingHeadingMarkers(from line: String) -> String {
    line.replacingOccurrences(of: "^#{1,6}[ \t]+", with: "", options: .regularExpression)
}
```

**Chosen deliberately as a control, and the ledger needed one.** Subjects 1 and 2
were both parse-family, so Findings 1 and 3 support only *"the parse/decode family
gets `input-totality` and nothing else"* — not a claim about the tool in general.
This subject's role is `normalizer`, whose law (idempotence) the catalog **does**
name. If the loop delivers here, the finding sharpens from "the tool is quiet" to
"the tool reaches exactly what a template names, and the parse family is a named
gap."

> **Declared contamination.** I knew from the whole-run subject list that this
> function received exactly **one** suggestion. I had not read which template, and
> the predictions below were written before doing so.

### Prediction — written 2026-09-11

The docstring carries three separable clauses, which is unusually generous, and
each is a law.

| # | Predicted law | Refutable? | A plausible implementation it rejects |
|---|---|---|---|
| **Q1** | **Idempotence — predicted FALSE.** `strip(strip(s)) == strip(s)` fails at `"## ## Title"`: one strip leaves `"## Title"`, a second leaves `"Title"`. The regex is `^`-anchored so it removes exactly one marker run. | — | Recorded as a **negative** prediction. If the tool proposes idempotence it is proposing a law the correct code fails — the cry-wolf case `Refutability.isWorthSurfacingBelowCut` exists to prevent. |
| **Q2** | **Result is a suffix of the input.** `s.hasSuffix(strip(s))` — only a prefix is ever removed | **yes** | One that also trims trailing whitespace, or normalises the line |
| **Q3** | **`#tag` is left intact** (docstring clause 2). A leading `#` run not followed by a space or tab leaves the line unchanged | **yes** | `^#{1,6}[ \t]*` — star for plus, which eats `#tag` → `tag` |
| **Q4** | **Seven or more hashes are untouched** (docstring clause 1, `#`…`######`). `"####### Title"` is returned unchanged, ATX having six levels | **yes** | `^#+[ \t]+`, which strips all seven |
| **Q5** | **A trailing newline survives** (docstring clause 3) | **yes** | Entailed by Q2, but it is the docstring's own sentence and worth stating where a reader will look for it |

**Reachability wrinkle to watch at S6:** the function is `static` on a
`@MainActor` class, so it inherits main-actor isolation. A test calling it must be
`@MainActor` too. Nothing in the seed manifest or the suggestion says so, and it
is the kind of thing that surfaces as a compile error in emitted code.

### Result — the control arm works, and it proposes a law the code fails

| template | score | tier |
|---|---|---|
| `idempotence` | 20 (Possible) | conjecture |

**Q1 was the prediction and it is confirmed.** The tool proposed idempotence off
the `T -> T` shape, and its own warning names the counterexample class verbatim:
*"a `T -> T` need not be idempotent (a one-shot suffix strip applied twice removes
two suffixes)"*. That is exactly this function. So the catalog reached this
subject, produced a law, **and the law is false of the correct implementation.**

Predictions Q2–Q5 were, as in Subjects 1 and 2, **not proposed** — they are
docstring clauses and output-to-input relations, and no signature pattern names
them.

**This is what the ledger needed, and it changes the shape of the finding.** The
tool is not uniformly quiet. It reaches `T -> T` and `(T, T) -> T` shapes and says
something; it reaches the parse family and says only "does not trap". The
difference is whether a *signature* names the law. Where the law lives in a
docstring clause or an output-to-input relation, the catalog is silent regardless
of family — which is S3 stated properly for the first time in this document.

**A scoring wrinkle, minor and worth one line.** The suggestion is docked −10 for
*"Reference-type carrier (EditorFormatter) — class/actor; algebraic properties may
be aliasing-sensitive"*. The function is `static`. There is no carrier instance and
no aliasing to be sensitive to, so the penalty is reading the enclosing
declaration rather than the function.

### S6, finally reached — and two compile errors, one unpredicted

The laws were written **deliberately without `@MainActor`** to measure the
reachability wrinkle predicted above. Both errors are the kind an emitted stub
would hit:

1. **`call to main actor-isolated static method … in a synchronous nonisolated
   context`.** Predicted. `strippingHeadingMarkers` is `static` on a `@MainActor`
   class and inherits the isolation. Nothing in the seed manifest or the
   suggestion mentions it; the seed's `kind` is a plain `pure-function`.
2. **`instance method 'replacingOccurrences(of:with:options:range:)' is not
   available due to missing import of defining module 'Foundation'`.**
   **Not predicted.** This package enables
   `.enableUpcomingFeature("MemberImportVisibility")`, so a test file that touches
   any Foundation member must import Foundation explicitly.

The second is the sharper one for the toolchain, because it is not about this
function at all: **emitted test code that omits `import Foundation` will not
compile in any package that has opted into `MemberImportVisibility`**, whatever it
is testing. It is the same class as the `@testable import` defect this ledger's
parent repo recorded in 2026-08-08 — an emitted file that cannot name what it
uses — one module over.

### Mutation matrix

| # | mutant | killed by the laws | by the 18 examples |
|---|---|---|---|
| 1 | `[ \t]+` → `[ \t]*`, so `#tag` is eaten | Q3, Q4 | `headingLeavesHashtagWithoutSpaceIntact` |
| 2 | `#{1,6}` → `#+`, so seven hashes strip | Q4 | **survived** |
| 3 | result also trimmed at the end | Q2, Q3, Q4, Q5, Q1 | `headingOnlyRewritesTheCurrentLine` |
| 4 | looped to a fixpoint, i.e. **made idempotent** | **Q1 alone** | **survived** |

**4 of 4 to the laws, 2 of 4 to the examples** — and this example suite is a good
one, far better than `FrontMatterTests`, with a test per docstring clause. The two
survivors are the six-level boundary and the idempotence question.

**Mutant 4 is the one this subject exists for.** It is the change a reader makes
after accepting the tool's suggestion: loop the strip to a fixpoint so the law
holds. Only Q1 — the law that *pins the refutation* — notices.

**And Q1 deliberately does not claim the current behaviour is right.** Under
`heading(1)`, a user-typed `# ## Title` stays `# ## Title` today and would become
`# Title` under mutant 4. Which is correct is a product judgement: the docstring
says the function exists to stop markers stacking, which argues for the loop; a
literal `##` in heading text argues against. **The law states what the behaviour
is and makes a change deliberate** — that is all a refutation law should claim,
and claiming more here would be inventing a spec the docstring does not give.

### Subject 3 state

| | |
|---|---|
| space | **450** lines (6 markers × 5 separators × 5 contents × 3 terminators), walked |
| laws | 5 + a pinned denominator, all passing, every vacuity guard firing |
| subject suite | **469 tests, 72 suites, passing, 0 known issues** |
| swiftlint | exit 0 |
| working tree | `EditorFormatterPropertyLawTests.swift` new, **uncommitted**. No production change — the code is correct as written. |

---

## Running tally, after three subjects

| stage | rows | note |
|---|---|---|
| S0 | 2 | extensions on non-project types never seeded |
| S3 | 12 | L1–L4, P1–P4, Q2–Q5 — docstring clauses and output-to-input relations, none signature-shaped |
| S4 | 2 | docstring advisory suppressed on both parse-family subjects |
| S6 | 2 | actor isolation unmentioned by the seed; **`import Foundation` under `MemberImportVisibility`** |
| S7 | 1 | P3 passes over a live defect in the field it quantifies over |
| S1, S2, S5, S8 | 0 | S5 still unreached — nothing has been emitted by the tool |

**S3 is now stated correctly.** It is not "the parse family is unsupported". It is
**the catalog names laws that a signature implies, and is silent on laws that a
docstring states or that relate output to input** — which is a boundary, not a
gap, and the three subjects fall on the same side of it for the same reason.

---

## S5 — emission, reached at last, and it is the sharpest finding of the walk

`yes A | swift-infer discover --sources SwiftMarkdownWiki --include-possible --interactive`
· exit 0 · **19 files written**, one per accepted suggestion, under
`<packageRoot>/Tests/Generated/SwiftInfer/<Template>/<Function>.swift`.

Three defects compound here, and each one alone would be enough to make the
emitted suite worthless. They are listed in the order a reader would hit them —
which is the reverse of the order in which they matter.

### (a) Nothing built the files, and nothing said so

This package's targets are rooted at `SwiftMarkdownWiki`,
`SwiftMarkdownWikiTests` and `SwiftMarkdownWikiIntegrationTests` — Xcode-originated
`path:` values, not the SwiftPM `Sources/` + `Tests/` convention. **No target is
rooted at `Tests/`.** So all 19 files landed in a directory SwiftPM does not
compile:

```
swift build --build-tests   →  exit 0, no warning mentioning Tests/Generated
swift test                  →  469 tests — the same 469 as before the emission
```

Nineteen files written, exit 0, no diagnostic of any kind, and a green suite. **A
reader who accepted nineteen suggestions and ran `swift test` would conclude the
laws pass.** That is the confident-zero shape of §1.1.3 on the emit side: not a
wrong answer, a silent one.

### (b) Not one of the 19 can compile

| | |
|---|---|
| files containing `@testable import SwiftMarkdownWiki` | **0 of 19** |
| files containing any import of the module under test | **0 of 19** |
| distinct imports emitted | `Testing`, `PropertyBased`, `PropertyLawKit` — 19 each |

Every call is also unqualified. `strippingHeadingMarkers` is
`static func strippingHeadingMarkers(from:)` on `EditorFormatter`; the emitted
property reads:

```swift
property: { value in strippingHeadingMarkers(strippingHeadingMarkers(value)) == strippingHeadingMarkers(value) }
```

— missing the type qualification *and* the `from:` argument label. The same
holds for `bucketURL`, `filtered`, `clamp`, `highlight`, `mimeType` and the rest.
Add to that the main-actor isolation and the `import Foundation` requirement
measured in Subject 3, and the subject declares no dependency on `PropertyBased`
or `PropertyLawKit` at all, so even the emitted imports do not resolve.

**This is the defect SwiftPropertyLaws found and fixed in its own emitter on
2026-08-08** — *"The generated test file never imported the module under test…
180 detected types, not one of them nameable"* — present, unfixed, in
`swift-infer`'s emitter. Same shape, one repository over.

### (c) The generator cannot produce an input the law is about

This is the one that matters, and it survives fixing (a) and (b).

**11 of the 19 emitted tests sample from
`Gen<Character>.letterOrNumber.string(of: 0...8)`** — every `String`-taking
function gets it. Its alphabet, read from `swift-property-based`'s
`Gen+String.swift:50`, is exactly:

```
abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789
```

No `#`. No space. No tab. No quote, bracket, angle bracket or punctuation of any
kind. And the eleven functions it is pointed at are `strippingHeadingMarkers`,
`replaceWikilinks`, `render`, `stripMarkTags`, `sanitizeFTSQuery`, `unquoted`,
`sequenceElement`, `highlight`, `highlightLine`, `highlightCode` and `mimeType` —
**functions whose entire job is to recognise markup, delimiters, quotes and
whitespace.**

Measured on Subject 3, replicating the generator's domain exactly (every
alphanumeric string of length 0–2, 3 907 of them):

| | |
|---|---|
| inputs the function leaves **unchanged** | **3 907 of 3 907** |
| inputs on which idempotence holds | **3 907 of 3 907** |

The function is a **no-op on the entire generated domain**. So:

> `discover` proposed `idempotence` for `strippingHeadingMarkers`. That law is
> **false of the correct implementation** — Subject 3 pins the witness at
> `"# ## Title"`. The generator `discover` derived for it **cannot produce a `#`**.
> Fix the imports and the emitted test passes, green, at every trial budget,
> forever — **ratifying a false law with a vacuous run.**

The tool's own `input-totality` warning states the principle it violates here:
*"A generator tuned for coverage of the TYPE is silently mistuned for coverage of
THIS LAW."* That warning is attached to the wrong template. It belongs to the
generator derivation.

**The remaining 4 generators are `.todo` in all but name.** `CGFloat.gen()`,
`URL.gen()`, `Date?.gen()` and `[PluginLogEntry].gen()` — neither
`swift-property-based` nor `PropertyLawKit` defines `gen()` on any of them, and
the subject defines none. They are the "user supplies it" convention, emitted
**without the trailing `// TODO: no generator derived` marker** that
SwiftPropertyLaws added in August precisely so a reader (and a `grep`) can tell a
working generator from a deliberate compile error.

### What S5 changes about the ledger

Every earlier row read "the tool proposed nothing useful". This row is worse and
more useful: **on the one subject where the tool did propose a law, the pipeline
would have delivered a passing test for a false claim.** A silence a reader can
notice; a green test for a law that cannot fail is the failure mode this entire
exercise exists to find, and it is the one the corpus sweep keeps recording about
itself.

The emitted directory was removed after measurement. Filed as
**[#414](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/414)** (path),
**[#415](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/415)** (imports and
qualification) and
**[#416](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/416)** (generator).

### Correction — (c) is not an unknown defect, and that makes it worse

The section above was written as though the alphanumeric generator were an
oversight nobody had noticed. Reading the source to write the issue showed
otherwise. `StrategistDispatchEmitter.swift:123` carries this comment:

> V1.150 — edge-bias the *top-level* String carrier. The kit's raw
> `Gen<Character>.letterOrNumber.string` is alphanumeric-only, so it never
> generates the whitespace / newline / punctuation inputs that falsify
> string-structural logic (YAML markers, indentation, etc.) — a
> determinism/idempotence check on such a function *false-passes*.

**That is this finding, written down in advance, with the fix beside it** —
`RawType.edgeBiasedGeneratorExpression`, which lives in the kit and which that
path calls.

It is the `verify` path. The stub emitter is a different path:
`InteractiveTriage+Accept.chooseGenerator` → `LiftedTestEmitter.defaultGenerator`
→ `RawType.generatorExpression`, the plain one. **A known defect whose fix landed
in one consumer and not its twin** — the same shape Appendix C describes for
shared vocabulary, where one side holds what the other needs and neither is able
to notice.

Two roots (a) and (b) also share one assumption — the SwiftPM `Sources/` + `Tests/`
layout — which `--sources` exists precisely to escape. So the honest summary of
S5 is not "three defects" but **two assumptions and a fix that did not
propagate**, and none of the three is a gap in anyone's understanding. They are
all places where something already known failed to reach the code that needed it.

---

## Running tally, after three subjects and one emission

| stage | rows | note |
|---|---|---|
| S0 | 2 | extensions on non-project types never seeded — **measured corpus-wide, 0 of 73; documented limitation, SwiftProjectLint#214** |
| S3 | 12 | docstring clauses and output-to-input relations, none signature-shaped |
| S4 | 2 | docstring advisory suppressed on both parse-family subjects |
| **S5** | **3** | **wrong output path (silent), no module import (0/19), generator cannot reach the law (11/19)** |
| S6 | 2 | actor isolation unmentioned; `import Foundation` under `MemberImportVisibility` |
| S7 | 2 | P3 passes over a live defect; the emitted idempotence test is vacuous on 3 907/3 907 inputs |
| S1, S2, S8 | 0 | S8 unreachable — no emitted test can run |


---

## Finding 3, measured across the corpus — and the first claim was wrong

Subject 1 recorded that `String.htmlEscaped` and `NSRange.clamped` are absent
from a 101-seed manifest, read the cause out of
`PropertyTestCandidacy.enclosingTypeContainer`, and said the claim rested on the
mechanism rather than on n = 2 — but that it predicted "the same silence in all 26
repositories" and was **worth measuring before filing**. It was measured. The
prediction about the mechanism survives; the prediction about the scale does not.

### Method

A **foreign extension** is an `extension X { … }` where `X` is a type no file in
the repository declares. Members are attributed to the extension block that
lexically contains them, and a seed is attributed to a block when its line falls
inside that block's line range.

The control is the same construct with one variable changed: an extension on a
type the repository **does** declare.

**Two bugs in the instrument, both caught by a result that looked odd rather than
by a test, and both recorded because the corrected numbers are the finding.**

1. **v1 attributed every member of a file to that file's extensions.**
   `pbt-workbook/main.swift` holds a top-level `func indent` *and* an
   `extension Grade`; v1 credited `indent` to the extension and reported it as a
   seeded foreign member. It is not in the extension at all.
2. **v2 matched seeds to members by symbol name within a file.**
   `TeamStandard.swift` declares both `RuleSeverity.strength` and
   `Optional<RuleSeverity>.strength`; v2 credited the seed for the first to the
   foreign extension holding the second. Seeds carry a line number, so v3 matches
   on line range, which is exact.

Both errors inflated the *seeded* count — i.e. both pushed **against** the
finding — which is why they surfaced as "why is this one seeded?" rather than
staying invisible.

### The result: 21 of 23 repositories, 1 646 non-test files

| | foreign extensions | members | seeded |
|---|---|---|---|
| **extension on a type the repo does not declare** | 57 | **112** | **5** |
| control — extension on a type the repo declares | 225 | 1 095 | **369** |

4.5% against 33.7%. And splitting the foreign members by whether they take a
parameter turns that into a clean rule:

| foreign-extension members | seeded | dropped |
|---|---|---|
| takes at least one parameter | 3 | 36 |
| **takes none** | **0** | **73** |

**Zero of 73.** A computed property or nullary method on `String`, `URL`,
`NSRange` or `Array` is never a seed, corpus-wide.

*(The table above is **21 of 23 repositories** — `SwiftProjectLint` and
`SwiftInferProperties` were still generating. Superseded by the complete run
below, which also carries a third instrument bug the last two repositories
exposed.)*

### The mechanism, read from source rather than inferred

Three separate pieces of state are empty for a type the project does not declare,
and any one of them is enough:

1. `enclosingTypeContainer(of:knownValueTypes:)` sets
   `isValueType: knownValueTypes.contains(extendedBase)`, and `knownValueTypes`
   is *"project types declared as `struct` or `enum`"*. So `String` is **not** a
   value type as far as the analyzer is concerned, and `SelfAccessAnalyzer`'s
   bare-`self` branch reads
   `enclosingIsValueType ? .immutableSelf : .disqualifying`.
2. `TypeStoredPropertyCollector` finds no declaration, so `storedProperties` is
   empty and `self.x` resolves to nothing.
3. `CleanInstanceMethodCatalog` has no entry for the type, so a call to one of its
   own methods — `replacingOccurrences(of:with:)`, the normal way to write such an
   extension — is a bare lowercase callee that is not local, not a stored
   property, not in `pureStdlibFunctions` and not a cleared sibling. It falls
   through to the conservative branch and disqualifies the member.

So a member whose body touches `self` **at all** — explicitly, through a stored
property, or through an implicit-`self` method call — is refused. Only a member
that ignores `self` survives, and ignoring `self` usefully requires parameters.
That is exactly the 0-of-73 boundary.

### An A/B/C experiment, because a census is a correlation

The census cannot separate "foreign" from "these functions differ somehow". A
three-arm fixture with the **same body** does:

| arm | carrier | reads `self`? | result |
|---|---|---|---|
| **A** | `extension String` (foreign) | yes | **dropped** |
| **B** | `struct Markup` (declared here) | yes | **seeded** |
| **C** | `extension String` (foreign) | no — `static`, takes the input as a parameter | **seeded** |

A and B are the same escaping logic; only the carrier differs. A and C are the
same carrier; only the relationship to `self` differs. The mechanism is causal.

### Verdict: documented limitation, not a filing

**The population is the reason.** 112 foreign-extension members across 1 646
files, and most are not property-test subjects at all:

| extended type | members | what they are |
|---|---|---|
| `Gen` | 23 | swift-property-based generator definitions |
| swift-syntax node types | ~37 | mostly `PropertyLawSyntax`'s own `gen()` factories |
| SwiftUI `View` / `Binding` | several | view modifiers returning `some View` |
| **the rest** | **~12** | the genuinely missed candidates |

Those twelve are the whole cost: `String.htmlEscaped`, `NSRange.clamped`,
`unichar.isASCIIDigit`, `Duration.seconds` (two repos), `URL.fileSize`,
`Collection.bindingInitializers`, and SwiftUMLStudio's `String+Extensions.swift`
— which holds `globPatternToRegex`, the best missed candidate in the set.

**The bias still runs the wrong way**, and that is worth writing down: an
extension on `String`, `Array` or `NSRange` is the *easiest* possible property
subject — the carrier is a value type, a generator is trivially derivable, and
the function is pure by construction because there is nowhere impure to reach.
The gate that cannot see them is the one that asks whether the project declared
the carrier.

But twelve candidates corpus-wide does not justify teaching the scanner about
stdlib types, and the conservative posture that produces the silence is the same
one that keeps its false-positive rate low everywhere else. **Filed as a
documented limitation rather than a defect** —
[SwiftProjectLint#214](https://github.com/Joseph-Cursio/SwiftProjectLint/issues/214)
— which is the outcome the "measure before filing" note in Subject 1 was holding
the question open for.

**What the exercise actually bought**: the first write-up would have said "the
linter is blind to extensions on stdlib types" and implied a systemic gap. The
true statement is narrower in scope, sharper in mechanism, and smaller in
consequence — and only one of those three was knowable from n = 2.


### Completed — all 23 repositories, and a third instrument bug

The two largest landed (`SwiftProjectLint` 249s, `SwiftInferProperties` 252s;
23 of 23, no failures). They exposed one more defect in the measurement, found
the same way as the first two — by a number that did not reconcile.

**Eight seeds fell inside foreign-extension blocks, but only four aligned with a
member.** Four of the eight were `kind: extractable-kernel` — *closure* seeds
pointing inside a member's body, not member declarations — which reconciles the
count. But two of those named `extension SharedVerifierPackage`, and
`SharedVerifierPackage` **is declared in the repository**, at
`Sources/SwiftInferCLI/SharedVerifierPackage.swift:58`. It should never have been
classified foreign.

The cause was in my exclusion filter:

```python
if '/.build/' in low or low.endswith('package.swift'): return True
```

`"SharedVerifierPackage.swift".lower()` ends with `package.swift`. The filter
meant to skip the SwiftPM manifest, and it also skipped every file whose name
merely *ends* in `Package.swift` — so the type declared there was missing from
`declared`, and its own extensions were counted as extensions on a foreign type.
Fixed to match the basename exactly.

**Three instrument bugs now, and the pattern is worth naming.** All three were in
**attribution** — which member belongs to which extension, which seed belongs to
which member, which file counts as declaring a type. None was caught by a test.
Each surfaced as a row that read wrong on inspection, and each had been silently
shifting the totals until then. Two inflated the seeded count and one inflated
the foreign population; all three therefore flattered the finding's *size*
while leaving its *direction* intact.

### The final numbers

23 repositories · 2 822 non-test files · 5 629 seeds

| | extension blocks | members | member seeds |
|---|---|---|---|
| **carrier the repo does not declare** | 71 | **134** | **3** |
| control — carrier the repo declares | 507 | 2 179 | **1 119** |

2.2% against 51.4% — a 23× gap, wider than the 21-repo figure because the two
large repositories are extension-heavy on their *own* types.

| foreign-extension members | seeded | dropped |
|---|---|---|
| takes at least one parameter | 3 | 43 |
| **takes none** | **0** | **88** |

**Zero of 88**, corpus-wide, with no exceptions to chase. The three seeded
members all take a parameter and ignore `self`, exactly as arm C of the A/B/C
fixture predicts.

The extended carriers, for scale: `Gen` (32 members), `String` (16), SwiftUI
`View` (10), `Array` (8), `ExprSyntax` (6), `Optional` (6), `Int` (5). The two
largest groups remain generator definitions and SwiftUI modifiers — neither a
property-test subject — which is why the verdict stays *documented limitation*.

**Nothing in the mechanism moved.** The A/B/C fixture settles causation and did
not depend on the census; the census only ever sized the consequence. The final
size is **0 of 88 parameterless members, ~12 of which are candidates anyone
would want.**

---

## Subject 4 — `GraphViewModel.matchesSearch(_:)`

`SwiftMarkdownWiki/Graph/GraphViewModel.swift:102` · `(GraphNode) -> Bool` on a
`@Observable @MainActor final class`.

```swift
/// Returns true when the node matches the current search query (or no query is set).
func matchesSearch(_ node: GraphNode) -> Bool {
    let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return true }
    return node.title.localizedCaseInsensitiveContains(trimmed)
}
```

**Chosen for three reasons, and the third is the strongest.** It is the first
`predicate`-role subject, after two parse-family and one normalizer. `predicate`
is one of the two entries in `referenceDefinitionHungryTemplates`, so Finding 1's
**branch 1** should fire and the docstring advisory should *appear* — testing the
positive side of that finding rather than the negative. And it is exactly the
shape Appendix C names as the road test's unscored find: the locale-dependent
search predicate the hand-written answer key walked past, which the appendix says
carries four refutable laws.

> **Declared contamination.** I knew this function received exactly one
> suggestion, from the whole-run subject list. I had not read which template.

### Prediction — written 2026-09-11

Appendix C lists four laws for this shape. **Two of them do not survive contact
with this codebase, and saying why is half the prediction.**

| # | Predicted law | Refutable here? | Notes |
|---|---|---|---|
| **R1** | **An empty or whitespace-only query matches every node.** | **yes** | Appendix C's first. Rejects an implementation that forgets to trim, or that returns `false` on an empty query. |
| **R2** | **The query is whitespace-insensitive.** Padding `searchQuery` with spaces changes no verdict. | **yes** | Not in Appendix C's list; it is what the `trimmingCharacters` line buys, and deleting that line is the mutant it kills. |
| **R3** | **A match implies a case-insensitive substring.** | **yes, and it is the interesting one** | Appendix C's second. `localizedCaseInsensitiveContains` is **locale-dependent**, so stated against locale-independent `lowercased().contains` it is a latent flake — Turkish dotless `ı` is the classic divergence. Predicting it **holds under `en_US` and is not safe to state unconditionally.** |
| — | *the result is a subset of the input* | **no — not about this function** | Appendix C's third. Here the filtering is stdlib `.filter`, which guarantees it. The law is about `filter`, not about the predicate. |
| — | *filtering twice changes nothing* | **no — same reason** | Appendix C's fourth. `filter` is idempotent by construction for a pure predicate; the law cannot fail whatever this function does. |

**That is a correction to a published list, not a complaint about it.** Appendix C
states those four for an *extracted kernel* of the form
`search(_ nodes: [Node], query: String) -> [Node]`, where subset and idempotence
are real claims about the kernel's own filtering. Point them at a `(Node) -> Bool`
predicate consumed by stdlib `filter` and two of the four become tautologies. The
refutable count for this shape is **a property of how the kernel is carved**, not
of the domain — which is the same lesson as the `f(x) == f(x)` fallback, arriving
from a direction the scope doc did not anticipate.

**Also predicted, before running anything:** this function is **not in the seed
manifest**, while `isVisible` twelve lines above it is. Both read a mutable
stored `var`. That discrepancy is what led to
[SwiftProjectLint#215](https://github.com/Joseph-Cursio/SwiftProjectLint/issues/215),
recorded below — and `matchesSearch` being absent is the **correct** half of it.

### Result — the loop's best showing, and the positive control Finding 1 needed

| template | score | tier |
|---|---|---|
| `predicate` | 20 | Possible (role-entailed) |

*"`matchesSearch` classifies its inputs — it must be TOTAL over them, and it must
agree with a reference definition only you can state."*

R1–R4 were not proposed. **But the docstring advisory fired**, which is the first
time in four subjects:

```
• matchesSearch(_:)  (GraphNode) -> Bool
  the `predicate` law openly owes a reference definition — your docstring states one:
    "Returns true when the node matches the current search query (or no query is set)."
  encode THAT sentence as the property; the law checks the code against it.
```

— followed by a `matchesSearch_reference(_:)` scaffold. `DocstringAdvisor` branch
**1** took it, because `predicate` is in `referenceDefinitionHungryTemplates`.

**This is the positive control Finding 1 was missing, and it narrows that finding
rather than confirming it.** The advisory machinery is not broken; it works
exactly as designed, and what it produces here is useful. Finding 1 is
specifically that `input-totality` is *role-entailed but weak*, so it takes
branch **4** — "a self-contained role-entailed law already serves the function" —
and suppresses this same output for every parser. Subjects 1 and 2 were denied
precisely what Subject 4 was handed.

`matchesSearch` also **survives seed focusing despite being absent from the
manifest**, because `predicate` is role-entailed and `SeedFocus` keeps a law the
code owes. The documented seam works.

### The laws, and two violators that survived first

Six laws over 110 cases, in
`SwiftMarkdownWikiTests/GraphSearchPropertyLawTests.swift` (shipped as
SwiftMarkdownWiki#28). R1–R4 as predicted; R3 confirmed locale-dependent, pinned
by a test asserting `en_US` and `tr_TR` **disagree** — searching `i` finds a note
titled `I` in English and does not in Turkish.

| # | mutant | first run | after |
|---|---|---|---|
| 1 | query not trimmed | R1, R2 | R1, R2, R4 |
| 2 | case-**sensitive** `contains` | **survived** | R4 |
| 3 | blank query matches nothing | R1 | R1 |
| 4 | matches `node.id.path`, not `node.title` | **survived** | R3, R4 |

**Mutant 2 was predicted to survive** — R3 is one-directional, and a
case-sensitive implementation satisfies it because every match it reports is
still a substring. R4 is its converse and exists for it.

**Mutant 4 was not predicted, and the fault was in the fixture.** Node ids were
built as `/tmp/<title>.md`, so the path always contained the title and "matches
the title" was indistinguishable from "matches the path". Ids are now opaque. **An
id derived from the data under test cannot witness a claim about that data** —
recorded at the fixture, because the next person to write a `GraphNode` helper
will reach for the readable spelling.

### And the anomaly that started the subject: SwiftProjectLint#215

`matchesSearch` is **not** in the seed manifest; `isVisible`, twelve lines above,
**is**. Both read a mutable stored `var`. The difference is one line:

```swift
if let tagFilter, !node.tags.contains(tagFilter) { return false }   // shorthand
```

Swift 5.7 shorthand optional binding is collected as a fresh local by
`SelfAccessAnalyzer.LocalBindingCollector`, so the implicit `self.tagFilter` read
is never classified. A three-arm fixture settles it: the same logic is **seeded**
as `if let tagFilter`, and **dropped** as `if let filter = self.tagFilter` or
`guard let value = tagFilter`.

Measured corpus-wide: **12 of 3,280** seeded pure/restricted functions
shorthand-bind a mutable stored `var` — including `EditorFormatter.selectedText`,
which binds `weak var textView: NSTextView?`, a live view object seeded as a
pure-function candidate. A first pass counted **118** by flagging any stored
property; spot-checks killed it, because binding a `let` (`CappedList.wasTruncated`)
or a computed property over `let`s (`OptionSweep.currentImpact`) is harmless — the
blind spot is the same, but the seed is correct anyway.

**This is the mirror of #214.** That one is over-conservative and misses ~12
candidates; this one is under-conservative and admits 12. Same rule, same order of
magnitude, opposite signs. Both filed;
[#215](https://github.com/Joseph-Cursio/SwiftProjectLint/issues/215) carries the
note that the fix is not a one-liner, because a shorthand binding may legitimately
shadow an existing *local*.

### Running tally, after four subjects

| stage | rows | note |
|---|---|---|
| S0 | 3 | foreign extensions (**#214**, 0 of 88); **shorthand binding admits mutable state (#215, 12 of 3,280)** |
| S1 | 0 | `SeedFocus` kept an owed law the manifest never named — the seam working |
| S3 | 15 | R1–R4 join L1–L4, P1–P4, Q2–Q5: no template names an output-to-input relation or a docstring clause |
| S4 | 2 | **narrowed and filed — [#420](https://github.com/Joseph-Cursio/SwiftInferProperties/issues/420)**; the advisory works for `predicate`, the defect is `input-totality` taking branch 4 |
| S5 | 3 | path, imports, generator (#414 / #415 / #416) |
| S6 | 2 | actor isolation; `import Foundation` under `MemberImportVisibility` |
| S7 | 2 | P3 passes over a live defect; the emitted idempotence test is vacuous on 3 907/3 907 |
| S2, S8 | 0 | S8 unreachable — no emitted test can run |

---

## Subject 5 — `NSRange.clamped(to:)`

`SwiftMarkdownWiki/Editor/NSRange+Clamp.swift:7`

```swift
/// Clamps the receiver so its location and length stay within `[0, length]`.
/// Used when mapping styling ranges onto a text storage that may have changed
/// length since the ranges were computed.
func clamped(to length: Int) -> NSRange {
    let location = max(0, min(self.location, length))
    let clampedLength = max(0, min(self.length, length - location))
    return NSRange(location: location, length: clampedLength)
}
```

**Chosen to answer the question four subjects have left open: does the loop ever
propose a law that is true, refutable and non-trivial?** So far it has offered a
near-vacuous totality claim, a conjecture the code fails, and an owed reference
definition the reader must supply. `role-postcondition` is the one template that
supplies the law itself, **from a catalogue** — *"'clamped' names an operation
whose guarantee is known, so it owes it of its output — the result lies within the
given bounds"*. If the loop delivers anywhere, it delivers here.

It also sits on two earlier findings at once: it is in a foreign extension, so
[#214](https://github.com/Joseph-Cursio/SwiftProjectLint/issues/214) means it is
**absent from the seed manifest**, and Finding 2 recorded it as one of the two
real losses when the run was focused through that manifest.

> **Declared contamination.** I read the `role-postcondition` block before
> predicting — it is what selected the subject. So T3 below is not an independent
> prediction; it is the tool's claim, which I am about to test. T1, T2, T4, T5 and
> the failure prediction are mine.

### Prediction — written 2026-09-11

| # | Predicted law | Refutable? | Rejects |
|---|---|---|---|
| **T1** | `result.location >= 0` | yes | dropping the outer `max(0, …)` on location |
| **T2** | `result.length >= 0` | yes | dropping the outer `max(0, …)` on length |
| **T3** | **the tool's law** — `result.location + result.length <= bound` | yes | `min(self.length, length)` instead of `length - location`, the classic off-by-a-location |
| **T4** | **idempotence** — clamping twice to the same bound equals clamping once | yes | any implementation whose output is not already in range |
| **T5** | **fixpoint** — a range already inside `[0, bound]` is returned unchanged | yes | an implementation that always rewrites, e.g. zeroing the length |

**And a failure predicted in advance: T3 is false for a negative bound.** With
`bound = -1` the body gives `location = max(0, min(loc, -1)) = 0` and
`clampedLength = max(0, min(len, -1)) = 0`, so the result is `(0, 0)` and
`0 + 0 <= -1` is **false**. The catalogue's law cannot hold there, because no
range fits inside `[0, -1]` — the interval is empty.

So the interesting question is not *does the loop propose a good law* — it does —
but **what the loop does with a catalogue law whose precondition it never states.**
A negative bound is unreachable from this call site (`clamped(to:)` is handed an
`NSTextStorage` length), which is exactly the condition under which a false law
sits unnoticed.

### Result — the loop delivers, and the law it delivers is false as stated

**T3 was proposed, and it is the first genuinely good law the loop has produced in
five subjects.** No reference definition required of the reader, no conjecture off
a name's shape — the catalogue knows what `clamped` means and asserts it of the
output. And it earns its keep: of four planted violators, the one that swaps
`min(self.length, length - location)` for `min(self.length, length)` — the
off-by-a-location that lets a clamped range run past the end of the storage it was
clamped to, which is the bug this function exists to prevent — **is caught by T3
and by nothing else.**

T1, T2, T4, T5 were not proposed. Four of four violators die; the full matrix is
in [SwiftMarkdownWiki#29](https://github.com/Joseph-Cursio/SwiftMarkdownWiki/pull/29).

**And the failure predicted in advance holds: T3 is false for a negative bound.**
All **242** negative-bound cases in the 1 089-case space refute it, pinned by
`theCataloguesLawIsFalseForANegativeBound`. `[0, -1]` is the empty interval, so no
range fits inside it — the law is *unsatisfiable* there rather than violated.

**The catalogue supplies a law and not its domain, and that is the finding.** This
is not a defect in `clamped(to:)`: every call site hands it an `NSTextStorage`
length, so the region where the contract fails is unreachable — which is exactly
the condition under which an unstated precondition survives indefinitely. Nor is
it quite a defect in the tool, which never claimed to state preconditions. It is
the seam between them, and it has a shape worth naming:

> **A catalogue law is a law plus a domain, and only the law is shipped.**
> `role-postcondition`'s message — *"'clamped' names an operation whose guarantee
> is known, so it owes it of its output"* — is true on the domain the verb
> presupposes, and silent about what that domain is. A reader who encodes the
> sentence as given gets a test that is red on inputs the function was never asked
> about.

Which is the same defect this walk found in the *generator* (#416), arriving from
the opposite direction. There, the law was right and the inputs could not reach it.
Here the inputs reach further than the law, and the law is what gives way. **Both
are the gap between a law and the domain it is quantified over, and neither the
suggestion nor the emitted stub carries a domain at all.**

**An incidental, recorded because it landed in the instrument rather than the
subject.** T5's guard was first written `range.location + range.length <= bound`,
which traps on `NSNotFound + Int.max` and took the whole test process down with
SIGTRAP — no failure message, exit signal 5. That is precisely the hazard
`input-totality`'s warning describes (*"A VIOLATION CRASHES THE TEST PROCESS
instead of shrinking to a tidy counterexample"*), except the trap was in the law,
not in the code under test. A walked space that deliberately includes `Int.max`
will find the harness's own arithmetic before it finds the subject's.

### Running tally, after five subjects

| stage | rows | note |
|---|---|---|
| S0 | 3 | foreign extensions (#214, 0 of 88); shorthand binding (#215, 12 of 3 280) |
| S1 | 0 | `SeedFocus` kept an owed law the manifest never named |
| S3 | 19 | T1, T2, T4, T5 join R1–R4, Q2–Q5, P1–P4, L1–L4 |
| S4 | 2 | narrowed and filed (#420) |
| S5 | 3 | path, imports, generator (#414 / #415 / #416) |
| S6 | 2 | actor isolation; `import Foundation` under `MemberImportVisibility` |
| S7 | 3 | P3 over a live defect; the vacuous emitted idempotence test; **a catalogue law shipped without its domain** |
| S2, S8 | 0 | S8 unreachable — no emitted test can run |

**The answer to "does the loop ever deliver" is yes, once in five subjects, and
the delivery is 80% of a law.** T3 is correct, catalogue-supplied, needs nothing
from the reader, and catches the real bug. It is also stated over a domain that
does not exist.
