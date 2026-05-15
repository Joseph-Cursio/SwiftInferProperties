import Foundation

/// V2.0 M4.C — one detected Idempotence witness inside a reducer's
/// Action enum: a case whose name suggests applying-twice equals
/// applying-once (PRD §5.3).
///
/// **What M4.C detects.** Action enum cases whose name matches an
/// idempotent-sounding pattern:
///
///   - Exact-match names: `refresh`, `reset`, `clear`, `dismiss`,
///     `cancel`, `close`, `hide`.
///   - Prefix-match names: `set*` (e.g. `setColor(_:)`),
///     `select*` (e.g. `select(id:)`), `show*`, `present*`,
///     `dismiss*` (broader than the exact match — covers
///     `dismissAlert`, `dismissSheet`).
///
/// **What M4.C doesn't detect (yet).**
///   - The reducer body's purity for the matching action.
///     PRD §5.3's counter-signal: action-body side effects via
///     Effect / async downgrade idempotence to `.likely`. M4.C
///     stays at `.possible` regardless — reducer-body-purity
///     checks defer to a later refinement (the M3.A
///     `ReducerPurityAnalyzer` is a natural fit when the surface
///     extends to action-specific body analysis).
///   - Action cases with payloads where idempotence depends on
///     the payload (e.g. `setColor(.red)` is idempotent; `add(1)`
///     is not). v2.0 verifier handles this naturally — the action
///     is generated with the *same* payload twice in succession,
///     so payload-dependent idempotence still surfaces correctly
///     under the verifier loop.
public struct IdempotenceWitness: Sendable, Equatable, Codable {

    /// Name of the action case, e.g. `"refresh"` / `"reset"` /
    /// `"setColor"`. Stripped of any payload-clause and raw-value
    /// initializer — just the bare case identifier.
    public let actionCaseName: String

    /// Which pattern fired: `.exactName` for `refresh`/`reset`/etc.,
    /// `.namePrefix` for `set*`/`select*`/etc. Used by
    /// `IdempotenceInteractionTemplate`'s why-suggested rendering.
    public let matchKind: MatchKind

    public init(actionCaseName: String, matchKind: MatchKind) {
        self.actionCaseName = actionCaseName
        self.matchKind = matchKind
    }

    public enum MatchKind: String, Sendable, Equatable, Codable, CaseIterable {
        case exactName = "exact-name"
        case namePrefix = "name-prefix"
    }
}
