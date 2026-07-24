import Foundation

/// V2.0 — user decision recorded against a discovered
/// `InteractionInvariantSuggestion`. Mirrors v1's `Decision` four-
/// state classification, narrowed slightly: M9's Bridge proposals
/// use `acceptedAsConformance` for the kit-conformance-stub writeout
/// (Tests/Generated/SwiftInferRefactors/...), `accepted` for the
/// trace-replay regression writeout (Tests/Generated/SwiftInferTraces/...).
///
/// - `accepted` — user chose Option A: the trace-replay regression
///   stays in `Tests/Generated/SwiftInferTraces/<reducer>/...` as a
///   standard `@Test`.
/// - `acceptedAsConformance` — user chose Option B (M9 Bridge): a
///   kit-conformance stub got written to
///   `Tests/Generated/SwiftInferRefactors/<reducer>/<family>.swift`.
///   Distinct from `.accepted` so future metrics can split per-arm
///   adoption rates per peer-proposal family. Drift treats this as
///   suppression-equivalent to `.accepted`.
/// - `rejected` — user chose `n` in triage; the invariant is hidden
///   from future runs and from drift warnings.
/// - `skipped` — user chose `s`; the invariant re-surfaces in future
///   `discover-interaction` runs but `drift-interaction` doesn't
///   warn on it (acknowledged but undecided).
// Deliberately parallel to v1's `Decision` (same four verdicts) but a *distinct* persistence
// vocabulary: this v2 enum pins the `"accepted-as-conformance"` rawValue whereas `Decision`
// uses the synthesized form, so `interaction-decisions.json` and `decisions.json` diverge on
// the wire and the two can't share a raw-valued type. See `Decision`'s schema-version note.
// swiftprojectlint:disable:next parallel-enum-shape
public enum InteractionDecision: String, Sendable, Equatable, Codable, CaseIterable {
    case accepted
    case acceptedAsConformance = "accepted-as-conformance"
    case rejected
    case skipped
}

/// V2.0 — one entry in `.swiftinfer/interaction-decisions.json`.
/// Analog of v1's `DecisionRecord` but keyed on
/// `InteractionInvariantSuggestion`. Smaller field set: no
/// `signalWeights` because interaction families don't expose the
/// v1-shape per-signal weights yet.
public struct InteractionDecisionRecord: Sendable, Equatable, Codable {

    /// Stable suggestion-identity hash — matches
    /// `SuggestionIdentity.normalized` (16-char uppercase hex,
    /// no `0x` prefix).
    public let identityHash: String

    /// Family the suggestion came from at decision time.
    public let family: InteractionInvariantFamily

    /// Score the suggestion had at decision time. Stored so future
    /// calibration can detect score-threshold drift across kit
    /// versions.
    public let scoreAtDecision: Int

    /// Tier the suggestion fell into at decision time. V1.65 — the
    /// *effective* tier; a `.strong` pick with `.measuredBothPass`
    /// verify evidence records as `.verified`. Falls back to the
    /// base score-derived tier when no verify evidence was loaded.
    public let tier: Tier

    /// Reducer the suggestion fired on. Informational; identity
    /// hash binds the suggestion uniquely.
    public let reducerQualifiedName: String

    /// User's choice.
    public let decision: InteractionDecision

    /// Wall-clock time of the decision. ISO8601-encoded in JSON.
    public let timestamp: Date

    public init(
        identityHash: String,
        family: InteractionInvariantFamily,
        scoreAtDecision: Int,
        tier: Tier,
        reducerQualifiedName: String,
        decision: InteractionDecision,
        timestamp: Date
    ) {
        self.identityHash = identityHash
        self.family = family
        self.scoreAtDecision = scoreAtDecision
        self.tier = tier
        self.reducerQualifiedName = reducerQualifiedName
        self.decision = decision
        self.timestamp = timestamp
    }
}

/// V2.0 — top-level `.swiftinfer/interaction-decisions.json` shape.
/// Analog of v1's `Decisions`. Identity-keyed upsert; latest decision
/// in effect.
public struct InteractionDecisions: Sendable, Equatable, Codable {

    /// Bumped when the on-disk schema changes incompatibly.
    /// v2.0 ships schema version 1.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let records: [InteractionDecisionRecord]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        records: [InteractionDecisionRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.records = records
    }

    /// The empty value. `InteractionDecisionsLoader.load` returns
    /// this when the file doesn't exist.
    public static let empty = Self()

    /// Look up a decision by suggestion-identity hash. Used by the
    /// drift detector ("does this suggestion already have a
    /// recorded decision?") and the accept-check rerun ("which
    /// records are `accepted` / `acceptedAsConformance`?").
    public func record(for identityHash: String) -> InteractionDecisionRecord? {
        records.first { $0.identityHash == identityHash }
    }

    /// Append-or-overwrite by identity. Mirrors v1's upserting
    /// semantics — the prior record for the same identity is
    /// removed; the new record appends at the end. Re-saved JSON
    /// stays stable for previously-stable records.
    public func upserting(_ record: InteractionDecisionRecord) -> Self {
        let withoutPrior = records.filter { $0.identityHash != record.identityHash }
        return Self(
            schemaVersion: schemaVersion,
            records: withoutPrior + [record]
        )
    }

    /// Fold another `InteractionDecisions` into this one (v1.102 —
    /// cycle 99 calibration helper). Used by `metrics-interaction`
    /// to aggregate per-corpus decision files into one in-memory
    /// `InteractionDecisions` for per-family acceptance-rate
    /// reporting. Identity-keyed; on collision the record with the
    /// later `timestamp` wins (same posture as v1's `Decisions.merge`).
    public func merge(_ other: Self) -> Self {
        var byHash: [String: InteractionDecisionRecord] = [:]
        for record in records + other.records {
            if let existing = byHash[record.identityHash],
               existing.timestamp >= record.timestamp {
                continue
            }
            byHash[record.identityHash] = record
        }
        let merged = byHash.values.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return lhs.identityHash < rhs.identityHash
        }
        return Self(
            schemaVersion: max(schemaVersion, other.schemaVersion),
            records: merged
        )
    }
}
