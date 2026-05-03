import SwiftInferCore

/// One round-trip pattern surfaced by `AssertAfterTransformDetector`
/// against a sliced test body, packaged with the cross-validation key
/// the M1.5 CLI wiring threads into TemplateEngine's
/// `crossValidationFromTestLifter` parameter.
///
/// **Load-bearing invariant (M1.4):** the
/// `crossValidationKey` produced here from a test-side detection
/// matches — by `Hashable` equality — the `crossValidationKey` that
/// TemplateEngine's `RoundTripTemplate` produces for the same function
/// pair on the production side. The integration test in
/// `LiftedSuggestionCrossValidationKeyTests` asserts the round-trip
/// hash equality directly.
///
/// M1's LiftedSuggestion intentionally does NOT enter the main
/// `discover` suggestion stream — it contributes a key to the
/// cross-validation set only (open decision #3 default `(a)` in the
/// M1 plan). M2+ surfaces lifted suggestions in the discover output
/// alongside TemplateEngine's structural suggestions.
public struct LiftedSuggestion: Sendable, Equatable {

    /// Template ID for the surfaced pattern. M1 only ships
    /// `"round-trip"`; M2+ adds `"idempotence"`, `"commutativity"`, etc.
    public let templateName: String

    /// Cross-validation key — `(templateName, sortedCalleeNames)`. The
    /// M1.5 CLI wiring collects these into the `Set<CrossValidationKey>`
    /// fed to `TemplateRegistry.discover(crossValidationFromTestLifter:)`.
    public let crossValidationKey: CrossValidationKey

    /// The detection that produced this suggestion. Retained for
    /// diagnostics + future M2+ shape extensions; not used by the M1
    /// cross-validation matching path.
    public let detectedRoundTrip: DetectedRoundTrip

    public init(
        templateName: String,
        crossValidationKey: CrossValidationKey,
        detectedRoundTrip: DetectedRoundTrip
    ) {
        self.templateName = templateName
        self.crossValidationKey = crossValidationKey
        self.detectedRoundTrip = detectedRoundTrip
    }

    /// Builds a LiftedSuggestion from a `DetectedRoundTrip`. The
    /// cross-validation key is derived as `(templateName: "round-trip",
    /// calleeNames: [forwardCallee, backwardCallee])` with
    /// `CrossValidationKey.init` sorting the names lexicographically so
    /// the orientation `[encode, decode]` and `[decode, encode]` collide
    /// to the same key.
    public static func roundTrip(from detection: DetectedRoundTrip) -> LiftedSuggestion {
        let key = CrossValidationKey(
            templateName: "round-trip",
            calleeNames: [detection.forwardCallee, detection.backwardCallee]
        )
        return LiftedSuggestion(
            templateName: "round-trip",
            crossValidationKey: key,
            detectedRoundTrip: detection
        )
    }
}
