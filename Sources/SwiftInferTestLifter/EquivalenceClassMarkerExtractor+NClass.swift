import SwiftInferCore
import SwiftSyntax

/// TestLifter M13.2 — N-class classify pass that complements the M11.1
/// two-class pass in `EquivalenceClassMarkerExtractor.swift`. Recognizes
/// the `XCTAssertEqual(predicate(x), .case)` (or
/// `#expect(predicate(x) == .case)`) assertion shape and partitions test
/// methods into N buckets keyed by `MarkerSet.markers`.
///
/// **Same conservative-bias posture as M11.1:** any marker-bearing
/// method that fails the assertion-shape / case-literal checks becomes
/// an outlier; the M13.2 detector kills the partition on outlierCount > 0.
extension EquivalenceClassMarkerExtractor {

    /// Classifies a single (method, slice) pair against ONE marker set.
    /// Returns `nil` when the method's name carries no marker from the
    /// set. When the name carries a marker but the assertion shape /
    /// case literal doesn't match, returns `.outlier(...)` so the
    /// detector's "one outlier kills" rule fires.
    ///
    /// **Marker matching:** identifier-token match against
    /// `markerSet.markers`, case-insensitive (M13 plan OD #4). The
    /// matched marker is returned in its canonical form from the
    /// `MarkerSet` so the aggregator keys on stable text.
    static func classifyNClass(
        method: TestMethodSummary,
        slice: SlicedTestBody,
        markerSet: MarkerSet
    ) -> NClassClassification? {
        let tokens = tokenize(method.methodName)
        let lowercaseTokens = Set(tokens.map { $0.lowercased() })
        let matchedMarkers = markerSet.markers.filter { marker in
            lowercaseTokens.contains(marker.lowercased())
        }
        guard !matchedMarkers.isEmpty else { return nil }
        guard matchedMarkers.count == 1 else {
            return .outlier(predicateName: nil, reason: .ambiguousMarker)
        }
        let marker = matchedMarkers[0]
        guard let assertion = slice.assertion else {
            return .outlier(predicateName: nil, reason: .noTerminalAssertion)
        }
        guard let extracted = extractNClassPredicateAndCase(from: assertion) else {
            return .outlier(predicateName: nil, reason: .nonEqualityAssertion)
        }
        guard extracted.caseLiteral.caseInsensitiveCompare(marker) == .orderedSame else {
            return .outlier(
                predicateName: extracted.predicateName,
                reason: .caseLiteralMismatch
            )
        }
        return .matched(
            predicateName: extracted.predicateName,
            marker: marker
        )
    }

    /// Extracts `(predicateName, caseLiteral)` from an N-class assertion
    /// shape. Recognizes:
    /// - `XCTAssertEqual(predicate(x), .case)` and the symmetric
    ///   `XCTAssertEqual(.case, predicate(x))`.
    /// - `#expect(predicate(x) == .case)` and the symmetric
    ///   `#expect(.case == predicate(x))` — both `SequenceExprSyntax`
    ///   (raw parse) and `InfixOperatorExprSyntax` (folded) variants
    ///   handled, mirroring `AssertSymmetryDetector`'s approach.
    /// - `#require(predicate(x) == .case)` (same posture).
    ///
    /// Returns `nil` for any other assertion shape.
    static func extractNClassPredicateAndCase(
        from assertion: AssertionInvocation
    ) -> (predicateName: String, caseLiteral: String)? {
        switch assertion.kind {
        case .xctAssertEqual:
            guard assertion.arguments.count >= 2 else { return nil }
            return matchPredicateAndCase(
                lhs: assertion.arguments[0],
                rhs: assertion.arguments[1]
            )
        case .expectMacro, .requireMacro:
            guard let first = assertion.arguments.first else { return nil }
            return matchPredicateAndCaseInEqualityExpression(first)
        case .xctAssertTrue, .xctAssert, .xctAssertFalse,
                .xctAssertNotNil, .xctAssertLessThan,
                .xctAssertLessThanOrEqual, .xctAssertNotEqual,
                .xctAssertGreaterThan, .xctAssertGreaterThanOrEqual:
            return nil
        }
    }

