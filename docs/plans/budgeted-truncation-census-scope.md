# Is budgeted truncation a role with a population?

> **Status:** `shipped` · **As of:** 2026-10-05

SwiftAssist's `String.prefix(utf8Bytes:)` returns the longest prefix of a string that fits a UTF-8 byte
budget without splitting a character, plus whether anything was dropped. Mutation testing gave it four
laws: the result is a **prefix** of the input, it **fits** the budget, it is **maximal** (the next
character would not fit, or nothing was dropped), and the flag is **honest**. swift-infer proposed none of
them. The role-postcondition route (`postcondition-law-declined.md` §4–§5) is how such laws would ship: a
recognised role, a law the catalogue supplies. It was built on **36 exact sites over 11 corpora, largest
container 11%, ~97% precision**, and `normal-form` ships at 17. This census asks whether budgeted
truncation has a population comparable to those, before anything is built.

## 1. The shape — fixed now

A text census over masked source (comments and string contents blanked, braces matched). A `func` with a
body is a **SHAPE** row when all three hold:

1. **A budget parameter**: a parameter of an integer type (`Int`, `UInt`, `Int8`…`Int64`, `UInt8`…`UInt64`),
   optional or not.
2. **A sequence result**: the return type, after `some`, a trailing `?` and a tuple's first element are
   stripped, is `String`, `Substring`, `Data`, `ByteBuffer`, `AttributedString`, `Self`, a `SubSequence`,
   an array (`[T]`, `Array<T>`, `ArraySlice<T>`, `ContiguousArray<T>`; not a dictionary), or the enclosing
   type itself.
3. **A sequence input**: a non-budget parameter of a type rule 2 accepts, or an enclosing declaration of
   `String`, `Substring`, `StringProtocol`, `Array`, `ArraySlice`, `ContiguousArray`, `Data`, `ByteBuffer`,
   `AttributedString`, `Sequence` or a `…Collection` protocol, or a result of `Self`, a `SubSequence` or the
   enclosing type.

A SHAPE row is a **CANDIDATE** when it also carries a cue:

- **Name cue**: a camel-case word of the base name, an argument label or a parameter name starts with
  `truncat`, `prefix`, `suffix`, `clip`, `limit`, `max`, `trim`, `shorten`, `abbreviat`, `ellips`, `elid`,
  `fit`, `budget`, `cut`, `head`, `tail`, `byte`, `width`, `column` or `length`, or is `cap`, `capped`,
  `capping`, `char`, `chars`, `character` or `characters`.
- **Body cue**: the body calls `.prefix(`, `.suffix(`, `dropLast(`, `dropFirst(` or `index(…limitedBy:`, or
  contains `break` and a line comparing the budget parameter with `<`, `>`, `<=` or `>=`.

SHAPE rows with no cue are **SHAPE-ONLY**.

## 2. Population

Three groups, reported separately and then deduplicated by file for a total:

- the **manifest corpora**, through `measurement.corpus_roots` and `measurement.source_dirs`. A corpus whose
  `localPath` is missing is looked for at `~/github_projects/<name>`, and the run says so;
- the **19 funnel repositories** (the decoder census's list), as package roots;
- the **13 unmet subjects** (Euclid, swift-docc, OpenAPIKit, jwt-kit, swift-system, Harbeth and the seven
  screened in `subject-harbeth.md`), at the HEAD of a 2026-10-05 clone.

`measurement.EXCLUDED_DIRS` applies (no `Tests`, `.build`, `checkouts`), and so does one addition:
hidden directories are skipped. A dry run of the instrument on SwiftAssist, before any population was
read, counted each function up to five times, because the checkout's `.claude/worktrees` holds whole
copies of its sources. Every subject's revision is recorded. `swiftlang-swift` (the stdlib) is not on this machine and stays in the denominator as missing.

**Controls, asserted before the population is read:** SwiftAssist's `prefix(utf8Bytes:)`, verbatim, is a
CANDIDATE with both cues; a `truncated(to:)` over `prefix(limit)` is a CANDIDATE; `repeated(_ times: Int)
-> String` is SHAPE-ONLY; `count(of: Int) -> Int` is not a SHAPE row.

## 3. Hand-check

Every CANDIDATE if ≤ 300, else a seeded 300 (`random.Random(20261005)`), plus a seeded 40 of SHAPE-ONLY to
estimate what the cue misses. The rows are frozen before any is read. Each row gets one verdict:

- **STRICT**: returns the longest prefix (or suffix) of its input whose size in some unit fits an integer
  budget. Prefix, fits and maximal hold as stated.
- **WEAK**: returns a prefix (or suffix) that fits, but not always the longest: it cuts at a word, line or
  token boundary, or rounds down. Prefix and fits hold; maximal does not, as stated.
- **MARKER**: truncates to a budget and appends a marker (`…`, `[truncated]`), so the result is not a
  prefix of the input.
- **OTHER**: anything else, such as padding, wrapping, chunking, slicing at an offset, a read that fails
  when the input is short, or arithmetic.

STRICT, WEAK and MARKER rows also record the **unit** (UTF-8 bytes, UTF-16 units, scalars, characters,
elements, display columns, lines, tokens), whether a **flag** reports the cut, the **visibility**, and
whether the function is **pure** by reading. Two independent judges classify each row, and a third
decides where they disagree. Every judgement is recorded with its reason, and every STRICT and WEAK row is
re-read before the result is written.

**A recall probe** runs beside the instrument: an independent search of every group for truncation
functions the shape misses (a constant or property-held budget, a non-integer budget, a result outside
rule 2). Its finds are counted by reason, not added to the population.

## 4. Predictions

| # | prediction |
|---|---|
| 1 | the controls hold |
| 2 | **≤ 15 STRICT** rows over all groups: most truncation is inline `.prefix(n)` or a `Collection` conformance, not a named function |
| 3 | of the STRICT rows, **≤ 3** measure in a unit where a multibyte generator matters (UTF-8, UTF-16, scalars, columns) |
| 4 | **MARKER ≥ STRICT**: truncation for display appends an ellipsis |
| 5 | the SHAPE-ONLY sample holds **≤ 2** STRICT or WEAK rows |
| 6 | if STRICT ≥ 5, one container holds **≥ 40%** of them |

This census reports against §4 of `postcondition-law-declined.md`; it does not decide. Result: `docs/measurements/budgeted-truncation-census.md`.

## 5. The generator half

The laws need inputs where the units disagree. `RawType`'s plain `String` generator draws ASCII letters and
digits; the edge-biased arm adds ASCII structure tokens; the hostile arm adds Latin-1, which is two bytes
in UTF-8 but one scalar per character. None draws a three- or four-byte scalar or a multi-scalar grapheme
(an emoji sequence, a combining mark), which is where `prefix(utf8Bytes:)`'s surviving mutants lived.
Prediction 3's unit counts say whether a multibyte arm has subjects.

## 6. What this does not answer

- A truncation with no budget parameter (a constant, a property, a configuration value) is not a SHAPE
  row. The recall probe counts these.
- A budget in points or pixels needs font metrics, so it is out of scope.
- Inline truncation (`String(text.prefix(n))`) leaves no function for a template to name.
- A text census, not a parse: both arms of an `#if` are read, and a cue spelled in a helper the body
  calls is not seen.
