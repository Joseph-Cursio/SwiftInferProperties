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

extension LiftedTestEmitter {

    /// The property closure's binding for a MULTI-ARGUMENT stub: `(args: (A, B, C))`, or a bare
    /// `args` when the types are not available.
    ///
    /// **Why the annotation, and why it is the same fix `makeTestStub` already applies.** A tuple
    /// parameter has nothing to anchor it: its type comes from the `sample` closure's return,
    /// which is a tuple of large generic expressions — a four-arm `Gen.frequency`, a `zip` of
    /// seven generators `map`ped into a struct. Swift gives up with *cannot infer type of closure
    /// parameter 'args' without a type annotation*. `makeTestStub` supplies `carrierType` for the
    /// one-value form for exactly this reason, measured on `htmlEscaped_idempotence`; the
    /// multi-argument form never got it (#498).
    ///
    /// ⚠ **This frees far fewer stubs than fail this way, and the issue says so.** 288 stubs hit
    /// that error across the 19 corpus-funnel repositories and **269 of them also carry a `.todo`
    /// generator** — a `Foo.gen()` that does not exist — so the annotation changes their error
    /// rather than removing it. That is the point: today the reader is told a closure parameter
    /// cannot be inferred when the real problem is named three lines above, in a comment the
    /// compiler never reaches. *A refuter that fires first hides every refuter behind it.*
    ///
    /// Falls back to the bare binding when `argumentTypes` is empty or disagrees with the
    /// generator count, so a caller that cannot supply types emits exactly what it emitted before.
    static func tupleBinding(argumentTypes: [String], count: Int) -> String {
        guard argumentTypes.count == count, !argumentTypes.isEmpty else { return "args" }
        return "(args: (\(argumentTypes.joined(separator: ", "))))"
    }
}
