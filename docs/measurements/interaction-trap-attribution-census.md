# Interaction trap attribution — is `measured-defaultFails` one population or two?

> **Status:** `measured` · **As of:** 2026-08-07


**Subject:** the six interaction verify corpora under `Tests/Fixtures/`, at `164482a` **plus the
attribution change this doc describes** — the marker and the parser split did not exist before, so
there is no "before" arm and none is claimed. The number here is a first reading, not a delta.
**Instrument:** `TrapAttributionCensusMeasuredTests` (opt-in — see §5).
**Question:** of the refutations `verify-interaction` reports, how many are the harness's own
invariant check firing, and how many are the subject trapping for its own reasons?

---

## 1. Why the question exists

`InteractionVerifyOutcomeParser` maps **every** non-zero exit from the verifier binary to
`.measuredDefaultFails`, and its doc comment defends that in as many words:

> A non-zero exit from the verifier binary means a Swift trap fired — the reducer panicked under
> some action sequence, which IS a real signal that the property "reducer doesn't crash" is violated.

That argument is sound for a **reducer**, which is total over its action alphabet by construction:
if it traps, something is wrong with it. It is not obviously sound for a carrier whose methods
legitimately carry preconditions. There, an unguarded random sequence can call a method out of
order, trap, and produce a `measured` refutation that is an artifact of the generator rather than
evidence about the invariant — a false positive at the tier the reader-facing `docc` surface trusts.

This was the live half of `docs/design/Interaction Invariant Taxonomy.md` §3.6: *"sequences today are
unguarded, so an action that traps on an invalid precondition can mask signal."* The kit shipped the
remedy (`StatefulGuard`, v2.2.0) and the engine never passed one. Before building that, the
question is whether the population it would protect exists.

## 2. Method

Every emitted invariant `precondition` now carries a byte-stable prefix,
`ActionSequenceStubEmitter.invariantViolationMarker` — a marker rather than the English
("… invariant violated") so the parser is not matching prose a subject could coincidentally print.
Swift writes a `precondition` message to stderr on trap, and `parseRunOutput` already receives
stderr (it scans it for `TRACE-CURRENT-SEQ:`). So the attribution needs no new machinery:

| stderr | attribution |
|---|---|
| carries the marker | `.invariantCheck` — the property is genuinely refuted |
| no marker, but a sequence was reached | `.subjectCode` — the subject's own trap |
| no marker, no sequence reached | `.unattributable` |

**Absence of the marker never convicts the subject on its own.** A harness that stopped emitting the
marker would otherwise turn a corpus of real refutations into a corpus of "artifacts" — arriving at
this census's most interesting possible finding by way of a bug. A trap is attributed to the subject
only when the process is known to have reached a sequence.

The verdict is deliberately **unchanged**: both still return `.measuredDefaultFails`. Whether a
subject-code trap should count as a refutation is a calibration question, and changing the verdict
in the same step would destroy the baseline it is asked against.

## 3. Result

Six corpora, `--sequence-count 128`, 347s:

| | count |
|---|---|
| refutations surveyed | **10** |
| `.invariantCheck` | **10** |
| `.subjectCode` | **0** |
| `.unattributable` | **0** |

Two each from `cardinality`, `conservation`, `biconditional`, `referential-integrity`; one each from
`determinism` and `idempotence`.

**Every measured refutation in the corpora is the harness's own check firing. There are no
trap-artifacts.**

## 4. What this does and does not license

**Does:** the conflation defended in the parser is, on this population, not costing anything. The
`.measuredDefaultFails` verdicts these corpora produce are all genuine.

**Does not:** these are *reducer* corpora, and reducers are exactly the population where the
conflation was predicted to be harmless. The hypothesis was about MVVM / VIPER carriers whose
methods carry preconditions, and **no fixture corpus contains that shape**, so that half is
unmeasured rather than refuted. Stating it the other way round — "0 artifacts, therefore the concern
was wrong" — would be reading a confident zero as evidence.

The consequence for §3.6 is recorded there: with no artifact population, a stateful guard is a
filter with no measured problem, which is the `fixtures/domain-transfer-signal` lesson exactly.

**One instrument note.** The first run reported 16 refutations, 6 of them unattributable — one per
corpus. The survey prints a per-corpus tally line (`1 measured-defaultFails`) alongside its
bracketed entry rows, and the matcher counted it. The census's own "unrecognised must be zero"
assertion caught it. Had that assertion been written as "unattributable and unrecognised are the
same bucket," the miscount would have been reported as a finding.

## 5. Re-running

Opt-in, because it re-surveys corpora that BATCH2 / BATCH4 / BATCH7 already build:

```sh
SWIFT_INFER_RUN_TRAP_CENSUS=1 swift test --filter TrapAttributionCensusMeasuredTests
```

Re-run it when a new interaction family ships, when a carrier kind without total methods is added
(that is the population this census could not reach), or before revisiting §3.6. Per §10.3 of the
findings, compare two runs from the **same day** over the same corpora — not this table against a
fresh run months later.

The standing guard is separate and cheap: `InteractionTrapAttributionTests.everyFamilyMarksItsCheck`
is parameterised over `InteractionInvariantFamily.allCases` and fails if a family emits an unmarked
check, which would silently reclassify its refutations as artifacts.
