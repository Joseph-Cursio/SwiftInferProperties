# Auditing property tests that already exist — scope, with the cheap version measured and rejected

> **Status:** `open` · **As of:** 2026-08-02


**Status: scoped, not built. 2026-08-02.**

Every capability in this toolchain points at code that has *no* property tests: `discover`
proposes laws, `scaffold-kit-suites` emits the kit's conformance suites, `verify` executes
them. Nothing asks whether the property tests a codebase **already has** are any good.

The question that prompted this: *"What if we have a codebase with previously existing
property-based tests? Are we checking them for correctness? Strong enough generators?"*

The answer today is **no**, and `SwiftInferTestLifter` is why the answer looks like it might
be yes. The lifter reads existing test bodies — but to **mine** them, converting an
assert-after-transform into a `LiftedSuggestion` that feeds the +20 cross-validation signal.
It never asks whether the test it just read would catch anything.

## What "weak generator" means here, and the one worked example

`fixtures/integer-division-generator/` is the measured case, and it is the reason this is
worth scoping at all rather than dismissing.

A corpus generator for `IntegerDivision.swift`'s `Int64` arm looked entirely reasonable. It
was **stratified for sign and blind to magnitude**, so across 65,536 trials the smallest
divisor drawn was 2^53.3. Converting it moved the mutant table from **2/8 to 8/8 killed** —
six defects the test could not previously catch — with **zero interior detection lost**,
shown by two deliberate interior controls.

The load-bearing detail for this scope: **the weak generator did not look weak.** A reviewer
grepping for `random(in: 0..<100)` walks straight past `stratified-for-sign`. That is the
whole difficulty.

## The cheap static version was measured, and it finds nothing here

The obvious first cut is a lint pass: flag unbounded numeric draws (`Gen<Int>.int()` with no
`in:`), since an unbounded draw is what made `scaffold-kit-suites` trap on `Score` (PR #43).

Measured across this repo's 8 real property-test files:

| numeric draws | count |
|---|---:|
| bounded (`Gen<Int>.int(in: …)`) | **11** |
| unbounded | **0** |

**The check would fire zero times.** And that is not because the tests are beyond reproach —
it is because the naive weakness is the one people already avoid. The weakness that actually
cost refutation power in the one measured case was *invisible to exactly this kind of check*.

So the cheap version is not a smaller first step toward the real thing. It is a different,
much weaker thing that would report a clean bill of health on a corpus nobody has audited.

## What detection actually requires

The `integer-division` weakness was found by **running mutants** — take the function under
test, perturb it, and see whether the existing test's generator produces an input that
catches the perturbation. That is execution, not analysis, and it means:

- A build of the subject, per mutant. `docs/measurements/roadtest-self-dogfood.md` §15 already carries a
  metamorphic cost estimate; this is the same order.
- A mutation operator set. The leaderboard fixture has 7 hand-written mutants for one sort;
  generating them per-function is its own project.
- A way to attribute a survived mutant to the **generator** rather than to the **law**. A
  mutant surviving because the property is too weak is a different finding from one surviving
  because the domain is too narrow, and the remedy differs. `fixtures/leaderboard-sort`'s
  mutant × law matrix exists precisely because those two are confusable.

## Scoring, if it is built

**In refutation units, not coverage.** `fixtures/integer-division-generator`'s README makes
the argument: the coverage table (0/17 → 17/17 edge classes) only says boundary values are
*present*; the mutant table (2/8 → 8/8) says the test catches things it could not before.
Report the second.

This is the same rule as *"score refutability, not suggestion count"*, applied to a test
someone else wrote.

## Recommendation

**Do not build the lint pass.** It is cheap, it is measurable, and it would find nothing —
the worst combination, because a green result would be read as "your generators are fine".

The execution-based version is a real project with a real payoff, and the honest sequencing
is to treat it as one: a scope of its own, with the mutation-operator question answered
first, since that is the part with no prior art in this repo.

**One thing worth doing regardless, and cheaply:** the population question is unanswered.
This repo has 46 property-based tests, 44 of them driven by its own `propertyCheck` harness
and 2 by the kit. Whether the lifter *recognises* those 46 is the ceiling on any audit built
on top of it, and it is one measurement — run the lifter over `Tests/` and compare. If
recognition is low, an audit built on lifting is bounded before it starts.
