import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// The text accept writes for each uniquifier witness subject is the text `UniquifierStubCompiledWitness`
/// compiles, and running it holds on the correct subjects and refutes the defective one (#692).
///
/// The subjects are scanned out of the witness file and proposed by the template itself, so neither the
/// subject nor the stub is restated here. The receiver is built as `TrivialConstruction` builds a class
/// with a no-argument initializer.
@Suite("Uniquifier — the stubs accept writes compile, hold, and refute #669's defect")
struct UniquifierStubCompiledWitnessTests {

    static let witnessFile = "UniquifierStubCompiledWitness.swift"

    static func witnessText() throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(witnessFile)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The namespaced stub accept writes for the function `name`, laid out as the written file is.
    static func acceptWrittenStub(_ name: String, in source: String) throws -> String {
        let corpus = FunctionScanner.scanCorpus(source: source, file: witnessFile)
        let suggestions = TemplateRegistry.discover(
            in: corpus.summaries, typeDecls: corpus.typeDecls, templateFilter: [UniquifierTemplate.name]
        )
        let law = try #require(suggestions.first { $0.evidence.first?.displayName.hasPrefix(name + "(") == true })
        let stub = try #require(InteractiveTriage.entailedTemplateStub(for: law, customGenerator: nil) { "\($0)()" })
        let fileName = try #require(InteractiveTriage.stubFileName(for: law))
        let suiteName = InteractiveTriage.suiteName(forStubFileName: fileName)
        return GeneratedFileLayout.laidOut(InteractiveTriage.namespaced(stub, suiteName: suiteName))
    }

    @Test("the witness holds the stub accept writes", arguments: [
        "freshName", "id", "uniquifierWitnessCaseName", "uniqName", "issue",
    ])
    func theWitnessHoldsTheAcceptWrittenStub(name: String) throws {
        let witness = try Self.witnessText()
        let stub = try Self.acceptWrittenStub(name, in: witness)
        let indentedIntoTheRefutedSuite = stub.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "    " + $0 }
            .joined(separator: "\n")
        #expect(
            witness.contains(stub) || witness.contains(indentedIntoTheRefutedSuite),
            "regenerate the witness; accept now writes:\n\(stub)"
        )
    }

    /// The defect's stub, run: it must record an issue, and the issue must name the two calls that
    /// collided. `withKnownIssue` fails this test if the stub passes.
    @Test("the stub refutes #669's defect, naming the colliding calls")
    func theStubRefutesTheDefect() async {
        await withKnownIssue {
            await UniquifierWitnessRefuted.UniquifierWitnessDefectiveNamerUniqNameUniquifierTests()
                .uniqName_issuesDistinctResults()
        } matching: { issue in
            String(describing: issue).contains("uniqName(_:) issued one result twice: calls")
        }
    }
}
