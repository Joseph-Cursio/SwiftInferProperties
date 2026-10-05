@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// **A reason exactly when no stub.** `deterministicStub` writes from `SubjectCallPlan` and
/// `StubApplicationArity.declineReason` reports from it, so for any row the two cannot disagree —
/// pinned over a table that crosses every decline and every plan shape.
@Suite("SubjectCallPlan — the writer and the decline read one outcome")
struct SubjectCallPlanBothSidesTests {

    /// Each row: a declaration inside `enum Host` (or the whole source when it declares its own
    /// type), and the function's name.
    static let rows: [(source: String, name: String)] = [
        ("enum Host {\n    static func f(_ value: Int) -> Int { value }\n}", "f"),
        ("struct Host {\n    func f(_ value: String) -> Bool { true }\n}", "f"),
        ("enum Host {\n    static func f(_ value: Int) throws -> String { \"\" }\n}", "f"),
        ("enum Host {\n    static func f(_ value: Int) async -> String { \"\" }\n}", "f"),
        ("struct Host {\n    static func + (lhs: Host, rhs: Host) -> Host { lhs }\n}", "+"),
        ("struct Host {\n    static func f(_ lhs: Self, _ rhs: Self) -> Bool { true }\n}", "f"),
        ("enum Host {\n    static func f(_ value: Int) -> Double { 0 }\n}", "f"),
        ("enum Host {\n    static func f(_ value: Int) -> (Int, Int) { (value, value) }\n}", "f"),
        ("enum Host {\n    static func f(_ value: inout Int) -> Int { value }\n}", "f"),
        ("enum Host {\n    static func f(_ test: (Int) -> Bool) -> Int { 0 }\n}", "f"),
        ("enum Host {\n    static func f(_ value: Int) -> (Int) -> Int { { $0 } }\n}", "f"),
        ("struct Host {\n    mutating func f(_ value: Int) -> Int { value }\n}", "f"),
        ("enum Host {\n    static func f(_ value: Int) throws -> (Int, Int) { (value, value) }\n}", "f"),
        ("enum Host {\n    static var f: Int { 3 }\n}", "f"),
        ("func f(_ value: Int) -> Int { value }", "f")
    ]

    static func suggestion(for evidence: Evidence) -> Suggestion {
        Suggestion(
            templateName: "determinism",
            evidence: [evidence],
            score: Score(signals: [Signal(kind: .deterministicPurity, weight: 30, detail: "seed")]),
            generator: GeneratorMetadata(source: .notYetComputed, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "determinism|\(evidence.displayName)")
        )
    }

    @Test("the plan declines exactly when the writer writes nothing", arguments: rows.indices)
    func aReasonExactlyWhenNoStub(row: Int) throws {
        let (source, name) = Self.rows[row]
        let evidence = try SubjectCallPlanTests.evidence(source, named: name)
        let law = Self.suggestion(for: evidence)
        let reason = SubjectCallPlan.declineReason(for: evidence)
        let stub = InteractiveTriage.deterministicStub(for: law)
        #expect((reason != nil) == (stub == nil), "\(source): reason \(reason ?? "nil")")
        #expect(StubApplicationArity.declineReason(for: law) == reason)
    }

    /// The table must hold both outcomes, or the pin above proves nothing.
    @Test func theTableHoldsBothOutcomes() throws {
        let reasons = try Self.rows.map { row in
            SubjectCallPlan.declineReason(for: try SubjectCallPlanTests.evidence(row.source, named: row.name))
        }
        #expect(reasons.filter { $0 == nil }.count == 9)
        #expect(reasons.filter { $0 != nil }.count == 6)
    }
}
