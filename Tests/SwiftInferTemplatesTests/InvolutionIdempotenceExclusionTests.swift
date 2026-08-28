import Foundation
@testable import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// `idempotence` must not survive beside `involution` on the same declaration.
///
/// The two are mutually exclusive except for the identity function, so a declaration carrying
/// both proposals is the tool contradicting itself. Measured on `Euclid`, where `Mesh.inverted()`
/// returned `measured-bothPass` for BOTH — a false law reported as verified, which is worse than
/// the two siblings that refuted.
@Suite("Involution excludes idempotence on the same declaration")
struct InvolutionIdempotenceExclusionTests {

    private func suggestion(
        template: String,
        file: String,
        line: Int
    ) -> Suggestion {
        let evidence = Evidence(
            displayName: "inverted()",
            signature: "() -> Self",
            location: SourceLocation(file: file, line: line, column: 1)
        )
        return Suggestion(
            templateName: template,
            evidence: [evidence],
            score: Score(signals: []),
            generator: GeneratorMetadata(source: .derivedComposite, confidence: .high, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: ["why"], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "\(template)|\(file)|\(line)"),
            carrier: nil,
            carrierTypeName: "Mesh"
        )
    }

    @Test("idempotence is dropped when involution names the same (file, line)")
    func contradictedIdempotenceIsRemoved() {
        let input = [
            suggestion(template: "involution", file: "Mesh.swift", line: 10),
            suggestion(template: "idempotence", file: "Mesh.swift", line: 10)
        ]

        let kept = TemplateRegistry.applyInvolutionIdempotenceExclusion(to: input)

        #expect(kept.map(\.templateName) == ["involution"])
    }

    @Test("idempotence on a DIFFERENT declaration is untouched")
    func unrelatedIdempotenceSurvives() {
        let input = [
            suggestion(template: "involution", file: "Mesh.swift", line: 10),
            suggestion(template: "idempotence", file: "Mesh.swift", line: 99)
        ]

        let kept = TemplateRegistry.applyInvolutionIdempotenceExclusion(to: input)

        #expect(kept.count == 2)
    }

    @Test("idempotence in a same-named function on another FILE is untouched")
    func sameNameDifferentFileSurvives() {
        let input = [
            suggestion(template: "involution", file: "Mesh.swift", line: 10),
            suggestion(template: "idempotence", file: "Vertex.swift", line: 10)
        ]

        let kept = TemplateRegistry.applyInvolutionIdempotenceExclusion(to: input)

        #expect(kept.count == 2)
    }

    @Test("involution is never dropped, whichever order the proposals arrive in")
    func involutionIsNeverTheCasualty() {
        let input = [
            suggestion(template: "idempotence", file: "Mesh.swift", line: 10),
            suggestion(template: "involution", file: "Mesh.swift", line: 10)
        ]

        let kept = TemplateRegistry.applyInvolutionIdempotenceExclusion(to: input)

        #expect(kept.map(\.templateName) == ["involution"])
    }

    @Test("a corpus with no involution proposals is returned unchanged")
    func noInvolutionMeansNoChange() {
        let input = [
            suggestion(template: "idempotence", file: "Mesh.swift", line: 10),
            suggestion(template: "predicate", file: "Mesh.swift", line: 20)
        ]

        let kept = TemplateRegistry.applyInvolutionIdempotenceExclusion(to: input)

        #expect(kept.count == 2)
    }
}
