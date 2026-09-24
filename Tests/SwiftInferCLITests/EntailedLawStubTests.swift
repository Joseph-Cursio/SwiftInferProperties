@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// `involution`, `role-postcondition` and `equivalence-relation` get accept-path writers. Each had
/// a `verify` composer and no writer (`StubWriterCoverageTests`), so a reader could verify the law
/// and never get it as a test in their own suite.
@Suite("Entailed law writers — involution, role postcondition, equivalence")
struct EntailedLawStubTests {

    private static func suggestion(
        template: String,
        displayName: String,
        signature: String,
        carrier: String? = nil,
        isInstanceMethod: Bool = false
    ) -> Suggestion {
        Suggestion(
            templateName: template,
            evidence: [
                Evidence(
                    displayName: displayName,
                    signature: signature,
                    location: SourceLocation(file: "F.swift", line: 1, column: 1),
                    isInstanceMethod: isInstanceMethod,
                    qualifiedTypeName: carrier
                )
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "F.swift::\(displayName)")
        )
    }

    private static func stub(_ suggestion: Suggestion) -> String? {
        InteractiveTriage.templateStub(for: suggestion)
    }

    // MARK: - involution

    @Test("an involution checks that applying it twice gives the input back")
    func involution() throws {
        let text = try #require(Self.stub(Self.suggestion(
            template: "involution", displayName: "toggled(_:)", signature: "(Bool) -> Bool"
        )))
        #expect(text.contains("toggled(toggled(value)) == value"), "got:\n\(text)")
        #expect(text.contains("toggled_isAnInvolution"))
    }

    // MARK: - role postcondition

    @Test("a lowercasing function checks its result has no uppercase character")
    func lowercasedPostcondition() throws {
        let text = try #require(Self.stub(Self.suggestion(
            template: "role-postcondition", displayName: "lowercased(_:)", signature: "(String) -> String"
        )))
        #expect(text.contains("let result = lowercased(value); return !(result.contains(where: { $0.isUppercase }))"),
                "got:\n\(text)")
    }

    @Test("a role whose check needs a proof the tool does not have writes nothing, as in verify")
    func sortedStaysAdvisory() {
        #expect(Self.stub(Self.suggestion(
            template: "role-postcondition", displayName: "sorted(_:)", signature: "([Item]) -> [Item]"
        )) == nil)
    }

    // MARK: - equivalence relation

    @Test("a static equivalence checks all three laws and reports untested transitivity")
    func staticEquivalence() throws {
        let text = try #require(Self.stub(Self.suggestion(
            template: "equivalence-relation", displayName: "areEqual(_:_:)", signature: "(Int, Int) -> Bool"
        )))
        #expect(text.contains("guard areEqual(a, a) else { return false }"), "got:\n\(text)")
        #expect(text.contains("guard areEqual(a, b) == areEqual(b, a) else { return false }"))
        #expect(text.contains("return !(areEqual(a, b) && areEqual(b, c)) || areEqual(a, c)"))
        #expect(text.contains("NOT APPLIED — transitivity"))
        #expect(text.contains("Gen<Int>.int(in: 0...4)"), "operands are drawn tie-dense")
    }

    @Test("an equivalence held by a receiver draws it once and keeps it across the triple")
    func receiverHeldEquivalence() throws {
        let text = try #require(Self.stub(Self.suggestion(
            template: "equivalence-relation", displayName: "equals(_:_:)", signature: "(Int, Int) -> Bool",
            carrier: "Checker", isInstanceMethod: true
        )))
        #expect(text.contains("let relation = (Checker.gen()"), "got:\n\(text)")
        #expect(text.contains("relation.equals(a, b)"))
        #expect(text.contains("return (relation, a, b, c)"))
    }

    @Test("an equivalence whose receiver is an operand relates two drawn values")
    func receiverIsAnOperand() throws {
        let text = try #require(Self.stub(Self.suggestion(
            template: "equivalence-relation", displayName: "isEqual(to:)", signature: "(Int) -> Bool",
            carrier: "Int", isInstanceMethod: true
        )))
        #expect(text.contains("a.isEqual(to: b)"), "got:\n\(text)")
        #expect(!text.contains("let relation"))
    }
}
