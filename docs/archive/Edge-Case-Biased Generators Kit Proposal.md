# Edge-Case-Biased Generators Kit Proposal

**Status:** ✅ **Kit-side landed in `SwiftPropertyLaws v2.1.0`** (commit `ba19ab7`, 2026-05-11). Downstream consumption now queued for SwiftInferProperties v1.42 — see §8 below.
**Target (now landed):** SwiftPropertyLaws v2.1.0 — opt-in `PropertyLawComplex` library product. Main `PropertyLawKit` line keeps a zero `swift-numerics` footprint.
**Date:** 2026-05-11

## 1. Summary

Add **edge-case-biased generators** for floating-point and Complex types to the kit's `Gen<T>` infrastructure. Each generator produces a 90/10 mix of (a) values from the existing default generator and (b) values from a curated edge-case list (NaN, ±Inf, ±0, subnormals, MAX, MIN, etc.). The bias keeps trial budgets focused on normal-domain exploration while guaranteeing each edge case is hit periodically over a typical N=100 trial run.

The minimum-viable scope is a **single generator** (`Gen<Complex<Double>>.edgeCaseBiased`) — the SwiftInfer Phase 1 verify mode targets CM round-trip pairs (`exp/log`, `cos/acos`, etc.), which are all `Complex<Double> -> Complex<Double>`. Expansion to `Double` / `Float` / `Complex<Float>` is a follow-up after the verify pipeline is validated end-to-end.

The shape is backward-compatible: a new generator added to `Gen<Complex<Double>>` alongside the existing `.default`. No existing kit consumer is affected.

-----

## 2. Motivation

### 2.1 Why edge-case-biased generators

SwiftInferProperties' cycle-27 acceptance-rate measurement landed at **72.4%** — the asymptote of name + type heuristics. The residual ~8 reject picks on the 109-surface are type-pattern false-positives that name-based reasoning structurally can't close (e.g., `binomial(n:k:)` matching commutativity by `(T, T) -> T` shape but failing `C(n,k) == C(k,n)`).

**Test-execution evidence** punches through the ceiling: instead of guessing from names, we compile + run the candidate property test on N random inputs and treat the result as a high-confidence signal. The kit's `Gen<T>` machinery already drives this on adopted-protocol law verification (PropertyLawKit's `checkSetAlgebraPropertyLaws`, etc.); SwiftInfer needs the same machinery aimed at *candidate* properties before the user adopts them.

The edge-case bias matters specifically for FP/Complex types because:

- **NaN-based bugs are common**: `decode(encode(NaN))` may return a non-NaN value, may crash, or may silently corrupt downstream computation. A finite-only generator never surfaces these.
- **Signed zero is a sleeper class**: `atan2(0, 0)` vs `atan2(-0.0, 0)` produce different results in IEEE 754; few APIs document the boundary.
- **Overflow boundaries**: `Double.greatestFiniteMagnitude * 2 == .infinity` cascades through many algorithms.
- **Subnormal precision loss**: `.leastNonzeroMagnitude` may produce different round-trip behavior than normal-range values.

