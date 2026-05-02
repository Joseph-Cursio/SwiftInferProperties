import Foundation
import SwiftInferCore
@testable import SwiftInferCLI

/// In-memory `DiscoverOutput` for `InteractiveTriageTests`. Distinct
/// name (`Triage`-prefixed) so it doesn't collide with the file-private
/// `RecordingOutput` in `DiscoverPipelineTests`.
final class TriageRecordingOutput: DiscoverOutput, @unchecked Sendable {
    private(set) var lines: [String] = []
    var text: String { lines.joined(separator: "\n") }
    func write(_ text: String) {
        lines.append(text)
    }
}

final class TriageRecordingDiagnosticOutput: DiagnosticOutput, @unchecked Sendable {
    private(set) var lines: [String] = []
    func writeDiagnostic(_ text: String) {
        lines.append(text)
    }
}

/// Plays back a scripted list of input lines. Returns nil after the
/// script is exhausted (simulating EOF on stdin).
final class TriageRecordingPromptInput: PromptInput, @unchecked Sendable {
    private var remaining: [String]
    init(scriptedLines: [String]) {
        self.remaining = scriptedLines
    }
    func readLine() -> String? {
        guard !remaining.isEmpty else { return nil }
        return remaining.removeFirst()
    }
}

// MARK: - Suggestion fixture builders

/// Free functions (not extension methods) so the call-sites in
/// `InteractiveTriageTests` don't need to thread a receiver, and so
/// SwiftLint's `type_body_length` rule on the test struct doesn't
/// re-inflate.
func makeIdempotentSuggestion(
    funcName: String,
    typeName: String,
    file: String = "Test.swift"
) -> Suggestion {
    let evidence = Evidence(
        displayName: "\(funcName)(_:)",
        signature: "(\(typeName)) -> \(typeName)",
        location: SourceLocation(file: file, line: 1, column: 1)
    )
    return Suggestion(
        templateName: "idempotence",
        evidence: [evidence],
        score: Score(signals: [Signal(kind: .typeSymmetrySignature, weight: 90, detail: "")]),
        generator: .m1Placeholder,
        explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
        identity: SuggestionIdentity(canonicalInput: "idempotence|\(funcName)|(\(typeName))->\(typeName)")
    )
}

func makeRoundTripSuggestion(
    forwardName: String,
    inverseName: String
) -> Suggestion {
    let forward = Evidence(
        displayName: "\(forwardName)(_:)",
        signature: "(MyType) -> Data",
        location: SourceLocation(file: "Test.swift", line: 1, column: 1)
    )
    let reverse = Evidence(
        displayName: "\(inverseName)(_:)",
        signature: "(Data) -> MyType",
        location: SourceLocation(file: "Test.swift", line: 5, column: 1)
    )
    return Suggestion(
        templateName: "round-trip",
        evidence: [forward, reverse],
        score: Score(signals: [Signal(kind: .typeSymmetrySignature, weight: 90, detail: "")]),
        generator: .m1Placeholder,
        explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
        identity: SuggestionIdentity(canonicalInput: "round-trip|\(forwardName)|\(inverseName)")
    )
}

func makeBinarySuggestion(template: String, funcName: String) -> Suggestion {
    let evidence = Evidence(
        displayName: "\(funcName)(_:_:)",
        signature: "(IntSet, IntSet) -> IntSet",
        location: SourceLocation(file: "Test.swift", line: 1, column: 1)
    )
    return Suggestion(
        templateName: template,
        evidence: [evidence],
        score: Score(signals: [Signal(kind: .typeSymmetrySignature, weight: 90, detail: "")]),
        generator: .m1Placeholder,
        explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
        identity: SuggestionIdentity(canonicalInput: "\(template)|\(funcName)")
    )
}
