import SwiftInferCore

/// Two functions a cross-function template can score together —
/// `forward: T -> U` paired with `reverse: U -> T`.
///
/// Orientation is canonical: `forward` is the function that comes first by
/// `(file, line)` so output is byte-stable across runs (PRD §16 #6). The
/// per-template scorer treats the pair as unordered for naming purposes —
/// `RoundTripTemplate` matches the curated inverse list against
/// `(forward.name, reverse.name)` *and* the swapped order.
public struct FunctionPair: Sendable, Equatable {

    public let forward: FunctionSummary
    public let reverse: FunctionSummary

    public init(forward: FunctionSummary, reverse: FunctionSummary) {
        self.forward = forward
        self.reverse = reverse
    }

    /// Common `@Discoverable(group:)` value when both halves of the
    /// pair carry the same non-nil group; `nil` otherwise. Computed
    /// pure-property — consumers like `RoundTripTemplate` (M5.1) read
    /// it to decide whether to fire the `+35` PRD §4.1
    /// `.discoverableAnnotation` cross-pair signal. Mismatched groups
    /// (one pair half tagged `"codec"`, the other tagged `"queue"`)
    /// return `nil` — the user explicitly grouped these into different
    /// scopes, so the annotation is *not* evidence of a cross-pair
    /// property; conversely, both-untagged is the M1-default case.
    public var sharedDiscoverableGroup: String? {
        guard let forwardGroup = forward.discoverableGroup,
              let reverseGroup = reverse.discoverableGroup,
              forwardGroup == reverseGroup else {
            return nil
        }
        return forwardGroup
    }
}

/// Type-driven candidate-pair finder. Implements PRD §5.5's first
/// tier — the type filter — at module scope (the entire scanned corpus).
/// Naming and explicit-`@Discoverable` filters live in the per-template
/// scorers (M1.4 only ships the type filter; naming is a *signal*, not a
/// pre-filter, so the scoring engine can still see Possible-tier pairs).
public enum FunctionPairing {

    /// Every candidate pair `(forward, reverse)` such that
    ///   - both are single-parameter, non-`inout`, non-`mutating`,
    ///   - both have a non-`Void` return,
    ///   - `forward.return == reverse.param[0]` and
    ///     `forward.param[0] == reverse.return`.
    /// Pairs are returned exactly once, oriented by `(file, line)` so the
    /// list is deterministic.
    public static func candidates(in summaries: [FunctionSummary]) -> [FunctionPair] {
        let pairable = summaries.filter(isPairable)
        var pairs: [FunctionPair] = []
        for (lhsIndex, lhs) in pairable.enumerated() {
            for rhs in pairable.dropFirst(lhsIndex + 1) where hasInverseTypeShape(lhs, rhs) {
                pairs.append(orientedPair(lhs, rhs))
            }
        }
        return pairs.sorted(by: lessThan)
    }

    /// The **domain** of `summary` viewed as a transformation
    /// `domain -> codomain`:
    ///   - a function with an explicit first parameter → that parameter's type
    ///     (free / static / instance binary-op — unchanged behaviour);
    ///   - a **0-parameter, non-`static` instance method** → the receiver type
    ///     (`self`), so an instance-method encode
    ///     `func base64EncodedString() -> String` reads as `Blob -> String`
    ///     and can pair with a free / static `decode(String) -> Blob`. This is
    ///     the idiomatic Swift codec shape the pairing was previously blind to
    ///     (it keyed on `parameters.first`).
    /// `nil` for a shape with no domain (a 0-parameter free or `static`
    /// function has no receiver to stand in as the input).
    public static func transformationDomain(_ summary: FunctionSummary) -> String? {
        if let param = summary.parameters.first {
            return param.typeText
        }
        guard summary.parameters.isEmpty,
              !summary.isStatic,
              let container = summary.containingTypeName else {
            return nil
        }
        return container
    }

    private static func isPairable(_ summary: FunctionSummary) -> Bool {
        guard !summary.isMutating,
              let returnType = summary.returnTypeText,
              returnType != "Void",
              returnType != "()",
              transformationDomain(summary) != nil else {
            return false
        }
        // With an explicit parameter it must be a *single*, non-`inout` one; a
        // multi-argument function is not a simple `domain -> codomain`
        // transformation. A 0-parameter instance method (domain = receiver) is
        // already gated by `transformationDomain`.
        if let param = summary.parameters.first {
            return summary.parameters.count == 1 && !param.isInout
        }
        return true
    }

    private static func hasInverseTypeShape(
        _ lhs: FunctionSummary,
        _ rhs: FunctionSummary
    ) -> Bool {
        guard let lhsDomain = transformationDomain(lhs),
              let rhsDomain = transformationDomain(rhs),
              let lhsReturn = lhs.returnTypeText,
              let rhsReturn = rhs.returnTypeText else {
            return false
        }
        return lhsReturn == rhsDomain && lhsDomain == rhsReturn
    }

    private static func orientedPair(
        _ lhs: FunctionSummary,
        _ rhs: FunctionSummary
    ) -> FunctionPair {
        if locationLessThan(lhs.location, rhs.location) {
            return FunctionPair(forward: lhs, reverse: rhs)
        }
        return FunctionPair(forward: rhs, reverse: lhs)
    }

    private static func lessThan(_ lhs: FunctionPair, _ rhs: FunctionPair) -> Bool {
        locationLessThan(lhs.forward.location, rhs.forward.location)
    }

    private static func locationLessThan(
        _ lhs: SourceLocation,
        _ rhs: SourceLocation
    ) -> Bool {
        if lhs.file != rhs.file {
            return lhs.file < rhs.file
        }
        return lhs.line < rhs.line
    }
}
