# The planted-defect arm — does the TEMPLATE predict whether a refutation is a bug?

> **Status:** `measured` · **As of:** 2026-08-08

The confound in `docs/plans/suspected-defect-verdict-scope.md` §4: across the only nine
refutations this project has ever produced, **tier and template are perfectly aligned** —
all four `Likely` refutations are `commutativity` (real defects, #92, fixed in #98) and all
five `Possible` ones are `idempotence` (false laws, #93). *"The tier predicts whether a
refutation is worth reading"* and *"`commutativity` refutations are defects and
`idempotence` refutations are false laws"* fit that data identically.

§9 then ran step 1 as written — three HEAD corpora — and got **zero refutations**, because
correct code does not refute. §9.1 replaced the step with `<fix>^` commits, and scouting
those found no separating arm either: every historical candidate was unreachable for a
stated reason (hash collisions, non-fixed-width type parameters, an unrelated code path).

This fixture takes the other route. Rather than hunting history for a bug that happens to
land in the empty cell, it **plants one there** — the mutant methodology
`fixtures/leaderboard-sort` already uses, pointed at a classification question.

## What it is

Three types, one method name, one tier. `combine(_:)` on each, all scored **`Likely` 70**
by `associativity` and by `commutativity`, so template and implementation vary while every
scoring signal is held constant.

| type | `combine` | associative? | commutative? | is a wrong answer a DEFECT? |
|---|---|---|---|---|
| `SumSummary` | accumulate both series | yes | yes | — (control, correct) |
| `BlendSummary` | average the totals, keep the larger count | **no** | yes | **yes — planted defect** |
| `PathSegment` | join with `/` | yes | **no** | **no — correct code, false law** |

`BlendSummary` is averaging-the-averages, the standard way this is got wrong: a summary
combiner that is not associative makes the answer depend on the order rows arrive in.
`PathSegment` is not a defect at all — concatenation simply does not commute, which the
tool's own explainability names in as many words: *"a `(T, T) -> T` need not commute
(subtraction, division, concatenation)."*

## Measured

`swift-infer 1.148.0`, `verify --all-from-index --max-parallel 2`, 2026-08-08.

| template | tier | carrier | verdict | what the refutation was |
|---|---|---|---|---|
| `associativity` | Likely 70 | `BlendSummary` | **REFUTED** trial=0 | **a real defect** |
| `associativity` | Likely 70 | `SumSummary` | held | control |
| `associativity` | Likely 70 | `PathSegment` | held | control |
| `commutativity` | Likely 70 | `PathSegment` | **REFUTED** trial=0 | **a false law about correct code** |
| `commutativity` | Likely 70 | `SumSummary` | held | control |
| `commutativity` | Likely 70 | `BlendSummary` | held | control |
| `idempotence` | Possible 35 | all three | REFUTED ×3 | false laws (`combine` is not idempotent) |

## What it settles

**The template reading is dead.** It required two things that are both now measured false:

1. *A non-`commutativity` refutation is a false law.* `associativity` on `BlendSummary`
   refutes and is a real defect.
2. *A `commutativity` refutation is a defect.* `commutativity` on `PathSegment` refutes and
   is not.

Both at the same tier, same score, same generator, in one run — so nothing about the
harness distinguishes them. The confound in §4 is broken: **template does not determine
whether a refutation is worth reading.**

## What it does NOT settle, and one thing it damages

**It does not establish the tier reading.** Every row here is `Likely` 70, so the fixture
says nothing about whether tier discriminates. What it *does* show is that at a single
high tier a refutation can be either kind — which is a **measured false positive for the
corrected `.likely` gate** in §3 of the scope note. `PathSegment`'s commutativity
refutation would be rendered *Suspected defect*, and it is not one.

That is worth stating plainly rather than filing under future work: the first thing this
arm produced for the gate it was built to support was a counterexample to it.

**And the obvious repair does not work.** The scope note first proposed consulting the
tool's own conjecture warning instead of tier alone. Measured the same day, that caveat
fires on **14 of 14** refutations on record — 5 defects and 9 false laws — because
`commutativity`, `associativity` and `idempotence` are all absent from
`Refutability.roleEntailedTemplates` by design. A body-shape reader fails more sharply:
`Decisions.merge`'s pre-fix body composed its operands positionally
(`records + other.records`), which is the same shape as `PathSegment`'s
`text + "/" + other.text`, so it would suppress the defect and keep the false law. See
`docs/plans/suspected-defect-verdict-scope.md` §11 — the conclusion there is that the fix
is the verdict's *wording*, not a better gate.

**Planted evidence cannot estimate a rate.** These three types were chosen to occupy
particular cells. The arm can *falsify* a categorical claim, which is what it was built
for; it cannot say how often a `Likely` refutation is a defect in real code. The nine
natural refutations remain the only base-rate evidence, and they are still 4/4 and 0/5.

**The ground truth is by construction.** `BlendSummary` is a defect because this README
declares its purpose to be a running summary, and a non-associative combiner defeats that
purpose. A reviewer could insist blending is intentionally order-dependent — and that
argument *is* the fork the whole feature exists to surface. The fixture does not dissolve
the fork; it shows the tool reaching a cell where the fork is live.

## Two things building it taught, both from getting it wrong first

**The fixture leaked its own answer.** The first draft documented each defect in its
docstring — *"It is not associative"* — and `DocstringPropertyCorroborator` read it and
declined to propose the law at all. Real buggy code does not carry a doc comment
describing its bug. Docstrings here are deliberately neutral and realistic, and the
explanation lives in this file instead. Same trap as the `PBT_ROAD_TEST` fixture leaking
its answer key, in a new place.

**The name is load-bearing, and it is not a detail.** `associativity` fires on
`combine(_:)` and `union(_:)` and **not** on `merging(_:)` or `adding(_:)` — measured with
a four-type probe. A fixture named the wrong way produces no rows and reads as *the tool
cannot see this*, which is the reading `docs/plans/kit-suite-backtest-plan.md` warns about
in a different context. The three types share one method name so that name signals are held
constant across the comparison; that is a control, not a convenience.

## Re-running

```
cd fixtures/planted-defect-arm
swift build
swift-infer index --target PlantedDefectArm
swift-infer verify --all-from-index --max-parallel 2
```

~35s. `.swiftinfer/` is gitignored — `index.json` stores absolute paths including the
username, the same reason the root index is not tracked. The verdicts above are the record.
