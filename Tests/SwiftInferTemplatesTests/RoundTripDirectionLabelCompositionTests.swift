import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// V1.12.1 — companion suites to RoundTripDirectionLabelCounterTests.
// Split out per the V1.10.1 / V1.11.1 file-length precedent (the parent
// file ran past swiftlint's 400-line `file_length` and 250-line
// `type_body_length` budgets when these suites were inlined).
//
// This file covers two cases that exercise the direction counter's
// interaction with other RoundTripTemplate signals (cross-type counter,
// discoverable annotation) plus the end-to-end discover() integration.

@Suite("RoundTripTemplate — V1.12.1 direction counter signal composition")
struct RoundTripDirectionLabelCompositionTests {

    @Test("V1.12.1 — cross-type counter + direction counter compose correctly")
    func crossTypeAndDirectionCounterCompose() {
        // Cross-type counter (-25) + direction counter (-15) compose
        // additively: +30 - 25 - 15 = -10 → Suppressed (deeper margin
        // than either alone). Both counters firing is the expected
        // behavior when a cross-type pair also happens to use direction
        // labels (e.g., distinct conforming types each declaring
        // `index(after:)`).
        let forward = makeSummary(
            name: "index",
            label: "after",
            paramType: "Index",
            returnType: "Index",
            line: 10,
            containingTypeName: "FooCollection"
        )
        let reverse = makeSummary(
            name: "index",
            label: "before",
            paramType: "Index",
            returnType: "Index",
            line: 20,
            containingTypeName: "BarCollection"
        )
        let suggestion = RoundTripTemplate.suggest(for: FunctionPair(forward: forward, reverse: reverse))
        #expect(suggestion == nil, "Cross-type + direction pair should be doubly suppressed")
    }

    @Test("V1.12.1 — discoverable group + direction counter still preserves Likely (+30 + 35 - 15 = +50)")
    func discoverableGroupOverridesDirectionCounter() {
        // A user who tagged both halves with `@Discoverable(group: …)`
        // has explicitly opted in. The +35 discoverable signal preserves
        // the suggestion at Likely (+50) even with the -15 direction
        // counter — the user's explicit signal beats the structural
        // counter, mirroring the v1.4.3b cross-type rule's exemption-3
        // posture.
        let forward = makeSummary(
            name: "step",
            label: "after",
            paramType: "Token",
            returnType: "Token",
            line: 10,
            discoverableGroup: "stepper"
        )
        let reverse = makeSummary(
            name: "unstep",
            label: nil,
            paramType: "Token",
            returnType: "Token",
            line: 20,
            discoverableGroup: "stepper"
        )
        let suggestion = RoundTripTemplate.suggest(for: FunctionPair(forward: forward, reverse: reverse))
        #expect(suggestion?.score.total == 50)
        #expect(suggestion?.score.tier == .likely)
        #expect(suggestion?.score.signals.contains { $0.kind == .discoverableAnnotation } ?? false)
        #expect(suggestion?.score.signals.contains { $0.kind == .directionLabel } ?? false)
    }

    private func makeSummary(
        name: String,
        label: String?,
        paramType: String,
        returnType: String,
        line: Int,
        containingTypeName: String? = nil,
        discoverableGroup: String? = nil
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: label, internalName: "x", typeText: paramType, isInout: false)],
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: line, column: 1),
            containingTypeName: containingTypeName,
            bodySignals: .empty,
            discoverableGroup: discoverableGroup
        )
    }
}

@Suite("RoundTripTemplate — V1.12.1 end-to-end discover() integration")
struct RoundTripDirectionLabelDiscoverTests {

    @Test("V1.12.1 — `index(after:) ↔ index(before:)` no longer surfaces in discover() round-trip output")
    func indexAfterIndexBeforeSuppressedEndToEnd() {
        let indexAfter = makeSummary(
            name: "index",
            label: "after",
            paramType: "Index",
            returnType: "Index",
            line: 10
        )
        let indexBefore = makeSummary(
            name: "index",
            label: "before",
            paramType: "Index",
            returnType: "Index",
            line: 20
        )
        let suggestions = TemplateRegistry.discover(
            in: [indexAfter, indexBefore],
            typeDecls: []
        )
        let roundTripCount = suggestions.filter { $0.templateName == "round-trip" }.count
        #expect(roundTripCount == 0, "Direction-labeled round-trip should not surface")
    }

    @Test("V1.12.1 — `encode/decode` pair still surfaces Likely")
    func encodeDecodeStillSurfacesEndToEnd() {
        let encode = makeSummary(
            name: "encode",
            label: nil,
            paramType: "Document",
            returnType: "Data",
            line: 30
        )
        let decode = makeSummary(
            name: "decode",
            label: nil,
            paramType: "Data",
            returnType: "Document",
            line: 40
        )
        let suggestions = TemplateRegistry.discover(
            in: [encode, decode],
            typeDecls: []
        )
        let roundTrip = suggestions.first { $0.templateName == "round-trip" }
        #expect(roundTrip != nil, "Curated round-trip pair should still surface")
        #expect(roundTrip?.score.tier == .likely)
    }

    private func makeSummary(
        name: String,
        label: String?,
        paramType: String,
        returnType: String,
        line: Int
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: label, internalName: "x", typeText: paramType, isInout: false)],
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: line, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }
}
