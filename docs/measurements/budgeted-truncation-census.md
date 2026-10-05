# Is budgeted truncation a role with a population? — 20 strict sites, 4 a test can draw

> **Status:** `measured` · **As of:** 2026-10-05

Fix 4 would teach swift-infer the laws mutation testing gave SwiftAssist's `String.prefix(utf8Bytes:)`:
the result is a **prefix** of the input, it **fits** the budget, it is **maximal**, and its flag is honest.
The route for such laws is a role template, where a recognised role makes the catalogue supply the law.
The last role template was built on **36 exact-name sites over 11 corpora, largest container 11%, ~97%
precision** (`postcondition-law-declined.md` §4–§5). This census asks whether budgeted truncation has a
population comparable to that. Plan, shape and predictions are in
`docs/plans/budgeted-truncation-census-scope.md`, committed before the instrument. The instrument is
`scripts/budgeted_truncation_census.py`. The 223 checked rows were frozen before any was read
(`fixtures/budgeted-truncation-census.json`), and every judgement is recorded with its reason
(`fixtures/budgeted-truncation-judgements.json`).

## Result

| group | subjects | functions | SHAPE rows | CANDIDATE | STRICT | WEAK | MARKER |
|---|---:|---:|---:|---:|---:|---:|---:|
| manifest corpora | 21 of 22 | 23,561 | 289 | 86 | 16 | 0 | 2 |
| funnel repositories | 19 of 19 | 10,687 | 92 | 44 | 3 | 1 | 5 |
| unmet subjects | 13 of 13 | 15,823 | 147 | 53 | 1 | 0 | 0 |
| **all, deduplicated** | **53 of 54** | | **509** | **183** | **20** | **1** | **7** |

Every CANDIDATE was checked (183 is under the 300 cap). **The seeded 40 of the 326 SHAPE-ONLY rows were
all OTHER**, so the cue missed nothing this sample could see. The two judges disagreed on 2 of 223 rows,
both swift-nio hex dumps, which the third judge called OTHER.

**Not a template route.** The 20 STRICT rows look like a population, but:

- **15 of the 20 truncate an unsafe buffer, a `Span` or a buffer view.** Thirteen are swift-collections'
  `_extracting(first:)`, `_trim(first:)`, `consumePrefix(upTo:)` and the deque's segment `prefix`/`suffix`,
  and two are FoundationEssentials' `BufferView.prefix`/`suffix`. All are element-count
  `min(maxLength, count)`, and no generator draws their inputs. A sixteenth, PropertyLawKit's
  `Enumeration.prefix(_:)`, holds closures, so no derived generator draws it either.
- **4 STRICT rows take an input a test can draw**: SwiftAssist's `String.prefix(utf8Bytes:)`,
  `CappedList.stoppedEarly(_:limit:keeping:)` and `ContextBudgetManager.leadingItems(_:fitting:)`, and
  swift-system's internal `Slice._eat(count:)`. **Three of the four are in the subject the census came
  from.** The one WEAK row, SwiftAssist's word-boundary `truncateToTokens`, is `private`.
- **They share no name.** The role route keys on exact names, because a prefix match supplied a false law
  (`postcondition-law-declined.md` §4). The four drawable rows have four different names, and the exact
  names that recur (`prefix(_:)`, `suffix(_:)`) are almost all on the unsafe types.

So the reachable population is 4, three of them self-selected, against 36 for the shipped role route and
17 for `normal-form`. As with the decoder census, **the shape has no population outside the subject it
came from.**

## Read before quoting a number

- ⚠ **Per-group function and SHAPE counts are not deduplicated**. SwiftProjectLint, SwiftPropertyLaws,
  SwiftEffectInference and SwiftLintRuleStudio are both manifest corpora and funnel repositories. CANDIDATE
  and verdict counts are deduplicated by file and line.
- ⚠ **The verdicts come from agent judges**: two independent passes per row with different instructions,
  one describing what the body does and one arguing against truncation, and a third pass on
  disagreement. I re-read all 21 STRICT and WEAK rows against the source and agree with each; the
  `reread_*` fields record that read. The 155 OTHER verdicts were not re-read by hand.
- **STRICT is a property of the code, not of a test.** No law was run. The unsafe-buffer rows hold the
  laws by reading (`min(maxLength, count)` behind a precondition), and nothing here drew one.
- Units of the 20 STRICT rows: elements 18, UTF-8 bytes 1 (`prefix(utf8Bytes:)`), estimated tokens 1
  (`leadingItems`, by word count).
- The unmet subjects are at the HEAD of a 2026-10-05 clone, not the revisions earlier censuses pinned. All
  revisions are in the census fixture. `swiftlang-swift` (the stdlib) is not on this machine and is the one
  missing subject. The stdlib's `Collection.prefix(_:)` is the textbook element-count case, and it would
  add to the element-count rows, not the drawable ones.

## Display truncation

**7 MARKER rows**, which append a marker so the result is not a prefix:

- the three `truncate(_:_:)` exercises in `pbt-workbook-corpus` (correct, off-by-one, always-ellipsis),
  which are planted teaching subjects;
