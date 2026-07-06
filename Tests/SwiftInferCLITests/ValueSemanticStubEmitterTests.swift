import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Slice 3 fast tests for `ValueSemanticStubEmitter` — the emitted stub shape
/// (retroactive conformance derived from the mutation surface, kit call, marker
/// contract) and the verify-readiness gates.
struct ValueSemanticStubEmitterTests {

    private func candidate(
        typeName: String = "Buffer",
        surface: [MutationMethod],
        equatability: EquatableEvidence = .equatable
    ) -> ValueSemanticCandidate {
        ValueSemanticCandidate(
            typeName: typeName,
            location: SourceLocation(file: "F.swift", line: 1, column: 1),
            referenceBackedMembers: [
                ReferenceBackedMember(name: "storage", typeName: "Store", kind: .corpusReference)
            ],
            mutationSurface: surface,
            equatability: equatability
        )
    }

    @Test func emitsRetroactiveConformanceKitCallAndMarkers() {
        let stub = ValueSemanticStubEmitter.emit(
            .init(typeName: "Buffer", mutationMethods: ["addOne", "reset"], moduleName: "Corpus")
        )
        #expect(stub.contains("import PropertyLawKit"))
        #expect(stub.contains("import Corpus"))
        #expect(stub.contains("extension Buffer: @retroactive ValueSemantic"))
        #expect(stub.contains("public static func makeProbe() -> Self { Buffer() }"))
        #expect(stub.contains("case addOne"))
        #expect(stub.contains("case reset"))
        #expect(stub.contains("case .addOne: target.addOne()"))
        #expect(stub.contains("case .reset: target.reset()"))
        #expect(stub.contains("checkValueSemanticPropertyLaws(for: Buffer.self)"))
        #expect(stub.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(stub.contains("VERIFY_EDGE_RESULT: PASS"))
        #expect(stub.contains("VERIFY_DEFAULT_RESULT: FAIL"))
        // Surfaces the kit's minimal counterexample, not the law-summary text.
        #expect(stub.contains("catch let violation as PropertyLawViolation"))
        #expect(stub.contains("compactMap(\\.counterexample)"))
    }

    @Test func buildsInputsFromPayloadFreeSurfaceOnly() throws {
        let inputs = try #require(
            ValueSemanticStubEmitter.inputs(
                for: candidate(surface: [
                    MutationMethod(name: "addOne", isMutating: true, parameterCount: 0),
                    MutationMethod(name: "set", isMutating: true, parameterCount: 2)      // payload → skipped
                ]),
                moduleName: "Corpus"
            )
        )
        #expect(inputs.mutationMethods == ["addOne"])
        #expect(inputs.typeName == "Buffer")
        #expect(inputs.moduleName == "Corpus")
    }

    @Test func gatesNonEquatableCandidate() {
        let gated = ValueSemanticStubEmitter.inputs(
            for: candidate(
                surface: [MutationMethod(name: "go", isMutating: true, parameterCount: 0)],
                equatability: .notEquatable
            ),
            moduleName: "M"
        )
        #expect(gated == nil)
    }

    @Test func gatesCandidateWithNoPayloadFreeMutation() {
        let gated = ValueSemanticStubEmitter.inputs(
            for: candidate(surface: [MutationMethod(name: "set", isMutating: true, parameterCount: 1)]),
            moduleName: "M"
        )
        #expect(gated == nil)
    }
}
