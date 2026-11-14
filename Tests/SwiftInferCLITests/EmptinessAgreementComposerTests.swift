@testable import SwiftInferCLI
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// `emptiness-agreement` verify support (#701), second half: the composer, the gates and the
/// verdict phrasing. Split from `EmptinessAgreementVerifySupportTests` (projection and call
/// resolution) only for SwiftLint's type-body cap.
@Suite("emptiness-agreement — composition and phrasing")
struct EmptinessAgreementComposerTests {

    private static func inputs(calls: [String]) -> StrategistDispatchEmitter.Inputs {
        StrategistDispatchEmitter.Inputs(
            carrier: "Int",
            typeShape: nil,
            template: "emptiness-agreement",
            functionCalls: calls,
            seedHex: .init(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
            trialBudget: .small
        )
    }

    private static let recipe = StrategistDispatchEmitter.GeneratorRecipe(
        expression: "Gen<Int>.int()", carrierTypeName: "Report", imports: []
    )

    // MARK: - Composition

    @Test("the comparison follows the polarity the names give", arguments: [
        (["hasIssues", "totalIssueCount()"], "if holds != (measured > 0) {"),
        (["isNotEmpty()", "count"], "if holds != (measured > 0) {"),
        (["isEmpty", "count()"], "if holds != (measured == 0) {"),
        (["isEmpty()", "count"], "if holds != (measured == 0) {"),
    ])
    func comparisonFollowsPolarity(calls: [String], check: String) throws {
        let source = try #require(StrategistDispatchEmitter.composeEmptinessAgreementPass(
            inputs: Self.inputs(calls: calls), recipe: Self.recipe
        ))
        #expect(source.contains(check))
        #expect(source.contains("let holds: Bool = value.\(calls[0])\n"))
        #expect(source.contains("let measured = value.\(calls[1])\n"))
    }

    /// Fails by ASSERTION. Totality's markers would make the parser read a trap in a member as a
    /// refutation of a law that is not totality.
    @Test("the pass prints the assertion contract and none of totality's trap markers")
    func passPrintsTheAssertionContract() throws {
        let source = try #require(StrategistDispatchEmitter.composeEmptinessAgreementPass(
            inputs: Self.inputs(calls: ["hasIssues", "totalIssueCount"]), recipe: Self.recipe
        ))
        for marker in [
            "VERIFY_DEFAULT_RESULT: FAIL", "VERIFY_DEFAULT_TRIAL:", "VERIFY_DEFAULT_INPUT: \\(value)",
            "VERIFY_DEFAULT_FORWARD: (\\(holds), \\(measured))",
            "VERIFY_DEFAULT_INVERSE: <hasIssues == (totalIssueCount > 0)>",
            "VERIFY_DEFAULT_RESULT: PASS", "VERIFY_DEFAULT_TRIALS:", "exit(1)",
        ] {
            #expect(source.contains(marker), "missing \(marker)")
        }
        #expect(!source.contains("VERIFY_TRIAL_INPUT"))
        #expect(!source.contains("VERIFY_TRIAL_CARRIER"))
    }

    @Test("names that do not pair, or a missing second name, compose nothing")
    func unpairedNamesComposeNothing() {
        for calls in [["hasIssues", "retryCount"], ["isEmpty"]] {
            #expect(StrategistDispatchEmitter.composeEmptinessAgreementPass(
                inputs: Self.inputs(calls: calls), recipe: Self.recipe
            ) == nil)
        }
    }

    @Test("the emitted stub carries a real boundary pass of the same law")
    func edgePassRunsTheSameLaw() throws {
        let source = try StrategistDispatchEmitter.emit(Self.inputs(calls: ["isEmpty", "count"]))
        #expect(source.contains("VERIFY_EDGE_INVERSE: <isEmpty == (count == 0)>"))
        #expect(!source.contains("VERIFY_EDGE_TRIALS: 0"), "fell back to the zero-trial sentinel")
    }

    // MARK: - The gates

    @Test("the template is in the verifiable vocabulary, the dispatch gate and the algebraic route")
    func gatesAgree() {
        #expect(TemplateName.verifiable.contains(.emptinessAgreement))
        #expect(SwiftInferCommand.Verify.supportedTemplates.contains("emptiness-agreement"))
        #expect(TemplateName.strategistAlgebraicLaws.contains(.emptinessAgreement))
        #expect(DeliberateVerifyDecline.reason(forTemplate: "emptiness-agreement") == nil)
        #expect(EmptinessAgreementTemplate.templateName == TemplateName.emptinessAgreement.rawValue)
    }

    @Test("it has its own verdict phrasing rather than the round-trip fallback")
    func hasOwnRenderShape() throws {
        let shape = try #require(RenderShape.byTemplateName["emptiness-agreement"])
        let subject = shape.subjectLine(context: .init(
            templateName: "emptiness-agreement",
            forwardName: "hasIssues",
            inverseName: "totalIssueCount",
            carrierType: "Report"
        ))
        #expect(subject == "emptiness-agreement on hasIssues / totalIssueCount over Report")
    }

    /// The law is a naming conjecture: a refutation must not read as a plain defect.
    @Test("a refutation shows both members, the law with its polarity, and the caveat", arguments: [
        ("hasIssues", "totalIssueCount", "hasIssues == (totalIssueCount > 0)"),
        ("isEmpty", "count", "isEmpty == (count == 0)"),
    ])
    func refutationCarriesTheCaveat(predicate: String, measure: String, law: String) {
        let rendered = VerifyResultRenderer.render(
            .defaultFails(DefaultFailDetail(
                trial: 0, input: "Report(deprecated: 1, removed: 0)", forwardResult: "(false, 1)",
                inverseResult: "<\(law)>"
            )),
            context: .init(
                templateName: "emptiness-agreement",
                forwardName: predicate,
                inverseName: measure,
                carrierType: "Report"
            )
        )
        #expect(rendered.contains("(input.\(predicate), input.\(measure)) = (false, 1)"), "got:\n\(rendered)")
        #expect(rendered.contains(law), "got:\n\(rendered)")
        #expect(rendered.contains("conjecture"), "got:\n\(rendered)")
        #expect(rendered.contains("narrower than its count"), "got:\n\(rendered)")
        #expect(!rendered.contains("round-trip"))
        #expect(!rendered.contains("isApproximatelyEqual"))
    }
}
