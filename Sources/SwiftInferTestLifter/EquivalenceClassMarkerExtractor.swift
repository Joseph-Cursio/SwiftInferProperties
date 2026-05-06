import SwiftInferCore
import SwiftSyntax

/// TestLifter M11.1 — pure-function pass that walks a paired
/// `[TestMethodSummary]` + `[SlicedTestBody]` corpus, classifies each
/// method against a curated marker table (per M11 plan OD #1, the v1.1
/// table is `Valid`/`Invalid` only), and aggregates positive/negative
/// matches into one `PartitionCandidate` per `(predicateName, markerPair)`
/// the M11.2 `PredicateEquivalenceClassDetector` then verifies and turns
/// into an `EquivalenceClassHint`.
///
/// **Hard contract (PRD §15):** never throws. Empty / unrecognized inputs
/// produce an empty result.
///
/// **Tokenization (M11 plan OD #7):** the marker is recognized as a
/// complete identifier sub-token of `methodName`. `testValid_simple`,
/// `testIsValidWithPlus`, and `testEmail_valid` all match `Valid`;
/// `testValidate_simple` does NOT (the token continues into `ate`).
/// Boundaries are camelCase + snake_case.
public enum EquivalenceClassMarkerExtractor {

    public static func extract(
        methods: [TestMethodSummary],
        slices: [SlicedTestBody],
        markerTable: [MarkerPair]
    ) -> [PartitionCandidate] {
        guard methods.count == slices.count else { return [] }
        var accumulator = PartitionAggregator()
        for (method, slice) in zip(methods, slices) {
            accumulator.observe(
                method: method, slice: slice, markerTable: markerTable
            )
        }
        return accumulator.finalize()
    }

    /// M13.2 unified overload — runs both the two-class scan (over
    /// `table.pairs`) and the N-class scan (over `table.sets`) in a
    /// single pass per method. The discover loop's pipeline-wiring
    /// (M13.3) consumes this signature once `Vocabulary.markerSets` is
    /// piped into `TestLifter.discover(in:)`.
    public static func extract(
        methods: [TestMethodSummary],
        slices: [SlicedTestBody],
        markerTable: MarkerTable
    ) -> [PartitionCandidate] {
        guard methods.count == slices.count else { return [] }
        var accumulator = PartitionAggregator()
        for (method, slice) in zip(methods, slices) {
            accumulator.observe(
                method: method, slice: slice, markerTable: markerTable.pairs
            )
            accumulator.observeNClass(
                method: method, slice: slice, markerSets: markerTable.sets
            )
        }
        return accumulator.finalize()
    }

    /// Classifies a single (method, slice) pair against ONE marker pair.
    /// Returns `nil` when the method's name carries no marker from this
    /// pair. When the name carries a marker but the polarity / predicate-
    /// shape doesn't match, returns `.outlier(...)` so the detector's
    /// "one outlier kills" rule fires per PRD §3.5 conservative bias.
    ///
    /// The outlier's `predicateName` is populated when the body still
    /// yielded a clean unary predicate call (i.e. only the polarity
    /// disagreed with the marker bucket) — the aggregator routes such
    /// outliers to the partition keyed on that predicate so the kill
    /// signal lands on the right candidate. Outliers from unparseable
    /// assertion shapes carry `nil` and are dropped during aggregation
    /// (they don't unambiguously belong to any partition).
    static func classify(
        method: TestMethodSummary,
        slice: SlicedTestBody,
        markerPair: MarkerPair
    ) -> Classification? {
        let tokens = tokenize(method.methodName)
        let hasPositive = tokens.contains(markerPair.positive)
        let hasNegative = tokens.contains(markerPair.negative)
        guard hasPositive || hasNegative else { return nil }
        guard !(hasPositive && hasNegative) else {
            return .outlier(predicateName: nil, reason: .ambiguousMarker)
        }
        let expectedPolarity: Polarity = hasPositive ? .positive : .negative
        guard let assertion = slice.assertion else {
            return .outlier(predicateName: nil, reason: .noTerminalAssertion)
        }
        guard let extracted = extractPredicate(from: assertion) else {
            return .outlier(predicateName: nil, reason: .nonPredicateAssertion)
        }
        guard extracted.polarity == expectedPolarity else {
            return .outlier(predicateName: extracted.predicateName, reason: .polarityMismatch)
        }
        return .matched(predicateName: extracted.predicateName, polarity: expectedPolarity)
    }

