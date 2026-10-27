# Do a predicate stub's draws reach both answers? — 42.8% do, and the reach check is not emitted

> **Status:** `measured` · **As of:** 2026-10-27

This scores the census that `docs/plans/predicate-outcome-reach-scope.md` scoped for issue #665. The scope's
rule was frozen at `d41da52c`, before arm A's funnel ran and before any census or control stub was probed.
Its amendments A1–A3 were recorded at `05b75540`, also before any stub was probed. The question is whether a
`predicate` stub's own 100 draws get back both `true` and `false`, and so whether an outcome-reach check
beside each stub would be green often enough to emit.

**DECISION: NONE.** **204 of 477** rows in R reach both answers (**G = 42.8%**). That is below the 50% floor
for W. Leaving out SwiftProjectLint, which holds 73.8% of R, gives 53.6%, but the rule takes the lower band
of the two. So **nothing is emitted**: the emitter is unchanged, there is no arm B, and the funnel's `reach`
bucket ships with every column at 0. P3a and P3b both held: the predicted G was 0.40 in [0.25, 0.55], and
the predicted DECISION was NONE. **8 of 13 scored predictions held.** P13 is not scored under NONE.

The reds are mostly the generator's to fix, not the subject's. **26 of 30** hand-sampled reds have a witness
input that some generator could draw: 23 drawn by one generator, 3 needing two drawn values to line up. The 4
that are constant by design share one cause, which this census found in passing (§6.1): **the stub builds
a fresh receiver whose state the predicate reads, and nothing ever writes that state.** Both of #665's
Direction-2 triggers fire (§5).

---

## 1. The decision, verbatim

`fixtures/predicate-outcome-reach/decisions.log` holds one line. It is the only DECISION line ever recorded,
and there was no NOT-DECISIVE round:

```
2026-10-27T20:10:30Z  script 0d8f4a19  DECISION: NONE  G=42.8% (204/477)  G_loo=53.6% without SwiftProjectLint  G_all=42.8%  |R|=477  unstable=0  no_reading=0.0% of compiled  hand: constant-by-design 14.3% weighted (4/30)  V1=pass  V2a=pass  V2b=10/10  input=50c38277c609
```

How the frozen rule (scope §7) reads it:

- `instrument_ok`: V0, V1 and V2a all passed.
- `|R|` is 477, which is at least 100.
- `no_reading` is 0 of 480, which is at most 10%.
- `band(G = 0.428)` is NONE and `band(G_loo = 0.536)` is W. The rule takes the lower band, NONE.
- The hand drop from E to W does not arise.

`input=50c38277c609` digests the scratch JSONL, which carries absolute paths. The committed fixture
`census-2026-10-27.jsonl` has portable paths and also carries the 10 control rows. It digests to
`308e1fb84edc`, and `report` on it prints the same DECISION line apart from that field.

## 2. The run

