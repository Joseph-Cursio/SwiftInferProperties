import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// **A law that splices a bare call to a `throws` subject cannot be spelled**, so it is not written.
///
/// The exhibit is real: `CoreDataModelExtractor.contentsURL(in:) throws` on `SwiftUMLStudio`, whose
/// `idempotence` stub emitted `contentsURL(in: contentsURL(in: value)) == contentsURL(in: value)`
/// and failed with `call can throw, but it is not marked with 'try'`. It was invisible until the
/// subject was widened out of an access error.
@Suite("Throwing subjects — withdrawn, not emitted")
struct ThrowingSubjectGateTests {

    private func suggestion(template: String, display: String, signature: String) -> Suggestion {
        Suggestion(
            templateName: template,
            evidence: [
                Evidence(
                    displayName: display,
                    signature: signature,
                    location: SourceLocation(file: "CoreDataModelExtractor.swift", line: 50, column: 5),
                    parameterTypeNames: ["URL"],
                    qualifiedTypeName: "CoreDataModelExtractor"
                )
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "\(template)|\(display)"),
            carrier: "CoreDataModelExtractor"
        )
    }

    @Test("a throwing subject is withdrawn, and the reason names the effect")
    func throwingIsWithdrawn() throws {
        let reason = try #require(ThrowingSubjectGate.declineReason(
            for: suggestion(
                template: "idempotence",
                display: "contentsURL(in:)",
                signature: "(URL) throws -> URL"
            )
        ))
        #expect(reason.contains("contentsURL(in:)"))
        #expect(reason.contains("throws"))
    }

    /// **The gate must cost no laws.** A non-throwing subject is untouched, which is the whole
    /// argument for a withdrawal.
    @Test("a non-throwing subject is not gated")
    func nonThrowingIsUntouched() {
        #expect(ThrowingSubjectGate.declineReason(
            for: suggestion(
                template: "idempotence",
                display: "normalized(_:)",
                signature: "(URL) -> URL"
            )
        ) == nil)
    }

    /// ⚠ **The regression this gate's polarity exists for, measured.** Written with an EXEMPT
    /// list, the gate withdrew `SPMPackageReader.parse` under `input-totality` — which spells its
    /// own `_ = try? parse(value); return true`, compiled, and passed. One compile and one pass
    /// lost to an arm nobody had remembered to name.
    @Test("an arm that spells its own try is not gated")
    func totalityIsNotGated() {
        #expect(ThrowingSubjectGate.declineReason(
            for: suggestion(
                template: "input-totality",
                display: "parse(_:)",
                signature: "(String) throws -> Package"
            )
        ) == nil)
    }

    /// The same, for the two arms that take `isThrows` to their own emitters.
    @Test("determinism and replay-idempotence are not gated")
    func throwsHandlingArmsAreNotGated() {
        for template in ["determinism", "replay-idempotence"] {
            #expect(ThrowingSubjectGate.declineReason(
                for: suggestion(
                    template: template,
                    display: "contentsURL(in:)",
                    signature: "(URL) throws -> URL"
                )
            ) == nil, "\(template) handles its own throwing subjects")
        }
    }

    /// ⚠ **`rethrows` called with a non-throwing argument does not throw**, so the call the stub
    /// writes is legal and the law is not withdrawn.
    @Test("a rethrows subject is not gated")
    func rethrowsIsNotGated() {
        #expect(ThrowingSubjectGate.declineReason(
            for: suggestion(
                template: "idempotence",
                display: "mapped(_:)",
                signature: "((Int) -> Int) rethrows -> URL"
            )
        ) == nil)
    }

    /// The word has to be the effects clause, not a type or parameter that contains those letters.
    @Test("a name merely containing the letters is not gated")
    func substringIsNotGated() {
        #expect(ThrowingSubjectGate.declineReason(
            for: suggestion(
                template: "idempotence",
                display: "normalize(_:)",
                signature: "(ThrowsPolicy) -> ThrowsPolicy"
            )
        ) == nil)
    }
}
