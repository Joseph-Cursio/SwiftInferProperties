import Foundation
import PropertyLawCore
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

    /// The witness file scanned the way discover scans a target.
    struct Scanned {
        let corpus: ScannedCorpus
        let shapes: [String: TypeShape]
    }

    static func scanned(_ source: String) -> Scanned {
        let corpus = FunctionScanner.scanCorpus(source: source, file: witnessFile)
        let folded = TypeShapeBuilder.shapes(from: corpus.typeDecls)
        return Scanned(corpus: corpus, shapes: Dictionary(uniqueKeysWithValues: folded.map { ($0.name, $0) }))
    }

    /// The determinism law a seed on `owner.name` synthesizes.
    static func law(owner: String, name: String, in scanned: Scanned) throws -> Suggestion {
        let summary = try #require(scanned.corpus.summaries.first { $0.name == name && $0.containingTypeName == owner })
        let manifest = SeedManifest(seeds: [
            SeedManifest.Seed(file: witnessFile, line: summary.location.line, symbol: name, kind: .pureFunction)
        ])
        let laws = SwiftInferCommand.Discover.synthesizeGenericLaws(
            for: manifest, summaries: [summary], covered: [], diagnostics: SilentDiagnostics()
        )
        return try #require(laws.first { $0.templateName == "determinism" })
    }

    /// The namespaced stub accept writes for `owner.name`, exactly as `wrappedFileContents` places it
    /// — laid out by `GeneratedFileLayout` as the written file is, so the witness compiles the
    /// layout's output and not only the emitter's.
    static func acceptWrittenStub(owner: String, name: String, in source: String) throws -> String {
        let scanned = Self.scanned(source)
        let law = try Self.law(owner: owner, name: name, in: scanned)
        let presented = InteractiveTriage.presentedShapes(
            typeShapesByName: scanned.shapes, visible: Set(scanned.shapes.keys)
        )
        let resolver = InteractiveTriage.projectTypeGenerator(types: presented)
        let stub = try #require(InteractiveTriage.deterministicStub(for: law, customGenerator: resolver))
        let fileName = try #require(InteractiveTriage.stubFileName(for: law))
        let suiteName = InteractiveTriage.suiteName(forStubFileName: fileName)
        return GeneratedFileLayout.laidOut(InteractiveTriage.namespaced(stub, suiteName: suiteName))
    }

    /// The subjects whose stubs `UnequatableResultGate` used to withdraw although they compile.
    static let misreadResults: [(String, String)] = [
        ("DeterminismWitnessColumns", "sortKey"),
        ("DeterminismWitnessColumns", "rowID"),
        ("DeterminismWitnessBank", "credit"),
        ("DeterminismWitnessBank", "read")
    ]

    @Test("the witness holds the stub accept writes", arguments: [
        ("DeterminismWitnessGauge", "scale"),
        ("DeterminismWitnessPoint", "merge")
    ] + misreadResults)
    func theWitnessHoldsTheAcceptWrittenStub(owner: String, name: String) throws {
        let witness = try Self.witnessText()
        let stub = try Self.acceptWrittenStub(owner: owner, name: name, in: witness)
        #expect(witness.contains(stub), "regenerate the witness; accept now writes:\n\(stub)")
    }

    /// The gate, fed this file the way discover feeds it a target, lets each of these through —
    /// and the witness holding their stubs, which builds, is the proof that was right.
    @Test("the result gate lets the misread results through", arguments: misreadResults)
    func theResultGateLetsTheMisreadResultsThrough(owner: String, name: String) throws {
        let scanned = Self.scanned(try Self.witnessText())
        let law = try Self.law(owner: owner, name: name, in: scanned)
        let reason = UnequatableResultGate.declineReason(
            for: law,
            typeShapesByName: scanned.shapes,
            inheritedTypesByName: ProtocolCoverageMap.inheritedTypesIndex(from: scanned.corpus.typeDecls),
            equalityOutsideInheritance: UnequatableResultGate.equalityOutsideInheritance(
                typeDecls: scanned.corpus.typeDecls, summaries: scanned.corpus.summaries
            )
        )
        #expect(reason == nil)
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
