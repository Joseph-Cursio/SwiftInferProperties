import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// Conformance-accept path (Option B — `LiftedConformanceEmitter`
/// writeouts to `Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift`).
/// Per PRD §16 #1's allowlist extension, the writeout never touches
/// existing source files.
extension InteractiveTriage {

    /// Returns the URL written to (or `nil` for dry-run / extraction
    /// failure).
    static func handleConformanceAccept(
        suggestion: Suggestion,
        proposal: RefactorBridgeProposal,
        context: Context
    ) throws -> URL? {
        let extensionSource = liftedConformanceSource(for: proposal)
        let path = context.outputDirectory
            .appendingPathComponent(LiftedConformanceEmitter.relativePath(
                typeName: proposal.typeName,
                protocolName: proposal.protocolName
            ))
        if context.dryRun {
            context.output.write("[dry-run] would write \(path.path)")
            return nil
        }
        let contents = wrappedConformanceFileContents(
            extensionSource: extensionSource,
            proposal: proposal,
            suggestion: suggestion
        )
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: path, options: .atomic)
        context.output.write("Wrote \(path.path)")
        return path
    }

    /// Build the conformance extension source via `LiftedConformanceEmitter`.
    /// Dispatches on `protocolName`; threads the proposal's witness
    /// names (M7.5.a + M8.5) into the emitter so the writeout aliases
    /// the user's existing op / identity / inverse into the kit's
    /// required statics. Returns the unsupported-protocol comment for
    /// future protocol arms not yet covered by the emitter.
    private static func liftedConformanceSource(for proposal: RefactorBridgeProposal) -> String {
        switch proposal.protocolName {
        case "Semigroup":
            return LiftedConformanceEmitter.semigroup(
                typeName: proposal.typeName,
                combineWitness: proposal.combineWitness,
                explainability: proposal.explainability
            )
        case "Monoid":
            // Monoid proposals always carry an identityWitness per the
            // orchestrator's Monoid-only-when-identity-element-fires
            // rule. Defensive fallback to "identity" if nil — emits the
            // bare extension shape so the user gets a clean Swift
            // compile error rather than a malformed witness reference.
            return LiftedConformanceEmitter.monoid(
                typeName: proposal.typeName,
                combineWitness: proposal.combineWitness,
                identityWitness: proposal.identityWitness ?? "identity",
                explainability: proposal.explainability
            )
        case "CommutativeMonoid":
            // CommutativeMonoid (kit v1.9.0) — same shape as Monoid; the
            // commutativity law is verified at law-check time, no new
            // requirement on the emitted extension.
            return LiftedConformanceEmitter.commutativeMonoid(
                typeName: proposal.typeName,
                combineWitness: proposal.combineWitness,
                identityWitness: proposal.identityWitness ?? "identity",
                explainability: proposal.explainability
            )
        case "Group":
            // Group (kit v1.9.0) — adds the `static func inverse(_:)`
            // requirement on top of Monoid's combine + identity. M8.4.a's
            // orchestrator threads inverseWitness from the M8.3
            // InverseElementPair when the Group promotion fires.
            return LiftedConformanceEmitter.group(
                typeName: proposal.typeName,
                combineWitness: proposal.combineWitness,
                identityWitness: proposal.identityWitness ?? "identity",
                inverseWitness: proposal.inverseWitness ?? "inverse",
                explainability: proposal.explainability
            )
        case "Semilattice":
            // Semilattice (kit v1.9.0) — extends CommutativeMonoid with
            // the idempotence Strict law. No new requirements; same body
            // shape as Monoid / CommutativeMonoid.
            return LiftedConformanceEmitter.semilattice(
                typeName: proposal.typeName,
                combineWitness: proposal.combineWitness,
                identityWitness: proposal.identityWitness ?? "identity",
                explainability: proposal.explainability
            )
        case "SetAlgebra":
            // SetAlgebra (stdlib) — secondary arm for Semilattice
            // claims with curated set-named ops (M8.4.b.1, open
            // decision #3 default `(a)`). Bare extension — the user's
            // existing methods satisfy the protocol's requirement set
            // (insert / remove / contains / etc.); the §4.5 caveat
            // lists what's not implied by the Semilattice signals.
            return LiftedConformanceEmitter.setAlgebra(
                typeName: proposal.typeName,
                explainability: proposal.explainability
            )
        case "Numeric":
            // Numeric (stdlib) — Ring arm (M8.4.b.2). Bare extension;
            // the user's existing +/-/* operators + Numeric.init?(exactly:)
            // satisfy the protocol. The §4.5 caveat enumerates what's
            // not implied by the two-monoid signals + the IEEE-754
            // caveat for floating-point types.
            return LiftedConformanceEmitter.numeric(
                typeName: proposal.typeName,
                explainability: proposal.explainability
            )
        default:
            // No remaining shipped protocol arms — every M8 promotion
            // routes through one of the explicit cases above. Future
            // protocol arms (kit-side CommutativeGroup, Group acting
            // on T) would dispatch here.
            return "// SwiftInfer: unsupported protocol '\(proposal.protocolName)' in v1.\n"
        }
    }

    /// Wrap the bare extension block from `LiftedConformanceEmitter`
    /// with the file-level imports + provenance header that the
    /// `Tests/Generated/SwiftInferRefactors/` writeout needs.
    private static func wrappedConformanceFileContents(
        extensionSource: String,
        proposal: RefactorBridgeProposal,
        suggestion: Suggestion
    ) -> String {
        let location = suggestion.evidence.first?.location
        let provenance = location.map { loc in "// Source: \(loc.file):\(loc.line)" } ?? ""
        return """
        // Auto-generated by `swift-infer discover --interactive` — do not edit.
        \(provenance)
        // RefactorBridge proposal: \(proposal.typeName) → \(proposal.protocolName)

        import ProtocolLawKit
        \(extensionSource)
        """
    }
}