| Step | What | Result |
|---|---|---|
| Harness | `efbe661f` gives the reach test its own funnel bucket. `f49bd85b` scopes the helper sweep to the funnel's own trees. `df88a65c` attributes a Swift Build parse error (A1) | The harness A/A on the control at `e36da59` covered `efbe661f` and `f49bd85b`: it moved 0 legacy keys, and the patch's self-tests killed all 14 of its mutants. `df88a65c` came after the A/A, and rests on A1's argument, not a re-run |
| Arm A | `scripts/corpus_funnel.py`, swift-infer `fef2971d` (1.160.0), CLI `eec21fbb`, 19 repositories at their recorded SHAs, kit 4.10.0. swift.org 6.4.1, except Xcode 27's Swift 6.4.0 (`swiftlang-6.4.0.34.1`) for the funnel's `XCODE_REPOS`: 62 rows from 6 repositories, 60 of them in R | 17:34:38Z–18:43:29Z. Seeds 4,743; stubs 1,537; compiled 1,058; passed 874 (308 behaviour + 566 does not crash); failed 140; crashed 44; hung 0; unaccounted 0; `reach` expected 0 |
| V0 | `predicate_outcome_reach.py --self-test` (in `make measurement-selftest`) | pass |
| V1 | toy control, 20 subjects, every class and call shape | **pass**: oracle agreement bit for bit on all 20; classes and flags as frozen in the toy's `expected.json`; 336 s |
| V2 | SwiftUMLBridge at `e36da59`, the road test's own 10 stubs | BOTH 3, ONLY-FALSE 7; 107 s. The first invocation exited on a usage error before probing anything: the repository came after the options (exit 2, so V2a had no rows). It was re-run as written |
| V2a | hand-written Xoshiro oracles replay each control stub's `law` | **pass**, 10 of 10 bit for bit |
| V2b | the census reproduces the road test's split (3 pass, 7 only `false`) | **10 of 10** |
| Census | `run`, one process per clone per mode: det (180 s), then 2 random-hashing runs (60 s) | 18:52:44Z–19:59:59Z, 4,035 s wall; 1,501 processes, 3,892 s of process time; clone builds 140 s over 19 packages. 503 rows, 0 NO READING, 0 HUNG, 0 clones set aside, nothing left in the trees |

**Two departures from the scope's order, both disclosed rather than amended.**
- `f49bd85b` also landed before the scope commit, against §0's "the harness-bucket commit (§4) is the
  only commit of this work before it". It changes only which test helpers the funnel kills between
  repositories.
- The arm-A invariants were asserted after the census (below).

The run was projected at 1.41 h before it started and took 1.12 h. `uptime` read 3.03 / 4.26 / 5.50 at
the start and 3.86 / 3.74 / 3.70 at the end, and no `swiftpm-testing-helper` was running at the start.
Nothing sampled the load in between. Arm A's own end-of-run `uptime` and `du -sh` (scope §2, §11) were
not captured: a shell variable named `status` is read-only in zsh, and the post-steps were lost to it.

**The arm-A invariants (scope §4) hold.** `report --census` asserted all of them:
- no reach name in any list;
- every `exhausted` false;
- every `resumes` ≤ 30;
- every `reach_*` 0;
- `run_seconds` present for every built package;
- `record_passes` reproduces each package's `passed` and its split;
- `unaccounted` 0.

Scope §4 orders them shown before the census. They were first asserted after it, in the 20:10:30Z
`report`, because the pre-census gate run never passed `--census`. Arm A's result files were fixed
before the census began, so the order could not change the outcome.

**Arm A's predicate population** is 503 compiled stubs, against P1's 330–500. Of those, 23 (4.6%) are in
teaching repositories, which are reported apart and never enter the rule:

| Repository | stubs | | Repository | stubs |
|---|---:|---|---|---:|
| SwiftProjectLint | 352 | | SwiftLintRuleStudio | 9 |
| SwiftEffectInference | 36 | | pbt-workbook-corpus (teaching) | 8 |
| SwiftAssist | 29 | | SwiftCloneDetector | 6 |
| SwiftPropertyLaws | 23 | | MacCloud_server | 5 |
| pbt-book (teaching) | 15 | | SwiftFormatRuleStudio | 5 |
| SwiftMarkdownWiki | 10 | | SwiftUMLStudio | 3 |
| | | | SwiftIdempotency | 2 |

## 3. What the draws reach

At 100 trials, which is the stub's own budget and the reading the rule decides on:

| Population | rows | BOTH | ONLY-FALSE | ONLY-TRUE | TRAPPED | HUNG | NO READING |
|---|---:|---:|---:|---:|---:|---:|---:|
| **non-teaching R (decides)** | **477** | **204** | 252 | 21 | 0 | 0 | 0 |
| non-teaching, all (the 3 TRAPPED are not readable) | 480 | 204 | 252 | 21 | 3 | 0 | 0 |
| teaching | 23 | 12 | 8 | 2 | 1 | 0 | 0 |
| R without SwiftProjectLint | 125 | 67 | 50 | 8 | 0 | 0 | 0 |

