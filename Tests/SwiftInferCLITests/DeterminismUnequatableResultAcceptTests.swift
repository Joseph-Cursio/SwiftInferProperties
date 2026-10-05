import Foundation
import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `accept` on a determinism law whose result is a scanned type nothing makes `Equatable` names
/// that cause instead of writing `f(x) == f(x)`, which fails with *referencing operator function
/// '==' on 'Equatable' requires that 'FixResult' conform to 'Equatable'* — end to end, through
/// `handleAccept` in a dry run, with the types scanned the way discover scans them.
@Suite("Determinism — accept declines a result type with no ==")
struct DeterminismUnequatableResultAcceptTests {

    private static let subject = """
        struct FixResult {
            let text: String
        }

        enum Fixer {
            static func fix(_ source: String) -> FixResult { FixResult(text: source) }
        }
        """

    private static func accept(extraSource: String) throws -> (output: String, diagnostics: [String]) {
        let source = subject + "\n" + extraSource
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Fixer.swift")
        let law = try DeterminismAcceptPathPlanTests.law(source, named: "fix")
        let shapes = TypeShapeBuilder.shapes(from: corpus.typeDecls)
        let output = TriageRecordingOutput()
        let diagnostics = TriageRecordingDiagnosticOutput()
        let context = InteractiveTriage.Context(
            prompt: TriageRecordingPromptInput(scriptedLines: []),
            output: output,
            diagnostics: diagnostics,
            outputDirectory: FileManager.default.temporaryDirectory,
            dryRun: true,
            typeShapesByName: Dictionary(uniqueKeysWithValues: shapes.map { ($0.name, $0) }),
            inheritedTypesByName: ProtocolCoverageMap.inheritedTypesIndex(from: corpus.typeDecls)
        )
        #expect(try InteractiveTriage.handleAccept(suggestion: law, context: context) == nil)
        return (output.text, diagnostics.lines)
    }

    @Test func aResultNothingMakesEquatableIsNotWritten() throws {
        let (output, diagnostics) = try Self.accept(extraSource: "")
        #expect(output.contains("would write") == false)
        #expect(diagnostics.contains(
            "note: no stub written — fix(_:) returns FixResult, and no scanned declaration makes FixResult "
                + "Equatable, so `==` cannot compare two results; decision recorded without writing a file"
        ))
    }

    /// The control: one conformance, declared anywhere the scan sees, and the stub is written.
    @Test func aConformanceDeclaredInAnExtensionIsEnough() throws {
        let (output, diagnostics) = try Self.accept(extraSource: "extension FixResult: Equatable {}")
        #expect(output.contains("would write"))
        #expect(diagnostics.contains { $0.contains("no stub written") } == false)
    }
}
