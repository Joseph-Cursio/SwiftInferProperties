import Foundation
import SwiftInferCore

/// V2.0 — Unknown-action-is-no-op interaction-template family.
///
/// **What it produces.** One `InteractionInvariantSuggestion` per `.redux`-family
/// reducer whose Action alphabet is *open* — `actionCases` empty: a protocol
/// `Action` (ReSwift), or String / opaque dispatch. A closed Swift enum is
/// exhaustive, so no "unknown" action is representable and the claim is vacuous;
/// those are skipped (mirrors `ReducerInteractionAnalyzer`'s gate — this template
/// is the measured consumer that the analyzer's PROTOTYPE candidate lacked).
///
/// **The property.** `reduce(s, unknown) == s`: an action the reducer does not
/// recognise should fall through to the default branch and leave State
/// unchanged. Measured by minting a fresh probe type conforming to the open
/// alphabet (`ActionSequenceStubEmitter.unknownActionProbeTypeName`) and
/// asserting the reducer leaves State untouched. Open alphabets have no
/// generatable actions, so the measured stub drives an empty sequence and checks
/// the initial state.
///
/// **Carrier scope.** `.redux`-family only (Elm / ReSwift / Mobius / generic) —
/// TCA reducers carry closed enums, so they never surface here.
///
/// **Scoring.** Ships at 30 (`.possible`) per the PRD §3.5 corollary; a measured
/// `bothPass` folds +50 → `.strong` → `.verified` through the M9 evidence→tier
/// join (no Finding-G deferral, so the fold is not clamped).
public enum UnknownActionIsNoOpInteractionTemplate: InteractionTemplateFamily {

    static let family = InteractionInvariantFamily.unknownActionIsNoOp

    static let initialScore = 30

    static func makePredicate(witness _: ReducerCandidate) -> String {
        "reduce(s, unknown) == s"
    }

    static func whySuggestedFor(
        witness _: ReducerCandidate,
        candidate: ReducerCandidate
    ) -> [String] {
        [
            "Reducer (\(candidate.carrierKind.rawValue)) with an open Action alphabet "
                + "('\(candidate.actionTypeName)' has no statically-resolved closed case set) — "
                + "an unrecognised action should hit the default branch and leave State unchanged.",
            "Reducer-shaped signature (\(candidate.signatureShape.rawValue)); "
                + "static purity label: \(candidate.purity.rawValue)."
        ]
    }

    static func whyMightBeWrongFor(witness _: ReducerCandidate) -> [String] {
        [
            "Measured by applying a freshly-minted probe action (a type conforming to the "
                + "open Action alphabet the reducer cannot recognise) and comparing State. A "
                + "reducer whose default branch mutates State (logging into State, a catch-all "
                + "that bumps a counter) will fail — a true negative, not a false positive.",
            "Requires State: Equatable and a zero-argument State initialiser; an unsupported "
                + "shape / non-constructible State reports architectural-coverage-pending rather "
                + "than a pass/fail. Open alphabets have no generatable actions, so only the "
                + "initial state is exercised (the action sequence is empty)."
        ]
    }

    /// Emit one suggestion only for an *open-alphabet* `.redux`-family reducer.
    /// A closed enum (`actionCases` non-empty) makes "unknown" unrepresentable —
    /// the claim is vacuous, so it is skipped; TCA and other non-redux carriers
    /// are excluded (they carry closed enums). Mirrors
    /// `ReducerInteractionAnalyzer.unknownActionIsNoOp`'s gate exactly, so the
    /// measured template and the discovery render agree on eligibility.
    static func analyze(
        candidate: ReducerCandidate,
        firstSeenAt: Date
    ) -> [InteractionInvariantSuggestion] {
        guard candidate.carrierKind.isReduxFamily, candidate.actionCases.isEmpty else {
            return []
        }
        return analyze(candidate: candidate, witnesses: [candidate], firstSeenAt: firstSeenAt)
    }
}
