import Foundation
@testable import SwiftInferCore
import Testing

/// V1.36.B — `ConstraintRunner.suggest(constraint:subject:)` tests.
@Suite("ConstraintRunner — V1.36.B orchestration")
struct ConstraintRunnerTests {

    // MARK: - Helpers

    private static func makeSummary(name: String = "f") -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [],
            returnTypeText: nil,
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: "Foo",
            bodySignals: .empty
        )
    }

    private static func makeEvidence() -> Evidence {
        Evidence(
            displayName: "f()",
            signature: "() -> Void",
            location: SourceLocation(file: "Test.swift", line: 1, column: 1)
        )
    }

    // MARK: - Gate-driven nil

    @Test("V1.36.B — appliesTo=false returns nil without computing signals")
    func gateFalseReturnsNil() {
        let signalsCalled = LockedFlag()
        let constraint = Constraint<FunctionSummary>(
            templateName: "test",
            appliesTo: { _ in false },
            signals: { _ in
                signalsCalled.set()
                return [Signal(kind: .typeSymmetrySignature, weight: 100, detail: "x")]
            },
            evidence: { _ in [Self.makeEvidence()] },
            identity: { _ in SuggestionIdentity(canonicalInput: "x") }
        )
        let suggestion = ConstraintRunner.suggest(constraint: constraint, subject: Self.makeSummary())
        #expect(suggestion == nil, "gate=false should short-circuit")
        #expect(!signalsCalled.wasSet, "signals closure must NOT be called when gate is false")
    }

    // MARK: - Suppressed-tier nil

    @Test("V1.36.B — suppressed tier (veto present) returns nil")
    func vetoReturnsNil() {
        let constraint = Constraint<FunctionSummary>(
            templateName: "test",
            appliesTo: { _ in true },
            signals: { _ in
                [
                    Signal(kind: .typeSymmetrySignature, weight: 100, detail: "shape"),
                    Signal(kind: .nonDeterministicBody, weight: Signal.vetoWeight, detail: "veto")
                ]
            },
            evidence: { _ in [Self.makeEvidence()] },
            identity: { _ in SuggestionIdentity(canonicalInput: "x") }
        )
        let suggestion = ConstraintRunner.suggest(constraint: constraint, subject: Self.makeSummary())
        #expect(suggestion == nil, "veto should suppress")
    }

    @Test("V1.36.B — below-threshold score returns nil")
    func belowThresholdReturnsNil() {
        let constraint = Constraint<FunctionSummary>(
            templateName: "test",
            appliesTo: { _ in true },
            signals: { _ in
                [Signal(kind: .typeSymmetrySignature, weight: 10, detail: "low")]
            },
            evidence: { _ in [Self.makeEvidence()] },
            identity: { _ in SuggestionIdentity(canonicalInput: "x") }
        )
        let suggestion = ConstraintRunner.suggest(constraint: constraint, subject: Self.makeSummary())
        #expect(suggestion == nil, "score 10 < 20 threshold → suppressed → nil")
    }

    // MARK: - Full Suggestion construction

    @Test("V1.36.B — passing gate + non-suppressed score produces Suggestion")
    func fullSuggestionConstructed() throws {
        let constraint = Constraint<FunctionSummary>(
            templateName: "my-template",
            appliesTo: { _ in true },
            signals: { _ in
                [Signal(kind: .typeSymmetrySignature, weight: 30, detail: "shape")]
            },
            evidence: { _ in [Self.makeEvidence()] },
            identity: { _ in SuggestionIdentity(canonicalInput: "stable") },
            carrier: { _ in "MyCarrier" }
        )
        let suggestion = try #require(ConstraintRunner.suggest(
            constraint: constraint,
            subject: Self.makeSummary()
        ))
        #expect(suggestion.templateName == "my-template")
        #expect(suggestion.score.total == 30)
        #expect(suggestion.score.tier == .possible)
        #expect(suggestion.carrier == "MyCarrier")
        #expect(suggestion.evidence.count == 1)
        #expect(suggestion.evidence[0].displayName == "f()")
    }

    @Test("V1.36.B — caveats flow through to whyMightBeWrong")
    func caveatsFlowThrough() throws {
        let constraint = Constraint<FunctionSummary>(
            templateName: "test",
            appliesTo: { _ in true },
            signals: { _ in
                [Signal(kind: .typeSymmetrySignature, weight: 30, detail: "shape")]
            },
            evidence: { _ in [Self.makeEvidence()] },
            identity: { _ in SuggestionIdentity(canonicalInput: "x") },
            caveats: { _ in
                ["T must conform to Equatable.", "If T is a class with custom ==, ..."]
            }
        )
        let suggestion = try #require(ConstraintRunner.suggest(
            constraint: constraint,
            subject: Self.makeSummary()
        ))
        #expect(suggestion.explainability.whyMightBeWrong.count == 2)
        #expect(suggestion.explainability.whyMightBeWrong[0].contains("Equatable"))
    }

    // MARK: - makeExplainability shape

    @Test("V1.36.B — makeExplainability formats evidence + signals + caveats")
    func explainabilityShape() {
        let evidence = [Self.makeEvidence()]
        let signals = [Signal(kind: .typeSymmetrySignature, weight: 30, detail: "shape")]
        let caveats = ["First caveat", "Second caveat"]
        let block = ConstraintRunner.makeExplainability(
            evidence: evidence, signals: signals, caveats: caveats
        )
        // whySuggested = 1 evidence line + 1 signal line
        #expect(block.whySuggested.count == 2)
        #expect(block.whySuggested[0].contains("f()"))
        #expect(block.whySuggested[0].contains("Test.swift:1"))
        #expect(block.whySuggested[1].contains("shape"))
        // whyMightBeWrong = caveats verbatim
        #expect(block.whyMightBeWrong == caveats)
    }

    @Test("V1.36.B — empty signals + empty caveats produce empty explainability lists")
    func emptyExplainability() {
        let block = ConstraintRunner.makeExplainability(
            evidence: [], signals: [], caveats: []
        )
        #expect(block.whySuggested.isEmpty)
        #expect(block.whyMightBeWrong.isEmpty)
    }
}

/// Thread-safe boolean flag for the gate-short-circuit test.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func set() {
        lock.lock(); defer { lock.unlock() }
        flag = true
    }

    var wasSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return flag
    }
}
