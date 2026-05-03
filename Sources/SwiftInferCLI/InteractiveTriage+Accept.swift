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
            generator: chooseGenerator(for: suggestion, typeName: typeName)
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
            generator: chooseGenerator(for: suggestion, typeName: forwardParam)
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
            generator: chooseGenerator(for: suggestion, typeName: typeName)
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
            generator: chooseGenerator(for: suggestion, typeName: typeName)
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
            generator: chooseGenerator(for: suggestion, typeName: typeName)
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
            generator: chooseGenerator(for: suggestion, typeName: typeName)
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
            generator: chooseGenerator(for: suggestion, typeName: typeName)
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
            generator: chooseGenerator(for: suggestion, typeName: forwardParam)
        )
    }

    /// TestLifter M4.4 — pick the right generator string based on the
    /// suggestion's source. Mock-inferred suggestions (M4.3) carry a
    /// populated `mockGenerator` field that the
    /// `LiftedTestEmitter.mockInferredGenerator` renderer translates
    /// into a `zip(...).map { Type(...) }` shape using the kit's
    /// RawType generator factories. All other suggestions fall back to
    /// `defaultGenerator(for:)` — the M3.3 behavior preserved.
    private static func chooseGenerator(
        for suggestion: Suggestion,
        typeName: String
    ) -> String {
        if suggestion.generator.source == .inferredFromTests,
           let mock = suggestion.mockGenerator {
            return LiftedTestEmitter.mockInferredGenerator(mock)
        }
        if suggestion.generator.source == .derivedCodableRoundTrip {
            return LiftedTestEmitter.codableRoundTripGenerator(for: typeName)
        }
        return LiftedTestEmitter.defaultGenerator(for: typeName)
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
    /// `Tests/Generated/SwiftInfer/` writeout needs. Lifted-origin
    /// suggestions get an extra "Lifted from" line pointing at the
    /// originating test method (TestLifter M3.3) so the writeout is
    /// self-explanatory about its TestLifter provenance — distinct
    /// from the existing `// Source:` line which points at the
    /// promoted Suggestion's `evidence[0].location` (which for lifted
    /// suggestions is the assertion site, not the test method
    /// declaration).
    private static func wrappedFileContents(
        stub: String,
        suggestion: Suggestion
    ) -> String {
        let location = suggestion.evidence.first?.location
        let sourceLine = location.map { loc in "// Source: \(loc.file):\(loc.line)" } ?? ""
        let liftedLine = suggestion.liftedOrigin.map { origin in
            "// Lifted from \(origin.sourceLocation.file):\(origin.sourceLocation.line)"
                + " \(origin.testMethodName)()"
        } ?? ""
        // TestLifter M4.4 — mock-inferred suggestions get an extra
        // provenance line surfacing the synthesized generator's
        // construction-site count + the .low confidence the user
        // should treat the generator with. PRD §3.5 conservative-bias
        // reinforcement at the writeout layer.
        let mockLine: String = {
            guard suggestion.generator.source == .inferredFromTests,
                  let mock = suggestion.mockGenerator else {
                return ""
            }
            return "// Mock-inferred from \(mock.siteCount) construction"
                + " site\(mock.siteCount == 1 ? "" : "s") in test bodies — low confidence"
                + " (verify the generator covers your domain)"
        }()
        // TestLifter M5.4 — Codable round-trip suggestions get a
        // provenance line surfacing the .medium confidence and the
        // user-action requirement (replacing the placeholder fixture
        // before the generator buys you a real round-trip property).
        let codableLine: String = {
            guard suggestion.generator.source == .derivedCodableRoundTrip else {
                return ""
            }
            return "// Codable round-trip generator scaffold — medium confidence"
                + " (replace the fixture inside the generator body before this"
                + " property exercises real values)"
        }()
        // M5.4 — Foundation is required for the JSONEncoder / JSONDecoder
        // calls inside the Codable round-trip generator scaffold.
        // Otherwise the wrapper sticks to the M3.3 imports list.
        let foundationImport = suggestion.generator.source == .derivedCodableRoundTrip
            ? "import Foundation\n"
            : ""
        return """
        // Auto-generated by `swift-infer discover --interactive` — do not edit.
        \(sourceLine)
        \(liftedLine)
        \(mockLine)
        \(codableLine)
        // Suggestion identity: \(suggestion.identity.display)
        // Template: \(suggestion.templateName)

        \(foundationImport)import Testing
        import PropertyBased
        import ProtocolLawKit
        \(stub)
        """
    }

    private static func stubFileName(for suggestion: Suggestion) -> String? {
        // TestLifter M3.3 — lifted-origin suggestions get a
        // `<TestMethodName>_lifted_<TemplateName>.swift` name so they
        // disambiguate from TemplateEngine-accepted writeouts in the
        // same `<template>/` subdirectory (M3 plan OD #6 default).
        // The `_lifted_` infix is the load-bearing token — avoids
        // collision when one test method body lifts multiple patterns
        // (rare but possible).
        if let origin = suggestion.liftedOrigin {
            let sanitizedMethod = sanitizeForFileName(origin.testMethodName)
            let sanitizedTemplate = sanitizeForFileName(suggestion.templateName)
            return "\(sanitizedMethod)_lifted_\(sanitizedTemplate).swift"
        }
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

    /// Replace `/`, whitespace, and other path-hostile characters with
    /// `_` so file-name components from `LiftedOrigin.testMethodName`
    /// or `Suggestion.templateName` (e.g. `"round-trip"` → `"round-trip"`,
    /// `"identity-element"` → `"identity-element"`) don't introduce
    /// path separators or shell-special characters into writeout paths.
    /// Hyphens are preserved — they're safe and they're the natural
    /// shape of `Suggestion.templateName` values.
    private static func sanitizeForFileName(_ raw: String) -> String {
        let allowed: Set<Character> = Set(
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
        )
        return String(raw.map { allowed.contains($0) ? $0 : "_" })
    }
}
