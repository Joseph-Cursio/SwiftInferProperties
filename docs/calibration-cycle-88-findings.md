# v1.91 Calibration Cycle 88 — Findings (bare-name cross-contamination fix)

Captured: 2026-05-16. swift-infer at v1.91.

## Headline

**First cycle-87-finding fix lands.** v1.91 closes Finding #2
(bare-`State` / bare-`Action` cross-contamination) by adding
`ReducerCandidate.stateQualifiedName` + `actionQualifiedName`
computed properties and threading them through the
`InteractionTemplateEngine` to all five witness detectors.

**Hand-rolled corpus: 98 → 18 suggestions (−81.6%).** Per-family
counts now match per-fixture design exactly. Corpus-wide cycle-1
baseline drops from 114 → 34 (−70.2%). The TCA arms were
unaffected because M1.B's TCA closure walker already pre-qualifies
State/Action names — they were never cross-contaminating.

After v1.91, four cycle-87 findings remain queued for fix:
@Reducer macro recognition (#1), M1.A 4th-shape extension (#2),
two-scalar false-positive filter (#3), and family-pattern
calibration (#4).

## What landed

### A — `ReducerCandidate.stateQualifiedName` / `actionQualifiedName`

Two new computed properties on `ReducerCandidate`. Both call a
shared `qualify(typeName:enclosing:)` private static helper that:

1. If the typeName already contains a dot, return it as-is (M1.B's
   TCA closure walker pre-qualifies as `"<enclosing>.State"` for
   downstream stub-emission reasons — see
   `ActionSequenceStubEmitter`'s `\(stateTypeName)()` constructor).
2. Otherwise prefix the enclosing type name (M1.A's signature scan
   stores bare `"State"`).
3. For free functions with `enclosingTypeName == nil`, return the
   bare typeName.

The dot-awareness is **load-bearing** — naively prefixing M1.B's
already-qualified output would produce
`"LazyNavigation.LazyNavigation.State"` and break detector lookup.
Initial cycle-88 measurement caught this exact failure mode (TCA
1.0.0 CaseStudies dropped from 12 → 0 with naive prefixing); the
dot-aware helper restored the correct count.

### B — Engine threading

`InteractionTemplateEngine.analyzeOne` was updated to pass
`candidate.stateQualifiedName` to Conservation / Cardinality /
ReferentialIntegrity / Biconditional detectors and
`candidate.actionQualifiedName` to Idempotence. No detector-side
changes — the existing `targetName.split(".")` + typestack-
suffix-match logic already handles qualified names correctly. The
fix is purely in the engine's call sites.

### C — Tests

Three new test groups:

- 6 unit tests in `ReducerCandidateTests` covering the qualified-
  name properties: bare-name input from M1.A (prefixed), dotted
  input from M1.B (passed through), free-function input
  (unchanged for both State and Action).
- 2 end-to-end tests in `InteractionTemplateEngineTests` — two
  reducers sharing bare `State` / `Action` declarations exercise
  the cross-contamination scenario; the test asserts each reducer
  sees only its own witnesses.
- Post-fix discovery outputs persisted under
  `docs/calibration-cycle-88-data/` (3 files: hand-rolled +
  TCA 1.0.0 CaseStudies + TCA 1.0.0 UIKit). The pre-fix outputs
  remain under `docs/calibration-cycle-87-data/` for forensic
  diffs.

### D — Hand-rolled fixture lint cleanup

`Hand07_Negative.swift`'s `transform(_ a: Int, _ b: Int) -> Int`
was renamed to `transform(_ lhs: Int, _ rhs: Int) -> Int` to
satisfy SwiftLint's `identifier_name` rule (min length 3). The
3-char-minimum rule wasn't firing at v1.90 because lint runs from
the project root and the fixture wasn't yet checked in; v1.91 picked
it up on first lint scan post-corpus-merge.

## Measured delta

### Hand-rolled corpus (`Tests/Fixtures/v2.0-corpus/`)

| Family | Cycle-0 (v1.89) | Cycle-1 (v1.91) | Reduction |
|---|---|---|---|
| Idempotence | 49 | 9 | −40 |
| Biconditional | 24 | 4 | −20 |
| Referential Integrity | 12 | 2 | −10 |
| Cardinality | 7 | 2 | −5 |
| Conservation | 6 | 1 | −5 |
| **Total** | **98** | **18** | **−80 (−81.6%)** |

Per-family cycle-1 counts now match per-fixture design exactly
(see `docs/calibration-corpus-v2.0.md` §3.1).

### TCA corpora

| Corpus | Cycle-0 | Cycle-1 | Delta |
|---|---|---|---|
| TCA 1.25.5 (7 examples) | 0 | 0 | unchanged |
| TCA 1.0.0 CaseStudies | 12 | 12 | unchanged |
| TCA 1.0.0 UIKit | 4 | 4 | unchanged |

**Important calibration finding**: TCA arms saw no delta because
M1.B's closure walker has pre-qualified State/Action types since
v1.74 (`enclosingTypeName + ".State"` literal — see
`ReduceClosureWalker.swift:84`). The bare-name bug was specific to
M1.A's signature-scan path, which leaves the names bare. So real-
world TCA was never affected by Finding #2 in practice — only
codebases using M1.A's path (free Elm-style functions, or struct
methods on non-`Reducer`-conforming types) would see the bug.

This nuance was not visible in cycle-0 because the hand-rolled
corpus only exercised M1.A. Cycle-1's measurement confirms the
asymmetry.

## What's next

Four cycle-87 findings still queued, in priority order:

1. **M1.D `@Reducer` macro recognition** — modern TCA visibility.
   Highest priority. M1.B extension; not a bug fix but a new
   detector path.
2. **M1.A 4th-shape extension** — recognize
   `(inout S, A) -> Effect<A>` in signature scan. Small surgical
   fix; the case label already exists.
3. **Two-scalar false-positive filter** on M1.A.
4. **Family-pattern calibration** for real TCA conventions
   (`@PresentationState`, `IdentifiedArrayOf`, TCA Action names).
   The actual three-cycle calibration loop.

Cycle 89 should pick up #2 (smallest of the remaining items, and
M1.B's #1 needs more design work).