The 90/10 bias is the standard PBT pattern (Hedgehog default; swift-property-based's `frequency` combinator landed close to this ratio). 100% normal-domain misses edge bugs; 100% edge-only wastes trials on the same ~12 distinct values.

### 2.2 Two-pass verification (motivating the *biased* design specifically)

SwiftInferProperties Phase 1's verify mode runs each property **twice**, once with the kit's existing `.default` generator and once with `.edgeCaseBiased`. The four outcomes carry distinct meanings:

| Default | EdgeCase | Interpretation |
|---|---|---|
| Pass | Pass | Strong evidence — property holds across full domain |
| Pass | Fail | Holds for normal inputs, breaks at boundary — **advisory with failing edge value** |
| Fail | — | Property is wrong; skip edge pass; surface finite-pass counterexample |

Row 2 is the high-value outcome. Today the user accepts a candidate property without knowing it has a NaN-specific failure; two-pass verification turns that into a documented edge-case advisory at accept time.

The bias ratio matters here: a pure-edge-case generator would make row 2 fire on properties that legitimately exclude NaN from their documented domain. The 90/10 bias ensures the edge pass has ~10 edge-case trials over N=100 — enough to hit each curated edge case at least once, but small enough that a "doesn't hold for NaN" outcome is genuinely about NaN specifically.

-----

## 3. API Surface

### 3.1 Phase 1 minimum scope

```swift
extension Gen where Value == Complex<Double> {

    /// 90/10 mix: 90% finite-domain values from `.default`, 10%
    /// drawn from `complexEdgeCases`. The bias keeps trial budgets
    /// focused on normal-domain exploration while guaranteeing
    /// each curated edge case is hit periodically over N=100 trials.
    ///
    /// **Determinism.** Same `(seed, trialIndex)` always produces the
    /// same value. The Bernoulli sampler driving the 90/10 split is
    /// seeded from the same source as the existing `.default`
    /// generator, so reproducibility holds.
    ///
    /// **Shrinking.** Default-path values shrink via the existing
    /// `Gen<Complex<Double>>.default` shrinker. Edge-case values are
    /// already minimal (NaN has no simpler form); they do not shrink.
    public static var edgeCaseBiased: Gen<Complex<Double>>

    /// Curated 12-element edge-case set covering the distinct
    /// IEEE 754 + Complex<Double> failure modes. Public so SwiftInfer
    /// can reference specific entries in counterexample reports.
    public static var complexEdgeCases: [Complex<Double>]
}
```

### 3.2 Curated edge-case set (the only place opinion lives)

| # | Value | Failure mode covered |
|---|---|---|
| 1 | `Complex(.nan, .nan)` | Both components NaN |
| 2 | `Complex(.nan, 0)` | NaN real, finite imag — composition with finite |
| 3 | `Complex(0, .nan)` | Finite real, NaN imag — symmetric to #2 |
| 4 | `Complex(.infinity, 0)` | Positive real infinity |
| 5 | `Complex(-.infinity, 0)` | Negative real infinity |
| 6 | `Complex(0, .infinity)` | Positive imaginary infinity |
| 7 | `Complex(0, -.infinity)` | Negative imaginary infinity |
| 8 | `Complex(.infinity, .infinity)` | Diagonal infinity |
| 9 | `Complex(0, 0)` | Origin / additive identity |
| 10 | `Complex(-0.0, 0)` | Signed zero — `atan2`-class boundary |
| 11 | `Complex(.greatestFiniteMagnitude, 0)` | Overflow boundary |
| 12 | `Complex(.leastNonzeroMagnitude, 0)` | Underflow / subnormal |

**Notable omissions** (each documentable as deliberate):
- `Complex(1, 0)` / `Complex(0, 1)` / `Complex(-1, 0)`: not edge cases — the unit / imaginary unit are normal-domain values the default generator hits.
- Mixed-magnitude pairs like `Complex(.infinity, .greatestFiniteMagnitude)`: noise; the 12 above cover the distinct semantic categories. Trial budget is finite.
- Denormal mixed pairs: row 12 covers subnormals on the real axis; the imaginary-axis case follows by Complex's componentwise arithmetic.

The 12-entry list is intentionally tight. If real verification reveals a missed class, expansion is a backward-compatible kit minor bump.

### 3.3 Bias ratio

**Default**: 90% from `.default`, 10% from `complexEdgeCases`. Implementation uses a Bernoulli sampler at trial-generation time.

**Configurability**: Phase 1 ships the 90/10 ratio as a hard-coded constant. If SwiftInfer's Phase 2 calibration reveals a different ratio (e.g., 80/20 surfaces more bugs without too many spurious "doesn't hold for edge cases" advisories), the ratio becomes an argument: `Gen<Complex<Double>>.edgeCaseBiased(edgeFraction: 0.20)`.

Not promising configurability in v2.1 keeps the kit-side scope contained.

-----

## 4. Implementation Sketch

The generator is a thin combination over existing primitives:

```swift
extension Gen where Value == Complex<Double> {

    public static var edgeCaseBiased: Gen<Complex<Double>> {
        Gen<Complex<Double>> { context in
            // 1 in 10 trials picks an edge case; the rest fall through
            // to the existing .default generator.
            let edgeFraction = 0.10
            let pick = Gen<Double>.uniform(in: 0..<1).run(in: context)
            if pick < edgeFraction {
                let index = Gen<Int>.uniform(in: 0..<complexEdgeCases.count)
                    .run(in: context)
                return complexEdgeCases[index]
            }
            return Gen<Complex<Double>>.default.run(in: context)
        }
    }

    public static var complexEdgeCases: [Complex<Double>] {
        [
            Complex(.nan, .nan),
            Complex(.nan, 0),
            // ... 10 more
        ]
    }
}
```

The pseudocode mirrors the kit's existing `Gen` combinator style. The actual implementation needs to thread the seed/context correctly per the kit's `Gen<T>` shape.

-----

## 5. Tests

Per the kit's standard test posture:

1. **Distribution test**: 10,000 trials, count edge-case hits. Expected range: 900–1100 (10% ± 1pp at this sample size). Tolerates the binomial-distribution noise; tightens on a 100,000-trial smoke run.
2. **Coverage test**: 1,000 trials, assert every entry in `complexEdgeCases` was hit at least once. (Probability of missing any single entry is `(11/12)^100 ≈ 1.5×10⁻⁴` per 100-trial budget; well under flake threshold.)
3. **Determinism test**: same seed produces same sequence of values across two `Gen` invocations.
4. **Default-path passthrough**: configurable trial that forces `pick >= 0.10` always; verify the values match `Gen<Complex<Double>>.default`'s output.

Aggregate: 4 new tests in `Tests/PropertyLawCoreTests/` (or equivalent kit directory).

-----

## 6. Versioning

**SwiftPropertyLaws**: minor bump to `2.1.0` (additive surface — no existing API changes).

**SwiftInferProperties**: `Package.swift` kit pin bumps from `2.0.0` to `2.1.0` in the v1.42 cycle that consumes `edgeCaseBiased`. The bump is straightforward — no API consumed today changes.

The two repos stay independently shippable. Kit `2.1.0` is useful on its own (any kit consumer can use the new generator) even if SwiftInferProperties' Phase 1 verify mode doesn't land for several more cycles.

-----

## 7. Open Decisions — RESOLVED 2026-05-11

1. **The 12-entry curated set**: ✅ **Approved as-is.** No additions or removals.

2. **Bias ratio**: ✅ **90/10.** Standard PBT default; produces sharper row-2 outcomes in the two-pass verification design.

3. **Shrinking representation**: ✅ **Deferred / value-only.** The counterexample report carries the failing `Complex<Double>` value; callers that need to know "edge case #N" do an index lookup against `complexEdgeCases`. If SwiftInfer's Phase 1 verify-mode reporting motivates a first-class index field later, the API can extend backward-compatibly (additive).

-----

## 8. Sequencing

1. ✅ Owner reviews this proposal; resolves the §7 open decisions. *(Done 2026-05-11.)*
2. ✅ Kit-side: land `Gen<Complex<Double>>.edgeCaseBiased` + tests + version bump to `2.1.0`. *(Done 2026-05-11 — `SwiftPropertyLaws` commit `ba19ab7`, tag `v2.1.0`. Shipped as opt-in `PropertyLawComplex` library product. 3 tests pass; full kit suite at 445/445; lint silent.)*

   **Departures from the original sketch:**

   - `edgeCaseBiased` is a **static func** (`Gen<Complex<Double>>.edgeCaseBiased()`), not a static `var`, to match the existing kit convention from `Gen<Double>.doubleWithNaN()` / `Gen<Float>.floatWithNaN()`. Callers write `.edgeCaseBiased()` with parens.
   - Return type is `Generator<Complex<Double>, some SendableSequenceType>` (the kit's actual `swift-property-based`-flavored shape) rather than the proposal-§3.1 sketch's `Gen<Complex<Double>>` shorthand.
   - Bias driver: a single seeded `Gen<Int>.int(in: 0 ..< 120)` call. Tags `0 ..< 12` map 1-to-1 to `complexEdgeCases` entries (so each entry is equally represented within the 10% slice); tags `12 ..< 120` fall through to a bounded-magnitude finite Complex value. The finite-path components use non-seeded `Double.random(in:)`, matching the existing `doubleWithNaN` convention; this means determinism is partial — the edge-vs-finite decision and which-edge-case selection are fully reproducible from the Xoshiro seed, but the finite-Complex values are not.
   - Carved out as a new library product (`PropertyLawComplex`) rather than landing in `PropertyLawKit` proper, so the kit's main line keeps a zero `swift-numerics` footprint. Downstream consumers `import PropertyLawComplex` explicitly. (User-chosen architecture; see SwiftInfer's tracking issue / git log for the AskUserQuestion prompt that surfaced the three options.)

3. SwiftInferProperties: v1.42 plan consumes the kit's `2.1.0` pin; Phase 1 verify subcommand uses `edgeCaseBiased` for the two-pass design. ~2–3 cycles of v1.4x work. *(Now the next step — `docs/v1.42 Calibration Plan.md`.)*
4. Phase 2+ kit-side: extend to `Double` / `Float` / `Complex<Float>` once Phase 1 establishes patterns.
