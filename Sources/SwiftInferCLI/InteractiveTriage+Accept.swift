import Foundation
import SwiftInferCore
import SwiftInferTemplates

// swiftlint:disable file_length
// M8.2 added four template arms (commutative / associative /
// identity-element / inverse-pair) on top of the M6.3 + M7.3 four,
// pushing this file past the 400-line cap. Splitting further would
// scatter the dispatch + extraction helpers across two files for
// minimal reader benefit; the file already lives one extension deep
// from `InteractiveTriage.swift` for the same SwiftLint reason.

/// Accept-path helpers + suggestion-field extraction for
/// `InteractiveTriage` (M6.4). Split out to keep the main enum body
/// under SwiftLint's 250-line cap; nothing here is part of the
/// public surface.
extension InteractiveTriage {

    // MARK: - Accept-path file write

    /// Returns the URL written to (or `nil` when no file was written
    /// — dry-run, unsupported template arm, or extraction failure).
    static func handleAccept(
        suggestion: Suggestion,
        context: Context
    ) throws -> URL? {
        guard let stub = liftedTestStub(for: suggestion) else {
            context.diagnostics.writeDiagnostic(
                "note: no stub writeout available for template '\(suggestion.templateName)' in v1; "
                    + "decision recorded without writing a file"
            )
            return nil
        }
        let fileName = stubFileName(for: suggestion) ?? "\(suggestion.identity.normalized).swift"
        let path = context.outputDirectory
            .appendingPathComponent("Tests/Generated/SwiftInfer/\(suggestion.templateName)/\(fileName)")
        if context.dryRun {
            context.output.write("[dry-run] would write \(path.path)")
            return nil
        }
        let contents = wrappedFileContents(stub: stub, suggestion: suggestion)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: path, options: .atomic)
        context.output.write("Wrote \(path.path)")
        return path
    }

    /// Build the lifted-test source text for `suggestion` if its
    /// template arm has a `LiftedTestEmitter` writeout in v1. M6.3
    /// ships `idempotent` + `roundTrip`; M7.3 adds `monotonicity` +
    /// `invariant-preservation`; M8.2 closes the gap with
    /// `commutativity`, `associativity`, `identity-element`, and
    /// `inverse-pair`. After M8.2 every shipped template has a stub
    /// arm — the `default` branch becomes a defensive fallback for
    /// future templates rather than a v1 limitation.
    private static func liftedTestStub(for suggestion: Suggestion) -> String? {
        switch suggestion.templateName {
        case "idempotence":
            return idempotentStub(for: suggestion)
        case "round-trip":
            return roundTripStub(for: suggestion)
        case "monotonicity":
            return monotonicStub(for: suggestion)
        case "invariant-preservation":
            return invariantPreservingStub(for: suggestion)
        case "commutativity":
            return commutativeStub(for: suggestion)
        case "associativity":
            return associativeStub(for: suggestion)
        case "identity-element":
            return identityElementStub(for: suggestion)
        case "inverse-pair":
            return inversePairStub(for: suggestion)
        default:
            return nil
        }
    }

    private static func idempotentStub(for suggestion: Suggestion) -> String? {
        guard let evidence = suggestion.evidence.first,
              let funcName = functionName(from: evidence.displayName),
              let typeName = paramType(from: evidence.signature) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.idempotent(
            funcName: funcName,
            typeName: typeName,
            seed: seed,
            generator: LiftedTestEmitter.defaultGenerator(for: typeName)
        )
    }

    private static func roundTripStub(for suggestion: Suggestion) -> String? {
        guard suggestion.evidence.count >= 2,
              let forwardEvidence = suggestion.evidence.first,
              let reverseEvidence = suggestion.evidence.dropFirst().first,
              let forwardName = functionName(from: forwardEvidence.displayName),
              let inverseName = functionName(from: reverseEvidence.displayName),
              let forwardParam = paramType(from: forwardEvidence.signature) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.roundTrip(
            forwardName: forwardName,
            inverseName: inverseName,
            seed: seed,
            generator: LiftedTestEmitter.defaultGenerator(for: forwardParam)
        )
    }

    private static func monotonicStub(for suggestion: Suggestion) -> String? {
        guard let evidence = suggestion.evidence.first,
              let funcName = functionName(from: evidence.displayName),
              let typeName = paramType(from: evidence.signature),
              let returnType = returnType(from: evidence.signature) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.monotonic(
            funcName: funcName,
            typeName: typeName,
            returnType: returnType,
            seed: seed,
            generator: LiftedTestEmitter.defaultGenerator(for: typeName)
        )
    }

    private static func invariantPreservingStub(for suggestion: Suggestion) -> String? {
        guard let evidence = suggestion.evidence.first,
              let funcName = functionName(from: evidence.displayName),
              let typeName = paramType(from: evidence.signature),
              let invariantName = invariantKeypath(from: evidence.signature) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.invariantPreserving(
            funcName: funcName,
            typeName: typeName,
            invariantName: invariantName,
            seed: seed,
            generator: LiftedTestEmitter.defaultGenerator(for: typeName)
        )
    }

    private static func commutativeStub(for suggestion: Suggestion) -> String? {
        guard let evidence = suggestion.evidence.first,
              let funcName = functionName(from: evidence.displayName),
              let typeName = paramType(from: evidence.signature) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.commutative(
            funcName: funcName,
            typeName: typeName,
            seed: seed,
            generator: LiftedTestEmitter.defaultGenerator(for: typeName)
        )
    }

    private static func associativeStub(for suggestion: Suggestion) -> String? {
        guard let evidence = suggestion.evidence.first,
              let funcName = functionName(from: evidence.displayName),
              let typeName = paramType(from: evidence.signature) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.associative(
            funcName: funcName,
            typeName: typeName,
            seed: seed,
            generator: LiftedTestEmitter.defaultGenerator(for: typeName)
        )
    }

    /// IdentityElementTemplate emits a 2-row evidence: row 0 is the
    /// binary op (signature `(T, T) -> T`), row 1 is the identity
    /// element (displayName like `"IntSet.empty"` or `"empty"`,
    /// signature `": T"`). Mirror of
    /// `RefactorBridgeOrchestrator.identityWitnessName(from:)` —
    /// strips the optional type prefix so the emitter receives the
    /// bare member name and references it as `\(typeName).\(identityName)`.
    private static func identityElementStub(for suggestion: Suggestion) -> String? {
        guard suggestion.evidence.count >= 2,
              let opEvidence = suggestion.evidence.first,
              let identityEvidence = suggestion.evidence.dropFirst().first,
              let funcName = functionName(from: opEvidence.displayName),
              let typeName = paramType(from: opEvidence.signature) else {
            return nil
        }
        let identityName = bareIdentityName(from: identityEvidence.displayName)
        guard !identityName.isEmpty else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.identityElement(
            funcName: funcName,
            typeName: typeName,
            identityName: identityName,
            seed: seed,
            generator: LiftedTestEmitter.defaultGenerator(for: typeName)
        )
    }

    private static func inversePairStub(for suggestion: Suggestion) -> String? {
        guard suggestion.evidence.count >= 2,
              let forwardEvidence = suggestion.evidence.first,
              let reverseEvidence = suggestion.evidence.dropFirst().first,
              let forwardName = functionName(from: forwardEvidence.displayName),
              let inverseName = functionName(from: reverseEvidence.displayName),
              let forwardParam = paramType(from: forwardEvidence.signature) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.inversePair(
            forwardName: forwardName,
            inverseName: inverseName,
            typeName: forwardParam,
            seed: seed,
            generator: LiftedTestEmitter.defaultGenerator(for: forwardParam)
        )
    }

    /// Strip the optional `\(typeName).` prefix from an identity-element
    /// evidence displayName. `"IntSet.empty"` → `"empty"`; `"empty"` →
    /// `"empty"`. Used by `identityElementStub`.
    private static func bareIdentityName(from displayName: String) -> String {
        guard let dotIndex = displayName.lastIndex(of: ".") else {
            return displayName
        }
        return String(displayName[displayName.index(after: dotIndex)...])
    }

    /// Wrap the bare `@Test func` block from `LiftedTestEmitter` with
    /// the file-level imports + provenance header that the
    /// `Tests/Generated/SwiftInfer/` writeout needs.
    private static func wrappedFileContents(
        stub: String,
        suggestion: Suggestion
    ) -> String {
        let location = suggestion.evidence.first?.location
        let provenance = location.map { loc in "// Source: \(loc.file):\(loc.line)" } ?? ""
        return """
        // Auto-generated by `swift-infer discover --interactive` — do not edit.
        \(provenance)
        // Suggestion identity: \(suggestion.identity.display)
        // Template: \(suggestion.templateName)

        import Testing
        import PropertyBased
        import ProtocolLawKit
        \(stub)
        """
    }

    // MARK: - Conformance-accept (Option B / RefactorBridge — M7.5)

    /// Returns the URL written to (or `nil` for dry-run / extraction
    /// failure). Per PRD §16 #1's allowlist extension, the writeout
    /// goes to `Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift`
    /// — never to existing source files.
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
    /// names (M7.5.a) into the emitter so the writeout aliases the
    /// user's existing op + identity into the kit's required statics.
    /// Returns the always-fail extension for unsupported protocols
    /// (M8 will widen this surface).
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
        default:
            // M7.5 ships only Semigroup + Monoid arms. Future protocol
            // arms (CommutativeMonoid, Group, Semilattice, Ring) get
            // dispatched here as M8 lands them.
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

    // MARK: - Suggestion field extraction

    /// Pull the function identifier out of a display name like
    /// `"normalize(_:)"` → `"normalize"`. Returns `nil` if the format
    /// doesn't match.
    static func functionName(from displayName: String) -> String? {
        guard let parenIndex = displayName.firstIndex(of: "(") else { return nil }
        let name = String(displayName[..<parenIndex])
        guard !name.isEmpty else { return nil }
        return name
    }

    /// Pull the first parameter type out of a signature like
    /// `"(String) -> String"` or `"(Money, Money) -> Money"`.
    /// Whitespace tolerant; returns `nil` if the parens are missing.
    static func paramType(from signature: String) -> String? {
        guard let openIndex = signature.firstIndex(of: "("),
              let closeIndex = signature.firstIndex(of: ")") else {
            return nil
        }
        let inside = signature[signature.index(after: openIndex)..<closeIndex]
        let trimmed = inside.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        let firstComponent = trimmed.split(separator: ",").first.map(String.init) ?? trimmed
        let stripped = firstComponent.trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? nil : stripped
    }

    /// Pull the return type out of a signature like
    /// `"(String) -> Int"` — returns `"Int"`. Strips any trailing
    /// `preserving X` clause that the invariant-preservation template
    /// appends. Returns `nil` if no `->` separator exists.
    static func returnType(from signature: String) -> String? {
        guard let arrowRange = signature.range(of: "->") else { return nil }
        var tail = signature[arrowRange.upperBound...].trimmingCharacters(in: .whitespaces)
        if let preservingRange = tail.range(of: " preserving ") {
            tail = String(tail[..<preservingRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return tail.isEmpty ? nil : tail
    }

    /// Pull the keypath text out of an invariant-preservation signature
    /// like `"(Widget) -> Widget preserving \\.isValid"` — returns
    /// `"\\.isValid"`. Returns `nil` if the `preserving` marker is absent
    /// (the signature isn't from `InvariantPreservationTemplate`).
    static func invariantKeypath(from signature: String) -> String? {
        guard let preservingRange = signature.range(of: " preserving ") else { return nil }
        let tail = signature[preservingRange.upperBound...].trimmingCharacters(in: .whitespaces)
        return tail.isEmpty ? nil : tail
    }

    // MARK: - Decision record construction

    static func makeRecord(
        for suggestion: Suggestion,
        decision: Decision,
        timestamp: Date
    ) -> DecisionRecord {
        DecisionRecord(
            identityHash: suggestion.identity.normalized,
            template: suggestion.templateName,
            scoreAtDecision: suggestion.score.total,
            tier: suggestion.score.tier,
            decision: decision,
            timestamp: timestamp,
            signalWeights: suggestion.score.signals.map { signal in
                SignalSnapshot(kind: signal.kind.rawValue, weight: signal.weight)
            }
        )
    }

    // MARK: - File-name helpers

    private static func stubFileName(for suggestion: Suggestion) -> String? {
        guard let evidence = suggestion.evidence.first,
              let funcName = functionName(from: evidence.displayName) else {
            return nil
        }
        switch suggestion.templateName {
        case "round-trip":
            guard let reverse = suggestion.evidence.dropFirst().first,
                  let reverseName = functionName(from: reverse.displayName) else {
                return "\(funcName).swift"
            }
            return "\(funcName)_\(reverseName).swift"
        case "invariant-preservation":
            // Same function with two different keypaths is two distinct
            // suggestions per InvariantPreservationTemplate's identity
            // rule — the file name carries the keypath suffix so accept
            // doesn't overwrite a previous accept on the other keypath.
            guard let keyPath = invariantKeypath(from: evidence.signature) else {
                return "\(funcName).swift"
            }
            let suffix = keyPath
                .replacingOccurrences(of: "\\.", with: "")
                .replacingOccurrences(of: ".", with: "_")
            return "\(funcName)_\(suffix).swift"
        default:
            return "\(funcName).swift"
        }
    }
}
// swiftlint:enable file_length
