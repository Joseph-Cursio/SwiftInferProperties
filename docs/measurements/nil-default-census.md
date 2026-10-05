# Does "nil means the default" have a population? — 64 sites hold, a quarter to a half a test can reach

> **Status:** `measured` · **As of:** 2026-10-05

Fix 5 would have swift-infer propose a law for any optional parameter `p` read only as `p ?? D`:

> `f(…, p: nil, …) == f(…, p: D, …)`

It comes from SwiftAssist's `ReadWindow.resolve`, where a hand-applied mutant of `maxLines ?? cap` survived
the whole suite. **The law holds by construction for the code it is read from.** It catches a later edit to
the default, and would ship labelled as doing only that. The role route was built on 36 exact sites over 11
corpora (`postcondition-law-declined.md` §4). Fix 4's census found a shape with no population outside its
own subject (`budgeted-truncation-census.md`).

The plan, shape and seven predictions are in `docs/plans/nil-default-census-scope.md`, committed before the
instrument. The instrument is `scripts/nil_default_census.py`. Every SHAPE row
(`fixtures/nil-default-census.json`) and a seeded 60 MIXED rows (`fixtures/nil-default-mixed-sample.json`)
were frozen before any was read. The judgements, re-read notes and recall finds are in
`fixtures/nil-default-judgements.json`.

## Result

| group | subjects | SHAPE | HOLDS | INCOMPARABLE | IMPURE | UNSPELLABLE | INSTRUMENT | MIXED | VOID |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| manifest corpora | 21 of 22 | 104 | 30 | 32 | 40 | 1 | 1 | 6,730 | 8 |
| funnel repositories | 19 of 19 | 45 | 10 | 8 | 26 | 0 | 1 | 1,033 | 5 |
| unmet subjects | 13 of 13 | 147 | 24 | 70 | 44 | 2 | 7 | 21,664 | 7 |
| **all, deduplicated** | **53 of 54** | **296** | **64** | **110** | **110** | **3** | **9** | | |

SHAPE, HOLDS and the other verdicts are deduplicated. MIXED and VOID are raw per-group counts. All 296 SHAPE
rows were judged, since that is under the 300 cap. **The judges disagreed on 32 rows** (11%, against 2 of 223
in fix 4), and an adjudicator settled them.

**Unlike fix 4, there is a population:**

- **64 HOLDS rows over 18 corpora.** The largest share is swift-collections' 11 (17%); then Euclid 9,
  Harbeth 8, swift-foundation 8, SwiftAssist 7 and swift-docc 5.
- **58 of the 64 are public or internal**, so a test target reaches them.
- **33 are functions and 31 initializers.**
- **I agree with 38 of a seeded 40 on re-read** (95%). The two I would change: swift-collections'
  `_UnsafeHandle.withUnsafeSegment` takes a closure and returns `(Int, R)`, so it is INCOMPARABLE.
  swift-docc's `renderReference` defaults to a throwing lookup on its receiver's context and mutates an
  `inout` argument, so it is UNSPELLABLE.

**But it thins quickly.** HOLDS does not ask whether a test can construct the inputs, and fix 4 showed that
decides the reach. Of the 38 re-read HOLDS rows I agree with:

- **11 take inputs a generator draws today.** Two of those are `private`, which leaves **9 a test can
  reach**: `ReadWindow.resolve` ×2, `joinedThinking`, `SourceLocation.init` ×2, `ProjectFile.init`,
  `FormatRule.init`, `headerColor(for:)` and Euclid's `cone`. Three of the nine are in SwiftAssist.
- **12 need a derived generator for a project or Foundation type** (Euclid's `Vector`, `Rotation` and
  `Vertex`, `Locale`, `TimeZone`, `Date`).
- **15 cannot be drawn**: noncopyable containers (`RigidArray`, `UniqueArray`, `RigidDeque`), a `Span` or
  `RawSpan`, an unsafe bit set, a Metal texture, a workspace or rendering context, or `private`.

Scaled to all 64, that is **about 14 sites a generated test reaches and draws today, and about 34 if the
derived generators come through**. The role route was built on 36 sites, and `normal-form` ships at 17.

## Read before quoting a number

- ⚠ **The verdicts come from agent judges**: two independent passes per row with different instructions,
  one describing what the code returns and one arguing the law fails, and a third pass where they disagreed
  on the verdict or on a contradicting doc. Only the 40 re-read HOLDS rows were checked by hand. The 220
  INCOMPARABLE and IMPURE verdicts were not.
- ⚠ **Drawability is my judgement from reading**, on the 40 re-read rows only. No generator was run.
- **HOLDS is by reading.** No law was run. A HOLDS row's value is in catching edits, which is what the
  template would say it does.
- **What the 220 failures are**, by keyword in the judges' reasons, so the split is approximate:
  - INCOMPARABLE (110): structs with no `Equatable` 42, classes 32, closures 13, views 3, other 20;
  - IMPURE (110): file or I/O 53, UUIDs 19, Metal or GPU state 17, shared singletons 12, other 9.

  A template would need gates for both. The scan knows `Equatable` conformances, and SwiftEffectInference
  infers purity, so neither gate starts from nothing. How precise the template is depends on those gates,
  since 220 of the 296 rows fail one of them.
