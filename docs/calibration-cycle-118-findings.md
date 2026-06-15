# Calibration cycle 118 — A1 measured-promotion sign-off

> **STATUS: SIGN-OFF (no binary change — durable tests + record).** The A1
> campaign's thesis — promote idempotence `.likely → .verified` on *measured
> execution*, not re-triage — is empirically confirmed and locked with a
> determinism guarantee. The mechanism arc (cycles 110–117) is complete;
> this cycle records the result and guards its reproducibility. Captured
> 2026-06-14. **No version bump** (ships tests + documentation, not binary
> behavior — same posture as cycle 108).

## What the "three-cycle promotion run" actually requires

The PRD §3.5 corollary requires a family to hold for three calibration
cycles before promotion. That discipline exists to absorb **variance**: the
`.possible → .likely` promotion (cycles 104–106 → 107) re-ran human triage
over the corpus three times because triage outcomes and corpus selection
drift cycle to cycle, and a single cycle could over-fit.

The A1 `.likely → .verified` promotion is gated on a *different* signal —
machine-measured execution (cycle 112's verify-evidence consumer) — which
has **zero cycle-to-cycle variance**:

- **Deterministic seed.** `ActionSequenceStubEmitter.seedTuple(for:)`
  derives the verifier's Xoshiro256** seed from the reducer's
  `qualifiedName` via a byte-stable custom SipHasher — deliberately *not*
  Swift's per-process-randomized `Hasher`. Same reducer → same seed → same
  action sequences.
- **Pure reducers.** The verified property (`reduce(reduce(s,a),a) ==
  reduce(s,a)`) is a pure function of state; no clock, no RNG outside the
  seeded generator, no I/O.

So re-running the survey produces byte-identical evidence every time. A
single confirmed run is therefore equivalent to the three-cycle discipline —
there is no variance for additional cycles to reveal. This cycle makes that
equivalence explicit (and regression-guarded) rather than re-running an
identical deterministic survey three times for ceremony.

## The signed-off result

The measured survey over the widened verify-ready corpus (cycle 116,
`Tests/Fixtures/idempotence-survey-corpus/`, 5 reducers / 12 identities /
3 carrier shapes):

| Outcome | Count | Tier after `discover-interaction` |
|---|---|---|
| `measured-bothPass` | **11** | `.verified` |
| `measured-defaultFails` | **1** (`SettingsReducer.setBadge`) | suppressed |

Promotion is gated on execution end-to-end: 11 genuinely-idempotent
identities across the generic / TCA-convention / Elm-free-function carriers
promote to `.verified`; the deliberate `set*` false positive — which static
analysis cannot rule out — is disproven and dropped. Default (no-evidence)
idempotence remains `.likely`; promotion past it requires a measured
`.measuredBothPass` on disk.

## Verification (the durable guards)

- **Fast (`MeasuredPromotionDeterminismTests`, 2):** `seedTuple` is
  deterministic for a given reducer (same `qualifiedName` → identical seed,
  four well-formed hex words) and varies by reducer identity. Guards the
  root of reproducibility against an accidental swap to a randomized hasher.
- **Measured (`MeasuredPromotionDeterminismMeasuredTests`, `.subprocess`,
  ~19s):** verifying the same identity twice yields a byte-identical
  `Result` — end-to-end reproducibility of the measured outcome.
- **Standing baseline guard (`IdempotenceSurveyCorpusMeasuredTests`):** the
  full 11/1 split + `.verified` promotion is already a regression test and
  has held identically across cycles 115–117.
- **Suites:** full fast suite green (3196 tests; only the known §13 perf-
  budget timing flakes under load). SwiftLint clean.

## A1 status: mechanism arc complete

The campaign that began with "execute the 39 idempotence identities instead
of re-triaging them" now has every piece:

| Cycle | Piece |
|---|---|
| 110 | measured execution runs from the CLI (`measured-bothPass`) |
| 111 | verify-evidence **producer** (`recordEvidence`) |
| 112 | verify-evidence **consumer** (`.likely → .verified` fold, Finding-G-gated) |
| 113 | `CorpusPackager` (loose sources → standalone package) |
| 114 | `verify-interaction --all` survey |
| 115 | verify-ready corpus + first measured baseline |
| 116 | widened corpus (3 carrier shapes) |
| 117 | free-function pin disambiguation |
| 118 | **measured-promotion sign-off + determinism guarantee** |

## What's next — optional widening / accelerators

The core A1 result is signed off. Remaining items are all optional or
blocked on a separate capability, none on the critical path:

- **Value-generator path** for associated-value Action cases
  (`setColor(String)` et al.) — the prerequisite to widen toward the
  *literal* ~39 real-corpus identities. Until then such identities survey
  `architectural-coverage-pending` (surfaced, not dropped).
- **Per-invariant workdir isolation** — unlocks a *parallel* `--all` survey
  (today's is serial because the verify workdir is reducer-keyed).
- **`CorpusPackager` `dependencies:` thread** — to package the
  dependency-bearing TCA corpora.

Default (no-evidence) idempotence stays `.likely`; the other four
interaction families stay `.possible` behind `--include-possible`.
