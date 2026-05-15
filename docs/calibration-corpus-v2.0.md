# SwiftInferProperties v2.0 — Calibration Corpus

**Status: skeleton (M1.C ship).** This file frames what the v2.0
calibration corpus will be. Real OSS commit pins land at M3+ when the
verify pipeline can validate expected per-family suggestion counts.

The v2.0 analog of v1's cycle-1 1167-baseline (the candidate-count
that the first calibration cycle starts from) is the per-carrier-kind
+ per-family discovery count this corpus produces.

-----

## 1. Why a corpus, and why now

v2.0's success criteria (PRD §19) measure per-family acceptance rates
and measured-execution rates against a calibration corpus. v1
calibrated against four OSS Swift libraries (swift-collections /
swift-algorithms / swift-async-algorithms / Apollo iOS) — its corpus
*was* the verification surface.

v2.0's domain is reducer-shaped state systems, so the natural corpus
is a mix of:

- **TCA exemplars.** The canonical `swift-composable-architecture/Examples/`
  reducers — ~15 reducers across the standard examples.
- **Elm-style OSS projects.** Smaller surface in Swift OSS; ELM-in-Swift
  patterns mostly live in proof-of-concept projects.
- **Hand-rolled reducers.** Analog of v1's cycle-27 frozen surface — a
  curated set of representative reducers exercising each family at
  least 5 times.

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

Per-carrier expected counts are TBD — populated at M3+ when discovery
runs against the pinned OSS corpora and verify validates the numbers.

-----

## 3. Per-family expected suggestion counts

The five interaction-template families (PRD §5):

| Family | M-milestone | Witness | Expected per-corpus count (TBD) |
|---|---|---|---|
| 4. Conservation | M4 (lifted from v1) | Stored aggregate + contributing collection | TBD |
| 5. Idempotence | M4 (lifted from v1) | Action case name pattern (refresh / reset / clear) | TBD |
| 1. Cardinality | M5 | ≥ 2 transient-presentation modifiers in State | TBD |
| 2. Referential integrity | M6 | `selectedX: T.ID?` + `xs: [T]` pair | TBD |
| 3. Biconditional / iff | M7 | `(isLoadingX, taskX?)` or `(isShowingX, dataX?)` pair | TBD |

Each per-family number lands when the family's milestone ships at
default `Possible` visibility (§3.5 corollary). The number is the
calibration baseline against which "stable acceptance rate" is
measured across the three required calibration cycles before
promotion to default-visible (`Likely` / `Strong`).

-----

## 4. OSS corpus pins (deferred to M3+)

Each corpus is pinned at a specific git commit so re-running
calibration on a later cycle compares against the same source bytes
(matches v1's reproducibility posture — PRD §16 #6).

**Pinning happens at M3+ ship**, not at M1. Reason: pinning numbers
that haven't been validated against a working verify path produces a
false anchor — better to pin once we can stand behind the counts.

The corpora intended for inclusion (no commits pinned yet):

- **TCA examples.**
  - Repository: `https://github.com/pointfreeco/swift-composable-architecture`
  - Path: `Examples/`
  - Commit: TBD (pinned at M3+ ship).
- **Elm-style OSS.** TBD — research task to find a representative
  exemplar. Strong candidates include any Swift reproductions of
  classic Elm examples (counter, list-with-add/remove,
  navigation-with-pages).
- **Hand-rolled corpus.** TBD — analog of v1's cycle-27 frozen
  surface. Likely lives in `Tests/Fixtures/v2.0-corpus/` once M3
  shows what fixtures are worth keeping under version control.

-----

## 5. What this file becomes at M3+

When this skeleton is upgraded to a real pinned corpus, the structure
becomes:

1. Per-corpus reducer inventory: file path, carrier kind, signature
   shape (the M1 discovery output, frozen at the pinned commit).
2. Per-corpus per-family expected suggestion counts (M3+ scoring's
   output, frozen at the pinned commit).
3. Per-corpus measured-execution rate (M3+ verify's output, frozen
   at the pinned commit).

Together these are the v2.0 calibration baseline. Cycles 1–N then
report deltas against this baseline, mirroring v1's
`docs/calibration-cycle-N-data/` shape.

-----

## 6. Open questions

1. **Corpus size.** v1 pinned four large OSS libraries (~thousands of
   functions). v2.0's "reducer" surface is far smaller per repo, so
   the corpus probably needs more *projects* — maybe 8–12 reducers
   per project across 5–10 projects.
2. **TCA-only bias.** If the OSS corpus is dominated by TCA, the
   heuristics will tune to TCA conventions and not generalize. PRD
   §14 calls this out as a risk — at least one Elm-style and one
   hand-rolled project must be in the pinned corpus.
3. **Whether to include `swift-infer` itself.** Dogfooding signal —
   does v2.0 produce useful interaction-invariant suggestions on its
   own reducer-ish code paths? Probably not many: `swift-infer` is a
   one-shot CLI tool, not a state-system. Skip.
