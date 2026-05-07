# v1.4 Calibration Cycle 1 — Runbook

V1.4.2 needs human-in-the-loop triage. This runbook lists the exact commands per corpus, the target picks, and the up-front observations that already inform V1.4.3 tuning hypotheses (some findings are visible in the raw discover output without requiring any triage).

## Setup

The 3 Apple corpora are cloned to `~/calibration/`. SwiftPropertyLaws is already a sibling at `~/xcode_projects/SwiftPropertyLaws`. The release-build `swift-infer` binary lives at `~/xcode_projects/SwiftInferProperties/.build/release/swift-infer`.

```sh
# (already done by V1.4.2 setup)
mkdir -p ~/calibration
cd ~/calibration
git clone --depth 1 https://github.com/apple/swift-collections.git
git clone --depth 1 https://github.com/apple/swift-numerics.git
git clone --depth 1 https://github.com/apple/swift-algorithms.git

cd ~/xcode_projects/SwiftInferProperties
swift build -c release
```

## Up-front observations (before any triage)

The surfaced discover output for all 4 corpora is captured in `docs/calibration-cycle-1-data/*.discover.txt`. Aggregate stats (across all 4 corpora, `--include-possible`):

| Template          | Total | Default-tier visible | Possible-tier (hidden) | Score |
|-------------------|------:|---------------------:|-----------------------:|------:|
| round-trip        |   990 |                    0 |                    990 |    30 |
| idempotence       |    89 |                    0 |                     89 |    30 |
| monotonicity      |    29 |                    0 |                     29 | 25/35 |
| commutativity     |    19 |                    0 |                     19 |    30 |
| associativity     |    19 |                    0 |                     19 |    30 |
| inverse-pair      |    15 |                    0 |                     15 |    25 |
| identity-element  |     6 |                    6 |                      0 |    70 |
| **Total**         | **1167** |             **6** |              **1161** |       |

**Pre-triage findings:**

1. **Default-tier output is sparse on test-free corpora.** Only 6 of 1167 surfaced suggestions reach the default visibility threshold (≥ 40 score / Likely). All 6 are `identity-element` on `swift-numerics/ComplexModule` — surfacing because the curated-identity-constant signal (+40) bumps signature-matching templates above the Likely threshold. Without that signal, all other templates stay at Score 30 (Possible — hidden by default).
2. **Round-trip is 85% of the Possible-tier surface (990/1167).** The signature-only `(T) -> U` × `(U) -> T` pair-matching catches every inverse-shaped function pair regardless of actual semantic relationship. Real-world examples include any pair like `Array.init(_:)` × `Array.elements` or various encoder/decoder pairs that aren't actually round-trips. Without test-body cross-validation (TestLifter M5) these stay at Score 30 forever — by PRD §4.2 design, hidden by default.
3. **Score distribution is highly compressed.** Most templates produce a single score value with no variance: round-trip = 30, idempotence = 30, commutativity = 30, associativity = 30, monotonicity = 25 (with 1 outlier at 35), inverse-pair = 25, identity-element = 70. The PRD §4.1 +20 cross-validation signal is the design's primary "escape from Possible" mechanism — but real corpora often don't have matching XCTest bodies for swift-infer's TestLifter to lift.

These findings are the V1.4.3 tuning input even before any human triage; user-visible behavior on these corpora is exactly the 6 default-tier identity-element suggestions on ComplexModule.

## Triage instructions

