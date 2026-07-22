import SwiftInferCore
@testable import SwiftInferCLI
import Testing

/// A seeded *throwing* pure function used to fall through `qualifiesForDeterminism`
/// (its `isThrows == false` guard) and earn no law at all — the confident zero the
/// SwiftLintRuleStudio road-test surfaced on `serialize` (docs/roadtest-…). It now
/// earns the determinism law, mirroring the instance-method relaxation already in
/// that function ("refusing to write a law because it might fail is refusing to
/// test"). The emitted stub compares `try? f(x)` on both sides, so an input in the
/// throwing domain collapses to `nil == nil` and never false-positives.
@Suite
struct ThrowingDeterminismSynthesisTests {

    private struct SilentDiagnostics: DiagnosticOutput {
        func writeDiagnostic(_ text: String) { /* no-op */ }
    }

    private static let loc = SourceLocation(file: "Config.swift", line: 1, column: 1)

    private func throwingSummary() -> FunctionSummary {
        FunctionSummary(
            name: "serialize",
            parameters: [Parameter(label: nil, internalName: "config", typeText: "YAMLConfig", isInout: false)],
            returnTypeText: "String",
            isThrows: true,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: Self.loc,
            containingTypeName: "Engine",
            bodySignals: .empty
        )
    }

    private func manifest() -> SeedManifest {
        SeedManifest(seeds: [
            SeedManifest.Seed(file: "Config.swift", line: 1, symbol: "serialize", kind: .pureFunction)
        ])
    }

    @Test("a seeded throwing pure function earns the determinism law")
    func throwingFunctionQualifies() {
        let result = SwiftInferCommand.Discover.synthesizeGenericLaws(
            for: manifest(),
            summaries: [throwingSummary()],
            covered: [],
            diagnostics: SilentDiagnostics()
        )
        #expect(result.contains { $0.templateName == "determinism" })
    }

    @Test("the throwing determinism suggestion's evidence carries the throws marker")
    func evidenceMarksThrows() throws {
        let result = SwiftInferCommand.Discover.synthesizeGenericLaws(
            for: manifest(),
            summaries: [throwingSummary()],
            covered: [],
            diagnostics: SilentDiagnostics()
        )
        let determinism = try #require(result.first { $0.templateName == "determinism" })
        // The accept path reads this marker to emit a `try?` stub, not a bare call.
        #expect(determinism.evidence.first?.signature.contains("throws") == true)
    }
}
