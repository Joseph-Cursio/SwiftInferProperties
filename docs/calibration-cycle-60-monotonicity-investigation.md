# Cycle-60 — Residual-surface investigation + findings correction

Captured: 2026-05-14. swift-infer at v1.63. Follow-up to
`docs/calibration-cycle-60-findings.md`.

## Why this note exists

The cycle-60 findings doc framed the v1.64 priority as a "Comparable-aware
monotonicity composer" closing "4 picks currently blocked on Comparable."
A direct verify-run investigation shows that framing is **wrong on two
counts**: the picks are not classified as Comparable-blocked in the
committed cycle-60 data, *and* a Comparable-aware composer alone would
close zero of them.

A follow-up investigation of the second-ranked priority — "non-OC generic
scaffolds (17 picks)" — found it is **also a mirage**: ~11 of the 18 are
internal-API dead ends, ~3 are discover-layer false positives, leaving
~3–4 genuinely closeable picks behind a carrier scaffold each.

This note records both investigations and concludes that **v1.64 has no
high-yield pick-closing target** — the cycle should pivot to Phase 2
accept-flow integration. The accept-flow scope is in the final section.

## The data discrepancy

`docs/calibration-cycle-60-findings.md` and
`docs/calibration-cycle-60-data/full-surface-summary.md` both report **4
`carrier-missing-required-conformance` picks** for cycle-60. The committed
cycle-60 survey JSON (`full-surface-outcomes.json`) contains **zero** —
`grep -c conformance` returns 0. The category is real (it appears in the
cycle-58 and cycle-59 JSONs, 2 each, and is emitted by
`VerifyCommand+AllFromIndex.swift:365`), but it is absent from cycle-60.

Root cause: `architecturalPendingDetail` checks
`instance-method-shape-not-supported` (line 348) **before**
`carrier-missing-required-conformance` (line 364). V1.63.A added the
`"generic parameter … could not be inferred"` pattern to the first check.
That pattern now also matches the OrderedSet `index(after:)` /
`index(before:)` monotonicity picks, so they moved from
`carrier-missing-required-conformance` (cycle-59) →
`instance-method-shape-not-supported` (cycle-60). The cycle-60 findings
doc described the cycle-59 classification without re-checking the new JSON.

## The verify-run investigation

Ran `swift-infer verify --suggestion 5F9B` (OrderedSet × `index(after:)` ×
monotonicity) and built the synthesized stub directly. The stub:

```swift
let valueA = min(firstDraw, secondDraw)        // line 28
let valueB = max(firstDraw, secondDraw)        // line 29
let resultA = OrderedSet.index(valueA)         // line 30
let resultB = OrderedSet.index(valueB)         // line 31
```

Build output — four errors, **two distinct root causes**:

```
line 28: error: global function 'min' requires that 'OrderedSet<Int>' conform to 'Comparable'
line 29: error: global function 'max' requires that 'OrderedSet<Int>' conform to 'Comparable'
line 30: error: generic parameter 'Element' could not be inferred
line 31: error: generic parameter 'Element' could not be inferred
```

**Bug A — Comparable (lines 28–29).** The monotonicity stub orders its two
trial values with global `min` / `max`, which requires the *carrier* to
conform to `Comparable`. `OrderedSet<Int>` does not. This is the genuine
"Comparable-blocked" issue — a Comparable-aware value-ordering strategy
would fix this part.

**Bug B — call shape (lines 30–31).** `OrderedSet.index(valueA)` is a
**static call on the type**, passing a generated `OrderedSet<Int>` *value*
as a positional argument. But `index(after:)` is an **instance method**
requiring a receiver and a labeled *index* argument —
`someCollection.index(after: someIndex)`. The emitter generated the wrong
call shape entirely: it treats the carrier value as the argument to
`index()`. Swift cannot infer `Element` because `OrderedSet.index(_:)` in
that form does not exist. A Comparable-aware composer does not touch this.

Both diagnostics are emitted on every build of this pick. Because the
classifier short-circuits at the first match, the JSON shows only
`instance-method-shape-not-supported` and the findings doc saw only the
Comparable half — each captured one of two co-occurring real bugs.

## Corrected breakdown — 22 pending monotonicity picks

