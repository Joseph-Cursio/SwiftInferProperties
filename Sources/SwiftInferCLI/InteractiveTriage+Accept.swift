import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// Accept-path for lifted-test stubs (Option A — `LiftedTestEmitter`
/// writeouts to `Tests/Generated/SwiftInfer/<template>/<file>.swift`).
/// The conformance-accept path (Option B — `LiftedConformanceEmitter`
/// writeouts) lives in `InteractiveTriage+AcceptConformance.swift`;
/// extraction helpers live in `InteractiveTriage+Extraction.swift`.
extension InteractiveTriage {

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
    /// `WitnessExtractor.identityWitnessName(from:)` — strips the
    /// optional type prefix so the emitter receives the bare member
    /// name and references it as `\(typeName).\(identityName)`.
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
