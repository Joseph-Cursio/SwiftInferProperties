# v1.88 Calibration Cycle 85 — Findings (accept-check follow-up: decisions + rerun)

Captured: 2026-05-15. swift-infer at v1.88.

## Headline

**First post-§5.8 follow-up ships — accept-check-shaped flow for
interaction invariants.** Analog of v1.72's accept-check (PRD §17.2
5th metric) but keyed on `InteractionInvariantSuggestion`. Three
sub-pieces in one push, where v1 took three calibration cycles:

- **A.A — decisions surface.** Persisted to
  `.swiftinfer/interaction-decisions.json`.
- **A.B — drift filter integration + recorder.** M10's deferred
  decisions filter now lands; new `accept-interaction` subcommand
  records decisions.
- **A.C — accept-check rerun.** New `accept-check-interaction`
  subcommand classifies into stillPasses / nowFails / obsolete /
  error; persists to
  `.swiftinfer/interaction-post-acceptance-outcomes.json`.

**Test count 2952 → 2972 (+20).** No §13 budget regression.

After v1.88, two follow-up sub-cycles remain queued for v2.0:
the kit's `checkInteractionInvariantPropertyLaws` harness + macro
discovery, and the N-arm interactive triage prompt for M9's peer
proposals.

## Why one cycle vs v1.72's three

v1.72 staged its work as V1.72.A (subcommand surface) → V1.72.B
(persistence) → V1.72.C (metrics section in `swift-infer metrics`).
v2.0's analog ships in one because:

1. **Smaller data model.** v1's `DecisionRecord` carries a
   `signalWeights: [SignalSnapshot]` array for the calibration loop;
   interaction families have a single integer score, no per-signal
   breakdown.
2. **No metrics-section work this cycle.** The §17.2 5th-metric
   render in `swift-infer metrics` is v1.72.C-equivalent and remains
   queued — it's purely a render-time concern.
3. **The drift filter integration was already designed.** M10
   shipped with the decisions-filter parameter wired but always-nil
   in production; A.B just flips the switch.

## What landed

### A.A — Decisions surface

**Core types** (`Sources/SwiftInferCore/InteractionDecisions.swift`):

```swift
public enum InteractionDecision: String, ... {
    case accepted
    case acceptedAsConformance = "accepted-as-conformance"
    case rejected
    case skipped
}
public struct InteractionDecisionRecord: ... {
    public let identityHash: String
    public let family: InteractionInvariantFamily
    public let scoreAtDecision: Int
    public let tier: Tier
    public let reducerQualifiedName: String
    public let decision: InteractionDecision
    public let timestamp: Date
}
public struct InteractionDecisions: ... {
    public static let currentSchemaVersion = 1
    // ... upserting / record(for:) ...
}
```

**Loader** (`InteractionDecisionsLoader`): explicit-path override,
implicit walk-up to `Package.swift`, atomic write,
sortedKeys-prettyPrinted JSON, malformed-JSON warning. Same shape
as v1's `DecisionsLoader`; same shape as M10's
`InteractionBaselineLoader`.

### A.B — Drift filter + recorder

