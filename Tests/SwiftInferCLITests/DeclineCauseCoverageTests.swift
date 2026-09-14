import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Every decline names its own cause, or says the template has no arm — and means it.
///
/// The generic sentence *"no stub writeout available for template 'X' in v1"* was the only thing
/// a reader saw for every un-emitted suggestion. It fired for at least four distinct causes, and
/// named the template for all of them — sending the reader to look for a missing arm when the
/// arm exists. #445 split out arity and mutating; #456 found it still firing for a missing
/// carrier and for an unresolved pair.
///
/// **Measured on SwiftMarkdownWiki after this: 18 declines name their cause, and the 8 that
/// still take the generic sentence are templates that genuinely have no emitter arm.**
@Suite("Declines name their cause")
struct DeclineCauseCoverageTests {

    private static func suggestion(
        template: String,
        displayName: String,
        signature: String = "(String) -> String",
        carrier: String? = nil,
        isInstanceMethod: Bool = false,
        evidenceCount: Int = 1
    ) -> Suggestion {
        let row = Evidence(
            displayName: displayName,
            signature: signature,
            location: SourceLocation(file: "F.swift", line: 1, column: 1),
            isInstanceMethod: isInstanceMethod,
            qualifiedTypeName: carrier
        )
        return Suggestion(
            templateName: template,
            evidence: Array(repeating: row, count: evidenceCount),
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "F.swift::\(displayName)")
        )
    }

    /// A free nullary function has no parameter and no receiver.
    @Test func aSubjectWithNoCarrierSaysSo() throws {
        let reason = try #require(StubApplicationArity.declineReason(
            for: Self.suggestion(template: "idempotence", displayName: "now()", signature: "() -> Date")
        ))
        #expect(reason.contains("no parameter and no enclosing type"))
    }

    /// A paired template with one evidence row: the pair was never resolved, which is a fact
    /// about the subject rather than about the emitter.
    @Test func anUnresolvedPairSaysSo() throws {
        let reason = try #require(StubApplicationArity.declineReason(
            for: Self.suggestion(template: "round-trip", displayName: "encode(_:)", carrier: "Codec")
        ))
        #expect(reason.contains("needs two subjects"))
    }

    /// **The control that keeps this honest.** A subject the emitter can write must produce no
    /// reason at all — a decline message on a suggestion that emits would be worse than the
    /// generic sentence it replaces.
    @Test func anEmittableSubjectHasNoDeclineReason() {
        #expect(StubApplicationArity.declineReason(
            for: Self.suggestion(
                template: "idempotence",
                displayName: "trimmed()",
                signature: "() -> Self",
                carrier: "String",
                isInstanceMethod: true
            )
        ) == nil)
    }

    /// A resolved pair is not an unresolved one.
    @Test func aResolvedPairHasNoReason() {
        #expect(StubApplicationArity.declineReason(
            for: Self.suggestion(template: "round-trip", displayName: "encode(_:)", carrier: "Codec", evidenceCount: 2)
        ) == nil)
    }
}
