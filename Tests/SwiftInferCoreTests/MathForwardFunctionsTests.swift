@testable import SwiftInferCore
import Testing

@Suite("MathForwardFunctions — V1.21.C curated set + canonical-inverse-pair allowlist")
struct MathForwardFunctionsTests {

    @Test("Curated set includes the cycle-17-measured CM rejects (exp, log, sqrt)")
    func curatedSetIncludesMeasuredRejects() {
        for name in ["exp", "log", "sqrt"] {
            #expect(MathForwardFunctions.curated.contains(name), "\(name) should be in curated set")
        }
    }

    @Test("Curated set spans the elementary-functions families")
    func curatedSetSpansFamilies() {
        // Exponential family
        #expect(MathForwardFunctions.curated.contains("exp"))
        #expect(MathForwardFunctions.curated.contains("exp2"))
        #expect(MathForwardFunctions.curated.contains("expMinusOne"))
        // Logarithm family
        #expect(MathForwardFunctions.curated.contains("log"))
        #expect(MathForwardFunctions.curated.contains("log10"))
        #expect(MathForwardFunctions.curated.contains("log1p"))
        // Trig
        #expect(MathForwardFunctions.curated.contains("sin"))
        #expect(MathForwardFunctions.curated.contains("cos"))
        #expect(MathForwardFunctions.curated.contains("tan"))
        // Inverse trig
        #expect(MathForwardFunctions.curated.contains("asin"))
        #expect(MathForwardFunctions.curated.contains("acos"))
        #expect(MathForwardFunctions.curated.contains("atan"))
        // Hyperbolic
        #expect(MathForwardFunctions.curated.contains("sinh"))
        #expect(MathForwardFunctions.curated.contains("cosh"))
        #expect(MathForwardFunctions.curated.contains("tanh"))
        // Inverse hyperbolic
        #expect(MathForwardFunctions.curated.contains("asinh"))
        #expect(MathForwardFunctions.curated.contains("acosh"))
        #expect(MathForwardFunctions.curated.contains("atanh"))
        // Roots
        #expect(MathForwardFunctions.curated.contains("sqrt"))
        #expect(MathForwardFunctions.curated.contains("cbrt"))
    }

    @Test("Curated set excludes idempotent math functions (abs, negate)")
    func curatedSetExcludesIdempotent() {
        // abs(abs(x)) == abs(x) — IS idempotent on real inputs.
        // Excluding from curated keeps these legitimately surfacing.
        #expect(!MathForwardFunctions.curated.contains("abs"))
        #expect(!MathForwardFunctions.curated.contains("negate"))
    }

    @Test("isCanonicalInversePair: exp × log preserves in either orientation")
    func canonicalInversePairExpLog() {
        #expect(MathForwardFunctions.isCanonicalInversePair("exp", "log"))
        #expect(MathForwardFunctions.isCanonicalInversePair("log", "exp"))
    }

    @Test("isCanonicalInversePair: cycle-17 7 anchors all preserve in both orientations")
    func canonicalInversePairCycle17Anchors() {
        let anchors: [(String, String)] = [
            ("exp", "log"),
            ("cosh", "acosh"),
            ("sinh", "asinh"),
            ("tanh", "atanh"),
            ("cos", "acos"),
            ("sin", "asin"),
            ("tan", "atan")
        ]
        for (forward, inverse) in anchors {
            #expect(
                MathForwardFunctions.isCanonicalInversePair(forward, inverse),
                "\(forward) × \(inverse) should be canonical"
            )
            #expect(
                MathForwardFunctions.isCanonicalInversePair(inverse, forward),
                "\(inverse) × \(forward) should be canonical (orientation-insensitive)"
            )
        }
    }

    @Test("isCanonicalInversePair: cross-product noise (exp × cosh) does NOT preserve")
    func canonicalInversePairCrossProductRejected() {
        // Cycle-17 picks #12 (exp × cosh) reject — not in allowlist.
        #expect(!MathForwardFunctions.isCanonicalInversePair("exp", "cosh"))
        #expect(!MathForwardFunctions.isCanonicalInversePair("exp", "sqrt"))
        #expect(!MathForwardFunctions.isCanonicalInversePair("log", "sqrt"))
        #expect(!MathForwardFunctions.isCanonicalInversePair("sin", "cos"))
        #expect(!MathForwardFunctions.isCanonicalInversePair("sinh", "cosh"))
    }

    @Test("isCanonicalInversePair: numerics-extended numerical-variant pair preserves")
    func canonicalInversePairExpMinusOneLog1p() {
        // expMinusOne × log1p is the accurate-near-zero numerical-variant
        // pair the swift-numerics library exposes.
        #expect(MathForwardFunctions.isCanonicalInversePair("expMinusOne", "log1p"))
        #expect(MathForwardFunctions.isCanonicalInversePair("log1p", "expMinusOne"))
    }
}