Per repository, R:

| Repository | rows | green | G | share of R |
|---|---:|---:|---:|---:|
| SwiftProjectLint | 352 | 137 | 38.9% | 73.8% |
| SwiftEffectInference | 35 | 23 | 65.7% | 7.3% |
| SwiftAssist | 27 | 13 | 48.1% | 5.7% |
| SwiftPropertyLaws | 23 | 11 | 47.8% | 4.8% |
| SwiftMarkdownWiki | 10 | 2 | 20.0% | 2.1% |
| SwiftLintRuleStudio | 9 | 5 | 55.6% | 1.9% |
| SwiftCloneDetector | 6 | 3 | 50.0% | 1.3% |
| MacCloud_server | 5 | 5 | 100.0% | 1.0% |
| SwiftFormatRuleStudio | 5 | 2 | 40.0% | 1.0% |
| SwiftUMLStudio | 3 | 1 | 33.3% | 0.6% |
| SwiftIdempotency | 2 | 2 | 100.0% | 0.4% |

By how each row draws its inputs and builds its receiver, R:

| Cut | rows | G |
|---|---:|---:|
| `syntax-corpus` | 315 | 45.4% |
| `hostile-string` | 115 | 40.9% |
| — with the subject's own literals | 50 | **68.0%** |
| — without | 65 | **20.0%** |
| `derived` · `other` · `stdlib-scalar` · `array` | 21 · 16 · 8 · 2 | 19.0% · 43.8% · 25.0% · 50.0% |
| unary · relational | 394 · 83 | 42.6% · 43.4% |
| receiver constructed · none · drawn | 240 · 224 · 13 | **36.2%** · 48.2% · 69.2% |
| isolation none · MainActor | 462 · 15 | 42.6% · 46.7% |

**The reds are one-sided**: 252 of 273 (92.3%) return only `false`. A predicate the generator misses is
almost always one whose `true` needs a particular token, name or shape.

**The rare region is small.** At 1,000 trials, 40 of the 273 reds reach the other answer (14.7%). That puts G
at 1,000 at 51.2% (244/477), 8.4 points above G at 100. The scope's budget-raise trigger is 20 points, so no
budget follow-up is filed. The 1,000-trial reading decides nothing: the check would run at the stub's own
100 trials. Of the 204 BOTH rows, 55 (27.0%) reach their minority answer at most twice in 100. Those rows
are green, but only barely.

**Stability:** no row is unstable, stateful or hash-sensitive, and no row has `again_bits_differ`,
`scale_prefix_differs` or `hash_sensitive_bits` set. **Detector power** (scope §3): a row whose class
flips per process with probability ½ escapes det plus 2 random-hashing runs with probability ¼. Under
NONE there is no arm B to catch it. All 4 TRAPPED rows have `law_a == crashed`, and every
readable row passed its law in arm A. No row throws or is async.

## 4. The hand check, blind to G

The sample is scope §5's frozen draw: 30 of the 273 reds, allocated by largest remainder (SwiftProjectLint
24; SwiftAssist 2; one each from SwiftEffectInference, SwiftLintRuleStudio, SwiftMarkdownWiki and
SwiftPropertyLaws), drawn with `random.Random(20261027)`.

**How it was kept blind.**
- Each row went to two judges, each taking an independent approach:
  - *witness-first*: hunt for an input that gives the other answer;
  - *constant-first*: try to prove that no input can.
- Each judge read only that row's block of `sample`'s output, the stub, and the repository's census tree
  (the subject, its helpers, the syntax corpora). They were barred from the JSONL, the run log, `gates.meta` and the script.
- A third judge was held ready for any disagreement. **The two agreed on all 30, so none was called.**
- `judgements.json` was written from their verdicts, and its sha256 (`f60fd60d3f0c…`) was logged at
  20:08:18Z. It was committed at `0d8f4a19`, and `report` first ran at 20:10:30Z.
