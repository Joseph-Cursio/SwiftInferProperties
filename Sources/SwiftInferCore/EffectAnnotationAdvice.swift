/// Advisory record recommending a `/// @lint.effect pure` annotation on a
/// function that `SoundPurity` infers is referentially transparent.
///
/// This is **not** a property-test `Suggestion`. It carries no generator,
/// sampling state, score, or accept-flow stub — emitting it through the
/// property-test pipeline would mean a fabricated `Score`/`GeneratorMetadata`
/// and a dead-end in the templateName-driven accept/verify switches. Instead it
/// rides a separate advisory channel (`DiscoverArtifacts.effectAnnotations`)
/// and renders as its own discover section.
///
/// The verdict is computed once, at scan time, where the `FunctionDeclSyntax`
/// is live (`FunctionSummary.isInferredPure`); this record is the rendered
/// form, built for each function the scan flagged pure.
public struct EffectAnnotationAdvice: Sendable, Equatable {

    /// Human-facing call shape with parameter labels, e.g. `clamp(_:into:)`.
    public let displayName: String

    /// Rendered type signature, e.g. `(Int, Range<Int>) -> Int`.
    public let signature: String

    /// File-relative location of the function's `func` keyword.
    public let location: SourceLocation

    /// The annotation line to add above the declaration. Always the `pure`
    /// tier — `SoundPurity` only ever yields `Effect.pure`.
    public let recommendedAnnotation: String

    /// One-line justification for the human reviewer.
    public let rationale: String

    public init(
        displayName: String,
        signature: String,
        location: SourceLocation,
        recommendedAnnotation: String = "/// @lint.effect pure",
        rationale: String = "Inferred referentially transparent "
            + "(no side effects, deterministic, total) by SoundPurity — "
            + "ReducerPurity and the shared PurityInferrer both agree."
    ) {
        self.displayName = displayName
        self.signature = signature
        self.location = location
        self.recommendedAnnotation = recommendedAnnotation
        self.rationale = rationale
    }
}
