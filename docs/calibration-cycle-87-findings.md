# v1.90 Calibration Cycle 87 — Findings (v2.0 corpus cycle-0 baseline)

Captured: 2026-05-16. swift-infer at v1.90.

## Headline

**v2.0 calibration corpus is populated with measured cycle-0
baseline numbers.** First measurement of v1.89's detectors against
real reducer-shaped code. Three OSS corpora pinned + a 7-file
hand-rolled fixture set, with byte-stable raw outputs under
`docs/calibration-cycle-87-data/`. **114 interaction-invariant
suggestions across 29 reducers**, all at default Possible tier —
the v2.0 analog of v1's cycle-1 1167-baseline.

**Five findings surfaced** by the measurement itself; three
detector gaps + one false-positive class + one bare-name
cross-contamination bug. See §6 of the corpus doc for the
prioritized follow-up list.

After v1.90, the v2.0 calibration loop is *unblocked* — cycle 1
can start measuring deltas against the cycle-0 baseline, and the
detector-gap follow-ups (M1.D `@Reducer` macro recognition;
M1.A 4th-shape extension) become concretely actionable.

## What landed

### A — Hand-rolled fixtures (7 files, ~190 LOC)

`Tests/Fixtures/v2.0-corpus/Sources/HandRolled/` — one fixture per
PRD §5 family + an elm-style carrier-kind demonstrator + a negative
control. Detection-rule references woven into the file headers so
"why does this test demonstrate Cardinality?" reads off the
fixture itself.

Layout:

| File | Family | Carrier | Designed witnesses |
|---|---|---|---|
| `Hand01_Conservation.swift` | Conservation | `.generic` | 1 |
| `Hand02_Idempotence.swift` | Idempotence | `.generic` | 4 |
| `Hand03_Cardinality.swift` | Cardinality | `.generic` | 1 |
| `Hand04_ReferentialIntegrity.swift` | Referential Integrity | `.generic` | 2 |
| `Hand05_Biconditional.swift` | Biconditional | `.generic` | 2 |
| `Hand06_ElmStyle.swift` | Idempotence + Cardinality | `.elmStyle` | 2 |
| `Hand07_Negative.swift` | none | `.generic` | 0 expected |

### B — OSS corpus pins (two TCA versions)

Both pinned by SHA so cycle-N re-measurements compare against
identical source bytes (PRD §16 #6 reproducibility posture).

- **TCA 1.25.5** (`@Reducer` macro era, current):
  `1eaa6fa2ee57ac42843283b9fd3457af408c858d`. 7 examples surveyed.
- **TCA 1.0.0** (pre-macro): `195284b94b799b326729640453f547f08892293a`.
  3 examples surveyed; the other 1.0.0 examples already use
  `@Reducer` macro and produce 0 detections (same gap as 1.25.5).

Both clones produced via `git clone --depth 1 --branch <tag>`;
hard-copy to `Sources/<target>/` is required because
`FileManager.enumerator` doesn't follow top-level symlinks (a
recipe-style finding worth documenting in the corpus doc for future
re-runs).

### C — Cycle-0 measurement (114 suggestions, 29 reducers)

| Corpus | Reducers | Interaction suggestions |
|---|---|---|
| Hand-rolled | 8 | 98 |
| TCA 1.25.5 (7 examples) | 0 | 0 |
| TCA 1.0.0 (3 examples) | 21 | 16 |
| **Total** | **29** | **114** |

Raw outputs (one file per `discover-reducers` invocation, one per
`discover-interaction --include-possible` invocation): 12 files,
~38 KB total under `docs/calibration-cycle-87-data/`. These are
the byte-stable artifacts that cycle 1+ diff against.

## Five findings from the measurement

### Finding #1 — Signature-only scan produces ~12.5% false positives

`Hand07_Negative.swift`'s `transform(_:_:) -> Int` matches M1.A's
`(S, A) -> S` shape structurally with S=A=Int. The signature scan
has no type context to distinguish "state-shaped Int" from "scalar
Int." On the hand-rolled corpus this is 1/8 = 12.5%.

**Fix shape**: add a carrier-name heuristic that rejects two-scalars
shapes (Int/Int, Bool/Bool, String/String, …) from M1.A. PRD §3.5
conservative-inference posture suggests this should land before
calibration tier-promotion cycles begin.

### Finding #2 — Bare-`State` cross-contamination (8.2× inflation)