- **Disclosed:** the census run log prints each package's class tallies as it goes, and the operator saw
  them before the judges ran. The judges did not see them, the DECISION is computed mechanically, and the
  verdicts could not have moved it (below).

**Two readings of §5's class definitions were given to the judges.** They were written as instructions,
not recorded as amendments:
- **`relational`** is for a condition that relates two *drawn* values to each other. A condition where
  each drawn value meets a constant on its own (a table key, a version floor) is `generator-miss`.
- **A value the stub fixes**, such as a constructed receiver or a held argument, is held as the stub writes
  it.

Neither reading can move the DECISION. `cbd_share` is consulted only when the bands give E, and P11 counts
`generator-miss` and `relational` together.

| Class | n | Weighted share |
|---|---:|---:|
| `generator-miss` | 23 | |
| `relational` | 3 | |
| `constant-by-design` | 4 | 14.3% (k/n = 4/30) |
| `undecidable-by-reading` | 0 | |

- **Every `generator-miss` and `relational` note names a witness traced through the code.** Some examples:
  - `"<think>"` for `ThinkState.promptOpensThinking`;
  - the attribute list of `@ClockDeterministic func f() {}` for `hasClockDeterministicAttribute`;
  - `("inert_defer", "1")` for `SwiftLintDeprecations.isRemoved`.
- **7 of the 30 sampled rows reach BOTH at 1,000 trials**, so a witness exists for each by construction.
  All 7 were judged `generator-miss`. This is not an independent check: `sample` prints each row's
  1,000-trial class in its header, so the judges saw it.
- **Erratum, `hasClockDeterministicAttribute`:** its note ends "The corpus simply holds no such attribute
  list". That is false. The package's `SwiftInferSyntaxCorpus.swift` holds `@ClockDeterministic` four
  times, and the row reaches `true` twice in 1,000 draws (first at draw 550). The witness and the class
  stand. `judgements.json` is hash-frozen, so the note is corrected here, not there.
- **The three `relational` rows** each need a drawn string to equal a name inside a drawn syntax node or
  string array:
  - `AccessibilityTreeTraverser.containsAccessibilityModifier`;
  - `VariableShadowingVisitor.sequenceReferences`;
  - `DeclaredRoleClassifier.isOrdering`. This one also needs a function name from a constant table that
    its corpus never supplies, so pairing alone would not reach it.

  Of the 5 sampled reds whose `row_kind` is `relational`, 3 were judged `relational`. That is §8's
  precision reading: 60%.

## 5. Direction 2: both reopen triggers fire

#665's Direction 2 is reach at the source. It has two parts:
- seed the syntax-corpus draws with the tokens a predicate body compares against;
- pair two drawn values so they line up.

Scope §8 froze one mechanical trigger for each:

| Trigger | Bar | Measured |
|---|---|---|
| syntax-corpus seeding: red rows in R with `primary_kind == "syntax-corpus"` | ≥ 30 in ≥ 2 repositories | **172 in 4**: SwiftProjectLint 161, SwiftEffectInference 8, SwiftPropertyLaws 2, SwiftCloneDetector 1 |
| relational draws: red rows in R with `row_kind == "relational"` | ≥ 20 in ≥ 2 repositories | **47 in 8**: SwiftProjectLint 35, SwiftAssist 3, and 1–2 in each of six more |

Both reopen. Under NONE (by the bands), scope §10 says the follow-up is to score Direction 2 by the rows it
moves to BOTH, measured with this script. Neither trigger touches the separate guard-literal trigger in
`docs/plans/subject-literal-generation-scope.md` §4c.

**The literal seeding that already ships is the precedent.** Among `hostile-string` rows, those whose stub
also draws the subject's own string literals are green 68.0% of the time (34/50). Those without are green
20.0% of the time (13/65).

