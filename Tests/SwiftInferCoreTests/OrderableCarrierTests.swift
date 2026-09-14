import Testing

@testable import SwiftInferCore

/// `monotonicity` sorts a drawn pair with `<`, so its carrier must be orderable (#454b).
///
/// ## The failure was badly disguised, which is why this is a guard and not a comment
///
/// `NoteFile.modificationDate(reported: Date?)` emitted a stub whose sample did
/// `lhs < rhs ? (lhs, rhs) : (rhs, lhs)` over a `Date?`. **`Optional` is not `Comparable`**, so
/// it does not typecheck — and Swift reports `cannot infer type of closure parameter 'pair'`,
/// naming the closure rather than the comparison. Nothing in that message says "optionality".
///
/// ## Declining follows practice rather than inventing it
///
/// `isFloatingPointEquatable` already excludes optionals one rule over, because *"optionality is
/// orthogonal … and would require a nullable-aware assertion wrapper in the emitted code"*. The
/// same is true of ordering. Unwrapping instead would change the law being stated, since the
/// optionality is the parameter's own.
@Suite("Orderable carriers — monotonicity needs `<`")
struct OrderableCarrierTests {

    /// The measured case.
    @Test func anOptionalCarrierIsNotOrderable() {
        #expect(FloatingPointEquatableTypes.isOrderableCarrier(typeText: "Date?") == false)
    }

    /// `Optional<T>` is the same type as `T?` and must answer the same way — a rule keyed on the
    /// `?` suffix alone would let the long spelling through.
    @Test func theLongOptionalSpellingIsAlsoRefused() {
        #expect(FloatingPointEquatableTypes.isOrderableCarrier(typeText: "Optional<Date>") == false)
    }

    /// **The control that keeps this a narrowing rather than a removal.** Monotonicity over an
    /// ordinary carrier must still emit — the template is not being disabled.
    @Test("ordinary carriers stay orderable", arguments: [
        "Int", "Double", "String", "Date", "[Int]", "  Int  "
    ])
    func ordinaryCarriersAreOrderable(typeText: String) {
        #expect(FloatingPointEquatableTypes.isOrderableCarrier(typeText: typeText))
    }

    /// ⚠ **Deliberately syntactic.** This answers "is this spelled Optional", not "is this
    /// `Comparable`". A non-optional non-`Comparable` carrier still passes and fails at compile
    /// time as it does today; closing that needs conformance resolution, which this is not — and
    /// the boundary is asserted so nobody reads the guard as stronger than it is.
    @Test func aNonComparableNonOptionalStillPasses() {
        #expect(FloatingPointEquatableTypes.isOrderableCarrier(typeText: "UserDefaults"))
    }
}
