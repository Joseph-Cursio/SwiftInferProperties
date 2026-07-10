import Foundation
import PropertyLawCore
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
        // M11.2 / M13.3 / M16.3 — advisory writeouts dispatched on
        // templateName; hints carried out-of-band on Context (§13 row 4).
        if suggestion.templateName == "equivalence-class",
           let kind = context.equivalenceClassHintsByIdentity[suggestion.identity] {
            switch kind {
            case .twoClass(let hint):
                return try writeEquivalenceClassDocument(hint: hint, context: context)

            case .nClass(let hint):
                return try writeNClassEquivalenceClassDocument(hint: hint, context: context)
            }
        }
        if suggestion.templateName == "consumer-producer-chain",
           let hint = context.consumerProducerChainHintsByIdentity[suggestion.identity] {
            return try writeConsumerProducerChainDocument(hint: hint, context: context)
        }
        // A whole-module resolver that derives a generator for any project type
        // from its parsed shape (memoized, cycle-guarded). Built per accept; the
        // stub emitter uses it so custom-typed parameters compile without a
        // hand-written `gen()`.
        let resolver = GeneratorResolver(types: Array(context.typeShapesByName.values))
        let customGenerator: (String) -> String? = { typeName in
            resolver.customTypeGenerator(forTypeName: typeName)?.expression
        }
        guard let stub = liftedTestStub(for: suggestion, customGenerator: customGenerator) else {
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

    /// Build the lifted-test source text for `suggestion`. After M8.2
    /// every shipped template has a stub arm — `default` is a
    /// defensive fallback for future templates.
    /// `customGenerator` derives a generator expression for a custom type name
    /// (from the project's parsed type shapes); it's currently wired into the
    /// determinism path — the lint → infer pipeline's output — so a seeded
    /// function over a custom struct/enum compiles drop-in. The signature-pattern
    /// stubs still use the `Type.gen()` fallback (a fast-follow).
    private static func liftedTestStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)? = nil
    ) -> String? {
        // M5.5 — lifted-only fast path for countInvariance + reduce-
        // Equivalence: emit what the test body actually claimed rather
        // than the stronger algebraic shape. Production-side suggestions
        // (no `liftedOrigin`) continue through the existing switch.
        if let liftedOnly = liftedOnlyTestStub(for: suggestion) {
            return liftedOnly
        }
        // Determinism is the seed-driven generic law (not a signature template),
        // so it dispatches ahead of the template switch.
        if suggestion.templateName == "determinism" {
            return deterministicStub(for: suggestion, customGenerator: customGenerator)
        }
        return templateStub(for: suggestion)
    }

    /// Dispatches a signature-pattern template suggestion to its stub emitter.
    private static func templateStub(for suggestion: Suggestion) -> String? {
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

    /// Determinism stub for a seeded pure function `f: (P0, …) -> U`. Builds one
    /// generator per parameter and emits `f(args) == f(args)`. Equality keys off
    /// the return type. An `Int` parameter uses a *bounded* generator (see
    /// `boundedDeterminismGenerator`) so unchecked arithmetic in `f` doesn't trap
    /// on overflow.
    private static func deterministicStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)? = nil
    ) -> String? {
        guard let evidence = suggestion.evidence.first,
              let funcName = functionName(from: evidence.displayName) else {
            return nil
        }
        // Async candidates (clock-deterministic-annotated; the discover gate
        // admits no other async) render as `(P0) async -> U` in the evidence
        // signature — detect the marker, then parse the de-sugared form so
        // the existing parameter/return extraction stays untouched.
        let isAsync = evidence.signature.contains(" async ->")
        let signature = isAsync
            ? evidence.signature.replacingOccurrences(of: " async ->", with: " ->")
            : evidence.signature
        guard let returnTypeText = returnType(from: signature),
              let parsed = functionParameters(
                  displayName: evidence.displayName,
                  signature: signature
              ) else {
            return nil
        }
        let parameters = parsed.map { parameter in
            LiftedTestEmitter.DeterminismParameter(
                label: parameter.label,
                generator: boundedDeterminismGenerator(forTypeName: parameter.type)
                    ?? chooseGenerator(
                        for: suggestion,
                        typeName: parameter.type,
                        customGenerator: customGenerator
                    )
            )
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.deterministic(
            funcName: funcName,
            parameters: parameters,
            seed: seed,
            equalityKind: equalityKind(forTypeText: returnTypeText),
            isAsync: isAsync
        )
    }

    /// A bounded generator for a numeric parameter type in a *determinism* stub,
    /// or `nil` for non-numeric types (the caller then chooses normally).
    ///
    /// The determinism law `f(x) == f(x)` is a tautology for a pure function, so
    /// it reveals hidden nondeterminism on *any* input — a narrow domain loses no
    /// coverage. Bounding `Int` to ±10_000 keeps unchecked arithmetic (`a * b`,
    /// `a + b`) from overflow-trapping on the full-range extremes a default
    /// `Gen<Int>.int()` would draw, which would crash the test rather than
    /// falsify the law. (Other templates keep full-range generators, where
    /// extremes do matter.)
    static func boundedDeterminismGenerator(forTypeName typeName: String) -> String? {
        switch typeName {
        case "Int":
            return "Gen<Int>.int(in: -10_000 ... 10_000)"

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
            generator: chooseGenerator(for: suggestion, typeName: typeName),
            equalityKind: equalityKind(forTypeText: typeName)
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
            generator: chooseGenerator(for: suggestion, typeName: forwardParam),
            equalityKind: equalityKind(forTypeText: forwardParam)
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

    /// IdentityElementTemplate emits 2-row evidence: row 0 binary op,
    /// row 1 identity element (displayName like `"IntSet.empty"` or `"empty"`,
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
            generator: chooseGenerator(for: suggestion, typeName: forwardParam),
            equalityKind: equalityKind(forTypeText: forwardParam)
        )
    }

    /// V1.31.C — derives the `LiftedTestEmitter.EqualityKind` from a
    /// suggestion's carrier or forward-parameter type text. Returns
    /// `.approximate` when the type is in
    /// `FloatingPointEquatableTypes.curated` (with generic-parameter
    /// stripping) — required for `Complex`, `Double`, `Float`, etc.
    /// round-trip / idempotent / inverse-pair assertions to compile and
    /// pass under IEEE 754 rounding. Returns `.strict` otherwise
    /// (current behavior preserved for all non-FP carriers).
    ///
    /// **Module-internal** so the V1.31.C integration tests can verify
    /// the dispatch table directly without round-tripping through the
    /// full `liftedTestStub(for:)` path.
    static func equalityKind(
        forTypeText typeText: String
    ) -> LiftedTestEmitter.EqualityKind {
        FloatingPointEquatableTypes.isFloatingPointEquatable(typeText: typeText)
            ? .approximate
            : .strict
    }

    /// TestLifter M4.4 — pick the right generator string based on the
    /// suggestion's source. Mock-inferred suggestions (M4.3) carry a
    /// populated `mockGenerator` field that the
    /// `LiftedTestEmitter.mockInferredGenerator` renderer translates
    /// into a `zip(...).map { Type(...) }` shape using the kit's
    /// RawType generator factories. All other suggestions fall back to
    /// `defaultGenerator(for:)` — the M3.3 behavior preserved.
    ///
    /// **Module-private (not file-private)** so the M5.5 lifted-only
    /// dispatch helpers in `InteractiveTriage+AcceptM5.swift` can
    /// share the same dispatch without duplicating the priority order.
    static func chooseGenerator(
        for suggestion: Suggestion,
        typeName: String,
        customGenerator: ((String) -> String?)? = nil
    ) -> String {
        if suggestion.generator.source == .inferredFromTests,
           let mock = suggestion.mockGenerator {
            return LiftedTestEmitter.mockInferredGenerator(mock)
        }
        if suggestion.generator.source == .derivedCodableRoundTrip {
            return LiftedTestEmitter.codableRoundTripGenerator(for: typeName)
        }
        // Derive a generator for a custom project type — a memberwise struct, a
        // CaseIterable / RawRepresentable / payload enum — from its parsed shape,
        // so the stub compiles without the user hand-writing `gen()`. Stdlib and
        // external types have no shape, so the resolver returns nil and we fall
        // through to the stdlib mapping (or the `Type.gen()` fallback).
        if let derived = customGenerator?(typeName) {
            return derived
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
}