This is a cut, not an A/B. The literal draw exists only where the subject's body holds string literals, so
the two groups differ in more than the draw. It is, however, the same mechanism Direction 2 would give the
syntax corpus, and the one place a census can see it working.

## 6. Found in passing

### 6.1 Every sampled constant-by-design red is a receiver the stub builds in its initial state

All 4 sampled `constant-by-design` rows have a constructed receiver whose state the predicate reads:

- **`PluginTimeoutTracker.isDisabled`:** a fresh tracker's `disabled` set is empty.
- **`ObservableEnvironmentViewMissingInspectionHookVisitor.isInspected`:** a fresh visitor's
  `knownInspectedTypeNames` is `nil`, so it answers `true`.
- **`DirectInstantiationVisitor.isRuntimeDrivenMember`:** a visitor that never walked has an empty
  `entryTypeStack`.
- **`GeneratorResolver.isRecursive`:** a resolver that never resolved has an empty `recursiveDeclarations`.

Each predicate is honest about its receiver, and the stub's receiver has not been through anything. The
red is real but, like the 4 above, not the subject author's to fix.

Constructed receivers have the lowest G of any receiver kind, 36.2%. Among the 18 sampled reds with a
constructed receiver, 4 are these constants.

`docs/measurements/held-receiver-laws.md` measured what holding a receiver frees. This is a cost it did not
measure: a state-reading predicate on a fresh receiver is constant.

### 6.2 Two instrument findings

- **Swift Build's parse-error form (A1).** Swift 6.4's build system prints `error: <path>:<l>:<c> <msg>`
  for a parse error and then stops, so stage 5 read whole packages as unbuilt with nothing set aside. In the
  first arm-A run that hid 496 SwiftProjectLintRules stubs. `df88a65c` reads both forms in stage 5 and
  `literal_reach_check`.
  - `generator_diversity.py` and `reference_oracle_scaffold_census.py` still read only the old form.
  - **Any funnel figure taken under 6.4 before `df88a65c` may undercount compiles** wherever one stub fails
    to parse.
- **`generator_diversity.expressions` was blind to a hoisted generator.** Since `0d4ab637` (2026-10-10), a
  stub may draw through `Self.<name>.run(using:)`. That is 426 of the 1,064 generated stub files in arm A's
  trees, and 169 of the 503 predicate stubs.
  - Fixed on this branch: `expressions` now reads the `static let` text, as this probe does, through
    `mutation_check.hoisted_generator`.
  - Over arm A's stubs it now finds 1,478 draws where it found 879: all 599 hoisted draws. That is 340
    distinct generators where it found 118.

## 7. The predictions, scored: 8 of 13

| # | Prediction | Measured | |
|---|---|---|---|
| P1 | 330–500 compiled `predicate` stubs; teaching ≤ 10% | 503; 4.6% | ❌ by 3 stubs |
| P2 | readable ≥ 94%; TRAPPED + HUNG ≤ 3%; NO READING ≤ 3%; clones set aside 0; `wrap n≠1` ≤ 2; `missing` 0; throwing and async 0 | 99.2%; 0.8%; 0; 0; 0; 0; 0 | ✅ |
| P3a | G = 0.40, interval [0.25, 0.55] | 0.428 | ✅ |
| P3b | DECISION = NONE | NONE | ✅ |
| P4 | largest = SwiftProjectLint; its G ≤ 0.35; G_loo ≥ G | yes; **38.9%**; 53.6% ≥ 42.8% | ❌ on its own G |
| P5 | teaching G ≥ 0.70 | **54.5%** (12/22) | ❌ |
| P6 | syntax-corpus G ≤ 0.30; hostile-string unary 0.40–0.75; stdlib-scalar ≥ 0.65; relational G ≤ unary G | **45.4%**; **38.4%**; **25.0%**; **43.4% > 42.6%** | ❌ on all four |
| P7 | ONLY-FALSE ≥ 80% of reds; ONLY-TRUE ≤ 6% of R | 92.3%; 4.4% | ✅ |
| P8 | 5–20% of reds are BOTH at 1,000; G at 1,000 − G at 100 ≤ 10 points | 14.7%; 8.4 points | ✅ |
| P9 | unstable ≤ 3; `again_bits_differ` + `scale_prefix_differs` ≤ 3 | 0; 0 | ✅ |
| P10 | of BOTH rows, ≤ 25% reach their minority answer ≤ 2 times | **27.0%** (55/204) | ❌ |
| P11 | hand: generator-miss + relational ≥ 60% weighted; constant-by-design ≤ 20% | 85.7%; 14.3% | ✅ |
| P12 | V2a passes on every control row; V2b = 10 of 10 | pass; 10/10 | ✅ |
| P13 | arm B (E or W only) | — | not scored |