Six hand-rolled reducers each declare nested `Reducer.State`. Their
`ReducerCandidate.stateTypeName` field captures only the bare
`"State"`. The witness detectors then match *any* type whose
typestack-suffix is `["State"]` — so every reducer's witnesses fire
against every reducer's State. 96 cross-contaminated suggestions
on bare-State reducers + 2 on the elm-style `CounterState`
(distinct name) = 98 total, vs the designed 12.

This bug doesn't surface in single-reducer unit tests (the existing
M4–M7 test fixtures use one reducer per file) but breaks down
hard the moment a real codebase has >1 reducer using the standard
`Reducer.State` convention. Every TCA project would over-fire by
the same factor.

**Fix shape**: scope state-type lookup to
`<enclosingTypeName>.<stateTypeName>` rather than bare-suffix
match. Small change in
`ConservationWitnessDetector.Visitor.matchesTarget` (and the
parallel four visitors).

### Finding #3 — M1.B blind to `@Reducer` macro

TCA 1.25.5 (all 7 examples surveyed): 0 reducers detected. v1.74's
M1.B walker keys on the inheritance clause `: Reducer` /
`: Reducer<…>` / `: ReducerOf<…>`. Modern TCA replaces that with
the `@Reducer` macro attribute, which expands at compile time to
add conformance. The source-level inheritance clause is absent;
M1.B finds nothing.

**Fix shape**: add a new M1.D detection path that recognizes the
`@Reducer` attribute. Same body-walk logic as M1.B once the
attribute matches. **Highest-priority follow-up** — without it,
v2.0 doesn't fire on the dominant Swift reducer ecosystem.

### Finding #4 — M1.A blind to `(inout S, A) -> Effect<A>` shape

TCA 1.0.0 tvOSCaseStudies: `Focus.reduce(into:action:) -> Effect<Action>`
and `Root.reduce(into:action:) -> Effect<Action>`. M1.B's closure
walker recognizes this shape inside `Reduce { state, action in ... }`
blocks, but M1.A's `matchReducer` rejects it (no shape arm matches
`inout + non-Void + non-tuple return`). Result: 0 detections on
tvOS despite 2 clean reducer methods.

The case label `ReducerSignatureShape.inoutStateActionReturnsEffect`
already exists (added at v1.83 for the closure walker). M1.A just
needs a 4th shape arm that maps to it.

**Fix shape**: small surgical addition to
`ReducerDiscoverer.matchReducer` — add the
`inout-state + Effect<Action>-return` arm.

### Finding #5 — Only idempotence fires on real TCA

All 16 interaction suggestions across both TCA-pre-macro example
sets are idempotence (action-name-pattern matches). Cardinality /
referential integrity / biconditional fire 0 times. Working
hypotheses (recorded in corpus doc §4.2):

- TCA uses `@PresentationState alert: AlertState<Action>?` rather
  than `isShowingAlert: Bool` + `alert: AlertContent?` pairs, so
  M5 / M7 name patterns miss the `@Presents`-wrapped form.
- TCA uses `IdentifiedArrayOf<X>` rather than `[X]` array literals,
  so M6's array-element type extraction misses.
- TCA `Action` enums skew toward `task` / `delegate(...)` /
  `binding(.set(…))` shapes; only the small fraction of direct
  `refresh` / `set<X>` / `select<X>` cases match M4.C's curated
  lists.

These are calibration-loop signals about how the v0.0 detectors
compare to real-world TCA naming. Three-cycle promotion (PRD §3.5
corollary) will sharpen each family's patterns against the real
distribution.

## What's next

Three follow-up sub-cycles surfaced by this baseline, ordered by
calibration-loop impact:

1. **Fix Finding #2** (bare-`State` cross-contamination) — without
   it, per-family acceptance rates can't be measured meaningfully
   on multi-reducer codebases. Small change in the witness
   visitors. **Highest priority** since every other measurement
   depends on it.
2. **Ship M1.D** (`@Reducer` macro recognition) — without it, the
   TCA arm of the corpus stays at 0 reducers. Unlocks the modern
   TCA Examples for per-family measurement.
3. **Fix Finding #4** (M1.A 4th-shape extension) — small surgical
   fix; unlocks pre-macro TCA `reduce(into:action:)` methods.

Plus the slow-burn item: **tier-promotion calibration** for M4–M7
families. The cycle-0 baseline establishes the denominators;
cycles 1–3 measure acceptance-rate stability before any family
promotes to Likely / Strong.
