# SwiftInferProperties v2.0 — Calibration Corpus

**Status: cycle-7 baseline measured (v1.97 / cycle 94).** This file
pins the v2.0 calibration corpus and records per-corpus discovery
counts at v1.97's M1 + M4–M7 detectors. **All five cycle-87
findings + four sub-items now closed.** Cycles 8+ are the
three-cycle calibration loop proper (PRD §3.5 corollary — three
cycles of stable per-family acceptance rate before tier promotion).

**v1.97 update — Biconditional inferred-Bool initializer recognition.**
Fourth and final family-pattern-calibration sub-cycle.
`BiconditionalWitnessDetector.classifyBinding` now accepts Bool
fields declared without `: Bool` annotation but with a `true` /
`false` literal initializer (modern TCA's `var isLoading = false`
idiom). **Biconditional fires on real TCA for the first time** —
TCA 1.25.5 +3 (CaseStudies 2 + UIKit 1), TCA 1.0.0 +3 (same
distribution). Cycle-7 corpus baseline: 92 reducers, 76
interactions (was 70 at cycle-6). Biconditional share moves from
5.7% → 13.2%. Cycle-7 raw outputs at
`docs/calibration-cycle-94-data/`.

**v1.96 update — Idempotence TCA action-name conventions.** Third
family-pattern-calibration sub-cycle. Adds `task` / `delegate` /
`binding` to `IdempotenceWitnessDetector.exactNames` — three
canonical TCA conventions every Action enum uses. **TCA 1.25.5:
23 → 31 interactions (+8 idempotence)** with first detections on
SyncUps (+2) and Todos (+1). TCA 1.0.0 also picks up +4 idempotence
plus a belated +1 cardinality from v1.94 that wasn't re-measured
at cycle-4. Total corpus delta: +13 interactions (largest
single-cycle unlock outside the M1.D macro cycle). Cycle-6 raw
outputs at `docs/calibration-cycle-93-data/`.

**v1.95 update — Referential Integrity `IdentifiedArrayOf<X>`
recognition.** Second family-pattern-calibration sub-cycle of
cycle-87 finding #5. `ReferentialIntegrityWitnessDetector` now
recognizes `IdentifiedArrayOf<T>` + two-arg
`IdentifiedArray<ID, T>` alongside array literal `[T]`. **TCA
1.25.5 interaction count: 23 → 23 (no delta).** Detector is
correct (verified by 8 new tests) — but TCA 1.25.5 has **zero
`selected*` properties** anywhere in its 7 example apps, so the
pairing rule (`selected<X>` × collection) doesn't fire. Another
modern-TCA-prefers-enum-X finding parallel to cycle-91's
enum-destination-over-multi-Presents. Cycle-5 raw outputs at
`docs/calibration-cycle-92-data/`.

**v1.94 update — Cardinality `@Presents` / `@PresentationState`
recognition.** First family-pattern-calibration sub-cycle of
cycle-87 finding #5. `CardinalityWitnessDetector` now treats any
Optional carrying `@Presents` or `@PresentationState` as a
presentation slot regardless of property name. TCA 1.25.5 cardinality
witnesses: 3 → 5 (CaseStudies 3 → 4, VoiceMemos 0 → 1 first
detection). Smaller unlock than expected — modern TCA prefers a
single `@Presents var destination: Destination.State?` with an
enum carrying variants over multiple `@Presents` Optionals, so
only the legacy multi-slot shape fires Cardinality. Cycle-4 raw
outputs at `docs/calibration-cycle-91-data/`.

