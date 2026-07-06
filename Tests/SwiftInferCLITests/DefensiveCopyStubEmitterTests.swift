import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Slice 6c fast tests for `DefensiveCopyStubEmitter` — the emitted stub shape
/// (retroactive `DefensiveCopy` conformance, `copyUnderTest()` wiring, markers)
/// and the verify-readiness gates.
struct DefensiveCopyStubEmitterTests {

    private func candidate(
        surface: [MutationMethod],
        equatability: EquatableEvidence = .equatable,
        copyMethod: String = "copy"
    ) -> DefensiveCopyCandidate {
        DefensiveCopyCandidate(
            typeName: "Buffer",
            location: SourceLocation(file: "F.swift", line: 1, column: 1),
            copyMethodName: copyMethod,
            mutationSurface: surface,
            equatability: equatability
        )
    }

    @Test func emitsConformanceCopyUnderTestKitCallAndMarkers() {
        let stub = DefensiveCopyStubEmitter.emit(
            .init(typeName: "Buffer", copyMethodName: "clone", mutationMethods: ["appendOne"], moduleName: "Corpus")
        )
        #expect(stub.contains("import PropertyLawKit"))
        #expect(stub.contains("import Corpus"))
        #expect(stub.contains("extension Buffer: @retroactive DefensiveCopy"))
        #expect(stub.contains("public func copyUnderTest() -> Buffer { clone() }"))
        #expect(stub.contains("case appendOne"))
        #expect(stub.contains("case .appendOne: target.appendOne()"))
        #expect(stub.contains("checkDefensiveCopyPropertyLaws(for: Buffer.self)"))
        #expect(stub.contains("VERIFY_DEFAULT_RESULT: FAIL"))
        #expect(stub.contains("compactMap(\\.counterexample)"))
    }

    @Test func testableFlagControlsImport() {
        let plain = DefensiveCopyStubEmitter.emit(
            .init(typeName: "T", copyMethodName: "copy", mutationMethods: ["go"], moduleName: "M")
        )
        #expect(!plain.contains("@testable"))
        let testable = DefensiveCopyStubEmitter.emit(
            .init(typeName: "T", copyMethodName: "copy", mutationMethods: ["go"], moduleName: "M", testable: true)
        )
        #expect(testable.contains("@testable import M"))
    }

    @Test func gatesNonEquatable() {
        let gated = DefensiveCopyStubEmitter.inputs(
            for: candidate(
                surface: [MutationMethod(name: "go", isMutating: false, parameterCount: 0)],
                equatability: .notEquatable
            ),
            moduleName: "M"
        )
        #expect(gated == nil)
    }

    @Test func gatesNoPayloadFreeMutation() {
        let gated = DefensiveCopyStubEmitter.inputs(
            for: candidate(surface: [MutationMethod(name: "set", isMutating: false, parameterCount: 1)]),
            moduleName: "M"
        )
        #expect(gated == nil)
    }

    @Test func buildsInputsFromPayloadFreeSurface() throws {
        let inputs = try #require(
            DefensiveCopyStubEmitter.inputs(
                for: candidate(
                    surface: [
                        MutationMethod(name: "appendOne", isMutating: false, parameterCount: 0),
                        MutationMethod(name: "set", isMutating: false, parameterCount: 2)
                    ],
                    copyMethod: "clone"
                ),
                moduleName: "Corpus"
            )
        )
        #expect(inputs.mutationMethods == ["appendOne"])
        #expect(inputs.copyMethodName == "clone")
    }
}
