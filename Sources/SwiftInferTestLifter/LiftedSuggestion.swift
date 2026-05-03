import SwiftInferCore

/// One pattern surfaced by TestLifter against a sliced test body,
/// packaged with the cross-validation key the M1.5 CLI wiring threads
/// into TemplateEngine's `crossValidationFromTestLifter` parameter.
///
/// **Load-bearing invariant (M1.4):** the `crossValidationKey` produced
/// here from a test-side detection matches — by `Hashable` equality —
/// the `crossValidationKey` that the matching TemplateEngine template
/// produces for the same function (or function pair) on the production
/// side. The integration tests in `LiftedSuggestionTests` and
/// `SwiftInferIntegrationTests` assert the hash equality directly.
///
/// LiftedSuggestion intentionally does NOT enter the main `discover`
/// suggestion stream through M2 — it contributes a key to the
/// cross-validation set only (M2 plan's open decision #1 default `(a)`).
/// M3+ surfaces lifted suggestions in the discover output alongside
/// TemplateEngine's structural suggestions.
public struct LiftedSuggestion: Sendable, Equatable {

    /// Template ID for the surfaced pattern. M1 shipped `"round-trip"`;
    /// M2 adds `"idempotence"` and `"commutativity"`.
    public let templateName: String

    /// Cross-validation key — `(templateName, sortedCalleeNames)`. The
    /// M1.5 CLI wiring collects these into the `Set<CrossValidationKey>`
    /// fed to `TemplateRegistry.discover(crossValidationFromTestLifter:)`.
    public let crossValidationKey: CrossValidationKey

    /// The detection that produced this suggestion. Retained for
    /// diagnostics + future stream-entry work; not used by the
    /// cross-validation matching path.
    public let pattern: DetectedPattern

    public init(
        templateName: String,
        crossValidationKey: CrossValidationKey,
        pattern: DetectedPattern
    ) {
        self.templateName = templateName
        self.crossValidationKey = crossValidationKey
        self.pattern = pattern
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
            pattern: .roundTrip(detection)
        )
    }
}

/// Discriminator for the detection that produced a `LiftedSuggestion`.
/// One case per TestLifter pattern. M2.0 ships `.roundTrip` only;
/// M2.1 adds `.idempotence`, M2.2 adds `.commutativity`. M5+ patterns
/// (ordering, count-change, reduce-equivalence) extend the enum
/// without growing `LiftedSuggestion`'s storage shape.
public enum DetectedPattern: Sendable, Equatable {
    case roundTrip(DetectedRoundTrip)
}