**The misses are mostly about where G lies, not about G itself.**
- The syntax corpus reaches more than predicted (P6), and SwiftProjectLint less than the corpus as a whole
  but more than predicted (P4).
- The scalar and derived generators reach *less*, but they are 29 rows between them.
- The teaching repositories, written to be tested, reach both answers only about half the time (P5).
- P10 missed by 4 rows (55 against a bound of 51): the green rows are a little more marginal than
  predicted.

## 8. What NONE ships, and the follow-up

**Nothing is emitted.** Commits 4a and 4b (the shared totality call, and the reach `@Test` with its E or W
form) and 5 (arm B) are dropped. The branch ships:
- the scope and its amendments;
- the probe, `scripts/predicate_outcome_reach.py`, with its V0 self-test and the toy fixture;
- the funnel's `reach` bucket, with every column at 0 since no stub emits a reach test;
- two harness fixes, A1's parse-error form and the scoped helper sweep;
- this record: `fixtures/predicate-outcome-reach/census-2026-10-27.jsonl` (the 503 census rows and 10
  control rows), `judgements.json` and `decisions.log`.

**The follow-up issue** (scope §10, NONE by the bands) is Direction 2. Both of §5's triggers fired, so it is
reopened on two fronts:
- syntax-corpus seeding: 172 red rows, 161 of them in SwiftProjectLint;
- relational pairing: 47 red rows.

Success is scored as rows moved to BOTH, re-measured by running this script on a fresh funnel. Its number is
added here when it is filed.

## 9. V3, the mutation run's baselines

V3 is a reading, not a gate. `fixtures/mutation-check/run-2026-09-22.jsonl` digests each predicate baseline's
100 outputs. 7 of the 14 carry `1466cff07c09e9d2`, which is 100 × `false`. The census reads them, at later
SHAs and under the renamed stubs, as:

| Baseline digest | Census `class100` |
|---|---|
| all `false` (7) | ONLY-FALSE 6, BOTH 1 (`CallSiteEffectInferrer.isMetricReceiver`) |
| any other (7) | BOTH 6, ONLY-FALSE 1 (`OllamaModelMatching.isInstalled`, which reaches BOTH at 1,000) |

12 of 14 agree. The two that do not lie in opposite directions, and `isInstalled`'s `true` region is rare
enough that 100 draws can miss it.

## 10. What this does not answer

- **A reach claim is not a law.** No kill is measured, and no pass count moves. The road test's third
  A-quality mutant (`conformsToGRDBRecord`), killed only by a reach check, is not counted.
- **This corpus, never a rate.** G is the share of R, which is the passing, readable `predicate` stubs of
  the 11 non-teaching repositories that have any (of 14 surveyed), at these SHAs. 73.8% of R is one repository.
- **Constant by design is sampled, not found.** The hand check estimates the share; it names 4 rows, not
  all of them.
- **The verify-side twin** (`composePredicatePass`, whose draws are the strategist's 1,000) is not measured.
  It stays deferred on its witness, scope §10.
