import SwiftInferCore

/// V1.19.D — pair of mutating-method lifts whose names form a canonical
/// state-mutation inverse: `add`/`remove`, `insert`/`remove`, `push`/`pop`,
/// `subscribe`/`unsubscribe`, etc. Both halves operate on the same carrier
/// and the same parameter type; the asserted property is functional
/// inversion on the lifted shadows:
///
/// ```swift
/// let original = s
/// var added = original
/// added.<add>(x)
/// var roundTrip = added
/// roundTrip.<remove>(x)
/// roundTrip == original
/// ```
///
/// And symmetrically for `<remove>` then `<add>` — two assertions per
/// suggestion. The naming rule is intentionally orientation-insensitive:
/// `(add, remove)` and `(remove, add)` produce the same pair, oriented
/// canonically (lexicographically smaller name as `forward`).
public struct LiftedInversePair: Sendable, Equatable {

    /// Canonical-orientation: lexicographically smaller name. Templates
    /// scoring the pair iterate both halves; orientation only affects
    /// rendering / identity hashing.
    public let forward: LiftedTransformation
    public let reverse: LiftedTransformation

    /// The curated or project-vocabulary name pair that matched (always
    /// stored in canonical-orientation: lexicographically smaller name
    /// first). Rendered into the `whySuggested` block.
    public let pairName: NamePair

    public init(
        forward: LiftedTransformation,
        reverse: LiftedTransformation,
        pairName: NamePair
    ) {
        self.forward = forward
        self.reverse = reverse
        self.pairName = pairName
    }

    public struct NamePair: Sendable, Equatable {
        public let lhs: String
        public let rhs: String

        public init(lhs: String, rhs: String) {
            self.lhs = lhs
            self.rhs = rhs
        }
    }
}

/// V1.19.D — pairing pass over `[LiftedTransformation]` that finds
/// canonical mutating add/remove-style inverse pairs. Mirrors
/// `FunctionPairing` (non-mutating round-trip pairs) and
/// `LiftedIdentityElementPairing` (V1.19.C) — naming/coverage gates live
/// in the per-template scorer; this pass enforces only the pre-filter
/// shape: same carrier + same parameter list + curated/project name pair.
public enum InverseLiftedPairing {

    /// Curated state-mutation inverse pairs. Distinct from
    /// `RoundTripTemplate.curatedInversePairs` (which targets cross-type
    /// encoder/decoder shapes typically expressed as non-mutating
    /// functions). The mutating-specific list captures the canonical
    /// state-flip patterns Swift APIs follow:
    ///
    /// - `add` / `remove` — Set / Array / OrderedSet members
    /// - `insert` / `remove` — same family, different naming convention
    /// - `push` / `pop` — Stack-shaped mutators (note: stdlib's `popLast`
    ///   returns the popped element via `@discardableResult`, but the
    ///   lift's metadata-only shadow ignores the return value)
    /// - `attach` / `detach`, `link` / `unlink` — graph/tree mutations
    /// - `activate` / `deactivate`, `subscribe` / `unsubscribe`,
    ///   `register` / `deregister` — observer/listener patterns
    /// - `enable` / `disable` — feature-flag patterns
    public static let curatedPairs: [LiftedInversePair.NamePair] = [
        LiftedInversePair.NamePair(lhs: "add", rhs: "remove"),
        LiftedInversePair.NamePair(lhs: "insert", rhs: "remove"),
        LiftedInversePair.NamePair(lhs: "push", rhs: "pop"),
        LiftedInversePair.NamePair(lhs: "attach", rhs: "detach"),
        LiftedInversePair.NamePair(lhs: "link", rhs: "unlink"),
        LiftedInversePair.NamePair(lhs: "activate", rhs: "deactivate"),
        LiftedInversePair.NamePair(lhs: "subscribe", rhs: "unsubscribe"),
        LiftedInversePair.NamePair(lhs: "register", rhs: "deregister"),
        LiftedInversePair.NamePair(lhs: "enable", rhs: "disable")
    ]

