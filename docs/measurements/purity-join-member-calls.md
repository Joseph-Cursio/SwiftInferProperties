# Should the purity join follow member calls, or iterate? — measured NO, on precision

> **Status:** `measured` · **As of:** 2026-11-13

**DECLINED: neither widening ships, and `PackagePurityJoin` stays as it is.** The scope froze the arms, metric and
rules before any run (`docs/plans/purity-join-member-calls-scope.md`, hash `0cf1fbe4`). Its bar was that at least 90%
of an arm's added retractions hand-check as real, and that no row the arm withholds rests on a collision. All three
arms fall short:

| arm | added retractions | real | rows withheld |
|---|---|---|---|
| **J1**: also follow `T.f()`, `Self.f()`, `self.f()` | 34 | **27 (79.4%)** | 10 |
| **J0L**: today's join, to a fixpoint | 20 | **8 (40%)** | 2 |
| **J2**: both | 152 | **120 (78.9%)** | 19 |

**Member-key resolution itself is precise: 0 of J1's misses are an owner collision.** J1 fails because it carries
retractions from wrongly refuted seeds further:
- 3 rows rest on SwiftAssist's `SwiftSourceScanner.scan`, refuted only by `ReducerPurityAnalyzer`'s `.run` token on a
  local `scanner.run()`;
- 3 rest on a trap (`precondition`, `preconditionFailure`);
- 1 is unsettled.

Two of J1's withheld rows sit on such chains: `stripComments` and `expression`.

**So the circle closes.** #722 declined to narrow `.run` because the join could not see the impurity the token stood
in for. The join cannot widen safely while `.run`'s own false refutations seed it. Counting trap-only chains as real
lifts J1 and J2 to 88.2%, still under the bar.

**Kept from this work:** a real defect fix. `FunctionSummary.withInferredEffect` and `withPurityRetracted` dropped
`globalActor`, `declaresNonisolated` and `genericParameters`, so a summary the join retracted lost its isolation and
its generics. `BuilderFieldParityTests` could not see it: it left those fields at their defaults, and it never
covered `withPurityRetracted`. It now covers both, and failed before the fix.

## The arms

One binary, one switch (`SWIFT_INFER_JOIN_ARM`, now removed), over the 116 source targets of #684's 19 pinned
trees plus this repository's `Sources/` at `main` `05d97356`. That is 13,810 summaries.

- **J0** is the shipped join: a `.pure` summary whose body calls a free-function name, every declaration of which is
  `.refuted` and non-throwing, is retracted, one hop.
- **J1** adds member keys: `Owner.name` from `T.f(…)` and `T<…>.f(…)` (uppercase `T`), and `Self.f(…)` and
  `self.f(…)` (the enclosing type). A key is resolved by the owner's last component and is refuting only when every
  declaration it names is settled.
- **J0L** and **J2** iterate J0 and J1 to a fixpoint. The census's unanimity rule is re-applied to every key in every
  round; skipping it there was the 61% defect in `docs/measurements/purity-refuting-fixpoint-census.md`.

**The control held:** J0 applied to per-file summaries reproduced the shipped package scan on every target, verdict
for verdict, so the arms differ from `main` only by what they add.

## Results

### Retractions, hand-checked

Every added retraction was traced, with its full chain down to a base declaration and that base's witness, by four
agents. Then four more tried to overturn each verdict. They disagreed on 1 row of 152, and the challenger's reading
stands. The ledger, one row per retraction, is `fixtures/purity-join-member-calls/added-retractions.tsv`.

| arm | real | false | unsure | of which: trap-only chains |
|---|---|---|---|---|
| J1 | 27 | 6 | 1 | 3 |
| J0L | 8 | 12 | 0 | 2 |
| J2 | 120 | 31 | 1 | 14 |

**What the false rows are:**

