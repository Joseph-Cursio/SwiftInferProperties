// Widens the algebraic corpus to the ROUND-TRIP family — the FIRST
// verifying round-trip true positive in the project. cycle27-surface's
// round-trip picks were all filtered false positives, and the unary
// `atLeastMedium`/`bumpUp` pairing in `ConfidenceUnary.swift` is a
// deliberate spurious pick (an endomorphism pair the template
// over-generates → measured-defaultFails). This pair is a genuine
// bijection → measured-bothPass.
//
// Design notes — why this shape, NOT a rotation/involution pair on a
// single enum:
//
//   - The round-trip carrier is `forward.containingTypeName`
//     (`RoundTripTemplate.makeConstraint`'s `carrier`). Declaring BOTH
//     halves as STATIC methods on `Move` keeps the carrier well-defined
//     AND dodges `crossTypeRoundTripCounterSignal` (-25 → Suppressed),
//     which fires only when the two halves live in DISTINCT containing
//     types (cycle-1 calibration). Same container → exempt.
//
//   - `encode`/`decode` is a CURATED inverse-name pair
//     (`RoundTripTemplate.curatedInversePairs`) → a +40 name signal on
//     top of the +30 type-symmetry baseline → the pick surfaces well
//     above Possible.
//
//   - Neither half is an endomorphism `(T) -> T`, so NEITHER trips the
//     idempotence template — no extra picks (a cyclic-rotation pair on
//     ONE enum would add two idempotence false positives, the
//     "over-generation" the corpus deliberately keeps tight). `Move` /
//     `MoveTag` carry no binary `(T, T) -> T` ops, so no commutativity /
//     associativity picks either. Net surface: exactly ONE new pick.
//
//   - Both enums are public `CaseIterable`, so the `.caseIterable`
//     strategy generates the carrier `Move`. The intermediate `MoveTag`
//     never appears by name in the emitted stub (it is just `encode`'s
//     return / `decode`'s input — `decode(encode(x)) != x` is the only
//     check, both sides `Move`), so importing the corpus module suffices.

/// Wire-tag representation of a `Move`. A plain public `CaseIterable`
/// enum with no operations of its own, so it surfaces no picks; it
/// exists only as `encode`'s codomain / `decode`'s domain.
public enum MoveTag: Int, CaseIterable, Sendable {
    case r
    case p
    case s
}

// `Equatable` is declared explicitly (not just inherited from the raw
// `Int`): the round-trip property's `decode(encode(x)) != x` check needs
// it, AND it keeps `EquatableResolver` from classifying `Move` as
// non-Equatable — which would fire the separate `inverse-pair` template
// (an `unsupported-template` in the verifier → an `architectural-coverage-
// pending` record). `Confidence` dodges the same way via `Comparable`.
public enum Move: Int, CaseIterable, Equatable, Sendable {
    case rock
    case paper
    case scissors

    /// Serialize to the wire tag — the bijective inverse of `decode`.
    public static func encode(_ move: Move) -> MoveTag {
        switch move {
        case .rock: return .r
        case .paper: return .p
        case .scissors: return .s
        }
    }

    /// Deserialize from the wire tag — the bijective inverse of
    /// `encode`, so `decode(encode(x)) == x` for every `Move`
    /// → measured-bothPass (the first verifying round-trip).
    public static func decode(_ tag: MoveTag) -> Move {
        switch tag {
        case .r: return .rock
        case .p: return .paper
        case .s: return .scissors
        }
    }
}
