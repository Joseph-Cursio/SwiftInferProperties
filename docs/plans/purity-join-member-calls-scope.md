# Let the purity join see impurity behind member calls: scope, frozen before the build and the runs

> **Status:** `declined` · **As of:** 2026-11-13

> **Ran and decided 2026-11-13: nothing ships.** J1 79.4% and J2 78.9% of added retractions hand-checked real,
> against a 90% bar; J0L 40%. The result is `docs/measurements/purity-join-member-calls.md`. This scope stays as
> frozen (hash `0cf1fbe4`, recorded before any run), with no amendments.

**`PackagePurityJoin` takes back a `.pure` verdict only one hop up, and only through a bare free-function name.**
So an impurity reached through `Type.method(…)`, or two calls down, stays `.pure`. This scope measures two
widenings, each A/B'd and scored on hand-checked retractions and on the rows the impure-subject veto then withholds:
- **J1:** also resolve type-qualified member calls;
- **J2:** iterate the join to a fixpoint.

**The predicted outcome is that J1 and J2 both ship, catching most of the impurity the `.run` token now stands in
for.** Below are the frozen rules that decide what ships.

## 0. How this scope is held to its text

- **It is committed alone, before any join code or any run.** An amendment after the freeze goes in §8, with its
  reason, and never changes §5's rules or §6's predictions once an arm has run.
- **Arms run in the order J0, J0L, J1, J2,** over the same trees, from one binary, differing only in the switch.

## 1. Why

PR #722 stopped `ReducerPurityAnalyzer` refuting purity on TCA's `Effect` names, and declined to narrow `.run`
(`docs/measurements/reducer-purity-name-tokens.md`). The decline had two reasons:
- **8 of `.run`'s 19 hits would read `.pure` while impure** through calls neither SEI nor the join follows:
  - SwiftUMLStudio's `SyntaxStructureProvider.build` (a SourceKit request, two bare calls down);
  - this repo's `PackagePurity.forScan` and `forJudging` (file reads through
    `ConstructionUniverse.universe(forScanOf:)`);
  - SwiftUMLStudio's six `extract(from:…)` (a thread, and a global notice three calls down, through
    `ParsingStack.parse` → `NestedSquareBrackets.readable` → `SourceReadNotices.record`).
- **`Process.run()` on a parameter.** For a `Process` passed in, nothing but the token refutes the spawn. No join can
  see it: the callee is Foundation's.

This scope answers the first reason only. The second needs a different design, and §7 says so.

**What the join does today** (`PackagePurityJoin`, open item 43, `docs/measurements/purity-refuting-fixpoint-census.md`):
- A name **refutes** when every package declaration of it is `.refuted` and does not throw.
  - A non-throwing `.refuted` cannot be ignorance-only, so it carries a witness.
  - Unanimity is what keeps a bare name sound.
- A `.pure` summary whose body calls a refuting name is retracted to `.refuted`.
- **`CalleeNameCollector` collects free-shape calls only, by design.** `receiver.foo()` names a member of an
  unresolved type, and joining on it would match `encode` on any type against `encode` on any other.
- The census measured the loop on this repo: 18 rows at one hop, 29 at fixpoint. Its first answer, 75, was 61%
  name-collision artifacts, because the cascade skipped the unanimity rule.

## 2. The arms

One binary, one hidden switch, `SWIFT_INFER_JOIN_ARM`, read where the scan applies the join. Unset is J0, so the
binary matches `main` until the switch is set. The switch is removed in the cleanup commit, as #684's was.

| arm | what retracts a `.pure` summary |
|---|---|
| **J0** | today's join: a call to a refuting free-function name, one hop |
| **J0L** | J0 iterated to fixpoint: a retracted caller can make its own name refuting |
| **J1** | J0, plus a call to a refuting **member key**, one hop |
| **J2** | J1 iterated to fixpoint, over both kinds of key |

**A member key is `Owner.name`.** It is collected only from shapes whose owner the syntax names:
- `T.f(…)` and `T<…>.f(…)`, where `T` is an identifier starting with an uppercase letter;
- `Self.f(…)` and `self.f(…)`, resolved to the enclosing type.

It resolves against summaries whose `containingTypeName`'s last component is `Owner`. Owner is compared by last
component, as `PreconditionHelperHop` does.

