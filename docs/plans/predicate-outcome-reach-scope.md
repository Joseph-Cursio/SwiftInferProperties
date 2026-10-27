# Do a predicate stub's draws reach both answers? A census first, then a reach check only if it says so (#665)

> **Status:** `proposed` · **As of:** 2026-10-27

The `predicate` template's stub is totality, `_ = f(x); return true`, labelled ENTAILED. The label is
true, but for a `Bool`-returning subject a pass states only that nothing trapped on the inputs drawn. It
never says which answers those inputs got back. Only a trap or a hang can fail the stub. Under the kit's
fixed generators, totality refuted 0 of 102 on real code (`docs/measurements/template-refutation-rates.md`).
That doc's 2026-09-22 annotation records the one later refutation, a hang reached only with the subject's
own literals.

`docs/measurements/roadtest-swiftumlstudio-mutation.md` F2 measured what that costs on one package. On
SwiftUMLBridge, 10 `predicate` stubs compiled and passed, and they killed **0 of the 16 mutants** inside
their subjects. A test was added beside each stub, with the same generator, seed and 100 trials, asserting
that both `true` and `false` were returned:

- **7 of 10 fail on unmutated code, all returning only `false`:** `isStaticOrClass`, `isStatic`,
  `isAddTaskCall`, `isTaskGroupName`, `hasAttribute`, `isMatching`, `isExcluded`.
- **The 3 that pass** (`hasModelAttribute`, `conformsToGRDBRecord`, `pathContainsGlobSyntax`) took
  mutation kills **16 → 20 of 1,274** viable mutants, losing none. One of the new kills,
  `PersistenceSchemaExtractor.swift:192` `false` → `true`, also survives the hand-written suite, which kills
  770 of 1,274.

Issue #665 proposes emitting that test, an outcome-reach check, beside every `predicate` stub. One package
is a witness, not a rate. This scopes the census that comes first, and freezes, before any census or
control stub is probed, the rule by which its result decides whether the check is emitted and how.

**The predicted DECISION is NONE (P3b), with W the stated alternative.** Under any NONE, nothing is
emitted: the PR ships this scope, the probe, the harness bucket and the measurement doc, with no emitter
change, and a follow-up issue names the cause (§7, §10). That outcome is planned for, not a failure.

## 0. How this scope is held to its text

- **It is committed alone, before arm A's funnel run starts and before the probe is committed.** The
  harness-bucket commit (§4) is the only commit of this work before it. The probe,
  `scripts/predicate_outcome_reach.py`, and its toy fixture, `fixtures/predicate-outcome-reach/toy/`, land
  in a later commit, before any census or control stub is probed. V0 and V1 (§4) must pass in that commit.
- **Anything the implementation forces to differ from this text is recorded as a dated amendment in §12,
  before any census figure is read.** It is never a silent edit to the section it changes. Each amendment
  says what changed, why, and which section it overrides.
- **An amendment may change how a §4 gate is implemented, never what it requires.** Changing a gate's
  condition after that gate has been run is a fix round under §7's NOT-DECISIVE(instrument) line, and
  counts toward its two.
- **The one exception to "before any census figure is read" is a fix made in one of §7's bounded fix
  rounds.** It is recorded in §12 as a dated amendment that quotes the DECISION line, or the failing gate's
  verdict line, that triggered it.
  - A NOT-DECISIVE(no-reading) fix names the NO READING causes it addresses, and may change only how those
    rows are read: never a row that already read BOTH, ONLY-FALSE, ONLY-TRUE, TRAPPED or HUNG, and never
    §5's classes, flags or hand check.
  - A NOT-DECISIVE(instrument) fix re-runs every gate, and re-probes every row of a census that had
    already run.
- **§6 (the predictions) and §7 (the frozen rule) are not amendable**, before or after the run. If the
  implementation cannot compute one of §7's inputs as written, that is treated as a failed §4 gate:
  NOT-DECISIVE(instrument), counted toward §7's two fix rounds, not an amendment.
- **The measurement doc cites this scope by the SHA it was committed at**, so "not tuned to the answer" is
  checkable in `git log`, the practice `docs/measurements/lexer-corpus-prediction.md` follows.
- **Its status moves with the result.** Under E or W it becomes `open` when the measurement doc lands, and
  `shipped` after the funnel re-take (§9). Under any NONE it becomes `shipped` when the measurement doc
  lands.

N-numbered references (N1, N9, …) are the design measurements in the appendix.

## 1. Question

**Of the funnel's compiled `predicate` stubs, how many reach both answers, `true` and `false`, at their own
seed in their own 100 trials?** And so: is an outcome-reach check emitted beside every `predicate` stub as
a failure (E), as a warning (W), or not at all (NONE)?

Why the census comes first:

- **The check rides on every emitted `predicate` stub**, and `predicate` is the funnel's largest law
  class. F2's 7 of 10 is one package.
- **The census decides the presentation.** If most checks are red, a failing test on hundreds of correct
  subjects is noise that readers learn to delete.
- **It prices the payoff.** The check can kill only behind a green baseline, so its kills scale with the
  green share.
- **The population is re-taken, never reused.** The issue's 391 `predicate` + 63 `input-totality` of
  ~604 compiled laws (`docs/measurements/funnel-mutation-check.md` §1) is from 2026-09-22, before the
  road test's F1 `NO_COLOR` fix and the swift.org 6.4.1 pin. Arm A (§2) re-takes it.

`docs/measurements/totality-generator-reach.md` is the trap-side twin: whether the totality generator
reaches the inputs that trap. This census is the outcome side.

## 2. Population

**Arm A** is the funnel run whose compiled stubs this census reads.

| | |
|---|---|
| `swift-infer` | release binary built from `main` at `fef2971d`; `--version` prints `1.160.0 (fef2971d)` |
| seed CLI | SwiftProjectLint at `eec21fbb` |
| toolchains | swift.org `swift-6.4.1-RELEASE`; Xcode's `swiftlang-6.4.0.34.1` for the funnel's `XCODE_REPOS` |
| hashing | `SWIFT_DETERMINISTIC_HASHING` unset in the shell at provenance; the funnel runs under `env -u SWIFT_DETERMINISTIC_HASHING` |
| `NO_COLOR` | set for every SwiftPM call by `corpus_funnel_stage5.swift_environment` |

**The binary's own resolved pins (N13).** `Package.resolved` is untracked, and the work tree the binary
was built in resolves differently from the main checkout. So the binary's own file is copied into the
run's provenance record, and the pins are quoted from that file:

| dependency | resolved in the build work tree |
|---|---|
| SwiftPropertyLaws (the kit) | 4.10.0 (`9e774fb`) |
| swift-property-based (the engine) | 2.0.1 (`7d405e7`); the main checkout resolves 2.0.0 |
| swift-syntax | 602.0.0 |
| swift-collections | 1.7.5; the main checkout resolves 1.6.0 |
| SwiftEffectInference | `f34cee3`, a revision pin |
| swift-argument-parser · swift-async-algorithms · swift-numerics | 1.8.2 · 1.1.7 · 1.1.1 |

At provenance time the kit's newest remote tag was `v4.10.0` and the engine's `2.0.1`. Each subject
package resolves its own kit and engine; those are read from its `Package.resolved` after the run.

