# v1.87 Calibration Cycle 84 — Findings (V2.0.M10: drift-interaction)

Captured: 2026-05-15. swift-infer at v1.87.

## Headline

**V2.0.M10 ships — PRD §5.8's full milestone arc is complete.**

`swift-infer drift-interaction` is the v2.0 analog of v1's drift:
diff current interaction-invariant suggestions against a previously-
snapshotted `.swiftinfer/interaction-baseline.json` and warn non-
fatally on new Strong-tier candidates. PRD §16 #3 invariant honored
— exit code always 0; warnings stream to stderr keyed by `warning:
drift:` for CI dashboard grep.

**Test count 2928 → 2952 (+24).** No §13 budget regression.

After M10, **ten v2.0 milestones across eleven calibration cycles**
ship: reducer discovery → ActionSequenceFactory → in-process verify
→ lifted families → three new families (Cardinality / Refint /
Biconditional) → effect-bearing verify + trace persistence → Bridge
→ drift. The v2.0 surface is end-to-end usable.

## What M10 ships

### Core data model

- `InteractionBaselineEntry` — one snapshot row: identity hash,
  family, score, tier, reducer qualified name. Smaller than the
  full suggestion; just enough to identify + tier-match across runs.
- `InteractionBaseline` — top-level shape. Schema version 1.
  `contains(identityHash:)` for membership tests; `entry(for:)`
  for future score-tier-transition surfacing.

### Drift detector

`InteractionDriftDetector.warnings(currentSuggestions:baseline:)`:

```swift
return currentSuggestions.compactMap { suggestion in
    guard suggestion.tier == .strong || suggestion.tier == .verified else { return nil }
    guard !baseline.contains(identityHash: suggestion.identity.normalized) else { return nil }
    return InteractionDriftWarning(suggestion: suggestion)
}
```

Two filters:
1. **Strong-tier-only** (or Verified — the v1.65 promotion rule).
2. **Not in baseline.**

Order-preserving; the `discover-interaction` upstream already sorts
deterministically per PRD §16 #6, so drift inherits byte-stable
output.

### Rendered warning line

```
warning: drift: new Strong cardinality invariant 0xABCDEF1234567890 on
Inbox.body at Sources/MyApp/Inbox.swift:42 — predicate: (state.isShowingSheet ? 1 : 0) <= 1
```

Tests pin the format. CI dashboards grep for `warning: drift:`.

### CLI subcommand

`swift-infer drift-interaction` — new subcommand. Three flags:
- `--target <name>` (required) — same shape as
  `discover-interaction` / `verify-interaction`.
- `--baseline <path>` (optional) — explicit override; walks up to
  Package.swift when omitted.
- `--reducer <pin>` (optional) — same M1.C pin syntax as
  `discover-interaction`.

Exit code always 0 per PRD §16 #3. Output stream:
- `No drift detected.` when warnings is empty.
- `<N> drift warning(s) emitted.` otherwise; warnings stream to
  stderr.

### Architectural choice: separate subcommand vs flag

PRD §3.6 step 7 sketched `swift-infer drift --interaction`. v2.0
has settled on parallel subcommands (`discover-reducers`,
`discover-interaction`, `verify-interaction`); `drift-interaction`
continues that pattern. Pros: cleaner option-set per subcommand;
discoverability via `swift-infer --help`. Cons: PRD wording is
slightly off; future doc pass could update.

## What's deferred from M10

**Decisions filtering.** v1's drift skips suggestions the user has
already accept/skip/rejected (M6.1 `Decisions`). Interaction
invariants don't yet have a decisions surface — the `accept-check`-
shaped flow is queued as the M8/M9 follow-up. Once that lands,
drift here picks up the filter so user-handled candidates stop
firing warnings.

**Score-tier-transition surfacing.** v1's drift could warn on
"Likely → Strong promotion" transitions (recorded but not
surfaced as a separate warning class). M10 carries
`entry(for: identityHash)` on the baseline to enable this, but
doesn't yet emit promotion-class warnings.

**`--update-baseline` flag.** v1's `discover --update-baseline`
snapshots current Strong+ to baseline. M10 ships read; the
symmetric write side (`discover-interaction --update-baseline`)
is a follow-up. Until then, the user constructs the baseline
manually or via the loader's `write(_:to:)` API.

