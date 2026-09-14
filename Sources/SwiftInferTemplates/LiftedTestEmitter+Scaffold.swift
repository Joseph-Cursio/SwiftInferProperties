import SwiftInferCore

/// The per-arm scaffold builder, split out of `LiftedTestEmitter.swift` for its length ceiling.
///
/// It sits apart for a reason beyond length: this is where the emitted **property closure** is
/// shaped, and the annotation it carries is the difference between a receiver-form law that
/// builds and one the type-checker gives up on.
extension LiftedTestEmitter {

    /// - Parameter carrierType: the type the generator produces, used to **annotate the property
    ///   closure's parameter**. Optional so existing callers are unchanged.
    ///
    /// ## Why the annotation, and why it is not cosmetic
    ///
    /// `{ value in value.htmlEscaped.htmlEscaped == value.htmlEscaped }` gives the type-checker
    /// nothing to anchor `value` on: the generator is a four-arm `Gen.frequency` with `map` and
    /// `zip` inside it, the property is generic over the backend's `Input`, and the body is a
    /// chain of member lookups. Swift gives up — **`the compiler is unable to type-check this
    /// expression in reasonable time`** — and the emitted file does not build.
    ///
    /// A *call* form anchors it for free: `WikilinkParser.parse(value)` pins `value` to the
    /// parameter's type, which is why every stub emitted before receiver-form laws existed
    /// compiled. The receiver form has no such anchor, so it is supplied.
    ///
    /// **This is the `12-arm + chain` class CLAUDE.md records** — an expression that compiles in
    /// one shape and exceeds the solver's budget in another, with nothing about the law wrong.
    /// Measured: `htmlEscaped_idempotence` fails to build without it and builds with it.
    /// Module-internal rather than file-private since the split: the arms that call it live in
    ///  and it lives here, which is the same reason
    /// `makeTestStubExpression` is already internal.
    static func makeTestStub(
        testFunctionName: String,
        seed: SamplingSeed.Value,
        generator: String,
        propertyExpression: String,
        failureLabel: String,
        carrierType: String? = nil
    ) -> String {
        let sample = "{ rng in (\(generator)).run(using: &rng) }"
        let binding = carrierType.map { "(value: \($0))" } ?? "value"
        let property = "{ \(binding) in \(propertyExpression) }"
        return makeTestStubExpression(
            testFunctionName: testFunctionName,
            seed: seed,
            sampleExpression: sample,
            propertyExpression: property,
            failureLabel: failureLabel
        )
    }
}