**The 19 repositories, recorded 2026-10-27, before arm A's run** (`git -C ../<repo> rev-parse --short
HEAD` and `git -C ../<repo> status --porcelain`, run from the work tree):

| repository | SHA | branch | porcelain | toolchain | teaching |
|---|---|---|---|---|---|
| SwiftMarkdownWiki | `2a6d0d5` | `main` | clean | Xcode | |
| SwiftProjectLint | `eec21fbb` | `main` | clean | swift.org | |
| SwiftAssist | `6974842` | `main` | clean | Xcode | |
| SwiftPropertyLaws | `9e774fb` | `main` | clean | swift.org | |
| SwiftUMLStudio | `b8b1520` | `main` | clean | Xcode | |
| SwiftLintRuleStudio | `8b99ba7` | `main` | clean | Xcode | |
| pbt-workbook-corpus | `0ea4b22` | `main` | clean | swift.org | yes |
| pbt-book | `3b8ff81` | `main` | clean | swift.org | yes |
| SwiftFormatRuleStudio | `149526d` | `main` | clean | Xcode | |
| SwiftEffectInference | `f5014fb` | `date-named-as-a-type` | `?? main.swift` | swift.org | |
| SwiftLintRuleStudioTeam | `7789bde` | `main` | clean | Xcode | |
| MacCloud_client_MacOS | `a7376fd` | `main` | clean | Xcode | |
| SwiftCloneDetector | `c21171e` | `main` | clean | Xcode | |
| pbt-workbook-sampler | `0e07795` | `main` | clean | swift.org | yes |
| LintStudioUI | `73e31b1` | `main` | clean | Xcode | |
| MacCloud_server | `51c91cf` | `main` | clean | swift.org | |
| SwiftIdempotency | `5863dad` | `main` | clean | swift.org | |
| pbt-workbook | `959937e` | `main` | clean | swift.org | yes |
| pbt-workbook-grader | `79e6c81` | `main` | clean | swift.org | yes |

- **SwiftEffectInference is on its `date-named-as-a-type` branch at `f5014fb`, not `main`**, with one
  untracked file, `main.swift`. It is recorded, not cleaned. This is the subject tree; the binary's own
  SEI dependency is the `f34cee3` pin above.
- **SwiftUMLStudio's HEAD is `b8b1520`.** The road test ran at `e36da59`, which V2 (§4) pins in a
  detached worktree (N6).
- **Teaching repositories** are `mutation_check.EXCLUDED_REPOS`: pbt-book, pbt-workbook,
  pbt-workbook-corpus, pbt-workbook-sampler and pbt-workbook-grader. Every figure is reported for them
  apart, and they never enter §7's rule.

**Arm A's run.** Every package's `Package.resolved` is copied out afterwards, and `du -sh` is recorded.

```
env -u SWIFT_DETERMINISTIC_HASHING python3 scripts/corpus_funnel.py <scratch>/census-A <bin>/swift-infer-A-fef2971d <bin>/CLI-eec21fbb \
  SwiftMarkdownWiki SwiftProjectLint SwiftAssist SwiftPropertyLaws SwiftUMLStudio SwiftLintRuleStudio \
  pbt-workbook-corpus pbt-book SwiftFormatRuleStudio SwiftEffectInference SwiftLintRuleStudioTeam \
  MacCloud_client_MacOS SwiftCloneDetector pbt-workbook-sampler LintStudioUI MacCloud_server SwiftIdempotency \
  pbt-workbook pbt-workbook-grader > <scratch>/census-A.log 2>&1
