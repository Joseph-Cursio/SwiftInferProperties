# Calibration cycle 125 — Phase B SHIPPED (relaxed partial-exploration)

> **STATUS: SHIPPED (v1.127.0).** Implements the cycle-124 greenlight:
> `verify-interaction` now verifies a constructible idempotence witness for
> a `.tca` reducer over the *constructible-action subset* (payload-free +
> single-raw-payload cases), skipping non-derivable composition cases and
> disclosing them. Spike-first (the mixed-Action generator was proven by
> hand), then wired across discovery + emitter + pipeline with a mixed
> measured proof. Suite green (3204). Captured 2026-06-15.

## What shipped

The relaxed framing from cycle 123, ratified cycle 124, is now live:

- **Discovery (Core).** `ActionCaseInfo { name, payloadTypes }` replaces
  Phase A's payload-free-or-bail `actionCaseNames` on `ReducerCandidate`.
  The TCA walk captures **every** Action case with its associated-value
  payload types — no bail on payload cases.
- **Emitter (CLI).** Per-case constructibility: payload-free, or a single
  associated value of a recognized raw type (`RawType` via
  `DerivationStrategist`, PRD §11) → *constructible*; composition /
  multi-value / non-raw → *excluded*. The generator is `Gen.oneOf` over the
  constructible subset — `Gen.always(.case)` for payload-free,
  `<rawGen>.map(Action.case)` for raw — skipping the rest. `validate`
  rejects only when **no** case is constructible.
- **Pipeline (CLI), guardrail #1.** `foldPartialExplorationDisclosure`
  appends `partial exploration: explored M of N action types (excluded: …)`
  to the verdict `detail` for any `.tca` verify with excluded cases, so the
  partial basis rides into the evidence record + render. No-op when nothing
  is excluded (full exploration — e.g. an all-payload-free Action, the Phase
  A case, which renders exactly as before).

## Spike first (the de-risking that paid off in Phase A, repeated)

Before wiring, a throwaway hand-built verifier drove a mixed-Action
`Counter` (free witness + `setCount(Int)` raw + `received(Data)`
non-derivable) to `measured-bothPass`, confirming the crux unknown — that
`Gen.oneOf(Gen.always(.free), Gen.always(.free), Gen<Int>.int().map(.raw))`
composes as emitted code (heterogeneous shrink types via PropertyBased's
parameter-pack `oneOf`), and that the non-derivable case is cleanly omitted
while the reducer still compiles. No new blockers surfaced (Phase A had
already cleared Testing.framework / `@main` / visibility).

## Promotion semantics (as ratified, cycle 124)

A partial-exploration `measured-bothPass` is a single `measuredBothPass`
outcome (no new evidence case); the excluded set rides in `detail`. It
promotes idempotence `.likely → .verified` through the unchanged
scoring/promotion path — the disclosure makes the partial basis visible to
a reviewer. A later full-action-space verification supersedes the partial
record for the same identity.

## Verification

- **Fast.** `ReducerDiscovererTCATests` (payload types captured in order; no
  bail on payload cases). `ActionSequenceStubEmitterTCATests` (the `Gen.oneOf`
  shape; mixed Action generates raw + skips composition; classifier helpers
  agree on constructible/excluded). Existing emitter/candidate suites
  updated for the `actionCases` model.
- **Measured (`.subprocess`, `TCACarrierMeasuredTests`).** The Phase-A
  all-free capstone still `bothPass` (now via `Gen.oneOf`); **+1 Phase B**:
  a mixed Action verifies the witness `bothPass` and discloses
  `explored 2 of 3 action types (excluded: received)` in both the result and
  the persisted evidence.
- Fast suite green (3204); `swiftlint` clean on touched files.

## What's next

The `.tca` epic: **Phase A + Phase B shipped.** **Phase C** (corpus-scale
survey over real tca-10/tca-25) is the remaining piece — it needs
per-reducer source slicing for direct source inclusion (co-compiling ~100
unrelated corpus files into one verifier target won't work) plus a real
witness-detector pass instead of the hand-built invariants the measured
tests use. With Phase B's relaxed reach (~73/99 Action enums constructible),
Phase C is now where the measured-coverage delta on 50.5% would actually be
realized — and is the natural next scope. Lower-value optional: the shared
prebuilt user-package artifact (cycle 120 perf tail).
