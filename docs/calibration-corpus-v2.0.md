# SwiftInferProperties v2.0 — Calibration Corpus

**Status: cycle-2 baseline measured (v1.92 / cycle 89).** This file
pins the v2.0 calibration corpus and records per-corpus discovery
counts at v1.92's M1 + M4–M7 detectors. Cycles 3+ report deltas
against these baseline numbers.

**v1.92 update — M1.A 4th-shape + scalar filter landed.** Cycle-87
findings #1 (two-scalar false positive) and #4 (M1.A blind to
`(inout S, A) -> Effect<A>`) both closed in v1.92. Reducer-
detection count jumped 29 → 42 (+13, +44.8%) — the 4th-shape
extension caught 13 pre-macro TCA reducers using
`reduce(into:action:) -> Effect<Action>` that were previously
invisible; the scalar filter dropped 1 hand-rolled false-positive
(`transform: (Int, Int) -> Int`). Interaction-suggestion count
moved 34 → 35 (+1) — most newly-detected TCA reducers use Action
case names outside the curated idempotent set, confirming cycle-87
finding #5. Cycle-2 raw outputs at
`docs/calibration-cycle-89-data/`.

**v1.91 update — cross-contamination fix.** Cycle-87 finding #2
(bare-`State` / bare-`Action`) closed via
`ReducerCandidate.stateQualifiedName` / `actionQualifiedName`
properties threaded through to witness detectors. Cycle-1 outputs
at `docs/calibration-cycle-88-data/`.

The v2.0 analog of v1's cycle-1 1167-baseline (the candidate-count
that the first calibration cycle starts from) is the per-corpus,
per-family discovery count this file records.

-----

## 1. Why a corpus, and why now

v2.0's success criteria (PRD §19) measure per-family acceptance rates
and measured-execution rates against a calibration corpus. v1
calibrated against four OSS Swift libraries (swift-collections /
swift-algorithms / swift-async-algorithms / Apollo iOS) — its corpus
*was* the verification surface.

v2.0's domain is reducer-shaped state systems, so the natural corpus
is a mix of:

- **TCA exemplars** (`swift-composable-architecture/Examples/`),
  pinned at two versions — current (`1.25.5`) and pre-macro (`1.0.0`)
  — so we can measure both modern-TCA detection (gap-driven) and
  pre-`@Reducer`-era detection (signal-driven).
- **Hand-rolled fixtures** (`Tests/Fixtures/v2.0-corpus/Sources/HandRolled/`),
  designed to exercise each of the five PRD §5 families at least
  once on cleanly-shaped State types.

The corpus is the **denominator** for §19 metrics. A per-family
acceptance rate of "≥ 70% on cycle 3" means nothing without a fixed
corpus to evaluate against.

-----

## 2. Corpus categories — by carrier kind

Reducer candidates are labeled with one of three carrier kinds
(`ReducerCarrierKind` — M1.B / M1.C):

| Carrier kind | What it captures | Detection path (PRD §6) |
|---|---|---|
| `.tca` | TCA `Reducer` conformer's `Reduce { state, action in ... }` closures | M1.B conformance walk, gated on `import ComposableArchitecture` |
| `.elmStyle` | Free `(S, A) -> S` functions — the Elm idiom (`func update(_:_:)`) | M1.A signature scan, free-function specialization at M1.C |
| `.generic` | Methods matching canonical shapes; free `(inout S, A) -> Void`; free `(S, A) -> (S, Effect<A>)` (pre-2022 TCA) | M1.A signature scan, default |

Per-carrier-kind counts are recorded per-corpus in §3 / §4 below.

-----

## 3. Hand-rolled corpus

**Location:** `Tests/Fixtures/v2.0-corpus/Sources/HandRolled/`
(7 fixture files, ~190 LOC total).

**Layout:**

| File | Family targeted | Carrier kind | Designed witnesses |
|---|---|---|---|
| `Hand01_Conservation.swift` | Conservation | `.generic` | 1 (itemCount × items) |
| `Hand02_Idempotence.swift` | Idempotence | `.generic` | 4 (refresh, clear, dismiss, setColor) |
| `Hand03_Cardinality.swift` | Cardinality | `.generic` | 1 (multi-flag bundle) |
| `Hand04_ReferentialIntegrity.swift` | Referential Integrity | `.generic` | 2 (selectedMessageID × {messages, drafts}) |
| `Hand05_Biconditional.swift` | Biconditional | `.generic` | 2 (isLoadingResults × {activeTask, cachedResult}) |
| `Hand06_ElmStyle.swift` | Idempotence + Cardinality | `.elmStyle` | 1 + 1 |
| `Hand07_Negative.swift` | none (negative) | `.generic` | 0 expected |

