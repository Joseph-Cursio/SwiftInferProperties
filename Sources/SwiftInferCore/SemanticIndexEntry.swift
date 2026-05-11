import Foundation

/// V1.33.A — one row of the SemanticIndex (PRD §20.1). A pure value type
/// recording an inferred property suggestion alongside the user's
/// triage decision (if any) and the first/last times the indexer saw
/// the signature.
///
/// **Schema rationale.** The PRD §20.1 sketch is `(typeId, templateId,
/// score, evidenceJson, decisionAt, lastSeenAt)`. v1.33 expands the
/// rough sketch into structured columns the rest of the codebase
/// already produces:
///   - `typeId → typeName`: the carrier type, optional for free
///     functions.
///   - `templateId → templateName`: the template's stable string id.
///   - `evidenceJson` → structured `primaryFunctionName` + `location`:
///     enough surface for human-readable output without re-loading the
///     full suggestion. The full evidence is recoverable from a fresh
///     discover run.
///   - `decisionAt` is preserved + `decision` is added so queries can
///     filter on accept/reject/skip without joining against
///     `.swiftinfer/decisions.json`.
///   - `firstSeenAt` is new: enables "what appeared since" queries.
///
/// `identityHash` is the suggestion identity hex (the V1.7.5 PRD §7.5
/// canonical-input hash) and serves as the upsert key. Two runs of
/// `swift-infer index` against the same corpus produce stable
/// identityHashes; upsert preserves `firstSeenAt` while updating the
/// rest.
public struct SemanticIndexEntry: Codable, Sendable, Equatable {

    /// Suggestion identity hex (the V1.7.5 PRD §7.5 canonical-input
    /// hash). The upsert key. Format: 16-char uppercase hex with `0x`
    /// prefix, e.g. `"0xBC43359C0574816B"`.
    public let identityHash: String

    /// Template name as it appears in discover output. One of
    /// `"round-trip"`, `"idempotence"`, `"monotonicity"`,
    /// `"commutativity"`, `"associativity"`, `"inverse-pair"`,
    /// `"identity-element"`, `"dual-style-consistency"`,
    /// `"composition"`, `"invariant-preservation"`.
    public let templateName: String

    /// Carrier type name (the suggestion's `containingTypeName`).
    /// `nil` for free functions or templates that don't have a carrier
    /// (the M1 idempotence template's no-carrier case).
    public let typeName: String?

    /// The suggestion's total score (signal sum). Useful for
    /// `--min-score` query filtering.
    public let score: Int

    /// Score tier as a human-readable string: `"Strong"`, `"Likely"`,
    /// `"Possible"`, or `"Suppressed"` (the last is rare in an index
    /// since Suppressed suggestions don't surface, but allowed for
    /// completeness).
    public let tier: String

    /// First-evidence function display name, e.g. `"exp(_:)"` or
    /// `"OrderedSet.sort()"`. Mirrors how discover renders the
    /// suggestion's first `Why suggested` line.
    public let primaryFunctionName: String

    /// `"<file>:<line>"` of the suggestion's first evidence. Mirrors
    /// the SwiftLint-friendly format the renderer uses.
    public let location: String

    /// User's triage decision recorded in `.swiftinfer/decisions.json`,
    /// or `nil` when no decision has been made yet. One of `"accept"`,
    /// `"reject"`, `"skip"`.
    public let decision: String?

    /// ISO8601 timestamp of the user's decision, copied from
    /// `.swiftinfer/decisions.json`. `nil` when no decision recorded.
    public let decisionAt: String?

    /// ISO8601 timestamp of the first `swift-infer index` run that
    /// produced this entry. Preserved across upserts so historical
    /// "when did this signature appear" queries remain accurate.
    public let firstSeenAt: String

    /// ISO8601 timestamp of the most recent `swift-infer index` run.
    /// Updated on every upsert so the user can identify entries
    /// dropped out of the current discover state (where `lastSeenAt`
    /// is older than the most recent run).
    public let lastSeenAt: String

    public init(
        identityHash: String,
        templateName: String,
        typeName: String? = nil,
        score: Int,
        tier: String,
        primaryFunctionName: String,
        location: String,
        decision: String? = nil,
        decisionAt: String? = nil,
        firstSeenAt: String,
        lastSeenAt: String
    ) {
        self.identityHash = identityHash
        self.templateName = templateName
        self.typeName = typeName
        self.score = score
        self.tier = tier
        self.primaryFunctionName = primaryFunctionName
        self.location = location
        self.decision = decision
        self.decisionAt = decisionAt
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
    }

    /// Returns a copy of `self` with the upsert-mutable columns
    /// (`score`, `tier`, `primaryFunctionName`, `location`, `decision`,
    /// `decisionAt`, `lastSeenAt`) replaced from `other` while
    /// preserving `firstSeenAt` from `self`. Used by `IndexStore.upsert`
    /// (V1.33.B). `identityHash`, `templateName`, `typeName` are
    /// immutable across upserts (the PRD §7.5 identity hash is a
    /// function of those fields, so they cannot change without also
    /// changing the hash).
    public func updated(from other: SemanticIndexEntry) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: identityHash,
            templateName: templateName,
            typeName: typeName,
            score: other.score,
            tier: other.tier,
            primaryFunctionName: other.primaryFunctionName,
            location: other.location,
            decision: other.decision,
            decisionAt: other.decisionAt,
            firstSeenAt: firstSeenAt,
            lastSeenAt: other.lastSeenAt
        )
    }
}