**v1.93 update — M1.D `@Reducer` macro recognition landed.**
Cycle-87 finding #3 (M1.B blind to `@Reducer` macro — all modern
TCA invisible) closed in v1.93. New `hasReducerAttribute(_:)`
static helper checks each type-decl's `AttributeListSyntax` for
`@Reducer`; the existing `extractTCACandidatesIfReducerConformer`
fires on **either** inheritance-clause `: Reducer` (M1.B) or
`@Reducer` attribute (M1.D). The body-walk logic is shared and
idempotent, so a type with both forms emits one set of candidates.
**TCA 1.25.5 jumps from 0 → 50 reducers detected** across all 7
examples, with 21 interaction suggestions (18 idempotence + 3
cardinality — first non-idempotence family to fire on real TCA).
Cycle-3 raw outputs at `docs/calibration-cycle-90-data/`.

**v1.92 update — M1.A 4th-shape + scalar filter landed.** Cycle-87
findings #1 (two-scalar false positive) and #4 (M1.A blind to
`(inout S, A) -> Effect<A>`) both closed. Reducer count 29 → 42
(+13). Cycle-2 outputs at `docs/calibration-cycle-89-data/`.

**v1.91 update — cross-contamination fix.** Cycle-87 finding #2
(bare-`State` / bare-`Action`) closed via
`ReducerCandidate.stateQualifiedName` / `actionQualifiedName`.
Cycle-1 outputs at `docs/calibration-cycle-88-data/`.

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

### 4.1 TCA 1.25.5 (current / `@Reducer`-macro era) — unlocked at cycle-3

- **Repository**: `https://github.com/pointfreeco/swift-composable-architecture`
- **Commit**: `1eaa6fa2ee57ac42843283b9fd3457af408c858d` (tag `1.25.5`)
- **Examples surveyed**: CaseStudies (SwiftUI), UIKitCaseStudies, Search, SpeechRecognition, SyncUps, Todos, VoiceMemos.

**Setup** (network + hard-copy required — `FileManager.enumerator`
doesn't follow top-level symlinks):

> **Workdir location — do NOT use `/tmp`.** macOS purges `/tmp`
> entries older than ~3 days, which silently guts the `Sources` tree
> and makes `discover-interaction` return 0 with no error (this bit
> cycle 104 on 2026-06-13). Keep the discovery workdirs under the
> stable sibling dir `$HOME/xcode_projects/calibration-corpora/`. The
> throwaway upstream clone can still live in `/tmp`.

```
CORPORA="$HOME/xcode_projects/calibration-corpora"
cd /tmp && git clone --depth 1 --branch 1.25.5 \
    https://github.com/pointfreeco/swift-composable-architecture.git tca-corpus
mkdir -p "$CORPORA/tca-25-discovery/Sources"
cd "$CORPORA/tca-25-discovery"
cp -R /tmp/tca-corpus/Examples/CaseStudies/SwiftUICaseStudies Sources/CaseStudies
cp -R /tmp/tca-corpus/Examples/CaseStudies/UIKitCaseStudies   Sources/UIKitCaseStudies
cp -R /tmp/tca-corpus/Examples/SyncUps/SyncUps                Sources/SyncUps
cp -R /tmp/tca-corpus/Examples/Todos/Todos                    Sources/Todos
cp -R /tmp/tca-corpus/Examples/VoiceMemos/VoiceMemos          Sources/VoiceMemos
# (Search / SpeechRecognition surveyed but emit 0 interactions — omit from triage.)
for t in CaseStudies UIKitCaseStudies SyncUps Todos VoiceMemos; do
    swift-infer discover-reducers --target "$t"
done
```

**Measured discovery counts (post-v1.94 cardinality @Presents):**

| Example target | Reducers (cycle-0 → cycle-4) | Interactions (cycle-0 → cycle-4) |
|---|---|---|
| CaseStudies (SwiftUI) | 0 → **36** (+36) | 0 → **18** (14 idempotence + 4 cardinality) |
| UIKitCaseStudies | 0 → **3** (+3) | 0 → **4** (all idempotence) |
| Search | 0 → **1** (+1) | 0 → 0 |
| SpeechRecognition | 0 → **1** (+1) | 0 → 0 |
| SyncUps | 0 → **5** (+5) | 0 → 0 |
| Todos | 0 → **1** (+1) | 0 → 0 |
| VoiceMemos | 0 → **3** (+3) | 0 → **1** (1 cardinality, first detection) |
| **Total** | **0 → 50** (+50) | **0 → 23** (+23) |

**Cycle-87 finding #3 closed in v1.93.** New `hasReducerAttribute(_:)`
static helper in `ReducerDiscoverer` checks each type-decl's
`AttributeListSyntax` for `@Reducer`. The existing
`extractTCACandidatesIfReducerConformer` fires on **either**
inheritance-clause `: Reducer` (M1.B) or `@Reducer` attribute
(M1.D); the body-walk is shared and idempotent, so a type with
both forms emits one set of candidates. All 7 TCA 1.25.5 examples
now surface their reducers — 50 total across the corpus.

**First non-idempotence on real TCA** — 3 cardinality witnesses
in SwiftUICaseStudies (from State types with ≥ 2 Bool fields
matching `Showing` / `Presenting` patterns, or Optional fields
whose lowercased name matches `sheet` / `alert` / `fullscreencover`
/ `popover`). 0 conservation / referential-integrity /
biconditional across the entire TCA corpus, confirming cycle-87
finding #5 (`@PresentationState` / `IdentifiedArrayOf` / TCA
Action conventions need pattern calibration).

