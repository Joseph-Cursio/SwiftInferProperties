import Foundation

/// V2.0 M9 — InteractionInvariantBridge proposal (PRD §9). Fires
/// when `InteractionTemplateEngine` accumulates ≥ 3 Strong-tier
/// `InteractionInvariantSuggestion`s on the same reducer. Each peer
/// proposal corresponds to one of the kit's family-specific
/// `InteractionInvariant` sub-protocols.
///
/// **Peer-proposal shape.** PRD §9.4 settles that the families are
/// mutually independent — no umbrella protocol. When ≥ 2 distinct
/// families fire as Strong on the same reducer, the user sees an
/// N-arm extended triage prompt (`[A/B/B'/B''/.../s/n/?]`); each
/// `B*` arm corresponds to one peer in `peers`. A reducer with all
/// Strong-tier suggestions in a single family fires a 1-arm Bridge.
public struct BridgeSuggestion: Sendable, Equatable, Codable {

    /// Stable identity hash for the §17 metrics arc + accept-flow
    /// plumbing. Derived from `(reducerQualifiedName, sorted family
    /// rawValues)` so the same set of fires on the same reducer
    /// produces the same identity across runs.
    public let identity: SuggestionIdentity

    /// `reducerQualifiedName` + `stateTypeName` are copied from the
    /// source `InteractionInvariantSuggestion`s so the bridge is
    /// self-describing.
    public let reducerQualifiedName: String
    public let stateTypeName: String

    /// One peer proposal per distinct family. Sorted by `family.rawValue`
    /// for byte-stable rendering.
    public let peers: [PeerProposal]

    /// Wall-clock time the bridge was first emitted. Mirrors
    /// `InteractionInvariantSuggestion.firstSeenAt`.
    public let firstSeenAt: Date

    public init(
        identity: SuggestionIdentity,
        reducerQualifiedName: String,
        stateTypeName: String,
        peers: [PeerProposal],
        firstSeenAt: Date
    ) {
        self.identity = identity
        self.reducerQualifiedName = reducerQualifiedName
        self.stateTypeName = stateTypeName
        self.peers = peers
        self.firstSeenAt = firstSeenAt
    }

    /// V2.0 M9 — canonical input the identity hash derives from.
    /// `family rawValues` are sorted before joining so the order of
    /// fires doesn't affect the hash.
    public static func identityCanonicalInput(
        reducerQualifiedName: String,
        families: [InteractionInvariantFamily]
    ) -> String {
        let sortedRaws = families.map(\.rawValue).sorted()
        return "bridge::\(reducerQualifiedName)::\(sortedRaws.joined(separator: ","))"
    }
}

/// V2.0 M9 — one arm of a Bridge proposal. Corresponds to one
/// kit-side `InteractionInvariant` sub-protocol. The user accepts
/// each peer independently per PRD §9.4.
public struct PeerProposal: Sendable, Equatable, Codable {

    /// Which family this peer proposal targets. One peer per
    /// distinct family per `BridgeSuggestion`.
    public let family: InteractionInvariantFamily

    /// The kit-side protocol name a conformance stub will name
    /// (`"CardinalityInvariant"`, `"ConservationInvariant"`, etc.).
    /// Derived from `family` via `kitProtocolName(for:)`.
    public let kitProtocolName: String

    /// The contributing `InteractionInvariantSuggestion`s in this
    /// family. M9 currently emits a single conformance stub per
    /// family using the conjunction of all member predicates
    /// (`p1 && p2 && ...`); a future refinement could emit one
    /// stub per member.
    public let invariants: [InteractionInvariantSuggestion]

    public init(
        family: InteractionInvariantFamily,
        kitProtocolName: String,
        invariants: [InteractionInvariantSuggestion]
    ) {
        self.family = family
        self.kitProtocolName = kitProtocolName
        self.invariants = invariants
    }

    /// V2.0 M9 — Swift expression for the conjunction of all member
    /// predicates. Used as the `invariantHolds(in:)` body in the
    /// emitted conformance stub. `&&`-folded for multiple members;
    /// the single-member case returns the predicate verbatim.
    public var conjoinedPredicate: String {
        invariants.map(\.predicate).joined(separator: " && ")
    }

    /// V2.0 M9 — name for the emitted conformance stub. Combines
    /// the reducer's enclosing type with the family for readability
    /// (`InboxCardinality`, `InboxConservation`, etc.). Used as the
    /// stub's typename + filename.
    public func stubTypeName(reducerStateTypeName: String) -> String {
        let stateRoot = reducerStateTypeName.split(separator: ".").first.map(String.init)
            ?? reducerStateTypeName
        let familyLabel: String
        switch family {
        case .conservation: familyLabel = "Conservation"
        case .idempotence: familyLabel = "Idempotence"
        case .cardinality: familyLabel = "Cardinality"
        case .referentialIntegrity: familyLabel = "ReferentialIntegrity"
        case .biconditional: familyLabel = "Biconditional"
        case .determinism: familyLabel = "Determinism"
        }
        return "\(stateRoot)\(familyLabel)"
    }
}

/// V2.0 M9 — map an `InteractionInvariantFamily` to the kit-side
/// protocol name a conformance stub names. Mirrors
/// SwiftPropertyLaws v2.3.0's
/// `Sources/PropertyLawKit/Public/InteractionInvariant.swift`.
public func kitProtocolName(for family: InteractionInvariantFamily) -> String {
    switch family {
    case .conservation: return "ConservationInvariant"
    case .idempotence: return "ActionIdempotenceInvariant"
    case .cardinality: return "CardinalityInvariant"
    case .referentialIntegrity: return "ReferentialIntegrityInvariant"
    case .biconditional: return "BiconditionalInvariant"

    // The measured-verify path (ActionSequenceStubEmitter) never calls this;
    // it's the accept→conformance-bridge name. The kit-side
    // `DeterminismInvariant` protocol is a separate follow-up — determinism
    // ships verify-only for now.
    case .determinism: return "DeterminismInvariant"
    }
}