### 3.1 Measured discovery counts (v1.89)

```
cd Tests/Fixtures/v2.0-corpus
swift-infer discover-reducers --target HandRolled
swift-infer discover-interaction --target HandRolled --include-possible
```

**discover-reducers (post-v1.92 scalar filter):** 7 reducer-shaped
functions detected.

| Reducer | Signature shape | Carrier kind | Expected? |
|---|---|---|---|
| `CountedListReducer.reduce` | `state-action-returns-state` | `.generic` | ✓ |
| `SettingsReducer.reduce` | `state-action-returns-state` | `.generic` | ✓ |
| `PresentationReducer.reduce` | `state-action-returns-state` | `.generic` | ✓ |
| `MessageListReducer.reduce` | `state-action-returns-state` | `.generic` | ✓ |
| `FetchReducer.reduce` | `state-action-returns-state` | `.generic` | ✓ |
| `PlainReducer.update` | `state-action-returns-state` | `.generic` | ✓ (negative reducer) |
| `reduce` (CounterState/Action) | `state-action-returns-state` | `.elmStyle` | ✓ |
| ~~`transform` (Int, Int) → Int~~ | (filtered) | (filtered) | ~~false positive~~ |

**Cycle-87 finding #1 closed in v1.92.** The `transform: (Int, Int)
-> Int` false positive is now rejected by `ReducerDiscoverer`'s
scalar-type filter (curated set: Int / UInt variants, Bool, Double,
Float, String, Character — both `Swift.`-prefixed and bare). No
plausible reducer has both halves scalar.

**discover-interaction (post-v1.91 cross-contam fix):** 18
interaction-invariant suggestions.

| Family | Cycle-0 (pre-fix) | Cycle-1 (post-fix) | Designed per-fixture total |
|---|---|---|---|
| Idempotence | 49 | 9 | 9 (Hand02: 4, Hand03: 3, Hand04: 1, Hand06: 1) |
| Biconditional | 24 | 4 | 4 (Hand03: 2, Hand05: 2) |
| Referential Integrity | 12 | 2 | 2 (Hand04) |
| Cardinality | 7 | 2 | 2 (Hand03: 1, Hand06: 1) |
| Conservation | 6 | 1 | 1 (Hand01) |
| **Total** | **98** | **18** | **18** |

Post-fix counts match per-fixture design exactly. **81.6% reduction**
from the cycle-0 baseline reflects the cross-contamination overhead.

**Cycle-87 finding #2 — historical record.** Pre-v1.91, every
hand-rolled reducer declared its State as a nested `Reducer.State`
struct, so all six reducers exposed a type whose bare name was
`State`. The witness detectors (M4.B / M4.C / M5–M7) took a
`stateTypeName: "State"` from each `ReducerCandidate` and matched
*any* `State` in the corpus by bare-name suffix — not the
qualified path. Same problem for `Action` (idempotence detection).
Result: each of the 6 same-named-State reducers fired 16
witnesses (the union of every State's matchable fields), producing
16×6 = 96 suggestions + 2 elm-style = 98 total vs the designed
total of 18.

**v1.91 fix** added `ReducerCandidate.stateQualifiedName` and
`actionQualifiedName` computed properties that produce
`<enclosingType>.<typeName>` (or pass through M1.B's pre-qualified
names like `"LazyNavigation.State"` unchanged). The
`InteractionTemplateEngine` passes these qualified names to the
5 detectors, scoping the type-stack suffix match to the
candidate's own enclosing type. The dot-awareness is load-bearing
— M1.B's TCA closure walker pre-qualifies for downstream stub
emission, so naively prepending would produce
`"LazyNavigation.LazyNavigation.State"` and break detector lookup.

-----

## 4. TCA exemplar corpus

Two pinned versions because the v1.89 detectors have different
blind spots at each:

### 4.1 TCA 1.25.5 (current / `@Reducer`-macro era)

- **Repository**: `https://github.com/pointfreeco/swift-composable-architecture`
- **Commit**: `1eaa6fa2ee57ac42843283b9fd3457af408c858d` (tag `1.25.5`)
- **Examples surveyed**: CaseStudies (SwiftUI), UIKitCaseStudies, Search, SpeechRecognition, SyncUps, Todos, VoiceMemos.

