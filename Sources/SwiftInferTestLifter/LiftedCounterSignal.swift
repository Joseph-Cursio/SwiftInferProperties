import SwiftInferCore

/// One asymmetric-assertion counter-signal surfaced by TestLifter
/// against a sliced test body — a negative-form mirror of one of the
/// six positive `LiftedSuggestion` patterns. Carries the same
/// `crossValidationKey` the positive detectors produce (template +
/// sorted callee names) so the M7.0 seam can match TE-side
/// suggestions by key + apply the `-25 .asymmetricAssertion` Signal.
///
/// **Load-bearing invariant (M7.0):** the `crossValidationKey`
/// produced here from a negative test-side detection matches — by
/// `Hashable` equality — the `crossValidationKey` of the matching
/// TemplateEngine template's suggestion for the same callee. This
/// is the same invariant `LiftedSuggestion` carries on the positive
/// side; M7.0 reuses the `CrossValidationKey` shape so the same
/// seam infrastructure handles both polarities.
///
/// On the lifted side, a counter-signal whose key matches a
/// promoted lifted suggestion's key suppresses the lifted suggestion
/// entirely (filter, not demote — per M7 plan OD #1). The user's
/// explicit negative assertion is dispositive: we don't surface a
/// suggestion the test author has actively contradicted.
public struct LiftedCounterSignal: Sendable, Equatable {

    /// Template ID for the contradicted pattern. Matches the
    /// `templateName` of the corresponding positive
    /// `LiftedSuggestion`: `"round-trip"` / `"idempotence"` /
    /// `"commutativity"` / `"monotonicity"` /
    /// `"invariant-preservation"` / `"associativity"`.
    public let templateName: String

    /// Cross-validation key — `(templateName, sortedCalleeNames)`.
    /// Same shape as `LiftedSuggestion.crossValidationKey`; the
    /// M7.0 seam matches against TE-side suggestion keys directly.
    public let crossValidationKey: CrossValidationKey

    /// The detection that produced this counter-signal. Retained
    /// for diagnostics; not used by the seam matching path.
    public let pattern: DetectedAsymmetricAssertion

    /// Originating test method's name + source location, populated
    /// by `TestLifter.discover`'s seventh-detector loop (M7.0
    /// plumbing) — same shape `LiftedSuggestion.origin` carries on
    /// the positive side.
    public let origin: LiftedOrigin?

    public init(
        templateName: String,
        crossValidationKey: CrossValidationKey,
        pattern: DetectedAsymmetricAssertion,
        origin: LiftedOrigin? = nil
    ) {
        self.templateName = templateName
        self.crossValidationKey = crossValidationKey
        self.pattern = pattern
        self.origin = origin
    }

    /// Builds a counter-signal record contradicting the round-trip
    /// pattern for the matching `(forwardCallee, backwardCallee)`
    /// pair. Sorted-name canonicalization happens inside
    /// `CrossValidationKey.init`.
    public static func roundTrip(
        forwardCallee: String,
        backwardCallee: String,
        sourceLocation: SourceLocation,
        origin: LiftedOrigin? = nil
    ) -> LiftedCounterSignal {
        let key = CrossValidationKey(
            templateName: "round-trip",
            calleeNames: [forwardCallee, backwardCallee]
        )
        return LiftedCounterSignal(
            templateName: "round-trip",
            crossValidationKey: key,
            pattern: .roundTrip(forwardCallee: forwardCallee, backwardCallee: backwardCallee),
            origin: origin
        )
    }

    public static func idempotence(
        calleeName: String,
        sourceLocation: SourceLocation,
        origin: LiftedOrigin? = nil
    ) -> LiftedCounterSignal {
        let key = CrossValidationKey(
            templateName: "idempotence",
            calleeNames: [calleeName]
        )
        return LiftedCounterSignal(
            templateName: "idempotence",
            crossValidationKey: key,
            pattern: .idempotence(calleeName: calleeName),
            origin: origin
        )
    }

    public static func commutativity(
        calleeName: String,
        sourceLocation: SourceLocation,
        origin: LiftedOrigin? = nil
    ) -> LiftedCounterSignal {
        let key = CrossValidationKey(
            templateName: "commutativity",
            calleeNames: [calleeName]
        )
        return LiftedCounterSignal(
            templateName: "commutativity",
            crossValidationKey: key,
            pattern: .commutativity(calleeName: calleeName),
            origin: origin
        )
    }

    public static func monotonicity(
        calleeName: String,
        sourceLocation: SourceLocation,
        origin: LiftedOrigin? = nil
    ) -> LiftedCounterSignal {
        let key = CrossValidationKey(
            templateName: "monotonicity",
            calleeNames: [calleeName]
        )
        return LiftedCounterSignal(
            templateName: "monotonicity",
            crossValidationKey: key,
            pattern: .monotonicity(calleeName: calleeName),
            origin: origin
        )
    }

    public static func countInvariance(
        calleeName: String,
        sourceLocation: SourceLocation,
        origin: LiftedOrigin? = nil
    ) -> LiftedCounterSignal {
        let key = CrossValidationKey(
            templateName: "invariant-preservation",
            calleeNames: [calleeName]
        )
        return LiftedCounterSignal(
            templateName: "invariant-preservation",
            crossValidationKey: key,
            pattern: .countInvariance(calleeName: calleeName),
            origin: origin
        )
    }

    public static func reduceEquivalence(
        opCalleeName: String,
        sourceLocation: SourceLocation,
        origin: LiftedOrigin? = nil
    ) -> LiftedCounterSignal {
        let key = CrossValidationKey(
            templateName: "associativity",
            calleeNames: [opCalleeName]
        )
        return LiftedCounterSignal(
            templateName: "associativity",
            crossValidationKey: key,
            pattern: .reduceEquivalence(opCalleeName: opCalleeName),
            origin: origin
        )
    }
}

/// Discriminator for which positive pattern the counter-signal
/// contradicts. Carries just the callee names (not the full
/// detection record) since counter-signals are matched by key only;
/// the detail is for diagnostics.
public enum DetectedAsymmetricAssertion: Sendable, Equatable {
    case roundTrip(forwardCallee: String, backwardCallee: String)
    case idempotence(calleeName: String)
    case commutativity(calleeName: String)
    case monotonicity(calleeName: String)
    case countInvariance(calleeName: String)
    case reduceEquivalence(opCalleeName: String)
}
