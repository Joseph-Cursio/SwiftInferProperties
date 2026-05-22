import Foundation

/// V2.0 M9 — aggregates accepted `InteractionInvariantSuggestion`s
/// into `BridgeSuggestion` peer-proposal bundles per PRD §9.
/// Analog of v1's `RefactorBridge`: when ≥ 3 Strong-tier suggestions
/// fire on the same reducer, propose conformance to the kit's
/// family-specific `InteractionInvariant` sub-protocols.
///
/// **Why aggregate at the Bridge layer rather than per-template.**
/// The five PRD §5 families are detected independently — Cardinality
/// doesn't know whether Conservation also fired on the same State.
/// The Bridge sees the full set of suggestions and groups by reducer;
/// only the aggregated view can answer "does this reducer have ≥ 3
/// Strong invariants across enough families to warrant a Bridge?"
///
/// **Visibility.** PRD §3.5 corollary: every new family ships at
/// default `.possible` visibility, so no invariant reaches Strong
/// tier in production until calibration cycles promote it. The
/// Bridge is wired now (M9) so the writeout + data model are ready;
/// the actual fires arrive once tier promotion happens. Tests
/// directly construct synthetic Strong-tier inputs.
public enum InteractionInvariantBridge {

    /// V2.0 M9 — PRD §9.1 trigger threshold. A reducer's Bridge
    /// fires when its Strong-tier invariant count reaches this.
    public static let defaultStrongThreshold = 3

    /// V2.0 M9 — group Strong-tier suggestions by reducer; emit a
    /// `BridgeSuggestion` per reducer whose count meets the threshold.
    /// Pure: no I/O. Sorted output (by reducer qualified name) for
    /// byte-stable rendering.
    public static func bridges(
        from suggestions: [InteractionInvariantSuggestion],
        strongThreshold: Int = defaultStrongThreshold,
        now: Date = Date()
    ) -> [BridgeSuggestion] {
        let strong = suggestions.filter { $0.tier == .strong || $0.tier == .verified }
        let byReducer = Dictionary(grouping: strong, by: \.reducerQualifiedName)
        var bridges: [BridgeSuggestion] = []
        for reducerName in byReducer.keys.sorted() {
            guard let group = byReducer[reducerName], group.count >= strongThreshold else {
                continue
            }
            bridges.append(makeBridge(reducerName: reducerName, group: group, now: now))
        }
        return bridges
    }

    /// Build the per-reducer `BridgeSuggestion`. The State type name
    /// + peer-list construction live here so `bridges(from:...)` stays
    /// under SwiftLint's `function_body_length` cap.
    private static func makeBridge(
        reducerName: String,
        group: [InteractionInvariantSuggestion],
        now: Date
    ) -> BridgeSuggestion {
        let byFamily = Dictionary(grouping: group, by: \.family)
        let peers: [PeerProposal] = byFamily.keys.sorted { $0.rawValue < $1.rawValue }.map { family in
            PeerProposal(
                family: family,
                kitProtocolName: kitProtocolName(for: family),
                invariants: byFamily[family]!.sorted { $0.predicate < $1.predicate }
            )
        }
        let stateTypeName = group.first?.stateTypeName ?? "Unknown"
        let canonicalInput = BridgeSuggestion.identityCanonicalInput(
            reducerQualifiedName: reducerName,
            families: peers.map(\.family)
        )
        let identity = SuggestionIdentity(canonicalInput: canonicalInput)
        return BridgeSuggestion(
            identity: identity,
            reducerQualifiedName: reducerName,
            stateTypeName: stateTypeName,
            peers: peers,
            firstSeenAt: now
        )
    }
}