## The v2.0 milestone arc

| Milestone | Cycle | What shipped |
|---|---|---|
| M1.A — reducer discovery | 70 | `discover-reducers` subcommand; signature-scan path |
| M1.B — TCA conformance walk | 71 | `Reduce { state, action in ... }` extraction |
| M1.C — carrier kinds + pin | 72 | `.elmStyle` / `.generic` / `.tca` + `--reducer` flag |
| M2 — kit ActionSequenceFactory | 73 | Cross-repo; SwiftPropertyLaws v2.2.0 |
| M3 — in-process verify | 74-75 | `verify-interaction` + workdir + outcome parser |
| M4 — lifted families | 76 | Conservation + Idempotence (lifted from v1) |
| M5 — Cardinality | 77 | First new-family template |
| M6 — Referential Integrity | 78 | Identifiable-keyed collection invariant |
| M7 — Biconditional | 79 | Last new family for PRD §5 set |
| M8 — effect-bearing verify + trace | 80 | Effect-discard emit, trace persistence |
| M8.D — minimal-trace shrinking | 81-82 | Drop-suffix + drop-prefix binary search |
| M9 — InteractionInvariantBridge | 83 | Cross-repo; SwiftPropertyLaws v2.3.0 |
| **M10 — drift-interaction** | **84** | **(this cycle)** |

Eleven cycles to ship ten milestones. Two cross-repo cycles (M2 +
M9), each requiring a kit minor bump.

## What's still in flight at v2.0 ship

**Calibration is the bottleneck.** PRD §3.5 corollary keeps every
new family at default-`.possible` for three cycles of stable
acceptance. None of M5/M6/M7 have started their three-cycle clock
yet (the empirical loop needs OSS corpus runs). M9's Bridge fires
+ M10's drift warnings both gate on Strong tier, so they don't
show real signal in production until calibration promotes
families.

**Three follow-up sub-cycles queued.** Independent of calibration:
1. **`accept-check` for interaction invariants** — decisions
   surface, M9 follow-up. Once present, M10's drift gains a
   decisions filter and v1.72's PRD §17.2 5th metric (post-
   acceptance failure rate) extends to interaction invariants.
2. **Kit-side `checkInteractionInvariantPropertyLaws` harness** +
   PropertyLawMacro discovery integration. SwiftPropertyLaws
   v2.4.0 would auto-run M9's conformance stubs on every CI
   invocation via the same path Semigroup/Monoid/Group take.
3. **N-arm interactive triage prompt** for M9's peer proposals
   (PRD §9.4 — `[A/B/B'/B''/.../s/n/?]`). The UI layer for the
   data-model M9.B already ships.

**Plus the symmetric `--update-baseline` for M10.**

## Test count breakdown

**2928 → 2952 (+24):**

- **Detector + baseline-model (11):** tier filtering (Strong /
  Likely+Possible silent / Suppressed silent / Verified counts);
  baseline membership (present suppresses, mixed input partial,
  order preserved); rendered-line shape; baseline-model membership
  / lookup / JSON round-trip / schema version.
- **Loader (7):** implicit walk-up (existing file / missing
  silent); explicit override (reads supplied URL / missing warns);
  write atomicity + byte-stability; malformed JSON warns.
- **CLI orchestration (4):** empty package reports no-drift;
  Possible-tier suggestions stay silent; implicit missing baseline
  silent; explicit missing baseline diagnostic.

§13 budgets unchanged.

## Artifacts

- v1.87 sources:
  - `Sources/SwiftInferCore/InteractionBaseline.swift`
  - `Sources/SwiftInferCore/InteractionDrift.swift`
  - `Sources/SwiftInferCLI/InteractionBaselineLoader.swift`
  - `Sources/SwiftInferCLI/DriftInteractionCommand.swift`
  - `Sources/SwiftInferCLI/DiscoverInteractionCommand.swift`
    (`collectSuggestions` factor-out)
  - `Sources/SwiftInferCLI/SwiftInferCommand.swift` (subcommand
    registration)
- Prior cycle: `docs/calibration-cycle-83-findings.md` (M9 —
  InteractionInvariantBridge).
- v2.0 PRD: `docs/SwiftInferProperties PRD v2.0.md`.
