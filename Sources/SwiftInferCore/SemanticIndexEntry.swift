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

    /// V1.47.A — JSON-encodable mirror of the carrier type's
    /// `PropertyLawCore.TypeShape` (kind + inherited types + stored
    /// members + user-init/gen flags), populated when discover sees
    /// the type's declaration in the indexed source. `nil` for stdlib
    /// raw-type carriers, `Complex<Double>`, types whose primary decl
    /// the indexer couldn't see, or entries persisted by v1.46-and-
    /// earlier `swift-infer` releases. The verify pipeline reads this
    /// to call `DerivationStrategist.strategy(for:)` without
    /// re-parsing the user's source.
    public let typeShape: IndexedTypeShape?

    /// V1.49.C — non-curated round-trip pair inverse-half name.
    /// Populated by discover when the suggestion's evidence array
    /// surfaces both pair halves (round-trip template emits
    /// `[forward, inverse]`); the verify resolver consults this
    /// field after the curated-pair lookup misses. `nil` for all
    /// non-round-trip templates and for v1.47-and-earlier persisted
    /// entries. Format: bare function name in the same shape
    /// `primaryFunctionName` carries (e.g. `"_scale(forMinimumCapacity:)"`).
    public let secondaryFunctionName: String?

    /// V1.149 — the *generator* carrier, distinct from `typeName` (which
    /// is the function's owner / call-site qualifier). For a method
    /// defined on the carrier (`extension Int { … }`) the two coincide
    /// and this stays `nil`; the verify path falls back to `typeName`.
    /// For a `static`/free function whose property flows through a
    /// parameter — e.g. `static func indent(_ s: String) -> String` on an
    /// unrelated `enum Engine` — `typeName` is `"Engine"` (the call
    /// qualifier) and `carrierTypeName` is `"String"` (the type the
    /// generated `Gen<T>` must produce). `nil` for v1.148-and-earlier
    /// persisted entries and for templates that don't expose a distinct
    /// parameter carrier.
    public let carrierTypeName: String?

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
        lastSeenAt: String,
        typeShape: IndexedTypeShape? = nil,
        secondaryFunctionName: String? = nil,
        carrierTypeName: String? = nil
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
        self.typeShape = typeShape
        self.secondaryFunctionName = secondaryFunctionName
        self.carrierTypeName = carrierTypeName
    }

    // MARK: - Codable

    /// Custom decoder uses `decodeIfPresent` for `typeShape` so
    /// pre-v1.47 entries (without the field) decode cleanly. All
    /// other fields stay required — they've been part of the schema
    /// since v1.33.
    private enum CodingKeys: String, CodingKey {
        case identityHash
        case templateName
        case typeName
        case score
        case tier
        case primaryFunctionName
        case location
        case decision
        case decisionAt
        case firstSeenAt
        case lastSeenAt
        case typeShape
        case secondaryFunctionName
        case carrierTypeName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.identityHash = try container.decode(String.self, forKey: .identityHash)
        self.templateName = try container.decode(String.self, forKey: .templateName)
        self.typeName = try container.decodeIfPresent(String.self, forKey: .typeName)
        self.score = try container.decode(Int.self, forKey: .score)
        self.tier = try container.decode(String.self, forKey: .tier)
        self.primaryFunctionName = try container.decode(String.self, forKey: .primaryFunctionName)
        self.location = try container.decode(String.self, forKey: .location)
        self.decision = try container.decodeIfPresent(String.self, forKey: .decision)
        self.decisionAt = try container.decodeIfPresent(String.self, forKey: .decisionAt)
        self.firstSeenAt = try container.decode(String.self, forKey: .firstSeenAt)
        self.lastSeenAt = try container.decode(String.self, forKey: .lastSeenAt)
        self.typeShape = try container.decodeIfPresent(IndexedTypeShape.self, forKey: .typeShape)
        self.secondaryFunctionName = try container.decodeIfPresent(
            String.self, forKey: .secondaryFunctionName
        )
        self.carrierTypeName = try container.decodeIfPresent(String.self, forKey: .carrierTypeName)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identityHash, forKey: .identityHash)
        try container.encode(templateName, forKey: .templateName)
        try container.encodeIfPresent(typeName, forKey: .typeName)
        try container.encode(score, forKey: .score)
        try container.encode(tier, forKey: .tier)
        try container.encode(primaryFunctionName, forKey: .primaryFunctionName)
        try container.encode(location, forKey: .location)
        try container.encodeIfPresent(decision, forKey: .decision)
        try container.encodeIfPresent(decisionAt, forKey: .decisionAt)
        try container.encode(firstSeenAt, forKey: .firstSeenAt)
        try container.encode(lastSeenAt, forKey: .lastSeenAt)
        try container.encodeIfPresent(typeShape, forKey: .typeShape)
        try container.encodeIfPresent(secondaryFunctionName, forKey: .secondaryFunctionName)
        try container.encodeIfPresent(carrierTypeName, forKey: .carrierTypeName)
    }

    /// Returns a copy of `self` with the upsert-mutable columns
    /// (`score`, `tier`, `primaryFunctionName`, `location`, `decision`,
    /// `decisionAt`, `lastSeenAt`, `typeShape`) replaced from `other`
    /// while preserving `firstSeenAt` from `self`. Used by
    /// `IndexStore.upsert` (V1.33.B). `identityHash`, `templateName`,
    /// `typeName` are immutable across upserts (the PRD §7.5 identity
    /// hash is a function of those fields, so they cannot change
    /// without also changing the hash). `typeShape` is upsert-mutable
    /// because the type's structural shape can evolve (e.g., a user
    /// adds a stored property between two indexer runs).
    public func updated(from other: Self) -> Self {
        Self(
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
            lastSeenAt: other.lastSeenAt,
            typeShape: other.typeShape,
            secondaryFunctionName: other.secondaryFunctionName,
            carrierTypeName: carrierTypeName
        )
    }
}
