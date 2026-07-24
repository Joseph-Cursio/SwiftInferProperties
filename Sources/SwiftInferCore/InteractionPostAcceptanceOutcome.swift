import Foundation

/// V2.0 accept-check follow-up — the four-state post-acceptance verdict for an accepted
/// interaction-invariant suggestion.
///
/// This is v1's `PostAcceptanceOutcomeKind` verbatim: the four states (`stillPasses` /
/// `nowFails` / `obsolete` / `error`) and their raw values are identical, so the interaction
/// pipeline reuses the one vocabulary rather than maintaining a parallel copy that could drift.
/// Only the trigger differs (`verify-interaction` re-runs vs `verify`). The v1/v2 *records* stay
/// separate types; if the two schemas ever need to diverge on the verdict set, split this back
/// into its own enum — as `Decision` / `InteractionDecision` deliberately are.
public typealias InteractionPostAcceptanceOutcomeKind = PostAcceptanceOutcomeKind

/// V2.0 accept-check follow-up — one persisted post-acceptance
/// outcome, keyed by suggestion identity. Mirrors v1's
/// `PostAcceptanceOutcome` but with `family` in place of `template`.
///
/// Persisted to `.swiftinfer/interaction-post-acceptance-outcomes.json`
/// — a separate file from `interaction-decisions.json` because:
/// 1. **Different question.** Decisions answer "did the user
///    accept this?"; outcomes answer "did the accepted invariant
///    still hold on re-check?"
/// 2. **Different lifecycle.** Decisions write on accept; outcomes
///    write on each accept-check re-run.
public struct InteractionPostAcceptanceOutcome: Sendable, Equatable, Codable {

    /// Stable identity hash matching the source
    /// `InteractionDecisionRecord.identityHash` (16-char uppercase
    /// hex, no `0x` prefix).
    public let identityHash: String

    /// Family the originally-accepted suggestion came from.
    public let family: InteractionInvariantFamily

    /// The four-state verdict — see `InteractionPostAcceptanceOutcomeKind`.
    public let outcome: InteractionPostAcceptanceOutcomeKind

    /// Short human-readable detail: the verify sub-outcome
    /// (`bothPass` / `defaultFails` / etc.) or the reason an
    /// `.obsolete` / `.error` was emitted. `nil` when the outcome
    /// carries no extra detail.
    public let detail: String?

    /// The decision-time timestamp from the source
    /// `InteractionDecisionRecord` — when the user originally
    /// accepted. Persisted on each outcome so the consumer can
    /// compute "how long has the invariant been in the wild?"
    /// without re-loading decisions.json.
    public let originalAcceptedAt: Date

    /// Wall-clock time the accept-check rerun captured this
    /// verdict. ISO8601-encoded in JSON.
    public let checkedAt: Date

    /// swift-infer version string that produced this outcome.
    /// Older-stamped outcomes can surface a staleness warning at
    /// render time.
    public let swiftInferVersion: String

    public init(
        identityHash: String,
        family: InteractionInvariantFamily,
        outcome: InteractionPostAcceptanceOutcomeKind,
        detail: String?,
        originalAcceptedAt: Date,
        checkedAt: Date,
        swiftInferVersion: String
    ) {
        self.identityHash = identityHash
        self.family = family
        self.outcome = outcome
        self.detail = detail
        self.originalAcceptedAt = originalAcceptedAt
        self.checkedAt = checkedAt
        self.swiftInferVersion = swiftInferVersion
    }
}

/// V2.0 accept-check follow-up — top-level
/// `.swiftinfer/interaction-post-acceptance-outcomes.json` shape.
/// Identity-keyed upsert; latest accept-check run wins. The §17.2
/// metric (when extended to interactions) renders the *current*
/// state of each accepted invariant.
public struct InteractionPostAcceptanceOutcomeLog: Sendable, Equatable, Codable {

    /// Bumped when the on-disk schema changes incompatibly.
    /// v2.0 ships schema version 1.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let records: [InteractionPostAcceptanceOutcome]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        records: [InteractionPostAcceptanceOutcome] = []
    ) {
        self.schemaVersion = schemaVersion
        self.records = records
    }

    /// The empty value. `InteractionPostAcceptanceOutcomesStore.load`
    /// returns this when the file doesn't exist.
    public static let empty = Self()

    /// Look up an outcome by identity hash. Returns `nil` when no
    /// accept-check has run against the given suggestion.
    public func record(for identityHash: String) -> InteractionPostAcceptanceOutcome? {
        records.first { $0.identityHash == identityHash }
    }

    /// Append-or-overwrite by identity. Mirrors v1's posture: a
    /// second accept-check on the same identity replaces the first.
    public func upserting(_ record: InteractionPostAcceptanceOutcome) -> Self {
        let withoutPrior = records.filter { $0.identityHash != record.identityHash }
        return Self(
            schemaVersion: schemaVersion,
            records: withoutPrior + [record]
        )
    }
}
