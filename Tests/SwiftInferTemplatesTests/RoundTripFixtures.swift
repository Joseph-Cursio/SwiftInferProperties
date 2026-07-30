import SwiftInferCore
@testable import SwiftInferTemplates

// Shared round-trip fixture builders, used across every `RoundTrip*Tests` suite.
// Extracted from `RoundTripTemplateTests.swift` when adding the label parameters pushed
// that file past the 400-line cap.

func makeRoundTripPair(
    forwardName: String,
    reverseName: String,
    forwardParam: String,
    forwardReturn: String,
    forwardBodySignals: BodySignals = .empty,
    reverseBodySignals: BodySignals = .empty,
    forwardGroup: String? = nil,
    reverseGroup: String? = nil,
    // Argument labels, defaulting to unlabelled as before. Added so a fixture can carry the
    // RECIPROCAL labels that make a same-type pair read as an inverse
    // (`minimumCapacity(forScale:)` ↔ `scale(forCapacity:)`) — see
    // `RoundTripTemplate.hasReciprocalLabels`. Every existing call site is unaffected.
    forwardLabel: String? = nil,
    reverseLabel: String? = nil
) -> FunctionPair {
    let forward = FunctionSummary(
        name: forwardName,
        parameters: [
            Parameter(label: forwardLabel, internalName: "x", typeText: forwardParam, isInout: false)
        ],
        returnTypeText: forwardReturn,
        isThrows: false,
        isAsync: false,
        isMutating: false,
        isStatic: false,
        location: SourceLocation(file: "Test.swift", line: 1, column: 1),
        containingTypeName: nil,
        bodySignals: forwardBodySignals,
        discoverableGroup: forwardGroup
    )
    let reverse = FunctionSummary(
        name: reverseName,
        parameters: [
            Parameter(label: reverseLabel, internalName: "x", typeText: forwardReturn, isInout: false)
        ],
        returnTypeText: forwardParam,
        isThrows: false,
        isAsync: false,
        isMutating: false,
        isStatic: false,
        location: SourceLocation(file: "Test.swift", line: 5, column: 1),
        containingTypeName: nil,
        bodySignals: reverseBodySignals,
        discoverableGroup: reverseGroup
    )
    return FunctionPair(forward: forward, reverse: reverse)
}
