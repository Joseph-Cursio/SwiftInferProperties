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
/// As of TestLifter M3.2, LiftedSuggestion records ALSO enter the main
/// `discover` suggestion stream — promoted to `Suggestion` via
/// `LiftedSuggestion.toSuggestion(typeName:returnType:origin:)` (M3.0)
/// and routed through `Discover+Pipeline` with type recovery (M3.1) +
/// `GeneratorSelection` + cross-validation suppression (M3.2). The
/// cross-validation key contribution path stays load-bearing for the
/// suppression filter — when both TemplateEngine and TestLifter
/// surface the same template/callee key, TemplateEngine's suggestion
/// wins and carries the +20 cross-validation signal; the lifted
/// promotion is dropped to avoid double-counting.
public struct LiftedSuggestion: Sendable, Equatable {

    /// Template ID for the surfaced pattern. M1 shipped `"round-trip"`;
    /// M2 added `"idempotence"` and `"commutativity"`. M5+ patterns
    /// (ordering / count-change / reduce-equivalence) extend without
    /// changing the field's shape.
    public let templateName: String

    /// Cross-validation key — `(templateName, sortedCalleeNames)`. The
    /// M1.5 CLI wiring collects these into the `Set<CrossValidationKey>`
    /// fed to `TemplateRegistry.discover(crossValidationFromTestLifter:)`.
    public let crossValidationKey: CrossValidationKey

    /// The detection that produced this suggestion. Retained for
    /// diagnostics + future stream-entry work; not used by the
    /// cross-validation matching path.
    public let pattern: DetectedPattern

    /// Originating test method's name + source location, populated by
    /// `TestLifter.discover` (M3.2 plumbing) so M3.3's accept-flow can
    /// name the writeout file + emit a provenance comment header.
    /// `nil` only for direct factory call sites in unit tests that
    /// don't have a `TestMethodSummary` in scope; the discover loop
    /// always supplies a non-nil origin.
    public let origin: LiftedOrigin?

    public init(
        templateName: String,
        crossValidationKey: CrossValidationKey,
        pattern: DetectedPattern,
        origin: LiftedOrigin? = nil
    ) {
        self.templateName = templateName
        self.crossValidationKey = crossValidationKey
        self.pattern = pattern
        self.origin = origin
    }

    /// Builds a LiftedSuggestion from a `DetectedRoundTrip`. The
    /// cross-validation key is derived as `(templateName: "round-trip",
    /// calleeNames: [forwardCallee, backwardCallee])` with
    /// `CrossValidationKey.init` sorting the names lexicographically so
    /// the orientation `[encode, decode]` and `[decode, encode]` collide
    /// to the same key.
    public static func roundTrip(
        from detection: DetectedRoundTrip,
        origin: LiftedOrigin? = nil
    ) -> LiftedSuggestion {
        let key = CrossValidationKey(
            templateName: "round-trip",
            calleeNames: [detection.forwardCallee, detection.backwardCallee]
        )
        return LiftedSuggestion(
            templateName: "round-trip",
            crossValidationKey: key,
            pattern: .roundTrip(detection),
            origin: origin
        )
    }

    /// Builds a LiftedSuggestion from a `DetectedIdempotence`. The
    /// cross-validation key is `(templateName: "idempotence",
    /// calleeNames: [calleeName])` — single-callee, mirrors the
    /// production-side `IdempotenceTemplate`'s one-Evidence shape.
    public static func idempotence(
        from detection: DetectedIdempotence,
        origin: LiftedOrigin? = nil
    ) -> LiftedSuggestion {
        let key = CrossValidationKey(
            templateName: "idempotence",
            calleeNames: [detection.calleeName]
        )
        return LiftedSuggestion(
            templateName: "idempotence",
            crossValidationKey: key,
            pattern: .idempotence(detection),
            origin: origin
        )
    }

    /// Builds a LiftedSuggestion from a `DetectedCommutativity`. The
    /// cross-validation key is `(templateName: "commutativity",
    /// calleeNames: [calleeName])` — single-callee, mirrors the
    /// production-side `CommutativityTemplate`'s one-Evidence shape.
    public static func commutativity(
        from detection: DetectedCommutativity,
        origin: LiftedOrigin? = nil
    ) -> LiftedSuggestion {
        let key = CrossValidationKey(
            templateName: "commutativity",
            calleeNames: [detection.calleeName]
        )
        return LiftedSuggestion(
            templateName: "commutativity",
            crossValidationKey: key,
            pattern: .commutativity(detection),
            origin: origin
        )
    }

    /// Builds a LiftedSuggestion from a `DetectedMonotonicity`. The
    /// cross-validation key is `(templateName: "monotonicity",
    /// calleeNames: [calleeName])` — single-callee, mirrors the
    /// production-side `MonotonicityTemplate`'s one-Evidence shape.
    /// The +20 cross-validation signal escalates a Possible-tier
    /// signature-side monotonicity claim (codomain alone, ~25 pts) to
    /// Likely, which is the user-visible payoff for the M5 wiring per
    /// PRD §4.2's 40-threshold.
    public static func monotonicity(
        from detection: DetectedMonotonicity,
        origin: LiftedOrigin? = nil
    ) -> LiftedSuggestion {
        let key = CrossValidationKey(
            templateName: "monotonicity",
            calleeNames: [detection.calleeName]
        )
        return LiftedSuggestion(
            templateName: "monotonicity",
            crossValidationKey: key,
            pattern: .monotonicity(detection),
            origin: origin
        )
    }

