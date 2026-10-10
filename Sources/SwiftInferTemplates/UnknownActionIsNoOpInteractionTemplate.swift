import Foundation
import SwiftInferCore

/// V2.0 — Unknown-action-is-no-op interaction-template family.
///
/// **What it produces.** One `InteractionInvariantSuggestion` per `.redux`-family
/// reducer whose Action alphabet is not closed (`hasClosedActionAlphabet`): a
/// protocol `Action` (ReSwift), String / opaque dispatch, or a type declared
/// outside the scanned sources. A closed Swift enum is exhaustive, so no
/// "unknown" action is representable and the claim is vacuous; those are skipped
/// (mirrors `ReducerInteractionAnalyzer`'s gate — this template is the measured
/// consumer that the analyzer's PROTOTYPE candidate lacked).
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
            "Reducer (\(candidate.carrierKind.rawValue)) whose Action type "
                + "'\(candidate.actionTypeName)' \(alphabetEvidence(candidate.actionTypeKind)) — "
                + "an unrecognised action should hit the default branch and leave State unchanged.",
            "Reducer-shaped signature (\(candidate.signatureShape.rawValue)); "
                + "static purity label: \(candidate.purity.rawValue)."
        ]
    }

    static func whyMightBeWrongFor(witness: ReducerCandidate) -> [String] {
        var caveats = [
            "Measured by applying a freshly-minted probe action (a type conforming to the "
                + "open Action alphabet the reducer cannot recognise) and comparing State. A "
                + "reducer whose default branch mutates State (logging into State, a catch-all "
                + "that bumps a counter) will fail — a true negative, not a false positive.",
            "Requires State: Equatable and a zero-argument State initialiser; an unsupported "
                + "shape / non-constructible State reports architectural-coverage-pending rather "
                + "than a pass/fail. Open alphabets have no generatable actions, so only the "
                + "initial state is exercised (the action sequence is empty)."
        ]
        switch witness.actionTypeKind {
        case .unresolved:
            caveats.append(
                "'\(witness.actionTypeName)' is not declared in the scanned sources, so discovery "
                    + "could not see whether it is closed. If it is an enum declared elsewhere, no "
                    + "unknown action exists and the claim is vacuous."
            )

        case .struct, .class, .actor:
            caveats.append(
                "'\(witness.actionTypeName)' is declared `\(witness.actionTypeKind.rawValue)`, and the "
                    + "probe can only conform to a protocol — measured verify reports a build "
                    + "failure here, not a verdict."
            )

        case .enum, .protocol:
            break
        }
        return caveats
    }

    /// What discovery resolved the Action type to, as the reason the alphabet
    /// is not closed. Shared with `ReducerInteractionAnalyzer`'s rationale.
    static func alphabetEvidence(_ kind: ActionTypeKind) -> String {
        switch kind {
        case .protocol:
            return "is a protocol — an open alphabet any type can conform to"

        case .struct, .class, .actor:
            return "is declared `\(kind.rawValue)`, not `enum` — an opaque dispatch type"

        case .unresolved:
            return "is not declared in the scanned sources, so no closed case set was resolved"

        case .enum:
            return "is a closed enum"
        }
    }

    /// Emit one suggestion only for a `.redux`-family reducer whose Action
    /// alphabet is not closed. A closed enum (`hasClosedActionAlphabet`) makes
    /// "unknown" unrepresentable — the claim is vacuous, so it is skipped; TCA
    /// and other non-redux carriers are excluded (they carry closed enums).
    /// Mirrors `ReducerInteractionAnalyzer.unknownActionIsNoOp`'s gate exactly,
    /// so the measured template and the discovery render agree on eligibility.
    static func analyze(
        candidate: ReducerCandidate,
        firstSeenAt: Date
    ) -> [InteractionInvariantSuggestion] {
        guard candidate.carrierKind.isReduxFamily, !candidate.hasClosedActionAlphabet else {
            return []
        }
        return analyze(candidate: candidate, witnesses: [candidate], firstSeenAt: firstSeenAt)
    }
}
