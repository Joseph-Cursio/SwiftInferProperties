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
        // A stub naming a type parameter cannot compile under any budget, generator or import,
        // so it is withdrawn before an emitter spends work on it — the availability gate's
        // posture, which shipped at 0.58% of rows because it cost no laws (#493).
        if let reason = gateDeclineReason(for: suggestion, context: context) {
            context.diagnostics.writeDiagnostic(
                "note: no stub written — \(reason); decision recorded without writing a file"
            )
            return nil
        }
        let (customGenerator, drawn) = recordingGenerator(for: context)
        guard let stub = liftedTestStub(
            for: suggestion,
            customGenerator: customGenerator,
            receiverExpression: Self.receiverExpression(for: context)
        ) else {
            reportNoStub(for: suggestion, context: context)
            return nil
        }
        let path = stubDestination(for: suggestion, context: context)
        let fileName = path.lastPathComponent
        if context.dryRun {
            context.output.write("[dry-run] would write \(path.path)")
            return nil
        }
        let contents = wrappedFileContents(
            stub: stub,
            suggestion: suggestion,
            moduleUnderTest: context.moduleUnderTest,
            fileName: fileName,
            carrierImports: Self.carrierImports(for: context)
        )
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: path, options: .atomic)
        context.output.write("Wrote \(path.path)")
        try writeSendableShims(for: drawn.typeNames, context: context)
        return path
    }

    /// Build the lifted-test source text for `suggestion`.
    ///

    /// Determinism stub for a seeded pure function `f: (P0, …) -> U`. Builds one
    /// generator per argument and emits `f(args) == f(args)`. Equality keys off
    /// the return type. An `Int` argument uses a *bounded* generator (see
    /// `boundedDeterminismGenerator`) so unchecked arithmetic in `f` doesn't trap
    /// on overflow.
    ///
    /// **Spelled through `CalleeReference`, like every other arm (#465).** This arm took the bare
    /// function name and so wrote `tokenizeLine(value)` for a member of `SwiftTokenizer`; across
    /// the corpus funnel census all 33 determinism stubs that compiled were free functions. A
    /// static member is now qualified, and an instance method draws its receiver from the
    /// declaring type ahead of its parameters — the same argument list, and the same declines,
    /// as the totality arm (`arityFreeArgumentTypes`). Internal rather than private so the
    /// accept path's behaviour can be tested without writing files.
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

    static func idempotentStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)? = nil
    ) -> String? {
        let generatorFor = boundGenerator(for: suggestion, customGenerator: customGenerator)
        guard let evidence = suggestion.evidence.first,
              let callee = CalleeReference(evidence: evidence),
              let arity = StubApplicationArity.forTemplate(suggestion.templateName),
              callee.accepts(applicationArity: arity),
              let typeName = carrierType(for: evidence) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.idempotent(
            callee: callee,
            typeName: typeName,
            seed: seed,
            generator: generatorFor(typeName),
            equalityKind: equalityKind(forTypeText: typeName)
        )
    }

    /// Replay-idempotency scaffold for a `ReplayIdempotenceTemplate` suggestion.
    /// Extracts the handler name, its `IdempotencyKey` parameter label (if any),
    /// and the async/throws effect markers from the evidence signature, then hands
    /// off to `LiftedTestEmitter.replayIdempotent`. Unlike the value stubs this
    /// emits a `.todo`-style scaffold — see that emitter for why.
    static func replayIdempotentStub(for suggestion: Suggestion) -> String? {
        guard let evidence = suggestion.evidence.first,
              let funcName = functionName(from: evidence.displayName) else {
            return nil
        }
        let isAsync = evidence.signature.contains(" async")
        let isThrows = evidence.signature.contains(" throws")
        // A key-from-entity builder (M6) is a pure value builder — emit the VALUE
        // form (`#assertIdempotent`), not the effect form. Distinguished by its
        // signal's marker line in the explainability block.
        let isKeyBuilder = suggestion.explainability.whySuggested
            .contains { $0.contains("Constructs an `IdempotencyKey`") }
        if isKeyBuilder {
            return LiftedTestEmitter.replayKeyBuilder(
                funcName: funcName,
                ownerType: suggestion.carrier,
                isThrows: isThrows
            )
        }
        let signature = evidence.signature
            .replacingOccurrences(of: " async throws ->", with: " ->")
            .replacingOccurrences(of: " async ->", with: " ->")
            .replacingOccurrences(of: " throws ->", with: " ->")
        let keyLabel = functionParameters(
            displayName: evidence.displayName,
            signature: signature
        )?.first { $0.type == "IdempotencyKey" }?.label
        return LiftedTestEmitter.replayIdempotent(
            funcName: funcName,
            keyLabel: keyLabel,
            ownerType: suggestion.carrier,
            isAsync: isAsync,
            isThrows: isThrows
        )
    }

    static func roundTripStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)? = nil
    ) -> String? {
        let generatorFor = boundGenerator(for: suggestion, customGenerator: customGenerator)
        guard suggestion.evidence.count >= 2,
              let forwardEvidence = suggestion.evidence.first,
              let reverseEvidence = suggestion.evidence.dropFirst().first,
              let forward = CalleeReference(evidence: forwardEvidence),
              let inverse = CalleeReference(evidence: reverseEvidence),
              let arity = StubApplicationArity.forTemplate(suggestion.templateName),
              forward.accepts(applicationArity: arity),
              inverse.accepts(applicationArity: arity),
              let forwardParam = paramType(from: forwardEvidence.signature) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.roundTrip(
            forward: forward,
            inverse: inverse,
            seed: seed,
            generator: generatorFor(forwardParam),
            equalityKind: equalityKind(forTypeText: forwardParam)
        )
    }

    static func monotonicStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)? = nil
    ) -> String? {
        let generatorFor = boundGenerator(for: suggestion, customGenerator: customGenerator)
        guard let evidence = suggestion.evidence.first,
              let callee = CalleeReference(evidence: evidence),
              let arity = StubApplicationArity.forTemplate(suggestion.templateName),
              callee.accepts(applicationArity: arity),
              let typeName = paramType(from: evidence.signature),
              // `monotonicity` sorts a drawn pair with `<`, so the carrier must be orderable.
              // An `Optional` is not `Comparable`, and the resulting error names the closure
              // rather than the comparison — see `isOrderableCarrier`.
              FloatingPointEquatableTypes.isOrderableCarrier(typeText: typeName),
              let returnType = returnType(from: evidence.signature) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.monotonic(
            callee: callee,
            typeName: typeName,
            returnType: returnType,
            seed: seed,
            generator: generatorFor(typeName)
        )
    }

    static func invariantPreservingStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)? = nil
    ) -> String? {
        let generatorFor = boundGenerator(for: suggestion, customGenerator: customGenerator)
        guard let evidence = suggestion.evidence.first,
              let callee = CalleeReference(evidence: evidence),
              let arity = StubApplicationArity.forTemplate(suggestion.templateName),
              callee.accepts(applicationArity: arity),
              let typeName = paramType(from: evidence.signature),
              let invariantName = invariantKeypath(from: evidence.signature) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.invariantPreserving(
            callee: callee,
            typeName: typeName,
            invariantName: invariantName,
            seed: seed,
            generator: generatorFor(typeName)
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
    /// - Parameter failureReason: consulted only on the `.todo` arm, so the marker can name the
    ///   kit's own account of why nothing derived instead of the one fixed sentence every stub
    ///   carried. Optional, because most callers do not hold a resolver and a marker without a
    ///   reason is what they rendered before.
    static func chooseGenerator(
        for suggestion: Suggestion,
        typeName: String,
        customGenerator: ((String) -> String?)? = nil,
        failureReason: ((String) -> String?)? = nil
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
        let reason = failureReason?(typeName)
        // The subject's own literals, for a `String` carrier only — the one type the kit mixes them
        // into — so a file is parsed only where the answer can change the stub.
        let literals = RawType(typeName: typeName) == .string ? SubjectLiterals.of(suggestion) : []
        return LiftedTestEmitter.defaultGenerator(for: typeName, reason: reason, subjectLiterals: literals)
    }

    /// Strip the optional `\(typeName).` prefix from an identity-element
    /// evidence displayName. `"IntSet.empty"` → `"empty"`; `"empty"` →
    /// `"empty"`. Used by `identityElementStub`.
    static func bareIdentityName(from displayName: String) -> String {
        guard let dotIndex = displayName.lastIndex(of: ".") else {
            return displayName
        }
        return String(displayName[displayName.index(after: dotIndex)...])
    }
}
