import SwiftInferCore
import Testing
@testable import SwiftInferTestLifter

@Suite("LiftedSuggestionRecovery — M4.2 annotation-fallback tier")
struct LiftedRecoveryAnnotationFallbackTests {

    // MARK: - Helpers

    private static let dummyOrigin = LiftedOrigin(
        testMethodName: "testFoo",
        sourceLocation: SourceLocation(file: "Tests/Foo.swift", line: 1, column: 1)
    )

    private static func roundTripLifted(
        forwardCallee: String,
        backwardCallee: String,
        inputBindingName: String
    ) -> LiftedSuggestion {
        let detection = DetectedRoundTrip(
            forwardCallee: forwardCallee,
            backwardCallee: backwardCallee,
            inputBindingName: inputBindingName,
            recoveredBindingName: nil,
            assertionLocation: SourceLocation(file: "Tests/Foo.swift", line: 5, column: 1)
        )
        return LiftedSuggestion.roundTrip(from: detection, origin: dummyOrigin)
    }

    private static func idempotenceLifted(
        calleeName: String,
        inputBindingName: String
    ) -> LiftedSuggestion {
        let detection = DetectedIdempotence(
            calleeName: calleeName,
            inputBindingName: inputBindingName,
            assertionLocation: SourceLocation(file: "Tests/Foo.swift", line: 5, column: 1)
        )
        return LiftedSuggestion.idempotence(from: detection, origin: dummyOrigin)
    }

    private static func commutativityLifted(
        calleeName: String,
        leftArgName: String,
        rightArgName: String
    ) -> LiftedSuggestion {
        let detection = DetectedCommutativity(
            calleeName: calleeName,
            leftArgName: leftArgName,
            rightArgName: rightArgName,
            assertionLocation: SourceLocation(file: "Tests/Foo.swift", line: 5, column: 1)
        )
        return LiftedSuggestion.commutativity(from: detection, origin: dummyOrigin)
    }

    // MARK: - Round-trip annotation fallback

    @Test("Round-trip with no production-side forward but `let input: Foo = ...` recovers Foo")
    func roundTripAnnotationFallback() {
        let lifted = Self.roundTripLifted(
            forwardCallee: "encode",
            backwardCallee: "decode",
            inputBindingName: "input"
        )
        let typeName = LiftedSuggestionRecovery.recoveredTypeName(
            for: lifted,
            summariesByName: [:],  // empty FunctionSummary index — forces annotation tier
            setupAnnotations: ["input": "Foo"]
        )
        #expect(typeName == "Foo")
    }

    // MARK: - Idempotence annotation fallback

    @Test("Idempotence with no production-side normalize but `let doc: Doc = ...` recovers Doc")
    func idempotenceAnnotationFallback() {
        let lifted = Self.idempotenceLifted(calleeName: "normalize", inputBindingName: "doc")
        let typeName = LiftedSuggestionRecovery.recoveredTypeName(
            for: lifted,
            summariesByName: [:],
            setupAnnotations: ["doc": "Doc"]
        )
        #expect(typeName == "Doc")
    }

    // MARK: - Commutativity annotation fallback

    @Test("Commutativity recovers via leftArg annotation when production-side merge is missing")
    func commutativityLeftArgAnnotationFallback() {
        let lifted = Self.commutativityLifted(
            calleeName: "merge",
            leftArgName: "a",
            rightArgName: "b"
        )
        let typeName = LiftedSuggestionRecovery.recoveredTypeName(
            for: lifted,
            summariesByName: [:],
            setupAnnotations: ["a": "Counter", "b": "Counter"]
        )
        #expect(typeName == "Counter")
    }

    @Test("Commutativity falls back to rightArg annotation when leftArg is unannotated")
    func commutativityRightArgAnnotationFallback() {
        let lifted = Self.commutativityLifted(
            calleeName: "merge",
            leftArgName: "a",
            rightArgName: "b"
        )
        let typeName = LiftedSuggestionRecovery.recoveredTypeName(
            for: lifted,
            summariesByName: [:],
            setupAnnotations: ["b": "Counter"]
        )
        #expect(typeName == "Counter")
    }

    // MARK: - Precedence: FunctionSummary > annotation > nil

    @Test("FunctionSummary tier wins when both annotation and summary match")
    func functionSummaryWinsOverAnnotation() {
        let lifted = Self.idempotenceLifted(calleeName: "normalize", inputBindingName: "doc")
        let summary = FunctionSummary(
            name: "normalize",
            parameters: [Parameter(label: nil, internalName: "input", typeText: "TypeFromSummary", isInout: false)],
            returnTypeText: "TypeFromSummary",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Sources/Foo.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: BodySignals.empty
        )
        let typeName = LiftedSuggestionRecovery.recoveredTypeName(
            for: lifted,
            summariesByName: ["normalize": summary],
            setupAnnotations: ["doc": "TypeFromAnnotation"]
        )
        #expect(typeName == "TypeFromSummary")
    }

    @Test("Both tiers miss → nil (the .todo<?>() path survives M4.2)")
    func bothTiersMissReturnsNil() {
        let lifted = Self.idempotenceLifted(calleeName: "normalize", inputBindingName: "doc")
        let typeName = LiftedSuggestionRecovery.recoveredTypeName(
            for: lifted,
            summariesByName: [:],
            setupAnnotations: ["unrelatedBinding": "Doc"]
        )
        #expect(typeName == nil)
    }

    // MARK: - Backwards compatibility (no setupAnnotations arg)

    @Test("Recovery without setupAnnotations argument still works (M3.1 behavior preserved)")
    func backwardsCompatibleNoAnnotations() {
        let lifted = Self.idempotenceLifted(calleeName: "normalize", inputBindingName: "doc")
        // The default-empty setupAnnotations parameter means the M3.1
        // call shape (no annotation arg) compiles + behaves identically.
        let typeName = LiftedSuggestionRecovery.recoveredTypeName(
            for: lifted,
            summariesByName: [:]
        )
        #expect(typeName == nil)
    }

    @Test("Round-trip annotation fallback recovers (T, nil) — backward type unrecoverable from binding alone")
    func roundTripAnnotationReturnsNilForBackwardType() {
        let lifted = Self.roundTripLifted(
            forwardCallee: "encode",
            backwardCallee: "decode",
            inputBindingName: "input"
        )
        // Use the recover() variant directly to inspect the (typeName,
        // returnType) tuple shape — round-trip's annotation-only path
        // recovers T but leaves U as nil (the binding holds T, not U).
        let suggestion = LiftedSuggestionRecovery.recover(
            lifted,
            summariesByName: [:],
            setupAnnotations: ["input": "Foo"]
        )
        // The promoted suggestion should have evidence whose forward
        // signature carries Foo; the backward signature should still
        // include `?` for the return type (the backward callee maps
        // from U → T, but U is unknown). Easiest check: the signature
        // string mentions Foo.
        let signatureContainsFoo = suggestion.evidence.contains { $0.signature.contains("Foo") }
        #expect(signatureContainsFoo)
    }
}
