import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// The text accept writes for each witness subject is the text `DeterminismStubCompiledWitness`
/// compiles.
///
/// The subjects are scanned out of the witness file itself and resolved through the accept path's
/// own project-type resolver (`presentedShapes` → `projectTypeGenerator`), so neither the subject,
/// the generator nor the stub is restated here. If the emitter changes, this fails until the
/// witness is regenerated — and the witness only builds if the new text compiles.
@Suite("Determinism — the stubs that used to fail compile, and the witness holds them verbatim")
struct DeterminismStubCompiledWitnessTests {

    private struct SilentDiagnostics: DiagnosticOutput {
        func writeDiagnostic(_: String) { /* no-op */ }
    }

    static let witnessFile = "DeterminismStubCompiledWitness.swift"

    static func witnessText() throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(witnessFile)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The namespaced stub accept writes for `owner.name`, exactly as `wrappedFileContents` places it.
    static func acceptWrittenStub(owner: String, name: String, in source: String) throws -> String {
        let corpus = FunctionScanner.scanCorpus(source: source, file: witnessFile)
        let summary = try #require(corpus.summaries.first { $0.name == name && $0.containingTypeName == owner })
        let manifest = SeedManifest(seeds: [
            SeedManifest.Seed(file: witnessFile, line: summary.location.line, symbol: name, kind: .pureFunction)
        ])
        let laws = SwiftInferCommand.Discover.synthesizeGenericLaws(
            for: manifest, summaries: [summary], covered: [], diagnostics: SilentDiagnostics()
        )
        let law = try #require(laws.first { $0.templateName == "determinism" })
        let folded = TypeShapeBuilder.shapes(from: corpus.typeDecls)
        let shapes = Dictionary(uniqueKeysWithValues: folded.map { ($0.name, $0) })
        let resolver = InteractiveTriage.projectTypeGenerator(
            types: InteractiveTriage.presentedShapes(typeShapesByName: shapes, visible: Set(shapes.keys))
        )
        let stub = try #require(InteractiveTriage.deterministicStub(for: law, customGenerator: resolver))
        let fileName = try #require(InteractiveTriage.stubFileName(for: law))
        return InteractiveTriage.namespaced(stub, suiteName: InteractiveTriage.suiteName(forStubFileName: fileName))
    }

    @Test("the witness holds the stub accept writes", arguments: [
        ("DeterminismWitnessGauge", "scale"),
        ("DeterminismWitnessPoint", "merge")
    ])
    func theWitnessHoldsTheAcceptWrittenStub(owner: String, name: String) throws {
        let witness = try Self.witnessText()
        let stub = try Self.acceptWrittenStub(owner: owner, name: name, in: witness)
        #expect(witness.contains(stub), "regenerate the witness; accept now writes:\n\(stub)")
    }

    /// What the two witnesses changed, read off the accept-written text.
    @Test func theWitnessedShapesAreTheOnesThatUsedToFail() throws {
        let witness = try Self.witnessText()
        let gauge = try Self.acceptWrittenStub(owner: "DeterminismWitnessGauge", name: "scale", in: witness)
        #expect(gauge.contains(
            "approximatelyEqual(DeterminismWitnessGauge.scale(value), DeterminismWitnessGauge.scale(value))"
        ))
        #expect(gauge.contains("private func approximatelyEqual<Value: FloatingPoint>"))
        let point = try Self.acceptWrittenStub(owner: "DeterminismWitnessPoint", name: "merge", in: witness)
        #expect(point.contains("(args: (DeterminismWitnessPoint, DeterminismWitnessPoint))"))
        #expect(point.contains("Self") == false)
        #expect(LiftedTestEmitter.isUnresolvedGenerator(point) == false, "the resolver derives the owner")
    }
}