`InteractionDriftDetector.warnings` gains an optional
`decisions: InteractionDecisions?` parameter. nil preserves M10.0
behavior; non-nil filters out suggestions with any recorded decision
(any of the 4 states suppresses — same as v1's drift). M10 was
already structured to add this filter; the wiring took one line.

`DriftInteractionCommand.run` loads decisions via the new loader
and threads them in. Failure to load (malformed JSON) surfaces as a
diagnostic warning; drift continues with empty decisions.

`accept-interaction` is a thin recorder subcommand:
- `--target <name>` (same target shape as the rest of `*-interaction`)
- `--identity <hash>` (16-char uppercase hex — find via
  `discover-interaction`)
- `--decision <rawValue>` (one of the 4 enum cases)
- `--decisions <path>` (optional explicit-path override)

The recorder runs `DiscoverInteraction.collectSuggestions` to find
the matching suggestion (errors with `.unknownIdentity` if no match),
constructs an `InteractionDecisionRecord`, and upserts via the loader.
No interactive triage UI — that's a separate follow-up for the N-arm
peer-proposal prompt.

`AcceptInteractionRequest` bundles identity + decisionRaw + path,
file-scope to satisfy SwiftLint's `nesting` + `function_parameter_count`
caps.

### A.C — Accept-check rerun

`InteractionPostAcceptanceOutcomeKind` mirrors v1's four-state
classification:
- `stillPasses` — re-verify returned `.measuredBothPass` /
  `.measuredEdgeCaseAdvisory`
- `nowFails` — re-verify returned `.measuredDefaultFails` (the
  regression signal this metric is after)
- `obsolete` — identity hash no longer surfaces in current
  `discover-interaction` output (reducer renamed / removed /
  family-witness shape evolved)
- `error` — re-verify returned `.measuredError` /
  `.architecturalCoveragePending`, or the pipeline threw

`InteractionPostAcceptanceOutcome` carries identity + family +
outcome + detail + `originalAcceptedAt` (from the source decision) +
`checkedAt` (this rerun's timestamp) + `swiftInferVersion` (for
staleness detection at render time).
`InteractionPostAcceptanceOutcomeLog` wraps the records with schema
version + upsert semantics. Persisted via
`InteractionPostAcceptanceOutcomesStore` (same loader shape).

`accept-check-interaction` subcommand:
- `--target <name>`
- `--family <name>` (optional — restricts the rerun to one family
  at a time, useful for cycling through families during calibration)
- `--decisions <path>` (optional explicit-path override)

Loop: load decisions → filter to `.accepted` +
`.acceptedAsConformance` (skipped/rejected don't need re-checking)
→ for each, call
`VerifyInteractionPipeline.runWithInvariant(target:invariant:...)` →
classify → upsert into outcomes log → render summary line. Persist
log at end.

### Verify pipeline extension

`VerifyInteractionPipeline.resolveAndEmit` gains an optional
`invariant: InteractionInvariantSuggestion? = nil` parameter,
threaded into `ActionSequenceStubEmitter.Inputs.invariant`. When
supplied, the M4.D family-aware predicate embedding fires inside
the stub — so the verify run actually checks the invariant, not
just "did the reducer trap?"

New `runWithInvariant(target:invariant:...)` returns the parsed
`InteractionVerifyOutcomeParser.Result` directly. Used by
`accept-check-interaction` so classification operates on structured
data, not parsed rendered text.

`runWithInvariant` differs from `runPipeline`: it doesn't persist
traces, doesn't run the shrinker (those happen at suggestion-
discovery time, not at re-check time — re-runs against the same
invariant produce the same trace/shrink so persisting is redundant).

## Test count breakdown

**2952 → 2972 (+20):**

- **Decisions data model (6):** rawValue stability, record lookup,
  upsert replace + append, JSON round-trip, schema version.
- **Drift decisions filter (4):** nil preserves M10.0, accepted
  suppresses, all 4 decision classes suppress, undecided still
  warns.
- **Accept-check classification (5):** measuredBothPass →
  stillPasses, defaultFails → nowFails, measuredError → error,
  architecturalCoveragePending → error, no-match → obsolete.
- **Accept-interaction recorder (3):** unknown decision rejected,
  unknown identity rejected, valid decision persisted to JSON.
- **Accept-check orchestration (2):** no accepted decisions fast
  path, unknown family rejected.

§13 budgets unchanged — no scan-perf surface touched.

## What's still queued

After v1.88 the v2.0 follow-up list has shrunk:

1. **Kit-side `checkInteractionInvariantPropertyLaws` harness** +
   PropertyLawMacro discovery integration. SwiftPropertyLaws v2.4.0
   would auto-run M9's conformance stubs on every CI invocation via
   the same path Semigroup/Monoid/Group take. Cross-repo cycle.
2. **N-arm extended triage prompt for M9's peer proposals** (PRD
   §9.4 — `[A/B/B'/B''/.../s/n/?]`). The interactive UI layer that
   records decisions via the v1.88 surface. v1's
   `--interactive` triage path is the template; v2.0 needs the
   N-arm extension because peer proposals can fire on multiple
   families simultaneously.
3. **`swift-infer discover-interaction --update-baseline`** —
   symmetric write side for M10's baseline read. Trivial; mostly
   plumbing.
4. **§17.2 5th-metric render in `swift-infer metrics`** for
   interaction invariants (v1.72.C analog). Joins
   `interaction-post-acceptance-outcomes.json` with the existing
   metrics output.

## Artifacts

- v1.88 sources:
  - `Sources/SwiftInferCore/InteractionDecisions.swift`
  - `Sources/SwiftInferCore/InteractionPostAcceptanceOutcome.swift`
  - `Sources/SwiftInferCore/InteractionDrift.swift` (decisions
    filter wiring)
  - `Sources/SwiftInferCLI/InteractionDecisionsLoader.swift`
  - `Sources/SwiftInferCLI/InteractionPostAcceptanceOutcomesStore.swift`
  - `Sources/SwiftInferCLI/AcceptInteractionCommand.swift`
  - `Sources/SwiftInferCLI/AcceptCheckInteractionCommand.swift`
  - `Sources/SwiftInferCLI/DriftInteractionCommand.swift` (loader
    + filter wiring)
  - `Sources/SwiftInferCLI/VerifyInteractionPipeline.swift`
    (`runWithInvariant`)
- Prior cycle: `docs/calibration-cycle-84-findings.md` (M10 —
  drift mode).
- v2.0 PRD: `docs/SwiftInferProperties PRD v2.0.md`.
