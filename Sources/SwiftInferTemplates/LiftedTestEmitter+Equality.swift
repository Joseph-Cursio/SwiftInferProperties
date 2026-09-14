import SwiftInferCore

/// The equality assertion an emitted law uses, and the helper the approximate form needs.
///
/// Split out of `LiftedTestEmitter.swift` when that file passed SwiftLint's 400-line ceiling —
/// the same move that produced `+Totality` and `+Generators`. It sits apart for a reason beyond
/// length: this is the one place the emitter writes a **declaration** into the file rather than
/// an expression, which is what closing #454 required.
extension LiftedTestEmitter {

    /// V1.31.B equality assertion. `.strict` → `lhs == rhs`; `.approximate` → a relative-tolerance
    /// comparison, for FP types where IEEE 754 rounding makes strict `==` impractical.
    ///
    /// ## The approximate arm used to name a method no emitted file could reach
    ///
    /// It rendered `lhs.isApproximatelyEqual(to: rhs)`, which is **swift-numerics**. This comment
    /// used to say *"Emitted test files need `import Numerics` for the approximate form"* — and
    /// nothing emitted that import, nor could it: `PropertyLawKit` links only `PropertyBased`,
    /// deliberately, so the main kit line keeps a zero swift-numerics footprint.
    ///
    /// **So the arm had never produced a compiling stub, for any of its six carriers, since
    /// V1.31.A.** Proven on `Double` with exactly a stub's imports, not inferred from `CGFloat`
    /// alone — `error: value of type 'Double' has no member 'isApproximatelyEqual'` (#454).
    ///
    /// ## Why an inline helper and not one of the three alternatives
    ///
    /// - **`floatSameResult`** is stdlib-only and already in the kit, and is exact equality plus
    ///   NaN reflexivity with **no tolerance term**. It compiles and still fails the 8-of-8
    ///   canonical `exp/log`-style round trips this arm exists for, trading one broken outcome
    ///   for another.
    /// - **`import Numerics`** compiles and breaks every subject that does not already depend on
    ///   swift-numerics — the same reasoning that makes `--extra-import` opt-in.
    /// - **Strict `==`** is what the arm was built to replace.
    ///
    /// The helper is emitted into the file that needs it, so the stub carries no dependency it
    /// cannot assume. `private` at file scope, so two stubs in one target cannot collide.
    static func equalityExpression(
        lhs: String,
        rhs: String,
        kind: EqualityKind
    ) -> String {
        switch kind {
        case .strict:
            return "\(lhs) == \(rhs)"

        case .approximate:
            return "approximatelyEqual(\(lhs), \(rhs))"
        }
    }

    /// The relative-tolerance comparison emitted alongside an `.approximate` assertion.
    ///
    /// **Named as a free function rather than an extension method**, so it cannot be confused
    /// with — or ambiguous against — swift-numerics' `isApproximatelyEqual(to:)` in a subject
    /// that *does* depend on it.
    ///
    /// The tolerance is `ulpOfOne.squareRoot()`, which is swift-numerics' own default relative
    /// tolerance: this arm was reaching for that method, so matching its default preserves the
    /// intent rather than inventing a looser or tighter bound.
    ///
    /// Three cases are handled before the tolerance, and each is a real float value a generator
    /// produces: exact equality settles `±0` and `±infinity`; NaN is made reflexive, matching the
    /// kit's own `floatSameResult`, because a law over a partial function otherwise fails on an
    /// input neither side chose; and a non-finite delta cannot be under any bound.
    static let approximateEqualityHelper = """

        /// Relative-tolerance equality, emitted inline so this file needs no swift-numerics
        /// dependency. Tolerance matches that library's default (`ulpOfOne.squareRoot()`).
        private func approximatelyEqual<Value: FloatingPoint>(_ lhs: Value, _ rhs: Value) -> Bool {
            if lhs == rhs { return true }
            if lhs.isNaN, rhs.isNaN { return true }
            let delta = (lhs - rhs).magnitude
            let scale = Swift.max(lhs.magnitude, rhs.magnitude)
            return delta.isFinite && delta <= scale * Value.ulpOfOne.squareRoot()
        }
        """

    /// `stub` with the approximate-equality helper appended when the stub uses it.
    static func withApproximateEqualityHelper(_ stub: String, kind: EqualityKind) -> String {
        guard kind == .approximate else { return stub }
        return stub + "\n" + approximateEqualityHelper
    }
}