| Block reason | Count | Picks | Composer alone closes? |
|---|---:|---|---|
| dual bug (Comparable + call-shape) | 4 | `OrderedSet`, `OrderedDictionary.Elements` × `index(after:)` / `index(before:)` | **No** — needs both fixes |
| `unsupported-carrier` (nested-OC) | 6 | `OS.SubSequence`, `OD.Values`, `OD.Elements.SubSequence` × `index(after:)` / `index(before:)` | No — needs a 3-edit carrier scaffold each, *then* both fixes |
| `internal-api-not-accessible` | 3 | `OrderedSet._maximumCapacity` / `_minimumCapacity` / `_scale` | No — dead end |
| `unsupported-carrier` (`_HashTable*`) | 7 | `_HashTable`, `_HashTable.UnsafeHandle` | No — internal API, will reclassify to internal-api |
| `unsupported-carrier` (other) | 2 | `EvenlyChunkedCollection`, `ViolationFormatter` | No — unrelated non-OC scaffolds |

## Monotonicity emitter — what closing those 4 picks would actually take

**A standalone "Comparable-aware monotonicity composer" closes 0 picks.**
It would compile lines 28–29 and still hard-fail on lines 30–31.

The actual work to close the 4 dual-bug picks is a monotonicity-emitter
rework, not a composer:

1. **Instance-method call shape** — emit `receiver.index(after: index)`,
   not `Carrier.index(value)`. The emitter currently mismodels instance
   methods on collection carriers.
2. **Order-by-input, not `min`/`max`-on-carrier** — the monotonicity
   property for `index(after:)` is over *indices*, not over the carrier
   value; the value-ordering step should not require carrier `Comparable`.

Estimated yield: 4 direct picks, +6 more only if bundled with three
nested-OC carrier scaffolds. Given cycle-60's diminishing-returns finding
(v1.62 closed 8, v1.63 closed 1), an emitter rework for ~4 direct picks
is a weak trade. Defer indefinitely.

## Non-OC residual surface — also investigated

Verify runs on two representatives of the "17 non-OC generics" priority:

- **`ChunkedByCollection` idempotence** (`3543`) — fails at the resolver
  with `VerifyError.unsupportedCarrier` *before* a workdir is synthesized.
  A genuine 3-edit scaffold candidate, if the carrier is constructible.
- **`_HashTable` monotonicity** (`D722`) — the strategist returns `.todo`:
  `_HashTable` declares a user `init` (no synthesized memberwise init) and
  is internal API, invisible from a non-`@testable` workdir. Dead end.

Honest breakdown of the 18 non-OC pending picks:

| Bucket | Count | Picks | Real v1.64 target? |
|---|---:|---|---|
| Internal-API dead ends | 11 | `_HashTable*` (8), `_UnsafeHashTable` (1), `Complex.rescaledDivide` (2) | No — invisible from the workdir |
| Likely discover-layer false positives | 3 | `CombinationsSequence × binomial(n:k:)` (2 — `binomial` is a free function; `binomial(n,k)==binomial(k,n)` is false), `ViolationFormatter × format(_:)` monotonicity (1) | No — should *reject*, not be "covered" |
| Genuine scaffold candidates | ~4 | `ChunkedByCollection` idempotence (2), `EvenlyChunkedCollection` idempotence (1) + monotonicity (1 — also dual-bugged) | Maybe — 2–3 picks behind two scaffolds |

The "17 non-OC generics" priority is **~3 genuinely closeable picks**, not 17.

## v1.64 re-scope — pivot to accept-flow integration

Both pick-closing priorities the original cycle-60 doc named are mirages
once verify-checked. Combined with the cycle-60 trajectory (8 → 1 picks
closed), the honest read is: **the pick-closing game is essentially over.
Every remaining bucket is ≤4 picks or dead.** Grinding the measured rate
from 40.8% → ~42% is not worth a cycle.

The strategically correct v1.64 is **Phase 2 accept-flow integration** —
making the 42 already-measured verify outcomes (40.8%, 0 measured-error)
*do something* instead of being printed and discarded. That is the
product value; the residual picks are not.

### Current state

- `Decisions` / `DecisionRecord` / `Decision` live in
  `Sources/SwiftInferCore/Decisions.swift`; persisted at
  `.swiftinfer/decisions.json` via `DecisionsLoader` (atomic write,
  schema-versioned, `upserting` by `identityHash`). Schema is at v2.