### 4.2 TCA 1.0.0 (pre-`@Reducer`-macro era)

- **Commit**: `195284b94b799b326729640453f547f08892293a` (tag `1.0.0`)
- **Examples surveyed**: SwiftUICaseStudies, UIKitCaseStudies, tvOSCaseStudies.
- **Other 1.0.0 examples** (SpeechRecognition, Standups, etc.) already
  used `@Reducer` macro and produce 0 detections — same gap as 1.25.5.

**Setup** (same as 4.1 but with `--branch 1.0.0`; same
non-`/tmp` workdir rule — see the §4.1 callout):

```
CORPORA="$HOME/xcode_projects/calibration-corpora"
cd /tmp && git clone --depth 1 --branch 1.0.0 \
    https://github.com/pointfreeco/swift-composable-architecture.git tca-pre-macro
mkdir -p "$CORPORA/tca-10-discovery/Sources"
cd "$CORPORA/tca-10-discovery"
cp -R /tmp/tca-pre-macro/Examples/CaseStudies/SwiftUICaseStudies Sources/CaseStudies
cp -R /tmp/tca-pre-macro/Examples/CaseStudies/UIKitCaseStudies Sources/UIKitCaseStudies
cp -R /tmp/tca-pre-macro/Examples/CaseStudies/tvOSCaseStudies Sources/tvOSCaseStudies
for t in CaseStudies UIKitCaseStudies tvOSCaseStudies; do
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

## 5. Cycle-7 baseline summary (post-v1.97 Biconditional inferred Bool)

| Corpus | Reducers (c0 → c7) | Interactions (c0 → c7) | Per-family non-zero |
|---|---|---|---|
| Hand-rolled (`Tests/Fixtures/v2.0-corpus/`) | 8 → **7** | 98 → **18** | All 5 |
| TCA 1.25.5 (7 examples) | 0 → **50** | 0 → **34** | Idempotence + Cardinality + Biconditional |
| TCA 1.0.0 (3 examples) | 21 → **35** | 16 → **24** | Idempotence + Cardinality + Biconditional |
| **Total** | **29 → 92** | **114 → 76** | 5 of 5 (hand-rolled) |

**v2.0 cycle-7 baseline = 76 interaction-invariant suggestions
across 92 reducers, all at default Possible tier.** Per-family:
55 idempotence + 10 biconditional + 8 cardinality + 2 referential
integrity + 1 conservation. Idempotence share 72.4%; Biconditional
13.2% (up from 5.7% at cycle-6).

Per-cycle deltas (chronological):
- **Cycle-0 → 1** (v1.91 cross-contam fix): 114 → 34 (−80).
- **Cycle-1 → 2** (v1.92 4th-shape + scalar): 34 → 35 (+1), 29 → 42 reducers (+13).
- **Cycle-2 → 3** (v1.93 M1.D macro): 35 → 56 (+21), 42 → 92 reducers (+50).
- **Cycle-3 → 4** (v1.94 cardinality @Presents): 56 → 57 (+1 on
  TCA 1.25.5; +1 on TCA 1.0.0 caught belatedly in cycle-6).
- **Cycle-4 → 5** (v1.95 RefInt IdentifiedArrayOf): 57 → 57 (no
  delta — detector correct, but TCA doesn't use `selected*` naming).
- **Cycle-5 → 6** (v1.96 Idempotence TCA action names): 57 → 70
  (+13). TCA 1.25.5 +8 (first detections on SyncUps, Todos,
  VoiceMemos idempotence). TCA 1.0.0 +5 (+4 idempotence from
  v1.96 + 1 belated cardinality from v1.94).
- **Cycle-6 → 7** (v1.97 Biconditional inferred Bool): 70 → 76
  (+6 biconditional). TCA 1.25.5 +3 (CaseStudies 2 + UIKit 1);
  TCA 1.0.0 +3 (same distribution). **First biconditional firings
  on real TCA** — the inferred-Bool initializer (`var isLoading
  = false`) is modern TCA's idiom.

Raw discovery outputs:
- `docs/calibration-cycle-87-data/` — cycle-0 (pre-v1.91 baseline)
- `docs/calibration-cycle-88-data/` — cycle-1 (post-v1.91)
- `docs/calibration-cycle-89-data/` — cycle-2 (post-v1.92)
- `docs/calibration-cycle-90-data/` — cycle-3 (post-v1.93)
- `docs/calibration-cycle-91-data/` — cycle-4 (post-v1.94)
- `docs/calibration-cycle-92-data/` — cycle-5 (post-v1.95)
- `docs/calibration-cycle-93-data/` — cycle-6 (post-v1.96)
- `docs/calibration-cycle-94-data/` — cycle-7 (post-v1.97)

-----

## 6. v2.0 calibration arc closed — cycle-87 findings complete

**All 5 cycle-87 findings + 4 sub-items closed across v1.91 –
v1.97.** The detector-fix queue is empty. The next active surface
is the three-cycle calibration loop the PRD §19 metrics measure
against — per-family acceptance-rate measurement against the
cycle-7 corpus baseline (76 suggestions across 92 reducers), three
cycles of stable rate per family, then tier promotion from
default-`.possible` to `.likely` / `.strong`.

**Closed findings**:
- **#1** (two-scalar false positive) — closed in v1.92.
- **#2** (bare-`State` / bare-`Action` cross-contamination) — closed in v1.91.
- **#3** (M1.B blind to `@Reducer` macro) — closed in v1.93.
- **#4** (M1.A 4th-shape extension) — closed in v1.92.
- **#5 sub-item (a)** (Cardinality `@Presents` recognition) — closed in v1.94.
- **#5 sub-item (b)** (RefInt `IdentifiedArrayOf` recognition) — closed in v1.95.
- **#5 sub-item (c)** (Idempotence TCA action names) — closed in v1.96.
- **#5 sub-item (d)** (Biconditional inferred-Bool initializer) — closed in v1.97.

**Sibling threads still queued**, both unblock different aspects
of the calibration loop's UX:

- **N-arm interactive triage prompt** (PRD §9.4) — UI work to
  walk a user through accept/reject decisions efficiently.
  Mechanical wrapper around `accept-interaction` recorder.
- **Kit-side `checkInteractionInvariantPropertyLaws` harness**
  (cross-repo) — third cross-repo cycle after M2 and M9. Wires
  v2.3.0 conformances to auto-run on every CI invocation.

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