    /// Every candidate `(forward, reverse)` pair such that:
    ///   - Both lifts are on the same carrier,
    ///   - Both have a single non-`inout` parameter of the same type,
    ///   - Both names match one of `curatedPairs` or
    ///     `vocabulary.inversePairs` (orientation-insensitive),
    ///   - `forward.originalSummary.name` < `reverse.originalSummary.name`
    ///     lexicographically (canonical orientation; pair is unordered
    ///     so `(add, remove)` and `(remove, add)` both yield the same
    ///     `(add, remove)` orientation in output).
    /// Pairs are returned sorted by `(forward.original.file, line,
    /// reverse.original.file, line)` for byte-stable output.
    public static func candidates(
        in lifts: [LiftedTransformation],
        vocabulary: Vocabulary = .empty
    ) -> [LiftedInversePair] {
        // Group by carrier so cross-carrier pairs aren't formed (a pair
        // of `Set.insert` + `Array.remove` is not an inverse pair even
        // if the names match).
        var liftsByCarrier: [String: [LiftedTransformation]] = [:]
        for lift in lifts {
            liftsByCarrier[lift.carrier, default: []].append(lift)
        }
        let projectPairs = vocabulary.inversePairs.map {
            LiftedInversePair.NamePair(lhs: $0.forward, rhs: $0.reverse)
        }
        let allPairs = curatedPairs + projectPairs
        var out: [LiftedInversePair] = []
        for (_, sameCarrierLifts) in liftsByCarrier {
            for (lhsIndex, lhs) in sameCarrierLifts.enumerated() {
                for rhs in sameCarrierLifts.dropFirst(lhsIndex + 1) {
                    if let pair = matchedPair(lhs: lhs, rhs: rhs, against: allPairs) {
                        out.append(pair)
                    }
                }
            }
        }
        return out.sorted(by: lessThan)
    }

    /// Returns a `LiftedInversePair` if `lhs` and `rhs` match one of the
    /// `pairs` orientation-insensitively AND have matching parameter
    /// shape. The returned pair is always in canonical orientation
    /// (lexicographically smaller name as `forward`).
    private static func matchedPair(
        lhs: LiftedTransformation,
        rhs: LiftedTransformation,
        against pairs: [LiftedInversePair.NamePair]
    ) -> LiftedInversePair? {
        let lhsName = lhs.originalSummary.name
        let rhsName = rhs.originalSummary.name
        guard let matched = pairs.first(where: { pair in
            (pair.lhs == lhsName && pair.rhs == rhsName)
                || (pair.lhs == rhsName && pair.rhs == lhsName)
        }) else { return nil }
        guard hasMatchingShape(lhs: lhs, rhs: rhs) else { return nil }
        // Canonical orientation: lexicographically smaller name first.
        if lhsName < rhsName {
            return LiftedInversePair(forward: lhs, reverse: rhs, pairName: matched)
        }
        return LiftedInversePair(forward: rhs, reverse: lhs, pairName: matched)
    }

    /// Both lifts have a single non-inout parameter of the same type.
    /// (No-param add/remove pairs aren't meaningful as inverses — there
    /// has to be an `x` to add and remove.)
    private static func hasMatchingShape(
        lhs: LiftedTransformation,
        rhs: LiftedTransformation
    ) -> Bool {
        let lhsParams = lhs.originalSummary.parameters
        let rhsParams = rhs.originalSummary.parameters
        guard lhsParams.count == 1, rhsParams.count == 1 else { return false }
        let lhsParam = lhsParams[0]
        let rhsParam = rhsParams[0]
        guard !lhsParam.isInout, !rhsParam.isInout else { return false }
        return lhsParam.typeText == rhsParam.typeText
    }

    private static func lessThan(_ lhs: LiftedInversePair, _ rhs: LiftedInversePair) -> Bool {
        let lhsLoc = lhs.forward.originalSummary.location
        let rhsLoc = rhs.forward.originalSummary.location
        if lhsLoc.file != rhsLoc.file {
            return lhsLoc.file < rhsLoc.file
        }
        if lhsLoc.line != rhsLoc.line {
            return lhsLoc.line < rhsLoc.line
        }
        let lhsRev = lhs.reverse.originalSummary.location
        let rhsRev = rhs.reverse.originalSummary.location
        if lhsRev.file != rhsRev.file {
            return lhsRev.file < rhsRev.file
        }
        return lhsRev.line < rhsRev.line
    }
}
