# Does "nil means the default" have a population?

> **Status:** `open` · **As of:** 2026-10-05

SwiftAssist's `ReadWindow.resolve(lineCount:startLine:maxLines:cap:)` reads two optional parameters through
`??`: `startLine ?? 1` and `maxLines ?? cap`. A hand-applied mutant of the second default survived the whole
suite (swift-mutation-testing has no `??` operator), and the law that now kills it is *omitting `maxLines`
behaves like passing `cap`*. Fix 5 would have swift-infer propose that law for any function whose optional
parameter `p` is read only as `p ?? D`:

> `f(…, p: nil, …) == f(…, p: D, …)`

**The law holds by construction for the code it is read from**, so it finds no present bug: it catches a later
edit to the default, or a default that disagrees with what the doc promises. It would ship labelled that way,
as determinism's TAUTOLOGY header already is. The route reads the body, and a body-reading route was declined
once for concentration (`postcondition-law-declined.md` §3). The role route was built on **36 exact sites over
11 corpora**, and `normal-form` ships at 17. `budgeted-truncation-census.md` found a shape with no population
outside its own subject. This census asks the same question of this law before anything is built.

## 1. The shape — fixed now

A text census over masked source, braces matched, over every `func` and `init` with a body. For each parameter
whose type is written `T?` or `Optional<T>`, its **reads** are the occurrences of its internal name in the body
as an identifier: not after `.`, and not before `:`. The parameter makes a **SHAPE** row when:

1. **Every read is the left operand of `??`.** `p?.x ?? D`, `if let p`, `guard let p`, `p == nil` and `p.map`
   are other reads.
2. **Every read has the same default** `D`: the text after `??` up to the first `,`, `)`, `]`, `}`, `;`, `{`,
   line end, comparison, `&&`, `||`, ternary `?` or assignment at depth 0. String literals are kept.
3. **There is a value to compare**: a `func` with a non-`Void` result, or an `init`.

Each row records `D` and a guessed **default kind**: literal, enum case or static member (`.zero`,
`Self.limit`), another parameter, an expression of parameters, instance state, or a call. It also records the
read count and the doc comment above the declaration. The parameters that fail rule 1 (**MIXED**) and the
`Void` functions that pass 1 and 2 (**VOID**) are counted, not judged.

## 2. Population

The 53 subjects of `budgeted-truncation-census.md`, through that census's `subjects()`: 21 of 22 manifest
corpora, 19 funnel repositories and 13 unmet subjects at their 2026-10-05 HEADs, with hidden directories,
`Tests`, `.build` and `checkouts` skipped. `swiftlang-swift` is missing. Revisions are recorded, and rows are
deduplicated by file, line and parameter.

**Controls, asserted before the population is read:**
- SwiftAssist's `resolve`, verbatim, gives exactly two SHAPE rows, `startLine` with `D = 1` and `maxLines`
  with `D = cap`;
- `x ?? "none"` keeps its string literal as `D`;
- `(x ?? 1) + 2` gives `D = 1`;
- `if let x` gives no row;
- `x ?? 0` beside `x == nil` is MIXED;
- `print(x ?? 0)` in a `Void` function is VOID.

## 3. Hand-check

Every SHAPE row if ≤ 300, else a seeded 300 (`random.Random(20261005)`). The rows are frozen before any is
read. Each row gets one verdict:

- **HOLDS**: the law holds for every input. `D` can be spelled at a test's call site with the same value (a
  literal, an enum case or static member a test can see, another argument's value). The result can be compared
  with `==`, and `f` is deterministic.
- **UNSPELLABLE**: it holds, but no test can spell `D` with the same value (a private constant, instance state
  a test cannot set, a private helper's result).
- **INCOMPARABLE**: it holds, but the result has no `==` (a view, a closure, a non-`Equatable` class).
- **IMPURE**: `f(nil)` and `f(D)` can differ for a reason other than `p`: `D` or `f` reads the clock,
  randomness, I/O or global mutable state, or mutates.
- **INSTRUMENT**: not the shape. `p` is read another way, is shadowed or not optional, or `D` was mis-extracted.

Each row also records the judged **default kind**, whether the **doc** states the default, contradicts it or is
silent, the **visibility**, and whether the result is **Equatable**. Two independent judges classify each row,
and a third decides where they disagree. Every HOLDS row is re-read if there are ≤ 40, else a seeded 40.

**A recall probe** runs beside it. It is an independent search of every group for functions where nil means a
default through other syntax: `guard let p … else`, `if let`, `switch`, `p.map(…) ?? D`, `p?.x ?? D`. Those
are counted by form, to see how much of "nil means the default" a `??`-only template would miss.

## 4. Predictions

| # | prediction |
|---|---|
| 1 | the controls hold |
| 2 | **≥ 200** SHAPE rows, deduplicated, over the 53 subjects |
| 3 | **HOLDS ≥ 30%** of the checked rows |
| 4 | of the HOLDS rows, **≥ 60%** have a literal or an enum-case / static-member default |
| 5 | **IMPURE ≥ 10%** of the checked rows, from clock, identifier and I/O defaults |
| 6 | **no corpus** holds ≥ 40% of the HOLDS rows |
| 7 | a doc comment states the default for **≥ 20%** of the HOLDS rows, and **≥ 1** contradicts its code |

This census reports against §4 of `postcondition-law-declined.md`; it does not decide.

## 5. What this does not answer

- A default parameter value (`func f(x: Int = 5)`) is substituted by the compiler, so `f() == f(x: 5)` holds
  trivially. It is not this shape and is not counted.
- A text census, not a parse: both arms of an `#if` are read, and a local that shadows `p` is caught only by
  the judges.
- HOLDS means the law holds by reading. No law is run, and a HOLDS row's value is in catching edits. Prediction
  7's contradicting docs are the exception, and the only rows where the law could find a present bug.
