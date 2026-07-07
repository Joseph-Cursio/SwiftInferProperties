import Foundation

/// V1.141.A — one row of the SemanticIndex for the **interaction**
/// surface (PRD §20.1). The interaction analog of ``SemanticIndexEntry``:
/// where that type records an algebraic pure-function suggestion, this
/// one records an `InteractionInvariantSuggestion` (a `<family>` invariant
/// over a reducer / MVVM carrier) alongside the user's triage decision
/// (if any) and the first/last times the indexer saw it.
///
/// **Why a separate type, not more columns on `SemanticIndexEntry`.**
/// `SemanticIndexEntry` has grown ~13 algebraic-verify-specific columns
/// (`typeShape`, `carrierTypeName`, `isInstanceMethod`, `returnsSelfType`,
/// …) that are meaningless for an interaction row, which instead needs
/// `family` / `predicate` / `reducerQualifiedName` / `stateTypeName` /
/// `actionTypeName`. Keeping the two shapes distinct avoids a pile of nil
/// verify columns and overloading `templateName` to mean "family". The
/// store holds both in one `Index` (a parallel `interactionEntries` array),
/// exactly as it added `typeShapes` at schema v4.
///
/// **Schema rationale** (mirrors ``SemanticIndexEntry``'s §20.1 mapping):
///   - `typeId` → `reducerQualifiedName` + `stateTypeName` (the carrier is
///     the reducer's State, not a value type).
///   - `templateId` → `family` (the invariant family rawValue).
///   - `evidenceJson` → structured `predicate` + `location`: enough surface
///     for human-readable output without re-loading the full suggestion.
///   - `decisionAt` preserved + `decision` added so queries can filter on
///     accept/reject/skip without joining against
///     `.swiftinfer/interaction-decisions.json`.
///   - `firstSeenAt` / `lastSeenAt` enable "what appeared since" queries.
///
/// `identityHash` is the suggestion identity hex (the PRD §7.5
/// canonical-input hash, `family::reducerQualifiedName::predicate`) and
/// serves as the upsert key. Two runs of `swift-infer index` against the
/// same corpus produce stable identityHashes; upsert preserves
/// `firstSeenAt` while updating the rest.
///
/// - Note: interaction identity is **not** rename-stable — renaming the
///   reducer or a State field referenced in the predicate changes the hash
///   and therefore resets `firstSeenAt`. This matches the algebraic
///   surface's current behavior (the §7.5 AST-shape identity component is
///   unimplemented on both surfaces) and is a deliberate limitation, not a
///   bug in this type.
public struct InteractionIndexEntry: Codable, Sendable, Equatable {

    /// Suggestion identity hex (the PRD §7.5 canonical-input hash). The
    /// upsert key. Format: 16-char uppercase hex with `0x` prefix, e.g.
    /// `"0xBC43359C0574816B"` — the `SuggestionIdentity.display` form, so
    /// it matches ``SemanticIndexEntry/identityHash``'s convention.
    public let identityHash: String

    /// Invariant family as its rawValue: `"cardinality"`,
    /// `"referential-integrity"`, `"biconditional"`, `"conservation"`,
    /// or `"idempotence"`. Stored as a string (not the enum) for
    /// `swift-infer query --family` filtering, mirroring how
    /// ``SemanticIndexEntry`` stores `templateName` / `tier` as strings.
    public let family: String

    /// Fully-qualified reducer name the invariant fired on, e.g.
    /// `"Feature.reduce"` or the `var body` carrier's owner. The primary
    /// "type id" of the row.
    public let reducerQualifiedName: String

    /// The reducer's State type name.
    public let stateTypeName: String

    /// The reducer's Action type name.
    public let actionTypeName: String

    /// The invariant predicate, e.g.
    /// `"state.selected == nil || state.items.contains { $0.id == state.selected }"`.
    /// Part of the identity hash's canonical input.
    public let predicate: String

    /// `"<file>:<line>"` of the reducer declaration. Mirrors the
    /// SwiftLint-friendly format the renderer uses.
    public let location: String

    /// Owning module in a multi-target run, or `nil` for single-target
    /// discovery (which leaves candidates untagged).
    public let moduleName: String?

    /// The suggestion's score (signal sum). Useful for `--min-score`
    /// query filtering.
    public let score: Int

    /// Score tier as a human-readable string: `"Verified"`, `"Strong"`,
    /// `"Likely"`, `"Possible"`, `"Advisory"`, or `"Suppressed"`.
    public let tier: String

    /// User's triage decision recorded in
    /// `.swiftinfer/interaction-decisions.json`, or `nil` when no decision
    /// has been made yet. One of `"accept"`, `"acceptAsConformance"`,
    /// `"reject"`, `"skip"`.
    public let decision: String?

    /// ISO8601 timestamp of the user's decision, copied from
    /// `.swiftinfer/interaction-decisions.json`. `nil` when no decision
    /// recorded.
    public let decisionAt: String?

    /// ISO8601 timestamp of the first `swift-infer index` run that
    /// produced this entry. Preserved across upserts so historical "when
    /// did this invariant appear" queries remain accurate.
    public let firstSeenAt: String

    /// ISO8601 timestamp of the most recent `swift-infer index` run.
    /// Updated on every upsert so the user can identify entries dropped
    /// out of the current discover state.
    public let lastSeenAt: String

    public init(
        identityHash: String,
        family: String,
        reducerQualifiedName: String,
        stateTypeName: String,
        actionTypeName: String,
        predicate: String,
        location: String,
        moduleName: String? = nil,
        score: Int,
        tier: String,
        decision: String? = nil,
        decisionAt: String? = nil,
        firstSeenAt: String,
        lastSeenAt: String
    ) {
        self.identityHash = identityHash
        self.family = family
        self.reducerQualifiedName = reducerQualifiedName
        self.stateTypeName = stateTypeName
        self.actionTypeName = actionTypeName
        self.predicate = predicate
        self.location = location
        self.moduleName = moduleName
        self.score = score
        self.tier = tier
        self.decision = decision
        self.decisionAt = decisionAt
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
    }

    /// Returns a copy of `self` with the upsert-mutable columns (`location`,
    /// `moduleName`, `score`, `tier`, `decision`, `decisionAt`,
    /// `lastSeenAt`) replaced from `other`, while preserving `firstSeenAt`
    /// and the identity columns from `self`. Used by
    /// `IndexStore.upsertInteraction`.
    ///
    /// `identityHash`, `family`, `reducerQualifiedName`, `stateTypeName`,
    /// `actionTypeName`, and `predicate` are immutable across upserts — the
    /// PRD §7.5 identity hash is a function of `family` /
    /// `reducerQualifiedName` / `predicate`, so they cannot change without
    /// also changing the hash (which would key a different row).
    public func updated(from other: Self) -> Self {
        Self(
            identityHash: identityHash,
            family: family,
            reducerQualifiedName: reducerQualifiedName,
            stateTypeName: stateTypeName,
            actionTypeName: actionTypeName,
            predicate: predicate,
            location: other.location,
            moduleName: other.moduleName,
            score: other.score,
            tier: other.tier,
            decision: other.decision,
            decisionAt: other.decisionAt,
            firstSeenAt: firstSeenAt,
            lastSeenAt: other.lastSeenAt
        )
    }
}
