@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// `measure-non-negativity` gets a writer: a count, size or magnitude is never negative.
///
/// It was the largest template with no writer — 442 rows at 20 corpora and 23 corpus-funnel
/// declines over 9 repositories (`StubWriterCoverageTests`). It shares totality's call machinery,
/// so it reaches both shapes `MeasureTemplate` admits, and the stub and `declineReason` must agree
/// on each, the invariant `ArityFreeTotalityTests` pins for totality.
@Suite("Measure non-negativity — the accept path writes it")
struct MeasureNonNegativityStubTests {

    private static func suggestion(
        displayName: String,
        signature: String,
        carrier: String? = nil,
        isInstanceMethod: Bool = false
    ) -> Suggestion {
        Suggestion(
            templateName: "measure-non-negativity",
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

    private static func emits(_ suggestion: Suggestion) throws -> String {
        #expect(StubApplicationArity.declineReason(for: suggestion) == nil)
        return try #require(InteractiveTriage.entailedTemplateStub(for: suggestion))
    }

    @Test("a one-argument measure checks its result is non-negative")
    func oneArgumentMeasure() throws {
        let stub = try Self.emits(Self.suggestion(displayName: "depth(_:)", signature: "(Node) -> Int"))
        #expect(stub.contains("return depth(value) >= 0"), "got:\n\(stub)")
        #expect(stub.contains("depth_isNonNegative"))
        #expect(stub.contains("returned a negative measure"))
    }

    @Test("a nullary measure of self draws the receiver and checks it")
    func nullaryMeasureOfSelf() throws {
        let stub = try Self.emits(Self.suggestion(
            displayName: "remainingCount()",
            signature: "() -> Int",
            carrier: "Buffer",
            isInstanceMethod: true
        ))
        #expect(stub.contains("value.remainingCount() >= 0"), "got:\n\(stub)")
        #expect(stub.contains("Buffer.gen()"), "the receiver is the declaring type, drawn")
    }

    @Test("the law is a check on the result, not a discarded call")
    func notATotalityStub() throws {
        let stub = try Self.emits(Self.suggestion(displayName: "depth(_:)", signature: "(Node) -> Int"))
        #expect(!stub.contains("_ = "))
        #expect(!stub.contains("return true"))
    }
    /// A constructed receiver with a nullary measure leaves nothing to draw. The first cut
    /// rendered `{ rng in ().run(using: &rng) }`, which does not compile — 15 set-aside stubs on
    /// the census that shipped this writer, e.g. pbt-book's `BoundedCache(capacity: 1).count`.
    @Test("a constructed receiver with nothing to draw still compiles")
    func constructedReceiverWithNothingToDraw() throws {
        let suggestion = Self.suggestion(
            displayName: "count()", signature: "() -> Int", carrier: "BoundedCache", isInstanceMethod: true
        )
        let constructed: (String) -> String? = { $0 == "BoundedCache" ? "BoundedCache(capacity: 1)" : nil }
        let stub = try #require(InteractiveTriage.entailedTemplateStub(
            for: suggestion,
            receiverExpression: constructed
        ))
        #expect(!stub.contains("().run(using:"), "got:\n\(stub)")
        #expect(stub.contains("sample: { _ in () }"))
        #expect(stub.contains("BoundedCache(capacity: 1).count() >= 0"))
    }
}
