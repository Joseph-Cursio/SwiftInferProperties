# Calibration cycle 111 — interaction verify-evidence persistence (producer)

> **STATUS: SHIPPED (v1.118.0).** First half of the deferred "M9" join:
> the interaction verify path now **persists** each measured outcome to
> `.swiftinfer/verify-evidence.json`, keyed by the invariant's identity —
> the same store + join key the algebraic path uses. The discover-side
> *consumer* (the score-fold that lifts idempotence `.likely → .strong`)
> is deliberately deferred to cycle 112. Captured 2026-06-14.

## Context

Cycle 110 fixed Blocker B — interaction measured execution now runs
end-to-end from the CLI (`measured-bothPass`, 1024/1024). That reopened
the A1 `.likely → .strong` campaign, gated on two remaining items
(cycle-110 findings, "What's next"):

1. **Interaction verify-evidence persistence** — `VerifyInteractionPipeline`
   did not call `VerifyEvidenceRecorder`, so measured outcomes never
   reached `verify-evidence.json` and could not feed tier promotion.
2. **CLI corpus packaging** — standalone module-named packages for the
   HandRolled + TCA corpora so `verify-interaction` can run at corpus scale.

This cycle ships the **producer** half of item 1. Scope was deliberately
narrowed to producer-only ("producer first, durable proof") to keep the
one-mechanism-per-cycle rhythm; the consumer join is cycle 112.

## Key finding — the identity scheme already aligns; this is plumbing, not design

`InteractionInvariantSuggestion.identity` is the **same** `SuggestionIdentity`
(SHA256 of `"family::reducerQualifiedName::predicate"`, 16-char uppercase
hex) that the algebraic join keys on. The verify path reconstructs the
identical canonical input, so the persisted key matches what
`discover-interaction` will look up via `suggestion.identity.normalized`
**by construction** — no new identity scheme was needed. Two further
alignments made the producer a near-mechanical mirror of the algebraic
`VerifyCommand.runPipeline` recording:

- `InteractionVerifyOutcomeParser.Result.outcome` is **already** a
  `VerifyEvidenceOutcome` — no `VerifyOutcome → VerifyEvidenceOutcome`
  mapping (the algebraic side has to map; the interaction side does not).
- Both write the **same** `.swiftinfer/verify-evidence.json` via the same
  `VerifyEvidenceRecorder` / `VerifyEvidenceStore`, so the future
  consumer reads one unified store.

## What shipped

**`VerifyInteractionPipeline.recordEvidence(invariant:result:workingDirectory:)`**
— `runWithInvariant` now, after parsing the outcome, upserts a
`VerifyEvidence` keyed by `invariant.identity.normalized`
(`template = family.rawValue`, `outcome = result.outcome`,
`detail = result.detail`). Best-effort, identical posture to the algebraic
recorder: a persistence failure warns on stderr but never fails the verify
gesture.

**Why only the invariant-bearing entry records (documented in-code).**
The bare CLI `runPipeline(target:pinRaw:…)` carries no invariant — no
family, no predicate — and therefore **no identity hash to key on**
(`workdirSegment(for:)` still falls back to a name-based segment for the
same reason). So recording lives in `runWithInvariant`, the entry that
`accept-check-interaction` and the (cycle-112) corpus survey drive. This is
not a limitation for the A1 campaign: the 39 idempotence identities come
*with* invariants from `discover-interaction`.

## Verification

- **Durable proof:** `InteractionVerifyEvidenceTests`
  (`SwiftInferCLITests`, 3 tests) drives the recording leg in isolation
  (no subprocess build): `measuredBothPass`, `measuredDefaultFails`, and a
  re-run upsert all land on disk under `invariant.identity.normalized`
  with the right outcome / template / detail. The first test pins the
  crux — the persisted key equals exactly the consumer's lookup key, so
  the two halves cannot drift silently.
- **Directly-affected suites:** `AcceptCheckInteractionCommandTests`,
  `VerifyInteractionPipelineTests` — pass. The new write side-effect on
  `runWithInvariant` breaks none of them.
- **Suites:** full fast suite green (3167 tests; the only failures were
  the two known §13 perf-budget timing flakes, which pass in isolation —
  unrelated to this interaction-path change). SwiftLint clean.

## What's next — A1 campaign (consumer join, then corpus)

The producer writes evidence; nothing reads it yet. Cycle 112+:

1. **Consumer join (the immediate next).** A `VerifyEvidenceScoring`
   analogue for `InteractionInvariantSuggestion` in `discover-interaction`:
   load `verify-evidence.json`, look up `suggestion.identity.normalized`,
   fold the `+verifyBothPassWeight` so a `.measuredBothPass` lifts
   idempotence (score 40, `.likely`) into the `.strong` band. **Must
   respect the Finding-G gate** — `swiftProjectLintDeferral != nil`
   (cardinality / biconditional) stays pinned at `.possible` regardless of
   evidence. Note `Tier.promoted(byVerifyOutcome:)` only does
   `.strong → .verified`; the `.likely → .strong` lift is the score-fold's
   job, so the gate must be consulted on that path.
2. **CLI corpus packaging** (carried over from cycle 110, item 2) —
   module-named standalone packages for the HandRolled + TCA corpora so a
   measured survey can run over the 39 idempotence identities.

Then: run measured verify over the idempotence corpus, harvest evidence,
and gate `.strong` on execution. **Idempotence stays `.likely`
(v1.118.0)** until that lands.