- swift-nio's two `ByteBuffer` hex dumps (head, `...`, tail);
- SwiftAssist's `private` `excerpt(_:max:)` and SwiftMarkdownWiki's `private` `previewSnippet(_:limit:)`.

The recall probe found most display truncation outside the shape. Its budget is a constant, not a
parameter (next section). A MARKER role has no population here either.

## Recall probe

Three independent agents searched the three groups for truncation functions the shape misses. Their finds
are counted, not added to the population. After deduplication there are **20 finds: 11 MARKER and 9
STRICT**.

- **9 of the 11 MARKER finds have a constant budget**: `CIAdapter.truncateOutput`,
  `ThinkingRecipeExtractor.trimStep`, `InsecureTransportVisitor.truncateURL`, swift-docc's
  `NodeURLGenerator.fileSafeURL`, and others. A role template has no parameter to vary in these.
- The **STRICT finds** are element-count or character-count:
  - GRDB's `Cursor.prefix`/`suffix` (a lazy database cursor);
  - PropertyLawKit's `collect(_:cap:)` and `manualCollect(from:cap:)`;
  - swift-docc's scanner `take(_:)` and `scan(length:)`;
  - SwiftAssist's `CappedList.init` and its constant-budget `truncateOversizedChunks`.

  Spot checks confirmed `Cursor.prefix` and `truncateOversizedChunks`. They re-classified swift-foundation's
  `Platform.copyCString`, which the probe called a UTF-8-byte STRICT row, as OTHER: it is an
  `strlcpy`-style copy through unsafe pointers that cuts on bytes, not characters.
- **No find measures in a multibyte unit.** Adding the finds would not change the verdict. None shares a
  name with the drawable four, and most are constant-budget display code.

## Predictions

| # | prediction | outcome |
|---|---|---|
| 1 | the controls hold | ✅ all four |
| 2 | ≤ 15 STRICT rows | ❌ **20**, but 15 are unsafe-buffer or span internals |
| 3 | ≤ 3 STRICT rows in a multibyte unit | ✅ **1** (`prefix(utf8Bytes:)`) |
| 4 | MARKER ≥ STRICT | ❌ **7 against 20**; display truncation mostly has a constant budget and falls outside the shape (the recall probe found 9 such) |
| 5 | SHAPE-ONLY sample ≤ 2 STRICT or WEAK | ✅ **0 of 40** |
| 6 | if STRICT ≥ 5, one container ≥ 40% | ❌ as stated: the largest container (`UnsafeBufferPointer`, `UnsafeMutableBufferPointer`) holds 4 of 20, 20%. **One corpus, swift-collections, holds 13 of 20 (65%).** |

## The generator half

Fix 4's second part was a multibyte `String` generator. Today `RawType`'s arms draw ASCII alphanumerics,
ASCII structure tokens and, in the hostile arm, Latin-1. None draws a three- or four-byte scalar or a
multi-scalar grapheme. **Among the STRICT and WEAK rows, one function measures in a multibyte unit, and it
is the motivating one**, so this census gives such an arm one subject. It does not ask whether multibyte
input matters for laws other than truncation. Any function that counts `utf8`, `utf16` or
`unicodeScalars` is a candidate there, and that is a separate census.

## Method

`python3 scripts/budgeted_truncation_census.py controls`, then
`run fixtures/budgeted-truncation-census.json`. That takes about 8 s over 11,501 Swift files and 50,071
functions on an M5 Pro. The shape and cues are as the scope fixed them, with one change made after a dry
run on SwiftAssist and before the population was read: hidden directories are skipped, because the
checkout's `.claude/worktrees` held four whole copies of its sources. The judging, adjudication and recall
probe ran as one read-only workflow over the frozen rows. Their output is the judgements fixture.

## What this does not answer

- **Whether the four drawable functions should get laws.** They already have them where it mattered:
  SwiftAssist's law suite covers `prefix(utf8Bytes:)` and `CappedList`. swift-infer's route to such a
  function is its docstring. In the 2026-10-04 run on SwiftAssist, discover's docstring advice printed
  `prefix(utf8Bytes:)`'s contract as prose without `--seeds`. With `--seeds` the function drops out of the
  full advice, because SwiftProjectLint cannot see a member of an extension on a type the project does not
  declare (Joseph-Cursio/SwiftProjectLint#214, closed as "document rather than fix").
- **Constant-budget truncation as a role.** Nine display truncations have a literal budget. A template
  could read the literal, but most of these append a marker, so the prefix law is false for them as
  stated.
- **A text census, not a parse.** Both arms of an `#if` are read, and a truncation in a helper the body
  calls is seen only through the body cue.

## Found in passing

SwiftAssist's `CappedList.stoppedEarly(_:limit:keeping:)` stores its `keeping end:` argument but always
keeps the leading items, so a `.trailing` caller would get a value whose `end` names the wrong end. No
caller passes `.trailing` today. A producer that stops early cannot know its trailing items, so the honest
fix is probably to drop the parameter rather than honour it.
