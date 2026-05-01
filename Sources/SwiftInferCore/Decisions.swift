import Foundation

/// User decision recorded against a discovered suggestion. PRD §3.6
/// step 8 + §8 + §17.1. Three states per the M6 plan's open decision
/// #2 (`skipped` ≠ `rejected`):
///
/// - `accepted` — user chose Option A in `--interactive` triage; M6.4
///   wrote the lifted property test stub to `Tests/Generated/SwiftInfer/`.
/// - `rejected` — user chose `n` in triage; suggestion is hidden from
///   future runs and from drift warnings.
/// - `skipped` — user chose `s`; "decide later" — the suggestion will
///   re-surface in future `discover` runs but `drift` doesn't warn on
///   it (the user has acknowledged it).
///
/// PRD v0.4 open decision #1 defers Option B (RefactorBridge protocol-
/// conformance) to M7. When that ships, this enum gains a fourth case
/// (`acceptedAsConformance` or similar). The string raw value stays
/// stable across that change so v0.4 decisions.json files load cleanly.
public enum Decision: String, Sendable, Equatable, Codable, CaseIterable {
    case accepted
    case rejected
    case skipped
}

/// Per-signal weight snapshot recorded at decision time. PRD §17.1
/// "Signal weights that contributed" — used by §17.2's calibration
/// loop to track which weights are predictive of acceptance.
///
/// Stored as `kind`/`weight` pairs (not the full `Signal` value) so
/// the JSON file stays compact: detail strings are descriptive text
/// that bloats persistence without contributing to calibration.
public struct SignalSnapshot: Sendable, Equatable, Codable {
    public let kind: String
    public let weight: Int

    public init(kind: String, weight: Int) {
        self.kind = kind
        self.weight = weight
    }
}

/// One entry in `.swiftinfer/decisions.json`. PRD §17.1 specifies the
/// per-decision fields the calibration loop consumes.
public struct DecisionRecord: Sendable, Equatable, Codable {

    /// Stable suggestion-identity hash per PRD §7.5 — matches
    /// `SuggestionIdentity.normalized` (16-char uppercase hex,
    /// no `0x` prefix).
    public let identityHash: String

    /// Template that produced the suggestion (`"idempotence"`,
    /// `"round-trip"`, etc.).
    public let template: String

    /// Score the suggestion had at decision time. Stored alongside the
    /// signal snapshot so calibration can detect score-threshold drift
    /// across kit versions.
    public let scoreAtDecision: Int

    /// Tier the suggestion fell into at decision time per `Score.tier`.
    public let tier: Tier

    /// User's choice.
    public let decision: Decision

    /// Wall-clock time of the decision. ISO8601-encoded in JSON for
    /// human readability + cross-platform parsing.
    public let timestamp: Date

    /// Per-signal weight snapshot — see `SignalSnapshot` doc. Empty
    /// when the calibration metadata isn't tracked (e.g. for skip
    /// markers honored from M1.5's `// swiftinfer: skip` machinery
    /// which predates this schema).
    public let signalWeights: [SignalSnapshot]

    public init(
        identityHash: String,
        template: String,
        scoreAtDecision: Int,
        tier: Tier,
        decision: Decision,
        timestamp: Date,
        signalWeights: [SignalSnapshot] = []
    ) {
        self.identityHash = identityHash
        self.template = template
        self.scoreAtDecision = scoreAtDecision
        self.tier = tier
        self.decision = decision
        self.timestamp = timestamp
        self.signalWeights = signalWeights
    }
}

/// Top-level `.swiftinfer/decisions.json` shape. Wraps the decision
/// list with a schema version so future changes can be detected and
/// migrated without silent data loss.
///
/// Per the M6 plan's open decision #7, `upserting` is the canonical
/// mutator: a second decision on the same identity replaces the
/// first. The latest decision is what's currently in effect; v1.1+
/// can layer history-stacking on top via a separate opt-in if
/// calibration discovers a need.
public struct Decisions: Sendable, Equatable, Codable {

    /// Bumped when the on-disk schema changes incompatibly. v1 ships
    /// version `1`; loaders that see a higher number warn and load
    /// what they can.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let records: [DecisionRecord]

    public init(schemaVersion: Int = Self.currentSchemaVersion, records: [DecisionRecord] = []) {
        self.schemaVersion = schemaVersion
        self.records = records
    }

    /// The empty value — schema version present, no records yet.
    /// `DecisionsLoader.load` returns this when the file doesn't exist.
    public static let empty = Decisions()

    /// Look up a decision by suggestion-identity hash. Used by the
    /// `--interactive` flow ("has this been triaged?") and `drift`
    /// ("does this new suggestion already have a decision?").
    public func record(for identityHash: String) -> DecisionRecord? {
        records.first { $0.identityHash == identityHash }
    }

    /// Append-or-overwrite by identity (open decision #7). Returns a
    /// new `Decisions` with the prior record for the same identity
    /// removed (if any) and the new record appended at the end. The
    /// trailing-append shape keeps re-saved JSON stable for
    /// freshly-decided suggestions while leaving the previously-stable
    /// records in place.
    public func upserting(_ record: DecisionRecord) -> Decisions {
        let withoutPrior = records.filter { $0.identityHash != record.identityHash }
        return Decisions(schemaVersion: schemaVersion, records: withoutPrior + [record])
    }
}
