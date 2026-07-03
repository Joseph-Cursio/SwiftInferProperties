import Foundation
import SwiftInferCore

/// A candidate Redux-distinctive interaction invariant surfaced over a
/// recognised `ReducerCandidate`. The reducer analogue of
/// `ViewModelInteractionCandidate`, but keyed on `PropertyKind` — the
/// `.redux`-family reducers carry two paradigm-distinctive guarantees
/// (`determinism`, `unknownActionIsNoOp`) that don't belong to the five
/// shared `InteractionInvariantFamily` cases. This finally gives those
/// two dormant `PropertyKind` cases a consumer.
public struct ReducerInteractionCandidate: Sendable, Equatable {
    /// The distinctive property this candidate asserts.
    public let kind: PropertyKind
    /// The reducer's qualified name the candidate was surfaced on.
    public let typeName: String
    /// The State / Action type names the invariant ranges over.
    public let subjects: [String]
    /// One-line human rationale — why this shape suggests the invariant.
    public let rationale: String

    public init(kind: PropertyKind, typeName: String, subjects: [String], rationale: String) {
        self.kind = kind
        self.typeName = typeName
        self.subjects = subjects
        self.rationale = rationale
    }
}

/// PROTOTYPE — statically surfaces the two Redux-distinctive candidate
/// interaction invariants over a recognised `.redux`-family
/// `ReducerCandidate`. TCA reducers are deliberately excluded (`.tca` has
/// its own richer invariant story); only the Elm / ReSwift / Mobius /
/// Workflow / generic families — the ones `carrierKind.isReduxFamily`
/// labels `.redux` — flow through here. Every candidate is unverified
/// (`.possible`); a witness strategy that *constructs* the reducer's State
/// and drives an action decides.
///
/// **The two families, and why each is gated (not flooded onto every
/// reducer):** the rule-visitor carrier suppresses its generic law because
/// "detection determinism is near-always true and would flood `.possible`"
/// — the same discipline applies here.
///
///   - **`determinism`** (`reduce(s, a) == reduce(s, a)`) — surfaced for
///     *every* redux reducer, because the static purity analyzer
///     (`ReducerPurityAnalyzer`) only rules out TCA effects and hidden
///     mutation; it does **not** look for `Date()` / `UUID()` /
///     `.random()` / global reads, so a reducer it labels `.pure` can
///     still be nondeterministic. Determinism is therefore genuinely
///     unsettled by static means. The rationale carries the purity signal
///     so an already-flagged impure reducer reads as higher-urgency.
///   - **`unknownActionIsNoOp`** (`reduce(s, unknown) == s`) — surfaced
///     only when the Action alphabet is *open*: an unrecognised action can
///     only exist when the action type is not a statically-resolved closed
///     enum (`actionCases.isEmpty` — a protocol `Action` à la ReSwift, or a
///     String/opaque dispatch). A closed Swift enum is exhaustive, so no
///     "unknown action" is representable and the claim is vacuous — we skip
///     it rather than emit a tautology.
public enum ReducerInteractionAnalyzer {

    public static func analyze(_ candidate: ReducerCandidate) -> [ReducerInteractionCandidate] {
        guard candidate.carrierKind.isReduxFamily else { return [] }
        var out: [ReducerInteractionCandidate] = []
        out.append(determinism(candidate))
        if let noOp = unknownActionIsNoOp(candidate) { out.append(noOp) }
        return out
    }

    // MARK: - Determinism (reduce(s, a) == reduce(s, a))

    private static func determinism(_ candidate: ReducerCandidate) -> ReducerInteractionCandidate {
        let rationale: String
        switch candidate.purity {
        case .pure:
            rationale = "a `(State, Action) -> State` reducer should be deterministic — "
                + "`reduce(s, a)` should equal `reduce(s, a)` for the same inputs. Static purity "
                + "analysis rules out effects/hidden mutation but not a hidden `Date()` / `UUID()` "
                + "/ `.random()`, so this is worth a runtime witness"

        case .effectBearing, .hiddenMutability:
            rationale = "reducer shows an impurity signal (\(candidate.purity.rawValue)) — "
                + "determinism is the exact property to pin: verify `reduce(s, a) == reduce(s, a)`, "
                + "since a hidden `Date()` / `UUID()` / global read would falsify it"
        }
        return ReducerInteractionCandidate(
            kind: .determinism,
            typeName: candidate.qualifiedName,
            subjects: [candidate.stateTypeName, candidate.actionTypeName],
            rationale: rationale
        )
    }

    // MARK: - Unknown-action-is-no-op (reduce(s, unknown) == s) — open alphabets only

    private static func unknownActionIsNoOp(
        _ candidate: ReducerCandidate
    ) -> ReducerInteractionCandidate? {
        // A statically-resolved closed enum is exhaustive — no "unknown"
        // action is representable, so the invariant is vacuous. Only an open
        // alphabet (protocol `Action`, String/opaque dispatch) admits it.
        guard candidate.actionCases.isEmpty else { return nil }
        return ReducerInteractionCandidate(
            kind: .unknownActionIsNoOp,
            typeName: candidate.qualifiedName,
            subjects: [candidate.actionTypeName],
            rationale: "the Action type '\(candidate.actionTypeName)' has no statically-resolved "
                + "closed case set (an open / protocol alphabet) — an unrecognised action should "
                + "hit the default branch and leave State unchanged: `reduce(s, unknown) == s`"
        )
    }
}