**Setup** (network + hard-copy required — `FileManager.enumerator`
doesn't follow top-level symlinks):

```
cd /tmp && git clone --depth 1 --branch 1.25.5 \
    https://github.com/pointfreeco/swift-composable-architecture.git tca-corpus
mkdir -p tca-25-discovery/Sources
cp -R /tmp/tca-corpus/Examples/CaseStudies/SwiftUICaseStudies tca-25-discovery/Sources/CaseStudies
cp -R /tmp/tca-corpus/Examples/CaseStudies/UIKitCaseStudies tca-25-discovery/Sources/UIKitCaseStudies
# … same for Search / SpeechRecognition / SyncUps / Todos / VoiceMemos.
cd tca-25-discovery && for t in …; do swift-infer discover-reducers --target "$t"; done
```

**Measured discovery counts (v1.89):**

| Example target | Reducers detected | Interaction suggestions |
|---|---|---|
| CaseStudies (SwiftUI) | 0 | (skipped — no reducers) |
| UIKitCaseStudies | 0 | (skipped) |
| Search | 0 | (skipped) |
| SpeechRecognition | 0 | (skipped) |
| SyncUps | 0 | (skipped) |
| Todos | 0 | (skipped) |
| VoiceMemos | 0 | (skipped) |
| **Total** | **0** | **0** |

**Cycle-87 finding #3 — M1.B blind to `@Reducer` macro.** Modern
TCA uses the `@Reducer` macro attribute to attach `Reducer`
conformance; the source-level `: Reducer` inheritance clause that
v1.74's M1.B walker keys on is absent. Every example in 1.25.5
declares its reducer as `@Reducer struct Feature { … }` rather than
`struct Feature: Reducer { … }`. Result: 0 reducers detected across
~100 macro-attached `@Reducer` declarations in the seven examples.

This makes 1.25.5 a **gap-driven baseline** — the measurement says
the detector misses modern TCA entirely, and the follow-up is M1.D
@Reducer-macro recognition. Filing this as the highest-priority
M1 follow-up.

### 4.2 TCA 1.0.0 (pre-`@Reducer`-macro era)

- **Commit**: `195284b94b799b326729640453f547f08892293a` (tag `1.0.0`)
- **Examples surveyed**: SwiftUICaseStudies, UIKitCaseStudies, tvOSCaseStudies.
- **Other 1.0.0 examples** (SpeechRecognition, Standups, etc.) already
  used `@Reducer` macro and produce 0 detections — same gap as 1.25.5.

**Setup** (same as 4.1 but with `--branch 1.0.0`):

```
cd /tmp && git clone --depth 1 --branch 1.0.0 \
    https://github.com/pointfreeco/swift-composable-architecture.git tca-pre-macro
mkdir -p tca-10-discovery/Sources
cp -R /tmp/tca-pre-macro/Examples/CaseStudies/SwiftUICaseStudies tca-10-discovery/Sources/CaseStudies
cp -R /tmp/tca-pre-macro/Examples/CaseStudies/UIKitCaseStudies tca-10-discovery/Sources/UIKitCaseStudies
cp -R /tmp/tca-pre-macro/Examples/CaseStudies/tvOSCaseStudies tca-10-discovery/Sources/tvOSCaseStudies
cd tca-10-discovery && for t in CaseStudies UIKitCaseStudies tvOSCaseStudies; do
    swift-infer discover-reducers --target "$t"
done
```

**Measured discovery counts (post-v1.92 4th-shape extension):**

| Example target | Reducers (cycle-0 → cycle-2) | Interactions (cycle-0 → cycle-2) |
|---|---|---|
| SwiftUICaseStudies | 19 → **31** (+12) | 12 → **13** (+1) |
| UIKitCaseStudies | 2 → **3** (+1) | 4 → 4 |
| tvOSCaseStudies | 0 → **1** (+1) | 0 → 0 |
| **Total** | **21 → 35** (+14) | **16 → 17** (+1) |

**Cycle-87 finding #4 closed in v1.92.** `ReducerDiscoverer.matchReducer`
now recognizes the 4th canonical reducer shape `(inout S, A) ->
Effect<A>`. The case label `ReducerSignatureShape.inoutStateActionReturnsEffect`
existed since v1.83 (used by M1.B's closure walker for `Reduce {
state, action in ... }` blocks); v1.92 extends M1.A's signature
scan to assign the same shape to plain methods + free functions.
tvOSCaseStudies' `Focus.reduce(into:action:)` and 12 additional
SwiftUICaseStudies methods that were previously invisible now
surface. The interaction-suggestion delta is small (+1) because
most newly-detected reducers use Action case names outside the
curated idempotent set — cycle-87 finding #5 in action.

**Cycle-87 finding #5 — only idempotence fires on real TCA.** All
16 interaction suggestions across both example sets are
idempotence. Cardinality / referential integrity / biconditional
all fire 0 times on real TCA State types. Working hypotheses:

- TCA convention uses `@PresentationState alert: AlertState<Action>?`
  rather than two bare `Bool` flags, so M5 / M7's name patterns
  don't fire on the `@Presents` wrapper.
- TCA convention uses `IdentifiedArrayOf<X>` rather than `[X]`, so
  M6's `[T]` array-literal match misses.
- TCA's `Action` enum names skew toward `task` / `delegate(...)` /
  `binding(.set(…))` shapes; only direct `refresh` / `setX` /
  `selectX` match M4.C's curated lists.

These are real signals about how the v0.0 detectors compare to
real-world TCA naming. M4.C / M5 / M6 / M7 calibration cycles will
sharpen the patterns.

-----

## 5. Cycle-2 baseline summary (post-v1.92 fixes)

| Corpus | Reducers (c0 → c2) | Interactions (c0 → c2) | Per-family non-zero |
|---|---|---|---|
| Hand-rolled (`Tests/Fixtures/v2.0-corpus/`) | 8 → **7** | 98 → **18** | All 5 |
| TCA 1.25.5 (7 examples) | 0 → 0 | 0 → 0 | None |
| TCA 1.0.0 (3 examples) | 21 → **35** | 16 → **17** | Idempotence only |
| **Total** | **29 → 42** | **114 → 35** | 5 of 5 |

**v2.0 cycle-2 baseline = 35 interaction-invariant suggestions
across 42 reducers (7 hand-rolled + 35 TCA-pre-macro), all at
default Possible tier.**

Per-cycle deltas:
- **Cycle-0 → cycle-1** (v1.91 cross-contam fix): 114 → 34 suggestions
  (−80, −70.2%). All from hand-rolled corpus.
- **Cycle-1 → cycle-2** (v1.92 4th-shape + scalar filter): 34 → 35
  suggestions (+1) and 29 → 42 reducers (+13). 4th-shape extension
  catches 14 new TCA reducers (12 SwiftUI + 1 UIKit + 1 tvOS);
  scalar filter drops 1 hand-rolled false-positive (`transform`).
  Interaction-count delta is small because most newly-detected
  reducers use Action names outside M4.C's curated idempotent set.

Raw discovery outputs:
- `docs/calibration-cycle-87-data/` — cycle-0 (pre-v1.91, baseline)
- `docs/calibration-cycle-88-data/` — cycle-1 (post-v1.91)
- `docs/calibration-cycle-89-data/` — cycle-2 (post-v1.92)

-----

## 6. Follow-up work items remaining after cycle-2

Cycle-87 originally surfaced 5 findings. v1.91 closed #2 (bare-name
cross-contamination); v1.92 closed #1 (two-scalar false positive)
and #4 (M1.A 4th-shape). Two remain:

1. **M1.D: `@Reducer` macro recognition.** Without this, all
   modern TCA is invisible to v2.0. **Highest remaining priority**
   — TCA is the dominant Swift reducer ecosystem, and cycle-89
   measurement confirms TCA 1.25.5 still produces 0 detections
   across all 7 examples surveyed.
2. **Family-pattern calibration for real TCA conventions.** M4.C /
   M5 / M6 / M7 patterns should learn `@PresentationState` /
   `IdentifiedArrayOf` / TCA Action conventions. Cycle-89's +14
   reducer-detection delta on TCA 1.0.0 only translated to +1
   interaction-suggestion delta — confirming that Action name
   conventions are the dominant gap, not detection.

Item 1 is bug-fix-shaped; item 2 is the actual three-cycle
calibration loop the §19 metrics measure against.

**Closed findings**:
- **#1** (two-scalar false positive) — closed in v1.92.
- **#2** (bare-`State` / bare-`Action` cross-contamination) — closed in v1.91.
- **#4** (M1.A 4th-shape extension) — closed in v1.92.

-----

## 7. Open questions (revised after cycle-0)

1. **Corpus expansion.** The current corpus has 29 reducers across
   3 corpora. PRD §19 wants per-family acceptance rates with
   meaningful denominators — likely need 100+ reducers across more
   projects. Candidates for cycle 1+: SyncUps re-pinned at TCA 1.4.x
   (the last pre-macro `@Reducer`-free Standups), additional
   Elm-style Swift projects (research task), and dogfood
   `swift-infer` itself's `discover-interaction` pipeline against
   smaller real-world TCA codebases.
2. **TCA-only bias.** Currently the OSS corpus is 100% TCA. PRD §14
   risk: heuristics tune to TCA conventions and miss generic
   reducer patterns. At least one Elm-style and one non-TCA hand-
   rolled project should join the corpus before promotion cycles
   begin.
3. **Three-cycle promotion timeline.** Per PRD §3.5 corollary, each
   M4–M7 family needs three calibration cycles of stable acceptance
   rate before promotion. Cycle-0 establishes baseline; cycle 1
   would re-measure after fixing the bare-`State` cross-
   contamination bug (item #3 above) so the per-family denominators
   become meaningful.
