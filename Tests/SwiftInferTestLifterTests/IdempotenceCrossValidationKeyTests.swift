import SwiftInferCore
import SwiftInferTemplates
import Testing
@testable import SwiftInferTestLifter

@Suite("LiftedSuggestion.idempotence — cross-validation-key parity (M2.3)")
struct IdempotenceCrossValidationKeyTests {

    @Test("LiftedSuggestion.idempotence produces the (\"idempotence\", [calleeName]) key")
    func factoryProducesExpectedKey() {
        let detection = DetectedIdempotence(
            calleeName: "normalize",
            inputBindingName: "s",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.idempotence(from: detection)
        #expect(lifted.templateName == "idempotence")
        #expect(lifted.crossValidationKey.templateName == "idempotence")
        #expect(lifted.crossValidationKey.calleeNames == ["normalize"])
        #expect(lifted.pattern == .idempotence(detection))
    }

    /// Load-bearing M2.3 invariant: a LiftedSuggestion derived from a
    /// test body's idempotence detection produces a CrossValidationKey
    /// byte-identical to the CrossValidationKey of TemplateEngine's
    /// IdempotenceTemplate suggestion for the same callee. This is what
    /// makes the +20 cross-validation signal fire end-to-end for
    /// idempotence claims.
    @Test("LiftedSuggestion.crossValidationKey matches IdempotenceTemplate's for the same callee")
    func liftedKeyMatchesTemplateEngineKey() throws {
        // Production-side: build a function summary for `normalize(_:)`
        // and run it through TemplateEngine's discover. `normalize` is
        // in IdempotenceTemplate.curatedVerbs so the suggestion fires
        // (typeSymmetry +30, name +40 → likely tier).
        let normalize = FunctionSummary(
            name: "normalize",
            parameters: [Parameter(label: nil, internalName: "value", typeText: "String", isInout: false)],
            returnTypeText: "String",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Normalizer.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let suggestions = TemplateRegistry.discover(in: [normalize])
        let templateEngineIdempotence = try #require(
            suggestions.first { $0.templateName == "idempotence" }
        )
        let templateEngineKey = templateEngineIdempotence.crossValidationKey

        let detection = DetectedIdempotence(
            calleeName: "normalize",
            inputBindingName: "s",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.idempotence(from: detection)

        #expect(lifted.crossValidationKey == templateEngineKey)
    }

    @Test("End-to-end: LiftedSuggestion.idempotence's key feeds discover and lights up +20")
    func endToEndCrossValidationLightUp() throws {
        let normalize = FunctionSummary(
            name: "normalize",
            parameters: [Parameter(label: nil, internalName: "value", typeText: "String", isInout: false)],
            returnTypeText: "String",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Normalizer.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )

        let baseline = TemplateRegistry.discover(in: [normalize])
        let baselineIdempotence = try #require(baseline.first { $0.templateName == "idempotence" })
        let baselineTotal = baselineIdempotence.score.total

        let detection = DetectedIdempotence(
            calleeName: "normalize",
            inputBindingName: "s",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.idempotence(from: detection)
        let liftedKeys: Set<CrossValidationKey> = [lifted.crossValidationKey]

        let crossValidated = TemplateRegistry.discover(
            in: [normalize],
            crossValidationFromTestLifter: liftedKeys
        )
        let liftedIdempotence = try #require(crossValidated.first { $0.templateName == "idempotence" })
        #expect(liftedIdempotence.score.total == baselineTotal + 20)
        #expect(liftedIdempotence.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
        #expect(
            liftedIdempotence.explainability.whySuggested.contains { $0.contains("Cross-validated by TestLifter") }
        )
    }

    @Test("Mismatched callees produce different keys (no false +20)")
    func unrelatedKeysDoNotCollide() {
        let normalizeKey = LiftedSuggestion.idempotence(from: DetectedIdempotence(
            calleeName: "normalize",
            inputBindingName: "s",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        let canonicalizeKey = LiftedSuggestion.idempotence(from: DetectedIdempotence(
            calleeName: "canonicalize",
            inputBindingName: "s",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        #expect(normalizeKey != canonicalizeKey)
    }

    @Test("Idempotence key doesn't collide with round-trip key for the same name")
    func idempotenceDoesNotCollideWithRoundTrip() {
        let idempotenceKey = LiftedSuggestion.idempotence(from: DetectedIdempotence(
            calleeName: "encode",
            inputBindingName: "x",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        let roundTripKey = LiftedSuggestion.roundTrip(from: DetectedRoundTrip(
            forwardCallee: "encode",
            backwardCallee: "decode",
            inputBindingName: "x",
            recoveredBindingName: nil,
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )).crossValidationKey
        // Same callee name "encode" wouldn't collide because the
        // template name namespaces the key.
        #expect(idempotenceKey != roundTripKey)
    }
}
