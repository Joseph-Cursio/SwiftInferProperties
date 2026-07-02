import Foundation

/// Shared code-generation helpers for the seeded verification-stub emitters.
///
/// `setupSection`, `mergedImports`, and `hex` were previously copy-pasted
/// across `RoundTripStubEmitter`, `IdempotenceStubEmitter`,
/// `CommutativityStubEmitter`, `AssociativityStubEmitter`, and
/// `StrategistDispatchEmitter` (byte-for-byte identical). Providing them as a
/// protocol mixin lets each emitter enum reuse the single implementation —
/// the unqualified call sites in the `+NonComplex` extension files resolve
/// here via `Self`.
protocol SeededStubEmitter {}

extension SeededStubEmitter {
    /// The NaN-reflexive equality oracle emitted into `Double` symmetric-property
    /// stubs (commutativity / associativity / round-trip / idempotence).
    ///
    /// `NaN != NaN` under IEEE 754 makes an *equational* property inevaluable on
    /// NaN even when both sides are the SAME result: a commutative `f` on NaN
    /// input yields NaN on both sides, but `nan == nan` is `false`, so the raw
    /// oracle reports a spurious counterexample — to reflexivity of `==`, not to
    /// the property. Two NaNs are the same result; compare accordingly. A
    /// genuinely asymmetric `f` (e.g. `min(nan,1)=nan` vs `min(1,nan)=1`) still
    /// fails: the sides differ, `both.isNaN` is false, and the approximate check
    /// rejects them.
    ///
    /// No `Complex` analogue is needed — swift-numerics canonicalizes every
    /// non-finite value to a single equal "point at infinity", so `Complex`'s
    /// own `==` / `isApproximatelyEqual` are already NaN-reflexive.
    static var nanReflexiveDoubleEquality: String {
        """
        // NaN-reflexive equality (NaN != NaN): two NaNs are the same result.
        func sameResult(_ lhs: Double, _ rhs: Double) -> Bool {
            (lhs.isNaN && rhs.isNaN) || lhs.isApproximatelyEqual(to: rhs)
        }
        """
    }

    /// Imports + optional preamble + a seeded `Xoshiro` RNG + `trials` count —
    /// the common header every seeded verification stub opens with.
    static func setupSection(
        importsBlock: String,
        seed: RoundTripStubEmitter.SeedHex,
        trials: Int,
        preamble: String = ""
    ) -> String {
        let preambleBlock = preamble.isEmpty ? "" : "\n\(preamble)\n"
        return """
        \(importsBlock)
        \(preambleBlock)
        var rng: any SeededRandomNumberGenerator = Xoshiro(seed: (
            0x\(hex(seed.stateA)),
            0x\(hex(seed.stateB)),
            0x\(hex(seed.stateC)),
            0x\(hex(seed.stateD))
        ))

        let trials = \(trials)
        """
    }

    /// Dedupe + sort `base` plus the trimmed, non-empty entries of `extra`,
    /// rendered as `import` lines. V1.149 — an entry prefixed with
    /// `@testable ` (e.g. `"@testable MyModule"`) renders as
    /// `@testable import MyModule`, so a stub can reach a user module's
    /// `internal` symbols; all other entries render as plain `import X`.
    static func mergedImports(base: [String], extra: [String]) -> String {
        let testablePrefix = "@testable "
        let extraTrimmed = extra
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let combined = Set(base + extraTrimmed).sorted()
        let lines = combined.map { entry -> String in
            entry.hasPrefix(testablePrefix)
                ? "@testable import \(entry.dropFirst(testablePrefix.count))"
                : "import \(entry)"
        }
        return lines.joined(separator: "\n")
    }

    static func hex(_ word: UInt64) -> String {
        String(word, radix: 16, uppercase: true)
    }
}
