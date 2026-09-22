# What is a passing law worth? — a mutation check over the funnel's own output

> **Status:** `proposed` · **As of:** 2026-09-22

The corpus funnel reports **577 passing laws** (22 September, 19 repositories). A pass means *no
counterexample in 100 draws*, and **no planted violator has been run against any passing law in any
census**. Every lever pulled this cycle raised that count and none of them asked what it buys. This
scopes the measurement that would: plant a small bug in the subject of a sampled passing law, re-run
the law, and count what it catches.

It answers one question per template: **when the code under a passing law changes behaviour, does
the law notice?** It does not estimate a real-bug rate — planted defects have no base rate
(`fixtures/planted-defect-arm/README.md`) — and it does not re-litigate which templates are true.

## 1. The population

Compiled stubs not reported failing, read from the 22 September census trees (≈604; the funnel's
577 also excludes 24 traps and the unaccounted). By template:

| template | laws | share |
|---|---:|---:|
| `predicate` (totality) | 391 | 65% |
| `idempotence` | 73 | 12% |
| `input-totality` | 63 | 10% |
| `guard-domain` | 16 | 3% |
| `commutativity` · `associativity` | 26 | 4% |
| `round-trip` | 11 | 2% |
| `caseiterable-key-injectivity` · `monotonicity` · `filter-subset` · `comparator` | 23 | 4% |

⚠ **Concentrated twice over.** Three quarters are totality (`predicate` + `input-totality`), which can
only fail by trapping; and SwiftProjectLint holds **294 (49%)**. A sample drawn in proportion would
measure SwiftProjectLint's totality laws and little else, so it is stratified (§3).

## 2. What each mutant is scored as — three outcomes, not two

A surviving mutant means two different things, and the whole value of the check is separating them:

| outcome | how it is decided | what it says |
|---|---|---|
| **KILLED** | the law fails, or the process traps | the law caught the change |
| **SURVIVED, DIVERGED** | the law passes, but the mutant's output differs from the original's on ≥ 1 of the same drawn inputs | **the law is blind** to a change its generator reached |
| **SURVIVED, UNEXERCISED** | the mutant's output equals the original's on every drawn input | **the generator is blind** — or the mutant is equivalent; the law was never tested |

The split needs a **differential probe**: a copy of the stub with the same seed and `sample` closure,
whose property records `String(describing: subject(input))` for every trial instead of asserting. Run
on the original and on the mutant, the draws are identical, so the outputs compare input for input.
⚠ **A probe that differs between two runs of the ORIGINAL** (addresses in a class's description,
hash-ordered collections) makes that law **undiffable**: its mutants are scored KILLED or SURVIVED
only, and counted apart.

**Kill rate is reported over DIVERGED + KILLED, never over all mutants.** An unexercised mutant is no
evidence about the law, which is `criterion-a-unmet-subject.md` §3.1's correction — *a mutant is
evidence about a law only if it violates that law* — made mechanical.

## 3. The sample

**60 laws, frozen to `fixtures/mutation-check/sample.json` before any mutant runs**, drawn with a fixed
seed:

| stratum | laws |
|---|---:|
| `predicate` | 14 |
| `idempotence` | 12 |
| `input-totality` | 10 |
| `guard-domain` | 5 |
| `commutativity` + `associativity` | 8 |
| `round-trip` | 5 |
| `caseiterable-key-injectivity` + `monotonicity` + `filter-subset` | 6 |

- **No repository supplies more than a third of any stratum** — the concentration rule.
- **pbt-book and the workbook repos are excluded.** Their code is written to teach and some of it is
  broken on purpose, so a mutant of a deliberately wrong function measures nothing.
- **Two-subject laws** (`round-trip`) mutate each subject separately, as two law-mutant pairs.

## 4. The mutants

Applied with SwiftSyntax to **the subject's own body only** — the function the stub's `Source:` line
names — in a fixed operator order, the first **three that apply** per subject:

| op | change | aimed at |
|---|---|---|
| M1 | relational boundary: `<` ↔ `<=`, `>` ↔ `>=` | off-by-one |
| M2 | negate the first `if` / `guard` condition | wrong branch |
| M3 | `return x` → `return !x` on a `Bool` result | inverted predicate |
| M4 | integer literal `n` → `n + 1` | off-by-one, and the one likely to TRAP (indexing) |
| M5 | drop one call from a method chain (`.a().b()` → `.a()`) | a skipped transform step |
| M6 | string literal `"x"` → `""` | wrong constant |

A mutant that does not compile is discarded and counted, never scored. ⚠ **No operator is chosen to
violate a particular template**: the question is what a law notices of ordinary edits, and picking
mutants per law would build the answer into the sample.

## 5. Budget

Each law runs at **100 trials — what the stub ships with** — and again at **1,000**. `criterion-a-quality-swift-system.md`
measured a real defect invisible at 100 and killed at 500, so a kill appearing only at 1,000 is a
finding about the stub's budget, not the law. Trials are cheap; the cost is the build (§6).

## 6. Harness and cost

`scripts/mutation_check.py`, **committed** — the 14 and 16 September census harnesses lived in
scratchpads and were rebuilt with the same defects. It works in the census's scratch worktrees, which
already hold the compiled stubs, and **never in a real checkout** (#560). Per law-mutant: mutate the
file, `swift build --build-tests`, run the law with `--filter '\.<Suite>/<test>\('` and the probe,
revert with `git checkout` in the worktree.

**Cost: ~180 law-mutant builds at 30–120 s each, about 3–5 hours**, run in the background and resumable
per law as the census is. SwiftProjectLintRules is the slow module.

## 7. Predictions, written before the run

| template | predicted kill rate (of exercised) | why |
|---|---|---|
| `predicate`, `input-totality` | **≤ 10%** | a totality law fails only by trapping; only M4 plausibly traps |
| `idempotence` | 20–50% | kills only mutants that break re-application |
| `commutativity`, `associativity`, `round-trip` | ≥ 50% | relational laws over two evaluations notice most output changes |
| `guard-domain` | high where the mutant touches the guard, ≈ 0 elsewhere | a characterisation law checks the guarded answer only |

And: **UNEXERCISED ≥ 30% of mutants on laws over SwiftSyntax nodes**, whose inputs are a few hundred
test snippets.

## 8. What the result decides

- **If totality kills ≈ 0 of what it exercises**, the funnel's *passes* headline is 75% laws that cannot
  notice a behaviour change. Report them as a separate *does not crash* line rather than as yield, and
  stop widening for them.
- **Where UNEXERCISED dominates**, the lever is the generator, not more laws or more widening.
- **Templates with a high kill rate** are where writer and widening effort should go next.

## 9. Not in scope

- A real-defect rate — planted mutants cannot estimate one.
- Mutants outside the subject's body, including callee changes the subject inherits.
- `verify`'s own laws: this measures the census stubs as emitted, which is what the funnel counts.
