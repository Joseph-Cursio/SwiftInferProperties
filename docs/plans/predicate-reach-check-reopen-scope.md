# Reopen #665's predicate outcome-reach check after #684: scope, frozen before the re-take

> **Status:** `proposed` · **As of:** 2026-11-13

**#665's reopen condition is met, so its census is re-taken on what shipped and its frozen rule is applied
unchanged.** #665 decided NONE at G = 42.8%. #684's generator levers then moved net +81 rows to BOTH. Under
#684's shipped arm, G is 58.9% and G_loo 58.8%, both above #665's W floor of 0.50.

**The predicted decision is W:** a warning-form reach `@Test` beside every `predicate` stub, never failing CI.

**Issue:** Joseph-Cursio/SwiftInferProperties#724. This scope changes no threshold. It names the fresh arm, the predictions, and what happens under each outcome. The
rule, the instrument and the crosscheck are #665's, by reference: `docs/plans/predicate-outcome-reach-scope.md`.

## 0. How this scope is held to its text

- **It is committed alone, before the fresh arm's funnel runs and before any census or control stub is probed.**
- **#665's §7 is not amendable,** and nothing here amends it. An amendment to this scope goes in §7 below, dated,
  before any census figure is read.
- **Every DECISION line used to decide anything is recorded,** re-runs after NOT-DECISIVE included, in a fresh
  `fixtures/predicate-reach-check-reopen/decisions.log`. #665's log stays as it is.

## 1. Why reopen, and why re-take

**The condition.** #684's frozen §6 says: if G and G_loo under the shipped arms are both at least 0.50, #665's W
floor, its write-up records the reopen condition as met, for a follow-up issue. They were (58.9% and 58.8%;
`docs/measurements/predicate-reach-at-source.md`).

**Why the #684 numbers cannot decide it:**
- #665 §1 says the population is re-taken, never reused.
- #684's arms ran binary `62f10aa8` behind a switch that no longer exists.
- #665's validation gates never ran on them: V0 (self-test), V1 (toy control) and V2a (hand oracles), which
  `instrument_ok` requires.
- Its rows carry no hand sample, so the E → W drop for constant-by-design reds cannot be computed from them.
- #684 checked byte identity with the shipped behaviour on one repository, not on all 19.

## 2. The fresh arm (A′)

| | |
|---|---|
| `swift-infer` | release binary built from `main` at `05d97356` (the merge of #723) |
| seed CLI | SwiftProjectLint at `6a231cda`, #684's |
| subjects | #684's 19 pins, `scripts/reach_arms.py` `PINS`: SwiftFormatRuleStudio at `61cfea1`, its tokenizer fix |
| toolchains | swift.org `swift-6.4.1-RELEASE`; Xcode's toolchain for the funnel's `XCODE_REPOS`, recorded at provenance |
| hashing, `NO_COLOR` | as #665 §2 |
| teaching repositories | as #665 §2, reported apart, never in the rule |

**A′'s trees are created at the pins,** with `reach_arms.prepare` into a fresh census directory, and the funnel runs
over them under `env -u SWIFT_DETERMINISTIC_HASHING`. The provenance record follows #665 §11:
- the binary's `Package.resolved`;
- every package's `Package.resolved`;
- `uptime` at the start and end;
- one row per stub.

**The instrument is #665's:**
- §3 (`scripts/predicate_outcome_reach.py run`);
- §4's gates V0, V1 and V2a, with V2b read;
- §5's classes and the stratified hand sample (`sample`, 30 reds);
- `report --record-decision` into the fresh log.

The script is the one on `main` at `05d97356`.

## 3. What the result decides

**#665 §7's frozen rule, verbatim by reference:**
- `band(x)` is E at 0.80 or above, W at 0.50 or above, NONE below.
- `instrument_ok` must hold.
- |R| must be at least 100.
- NO READING must be at most 10% of `compiled_nt`.
- The decision is the lower band of G and G_loo, with E dropped to W when constant-by-design reds weigh more than
  half.

| DECISION | What happens |
|---|---|
| **W** | #665's commits 4a and 4b. 4a shares the totality call between `_isTotal` and the reach test, byte-identical. 4b emits the reach `@Test` after `_isTotal`, predicate only, with `Self.reachNote(…)` records, the per-stub helper and the W header line. Then commit 5, the funnel re-take: arm B against A′ with #665 §9's crosscheck. **Any crosscheck difference §9 says blocks, blocks.** |
| **E** | As W, with the error-severity record and the E header line (#665 §7). |
| **NONE** (any form) | Nothing is emitted. The doc names the cause, and #665 §10's follow-up text applies. |
| **NOT-DECISIVE(…)** | Only #665 §7's bounded fix rounds; every line recorded. |

**What it does not decide:**
- the stub budget, and #665 §10's other deferrals, each on its own witness;
- kills: under W, 0 by construction under exit-status tools (#665 N9).

## 4. Predictions (frozen)

| # | Prediction |
|---|---|
| R1 | V0, V1 and V2a pass; V2b reads 10 of 10 |
| R2 | \|R\| is in [450, 500]; NO READING is 0% of `compiled_nt`; unstable is at most 5 |
| R3 | G is in [0.55, 0.63] |
| R4 | G_loo is in [0.52, 0.63], with SwiftProjectLint still the largest repository |
| R5 | **DECISION = W** |
| R6 | Constant-by-design reds weigh at most 25% of the hand sample (#665's was 14.3%) |
| R7 | Under W, arm B moves 0 law rows; the content diff is clean after #665 §9's normalisation; the reach bucket's green count equals A′'s green |

**R3 to R5 can fail on one repository.** G_loo sat 8.8 points above the floor in #684's reading. A drop of that
size in the lower of the two moves the decision to NONE, which the rule then records.

## 5. Population terms

As #665 §7: R, green, G, G_all, largest, G_loo, `compiled_nt`, `no_reading`. The 1,000-trial reading decides
nothing; if G at 1,000 is 20 or more points above G at 100, the doc files the stub-budget follow-up (#665 §7).

## 6. Not answered here

- **Kills, and criterion A.** A reach claim is not a law.
- **Receiver state** (#665 §6.1): a predicate reading a fresh receiver's never-written state stays red, and is
  right to under W.
- **The verify-side twin** (`composePredicatePass`) and `input-totality` / `measure-non-negativity`.
- **A rate.** G is the share of R in these 14 non-teaching repositories at these SHAs.

## 7. Amendments

None yet.
