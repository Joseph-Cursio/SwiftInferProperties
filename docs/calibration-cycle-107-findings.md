# Calibration cycle 107 — idempotence promotion implemented (`.possible → .likely`)

> **STATUS: SHIPPED (v1.115.0).** Implements the promotion proposed in
> `docs/calibration-cycle-106-findings.md` after idempotence held 100%
> acceptance across cycles 104 + 105 + 106. Idempotence is the **first
> interaction-invariant family to graduate past default-`.possible`**.
> Captured 2026-06-14.

## What changed

Two coordinated changes, exactly as the cycle-106 proposal specified:

1. **`IdempotenceInteractionTemplate.initialScore` 30 → 40.** 40 lands in
   the `.likely` band (40..<75 per `Tier(score:)`).
2. **`InteractionTemplateFamily.makeSuggestion` derives tier from score.**
   Was a hardcoded `tier: .possible` for every family; now
   `tier: tierFor(family:score:)` where

   ```
   tierFor(family, score) =
       family.swiftProjectLintDeferral == nil ? Tier(score: score) : .possible
   ```

   The `swiftProjectLintDeferral` clamp (shipped in the Finding-G work,
   `7f82052`) is what keeps **cardinality + biconditional pinned at
   `.possible`** now that the global path derives tier from score. This is
   the promotion gate that mapping was introduced to back — cycle 107 is
   where it earns its keep.

No other family moves: conservation + referential-integrity keep
`initialScore = 30` → `Tier(30) = .possible` (not gated, but score keeps
them down); cardinality + biconditional keep score 30 **and** the gate.

## Verified behavior

- **Idempotence surfaces by default.** `discover-interaction --target
  HandRolled` with **no** `--include-possible` now renders **9 idempotence
  suggestions at `Score: 40 (Likely)`** (previously the
  "0 shown — pass `--include-possible`" sentinel).
- **`.possible` families still hidden by default.** The 6 cardinality /
  biconditional / conservation / referential-integrity suggestions on
  HandRolled remain hidden without the flag; the sentinel still points to
  `--include-possible`.
- **Finding-G gate holds.** Cardinality + biconditional render
  `Score: 30 (Possible)` on the new score-derived path; their template
  tests still assert `.tier == .possible` and pass.
- **Full suite green:** 3157 tests / 419 suites (one graduation test
  added; the hide-by-default sentinel test repurposed onto a still-
  `.possible` cardinality fixture so it keeps exercising the hidden path).
  SwiftLint clean.

## Scope guard — what this promotion does *not* do

- **Does not unlock M9 Bridge proposals or M10 drift warnings.** Per PRD
  those gate on `.strong`, not `.likely`. A fresh three-cycle ≥ 70% run
  would propose `.likely → .strong` and unlock them.
- **Does not change the verify / measured-execution path.** Tier affects
  discover-presentation visibility only.
- **Does not move cardinality / biconditional / conservation /
  referential-integrity** — idempotence is the sole family with a
  substantive (n=39) three-cycle record.

## What's next

| Cycle | What lands |
|---|---|
| 107 | **This file** — idempotence promotion `.possible → .likely` shipped. |
| 108+ | Either (a) begin a fresh three-cycle `.likely → .strong` run for idempotence (unlocks M9/M10), or (b) broaden the corpus for the thin families (RefInt / Conservation, both n=1) so they carry a meaningful promotion signal. |
