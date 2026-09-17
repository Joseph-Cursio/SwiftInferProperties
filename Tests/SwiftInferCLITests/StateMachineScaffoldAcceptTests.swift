import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `state-machine` on the accept path: a SCAFFOLD naming the two moves (#478).
@Suite("Accept path — state-machine writes a scaffold")
struct StateMachineScaffoldAcceptTests {

    private static func row(_ displayName: String, _ signature: String) -> Evidence {
        Evidence(
            displayName: displayName,
            signature: signature,
            location: SourceLocation(file: "InboxViewModel.swift", line: 39, column: 5),
            isInstanceMethod: true,
            qualifiedTypeName: "InboxViewModel"
        )
    }

    private static func suggestion(template: String, evidence: [Evidence]) -> Suggestion {
        Suggestion(
            templateName: template,
            evidence: evidence,
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 35, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "\(template)|InboxViewModel"),
            carrier: "InboxViewModel",
            carrierTypeName: "InboxViewModel"
        )
    }

    private static let pair = [row("select(_:)", "(Int) -> Void"), row("deselect()", "() -> Void")]

    @Test("a state-machine pair writes a scaffold, labelled SCAFFOLD")
    func stateMachineWritesAScaffold() throws {
        let stub = try #require(InteractiveTriage.entailedTemplateStub(
            for: Self.suggestion(template: "state-machine", evidence: Self.pair)
        ))
        #expect(InteractiveTriage.isScaffold(stub))
        #expect(stub.contains("subject.select(<#Int#>)"))
        #expect(stub.contains("subject.deselect()"))
    }

    @Test("a row naming one move is not a pair and writes nothing")
    func oneMoveIsNotAPair() {
        #expect(InteractiveTriage.entailedTemplateStub(
            for: Self.suggestion(template: "state-machine", evidence: [Self.pair[0]])
        ) == nil)
    }

    /// A display name and signature that disagree on arity would spell a call with the wrong
    /// arguments; a malformed row writes nothing instead.
    @Test("a move whose name and signature disagree writes nothing")
    func malformedMoveWritesNothing() {
        let malformed = [Self.row("select(_:_:)", "(Int) -> Void"), Self.pair[1]]
        #expect(InteractiveTriage.entailedTemplateStub(
            for: Self.suggestion(template: "state-machine", evidence: malformed)
        ) == nil)
    }
}
