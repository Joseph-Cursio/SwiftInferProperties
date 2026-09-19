/// V1.31.A — curated set of type names that require approximate-equality
/// assertions (`isApproximatelyEqual(to:)`) rather than strict `==` when
/// emitting property-test stubs. Closes the **13-cycle carry-forward**
/// "FP approximate-equality template arm" (cycle-14 priority #4).
///
/// **Why this exists.** Cycle-25 + cycle-27 measured 8 of 8 sampled CM
/// canonical math forward-inverse round-trip pairs at Accept (`exp/log`,
/// `cosh/acosh`, `sinh/asinh`, `cos/acos`, `sin/asin`, `tan/atan`,
/// `tanh/atanh`). The properties are mathematically correct, but the
/// current `LiftedTestEmitter.roundTrip` emits a strict `==` assertion
/// that fails under IEEE 754 rounding. The emitted production tests would
/// fail even on canonical inverse pairs. Detecting FP types and routing
/// to `isApproximatelyEqual(to:)` (a uniform method available on swift-
/// numerics' `AlgebraicField` protocol covering `Real` + `Complex<Real>`)
/// produces compiling, passing property tests.
///
/// **Scope.** Covers stdlib floating-point types + swift-numerics
/// `Complex<Real>` variants. Project-specific FP wrapper types (e.g.,
/// `struct Money { var value: Double }`) are NOT auto-detected — the
/// supported extension path is project-vocabulary in future cycles.
///
/// Mechanism-class extension: introduces **class 16** — emit-time
/// equality-form dispatch (vs the inference-time mechanism classes 1-15).
/// First emit-side mechanism class in the loop.
public enum FloatingPointEquatableTypes {

    /// Curated type-name set requiring approximate equality.
    ///
    /// Includes:
    /// - **Real types**: stdlib `Double`, `Float`, `Float16`, `Float80`,
    ///   and the Foundation/UI `CGFloat`. All conform to `Numerics.Real`
    ///   via swift-numerics, which provides `isApproximatelyEqual(to:)`.
    /// - **Complex types**: the canonical swift-numerics `Complex`
    ///   container in its bare form, the fully-qualified
    ///   `ComplexModule.Complex` form (as it appears in qualified
    ///   discover output), and the canonical generic specializations
    ///   `Complex<Double>` + `Complex<Float>`. Generic parameters are
    ///   stripped at lookup time so `Complex<Double>` and
    ///   `Complex<RealType>` both match the bare `Complex` entry.
    public static let curated: Set<String> = [
        // Real types (Numerics.Real conforming)
        "Double",
        "Float",
        "Float16",
        "Float80",
        "CGFloat",
        // Complex types (AlgebraicField conforming via swift-numerics)
        "Complex",
        "ComplexModule.Complex"
    ]

    /// Returns `true` when `typeText` names a floating-point type that
    /// requires `isApproximatelyEqual(to:)`-form assertions in emitted
    /// property tests. Strips generic parameters before lookup so
    /// `Complex<Double>` and `Complex<RealType>` both resolve to the
    /// bare `Complex` entry in the curated set.
    ///
    /// Whether a carrier can be **ordered** with `<`, which `monotonicity` requires: it draws a
    /// pair and sorts it so the law can read `f(lo) <= f(hi)`.
    ///
    /// **An `Optional` is not `Comparable`**, and the failure is badly disguised: `lhs < rhs`
    /// over a `Date?` does not typecheck, and Swift reports `cannot infer type of closure
    /// parameter 'pair'` — an error naming the closure rather than the comparison, so it does
    /// not read as an optionality problem at all. Measured on `NoteFile.modificationDate(reported:
    /// Date?)`, which emitted a stub that could not build (#454).
    ///
    /// **Declining is the answer already established for this repo**, one line above: FP
    /// equality excludes optionals because *"optionality is orthogonal … and would require a
    /// nullable-aware assertion wrapper in the emitted code"*. The same is true of ordering, and
    /// the wrapper would be the same kind of thing. Unwrapping instead would change the law
    /// being stated, since the optionality is the parameter's own.
    ///
    /// **Nor is a collection or a tuple.** `Array`, `Set`, `Dictionary` and tuples never conform
    /// to `Comparable`, whatever their elements, so `[Int]` is refused by its spelling alone.
    /// Measured on the 2026-09-19 corpus funnel re-run: `total(_: [Int])` and `mean(_: [Double])`
    /// emitted stubs failing with `binary operator '<' cannot be applied to two '[Int]' operands`.
    ///
    /// Deliberately **syntactic**: it answers "is this spelled as something that can never be
    /// ordered", not "is this Comparable". A nominal type that is not `Comparable` needs the
    /// conformance index, which `UnorderedCarrierGate` reads on the accept path.
    public static func isOrderableCarrier(typeText: String) -> Bool {
        let trimmed = typeText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasSuffix("?"), !trimmed.hasPrefix("Optional<") else { return false }
        // `[T]` and `[K: V]` both start with a bracket; a tuple starts with a parenthesis.
        guard !trimmed.hasPrefix("["), !trimmed.hasPrefix("(") else { return false }
        let unorderedGenerics = ["Array<", "ArraySlice<", "ContiguousArray<", "Set<", "Dictionary<"]
        return !unorderedGenerics.contains { trimmed.hasPrefix($0) }
    }

    /// Whitespace-trim and generic-parameter-strip are applied uniformly.
    /// Optional types (`Double?`) intentionally return `false` —
    /// optionality is orthogonal to FP equality and would require a
    /// nullable-aware assertion wrapper in the emitted code.
    public static func isFloatingPointEquatable(typeText: String) -> Bool {
        let trimmed = typeText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasSuffix("?") else {
            return false
        }
        let stripped = stripGenericParameters(trimmed)
        return curated.contains(stripped)
    }

    /// Strips a balanced trailing `<...>` from a type name. Used so
    /// `Complex<Double>` → `Complex`, `Complex<RealType>` → `Complex`.
    /// Returns the input unchanged when no balanced angle bracket pair
    /// is present.
    static func stripGenericParameters(_ typeText: String) -> String {
        guard let openIdx = typeText.firstIndex(of: "<"),
              typeText.last == ">" else {
            return typeText
        }
        return String(typeText[..<openIdx])
    }
}
