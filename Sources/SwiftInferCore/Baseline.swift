import Foundation

/// One entry in `.swiftinfer/baseline.json` — a snapshot of a single
/// suggestion's identity at a checkpoint. Used by `swift-infer drift`
/// (M6.5) to compute "what's new since the baseline." Smaller than
/// `DecisionRecord` (M6.1) because the baseline doesn't track user
/// intent or per-signal weights — just enough to identify and tier-
/// match suggestions across runs.
public struct BaselineEntry: Sendable, Equatable, Codable {

    /// Stable suggestion-identity hash per PRD §7.5 — matches
    /// `SuggestionIdentity.normalized` (16-char uppercase hex).
    public let identityHash: String

    /// Template that produced the suggestion at snapshot time.
    public let template: String

    /// Score the suggestion had at snapshot time. Drift uses this to
    /// detect score-tier transitions (a suggestion that was Likely at
    /// baseline and is now Strong is *technically* the same suggestion
    /// — the identity hash matches — but the tier upgrade may warrant
    /// re-triage).
    public let scoreAtSnapshot: Int

    /// Tier the suggestion fell into at snapshot time per `Score.tier`.
    public let tier: Tier

    public init(
        identityHash: String,
        template: String,
        scoreAtSnapshot: Int,
        tier: Tier
    ) {
        self.identityHash = identityHash
        self.template = template
        self.scoreAtSnapshot = scoreAtSnapshot
        self.tier = tier
    }
}

/// Top-level `.swiftinfer/baseline.json` shape — the "what's been
/// surfaced before" record `swift-infer drift` checks against. M6.2
/// data model; M6.5 wires the read into `drift` and the write into
/// `discover --update-baseline`.
///
/// PRD §3.6 step 7 + §9 frame the use case: CI runs `swift-infer
/// drift --baseline .swiftinfer/baseline.json` per PR; new Strong-
/// tier suggestions added since the baseline that lack a recorded
/// decision (M6.1) earn a non-fatal warning. The baseline lets the
/// developer set "this is the state I've already triaged; warn me
/// only about new things."
public struct Baseline: Sendable, Equatable, Codable {

    /// Bumped when the on-disk schema changes incompatibly. v1 ships
    /// version `1`; loaders that see a higher number warn and load
    /// what they can.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let entries: [BaselineEntry]

    public init(schemaVersion: Int = Self.currentSchemaVersion, entries: [BaselineEntry] = []) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }

    /// The empty value — schema version present, no entries yet.
    /// `BaselineLoader.load` returns this when the file doesn't exist.
    public static let empty = Baseline()

    /// `true` when an entry with the given identity hash exists.
    /// M6.5's `drift` uses this to ask "is this current suggestion
    /// new since the baseline?" — `false` here + Strong tier + no
    /// decision recorded = drift warning candidate.
    public func contains(identityHash: String) -> Bool {
        entries.contains { $0.identityHash == identityHash }
    }

    /// Look up an entry by identity hash. Used by `drift` for
    /// score-tier-transition detection (currently logged but not
    /// surfaced as a separate warning class — open decision for
    /// M6.5's "Likely → Strong promotion" handling).
    public func entry(for identityHash: String) -> BaselineEntry? {
        entries.first { $0.identityHash == identityHash }
    }
}