    /// Tokenizes a Swift identifier on camelCase + snake_case boundaries.
    /// `testIsValidWithPlus` → `["test", "Is", "Valid", "With", "Plus"]`;
    /// `testValidate_simple` → `["test", "Validate", "simple"]`. Per M11
    /// plan OD #7, this is the boundary algorithm that distinguishes
    /// `Valid` (matches) from `Validate` (does not).
    static func tokenize(_ identifier: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for character in identifier {
            if character == "_" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            if character.isUppercase, let last = current.last, last.isLowercase {
                tokens.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    /// Extracts `(predicateName, polarity)` from a recognized boolean
    /// assertion. Handles direct unary calls (`predicate(x)`) and the
    /// negated form (`!predicate(x)`); rejects compound boolean
    /// expressions, multi-arg comparisons, and non-boolean assertions.
    static func extractPredicate(
        from assertion: AssertionInvocation
    ) -> (predicateName: String, polarity: Polarity)? {
        switch assertion.kind {
        case .xctAssertTrue, .xctAssert:
            guard let first = assertion.arguments.first else { return nil }
            return interpretBooleanArgument(first, baseAssertedTrue: true)
        case .xctAssertFalse:
            guard let first = assertion.arguments.first else { return nil }
            return interpretBooleanArgument(first, baseAssertedTrue: false)
        case .expectMacro, .requireMacro:
            guard let first = assertion.arguments.first else { return nil }
            return interpretBooleanArgument(first, baseAssertedTrue: true)
        case .xctAssertEqual, .xctAssertNotNil,
                .xctAssertLessThan, .xctAssertLessThanOrEqual,
                .xctAssertNotEqual, .xctAssertGreaterThan,
                .xctAssertGreaterThanOrEqual:
            return nil
        }
    }

    private static func interpretBooleanArgument(
        _ expr: ExprSyntax,
        baseAssertedTrue: Bool
    ) -> (predicateName: String, polarity: Polarity)? {
        if let prefix = expr.as(PrefixOperatorExprSyntax.self),
           prefix.operator.text == "!" {
            guard let inner = unaryPredicateCall(in: ExprSyntax(prefix.expression)) else {
                return nil
            }
            return (inner, baseAssertedTrue ? .negative : .positive)
        }
        guard let predicateName = unaryPredicateCall(in: expr) else { return nil }
        return (predicateName, baseAssertedTrue ? .positive : .negative)
    }

    /// TestLifter M13.3 — `true` if the slice's terminal assertion
    /// uses the strict canonical form for syntactic-coverage detection:
    /// `XCTAssertTrue(predicate(x))` for positive sites or
    /// `XCTAssertFalse(predicate(x))` for negative sites, both without
    /// `!` prefix. The M11.1 detector aggregates per-bucket "all
    /// canonical?" booleans to decide `EquivalenceClassHint.coversDomain`.
    ///
    /// Strict by design — Swift Testing `#expect(predicate(x))` and
    /// `XCTAssert(predicate(x))` are NOT canonical because they don't
    /// syntactically pair with a `XCTAssertFalse` negative bucket. The
    /// plan's §"What M13 ships" axis 4 names XCTAssertTrue / XCTAssertFalse
    /// specifically.
    static func isCanonicalCoversDomainForm(
        assertion: AssertionInvocation?,
        polarity: Polarity
    ) -> Bool {
        guard let assertion else { return false }
        guard let firstArg = assertion.arguments.first else { return false }
        if let prefix = firstArg.as(PrefixOperatorExprSyntax.self),
           prefix.operator.text == "!" {
            return false
        }
        switch (assertion.kind, polarity) {
        case (.xctAssertTrue, .positive),
                (.xctAssertFalse, .negative):
            return true
        default:
            return false
        }
    }

    /// Internal-visibility (was `private` pre-M13.2) so the N-class
    /// extractor in `EquivalenceClassMarkerExtractor+NClass.swift` can
    /// share the unary-predicate parsing — the M13.2 N-class assertion
    /// shape `XCTAssertEqual(predicate(x), .case)` reuses this same
    /// inner call recognition for the predicate side.
    static func unaryPredicateCall(in expr: ExprSyntax) -> String? {
        // M11.2 — peek through `try`/`try!`/`try?` so corpora that
        // exercise a throwing predicate (e.g. `XCTAssertTrue(try! isValid(x))`)
        // still classify the inner call as the unary predicate site.
        // The detector's predicate-shape veto then fires on the
        // throwing `FunctionSummary` and emits a comment-only advisory.
        if let tryExpr = expr.as(TryExprSyntax.self) {
            return unaryPredicateCall(in: tryExpr.expression)
        }
        guard let call = expr.as(FunctionCallExprSyntax.self) else { return nil }
        guard call.arguments.count == 1 else { return nil }
        return trailingIdentifier(of: call.calledExpression)
    }

    /// Internal-visibility (was `private` pre-M13.2) so the N-class
    /// extractor can reuse the same trailing-identifier extraction.
    static func trailingIdentifier(of expr: ExprSyntax) -> String? {
        if let ident = expr.as(DeclReferenceExprSyntax.self) {
            return ident.baseName.text
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }
}

// `MarkerPair` was lifted to `SwiftInferCore.MarkerTable.swift` at M13.0
// so the CLI's `Vocabulary` schema and the TestLifter detectors share one
// source of truth. The constant `MarkerPair.defaultTable` (still
// `[Valid/Invalid]`) is preserved at the M13.0 cut and consumed by this
// extractor unchanged; M13.1's refactor switches the discover loop to
// consume `MarkerTable.curatedPairs` (the broader v1.x default).

/// Polarity surfaced by `EquivalenceClassMarkerExtractor.extractPredicate`
/// — the assertion's effective truth value over the predicate call. The
/// extractor combines the assertion's kind (`xctAssertTrue` /
/// `xctAssertFalse` / `expect` / `require`) with optional `!` negation in
/// the argument expression so `XCTAssertTrue(!isValid(x))` and
/// `XCTAssertFalse(isValid(x))` both classify as `.negative` (the M11.1
/// detector then matches polarity against the marker bucket — positive
/// marker expects `.positive`, negative marker expects `.negative`).
public enum Polarity: Sendable, Equatable {
    case positive
    case negative
}

/// One classified test method ready for partition aggregation. Either
/// the method matched the marker pair cleanly (becoming a `PartitionSite`),
/// or it carried a marker but the body failed one of the polarity /
/// predicate-shape checks (becoming an outlier — the M11.1 detector's
/// "one outlier kills" rule fires per PRD §3.5 conservative bias).
///
/// The outlier's `predicateName` is populated only when the body still
/// yielded a clean unary predicate call (i.e. polarity-mismatch). Other
/// outlier kinds — `noTerminalAssertion`, `nonPredicateAssertion`,
/// `ambiguousMarker` — carry `nil` and are dropped during aggregation
/// because they don't unambiguously belong to any partition.
public enum Classification: Sendable, Equatable {

    case matched(predicateName: String, polarity: Polarity)

    case outlier(predicateName: String?, reason: OutlierReason)

    var routingPredicateName: String? {
        switch self {
        case .matched(let name, _): return name
        case .outlier(let name, _): return name
        }
    }
}

/// Why a marker-bearing test method failed to become a `PartitionSite`.
/// Surfaced for diagnostics; the M11.1 detector treats any outlier as a
/// partition-kill signal regardless of reason.
public enum OutlierReason: Sendable, Equatable {

    /// Method's name carried BOTH the positive AND negative marker
    /// (e.g. `testValidInvalid_*`). Treated as outlier rather than
    /// double-counted to either bucket.
    case ambiguousMarker

    /// Slicer found no recognized terminal assertion in the method body.
    /// The method might be a setup helper or a non-property test.
    case noTerminalAssertion

    /// Terminal assertion was recognized but didn't yield a unary
    /// predicate call (e.g. `XCTAssertEqual`, compound boolean, multi-arg
    /// expression).
    case nonPredicateAssertion

    /// Marker bucket and assertion polarity disagreed (e.g. a `Valid`-
    /// marked test that asserts `XCTAssertFalse(predicate(x))`).
    case polarityMismatch
}

/// One verified positive- or negative-bucket site inside a
/// `PartitionCandidate`. Carries the originating method name for
/// diagnostics; the M11.1 detector uses bucket counts (not site detail)
/// to apply threshold + homogeneity.
public struct PartitionSite: Sendable, Equatable {

    public let methodName: String

    public init(methodName: String) {
        self.methodName = methodName
    }
}

/// One aggregated `(predicate, markerPair)` or `(predicate, markerSet)`
/// partition emitted by the extractor. The M11.1 / M13.2 detectors
/// consume one of these per call; `outlierSiteCount > 0` means at least
/// one marker-bearing method failed the polarity / shape / case-literal
/// checks and the partition will be killed by the conservative-bias
/// rule (PRD §3.5) regardless of how many clean sites the buckets hold.
///
/// **Carrier shape:** `markerPair` and `markerSet` are mutually
/// exclusive — exactly one is non-nil. M11/M13 two-class candidates
/// carry `markerPair` and populate `positiveSites` / `negativeSites`;
/// M13.2's N-class candidates carry `markerSet` and populate
/// `nClassBucketsByMarker`. The other field group stays empty / nil
/// for that candidate's variant. The M11.1 / M13.2 detectors guard on
/// the carrier shape and only fire on candidates carrying their
/// expected variant.
public struct PartitionCandidate: Sendable, Equatable {

    public let predicateName: String
    public let markerPair: MarkerPair?
    public let markerSet: MarkerSet?
    public let positiveSites: [PartitionSite]
    public let negativeSites: [PartitionSite]
    /// N-class per-marker bucket sites — non-nil only for candidates
    /// where `markerSet != nil`. Keyed by marker name from the marker
    /// set (verbatim, not lowercased — the detector consults the
    /// `MarkerSet.markers` order separately for ordering).
    public let nClassBucketsByMarker: [String: [PartitionSite]]?
    public let outlierSiteCount: Int
    /// M13.3 — `true` when every two-class site uses the canonical
    /// `XCTAssertTrue(predicate(x))` (positive) /
    /// `XCTAssertFalse(predicate(x))` (negative) form. The M11.1
    /// detector reads this to set `EquivalenceClassHint.coversDomain`.
    /// Defaults to `false`; only meaningful for two-class candidates.
    public let coversDomainSyntactic: Bool

    public init(
        predicateName: String,
        markerPair: MarkerPair? = nil,
        markerSet: MarkerSet? = nil,
        positiveSites: [PartitionSite] = [],
        negativeSites: [PartitionSite] = [],
        nClassBucketsByMarker: [String: [PartitionSite]]? = nil,
        outlierSiteCount: Int,
        coversDomainSyntactic: Bool = false
    ) {
        self.predicateName = predicateName
        self.markerPair = markerPair
        self.markerSet = markerSet
        self.positiveSites = positiveSites
        self.negativeSites = negativeSites
        self.nClassBucketsByMarker = nClassBucketsByMarker
        self.outlierSiteCount = outlierSiteCount
        self.coversDomainSyntactic = coversDomainSyntactic
    }
}

// `PartitionAggregator` (the streaming aggregator that the M11.2
// `TestLifter.discover(in:)` loop drives per-method) and its supporting
// internal types `PartitionKey` / `PartitionAccumulator` /
// `RankedCandidate` live in `PartitionAggregator.swift`. Split out at
// M13.1 to keep this file under SwiftLint's 400-line cap once the M13.1
// per-predicate ranking dedup landed.