The cycle-1 plan calls for at-minimum triaging the **default-tier** suggestions (6 visible across the 4 corpora). Optional widening: sample some Possible-tier suggestions (most informative would be sampling round-trip's 990 Possible-tier hits to confirm the "signature-only false-positive flood" hypothesis).

### Minimum-scope: triage default-tier only (~6 decisions, ~5 min)

Just one corpus has visible suggestions:

```sh
cd ~/calibration/swift-numerics
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target ComplexModule --interactive
```

The `--interactive` prompt walks each surfaced suggestion. Press one key per suggestion:

- `A` — accept (the suggestion is a real algebraic property worth running)
- `n` — reject (the suggestion is a false positive)
- `s` — skip (decide later — the suggestion will re-surface in future runs)
- `?` — show help (legend re-prompted)

Decisions persist to `~/calibration/swift-numerics/.swiftinfer/decisions.json`. After the first run, copy that file into the calibration data dir for committing:

```sh
cp ~/calibration/swift-numerics/.swiftinfer/decisions.json \
   ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-1-data/swift-numerics-ComplexModule.decisions.json
```

The remaining three corpora (swift-collections / swift-algorithms / SwiftPropertyLaws) have zero default-tier suggestions, so no triage is needed for cycle-1 minimum-scope.

### Optional widening: sample Possible-tier (~30–50 decisions, ~30–60 min)

To produce per-template metrics with statistical weight, sample some Possible-tier suggestions. Most useful sample shape:

- 10 round-trip Possible from `swift-algorithms/Algorithms` (highest-volume — 673 candidates available; sample alphabetically by callee name)
- 10 idempotence Possible from `swift-collections/OrderedCollections` (27 candidates)
- 5 commutativity + 5 associativity Possible from `swift-numerics/ComplexModule` (8 + 8 candidates)
- 5 monotonicity Possible from `swift-collections/OrderedCollections` (20 candidates)

Run discover with `--include-possible`:

```sh
cd ~/calibration/swift-algorithms
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target Algorithms --interactive --include-possible
```

The triage prompt walks every surfaced suggestion (728 on Algorithms!) — just press `s` (skip) to fast-forward through the ones you don't want to triage. The first 10 alphabetically you can A/n on; the rest skip.

**Important:** Triaged decisions on `--include-possible` runs persist in the same `.swiftinfer/decisions.json` as default-tier runs. Skipping doesn't pollute the calibration data — `s` is a deliberate "decide later" signal that the metrics command counts as the suppression rate.

After widening, copy each repo's decisions file:

```sh
cp ~/calibration/swift-algorithms/.swiftinfer/decisions.json \
   ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-1-data/swift-algorithms-Algorithms.decisions.json
cp ~/calibration/swift-collections/.swiftinfer/decisions.json \
   ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-1-data/swift-collections-OrderedCollections.decisions.json
cp ~/calibration/SwiftPropertyLaws/.swiftinfer/decisions.json \
   ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-1-data/SwiftPropertyLaws-PropertyLawKit.decisions.json 2>/dev/null || true
```

(Last command is `|| true` because SwiftPropertyLaws may have nothing to triage if you skip it.)

## After triage: handoff to V1.4.3

Once decisions files are copied to `docs/calibration-cycle-1-data/`, run `swift-infer metrics` to verify the data:

```sh
cd ~/xcode_projects/SwiftInferProperties
.build/release/swift-infer metrics \
    --decisions docs/calibration-cycle-1-data/swift-numerics-ComplexModule.decisions.json \
    --decisions docs/calibration-cycle-1-data/swift-algorithms-Algorithms.decisions.json \
    --decisions docs/calibration-cycle-1-data/swift-collections-OrderedCollections.decisions.json \
    --decisions docs/calibration-cycle-1-data/SwiftPropertyLaws-PropertyLawKit.decisions.json
```

The output table shows per-template acceptance / rejection / suppression rates. V1.4.3 reads this output + the surfaced discover output above to propose signal-weight tunings.

## Target picks (rationale)

- **swift-collections/OrderedCollections** — algebra-rich (set-like operations: union/intersection/symmetric-difference; predictable monoid candidate). Picked over `BitCollections` (similar shape, smaller surface) and `DequeModule` (already in the §13 perf row 1c — over-tested if we use it again here).
- **swift-numerics/ComplexModule** — Complex number arithmetic = textbook commutative ring; the only corpus that produces default-tier suggestions in cycle 1. Picked over `RealModule` (transcendental functions are less algebraic) and `IntegerUtilities` (utility functions, not type-method-heavy).
- **swift-algorithms/Algorithms** — combinatorics + folds (chunked, windows, joined, product) = high round-trip / idempotence candidate volume. The whole repo is one target so no choice needed.
- **SwiftPropertyLaws/PropertyLawKit** — sibling kit; Joseph's own algebraic-property-test library. Dogfooding: the library that defines `Monoid` / `Group` / `Semilattice` should be a calibration target.
