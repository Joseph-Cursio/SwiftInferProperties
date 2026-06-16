# Calibration cycle 147 — v1 algebraic measured-rate epic: scope + a correction

**Captured 2026-06-16.** No binary change — investigation + decision record.
The owner greenlit attacking the frozen **50.5% measured-execution rate**
(52/103, frozen since cycle 66). This cycle establishes the real baseline,
**corrects a long-standing mis-diagnosis**, and sizes the levers.

## The correction

The frozen `52/103` is the **v1 ALGEBRAIC corpus**
(`fixtures/cycle27-surface/` — 8 swift-algorithms + 20 swift-numerics
(ComplexModule) + 74 swift-collections (OrderedCollections) + 1
SwiftPropertyLaws picks, over round-trip / idempotence / commutativity /
associativity / monotonicity / dual-style / lifted templates).

Cycles 119/121/126's "what's next" framing — and the cycle-146 consolidation
doc §8 — attributed the freeze to **non-promotable nested-action
composition** + **non-compilable corpora**. **That is wrong for this
metric.** Those are the blockers for the *separate* TCA **interaction**
corpora (`tca-10`/`tca-25`). The v1 algebraic metric has nothing to do with
Action payloads; it is blocked by **carrier/shape coverage**. (Fixed in
`measured-verify-architecture.md` §8 + CLAUDE.md this cycle.)

## Baseline regen — confirmed, with a classification correction

Re-ran `swift-infer verify --all-from-index` over the freshly-resolved corpus
(swift-collections 1.6.0 / swift-algorithms 1.2.1 / swift-numerics /
SwiftPropertyLaws 2.5.0). **The rate reproduced exactly: 52/103 = 50.5%,
per-identity *identical* to the checked-in baseline** (38 bothPass + 6
defaultFails + 8 edgeAdvisory measured; 51 ACP). Not stale.

**But the current binary's detail classification differs** from the
checked-in evidence's (older-binary) detail strings: **12 picks the old
strings labeled `unsupported-carrier` the current classifier labels
`instance-method-shape-not-supported`** (the build-error pattern matcher in
`VerifyCommand+ArchitecturalPendingDetail.swift` improved between the snapshot
and now). The checked-in `verify-evidence.json` was left as-is (restored
after regen — refreshing it is pure timestamp/version/reorder churn for an
identical-outcome result). **The authoritative current breakdown of the 51
ACP is:**

| Category | Count | Nature |
|---|---|---|
| `unsupported-carrier` | 22 | strategist can't resolve a generator/recipe for the carrier |
| `instance-method-shape-not-supported` | 20 | public method (all associativity/commutativity), static call emitted where instance/mutating is needed |
| `internal-api-not-accessible` | 9 | selected symbol is `internal` in an external module → unverifiable externally |

The 22 `unsupported-carrier` split by addressability:

- **9 — private stdlib internals** (`_HashTable` ×4, `_HashTable.UnsafeHandle`
  ×4, `_UnsafeHashTable` ×1). `_`-prefixed = Swift's private-API convention;
  unconstructible. **False positives.**
- **6 — lazy-wrapper result types** (`EvenlyChunkedCollection` ×2,
  `ChunkedByCollection` ×2, `CombinationsSequence` ×2) — *results* of
  operations, not values a user constructs. Mostly false positives.
- **6 — real public types missing a recipe/pair** (`OrderedSet<Int>`
  round-trip ×3, `OrderedDictionary` ×3). **Addressable.**
- **1 — `ViolationFormatter`** monotonicity — a local false positive.

**Headline:** the biggest addressable lever is now **instance-method-shape
(20 picks)**, not unsupported-carrier — Lever B is far larger than the
checked-in detail strings suggested.

## The metric is movable — sized levers

| Lever | What | Picks | Effect | Risk |
|---|---|---|---|---|
| **A — non-public filter** | Drop `_`-prefixed + `internal`-symbol carriers at discovery. A direct extension of the **cycle-54** filter (already drops `private`/`fileprivate`, 109→103). False positives by the project's high-precision bar. | 9 `_`-internals + 9 internal-api = **18** | 52/103 → ~**52/85 = 61%** + precision win | low |
| **B — instance/mutating-method emitter** | Emit instance-relative / mutating call shapes (SetAlgebra-style assoc/commutativity ops on OrderedSet/OrderedDictionary + views). Scoped as the "v1.60 target," never finished. Pure emitter work, no new generators. **The big lever.** | **20** | → ~**72/85 = 85%** | medium |
| **C — pair/recipe gaps** | `OrderedSet<Int>` round-trip pair + `OrderedDictionary` strategist recipe. | **6** | → ~**78/85 = 92%** | medium |
| D — lazy-wrapper + local FPs | Filter the unconstructible result types (`EvenlyChunked`/`ChunkedBy`/`Combinations`) + `ViolationFormatter` as false positives (or generate from a source collection — low value). | 6 + 1 = **7** | → ~**78/78 ≈ 100%** of the legitimate denominator | low (filter) |

**Projected arc: 50.5% → ~85% (A+B) → ~92% (C) → ~100% of legitimate
denominator (D filter).** The regen reclassification makes **B the dominant
lever (20 picks)**, much larger than the checked-in detail strings implied.
Honest framing: A and D raise the rate by removing *false positives* (a
precision fix with a rate side-effect, report both axes); B and C are genuine
recall gains — real public algebraic properties that become measured
verdicts.

## Decision + plan

**Proceed.** Sequence: **A** (cheap, principled, precision-first) → **B**
(the real engineering lever) → **C** (pairs/recipes). D stays a low-value
tail (mostly more filtering). Each lever is its own build cycle, re-running
the survey to confirm the rate moved.

**Baseline reproducibility:** confirmed this cycle — see "Baseline regen"
above. The rate reproduces exactly (52/103, per-identity identical); only the
ACP *detail* classification refined (the current binary attributes 20 picks
to instance-method-shape vs the older snapshot's 8). The checked-in
`verify-evidence.json` was restored after the regen (an identical-outcome
refresh is pure timestamp/version churn).

## Where the levers live (for the build cycles)

- **A**: discovery/index scan filter — extend the cycle-54 access-level filter
  (where `private`/`fileprivate` are dropped at scan time; see
  `build-index.sh` note + `docs/calibration-cycle-54-findings.md`) to also
  drop `internal` + `_`-prefixed carriers/symbols.
- **B**: `StrategistDispatchEmitter` / the algebraic call-shape emission +
  `VerifyCommand+ArchitecturalPendingDetail.swift`'s
  `instance-method-shape-not-supported` classifier (the cycle-56 scope).
- **C**: `RoundTripPairResolver.curated` + `StrategistDispatchEmitter`
  recipe resolution (`OrderedDictionary`).
