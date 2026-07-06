import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Slice 6e-c fast tests for `StableIdentityStubEmitter` — the emitted stub
/// shape (retroactive `StableIdentity` conformance, kit call, markers) and the
/// no-payload-free-mutation gate.
struct StableIdentityStubEmitterTests {

    private func candidate(surface: [MutationMethod]) -> StableIdentityCandidate {
        StableIdentityCandidate(
            typeName: "Node",
            location: SourceLocation(file: "F.swift", line: 1, column: 1),
            mutationSurface: surface
        )
    }

    @Test func emitsConformanceKitCallAndMarkers() {
        let stub = StableIdentityStubEmitter.emit(
            .init(typeName: "Node", mutationMethods: ["rename"], moduleName: "Corpus")
        )
        #expect(stub.contains("import PropertyLawKit"))
        #expect(stub.contains("import Corpus"))
        #expect(stub.contains("extension Node: @retroactive StableIdentity"))
        #expect(stub.contains("public static func makeProbe() -> Node { Node() }"))
        #expect(stub.contains("case rename"))
        #expect(stub.contains("case .rename: target.rename()"))
        #expect(stub.contains("checkStableIdentityPropertyLaws(for: Node.self)"))
        #expect(stub.contains("VERIFY_DEFAULT_RESULT: FAIL"))
        #expect(stub.contains("compactMap(\\.counterexample)"))
    }

    @Test func testableFlagControlsImport() {
        let plain = StableIdentityStubEmitter.emit(
            .init(typeName: "T", mutationMethods: ["go"], moduleName: "M")
        )
        #expect(!plain.contains("@testable"))
        let testable = StableIdentityStubEmitter.emit(
            .init(typeName: "T", mutationMethods: ["go"], moduleName: "M", testable: true)
        )
        #expect(testable.contains("@testable import M"))
    }

    @Test func gatesNoPayloadFreeMutation() {
        let gated = StableIdentityStubEmitter.inputs(
            for: candidate(surface: [MutationMethod(name: "set", isMutating: false, parameterCount: 1)]),
            moduleName: "M"
        )
        #expect(gated == nil)
    }

    @Test func buildsInputsFromPayloadFreeSurface() throws {
        let inputs = try #require(
            StableIdentityStubEmitter.inputs(
                for: candidate(surface: [
                    MutationMethod(name: "rename", isMutating: false, parameterCount: 0),
                    MutationMethod(name: "set", isMutating: false, parameterCount: 2)
                ]),
                moduleName: "Corpus"
            )
        )
        #expect(inputs.mutationMethods == ["rename"])
        #expect(inputs.typeName == "Node")
    }
}