    /// Builds a LiftedSuggestion from a `DetectedCountInvariance`. The
    /// cross-validation key is `(templateName: "invariant-preservation",
    /// calleeNames: [calleeName])` — single-callee, mirrors the
    /// production-side `InvariantPreservationTemplate`'s shape.
    /// Production-side template is annotation-only (PRD §5.2 caveat); the
    /// +20 lights up only when the user has tagged the function with
    /// `@CheckProperty(.preservesInvariant(\\.count))`. Otherwise the
    /// LiftedSuggestion enters the visible discover stream as a
    /// freestanding count-invariant claim per M5 plan OD #1 (a).
    public static func countInvariance(
        from detection: DetectedCountInvariance,
        origin: LiftedOrigin? = nil
    ) -> LiftedSuggestion {
        let key = CrossValidationKey(
            templateName: "invariant-preservation",
            calleeNames: [detection.calleeName]
        )
        return LiftedSuggestion(
            templateName: "invariant-preservation",
            crossValidationKey: key,
            pattern: .countInvariance(detection),
            origin: origin
        )
    }

    /// Builds a LiftedSuggestion from a `DetectedReduceEquivalence`. The
    /// cross-validation key is `(templateName: "associativity",
    /// calleeNames: [opCalleeName])` — single-callee on the reducer
    /// operation, mirroring the production-side `AssociativityTemplate`'s
    /// one-Evidence shape.
    public static func reduceEquivalence(
        from detection: DetectedReduceEquivalence,
        origin: LiftedOrigin? = nil
    ) -> LiftedSuggestion {
        let key = CrossValidationKey(
            templateName: "associativity",
            calleeNames: [detection.opCalleeName]
        )
        return LiftedSuggestion(
            templateName: "associativity",
            crossValidationKey: key,
            pattern: .reduceEquivalence(detection),
            origin: origin
        )
    }
}

/// Discriminator for the detection that produced a `LiftedSuggestion`.
/// One case per TestLifter pattern. M5 added monotonicity /
/// countInvariance / reduceEquivalence; M5+ patterns extend the enum
/// without growing `LiftedSuggestion`'s storage shape.
public enum DetectedPattern: Sendable, Equatable {
    case roundTrip(DetectedRoundTrip)
    case idempotence(DetectedIdempotence)
    case commutativity(DetectedCommutativity)
    case monotonicity(DetectedMonotonicity)
    case countInvariance(DetectedCountInvariance)
    case reduceEquivalence(DetectedReduceEquivalence)
}

/// PRD §7.3 Assert-Ordering-Preserved → monotonicity. Carries the single
/// callee `f` whose preservation of input ordering is asserted, plus the
/// two argument identifiers driving the precondition `a < b` and the
/// `f(a) <= f(b)` (or `<`) result assertion. M5.1 detector populates;
/// M5.5 fan-out + LiftedTestEmitter consumes.
public struct DetectedMonotonicity: Equatable, Sendable {
    public let calleeName: String
    public let leftArgName: String
    public let rightArgName: String
    public let assertionLocation: SourceLocation

    public init(
        calleeName: String,
        leftArgName: String,
        rightArgName: String,
        assertionLocation: SourceLocation
    ) {
        self.calleeName = calleeName
        self.leftArgName = leftArgName
        self.rightArgName = rightArgName
        self.assertionLocation = assertionLocation
    }
}

/// PRD §7.3 Assert-Count-Change → invariant preservation. M5 hard-codes
/// the invariant keyPath to `\.count` (M5 plan OD #2 default); broader
/// keyPath generalization is M9 expanded-outputs territory. M5.2
/// detector populates; M5.5 fan-out + LiftedTestEmitter consumes.
public struct DetectedCountInvariance: Equatable, Sendable {
    public let calleeName: String
    public let inputBindingName: String
    public let assertionLocation: SourceLocation

    public init(
        calleeName: String,
        inputBindingName: String,
        assertionLocation: SourceLocation
    ) {
        self.calleeName = calleeName
        self.inputBindingName = inputBindingName
        self.assertionLocation = assertionLocation
    }
}

/// PRD §7.3 Assert-Reduce-Equivalence → associativity. The detected
/// shape is `xs.reduce(seed, op) == xs.reversed().reduce(seed, op)` —
/// `opCalleeName` is the reducer operation (function name or operator
/// text), `seedSource` is the textual seed expression (used for
/// same-seed invariant matching), `collectionBindingName` is the
/// collection binding the reduce is applied to. M5 plan OD #3 scopes
/// reordering to `xs.reversed()`; arbitrary permutations stay out of
/// scope. M5.3 detector populates; M5.5 fan-out + LiftedTestEmitter
/// consumes.
public struct DetectedReduceEquivalence: Equatable, Sendable {
    public let opCalleeName: String
    public let seedSource: String
    public let collectionBindingName: String
    public let assertionLocation: SourceLocation

    public init(
        opCalleeName: String,
        seedSource: String,
        collectionBindingName: String,
        assertionLocation: SourceLocation
    ) {
        self.opCalleeName = opCalleeName
        self.seedSource = seedSource
        self.collectionBindingName = collectionBindingName
        self.assertionLocation = assertionLocation
    }
}
