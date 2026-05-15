import Foundation

/// V2.0 M10 — one entry in `.swiftinfer/interaction-baseline.json`.
/// Snapshot of a single `InteractionInvariantSuggestion`'s identity
/// at a checkpoint. Used by `swift-infer drift-interaction` to
/// compute "what's new since the baseline."
///
/// Smaller than `InteractionInvariantSuggestion` itself — the
/// baseline only needs identity + family + tier to drift-check.
/// The full predicate / explainability live in the in-memory
/// suggestion at warning time.
public struct InteractionBaselineEntry: Sendable, Equatable, Codable {

    /// Stable suggestion-identity hash — matches
    /// `SuggestionIdentity.normalized` (16-char uppercase hex).
    /// Mirrors the v1 `BaselineEntry.identityHash` field.
    public let identityHash: String

    /// Family the suggestion came from at snapshot time
    /// (`conservation` / `idempotence` / `cardinality` /
    /// `referential-integrity` / `biconditional`).
    public let family: InteractionInvariantFamily

    /// Score the suggestion had at snapshot time.
    public let scoreAtSnapshot: Int

    /// Tier the suggestion fell into at snapshot time.
    public let tier: Tier

    /// Reducer the suggestion fired on, for human-navigation context
    /// in the rendered warning line. Identity hash already binds the
    /// suggestion uniquely; this is purely informational.
    public let reducerQualifiedName: String

    public init(
        identityHash: String,
        family: InteractionInvariantFamily,
        scoreAtSnapshot: Int,
        tier: Tier,
        reducerQualifiedName: String
    ) {
        self.identityHash = identityHash
        self.family = family
        self.scoreAtSnapshot = scoreAtSnapshot
        self.tier = tier
        self.reducerQualifiedName = reducerQualifiedName
    }
}

/// V2.0 M10 — top-level `.swiftinfer/interaction-baseline.json`
/// shape. Analog of v1's `Baseline` but keyed on
/// `InteractionInvariantSuggestion`s. `swift-infer drift-interaction`
/// reads it; `discover-interaction --update-baseline` writes it
/// (the write side is a follow-up — M10 ships read + drift, with
/// the baseline snapshotted manually for now).
public struct InteractionBaseline: Sendable, Equatable, Codable {

    /// Bumped when the on-disk schema changes incompatibly.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let entries: [InteractionBaselineEntry]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        entries: [InteractionBaselineEntry] = []
    ) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }

    /// The empty value — schema version present, no entries yet.
    /// `InteractionBaselineLoader.load` returns this when the file
    /// doesn't exist.
    public static let empty = InteractionBaseline()

    /// `true` when an entry with the given identity hash exists.
    /// `drift-interaction` uses this to ask "is this current
    /// suggestion new since the baseline?" — `false` here +
    /// Strong tier = drift warning candidate.
    public func contains(identityHash: String) -> Bool {
        entries.contains { $0.identityHash == identityHash }
    }

    /// Look up an entry by identity hash. Reserved for future
    /// score-tier-transition surfacing (e.g. "this suggestion was
    /// Likely at baseline, is now Strong"); M10 doesn't yet emit
    /// a separate warning class for promotions.
    public func entry(for identityHash: String) -> InteractionBaselineEntry? {
        entries.first { $0.identityHash == identityHash }
    }
}
