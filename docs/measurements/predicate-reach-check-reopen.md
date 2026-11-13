# Does #665's reach check clear its floor now? — W, at G = 58.9%

> **Status:** `measured` · **As of:** 2026-11-13

This re-takes #665's predicate outcome-reach census on A′: #684's shipped generators, at `05d97356`. The rule and
predictions were frozen in `docs/plans/predicate-reach-check-reopen-scope.md` at `d79d72e7` (#724), before
anything ran. One amendment, A1, was recorded before any census figure was read.

**DECISION: W.** **279 of 474** rows in R reach both answers (**G = 58.9%**). Leaving out SwiftProjectLint, which
holds 75.9% of R, gives **G_loo = 58.8%**. Both clear the 0.50 floor for W and fall short of 0.80 for E. The
instrument passed (V0, V1 and V2a). |R| ≥ 100, NO READING is 0%, and no row is unstable. Under W, the scope's
next step is #665's commits 4a and 4b, then commit 5's funnel re-take. **4a and 4b are built (2026-11-13); commit 5
has not run** (§7).

**5 of 6 scored predictions held.** R1 missed on two counts:
- V1 passed only after one fix round, because its toy oracles predated #684's pairing line;
- V2b read 5 of 10, not 10.

All five V2b misses are generator drift from #684's own levers: rows that the issue measured as red now reach both
answers. R7 (arm B's crosscheck) is not scored until commit 5 runs.

**Caveats:**
- **G moved for the reason #684 measured.** G is 41.1% → 58.9% against #684's A0, and 42.8% → 58.9% against #665.
  Both are rows moved to BOTH by the generators, not a change of rule.
- **A1 held back one law.** That law opened URLs on the host. Counting its row back in as red gives G = 58.7%
  (279/475) and G_loo = 58.3% (67/115), still W.

---

## 1. The decision, verbatim

`fixtures/predicate-reach-check-reopen/decisions.log` holds one line. There was no NOT-DECISIVE round:

```
2026-11-13T16:48:00Z  script 409b595b  DECISION: W  G=58.9% (279/474)  G_loo=58.8% without SwiftProjectLint  G_all=58.9%  |R|=474  unstable=0  no_reading=0.0% of compiled  hand: constant-by-design 22.6% weighted (7/30)  V1=pass  V2a=pass  V2b=5/10  input=65c425671f7e
```

`script 409b595b` is the checkout the script ran from. `scripts/predicate_outcome_reach.py`, `scripts/reach_arms.py`
and `scripts/corpus_funnel.py` are byte-identical between `05d97356` and `409b595b` (`git diff --quiet`), so the
script is the scope's. `input=65c425671f7e` is the sha256 prefix of the census JSONL, which is committed as
`fixtures/predicate-reach-check-reopen/census-2026-11-13.jsonl`.

The rule and its inputs:

| term | value | rule |
|---|---|---|
| G | 58.9% (279/474) | W at 0.50 or above |
| G_loo | 58.8% without SwiftProjectLint (67/114) | W at 0.50 or above |
| decision | min(W, W) = W | the lower band |
| constant-by-design share | 22.6% weighted | under half, so an E would not have dropped |
| \|R\| | 474 | at least 100 |
| NO READING | 0.0% of `compiled_nt` | at most 10% |
| `instrument_ok` | V0, V1 and V2a pass | all three |

## 2. The instrument

| gate | result |
|---|---|
| **V0** (`--self-test`) | pass |
| **V1** (the toy control) | **pass after fix round 1** |
| **V2a** (hand oracles beside 10 real stubs) | **pass, 10 of 10** agree bit for bit; 5 were needed |
| **V2b** (the issue's 10, a reading) | **5 of 10**; all 5 misses are `generator-drift` |

**V1, fix round 1.** V1's first run failed gate (a). The toy's hand oracles replay each stub's draws without the
stub, and the oracles for `isRightOf` and `isWithin` were written before #684. #684 added a pairing draw to every
relational stub (`if Int.random(in: 0 ..< 4, using: &rng) == 0 { arg1 = arg0 }`). The stub draws that extra
random number and the oracle did not, so from the first relational trial on the two read different sequences.
The fix copies the pairing line into those two oracles, `fixtures/predicate-outcome-reach/toy/Oracles.swift`, and
V1 then passed. That is #665 §7's bounded fix round: the instrument was out of date with the code it reads, and the
code did not change.

**V2b's five misses.** The issue measured these as ONLY-FALSE, and all five now read BOTH at 100:

| stub | the issue | A′ | cause |
|---|---|---|---|
| `ActivityGraphBuilder.isAddTaskCall` | ONLY-FALSE | BOTH | `generator-drift`: #684's seeded syntax draw (`gen(_:preferring:kinds:)`) |
| `ERModelExtractor.hasAttribute` | ONLY-FALSE | BOTH | `generator-drift`: seeded syntax draw |
| `PersistenceSchemaExtractorVisitor.isStatic` | ONLY-FALSE | BOTH | `generator-drift`: seeded syntax draw |
| `SyntaxStructureBuilder.isStaticOrClass` | ONLY-FALSE | BOTH | `generator-drift`: seeded syntax draw |
| `String.isMatching` | ONLY-FALSE | BOTH | `generator-drift`: #684's pairing line |

The resolved kit is 4.10.0 on both sides, and in each case the generator text differs, so none is `kit-drift`.
None is `unexplained`. The other five read as the issue measured them: three BOTH and two ONLY-FALSE
(`isTaskGroupName`, `isExcluded`).

## 3. The population

At 100 trials (the det `law` test):

| population | rows | BOTH | ONLY-FALSE | ONLY-TRUE | TRAPPED | HUNG | NO READING |
|---|---:|---:|---:|---:|---:|---:|---:|
| **non-teaching R (decides)** | **474** | **279** | 184 | 11 | 0 | 0 | 0 |
| non-teaching, all (G_all) | 475 | 279 | 184 | 11 | 1 | 0 | 0 |
| teaching | 23 | 13 | 7 | 2 | 1 | 0 | 0 |
| R without SwiftProjectLint | 114 | 67 | 44 | 3 | 0 | 0 | 0 |

**At 1,000 trials, G is 70.0% (332/474)**: 53 rows red at 100 reach both answers by 1,000. That is 11.1 points
above G at 100, under the 20 points at which #665 §7 files the stub-budget follow-up, so it is not filed.

<details><summary>Per repository, per kind, and the consistency checks</summary>

| repository | rows | green | G | share of R |
|---|---:|---:|---:|---:|
| SwiftProjectLint | 360 | 212 | 58.9% | 75.9% |
| SwiftEffectInference | 31 | 20 | 64.5% | 6.5% |
| SwiftPropertyLaws | 23 | 11 | 47.8% | 4.9% |
| SwiftLintRuleStudio | 17 | 10 | 58.8% | 3.6% |
| SwiftUMLStudio | 13 | 10 | 76.9% | 2.7% |
| SwiftMarkdownWiki | 10 | 2 | 20.0% | 2.1% |
| SwiftCloneDetector | 6 | 3 | 50.0% | 1.3% |
| MacCloud_server | 5 | 5 | 100.0% | 1.1% |
| SwiftFormatRuleStudio | 5 | 2 | 40.0% | 1.1% |
| SwiftAssist | 2 | 2 | 100.0% | 0.4% |
| SwiftIdempotency | 2 | 2 | 100.0% | 0.4% |

| `primary_kind` | rows | G |
|---|---:|---:|
| syntax-corpus | 326 | 65.0% |
| hostile-string | 111 | 48.6% |
| derived | 16 | 31.2% |
| other | 12 | 50.0% |
| stdlib-scalar | 7 | 14.3% |
| array | 2 | 50.0% |

By `row_kind`: unary 391 rows at G 57.3%, relational 83 at 66.3%. By receiver: constructed 247 at 56.7%, none 210
at 59.5%, drawn 17 at 82.4%.

**Consistency:**
- `unstable`, `stateful` and `hash_sensitive_class` are all 0, and so is every bit flag.
- No readable row's law failed in arm A.
- Both TRAPPED rows are `law_a == crashed`.
- `throwing` 0, `async` 0.
- The arm-A invariants over the census directory all hold.
- Process time was 3,336 s over 1,490 processes, and clone builds took 106 s over 17 packages.

**A′'s funnel** matches #684's A3 save for one stub: 1,647 stubs, 992 compiled, 823 passed, 127 failed, 42 crashed,
0 hung (A3: 1,648 / 993 / 823 / 127 / 42 / 0). The missing stub is SwiftUMLStudio's
`consumer-producer/matchGlobs_expandGlobs`, a law #721's impure-subject veto now withholds. It is not a predicate,
so R is unaffected.

</details>

## 4. The hand sample

`sample` drew 30 of 195 reds by #665 §5's stratified rule (seed `20261027`). SwiftProjectLint got 23, and seven other
repositories got 0–2 each. Two judges classified every row independently, with the rows split differently between
them, from `sample`'s output and the subject trees only. Neither judge read the census JSONL or a report. **All 30
rows agreed, so none needed adjudication.** `judgements.json` was complete and its sha256 (`eb35b3df…`) logged at
16:47:49Z, before `report` first ran at 16:48:00Z.

| class | rows | #665 |
|---|---:|---:|
| `generator-miss` | 19 | 23 |
| `relational` | 4 | 3 |
| `constant-by-design` | 7 | 4 |
| `undecidable-by-reading` | 0 | 0 |

**The constant-by-design share is 22.6% weighted (7/30 = 23.3% unweighted), against #665's 14.3%.** The rise is
expected: #684's levers turned generator misses green, so a larger share of the reds left are ones no generator can
fix. Of the seven:
- **Five are #665 §6.1's receiver state.** The stub builds a fresh receiver, the predicate reads state that only a
  walk or a recording call writes, and the stub makes neither: `CloneFinder.passesIdentifierFloor`,
  `EffectSymbolTable.isCollision`, `PluginTimeoutTracker.isDisabled`, `AccessibilityVisitor.isImageInButtons` and
  `UnreachableEffectClosureVisitor.writesOnlyViewState`.
- **One is environment state.** `MirrorLock.isHeld` is true only while another descriptor holds `flock` on a lock
  file, and no drawn URL names a real directory. Its subject calls `open` and `flock`, so it is impure.
  SwiftEffectInference `ba3624d`, the pin this repository moves to next, refutes it, and the impure-subject veto
  then withholds the law.
- **One is constant in the code.** `StringSwitchOverEnumVisitor.isLikelyEnumBase` returns `true` on every path; its
  own comment calls the fall-through a deliberate opt-in heuristic.

<details><summary>The 30 sampled rows</summary>

Each row's witness or reason is in `fixtures/predicate-reach-check-reopen/judgements.json`.

| # | repository | stub | class |
|---:|---|---|---|
| 1 | SwiftCloneDetector | `CloneFinderPassesIdentifierFloor` | constant-by-design |
| 2 | SwiftEffectInference | `CaptureMutationCheckerIsShorthandParameter` | generator-miss |
| 3 | SwiftEffectInference | `EffectSymbolTableIsCollision` | constant-by-design |
| 4 | SwiftLintRuleStudio | `MirrorLockIsHeld` | constant-by-design |
| 5 | SwiftMarkdownWiki | `PluginTimeoutTrackerIsDisabled` | constant-by-design |
| 6 | SwiftProjectLint | `ServiceTypeSuffixMatches` | generator-miss |
| 7 | SwiftProjectLint | `CouldBePrivateMemberVisitorHasDisqualifyingDeclShape` | generator-miss |
| 8 | SwiftProjectLint | `MemberImportVisibilityNotEnabledVisitorEnablesFeature` | generator-miss |
| 9 | SwiftProjectLint | `LayerPolicyContains` | generator-miss |
| 10 | SwiftProjectLint | `AccessibilityTreeTraverserContainsAccessibilityModifier` | relational |
| 11 | SwiftProjectLint | `UserDefaultsSensitiveDataVisitorIsSensitiveKey` | generator-miss |
| 12 | SwiftProjectLint | `StringSwitchOverEnumVisitorIsLikelyEnumBase` | constant-by-design |
| 13 | SwiftProjectLint | `ObservableTypeCollectorDeclaresObservableObject` | generator-miss |
| 14 | SwiftProjectLint | `AccessibilityVisitorIsImageInButtons` | constant-by-design |
| 15 | SwiftProjectLint | `CatchWithoutHandlingVisitorContainsTerminatingCall` | generator-miss |
| 16 | SwiftProjectLint | `SwiftDataUniqueAttributeCloudKitVisitorHasUniqueAttribute` | generator-miss |
| 17 | SwiftProjectLint | `MemberImportVisibilityNotEnabledVisitorSupportsUpcomingFeatures` | generator-miss |
| 18 | SwiftProjectLint | `ObservableTypeCollectorHasObservableAttribute` | generator-miss |
| 19 | SwiftProjectLint | `LoggingSensitiveDataVisitorSensitiveReferenceFinderContainsSensitiveWord` | generator-miss |
| 20 | SwiftProjectLint | `MissingDynamicTypeSupportVisitorHasParentModifier` | relational |
| 21 | SwiftProjectLint | `RegistrationVerbIsStringOutputBuilding` | generator-miss |
| 22 | SwiftProjectLint | `ForwardingCallDescribes` | relational |
| 23 | SwiftProjectLint | `IsButtonTraitWithoutActionVisitorAddsIsButtonTrait` | generator-miss |
| 24 | SwiftProjectLint | `UnreachableEffectClosureVisitorWritesOnlyViewState` | constant-by-design |
| 25 | SwiftProjectLint | `ObservableViewInspectionHookVisitorHasInspectionHook` | generator-miss |
| 26 | SwiftProjectLint | `SynthesizedConformanceIsImplicitlyEquatable` | generator-miss |
| 27 | SwiftProjectLint | `BooleanControlCouplingVisitorIsBoolType` | generator-miss |
| 28 | SwiftProjectLint | `DirectInstantiationVisitorInsideCompositionRoot` | generator-miss |
| 29 | SwiftPropertyLaws | `InitializerPreconditionDetectorContainsSelfInitCall` | generator-miss |
| 30 | SwiftPropertyLaws | `RecursiveGeneratorEmitterIsRecursive` | relational |

</details>

## 5. The predictions, scored

| # | prediction | result | |
|---|---|---|---|
| R1 | V0, V1 and V2a pass; V2b reads 10 of 10 | V1 passed after fix round 1; V2b read 5/10 | **missed** |
| R2 | \|R\| in [450, 500]; NO READING 0%; unstable at most 5 | 474; 0.0%; 0 | held |
| R3 | G in [0.55, 0.63] | 0.589 | held |
| R4 | G_loo in [0.52, 0.63], SwiftProjectLint still the largest | 0.588; SwiftProjectLint 75.9% of R | held |
| R5 | DECISION = W | W | held |
| R6 | constant-by-design at most 25% of the hand sample | 22.6% weighted | held |
| R7 | under W, arm B moves 0 law rows, a clean content diff, reach-bucket green = A′'s green | not run: needs commits 4a, 4b and 5 | not scored |

## 6. Amendment A1, and what it can move

A′'s fresh SwiftLintRuleStudio tree had no skip marker. So `discover` proposed the `predicate` law over
`SystemXcodeLauncher.open(_:)`, which is `NSWorkspace.shared.open(url)`, and the funnel opened browser pages on the
host. The scope's amendment A1 records the stop, the reset, and the skip marker `// swiftinfer: skip
0x83347B0CF1C8F7D8` added before the funnel resumed. That row was ONLY-TRUE in every #684 arm. **Counted back in as a
red row, G = 58.7% (279/475) and G_loo = 58.3% (67/115). The decision is W either way.**

The skip marker is no longer needed. At SwiftEffectInference `ba3624d`, `NSWorkspace` is a side-effect marker, and on
a marker-free SwiftLintRuleStudio tree at `77cc792` a `ba3624d` build of `discover` withholds both
`0x83347B0CF1C8F7D8` and `MirrorLock.isHeld` through the impure-subject veto. `05d97356` proposes both.

## 7. What W sets in motion, and what waits

The scope's W row, unchanged:
- **4a:** share the totality call between `_isTotal` and the reach test, byte-identical.
- **4b:** emit the reach `@Test` after `_isTotal`, predicate only, with `Self.reachNote(…)` records, the per-stub helper
  and the W header line.
- **5:** the funnel re-take: arm B against A′, with #665 §9's crosscheck. Any crosscheck difference that §9 says blocks,
  blocks.

**4a and 4b are built (2026-11-13). Commit 5 has not run, so R7 is still unscored.**
- **4a is behaviour-neutral.** `TotalityCall` holds the call, and `stubTrialCount` names the 100-trial budget. On the
  V1 toy, the 20 stubs written by a build of 4a are byte-identical to a build of `main` at `25434303`.
- **4b emits the reach test.** It is `LiftedTestEmitter.reachesBothOutcomes`, the note text comes from `NotApplied`, and
  the header lines from `InteractiveTriage.reachLines`. It is written for `predicate` stubs only, never for a throwing or
  `async` subject. It replays the law's draws in a `Xoshiro(seed:)` loop over the law's four seed words, the backend's
  own loop, written out as `guard-domain`'s coverage pass writes it. It calls the subject through `TotalityCall`.
- **Amendment A2: the suite is `@Suite(.serialized)`.** An adversarial review found that a plain, parallel
  `swift test` ran the reach test beside its law. On the toy's stateful `isFirstSighting` that crashed the test
  process in 10 of 10 runs; the census never saw it, because every harness passes `--no-parallel`. Serialized, 8 of 8
  parallel runs passed with the census's true-side note. #665 §9's normalisation now also drops that one line.
- **A known limitation, recorded and not fixed:** the helper's `#if compiler(>=6.3)` reads the compiler, not the
  Testing library linked. So a test target that builds the swift-testing package below 6.3 from source cannot compile
  the predicate files. #665 §7 fixes the W form as this helper and is not amendable.
- **Checked end to end on the V1 toy:**
  - all 20 stubs built under `-warnings-as-errors`;
  - each of the 20 equals `main`'s after #665 §9's normalisation (`normalised_predicate`), as do SwiftAssist's 225
    stubs, whose 160 non-predicate files are byte-identical;
  - every reach verdict with a known class matched the toy's `class_again`: four notes on the expected sides, and the
    stateful `isFirstSighting`'s true-side note when its law runs first, as in the funnel's serial run.

Under W a reach test records a note and never fails, so it kills nothing under exit-status tools (#665 N9).

## 8. Not answered here

- **Kills, and criterion A.** A reach claim is not a law.
- **Receiver state.** Five of the seven constant-by-design reds stay red under W, and are right to.
- **The verify-side twin** (`composePredicatePass`), and `input-totality` / `measure-non-negativity`.
- **A rate.** G is the share of R in the 11 non-teaching repositories with rows in R, at these SHAs.

<details><summary>Provenance</summary>

| item | value |
|---|---|
| `swift-infer` | release build of `05d97356`, sha256 `5ef1f617…`, prints `1.160.0 (unattributable build)` |
| script | `scripts/predicate_outcome_reach.py`, byte-identical at `05d97356` and `409b595b` |
| seed CLI | SwiftProjectLint `6a231cda` |
| subjects | LintStudioUI `abcff42`, MacCloud_client_MacOS `9424f4f`, MacCloud_server `b0a1495`, SwiftAssist `8e1bc8d`, SwiftCloneDetector `e03e865`, SwiftEffectInference `5e981ca`, SwiftFormatRuleStudio `61cfea1`, SwiftIdempotency `adf8d18`, SwiftLintRuleStudio `77cc792`, SwiftLintRuleStudioTeam `7789bde`, SwiftMarkdownWiki `51b789e`, SwiftProjectLint `6a231cda`, SwiftPropertyLaws `b45d1bf`, SwiftUMLStudio `9ad7631`; teaching: pbt-book `3e76194`, pbt-workbook `959937e`, pbt-workbook-corpus `6df2650`, pbt-workbook-grader `79e6c81`, pbt-workbook-sampler `0e07795`. Every tree was clean |
| kit | SwiftPropertyLaws as each subject resolves it: 4.11.0 in 24 manifests, 4.10.0 in 1, both before SwiftPropertyLaws#99's `.invalid` hosts |
| toolchains | swift.org `swift-6.4.1-RELEASE`; Xcode's toolchain for the funnel's `XCODE_REPOS` |
| census | 2026-11-13T15:44:12Z to 16:41:38Z; load 11.7 at the start, 3.4 at the end |
| hand check | two blind judges per row, split differently between them; 30 of 30 agreed |
| fixtures | `fixtures/predicate-reach-check-reopen/`: `census-2026-11-13.jsonl`, `judgements.json`, `decisions.log` |

</details>
