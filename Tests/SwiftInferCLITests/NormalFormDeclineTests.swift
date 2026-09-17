import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `normal-form` on the accept path: declined by design, and the note says so (#478).
@Suite("Accept path — normal-form declines by design")
struct NormalFormDeclineTests {

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

    @Test("normal-form's note says the decline is a decision, and why")
    func normalFormSaysWhy() {
        let note = InteractiveTriage.noStubNote(
            for: Self.suggestion(template: "normal-form", evidence: Self.pair)
        )
        #expect(note.contains("by design"))
        #expect(note.contains("0 times in 10,000"))
        #expect(!note.contains("no stub writeout available"))
    }

    /// **The control.** A template with no writer and no recorded decision still gets the generic
    /// sentence — the named decline must not become the default.
    @Test("an undecided template keeps the generic sentence")
    func undecidedTemplateIsGeneric() {
        let note = InteractiveTriage.noStubNote(
            for: Self.suggestion(template: "value-round-trip", evidence: Self.pair)
        )
        #expect(note.contains("no stub writeout available for template 'value-round-trip'"))
    }

    /// A deliberate decline on a template that HAS a writer would tell a reader to stop waiting for
    /// something that exists. Checked against the same source scan `StubWriterCoverageTests` uses,
    /// so the two cannot drift, and every declined template must still be on its `noWriterYet`.
    @Test("no deliberate decline names a template that has a writer")
    func declinesAreForWriterlessTemplates() throws {
        let declined = try StubWriterCoverageTests.emittedTemplates()
            .filter { DeliberateStubDecline.reason(forTemplate: $0) != nil }
        #expect(declined.contains("normal-form"), "the scan found no declined template — is it blind?")
        #expect(declined.isDisjoint(with: try StubWriterCoverageTests.templatesWithArms()))
        #expect(declined.isSubset(of: StubWriterCoverageTests.noWriterYet.keys))
    }
}
