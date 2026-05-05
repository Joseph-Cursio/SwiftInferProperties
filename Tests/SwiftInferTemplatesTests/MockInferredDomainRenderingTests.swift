import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("LiftedTestEmitter — M10.3 domain hint rendering")
struct MockInferredDomainRenderingTests {

    private static func unvetoedHint() -> DomainHint {
        DomainHint(
            forwardName: "encode",
            reverseName: "decode",
            producerName: "encode",
            domainTypeName: "MyType",
            siteCount: 5,
            producerVeto: nil,
            suggestedGenerator: "Gen<MyType>.map(encode)"
        )
    }

    private static func mockWithDomainHint(_ hint: DomainHint) -> MockGenerator {
        MockGenerator(
            typeName: "MyType",
            argumentSpec: [
                MockGenerator.Argument(label: nil, swiftTypeName: "Int", observedLiterals: ["1", "2", "3"])
            ],
            siteCount: 5,
            domainHint: hint
        )
    }

    @Test("Unvetoed domain hint substitutes Gen<T>.map(forward) generator with provenance comment")
    func unvetoedHintOverridesGenerator() {
        let mock = Self.mockWithDomainHint(Self.unvetoedHint())
        let rendered = LiftedTestEmitter.mockInferredGenerator(mock)
        #expect(rendered.contains("// Inferred domain:"))
        #expect(rendered.contains("decode's argument was always encode's output"))
        #expect(rendered.contains("across 5 sites"))
        #expect(rendered.contains("narrowing to Gen<MyType>.map(encode)"))
        #expect(rendered.contains("Gen<MyType>.map(encode)"))
    }

    @Test("Throwing-producer veto surfaces comment-only — generator uses default mock shape")
    func throwingVetoEmitsCommentOnly() {
        let hint = DomainHint(
            forwardName: "encode",
            reverseName: "decode",
            producerName: "encode",
            domainTypeName: "MyType",
            siteCount: 5,
            producerVeto: .producerThrows,
            suggestedGenerator: "Gen<MyType>.map(encode)"
        )
        let mock = Self.mockWithDomainHint(hint)
        let rendered = LiftedTestEmitter.mockInferredGenerator(mock)
        // The vetoed-hint surface doesn't substitute the generator in
        // this code path — the M10.3 renderer surfaces the comment
        // through `domainCommentLine(for:)` which is callable directly.
        let comment = LiftedTestEmitter.domainCommentLine(for: hint)
        #expect(comment.contains("narrowing skipped"))
        #expect(comment.contains("producerThrows"))
        #expect(comment.contains("can't shrink through"))
        // Generator still uses the standard mock shape (not Gen<T>.map).
        #expect(!rendered.contains("Gen<MyType>.map(encode)"))
    }

    @Test("Async-producer veto comment names the runner-incompatibility reason")
    func asyncVetoCommentText() {
        let hint = DomainHint(
            forwardName: "encode",
            reverseName: "decode",
            producerName: "encode",
            domainTypeName: "MyType",
            siteCount: 4,
            producerVeto: .producerAsync,
            suggestedGenerator: "Gen<MyType>.map(encode)"
        )
        let comment = LiftedTestEmitter.domainCommentLine(for: hint)
        #expect(comment.contains("producerAsync"))
        #expect(comment.contains("synchronous"))
        #expect(comment.contains("4 sites"))
    }

    @Test("Multi-arg veto comment cites the unary `Gen<_>.map` constraint")
    func multiArgVetoCommentText() {
        let hint = DomainHint(
            forwardName: "encode",
            reverseName: "decode",
            producerName: "encode",
            domainTypeName: "MyType",
            siteCount: 3,
            producerVeto: .producerMultiArg,
            suggestedGenerator: "Gen<MyType>.map(encode)"
        )
        let comment = LiftedTestEmitter.domainCommentLine(for: hint)
        #expect(comment.contains("producerMultiArg"))
        #expect(comment.contains("unary"))
    }

    @Test("Single-site rendering uses singular `site` instead of `sites`")
    func singleSiteSingularizesPlural() {
        let hint = DomainHint(
            forwardName: "encode",
            reverseName: "decode",
            producerName: "encode",
            domainTypeName: "MyType",
            siteCount: 1,
            producerVeto: nil,
            suggestedGenerator: "Gen<MyType>.map(encode)"
        )
        let comment = LiftedTestEmitter.domainCommentLine(for: hint)
        #expect(comment.contains("across 1 site —"))
        #expect(!comment.contains("1 sites"))
    }
}
