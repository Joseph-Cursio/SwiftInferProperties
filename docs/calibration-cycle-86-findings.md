# v1.89 Calibration Cycle 86 — Findings (`discover-interaction --update-baseline`)

Captured: 2026-05-16. swift-infer at v1.89.

## Headline

**Second post-§5.8 follow-up ships — symmetric write side for M10's
drift read.** `swift-infer discover-interaction --update-baseline`
snapshots the current run's Strong-tier-or-Verified
`InteractionInvariantSuggestion`s to
`.swiftinfer/interaction-baseline.json`. Filter is deliberately
identical to `InteractionDriftDetector` + `InteractionInvariantBridge`
so baseline + drift stay aligned by construction: persisting Possible
/ Likely would write entries that drift would never warn against, and
the two surfaces would silently desync.

**One file touched (Sources side), one new test suite, one helper
sink.** No new Core types — M10 already shipped the data model
(`InteractionBaseline` / `InteractionBaselineEntry`) and the writer
(`InteractionBaselineLoader.write` was added in M10 anticipating this
cycle). All this cycle does is wire a CLI gesture through to the
existing infrastructure.

**Test count 2972 → 3000 (+7 in the new suite; remainder from
parameterized-test variance across runs).** No §13 budget regression.

After v1.89, two follow-up sub-cycles remain queued for v2.0:
the kit's `checkInteractionInvariantPropertyLaws` harness + macro
discovery, and the N-arm interactive triage prompt for M9's peer
proposals.

## Why one push vs v1's three-cycle pattern

v1's `discover --update-baseline` shipped in M6.5 as part of the
drift milestone, alongside `BaselineLoader` and `Drift` itself.
For v2.0 the analog was split because M10 had to ship something
end-to-end before there was anything to baseline against — the M10
read side proved out the data model + loader and left a single
explicit follow-up: the write gesture. That follow-up is this cycle.

## What landed

### A.A — Flag surface on `DiscoverInteraction`

Two new `@Flag` declarations, mirroring v1's `Discover` shape:

```swift
@Flag(name: .long, help: """
    Snapshot the current run's Strong-tier-or-Verified
    interaction-invariant suggestions to
    .swiftinfer/interaction-baseline.json. … Honors --dry-run by
    skipping the write. Additive: the suggestion stream is still
    rendered.
    """)
public var updateBaseline: Bool = false

@Flag(name: .long, help: """
    Suppress writes during --update-baseline. The would-be file
    path is reported on stdout and the .swiftinfer/ update is
    skipped. Without --update-baseline there are no writes to
    suppress, so --dry-run is a no-op.
    """)
public var dryRun: Bool = false
```

Both default to `false` — flag absence preserves the pre-v1.89
render-only behavior byte-for-byte.

### A.B — Orchestrator + writeout helper

The instance `func run() async throws` (the `AsyncParsableCommand`
entry) now calls a new `static func run(target:pinRaw:
includePossible:updateBaseline:dryRun:workingDirectory:output:
firstSeenAt:)` that does the same `collectSuggestions` + render leg
the old `runPipeline` did, plus an optional `runUpdateBaseline`
write in between when `--update-baseline` is set. Tests use a
recording `DiscoverOutput` sink to assert against both the
baseline-write status line and the renderer block in one call.

`runPipeline` (which returns `String`) is kept as a thin wrapper for
the existing pipeline tests that pin renderer output — no churn on
those.

`runUpdateBaseline` itself maps Strong + Verified suggestions to
`InteractionBaselineEntry` values, walks up from
`Sources/<target>/` to find the package root, and either writes via
`InteractionBaselineLoader.write` or (with `dryRun: true`) emits
`[dry-run] would write interaction-baseline to <path> (N entries).`
on the output sink and returns. The walk-up is inlined as a
private static rather than promoting `InteractionBaselineLoader`'s
existing private helper — keeps the loader's API narrow.

