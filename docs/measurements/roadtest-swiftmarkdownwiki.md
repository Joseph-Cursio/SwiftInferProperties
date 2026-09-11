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

Filed against SwiftInferProperties.

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
| S0 | 2 | extensions on non-project types never seeded |
| S3 | 12 | docstring clauses and output-to-input relations, none signature-shaped |
| S4 | 2 | docstring advisory suppressed on both parse-family subjects |
| **S5** | **3** | **wrong output path (silent), no module import (0/19), generator cannot reach the law (11/19)** |
| S6 | 2 | actor isolation unmentioned; `import Foundation` under `MemberImportVisibility` |
| S7 | 2 | P3 passes over a live defect; the emitted idempotence test is vacuous on 3 907/3 907 inputs |
| S1, S2, S8 | 0 | S8 unreachable — no emitted test can run |