    /// Recognizes `lhs == rhs` in either the raw `SequenceExprSyntax`
    /// form (parser output) or the folded `InfixOperatorExprSyntax` form
    /// (post operator-precedence-pass output). Returns the predicate +
    /// case match if either side resolves to `(predicate(x), .case)`.
    private static func matchPredicateAndCaseInEqualityExpression(
        _ expr: ExprSyntax
    ) -> (predicateName: String, caseLiteral: String)? {
        if let sequence = expr.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            guard elements.count == 3,
                  let opExpr = elements[1].as(BinaryOperatorExprSyntax.self),
                  opExpr.operator.text == "==" else { return nil }
            return matchPredicateAndCase(lhs: elements[0], rhs: elements[2])
        }
        if let infix = expr.as(InfixOperatorExprSyntax.self),
           let opExpr = infix.operator.as(BinaryOperatorExprSyntax.self),
           opExpr.operator.text == "==" {
            return matchPredicateAndCase(
                lhs: ExprSyntax(infix.leftOperand),
                rhs: ExprSyntax(infix.rightOperand)
            )
        }
        return nil
    }

    /// Tries to match `(predicate(x), .case)` in either argument
    /// position — the N-class shape is symmetric across `==`.
    private static func matchPredicateAndCase(
        lhs: ExprSyntax,
        rhs: ExprSyntax
    ) -> (predicateName: String, caseLiteral: String)? {
        if let predicate = unaryPredicateCall(in: lhs),
           let literal = caseLiteralIdentifier(in: rhs) {
            return (predicate, literal)
        }
        if let predicate = unaryPredicateCall(in: rhs),
           let literal = caseLiteralIdentifier(in: lhs) {
            return (predicate, literal)
        }
        return nil
    }

    /// Recognizes a leading-dot enum case reference like `.small` —
    /// SwiftSyntax models this as `MemberAccessExprSyntax` with no base.
    /// Returns the case identifier text (`"small"`).
    private static func caseLiteralIdentifier(in expr: ExprSyntax) -> String? {
        guard let member = expr.as(MemberAccessExprSyntax.self),
              member.base == nil else { return nil }
        return member.declName.baseName.text
    }
}

/// One classified test method ready for N-class partition aggregation.
/// Mirrors M11.1's `Classification` shape with N-class-specific outlier
/// reasons (marker-set-based assertion shape, case-literal mismatch).
public enum NClassClassification: Sendable, Equatable {

    case matched(predicateName: String, marker: String)

    case outlier(predicateName: String?, reason: NClassOutlierReason)

    var routingPredicateName: String? {
        switch self {
        case .matched(let name, _): return name
        case .outlier(let name, _): return name
        }
    }
}

/// Why an N-class marker-bearing test method failed to become a
/// matched site. Surfaced for diagnostics; the M13.2 detector treats any
/// outlier as a partition-kill signal regardless of reason (PRD §3.5
/// conservative bias).
public enum NClassOutlierReason: Sendable, Equatable {

    /// Method's name carried multiple markers from the same marker set
    /// (e.g. `testSmallLarge_*` against `MarkerSet(markers: ["Small", "Medium", "Large"])`).
    /// Treated as outlier rather than double-counting to either bucket.
    case ambiguousMarker

    /// Slicer found no recognized terminal assertion in the method body.
    case noTerminalAssertion

    /// Terminal assertion was recognized but didn't match the
    /// `XCTAssertEqual(predicate(x), .case)` (or `#expect(predicate(x) == .case)`)
    /// N-class shape — e.g. plain `XCTAssertTrue`, multi-arg comparisons,
    /// or no `==` infix.
    case nonEqualityAssertion

    /// Assertion shape matched but the case literal didn't match the
    /// bucket marker (case-insensitive identifier comparison per M13
    /// plan OD #4). E.g. `testSmall_x` body asserts
    /// `XCTAssertEqual(size(x), .medium)`.
    case caseLiteralMismatch
}