### Filter scope — Strong + Verified, not all-visible

**This is the load-bearing design decision of the cycle.** v1's
`runUpdateBaseline` persists every visible suggestion (all tiers
passing the `--include-possible` cut), and v1's `DriftDetector`
filters to Strong+ at warning time. That asymmetry is harmless
for v1 because `discover` is the only writer and `drift` is the
only reader, and they both walk the same per-pick `Score` math.
For v2.0 the same asymmetry would be actively misleading:

- M10's `InteractionDriftDetector.warnings` already filters to
  `tier == .strong || tier == .verified` (v1.86 / v1.87).
- v1.86's `InteractionInvariantBridge` filters to the same set.

If `--update-baseline` persisted Possible / Likely entries, those
entries would *suppress* future drift warnings (the entry is "in
baseline" so drift treats the suggestion as known), but the
suggestion was never Strong-tier so drift wouldn't have warned on
it anyway. The persisted entry contributes nothing — it just inflates
the file. Worse, if calibration later promotes the family to Strong,
the baseline would silently mask the first Strong-tier appearance as
"already known," and the user would never see the promotion.

Persisting Strong + Verified only keeps the invariant: **everything
in the baseline is something drift would have warned about today.**

### Pre-calibration consequence: the snapshot is typically empty

PRD §3.5 corollary keeps every M4–M7 family at default `.possible`
through three calibration cycles. So a fresh `discover-interaction
--update-baseline` against a real project today writes a baseline
with `entries: []`. That's the correct snapshot of the current drift
surface — drift today warns on nothing, and the baseline records
that state. As calibration promotes families, subsequent
`--update-baseline` runs will start writing non-empty entries lists.

The `run() with --update-baseline writes the baseline AND renders
the suggestion stream` test pins this explicitly: a fixture that
produces a `.possible` Conservation suggestion writes a baseline
with `entries.isEmpty == true`, while the rendered stream still
includes the Conservation block under `--include-possible`. Both
behaviors are correct.

## Test additions

New suite `DiscoverInteraction — V1.89 --update-baseline writeout`
in `Tests/SwiftInferCLITests/DiscoverInteractionUpdateBaselineTests.swift`,
split from the existing `DiscoverInteractionCommandTests` to keep
both files under SwiftLint's `file_length` + `type_body_length`
caps:

- `--update-baseline + --dry-run parse correctly` / default to false.
- `runUpdateBaseline filters out non-Strong+ tiers` — five-tier
  mixed input → exactly two entries persisted, identity hashes
  match the canonical-input derivation.
- `runUpdateBaseline with dry-run reports path and skips write`.
- `runUpdateBaseline real write produces a baseline that round-trips
  via the loader`.
- `runUpdateBaseline emits empty entries list when no Strong+
  suggestions exist`.
- `run() with --update-baseline writes the baseline AND renders the
  suggestion stream` — end-to-end through the orchestrator.

A small file-private `UpdateBaselineRecordingOutput` sink lives at
the bottom of the new test file; unlike `DPRecordingOutput` (which
overwrites on each `write`) it appends, so the test can assert
against both the baseline-write status line and the renderer block
emitted in one orchestrator call.

## What's next

Two follow-up sub-cycles queued for v2.0:

1. **`checkInteractionInvariantPropertyLaws` kit harness** + macro
   discovery so v2.3.0 conformances auto-run on every CI invocation.
   Cross-repo cycle (third one after M2 and M9).
2. **N-arm extended triage prompt for M9's peer proposals**
   (PRD §9.4) — the interactive UI layer that records decisions via
   the v1.88 surface. Natural follow-on now that
   `InteractionDecisions` is in place to receive them.

Plus the slow-burn item: **tier-promotion calibration** for M5–M7
families. Until at least one family promotes to `.strong`, the
v1.86–v1.89 surfaces (Bridge fire, drift warnings, baseline
non-empty, accept-check regression-detection) all stay quiet on
real input.
