# v1.72 Calibration Cycle 69 — Findings (post-acceptance failure rate: PRD §17.2 reaches 5/5)

Captured: 2026-05-15. swift-infer at v1.72.

## Headline

**§17.2 is complete.** v1.72 ships PRD §17.2's 5th and final metric —
**post-acceptance failure rate** — closing the section that began with
V1.4.1's three rate metrics, gained time-to-adoption at v1.71 (4/5),
and now reaches 5/5 at v1.72.

Unlike v1.71, this is **not** a metrics-only cycle: post-acceptance
failure rate needed a new human gesture — `swift-infer accept-check` —
to populate it. The cycle-68 findings called out the missing piece as
a **trigger-design** open decision rather than a schema or engineering
one; cycle 69 picked the manual-gesture option (B in the cycle-68
framing) for first-shipped reasons explained below.

Cycle-66's **52/103 = 50.5% measured-execution** carries forward
unchanged — v1.72 touches no emitter, resolver, or carrier path.

## The trigger-design decision — manual gesture, not CI hook

Cycle 68 framed three options for who records "the accepted property
later failed": (A) a CI hook the consuming repo installs, (B) a manual
`swift-infer accept-check` gesture, (C) swift-infer running the tests
itself on a schedule.

v1.72 ships **(B)**. The reasoning:

- **Smallest implementation step.** Reuses the V1.42+ verify pipeline
  pointed at a different input set (accepted decisions instead of one
  hash prefix). One sub-cycle's worth of subcommand wiring + one for
  persistence + one for the metric.
- **Matches the project's opt-in posture.** Same as `verify`: a
  separate human gesture from `discover` / `drift` / `accept`. Nothing
  else in the pipeline changes.
- **Honest about selection bias.** The §17.2 section explicitly says
  "rate reflects only re-checked decisions" — there's no pretense of
  a population-wide regression number.
- **Reversible.** If the gesture produces enough signal, (A) becomes
  the natural follow-up — accept-check defines the file format and
  the four-state vocabulary; a CI hook would write the same file.
- **Trap avoided.** Shipping (A) first risks "nobody installs the
  hook, no signal accrues, the metric stays empty forever."

(C) — swift-infer auto-running the tests — was off-axis for a CLI
tool with no daemon. It does the same work as (B) without the human
gesture; the gesture is the alignment with PRD §3.5's conservative,
human-reviewed posture.

## The four-state classification — why coarser than verify's five

`PostAcceptanceOutcomeKind` (4 states) is deliberately coarser than
`VerifyEvidenceOutcome` (5 states) because the question is different.

| Verify (pre-acceptance) | Post-acceptance | Why |
|---|---|---|
| `measuredBothPass` | `stillPasses` | "property holds" |
| `measuredEdgeCaseAdvisory` | `stillPasses` | Also "property holds" — the advisory sub-state matters at verify time (user sees curated edge cases) but not post-acceptance |
| `measuredDefaultFails` | `nowFails` | Regression — the signal §17.2 is really after |
| `measuredError` | `error` | Couldn't measure |
| `architecturalCoveragePending` | `error` | Also couldn't measure |
| *(no analog)* | `obsolete` | Identity hash no longer surfaces in current source. Synthesized from `VerifyError.suggestionNotFound` — the verify pipeline never reaches this classification because it throws first. Informative, not a failure. |

The denominator semantics fall out of this: rate = `nowFails / (stillPasses
+ nowFails)`. `obsolete` and `error` are shown in counts but excluded —
the function evolving past the suggestion shape isn't "the property
failed," and "couldn't measure" isn't a verdict either way.

## What shipped — three sub-cycles

### V1.72.A — `AcceptCheck` subcommand skeleton

- New `Sources/SwiftInferCLI/AcceptCheckCommand.swift` + the
  `PostAcceptanceOutcomeKind` enum in Core.
- Registered as `AcceptCheck.self` in `SwiftInferCommand.swift`'s
  subcommands list, alongside `Verify` / `Metrics` / etc.
- Pipeline: load decisions → filter to accepted / acceptedAsConformance
  (optionally narrowed by `--template`) → call `Verify.runPipeline`
  per identity hash → classify the resulting `VerifyEvidenceOutcome`
  via `classify(evidence:)` → render summary.
- The verify-error → `obsolete` mapping is the new behavior: a verify
  `suggestionNotFound` (the identity hash doesn't surface in the
  current SemanticIndex) classifies as `.obsolete`. The function
  evolved past the suggestion shape — informative, not regression.

### V1.72.B — `post-acceptance-outcomes.json` persistence

- New `PostAcceptanceOutcome` value + `PostAcceptanceOutcomeLog` (with
  `upserting` / `merge`, mirroring `VerifyEvidenceLog`).
- New `PostAcceptanceOutcomesStore` — disk-resident
  load / write / walk-up loader, near-clone of `VerifyEvidenceStore`.