| cause | J1 | J0L | J2 | example |
|---|---|---|---|---|
| base refuted by a trap, no impurity | 3 | 2 | 14 | `GeneratorExpressionEmitter.expression` ← `EnumCaseEmitter.expression`'s `precondition` |
| base refuted by the `.run` token on a local | 3 | 0 | 5 | SwiftAssist `CodeSandbox.stripComments` ← `SwiftSourceScanner.scan` |
| bare-name collision in the cascade | 0 | 7 | 7 | SwiftAssist's `visitContainer` calls SyntaxVisitor's inherited `walk`, matched to a static `GlobTool.walk(root:)` that enumerates files |
| callee not run at call time | 0 | 2 | 4 | `InteractiveTriage.boundGenerator` returns the closure that would read the file |
| base marker on a harmless token | 0 | 1 | 1 | `MetricsRenderer.timeToAdoptionRows`: `Date` only as a dictionary's value type |

**The lessons:**
- **J1's misses are inherited, not introduced.** Every one starts from a seed the oracle refuted for something
  other than an impurity.
- **J0L's misses are the census's old failure,** name-keying, arriving through shapes the unanimity rule cannot see:
  - an inherited method shares a name with a static one;
  - an injected closure property shares a name with a static function.
- **Path insensitivity is a third, smaller cause.** `supersededDependencyIdentities` and `selfContained` pass a
  literal `nil` that short-circuits the impure branch.

### Rows

`discover --include-possible`, plain and seeded, over the 87 seeded source targets; 1,392 runs, every one exit 0.
The rows each arm withholds that J0 keeps are in `fixtures/purity-join-member-calls/rows-withheld.txt`:
- J0L: 2;
- J1: 10, including `stripComments` (a `.run`-token base) and SwiftPropertyLaws' `expression` (a trap base);
- J2: 19.

### The `.run` question

The scope ran each arm again on pre-join summaries in which `.run`'s 19 survey functions carried SEI's own verdict,
as if the token did not refute (`fixtures/purity-join-member-calls/run-variant.tsv`).

| | J0 | J0L | J1 | J2 |
|---|---|---|---|---|
| of the 8 impure `.run` hits, taken back | 0 | 1 (`build`) | **8** | 8 |
| of the 8 controls, taken back | 0 | 0 | 0 | 0 |

J1 alone reaches all 8, through `ParsingStack.run` and `LargeStackWorkers.run`, the large-stack runners, which are
themselves refuted. **That half of #722's decline is answerable.** But J1 does not ship, and the `Process.run()`
reason stands regardless, so `.run` stays.

### The frozen predictions

| # | prediction | result | held? |
|---|---|---|---|
| P1 | J1 adds 20–80 | 34 | yes |
| P2 | J0L adds 10–40; J2 adds 30–120 | 20; 152 | half: J2 over |
| P3 | J1 and J2 each at least 90% real | 79.4%; 78.9% | **no** |
| P4 | J2 withholds 5–40 rows | 19 | yes |
| P5 | of the 8 targets: J0 0, J0L 1, J1 ≤ 3, J2 ≥ 6 | 0, 1, 8, 8 | three of four: J1 took all 8 |
| P6 | no control taken back | none | yes |

## What would reopen it

- **Seeds refuted for what they are.** A trap refutes purity under SEI's definition (total), but it is not an
  impurity a law executes. A seed set that excluded partiality-only refutations would have removed 3 of J1's 7
  misses.
- **`.run` resolved by owner.** A `.run` on a local or parameter whose type is the package's own would stop seeding
  `SwiftSourceScanner.scan`, removing 3 more. That needs the type of the local, which is open item 38's index.
- **Re-measured with both,** J1 would have 1 unsettled row of 34 left. The 90% bar would then be within reach, and the
  `.run` question with it.

## Not answered

- Any callee outside the package, including `Process.run()` on a parameter.
- Instance calls on locals, parameters and expressions (open item 38).
- Whether CodeSandbox's `audit` should be refuted on its own body: it calls `Log.app.notice`, which SEI's markers miss.
  The hand-check found it in passing; it is not this join's question.
