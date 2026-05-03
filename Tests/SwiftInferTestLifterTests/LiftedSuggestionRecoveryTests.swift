import SwiftInferCore
import Testing
@testable import SwiftInferTestLifter

@Suite("LiftedSuggestionRecovery — type recovery via FunctionSummary lookup (M3.1)")
struct LiftedSuggestionRecoveryTests {

    // MARK: - Round-trip: free-function pair

    @Test("Round-trip recovery of (Int) -> String / (String) -> Int from free-function summaries")
    func roundTripRecoveryFreeFunctionPair() {
        let detection = DetectedRoundTrip(
            forwardCallee: "encode",
            backwardCallee: "decode",
            inputBindingName: "value",
            recoveredBindingName: nil,
            assertionLocation: SourceLocation(file: "CodecTests.swift", line: 10, column: 5)
        )
        let lifted = LiftedSuggestion.roundTrip(from: detection)
        let summaries = LiftedSuggestionRecovery.summariesByName([
            makeFreeFunction(name: "encode", paramType: "Int", returnType: "String"),
            makeFreeFunction(name: "decode", paramType: "String", returnType: "Int")
        ])

        let suggestion = LiftedSuggestionRecovery.recover(lifted, summariesByName: summaries)

        #expect(suggestion.evidence.count == 2)
        #expect(suggestion.evidence[0].displayName == "encode(_:)")
        #expect(suggestion.evidence[0].signature == "(Int) -> String")
        #expect(suggestion.evidence[1].displayName == "decode(_:)")
        #expect(suggestion.evidence[1].signature == "(String) -> Int")
    }

    // MARK: - Round-trip: missing-callee fallback