- `Decision` has four cases — `accepted`, `acceptedAsConformance`,
  `rejected`, `skipped` — all *user* choices. `DecisionRecord` carries
  no verify-outcome field.
- `VerifyOutcome` (`VerifyResult.swift`) has four cases — `bothPass`,
  `edgeCaseAdvisory`, `defaultFails`, `error`.
- `VerifyCommand.swift:24` states the gap explicitly: *"Verified
  suggestions don't flow into `decisions.json` in v1.42 — the accept-flow
  integration is deferred."* `--all-from-index` emits `SurveyRecord` JSON
  to stdout but persists nothing.

### Proposed v1.64 workstreams

**A. `VerifyEvidence` model + `.swiftinfer/verify-evidence.json` store.**
New `VerifyEvidence` value (`identityHash`, `outcome`, `capturedAt`,
`swiftInferVersion`, optional `detail`) + a `VerifyEvidenceStore`
loader/writer mirroring `DecisionsLoader` — atomic write, schema-versioned,
`upserting` by `identityHash`. **A parallel evidence file, not a new
`DecisionRecord` field** — keeps machine evidence orthogonal to user
decisions and avoids a schema-v3 migration of the v2 `Decisions` format.

**B. Verify command persists evidence.** Both `--suggestion` (upsert one
record) and `--all-from-index` (write the full batch) write to the store.
The survey path already computes every outcome; this is an added write
step, not new logic.

**C. First consumer — `discover` explainability annotation.** When a
discovered suggestion has a matching `VerifyEvidence` record, its
explainability block shows the evidence inline: `✓ verified (bothPass,
100 trials)` / `⚠ verify edge-case advisory` / `✗ verify-disproven`.
This surfaces the evidence where the user actually reads it and is the
lowest-risk consumer (render-only; no pipeline behaviour change).

**D. (Optional, defer if scope tight) `metrics` split.** `swift-infer
metrics` reports Possible-tier accept-rate split by verify-confirmed vs
unverified — feeds the §17.2 calibration loop.

**E. Tests + cycle-61 findings doc.**

### Open design decisions

1. **Parallel evidence file vs. schema-v3 `DecisionRecord` field** —
   recommend the parallel file (workstream A). Lower risk, no migration,
   and a suggestion can carry verify evidence with *no* user decision yet
   (which an optional-`decision` schema-v3 would force awkwardly).
2. **Does `defaultFails` (verify-disproven) auto-reject?** No. PRD §3.5
   conservative posture + "nothing auto-executes" → `discover` warns
   prominently and may drop the suggestion a tier, but the user still
   decides. Auto-rejection would be the Daikon trap in reverse.
3. **Staleness** — evidence is `swiftInferVersion`-stamped; a consumer
   reading evidence from an older binary warns, mirroring the existing
   index-staleness pattern in `VerifyHarness.resolveIndex`.

### Why this is the right v1.64

It is mostly mechanical (reuses `DecisionsLoader` patterns), carries no
schema-migration risk, and delivers the first concrete payoff from the
v1.42–v1.63 verify-architecture arc: verify evidence that influences what
the user sees. Pick-count cycles have hit diminishing returns; this is
the cycle that makes the prior fourteen worth something.

## Methodology note

The cycle-60 findings doc was written against the cycle-59 classification
without diffing the regenerated cycle-60 JSON — a re-occurrence of the
"findings doc not cross-checked against the machine-generated survey"
pattern. A fixture-level guard that asserts the findings doc's
outcomeDetail counts match the committed JSON would have caught this
pre-merge, analogous to the V1.58.B curated-bindings methodology guard.

## Artifacts

- Verify runs: `swift-infer verify --suggestion {5F9B,3543,D722} --index-path fixtures/cycle27-surface/.swiftinfer/index.json`
- Stub + build errors for `5F9B` captured from the synthesized workdir at
  `fixtures/cycle27-surface/.swiftinfer/verify-workdir/5F9B/` (gitignored
  build artifact). `3543` / `D722` fail at the resolver before workdir
  synthesis.
- Classifier ordering: `Sources/SwiftInferCLI/VerifyCommand+AllFromIndex.swift:348` vs `:364`.
- Accept-flow current state: `Sources/SwiftInferCore/Decisions.swift`,
  `Sources/SwiftInferCLI/DecisionsLoader.swift`,
  `Sources/SwiftInferCLI/VerifyResult.swift`, `VerifyCommand.swift:24`.