```

**The census population is every compiled `predicate` stub in arm A's trees:**

- **Packages:** every package entry of every `result-<repo>.json` with `built` true. The package directory
  is `realpath(<census>/trees/<repo>/<entry["package"]>)`.
- **Stubs:** `predicate/*.swift` in the package's census target (`mutation_check.census_target_dir`),
  minus `*_Reach.swift`.
- **A package with no stage-5 verdict** (`passed is None`): each of its predicate stubs becomes a NO READING
  `package-no-verdict` row. It counts in `compiled_nt` and is not probed.
- **`law_a`**, each row's arm-A outcome, from the harness bucket's fields: `passed_tests` → `passed`,
  `failures` → `failed`, `crashed_tests` → `crashed`, `hung_tests_all` → `hung`, a no-verdict package →
  `no-verdict`, anything else → `unknown`. §7's R takes only `law_a == passed`.

## 3. Instrument

`scripts/predicate_outcome_reach.py`, run from the repository root:

```
python3 scripts/predicate_outcome_reach.py --self-test                                       # V0, pure Python, in make measurement-selftest
python3 scripts/predicate_outcome_reach.py validate <scratch> <swift-infer> [--rand-runs 8]   # V1, the toy control
python3 scripts/predicate_outcome_reach.py run <census-dir> <out.jsonl> --arm <arm> [repo …]  # V2 (arm control-e36da59) and the census (arm census)
python3 scripts/predicate_outcome_reach.py run --package <dir> [--package <dir> …] <out.jsonl> --arm <arm>   # list mode: law_a = unknown
python3 scripts/predicate_outcome_reach.py oracle <out.jsonl> <stub> …                        # V2a: compares hand oracles with clone readings
python3 scripts/predicate_outcome_reach.py sample <out.jsonl>                                 # the stratified hand sample, with source spans
python3 scripts/predicate_outcome_reach.py report <out.jsonl> [--judgements <json>] [--v1 pass|fail] [--v2a pass|fail] [--v2b k/10] [--json] [--record-decision <decisions.log>]
python3 scripts/predicate_outcome_reach.py record <out.jsonl> <fixture.jsonl>                 # portable paths (mc.portable)
python3 scripts/predicate_outcome_reach.py crosscheck <census.jsonl> <census-A-dir> <census-B-dir> <out.jsonl> [--rerun 10]
```

**How `report` learns the gates.** No row field holds a gate's result. `report` runs V0 itself, and takes
V1's and V2a's results as `--v1` and `--v2a`, copied from the `V1=` and `V2a=` lines that `validate` and
`oracle` print (their exit statuses agree with those lines). `--v2b` carries V2b's k/10. Without both
`--v1` and `--v2a`, `instrument_ok` is false, and `--record-decision` records nothing.

It reuses `mutation_check`'s `census_target_dir`, `mask`, `matching`, `wrap_subject_calls`,
`EXCLUDED_REPOS`, `portable` and `build`; `corpus_funnel.toolchain`; stage 5's `swift_environment` and its
test-line patterns; and `literal_reach_check.build_setting_aside`, which gains a `suffix` parameter
(default `"_Lit"`). It does not reuse `mutation_check.law_of` (its `split("_")`),
`generator_diversity.expressions` (blind to a hoisted `Self.<name>.run`), or `mutation_check.run_suite`
(a machine-wide `pkill` and a stdout probe). Every path it uses goes through `os.path.realpath` first: a
root package's `entry["package"]` is `"."`, and that `./` defeats any path matching.

**A whole-file clone holding three tests, in source order.** For each stub the probe writes
`<stub stem>_Reach.swift` beside it: the whole stub, its first `struct <Suite>` renamed
`<Suite>_Reach`, with `_isTotal` replaced by three copies of itself.

| test | trials | tag |
|---|---|---|
| `<subject>_isTotal` | 100 | `law` |
| `<subject>_isTotalAgain` | 100, the same seed | `again` |
| `<subject>_isTotalAt1000` | 1,000 | `scale` |

Each copy keeps the stub's seed words, generators and call; nothing is re-derived. Inside the copy's
`property:` region the one call to the subject is wrapped as `__reachProbe(<call>, <tag>)`, which logs the
answer and returns it. The wrap count must be exactly 1, and `trials: 100,` must occur exactly once in
`_isTotal`, or the row is NO READING (`wrap n=<n>`, `trials n=<n>`). Each copy's first statement is
`__reachBegin("<Suite>_Reach|<tag>")`. Hoisted `Self.<name>` generators stay valid under the renamed suite.
Only `_isTotal`'s own `sample:` region is parsed, so the hoist's per-region choices (N12) cannot affect the
census.

Why three tests, in that order:

- **Swift Testing runs a suite's tests serially in source order.** So `Again` sees the subject after
  exactly the law's 100 calls. That is the state an emitted reach test, run right after its law, would see,
  and `class_again` is that reading.
- **`Again`, and the first 100 draws of `At1000`, replay the law's draws.** So every row carries its own
  bitwise prefix check, and a stateless, deterministic subject must read the same bits three times.
- **`Again` runs before `At1000`.** A late trap in the 1,000-trial run cannot null the stateful reading.

**A file probe, and `BEGIN` markers.** `SwiftInferReachProbe.swift`, written at the census target's root,
appends one `RBEGIN|<Suite>_Reach|<tag>` line when each cloned test begins and one `RPROBE|<tag>|<0|1>` line
per answer. Each write is POSIX `write` on a descriptor opened `O_WRONLY|O_APPEND|O_CREAT` at the path the
`SWIFTINFER_REACH_LOG` environment variable names. Output relayed through `swift test` is not enough: a
killed, hung run loses what SwiftPM still holds, which is all of it for a quiet run, `started` lines
included (N1, N10). A trap loses nothing, and the file probe keeps every line written before a trap or a
hang. `__reachProbe` takes `Bool` only, so a wrap that caught anything else does not compile and that clone
is set aside. The helper carries no isolation annotation; the census target has no `defaultIsolation`.

**Build and set-aside.** Clones and the helper are written inside `try/finally`. The package is built with
`literal_reach_check.build_setting_aside(package, swift, suffix="_Reach")`.

- A clone the compiler names becomes NO READING `clone-not-compiled: <first error>`.
- A failure that names no clone makes every row of the package NO READING `package-build-failed`.
- `finally` removes the clones, the helper and the logs. There is no rebuild afterwards.
- **Foreign clones** (any `*_N1000.swift`, `*_Probe.swift` or `*_Lit.swift`, `SwiftInferMutationProbe.swift`,
  or a `// generator_diversity.py probe` marker in the package) make every row of the package NO READING
  `foreign-clones`. The probe's own leftovers (`*_Reach.swift`, `SwiftInferReachProbe.swift`, the logs) are
  removed before anything is written.

**One process per clone suite per hashing mode:** `swift test --skip-build --no-parallel --filter
'\.<Suite>_Reach/'`, with the log path in `SWIFTINFER_REACH_LOG`. **Each log is removed before its process
starts**, because `O_APPEND` would otherwise extend an old run's log.

| row | runs |
|---|---|
| default | det (`SWIFT_DETERMINISTIC_HASHING=1`, all three tests, 1,200 calls) with **180 s**, then rand1 and rand2 (the variable unset; `law` and `Again` only, 200 calls, `At1000` skipped with `--skip`) with **60 s** each |
| `law_a == hung` | det only, with **60 s** |
| det class at 100 is TRAPPED, HUNG or NO READING | rand1 and rand2 are skipped |
| `validate` | 20 s for every run, and 8 rand runs |

**The kill, on a timeout.** Every process whose `ps -axo pid=,command=` line contains
`realpath(package)/.build`, found by a Python substring test and never a `pgrep` regex, gets `kill -9`;
then the process group is killed, and the output is collected with `communicate(timeout=30)`. If that
expires too, the pipes are closed and the run is marked `kill_incomplete`. After each package, a process
still holding that package's `.build` aborts the whole run, printing the processes, and so does a
`kill_incomplete`. The substring kill left no orphan on N10's hang toy.

**Classifying one process.** The file log is the primary source: per tag, whether its `RBEGIN` line is
present, and its `RPROBE` bits in order. Stdout's started, passed and failed lines for the three clone test
names supply `passed[t]` and `failed[t]`. A filter that matches nothing exits 0 (N11), so an absent test is
read from the output, never from the exit status.

| Status | Condition |
|---|---|
| `unexpected-failure` | any `failed[t]`. A totality property cannot fail. NO READING. |
| `hung` in test `t` | timed out, and `t` is the last tag that began. `hung_at = len(bits[t]) + 1`. A timeout with no tag begun is NO READING `no-test-began`. |
| `ran` | every expected test passed. Expected tests are all three under det, `law` and `again` under rand. The counts must be exactly 100 / 100 / 1,000, or the status is NO READING `miscounted`. |
| `trapped` in test `t` | the run did not time out, `returncode != 0`, `t` began and did not pass. `trapped_at = len(bits[t]) + 1`. |
| `missing` | anything else: exit 0 with an expected test absent, or no `RBEGIN` at all. NO READING. A filter that matches nothing exits 0 (N11). |

**Run order and isolation.** No two runs overlap, and no other `swift test` runs on the machine while one
does: `ps -axo command= | grep -c '[s]wiftpm-testing-helper'` must print 0 at each start (the bracket keeps
the check from counting itself). That includes V1's toy: the V1 reading that gates (§4) is taken with
nothing else running, after arm A, and toy runs made while the probe is being built are development runs,
never quoted. Until this work, the funnel ran `pkill -f swiftpm-testing-helper` machine-wide after each
repository (`scripts/corpus_funnel.py`), so a test run beside it could be killed and misread; a commit
before arm A scopes that kill to processes running inside the census's own trees.

- Arm A's funnel run starts after this commit.
- **No census figure is read until V0, V1 and V2a pass.** The census starts after V2a passes, except on
  V2a's substitute path (§4). On that path the census runs first, the five substitute rows are drawn by
  stub name from its output before any class is read, and nothing else in it is read until their oracles
  agree.
- From V2's det process times, `report` prints
  `projected census time = Σ per-row seconds × (expected rows / control rows) + builds`. **If the
  projection exceeds 4 h, the run stops and the projection is reported** before the census starts.
- Then: the arm-A invariants (§4), `run` over arm A's trees, `sample`, the hand judgements,
  `report --record-decision fixtures/predicate-outcome-reach/decisions.log`, and `record`.
- **`judgements.json` is complete, and its sha256 written to the run log, before `report` is first run on
  the census JSONL in any mode.** Until then the judge reads `sample`'s output only. After a fix round, a
  row the redrawn sample adds is judged before `report` runs again, and no judgement already written
  changes.
- **A NOT-DECISIVE(no-reading) fix round re-probes only the rows that read NO READING for an
  instrument-side cause.** Every other row keeps its first reading.
- Arm A's trees are deleted only after the cross-check (§9), or after the measurement doc lands under NONE.

**Detector power.** A row whose class flips per process with probability ½ is missed by det + 2 rand runs
with probability ¼. Under E or W, arm B's run is one more random-hashing process, so the cross-check (§9)
sees a row the census missed disagree with probability ½, and `--rerun 10` then names it
`unstable-missed`. Such a row is missed by both with probability ⅛. Under NONE there is no arm B, and the
measurement doc states the ¼ beside the stability figures.

## 4. Validation, before any census number is read

Frozen here. A gate that fails makes §7's DECISION NOT-DECISIVE(instrument); a reading is reported and
gates nothing.

### V0, the self-test (a gate)

**V0. `--self-test`** (pure Python, about 0.1 s, in `make measurement-selftest`). It covers:
- **`wrap_subject_calls` on 12 canned property closures**, asserting n = 1 and the wrapped text. The shapes:
  - static;
  - tuple;
  - drawn receiver;
  - constructed receiver;
  - constructed receiver whose label is the subject's namesake;
  - inout;
  - MainActor;
  - MainActor + inout, in the re-laid multi-line form;
  - actor;
  - actor + inout;
  - an `_`-prefixed subject;
  - a hoisted draw.
- **A subject named `run` beside `MainActor.run`**, expecting n = 2 and the guard to fire.
- **`parse_stub` on two canned stubs**, one with a hoisted `Self.generator`, checking the resolution.
- **Bit packing**, as a round trip.
- **Parsing:**
  - clone text holding three functions with BEGIN lines in the right order;
  - the log parse.
- **Status rules, one canned log each:**
  - `missing`: exit 0 with nothing begun;
  - `no-test-began`: a timeout with an empty log;
  - a hang in each of `law`, `again` and `scale`;
  - a trap in `scale` at call 150, giving class100 BOTH and class1000 TRAPPED@150;
  - an `again` trap, giving `stateful` true and class1000 `blocked-by-again`;
  - `unexpected-failure`;
  - `miscounted`.
- **Flags:** both bit flags; the `hash_sensitive_class` and `stateful` truth tables.
- **Sampling:** stratified allocation (largest remainder and ties) and the weighted `cbd_share`.
- **The DECISION function**, at the boundaries 0.4999, 0.50, 0.7999 and 0.80, plus:
  - the lower band of G and G_loo;
  - ties for `largest`;
  - \|R\| = 99 giving NONE(population);
  - NO READING at 10.1%;
  - each NOT-DECISIVE cause;
  - the hand drop: E → W only, and W never dropped.
- **Kill helper:** `kill_build_processes` matching a `./`-containing package path after `realpath`.

### V1, the toy control (a gate)

**V1. `validate`, the toy: `fixtures/predicate-outcome-reach/toy/`.**

*Steps:*
1. Copy the toy to `<scratch>/toy` and run `discover --include-possible --interactive` with the arm-A binary.
2. Run `s5.rewrite_manifest` and `verify_manifest`.
3. Copy the committed `toy/Package.resolved` in, then run `build_to_fixpoint`.
4. **Assert** that the resolved SwiftPropertyLaws and swift-property-based versions equal `expected.json`'s. If they do not, V1 fails, and re-capturing them is a deliberate commit.
5. Write the hand stubs: clones of the emitted `Rules.isEven` stub with the same seed words.
6. Copy the committed oracle file `toy/Oracles.swift` into the census target.
7. Run `run --package` with `--rand-runs 8` and 20 s timeouts.

*The oracles.* One `@Test` per toy subject, written by hand. Each:
- copies its stub's four seed words and generator expressions verbatim from the stub emitted at `fef2971d`;
- draws with `var oracleRNG = Xoshiro(seed: (…))` for 1,000 iterations;
- calls the subject directly;
- writes `OPROBE|<subject>|<0|1>` lines with the probe helper.

The oracle needs no wrap, no clone and no parse of the stub.

*The gate* (all of these must hold):
- (a) For every toy subject whose det `law` test ran, `bits[law]` equals the oracle's first 100 answers, and `bits[scale]` equals all 1,000.
- (b) Every class and flag in `expected.json` is matched.
- (c) No orphan is left, and no `kill_incomplete`.

The counts the design's prototype toy run read are recorded in `expected.json` as **readings**, together with the resolved versions. A count that differs from them while (a) holds is a provenance note, not a failure.

*Toy subjects:*

| Subject | Expected | Exercises |
|---|---|---|
| `Rules.isEven` | BOTH / BOTH | static unary |
| `Point.isRightOf` | BOTH / BOTH | drawn receiver, hoisted generator, tuple |
| `Rules.isWithin` | BOTH / BOTH | two arguments |
| `Layout.isWide` | BOTH / BOTH | `MainActor` |
| `Layout.trimsLeading` | BOTH / BOTH | `MainActor` + `inout` |
| `Matcher.matchesPrefix` | BOTH / BOTH | constructed receiver, subject literals |
| `Rules.consumesPrefix` | BOTH / BOTH | `inout` |
| `isBlankLine` | BOTH / BOTH | free function |
| `Rules.hasControlCharacters` | BOTH / BOTH | hostile string |
| `Rules.isMagic` | ONLY-FALSE / ONLY-FALSE | — |
| `Rules.isRepresentable` | ONLY-TRUE / ONLY-TRUE | constant by design |
| **`Rules.isRareResidue`** | **ONLY-FALSE at 100, BOTH at 1,000, `first_true_at` in (100, 1000]** | the rare region. `x % 1000 == r` over its drawn `Int`, with `r` tuned **once** from the oracle's draws at its seed, recorded in `expected.json`, and frozen. |
| `Rules.indexesSmallTable` | TRAPPED in `law` at 1 | trap |
| `Faults.spinsForever` | HUNG in `law` at 1; rand skipped; no orphan | hang |
| `Faults.trapsLate` | class100 BOTH; class1000 TRAPPED in `scale` at 150 | traps on the value the oracle shows at draw 150 (tuned, frozen) |
| `Faults.spinsLate` | class100 BOTH; class1000 HUNG in `scale` at 150 | **the file probe across a hang** |
| `Sightings.isFirstSighting` | `stateful = true`; class_again ≠ class100 | a static seen-set |
| `HashOrder.firstOfFourIsEven` | `hash_sensitive_bits = true` | a `Set<Int>` of four, then `first` |
| **`HashOrder.firstOfTwoIsA`** | `hash_sensitive_class = true` with 8 rand runs: missed with probability 2⁻⁸ | `Set(["a", "b"]).first == "a"`, constant within a process, flipping between processes |
| `Registry.holds` (actor), if offered | BOTH / BOTH | actor `await` |

### V2, the road test's own subject (V2a gates, V2b is a reading)

SwiftUMLStudio at `e36da59`, the road test's revision, via a pinned worktree (N6). The control's funnel
run is the patched-harness half of the harness A/A below.

```
git -C ../SwiftUMLStudio worktree add --detach <scratch>/control-new/trees/SwiftUMLStudio e36da59
python3 scripts/corpus_funnel.py <scratch>/control-new <bin>/swift-infer-A-fef2971d <bin>/CLI-eec21fbb SwiftUMLStudio
python3 scripts/predicate_outcome_reach.py run <scratch>/control-new <scratch>/control.jsonl --arm control-e36da59
```

**V2a, the instrument gate.**
- For **every** emitted, compiled control row among the issue's 10 (at least 5 are needed), hand-write an F2-style oracle beside the stub in the control tree. It uses the same seed words and generator text, 100 trials, `Set<Bool>`, and logs its answers through `OPROBE`.
- `oracle` asserts that the oracle's 100 answers equal the clone's det `bits[law]` exactly.
- **Any disagreement is an instrument defect:** stop and fix.
- **If fewer than 5 of the 10 are emitted:** draw 5 census rows from 5 distinct repositories (sorted by stub, `random.Random(20261027)`, before any class is read) and oracle them the same way. They replace the control as the gate.
- V2a tests the clone pipeline (wrap, probe, log parse, classify) on real generators, including syntax corpora and constructed receivers, which V1's toy cannot cover.

**V2b, the reproduction reading. It is reported and never gates.**
- k = the number of the issue's 10 that read at 100 under det as the issue measured them:
  - BOTH: `hasModelAttribute`, `conformsToGRDBRecord`, `pathContainsGlobSyntax`;
  - ONLY-FALSE: the other seven.
- Each miss is attributed:
  - `not-emitted`;
  - `generator-drift`: the stub's generator text differs from what `f4bfdad1` emits;
  - `kit-drift`: the resolved kit differs and the generator text is the same;
  - `unexplained`.
- **If there are two or more misses**, rebuild `f4bfdad1` (`git archive` into scratch, release build) and emit the control with it, to separate `generator-drift` from `kit-drift`.
- **Why V2b does not gate.** The census measures arm A's current state, not the road test's. Gating on reproducing a measurement taken at a different binary and an unrecorded kit (N7) would make the decision hostage to upstream drift that V2a has already ruled out as an instrument cause.
- The doc quotes k/10 with every miss's attribution. **An `unexplained` miss is a finding to write up**: the same generator text and seed reading differently from the issue's hand test.
- Remove the worktree afterwards with `git -C ../SwiftUMLStudio worktree remove`.

### V3, the mutation run's baselines (a reading)

- `fixtures/mutation-check/run-2026-09-22.jsonl` stores each predicate baseline probe as a 16-hex digest.
- 100 × `- false⏎` digests to `1466cff07c09e9d2`, and 7 of the 14 predicate baselines carry it.
- Those subjects' census readings are compared with that split.

### Arm A is unchanged by the harness bucket

**The harness bucket** lands in the commit before this scope, so arm A runs on it. A test whose name ends
`_reachesBothOutcomes()` is a reach claim, not a law: it feeds only `reach` (`expected`, `green`,
`not_applied` by side, `other`, `crashed`, `hung`, `skipped_after_law`, `unaccounted`), never a law
column, so `compiled` still reconciles per stub file. `max_resumes` stays 30: when a law crashes or hangs,
its reach twin is skipped pre-emptively, so a stub costs at most one resume in either arm. Each
`swift test` invocation's wall time is recorded (`run_seconds`), with bisection's probes and seconds.

Arm A emits no reach name, so its columns must equal the unpatched harness's. Shown three ways, all before
the census:

- **The harness self-tests**, both in `make measurement-selftest`: stage 5's parse over captured
  Swift Testing output against the unpatched loop's expectations, and `record_outcomes` against the
  pre-patch assignments with reach names filtered out.
- **A harness A/A on V2's control**: the control run twice into two scratch directories pre-seeded at
  `e36da59`, with the same binaries, once with the harness at `fef2971d` (`git archive fef2971d scripts`)
  and once patched. Every legacy key of `result-SwiftUMLStudio.json` must be equal, except `started` and
  `finished`. A difference is read by hand (flake or hang), never averaged.
- **The arm-A invariants**, asserted by `report` and quoted in the measurement doc: no reach name in any
  list; every `exhausted` false; every `resumes` ≤ 30; every `reach_*` 0; `run_seconds` present for every
  built package; `record_passes(passed_tests)` reproduces the stored `passed` and its behaviour /
  does-not-crash split for every package; `unaccounted − unaccounted_tests` explained by stubs that declare
  no test.

## 5. Classes

### Row fields, read from each stub

| Field | How it is read |
|---|---|
| `suite` | `^struct (\w+)` |
| `test` | The first `@Test func (\w+)_isTotal\(`. If there is none: NO READING `no _isTotal`. |
| `subject` | `test[:-len("_isTotal")]` |
| `label` | `"([^"\n]+?) failed totality at input` |
| `source`, `line` | `^// Source: (.+):(\d+)\s*$` |
| `seed` | The four `state[ABCD]: 0x([0-9A-F]{16})` words inside `_isTotal`, in A–D order |
| `generators` | Each `.run(using: &rng)` between `sample:` and `property:`. Either the text inside `(`…`)` (paren matching on the masked text), or a `Self.<name>` resolved to its `nonisolated private static let <name> = ` declaration, which runs to the first blank line after it (`GeneratedFileGeneratorHoist.swift:57-60`). |
| `arity` | `len(generators)` |
| `receiver` | From the wrapped call (§3). `drawn` if the call text starts `value.<subject>(` or `args.0.<subject>(`. `constructed` if a `(`…`)` qualifier precedes `.<subject>(`. Otherwise `none`. |
| `isolation` | The property closure contains `await MainActor.run {` → `MainActor`. `await <X>.run {` → `<X>`. `await` with no `.run {` → `actor`. Otherwise `none`. |
| `inout` | `var inout\d` is present |
| `throwing` / `async` | `try?` is present; or `await` is present with no hop and the isolation is not `actor`. Both are expected to be 0 (N5), and any non-zero row is reported. |
| `kinds` | Per generator, the first matching rule: `TODO: no generator derived` → `unresolved` (never compiles, so never in the population); `SwiftInferSyntaxCorpus.gen(` → `syntax-corpus`; `Gen.always(` → `held-constant`; the hostile list (`"[[a\|b]]"`) → `hostile-string`, flagged `literals` when a second `Gen<String?>.element(of: [` is present; `.array(of:` → `array`; `^Gen<(U?Int\d*\|Double\|Float\|Bool\|Character)>`, or `Gen.int(` with no `zip(` and no `.map {` → `stdlib-scalar`; `zip(`, `.map {` or `.gen()` → `derived`; anything else → `other`. |
| `primary_kind` | The kind of the first generator that is not a drawn receiver |
| `row_kind` | `relational` if `arity ≥ 2` (a drawn receiver counts), else `unary` |

### Classes and flags

`classify(bits)` gives BOTH, ONLY-FALSE or ONLY-TRUE.

| Reading | Rule |
|---|---|
| `class100` | From the det `law` test: `classify(bits[law])`, or TRAPPED/HUNG with its position, or NO READING |
| `class_again` | From the det `again` test: `classify(bits[again])`, or TRAPPED/HUNG. `null` when the law did not complete. **This is the reading arm B's reach test reproduces.** |
| `class1000` | `classify(bits[scale][:1000])` when det `scale` ran. TRAPPED/HUNG at the `scale` position when it trapped or hung there. Equal to `class100` when the law trapped or hung. NO READING `blocked-by-again` when `again` trapped or hung. |
| `class100_randK`, `class_again_randK` | The same, from each random-hashing run that happened |

**Flags.**

| Flag | Meaning |
|---|---|
| `stateful` | det `class_again ≠ class100`, counting an `again` TRAPPED or HUNG as different; or the same holds in any rand run. A trap or hang on identical draws after a passing law is state, or nondeterminism. |
| `hash_sensitive_class` | `class100` differs among det and the rand runs that happened |
| `again_bits_differ` | det `bits[again] ≠ bits[law]` while both were read. Reported. |
| `scale_prefix_differs` | `bits[scale][:100] ≠ bits[law]`. Reported. On a stateless, deterministic subject both bit flags are false, so every row carries its own bitwise prefix check. |
| `hash_sensitive_bits` | the law bits differ among modes. Reported. |
| `unstable` | `stateful or hash_sensitive_class` |

A random-hashing run that reads NO READING does not count as having happened for `hash_sensitive_class` or
`stateful`. Such rows are listed in the stability section.

**G at 1,000** is \|{r ∈ R : class1000 == BOTH and not unstable}\| / \|R\|. A row of R whose `class1000`
is TRAPPED, HUNG or NO READING counts as not green. A row is **readable** when its det `class100` is BOTH,
ONLY-FALSE or ONLY-TRUE; TRAPPED and HUNG rows are counted apart, as P2 does.

### The hand check, stratified

- **Population:** non-teaching census rows in R whose `class100` is ONLY-FALSE or ONLY-TRUE (the reds).
- **Allocation:** n = min(30, |reds|), split across repositories by largest remainder of `n × reds_repo / reds_total`. Remainder ties go to the repository earlier in name order.
- **Draw:** within each repository, sort the reds by `stub` and take `random.Random(20261027).sample` of the allocated size. One `Random` instance, with repositories visited in name order.
- **Output:** each sampled row with its source span and generators.
- **Verdicts** go in `fixtures/predicate-outcome-reach/judgements.json` as `{stub: {class, note}}`. The classes:
  - `generator-miss`: a witness input of the drawn type exists. Name it.
  - `relational`: the other answer needs two drawn values to line up. This is a generator miss whose fix is a pairing (#665 Direction 2), recorded apart.
  - `constant-by-design`: no value the generator's type can build gives the other answer.
  - `undecidable-by-reading`.
- **Blind to G:** `judgements.json` is complete, and its sha256 written to the run log, before `report` is
  first run on the census JSONL in any mode. Until then the judge reads `sample`'s output only.
- **`cbd_share`** is the constant-by-design share **weighted** by each repository's share of reds:

  Σ_repo w_repo × (cbd_repo / n_repo), where w_repo = reds_repo / Σ reds over the repositories with n_repo > 0.

  The weights are renormalised over the repositories that were sampled. The unweighted k/n is printed beside it. With no reds, n = 0 and `cbd_share` is 0.
- **The rare region is mechanical:** a row red at 100 and BOTH at 1,000.

### What `report` prints

- Bucket tables at 100 and at 1,000 (BOTH, ONLY-FALSE, ONLY-TRUE, TRAPPED, HUNG, and NO READING split by
  reason) for non-teaching R, non-teaching all readable (G_all), teaching, all, and non-teaching
  leave-largest-out.
- Per repository with its share of R; per `primary_kind`, `row_kind`, `receiver` and `isolation`.
- The 100 → 1,000 matrix, and `first_true_at` / `first_false_at` for rows red at 100.
- `unstable`, `stateful` and `hash_sensitive_class` rows, listed; counts of the bit flags; `minority100`
  for BOTH rows.
- Consistency: readable rows with `law_a ≠ passed`; TRAPPED against `law_a == crashed`; `throwing` and
  `async` rows, expected 0 (N5); total process time and its projection.
- The DECISION line (§7).

## 6. Predictions

Written before arm A's funnel run and before any census or control stub was probed. Not amendable. The
measurement doc scores each one ✅ or ❌; P3a and P3b are scored separately, so there are 14. Under any NONE
there is no arm B, so P13 is marked not scored and the count is out of 13.

| # | Prediction |
|---|---|
| P1 | 330–500 compiled `predicate` stubs; teaching ≤ 10% |
| P2 | readable ≥ 94% of compiled; TRAPPED + HUNG ≤ 3%; NO READING ≤ 3%; clones set aside 0; `wrap n≠1` ≤ 2; `missing` 0; throwing and async rows 0 |
| P3a | **G (R, 100 trials, det) = 0.40, interval [0.25, 0.55]** |
| P3b | **DECISION = NONE.** The interval straddles the W floor, so W, which needs G and G_loo both ≥ 0.50, is the stated alternative. P3a and P3b are scored separately. |
| P4 | largest = SwiftProjectLint; its own G ≤ 0.35; G_loo ≥ G |
| P5 | teaching G ≥ 0.70 |
| P6 | syntax-corpus G ≤ 0.30; hostile-string unary 0.40–0.75; stdlib-scalar ≥ 0.65; relational G ≤ unary G |
| P7 | ONLY-FALSE ≥ 80% of reds; ONLY-TRUE ≤ 6% of R |
| P8 | of the reds at 100, 5–20% are BOTH at 1,000; G at 1,000 − G at 100 ≤ 10 points |
| P9 | unstable ≤ 3 rows; `again_bits_differ` + `scale_prefix_differs` ≤ 3 rows |
| P10 | of the BOTH rows, ≤ 25% reach their minority answer ≤ 2 times |
| P11 | hand sample: generator-miss + relational ≥ 60% (weighted); constant-by-design ≤ 20% |
| P12 | V2a passes on every emitted control row; V2b = 10 of 10 |
| P13 | (E or W only) in arm B: law columns move 0 rows; compiled `predicate` equal; content diff clean after normalisation; reach verdict = census `class_again` on 100% of stable rows; `reach_other` = 0; `reach_unaccounted` = 0 |

## 7. What the result decides

Frozen in this commit, before any census or control stub is probed. Nothing in this section is amendable.

### The two presentations

| | Swift Testing prints | `swift test` exit | Funnel (patched) | Exit-status mutation tools | On correct code missing an answer |
|---|---|---|---|---|---|
| **E**: its own `@Test`, `Issue.record("…")` | `✘ … recorded an issue` / `↳ NOT APPLIED — …` / `✘ … failed` | 1 | `reach.not_applied` | KILL, when a mutant newly makes the answer constant | a red test, CI red |
| **W**: its own `@Test`, `Self.reachNote("…")`, a helper holding `#if compiler(>=6.3)` `severity: .warning` / `#else withKnownIssue` | `⚠︎ … recorded a warning` / `↳ NOT APPLIED — …` / `✔ … passed … with 1 warning` (N9) | 0 | `reach.not_applied` | SURVIVED | a visible note, never red |
| `withKnownIssue` unconditional | — | 1 when the reach *succeeds* | — | — | **rejected** |
| a record inside `_isTotal` | — | — | — | — | **rejected**: the reach check is its own `@Test`, after `_isTotal` |

The emitter cannot choose per stub, so the presentation is per template, and the census sets it.

### Population terms

| Term | Definition |
|---|---|
| **R** | census-arm rows that are non-teaching, with `law_a == passed`, and `class100` (det) in {BOTH, ONLY-FALSE, ONLY-TRUE} |
| **green** | `class100 == BOTH and not unstable` |
| **G** | \|green\| / \|R\| |
| **G_all** | the same over every readable non-teaching row, whatever `law_a` is. Reported only. |
| **largest** | the repository with the most rows in R. Ties go to the earlier name. |
| **G_loo** | G over R without `largest` |
| **compiled_nt** | every non-teaching census row in the population, `package-no-verdict` rows included |
| **no_reading** | the rows of `compiled_nt` that are NO READING |

### The frozen rule

```
band(x) = "E" if x >= 0.80 else "W" if x >= 0.50 else "NONE"          # NONE < W < E
instrument_ok = V0 passed and V1 passed and V2a passed

if not instrument_ok:
    DECISION = NOT-DECISIVE(instrument)     # fix the instrument, re-run, record every line;
                                            # after a 2nd failed fix round: terminal NONE(instrument)
elif |R| < 100:
    DECISION = NONE(population)             # terminal
elif no_reading > 0.10 * |compiled_nt|:
    DECISION = NOT-DECISIVE(no-reading)     # one fix round on instrument-side causes (wrap, missing,
                                            # miscounted, clone-not-compiled); then terminal NONE(no-reading)
else:
    b = min(band(G), band(G_loo))
    if b == "E" and cbd_share > 0.5:  b = "W"      # a red that is not the user's to fix must not fail CI
    DECISION = b
```

What the commits named in the table are: **4a** shares the totality call between `_isTotal` and the reach
test (`TotalityCall`, `stubTrialCount`), and its output is byte-identical; **4b** emits the reach `@Test`
after `_isTotal`, predicate only, in the decided band's form; **5** is the funnel re-take (§9).

| DECISION | What happens |
|---|---|
| **E** | Commit 4b emits an error-severity record in the reach `@Test`, with the E header line. Commits 4a, 4b and 5 follow. |
| **W** | Commit 4b emits the reach `@Test` with `Self.reachNote(…)` records, the per-stub `reachNote` helper and the W header line. Commits 4a, 4b and 5 follow. |
| **NONE**, NONE(population), NONE(no-reading), NONE(instrument) | Nothing is emitted. Commits 4a, 4b and 5 are dropped. The PR ships the scope, probe, harness bucket and census doc. The doc names the cause, and a follow-up issue is filed (Q6.2 §10). |
| **NOT-DECISIVE(…)** | Not terminal. Only the bounded fix rounds above are allowed, and every line is recorded. |

So **under any NONE the PR ships no emitter change**: this scope, the probe, the harness bucket and the
measurement doc, and a follow-up issue that names the cause (§10).

**Why each number:**
- **0.80 (C6).** An error-severity check that fails CI on correct code sits under an ENTAILED header. It must be no noisier than the noisiest error-severity class already shipped: `idempotence`, which is red on correct code about 21.5% of the time and labelled CONJECTURE.
- **0.50 (C7).** The issue's own test is "if most checks are red". Below 50% green, most predicate files would carry the note, and readers learn to delete a note that most files carry. That holds whether it is a failure or a warning, and the remedy text itself says "or delete this test". It is also the floor that matches "Avoid the Daikon trap" and "conservative inference". It is chosen independently of P3, which lands below it.
- **The lower of G and G_loo:** one author's style must not set the presentation for everyone.
- **\|R\| ≥ 100:** at p = 0.8, the 95% interval is about [0.71, 0.87].
- **NO READING ≤ 10%:** nothing is decided on a biased subset.
- **The hand drop, E → W only.** Under W, a constant-by-design red is a true statement, and the W comment says so ("keeps warning, and is right to"). Under E it fails the user's CI for something the user cannot fix.
- **Teaching repositories** are reported apart and never enter the rule.

**What the rule does not decide:**
- **The 1,000-trial reading decides nothing.** If G at 1,000 minus G at 100 is 20 points or more, the doc files a follow-up that raises the stub budget. `stubTrialCount` is every template's stub budget (critique 2.16), so the follow-up either raises it for all templates or adds a predicate-only parameter, and must say which.
- **Payoff is priced, not measured.** Under W the doc states "0 kills by construction under exit-status tools", citing N9.
- **Predicted:** G = 0.40, interval [0.25, 0.55], so the **predicted DECISION is NONE**. The interval admits W, which needs G ≥ 0.50 *and* G_loo ≥ 0.50 (P3a and P3b are scored separately).

Keys used in the frozen text above: **C6** is the E threshold (G ≥ 0.80 and G_loo ≥ 0.80) and **C7** the
W floor (G ≥ 0.50 and G_loo ≥ 0.50); **N9** is the appendix's measurement of the W form; **critique 2.16**
is the design review's point that `stubTrialCount` is every template's stub budget; **Q6.2 §10** is this
document's §10.

**Every DECISION line used to decide anything is recorded**, re-runs after NOT-DECISIVE included: `report
--record-decision fixtures/predicate-outcome-reach/decisions.log` appends it with a UTC timestamp and the
script's git SHA, and the measurement doc quotes the file in full.

```
DECISION: E|W|NONE|NOT-DECISIVE(<cause>)  G=…% (B/R)  G_loo=…% without <repo>  G_all=…%  |R|=…  unstable=…  no_reading=…% of compiled  hand: constant-by-design …% weighted (k/n)  V1=pass|fail  V2a=pass|fail  V2b=k/10  input=<sha256 of out.jsonl, 12 hex>
```

## 8. Direction-2 reopen triggers

The issue's Direction 2 is reach at the source: syntax-node draws seeded with the tokens a predicate body
compares against, and relational draws that line two values up. None is proposed here; this census is what
would score one. Each trigger is mechanical and named by field:

- **Syntax-corpus seeding reopens** if ≥ 30 rows in R with `primary_kind == "syntax-corpus"` and `class100 ∈ {ONLY-FALSE, ONLY-TRUE}` sit in ≥ 2 repositories.
- **Relational draws reopen** if ≥ 20 rows in R with `row_kind == "relational"` and `class100 ∈ {ONLY-FALSE, ONLY-TRUE}` sit in ≥ 2 repositories.
  - The hand class `relational` is reported beside this count as a precision reading: of the relational rows that are sampled and red, the share judged `relational`.
  - The hand class is not the trigger.
- **Neither trigger replaces or satisfies** the standing trigger in `docs/plans/subject-literal-generation-scope.md` §4c ("Reopens if a census finds guard-literal `guard-domain` stubs in more than one repository"). That trigger is about guard-domain literal draws, and this census measures nothing about it.

## 9. The funnel re-take (only under E or W)

Under any NONE nothing here runs: there is no arm B, and the harness bucket ships with every `reach_*`
column 0.

**Arm B:**

1. The branch binary is built and stamped, and copied out with its `Package.resolved`. Any difference from
   arm A's in kit, engine, swift-syntax or swift-collections is resolved before running, by rebuilding B
   with A's resolved file copied in.
2. Provenance is recorded again, and the 19 HEADs and porcelain must match §2's. A repository that moved
   gets a detached worktree at A's SHA.
3. The funnel runs into a fresh census directory, under `env -u SWIFT_DETERMINISTIC_HASHING`.
4. Each package's `Package.resolved` is diffed against A's. A package whose kit or engine differs has void
   B figures, and A is re-run for it.

**`crosscheck` runs these, in order:**

1. **Stub content diff**, over every stub file in each package's census target and its `aside-<repo>/`
   directory, in both arms. The path sets must be equal. Non-predicate files must be byte-equal. Predicate
   files must be equal after normalising: drop the two `// Reach:` header lines; drop the
   `_reachesBothOutcomes` test and any `reachNote` helper (matched braces on masked text); de-hoist each
   `Self.<name>` to its `static let` text and delete the declarations (N12); collapse runs of whitespace.
   **Any other difference blocks the PR.**
2. **Columns**, per repository: compiled, all and `predicate`, must be equal; law passed (behaviour and
   does-not-crash); failed, crashed, hung; unaccounted (files and tests); the reach buckets.
3. **Per-stub reach verdicts against the census.** Every arm-B verdict is compared with the census's det
   `class_again`, because arm B's reach test runs right after its law, as `Again` does.

| Arm-B verdict | Census reading it must equal |
|---|---|
| reach green | BOTH |
| NOT APPLIED, true side | ONLY-FALSE |
| NOT APPLIED, false side | ONLY-TRUE |
| reach crashed or hung, beside a passing law | `stateful` true, or `class_again` TRAPPED/HUNG. Otherwise a disagreement. |
| reach skipped after its law crashed or hung | Reported with `law_a` and the census `class100`. It is a law-level reading, not a reach one. |
| `reach_other` (an issue with no NOT APPLIED side) | An emitter defect |

   - **Unstable rows** are excused and listed.
   - **A disagreement on a stable row** is re-run with `crosscheck --rerun 10`: that row's clone, rebuilt in
     arm A's tree, runs 10 times under random hashing (`law` and `Again`). If any run's `Again` class equals
     arm B's verdict, the row is `unstable-missed`: listed, counted as a detector miss, and not blocking.
     Otherwise it is an **emitter re-draw defect, and it blocks the PR**.
4. **Timing.** Each package's `run_seconds` and bisection are compared between the arms. A package is
   flagged when its arm-A wall time exceeds 240 s (40% of 600), or when bisection ran in either arm. A
   difference in compiled or law columns in a flagged package is re-run in both arms with a 1,800 s budget
   before it is attributed. An unflagged difference, and a B set-aside whose first error lies in a reach
   test, are defects to fix before reporting, never a measured cost.

**The expected moves are zero.** P13 states them: law columns move 0 rows, compiled `predicate` is equal,
the content diff is clean, and the reach columns are new.

| | arm A `fef2971d` | arm B `<sha>` | moved |
|---|---:|---:|---:|
| seeds · stubs | | | expected 0 |
| compiled, all · `predicate` | | | **must be 0 · 0** |
| content diff: non-predicate byte-equal · predicate normalised-equal | — | x/x · y/y | **must be all** |
| law passed | | | expected 0 |
| — behaviour | | | expected 0 |
| — does not crash | | | expected 0 |
| law failed · crashed · hung | | | expected 0 |
| unaccounted (files) · (tests) | | | 0 · 0 |
| packages flagged by time | | | listed |
| reach expected | — | = compiled `predicate` stubs that are not skipped | new |
| reach green · NOT APPLIED true side · false side | — | | new |
| reach crashed · hung · skipped after law · other · unaccounted | — | | other = 0, unaccounted = 0 |
| cross-check: B verdict = census `class_again`, stable rows | — | x of x | disagreements listed, with each one's re-run result |

A per-repository version follows it in the measurement doc. The sentence that reports it is filled from
the table, and nothing is pre-written:

> Law rows moved: <n> (compiled <C_A> → <C_B>; passed <P_A> → <P_B> = <B_B> behaviour + <D_B> does not crash)<; attribution of each moved row, if n > 0>. The reach check adds <R> tests in its own bucket: <g> green, <t> NOT APPLIED on the true side, <f> on the false side, <c> crashed, <h> hung, <s> skipped after their law trapped or hung. These are reach claims, not laws.

- Never write "laws gained", and never quote a single `passed` total.
- The measurement doc also states what an **unpatched** harness would read on a B tree:
  `passed_does_not_crash` + g under E, or + g + t + f under W.

## 10. Not in scope, and the deferrals

Each deferral is **deferred on a witness**: a stated, checkable observation that reopens it. No falsifier
annotations are written, for two reasons:

- `DeferralFalsifierTests.noFalsifierHasLanded` fails as soon as a named symbol is declared, so an existing
  symbol such as `composePredicatePass` would fire at once.
- A new local name is the "Fragile" shape in `docs/measurements/falsifier-naming-failure-modes.md` §4.

The deferrals and their witnesses:

| Deferral | Witness that reopens it |
|---|---|
| The verify-side twin (`composePredicatePass`, whose draws are the strategist's 1,000) | A road test or census records a `predicate` row that `verify` reports as passing while its strategist draws reached one answer. |
| Direction 2 | §8's triggers |
| The stub-budget raise | This census's own G at 1,000 − G at 100 ≥ 20 points. The follow-up names whether it raises every template's budget or adds a predicate-only one. |
| The guard-domain and equivalence retrofit onto `NotApplied` | A third emitter writes a NOT APPLIED message outside `NotApplied`, for example #668's or #673's. Under E or W only. Under any NONE, `NotApplied` is never written, and this row lapses. |
| A per-generator-kind presentation | It would be fitted in-sample, so it reopens only on a validation population (the corpora in `fixtures/corpora/manifest.json`). |

Also out of scope:
- `input-totality` and `measure-non-negativity`;
- a mutation run, and so any kill count;
- criterion A;
- the split law.

**Under NONE, the follow-up issue** names the cause and the re-take condition:
- `NONE` (by the bands): Direction 2 is scored by the rows it moves to BOTH, measured with this script.
- NONE(population): re-take on the manifest corpora. If `no_reading` also exceeds 10% of `compiled_nt`,
  the follow-up names the NO READING causes too, because the rule tests \|R\| first.
- NONE(no-reading) or NONE(instrument): the failing gate.

What the census cannot say, whatever it reads:

- **A rare `true` region.** A predicate true on a fraction *p* of draws misses in 100 trials with
  probability (1−*p*)^100. The 1,000-trial reading shows how much of the red is budget, and decides nothing.
- **Constant by design.** A predicate constant on every value its argument's type can build stays red, and
  is right to. The hand check estimates how much of the red that is; it does not find every such row.
- **A low ceiling.** A reach check catches only an edit that makes the answer constant over the draws,
  never one that moves which inputs are true.
- **A reach claim is not a law.** No kill is measured here, and no pass count moves.
- **This corpus, never a rate.** G is the share of R, the passing, readable `predicate` stubs of the 14
  non-teaching repositories, at these SHAs.

`composePredicatePass` is in `Sources/SwiftInferCLI/StrategistDispatchEmitter+Templates.swift`. The split
law is entry 8 of `docs/ideas/laws-from-mutation-survivors.md`, and criterion A is stated in
`docs/design-internal/toolchain-exit-criteria.md`. A reach claim is not a law, so this census gives no
criterion-A reading, and the road test's third relevant mutant cannot be counted from it. Totality itself
stays: it is role-entailed and never hidden (`docs/design/predicate-display-order.md`).

## 11. What the run records

- the binaries' SHAs and their `Package.resolved` files;
- the CLI SHA;
- per-repo SHAs and porcelain;
- per-package `Package.resolved`;
- toolchains, `NO_COLOR`, the hashing modes and the funnel's hashing environment;
- `uptime` at the start and end of each run;
- process wall times;
- one row per stub;
- every DECISION line.

Where they land: `fixtures/predicate-outcome-reach/census-<run-date>.jsonl` (census and control rows, each
with an `arm` field, portable paths), `fixtures/predicate-outcome-reach/judgements.json`,
`fixtures/predicate-outcome-reach/decisions.log`, and the `toy/` fixture. Under E or W, the re-take adds
`funnel-ab-<date>.json` and `crosscheck-<date>.jsonl` there. One JSONL row per stub carries its
provenance (`swift_infer`, `cli`, `toolchain`, `kit`, `engine`, `repo_sha`), its parsed fields (§5), every
run's status, seconds and hex-packed bits (bit *i* = call *i*), its classes and flags, and `no_reading`.

## 12. Amendments

Dated, each recorded before any census figure is read. None yet.

## Appendix: design measurements

Taken while designing this, in a session scratchpad, and not kept in the tree. The toy cases that matter
are re-run as V1.

- **N1. A killed, hung `swift test` loses the output SwiftPM is still holding, which can be all of it. A
  trap loses none.** A toy printing about 6 KB and then spinning delivered 0 lines after the kill, not even
  `started`; the same output followed by an index trap delivered all 300 lines. A probe appending to a FILE
  through POSIX `write` kept 150 of 150 lines across both, compiles in Swift 6 mode inside
  `await MainActor.run { }`, and its environment variable reaches the test helper.
- **N2.** A kill scoped to the package's `.build` leaves no orphans.
- **N4.** The kit already uses the `#if compiler(>=6.3)` / `severity: .warning` pattern
  (`SwiftPropertyLaws/Sources/PropertyLawKit/Model/PropertyLawViolation.swift`).
- **N5.** `PredicateTemplate.isPredicate` requires a return type of exactly `Bool`, not `async`, not
  `throws`, and at least one parameter. So throwing and async rows are expected to be 0, and any is
  reported.
- **N6.** SwiftUMLStudio's HEAD is `b8b1520`; `e36da59` is present in the clone;
  `corpus_funnel.worktree()` leaves an existing directory untouched.
- **N7.** The road test records no kit version, and kit `v4.10.0` was tagged on the day of the run.
- **N9. The W form lints clean, compiles warning-free and exits 0 on both toolchains.** Records routed
  through a per-stub `reachNote` helper that holds the only `#if compiler(>=6.3)`: 0 violations under
  SwiftLint 0.65.1 `--strict` with the repo's config, no `function_body_length` on a six-argument,
  two-`inout` MainActor shape, and builds with `-warnings-as-errors` on swift.org 6.4.1 and Xcode
  `swiftlang-6.4.0.34.1`, with and without `.defaultIsolation(MainActor.self)`. `swift test` exits 0 and
  prints `⚠︎ … recorded a warning`, `↳ NOT APPLIED — the false side: …`, `✔ … passed … with 1 warning`. The
  `#else` branch (before 6.3) cannot be built on this machine; it is the kit's own fallback shape.
- **N10. A hang after a LARGE output loses only the relay's tail.** 20,000 stderr and 20,000 `print` lines,
  then a spin, killed at 25 s: 1,933,312 bytes arrived, 19,953 of 20,000 lines of each kind (about 4.6 KB
  lost), the `started` line included, and no orphan was left. So N1's "all output is lost" holds only for a
  run whose whole output fits in the relay's buffer: a hang early in a quiet run.
- **N11.** `swift test --skip-build --no-parallel --filter '\.NoSuchSuiteAnywhere/'` on this repository's
  own test bundle exits 0, in 4.58 s cold and about 1.7 s warm. A filter that runs nothing exits 0, and
  about 2 s per process is the planning figure for real packages.
- **N12. The generator hoist decides per region and numbers names across the file.**
  `GeneratedFileGeneratorHoist` hoists a region only if its indent plus flattened length exceeds 120, and
  only generators of 40 or more characters; one name is `generator`, more are `generator1…N`, numbered over
  the whole file. So one generator can be hoisted in `_isTotal` and inline in a reach loop, and one extra
  hoisted generator renames the law's `Self.generator` to `Self.generatorN`: the same meaning, different
  bytes.
- **N13. The binaries' own dependency pins differ between checkouts.** `Package.resolved` is untracked.
  The work tree, where arm A was built, resolves swift-collections 1.7.5 and swift-property-based 2.0.1;
  the main checkout resolves 1.6.0 and 2.0.0. Both resolve SwiftPropertyLaws 4.10.0 and swift-syntax
  602.0.0.