    @Test("Round-trip with no FunctionSummary match falls back to (?) -> ? evidence")
    func roundTripMissingCalleeFallback() {
        let detection = DetectedRoundTrip(
            forwardCallee: "encoder",  // not in summaries
            backwardCallee: "decoder",
            inputBindingName: "value",
            recoveredBindingName: nil,
            assertionLocation: SourceLocation(file: "Tests.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.roundTrip(from: detection)
        let summaries: [String: FunctionSummary] = [:]  // empty

        let suggestion = LiftedSuggestionRecovery.recover(lifted, summariesByName: summaries)

        #expect(suggestion.evidence[0].signature == "(?) -> ?")
        #expect(suggestion.evidence[1].signature == "(?) -> ?")
        #expect(suggestion.generator.source == .notYetComputed)
    }

    // MARK: - Idempotence: free-function shape

    @Test("Idempotence recovery of (String) -> String from free-function summary")
    func idempotenceRecoveryFreeFunction() {
        let detection = DetectedIdempotence(
            calleeName: "normalize",
            inputBindingName: "raw",
            assertionLocation: SourceLocation(file: "Tests.swift", line: 5, column: 5)
        )
        let lifted = LiftedSuggestion.idempotence(from: detection)
        let summaries = LiftedSuggestionRecovery.summariesByName([
            makeFreeFunction(name: "normalize", paramType: "String", returnType: "String")
        ])

        let suggestion = LiftedSuggestionRecovery.recover(lifted, summariesByName: summaries)

        #expect(suggestion.evidence[0].signature == "(String) -> String")
    }

    // MARK: - Idempotence: instance-method shape (receiver-type recovery)

    @Test("Idempotence recovery of (Doc) -> Doc from instance-method summary on type Doc")
    func idempotenceRecoveryInstanceMethod() {
        let detection = DetectedIdempotence(
            calleeName: "normalize",
            inputBindingName: "doc",
            assertionLocation: SourceLocation(file: "Tests.swift", line: 5, column: 5)
        )
        let lifted = LiftedSuggestion.idempotence(from: detection)
        let summaries = LiftedSuggestionRecovery.summariesByName([
            // extension Doc { func normalize() -> Doc } — zero params,
            // containing type Doc → receiver type recovered as Doc.
            makeInstanceMethod(name: "normalize", containingType: "Doc", paramTypes: [], returnType: "Doc")
        ])

        let suggestion = LiftedSuggestionRecovery.recover(lifted, summariesByName: summaries)

        #expect(suggestion.evidence[0].signature == "(Doc) -> Doc")
    }

    // MARK: - Commutativity: free-function shape

    @Test("Commutativity recovery of (Int, Int) -> Int from two-arg free-function summary")
    func commutativityRecoveryFreeFunction() {
        let detection = DetectedCommutativity(
            calleeName: "merge",
            leftArgName: "a",
            rightArgName: "b",
            assertionLocation: SourceLocation(file: "Tests.swift", line: 5, column: 5)
        )
        let lifted = LiftedSuggestion.commutativity(from: detection)
        let summaries = LiftedSuggestionRecovery.summariesByName([
            FunctionSummary(
                name: "merge",
                parameters: [
                    .init(label: "_", internalName: "a", typeText: "Int", isInout: false),
                    .init(label: "_", internalName: "b", typeText: "Int", isInout: false)
                ],
                returnTypeText: "Int",
                isThrows: false,
                isAsync: false,
                isMutating: false,
                isStatic: false,
                location: SourceLocation(file: "Merge.swift", line: 1, column: 1),
                containingTypeName: nil,
                bodySignals: .empty
            )
        ])

        let suggestion = LiftedSuggestionRecovery.recover(lifted, summariesByName: summaries)

        #expect(suggestion.evidence[0].signature == "(Int, Int) -> Int")
    }

    // MARK: - Commutativity: instance-method shape

    @Test("Commutativity recovery of (Doc, Doc) -> Doc from one-arg instance-method on type Doc")
    func commutativityRecoveryInstanceMethod() {
        let detection = DetectedCommutativity(
            calleeName: "merge",
            leftArgName: "a",
            rightArgName: "b",
            assertionLocation: SourceLocation(file: "Tests.swift", line: 5, column: 5)
        )
        let lifted = LiftedSuggestion.commutativity(from: detection)
        let summaries = LiftedSuggestionRecovery.summariesByName([
            // extension Doc { func merge(_ other: Doc) -> Doc } — receiver Doc + one Doc param.
            makeInstanceMethod(
                name: "merge",
                containingType: "Doc",
                paramTypes: ["Doc"],
                returnType: "Doc"
            )
        ])

        let suggestion = LiftedSuggestionRecovery.recover(lifted, summariesByName: summaries)

        #expect(suggestion.evidence[0].signature == "(Doc, Doc) -> Doc")
    }

    // MARK: - Idempotence: shape mismatch (e.g. function takes 2 params)

    @Test("Idempotence with non-unary FunctionSummary shape falls back to nil typeName")
    func idempotenceShapeMismatchFallsBack() {
        let detection = DetectedIdempotence(
            calleeName: "normalize",
            inputBindingName: "raw",
            assertionLocation: SourceLocation(file: "Tests.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.idempotence(from: detection)
        let summaries = LiftedSuggestionRecovery.summariesByName([
            // Two-param shape doesn't match idempotence's (T) -> T contract.
            FunctionSummary(
                name: "normalize",
                parameters: [
                    .init(label: "_", internalName: "a", typeText: "Int", isInout: false),
                    .init(label: "_", internalName: "b", typeText: "Int", isInout: false)
                ],
                returnTypeText: "Int",
                isThrows: false,
                isAsync: false,
                isMutating: false,
                isStatic: false,
                location: SourceLocation(file: "X.swift", line: 1, column: 1),
                containingTypeName: nil,
                bodySignals: .empty
            )
        ])

        let suggestion = LiftedSuggestionRecovery.recover(lifted, summariesByName: summaries)

        #expect(suggestion.evidence[0].signature == "(?) -> ?")
    }

    // MARK: - Origin plumbing through recovery

    @Test("Origin parameter threads through recovery to the promoted Suggestion")
    func originPlumbing() {
        let detection = DetectedIdempotence(
            calleeName: "normalize",
            inputBindingName: "raw",
            assertionLocation: SourceLocation(file: "Tests.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.idempotence(from: detection)
        let summaries = LiftedSuggestionRecovery.summariesByName([
            makeFreeFunction(name: "normalize", paramType: "String", returnType: "String")
        ])
        let origin = LiftedOrigin(
            testMethodName: "testNormalizeIsIdempotent",
            sourceLocation: SourceLocation(file: "NormalizerTests.swift", line: 5, column: 5)
        )

        let suggestion = LiftedSuggestionRecovery.recover(
            lifted,
            summariesByName: summaries,
            origin: origin
        )

        #expect(suggestion.liftedOrigin == origin)
    }

    // MARK: - Multiple-overload first-match policy

    @Test("Multiple summaries with the same name resolve to the first occurrence")
    func multipleOverloadsFirstWins() {
        let summaries = LiftedSuggestionRecovery.summariesByName([
            makeFreeFunction(name: "normalize", paramType: "String", returnType: "String"),
            // This second `normalize` (different containing type, different sig)
            // would win if the index policy were "last-wins" — assert it doesn't.
            makeInstanceMethod(name: "normalize", containingType: "Doc", paramTypes: [], returnType: "Doc")
        ])
        // First-match: the free-function String shape wins.
        #expect(summaries["normalize"]?.containingTypeName == nil)
        #expect(summaries["normalize"]?.parameters.first?.typeText == "String")
    }

    // MARK: - Helpers

    private func makeFreeFunction(name: String, paramType: String, returnType: String) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [.init(label: "_", internalName: "x", typeText: paramType, isInout: false)],
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "\(name).swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }

    private func makeInstanceMethod(
        name: String,
        containingType: String,
        paramTypes: [String],
        returnType: String
    ) -> FunctionSummary {
        let params = paramTypes.enumerated().map { idx, type in
            Parameter(
                label: "_",
                internalName: "p\(idx)",
                typeText: type,
                isInout: false
            )
        }
        return FunctionSummary(
            name: name,
            parameters: params,
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "\(containingType).swift", line: 1, column: 1),
            containingTypeName: containingType,
            bodySignals: .empty
        )
    }
}