- Harbeth holds 94 SHAPE rows (32%) but only 8 HOLDS. Most of its rows build Metal objects.
- The unmet subjects are at the HEAD of a 2026-10-05 clone. Harbeth, StripeKit, scale-codec-swift,
  Open-Jellycore and nocturne-swift are at the revisions `subject-harbeth.md` recorded; the other seven are
  later. All revisions are in the census fixture.

## The defaults and their docs

- **Default kinds of the 64 HOLDS rows:** an expression of other arguments 17 (`capacity ?? contents.count`),
  a literal 14, another argument 12 (`presumedLine ?? line`), an enum case or static member 11, instance
  state 8, a pure call 2. **Defaults read from other arguments are the largest class**, at 29 of 64.
- **The doc states the default for 26 HOLDS rows and contradicts it for 3:**
  - **Euclid's `Mesh.cone`** says *"The default `nil` value for poleDetail will derive value
    automatically"*. The code passes a fixed `3`. Euclid's history shows the cause. Until d9eb83a
    (2023-07-30, "Default cone's poleDetail to 3 instead of sqrt(slices)") the code read
    `poleDetail ?? Int(sqrt(Double(slices)))`, and the note was not updated. **This is the kind of edit the
    law exists to catch.** A nil-default law written before that commit would have failed on it, and pointed
    at the doc. But the template would not have written that law. Before d9eb83a the parameter was
    shadowed (`let poleDetail = poleDetail ?? …`, then `poleDetail: poleDetail`), which this instrument reads
    as MIXED, not SHAPE.
  - **swift-collections' `UniqueArray.init(capacity:copying:)` ×2** says nil means *"allocate just enough
    capacity to store the contents"*. The code starts at capacity `0` and lets appending grow it, while the
    sibling `RigidArray` uses `contents.count`. `==` ignores capacity, so the law cannot see this one.
- In passing: Harmonize's private `cacheKey(folder:)` reads `folder ?? "nil"`, so a folder named `nil` and no
  folder share a cache key. The law holds there, and pins a collision.

## Recall: how much "nil means the default" a `??`-only template misses

- **The seeded 60 MIXED rows:**

  | how the parameter is read | rows |
  |---|---:|
  | generated code | 43 |
  | stored or passed through (nil is a value) | 13 |
  | nil selects a different behaviour | 2 |
  | other | 2 |

  Only 4 mean "nil is a default", and the law would hold for 2 of them. The MIXED population is 27,941,
  mostly generated DTOs and syntax nodes (StripeKit, nocturne-swift, swift-syntax, JiraKit), so 2 of 60 is
  too few to scale with confidence.
- **The free searches hit their cap of 25 finds in all three groups**, so these are lower bounds. The funnel
  search also covered some manifest and unmet subjects, so 9 of its 76 finds repeat another group's. The
  counts below are the 67 distinct functions:

  | form | the law would hold | would not | unclear |
  |---|---:|---:|---:|
  | `guard let` / `if let … else` | 44 | 2 | 2 |
  | `p?.x ?? D` / `p.map(…) ?? D` | 10 | 1 | 1 |
  | `switch` / `p == nil ? D : …` | 6 | 1 | |

  **At least 67 functions mean "nil is a default" through syntax a `??`-only template does not read, and the
  law would hold for 60 of them**, about as many as the 64 the template does read. Those forms are not true by construction. The template would have to show that
  the nil branch equals the `D` branch. That is harder, and it is also where such a law could find a present
  bug.

## Predictions

| # | prediction | outcome |
|---|---|---|
| 1 | the controls hold | ✅ all six |
| 2 | ≥ 200 SHAPE rows | ✅ **296** |
| 3 | HOLDS ≥ 30% of the checked rows | ❌ **22%** (64 of 296) |
| 4 | of the HOLDS rows, ≥ 60% have a literal or enum / static default | ❌ **39%** (25 of 64). Defaults from other arguments are the largest class (29) |
| 5 | IMPURE ≥ 10% of the checked rows | ✅ **37%** (110) |
| 6 | no corpus holds ≥ 40% of the HOLDS rows | ✅ largest 17% (swift-collections) |
| 7 | the doc states the default for ≥ 20% of HOLDS, and ≥ 1 contradicts | ✅ **41%** (26), and **3** contradict |

## Method

`python3 scripts/nil_default_census.py controls`, then `run fixtures/nil-default-census.json` and
`mixed-sample fixtures/nil-default-mixed-sample.json`. It reads the same 53 subjects and files as the
budgeted-truncation census through that census's `subjects()`. Two extraction faults were fixed after a dry
run on SwiftAssist, before the population was read: a closure default was cut at its brace, and an identifier
inside a string literal was guessed as instance state. The judging, adjudication, MIXED classification and
free searches ran as one read-only workflow over the frozen rows.

## What this does not answer

- **Whether to build it.** The census reports. The template would need four gates: an `Equatable` result,
  inferred purity, a default a test can spell, and inputs a generator draws. It would also need a label
  saying the law catches edits. The largest default class, a default read from other arguments, is
  spellable: the test passes the same argument twice, or the expression of it.
- **The other syntax.** `guard let`/`if let` defaults are at least as common, and reading them is a
  different and harder template.
- A text census, not a parse: both arms of an `#if` are read, and a local that shadows `p` is caught only by
  the judges (9 INSTRUMENT rows).