**A key refutes only when every declaration it resolves to is settled impure with a witness.** That means `.refuted`
and non-throwing, or retracted by the join in an earlier round. The rule applies to every key the cascade adds, not
only to the seed: skipping it there was the census's 61% defect.

**Anything else stays out:** a call on a local or a parameter (`scanner.run()`, `generator.run(using:)`), and a call
on an expression.

**The veto follows the join.** `TemplateRegistry.isImpureWithWitness` lets a throwing `.refuted` subject through
unless it calls a refuting free-function name. It gains the same clause for member keys, so a throwing subject the
join retracted through a member call is withheld just like one retracted through a free name. Without it, J1 and J2
would move verdicts that no row ever reads.

## 3. Population and pins

- **Verdicts:** every function in the 116 source targets of #684's 19 pinned trees (`scripts/reach_arms.py` `PINS`,
  SwiftFormatRuleStudio at `61cfea1`), plus this repo's `Sources/` at `main` `05d97356`, about 12,000 functions.
  These are the trees and targets #722's survey used.
- **Rows:** `discover --include-possible`, plain and with each repository's seed manifest, over the 87 seeded source
  targets, as #721's and #722's A/Bs ran.
- SEI stays at `5fbee6f`, kit 4.11.0, toolchain swift-6.4.1.

## 4. What is counted

- **Retractions per arm.** The `.pure` summaries the arm takes back that J0 leaves `.pure`, each with the key that
  justified it, the declaration it resolved to, and the hop.
- **Precision.** Every added retraction is hand-checked: is an impurity reachable from a call of the subject, at call
  time, through the callee the arm named? If one arm adds more than 150, a sample of 150 is drawn with a recorded
  seed, and precision is quoted with its denominator.
- **Rows withheld.** The suggestions each arm's veto removes that J0's keeps, every one hand-checked by its subject.
- **The `.run` targets.** Each arm runs a second time on pre-join summaries in which the 19 `.run` survey functions
  carry SEI's own verdict, as if `.run` did not refute. That tells how many of the 8 impure ones each arm takes back.
  It also tells whether the 8 controls stay `.pure`:
  - SEI's `combine` and `nameGatedInference`;
  - pbt-book's `isKilled` and `mutationScore`;
  - SwiftAssist's `scan` and `scanUnlexed`;
  - SwiftUMLStudio's `detectCycles`;
  - SwiftPropertyLaws' `draw`.

## 5. What the result decides (frozen)

- **J1 ships over J0** when both hold:
  - at least 90% of its added retractions hand-check as real;
  - no row it withholds rests on a name or owner collision.
- **The loop ships on top of whichever one-hop arm ships** (J2 over J1, or J0L over J0) under the same two
  conditions, applied to the retractions the loop alone adds.
- **If nothing ships,** the doc records why, and the join stays as it is.
- **Every retraction that hand-checks false is named in the write-up,** with its cause.
- **What it does not decide:** narrowing `.run`. If a shipped arm takes back all 8 impure targets and none of the 8
  controls, the write-up says the first of #722's two reasons is answered. The `Process.run()` reason stands either
  way (§1), so `.run` is a separate issue.

## 6. Predictions (frozen)

| # | Prediction |
|---|---|
| P1 | J1 adds 20–80 retractions over J0 |
| P2 | J0L adds 10–40 over J0; J2 adds 30–120 over J0 |
| P3 | J1's and J2's added retractions are each at least 90% real |
| P4 | J2 withholds 5–40 rows that J0 keeps, plain and seeded runs together |
| P5 | Of the 8 impure `.run` targets: J0 takes back 0, J0L 1 (`build`), J1 at most 3, J2 at least 6 |
| P6 | None of the 8 controls is taken back in any arm |

## 7. Not answered here

- **`Process.run()` on a parameter**, and any impurity in a callee outside the package. The join sees only package
  declarations.
- **Instance calls on a local, a parameter or an expression.** Their owner needs a type the syntax does not give;
  that is open item 38 (an index).
- **Promoting the other way:** a callee being pure never makes a caller pure. That was declined twice
  (`docs/measurements/purity-blocking-callee-census.md`).

## 8. Amendments

None yet.
