# Reopen #665's predicate outcome-reach check after #684: scope, frozen before the re-take

> **Status:** `shipped` · **As of:** 2026-11-13

**#665's reopen condition is met, so its census is re-taken on what shipped and its frozen rule is applied
unchanged.** #665 decided NONE at G = 42.8%. #684's generator levers then moved net +81 rows to BOTH. Under
#684's shipped arm, G is 58.9% and G_loo 58.8%, both above #665's W floor of 0.50.

**The predicted decision is W:** a warning-form reach `@Test` beside every `predicate` stub, never failing CI.

**Result (2026-11-13): DECISION W, at G = 58.9% and G_loo = 58.8%**
(`docs/measurements/predicate-reach-check-reopen.md`). Commits 4a, 4b and 5 are done (2026-11-13): the crosscheck
found 0 blocking differences after one emitter fix, and R7 held.

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

**A1 (2026-11-13, before any census figure was read): A′ withholds the one law that opens a URL on the host, as
#684's amendment A6 did.**
- **Why.** A′'s fresh SwiftLintRuleStudio tree carried no skip marker, so `discover` emitted the `predicate` law over
  `SystemXcodeLauncher.open(_:)` (identity `0x83347B0CF1C8F7D8`), which is `NSWorkspace.shared.open(url)`. The
  funnel ran it, and the pinned kit (4.10.0 and 4.11.0, both before SwiftPropertyLaws#99's `.invalid` hosts) drew
  `example.org` URLs, so it opened browser pages on the user's machine. The user stopped the run by reporting it.
- **What was done.** A′'s funnel was killed during pbt-book, after SwiftLintRuleStudio had finished. SwiftLintRuleStudio
  alone was reset (`reach_arms.reset_repo`), re-created at `77cc792`, and given one comment-only file holding
  `// swiftinfer: skip 0x83347B0CF1C8F7D8`. Before the funnel resumed, `discover --include-possible` on that target named
  the identity zero times. The funnel then resumed and re-ran SwiftLintRuleStudio and pbt-book. The repositories it had
  already finished keep their results.
- **Every other match was checked.** Files that mention `NSWorkspace` or similar exist in SwiftAssist, SwiftProjectLint,
  SwiftLintRuleStudio, MacCloud_client_MacOS and SwiftUMLStudio. Of the laws emitted before the stop, only this one has
  a subject that opens anything. The `CodeSandbox` and `ConcreteTypeUsageVisitor` laws name the word in rule tables.
- **What it can move.** That row was ONLY-TRUE in every #684 arm, so it was a red row in R. Withholding it can raise G
  by at most one row's share, about 0.1 point, and G_loo by about 0.4. SwiftLintRuleStudio is not the largest
  repository, so that change applies to G_loo as well as G. Either way it is under R3's and R4's widths. The doc
  reports G with the row restored as red beside the measured G, so no reading depends on it.

**A2 (2026-11-13, while building 4b, before commit 5 ran): a suite that carries a reach test is `@Suite(.serialized)`,
and #665 §9's normalisation drops that one line.**
- **Why.** #665 §9 and the emitter assumed the reach test runs after its law, so that it sees the subject after the
  law's 100 calls, the census's `class_again`. That holds only under `--no-parallel`, which every harness passes. A
  plain `swift test` runs a suite's tests at once. On the V1 toy's `Sightings.isFirstSighting`, a subject with an
  unsynchronised static set, the law and its reach test then raced. The test process crashed in 10 of 10 parallel runs,
  and a run that finished could name either side. The law alone never crashed. An adversarial review of 4b found this
  and two verifiers reproduced it.
- **What changed.** The suite line of a stub with a reach test is preceded by `@Suite(.serialized)`
  (`InteractiveTriage.suiteTraitLine`). `strip_reach` drops that line only where it sits directly on the suite's
  `struct`, and the probe's self-test checks both that it is dropped and that the trait anywhere else is not.
- **Which section it overrides.** #665 §9's normalisation list, step 1, which now names four shapes, not three. #665 §7
  is not touched: the reach check is still its own `@Test` after `_isTotal`, in the W form. The rejected alternative,
  running the reach loop inside `_isTotal`, is the "record inside `_isTotal`" row that §7 rejects.
- **Not changed, and recorded instead:** the helper's `#if compiler(>=6.3)` guard reads the compiler, not the Testing
  library linked. A test target that builds the swift-testing package below 6.3 from source gets a 6.3+ compiler and an
  `Issue.record(_:severity:)` that is still SPI there, so its predicate files stop compiling. §7 fixes the W form as this
  helper and is not amendable, so the case is documented, not fixed. No corpus package builds swift-testing from source.

**A3 (2026-11-13, before arm B's funnel ran): arm B is A′'s binary plus 4a and 4b, not a build of `main`.**
- **Why.** #665 §9 step 1 makes arm B differ from arm A only by the reach work, and it blocks on any stub-path or
  content difference. `main` at `d6b5a225` also carries SEI `ba3624d` (#727), which moves verdicts: on
  SwiftLintRuleStudio it withholds `MirrorLock.isHeld`, a predicate in A′. A build of `main` would fail step 1 for a
  reason that has nothing to do with the reach test.
- **What arm B is.** `05d97356`, A′'s commit, with `git diff 25434303 d6b5a225 -- Sources` applied: exactly #729's 4a and
  4b sources. Those files and the one source file changed between `05d97356` and `25434303`
  (`FunctionSummary+Builders.swift`, #725) are disjoint. It was built with A′'s `Package.resolved` copied in, and the
  resolved pins are identical to A′'s.
- **What is unchanged.** The funnel scripts are byte-identical between `05d97356` and `d6b5a225`. The crosscheck runs
  `scripts/predicate_outcome_reach.py` at `d6b5a225`, which carries amendment A2's normalisation. SwiftLintRuleStudio's
  tree carries A1's skip marker, as A′'s did.
