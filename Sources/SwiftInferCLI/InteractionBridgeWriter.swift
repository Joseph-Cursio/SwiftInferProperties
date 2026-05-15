import Foundation
import SwiftInferCore

/// V2.0 M9 — emits the kit-conformance stub Swift source file for
/// a `BridgeSuggestion`'s peer proposals. Each peer writes to
/// `Tests/Generated/SwiftInferRefactors/<TypeName>/<InvariantName>.swift`
/// per PRD §9.3, reusing v1's RefactorBridge path so the layout the
/// user already knows extends to interaction invariants.
///
/// **Hard guarantee.** Same v1 §16 #1 invariant: writeout is to
/// `Tests/Generated/`, never auto-editing existing source. The user
/// reviews + accepts the stub manually; `swift-infer` never modifies
/// the user's production code.
public enum InteractionBridgeWriter {

    /// V2.0 M9 — header marker (first non-blank line of stub
    /// output) so tests can pin the format without depending on
    /// emit-time variables.
    public static let stubHeaderMarker =
        "// swift-infer interaction-bridge conformance (V2.0 M9)"

    /// V2.0 M9 — emit the Swift source for one peer proposal. Pure:
    /// no disk I/O. The stub declares a `struct <StubName>:
    /// <KitProtocol>` conforming to the family-specific kit protocol
    /// from SwiftPropertyLaws v2.3.0; the `invariantHolds(in:)` body
    /// is the conjunction of all member-invariant predicates.
    public static func emit(
        bridge: BridgeSuggestion,
        peer: PeerProposal
    ) -> String {
        let stubName = peer.stubTypeName(reducerStateTypeName: bridge.stateTypeName)
        var lines: [String] = [
            stubHeaderMarker,
            "// Reducer: \(bridge.reducerQualifiedName)",
            "// State: \(bridge.stateTypeName)",
            "// Family: \(peer.family.rawValue)",
            "// Conformance: \(peer.kitProtocolName)",
            "// Contributing invariants:"
        ]
        for invariant in peer.invariants {
            lines.append("//   - \(invariant.predicate)")
        }
        lines.append("// DO NOT EDIT — regenerated when M9 fires on this reducer.")
        lines.append("")
        lines.append("import PropertyLawKit")
        lines.append("")
        if peer.family == .idempotence {
            lines.append(contentsOf: emitActionIdempotenceStub(
                stubName: stubName,
                peer: peer,
                bridge: bridge
            ))
        } else {
            lines.append(contentsOf: emitStatePredicateStub(
                stubName: stubName,
                peer: peer,
                bridge: bridge
            ))
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// V2.0 M9 — write the stub to disk under
    /// `<packageRoot>/Tests/Generated/SwiftInferRefactors/<stateRoot>/<stubName>.swift`.
    /// Creates the directory hierarchy on demand. Returns the
    /// absolute path of the written file.
    public static func persist(
        bridge: BridgeSuggestion,
        peer: PeerProposal,
        packageRoot: URL
    ) throws -> URL {
        let source = emit(bridge: bridge, peer: peer)
        let path = stubFilePath(bridge: bridge, peer: peer, packageRoot: packageRoot)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try source.write(to: path, atomically: true, encoding: .utf8)
        return path
    }

    /// V2.0 M9 — canonical writeout path:
    /// `<packageRoot>/Tests/Generated/SwiftInferRefactors/<stateRoot>/<stubName>.swift`.
    /// `stateRoot` is the State type's leftmost segment
    /// (`Inbox.State` → `Inbox`) so all M9 stubs for a single
    /// reducer cluster under one directory.
    public static func stubFilePath(
        bridge: BridgeSuggestion,
        peer: PeerProposal,
        packageRoot: URL
    ) -> URL {
        let stubName = peer.stubTypeName(reducerStateTypeName: bridge.stateTypeName)
        let stateRoot = bridge.stateTypeName.split(separator: ".").first.map(String.init)
            ?? bridge.stateTypeName
        return packageRoot
            .appendingPathComponent("Tests")
            .appendingPathComponent("Generated")
            .appendingPathComponent("SwiftInferRefactors")
            .appendingPathComponent(stateRoot)
            .appendingPathComponent("\(stubName).swift")
    }

    // MARK: - Stub body emit

    /// V2.0 M9 — Cardinality / Conservation / Referential integrity /
    /// Biconditional all share the state-predicate body shape. The
    /// stub conforms to the family protocol and implements
    /// `invariantHolds(in:)` with the `&&`-folded predicate.
    private static func emitStatePredicateStub(
        stubName: String,
        peer: PeerProposal,
        bridge: BridgeSuggestion
    ) -> [String] {
        [
            "struct \(stubName): \(peer.kitProtocolName) {",
            "    typealias State = \(bridge.stateTypeName)",
            "    static func invariantHolds(in state: State) -> Bool {",
            "        \(peer.conjoinedPredicate)",
            "    }",
            "}"
        ]
    }

    /// V2.0 M9 — ActionIdempotence is the one family whose protocol
    /// shape differs (PRD §9.2): it carries a `Set<Action>` of
    /// idempotent actions, not a state predicate. The contributing
    /// invariants' predicates are action-case dot-shorthand strings
    /// (M4.C convention — `".refresh"`, `".reset"`, etc.); the stub
    /// emits them as a literal Set.
    private static func emitActionIdempotenceStub(
        stubName: String,
        peer: PeerProposal,
        bridge: BridgeSuggestion
    ) -> [String] {
        let actionType = peer.invariants.first?.actionTypeName ?? "Action"
        let cases = peer.invariants.map(\.predicate).joined(separator: ", ")
        return [
            "struct \(stubName): \(peer.kitProtocolName) {",
            "    typealias State = \(bridge.stateTypeName)",
            "    typealias Action = \(actionType)",
            "    static let idempotentActions: Set<\(actionType)> = [\(cases)]",
            "}"
        ]
    }
}
