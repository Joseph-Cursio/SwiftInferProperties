@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Why a suggestion the user accepted produced no file.
///
/// Before this, every un-emitted suggestion got one sentence — *"no stub writeout available for
/// template 'idempotence' in v1"* — and for a subject that simply cannot be called it is false:
/// the template has a writeout, and the subject is what cannot be spelled. Measured on
/// SwiftMarkdownWiki after the call-shape fix, **7 of 7 declines were subjects rather than
/// templates**, so the one message was wrong every time it fired.
@Suite("Why no stub was written")
struct StubApplicationArityTests {

    private static func suggestion(
        template: String,
        displayName: String,
        carrier: String? = nil,
        isInstanceMethod: Bool = false,
        isMutatingMethod: Bool = false,
        signature: String = "(String) -> String"
    ) -> Suggestion {
        Suggestion(
            templateName: template,
            evidence: [
                Evidence(
                    displayName: displayName,
                    signature: signature,
                    location: SourceLocation(file: "F.swift", line: 1, column: 1),
                    isInstanceMethod: isInstanceMethod,
                    isMutatingMethod: isMutatingMethod,
                    qualifiedTypeName: carrier
                )
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "F.swift::\(displayName)")
        )
    }

    /// The measured case, reduced: `private func filtered(_:)` on a `View`, accepted under
    /// `idempotence`, which applies one argument to a subject that needs two.
    @Test func anInstanceMethodTooWideForItsTemplateSaysSo() throws {
        let reason = try #require(StubApplicationArity.declineReason(
            for: Self.suggestion(
                template: "idempotence",
                displayName: "filtered(_:)",
                carrier: "PluginLogPanelView",
                isInstanceMethod: true
            )
        ))
        #expect(reason.contains("needs 2 arguments"))
        #expect(reason.contains("a receiver plus 1"))
        #expect(reason.contains("'idempotence' applies 1"))
    }

    /// A two-parameter instance method does not fit the two-argument templates either, and the
    /// count in the message has to say 3 rather than repeat the parameter count.
    @Test func theReceiverIsCountedInTheNumberReported() throws {
        let reason = try #require(StubApplicationArity.declineReason(
            for: Self.suggestion(
                template: "commutativity",
                displayName: "union(_:_:)",
                carrier: "LiveMarkdownHiding",
                isInstanceMethod: true
            )
        ))
        #expect(reason.contains("needs 3 arguments"))
    }

    /// **The load-bearing negative.** A reason returned for a subject that emits fine would
    /// replace a correct message with a false one on every successful stub — the same defect in
    /// the other direction.
    @Test func aSubjectThatFitsHasNoReason() {
        #expect(StubApplicationArity.declineReason(
            for: Self.suggestion(
                template: "idempotence",
                displayName: "strippingHeadingMarkers(from:)",
                carrier: "EditorFormatter"
            )
        ) == nil)
    }

    /// `monotonicity` over an `Optional` carrier declines, and the reader is told why.
    ///
    /// **Without this the message would blame the template**, which is the misattribution #445
    /// split for arity and #456 records in a third place. The compiler's own error names the
    /// closure parameter rather than the comparison, so the emitted note is the only place
    /// optionality gets mentioned at all.
    @Test func anOptionalMonotonicityCarrierSaysWhy() throws {
        let reason = try #require(StubApplicationArity.declineReason(
            for: Self.suggestion(
                template: "monotonicity",
                displayName: "modificationDate(reported:)",
                carrier: "NoteFile",
                signature: "(Date?) -> Date"
            )
        ))
        #expect(reason.contains("Date?"))
        #expect(reason.contains("an Optional, collection or tuple is not Comparable"))
    }

    /// A collection carrier declines the same way — `[Int]` is never `Comparable`.
    @Test func aCollectionMonotonicityCarrierSaysWhy() throws {
        let reason = try #require(StubApplicationArity.declineReason(
            for: Self.suggestion(
                template: "monotonicity",
                displayName: "total(_:)",
                carrier: "Stats",
                signature: "([Int]) -> Int"
            )
        ))
        #expect(reason.contains("[Int]"))
        #expect(reason.contains("not Comparable"))
    }

    /// The control: an ordinary carrier still emits, so the template is narrowed, not disabled.
    @Test func anOrderableMonotonicityCarrierHasNoReason() {
        #expect(StubApplicationArity.declineReason(
            for: Self.suggestion(
                template: "monotonicity",
                displayName: "retention(in:)",
                carrier: "Vault",
                signature: "(Int) -> Int"
            )
        ) == nil)
    }

    /// A template with no emitter arm must keep the old sentence, which names the template
    /// because the template really is what is missing.
    @Test func aTemplateWithNoArmYieldsNoSubjectReason() {
        #expect(StubApplicationArity.declineReason(
            for: Self.suggestion(template: "guard-domain", displayName: "isValid(_:)")
        ) == nil)
    }

    @Test func aMutatingMethodSaysWhyItHasNoValueToCompare() throws {
        let reason = try #require(StubApplicationArity.declineReason(
            for: Self.suggestion(
                template: "idempotence",
                displayName: "normalize()",
                carrier: "Doc",
                isInstanceMethod: true,
                isMutatingMethod: true
            )
        ))
        #expect(reason.contains("mutating"))
    }

    /// The table is the single source the builders read, so a template listed here that the
    /// accept path does not dispatch — or vice versa — is drift. Pinned in both directions.
    @Test("every template with an arity has a stub arm, and the two-argument ones are the algebraic ones")
    func theArityTableMatchesTheDispatch() {
        #expect(StubApplicationArity.forTemplate("idempotence") == 1)
        #expect(StubApplicationArity.forTemplate("commutativity") == 2)
        #expect(StubApplicationArity.forTemplate("associativity") == 2)
        #expect(StubApplicationArity.forTemplate("identity-element") == 2)
        #expect(StubApplicationArity.forTemplate("replay-idempotence") == nil)
        #expect(StubApplicationArity.forTemplate("guard-domain") == nil)
        // Totality has no number (#464): it calls once and discards the result.
        #expect(StubApplicationArity.forTemplate("predicate") == nil)
        #expect(StubApplicationArity.forTemplate("input-totality") == nil)
        #expect(StubApplicationArity.arityFreeTemplates == ["predicate", "input-totality", "determinism"])
    }
}
