import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferTemplates

// V2.0 M4.A — InteractionTemplateEngine namespace smoke tests.
// The dispatch surface is in place; no per-family analyzer ships
// at M4.A (M4.B's Conservation lands next), so every input
// produces an empty result for now.

@Suite("InteractionTemplateEngine — V2.0 M4.A namespace + dispatch")
struct InteractionTemplateEngineTests {

    private func candidate(
        functionName: String = "reduce",
        signatureShape: ReducerSignatureShape = .stateActionReturnsState
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/T.swift:1",
            enclosingTypeName: nil,
            functionName: functionName,
            signatureShape: signatureShape,
            stateTypeName: "S",
            actionTypeName: "A",
            carrierKind: .elmStyle
        )
    }

    @Test("empty candidate list yields empty suggestions")
    func emptyCandidates() throws {
        let result = try InteractionTemplateEngine.analyze(candidates: [])
        #expect(result.isEmpty)
    }

    @Test("analyze without sourcesDirectory skips Conservation witness detection")
    func analyzeWithoutSourcesDirectory() throws {
        // Conservation is the only M4.B-shipped family and requires
        // sourcesDirectory to walk the State struct. Without it,
        // no suggestions surface even when candidates are present.
        let result = try InteractionTemplateEngine.analyze(candidates: [
            candidate(functionName: "reduceA"),
            candidate(functionName: "reduceB", signatureShape: .inoutStateActionReturnsVoid)
        ])
        #expect(result.isEmpty)
    }

    @Test("analyzeOne returns empty when sourcesDirectory is nil")
    func analyzeOneReturnsEmptyWithoutDirectory() throws {
        let result = try InteractionTemplateEngine.analyzeOne(
            candidate(),
            sourcesDirectory: nil,
            firstSeenAt: ISO8601DateFormatter().date(from: "2026-05-15T10:00:00Z")!
        )
        #expect(result.isEmpty)
    }
}