- AcceptCheck writes one upsert per re-checked record (matches
  `VerifyEvidenceRecorder.record(_:)`'s per-record posture, not the
  batch-at-end shape of survey mode) — a mid-run process death leaves
  prior verdicts on disk for the §17.2 join to consume.

### V1.72.C — Metrics §17.2 section: post-acceptance failure rate (5/5)

- New `MetricsRenderer+PostAcceptanceFailure.swift`:
  `postAcceptanceFailureRows(decisions:outcomes:)` + section render.
- `MetricsLoadResult` gains a `postAcceptanceOutcomes` field;
  `MetricsCommand` loads `post-acceptance-outcomes.json` in both
  default and `--decisions` modes (same opt-in-per-corpus shape as
  V1.70.A / V1.71.A).
- Section header surfaces two honest caveats: "selection bias applies"
  and (when present) "N `obsolete` records excluded from the rate
  denominator."
- Drive-by lint fix: `MetricsRenderer.swift`'s enum body had been
  creeping over the 250-line `type_body_length` cap (287 lines
  pre-cycle). Extracted `tierSection`, `verifyEvidenceSection`, and
  the new `postAcceptanceFailureSection` into `+Tier`, `+VerifyEvidence`,
  `+PostAcceptanceFailure` files, matching the V1.71 `+TimeToAdoption`
  posture. Each section in its own file; main enum back under 250.

## Why no `Decisions` schema-v3 bump

Same reasoning as v1.71's time-to-adoption: a parallel
`.swiftinfer/post-acceptance-outcomes.json` keyed by identity hash,
joined at `metrics` render time. `DecisionRecord` shape is untouched.

The cycle-68 framing called this out — "Storage is the easy part — a
parallel `post-acceptance-outcomes.json` keyed by identity hash,
joined at `metrics` render time, exactly mirroring `verify-evidence.json`
(V1.64.D) and the V1.70.A / V1.71.A join pattern. No `Decisions`
schema bump." That framing held.

## Test count

**2523 → 2572 (+49)**:

- **V1.72.A (+13).** `AcceptCheckCommandTests` — classifier across
  all five `VerifyEvidenceOutcome` states, accepted-records filter,
  summary render pluralization + per-record line + summary block.
- **V1.72.B (+21).** `PostAcceptanceOutcomeTests` (data model + upsert
  + merge + Codable round-trip, 7 tests), `PostAcceptanceOutcomesStoreTests`
  (explicit + walk-up + corrupt + newer-schema + atomic write, 7
  tests), `AcceptCheckCommandTests`'s persist round-trip block (7
  tests covering write, upsert, multi-identity preserve).
- **V1.72.C (+15).** `MetricsPostAcceptanceFailureTests` — join +
  rate computation across the four states, denominator-exclusion
  semantics, section sentinels (no outcomes / no joins), selection-bias
  caveat, obsolete-count caveat, n/a rate, table render.

§13 budgets unchanged — the renderer is pure, the gesture is opt-in.

## What's next (post-v1.72)

PRD §17.2 is at **5/5**. The documented roadmap is empty again (this
is the third consecutive "roadmap empty after this cycle" state —
v1.70 cleared it, v1.71 picked time-to-adoption from cycle 67's
candidate list, v1.72 picked post-acceptance failure rate from
cycle 68's candidate list). Remaining candidate directions, none
currently scoped:

1. **CI-hook variant of accept-check.** Option (A) from the cycle-68
   framing — a hook the consuming repo installs that writes
   `post-acceptance-outcomes.json` automatically on each CI run. The
   schema + identity-hash join + four-state vocabulary are already
   defined by v1.72; the work is the hook script + the hash-to-test
   marker convention in the emitted test file. Gated on whether the
   v1.72 manual gesture proves to produce useful signal in real use.
2. **Kit-side deferrals** — `Ring` / `CommutativeGroup` / `Group acting
   on T`, parked per `CLAUDE.md` "Kit-side coordination". Cross-repo;
   not driven by this codebase.
3. **Incremental index analysis** — `swift-infer index` rebuilds from
   a full discover each run; PRD §20.1 mentions incremental as a
   future optimization, deferred until profiling shows it's needed.

## Artifacts

- v1.72 sources:
  - `Sources/SwiftInferCore/PostAcceptanceOutcome.swift` (enum + value
    + log).
  - `Sources/SwiftInferCLI/AcceptCheckCommand.swift` (subcommand +
    `runPipeline` + classify + persist).
  - `Sources/SwiftInferCLI/PostAcceptanceOutcomesStore.swift` (disk
    loader/writer).
  - `Sources/SwiftInferCLI/MetricsRenderer+PostAcceptanceFailure.swift`
    (join + section).
  - `Sources/SwiftInferCLI/MetricsRenderer+Tier.swift` +
    `+VerifyEvidence.swift` (extractions to fix the
    type_body_length warning).
- Prior cycle: `docs/calibration-cycle-68-findings.md` (v1.71
  time-to-adoption — PRD §17.2 reached 4/5).
