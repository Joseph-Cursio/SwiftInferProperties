@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// `SubjectCallPlan` — how a test calls an agreement law's subject, or why it cannot.
///
/// **Every row is scanned from source**, then read through `FunctionSummary.inferenceEvidence`,
/// which is the row `discover` hands accept. A hand-written signature is how the `inout` decline
/// stayed dead: its fixture spelled `inout Scanner` in the type, which the scanner never does.
@Suite("SubjectCallPlan — one plan for the call, or one named reason")
struct SubjectCallPlanTests {

    static func evidence(_ source: String, named name: String) throws -> Evidence {
        let summaries = FunctionScanner.scan(source: source, file: "Subject.swift")
        return try #require(summaries.first { $0.name == name }).inferenceEvidence
    }

    static func plan(_ source: String, named name: String, universe: Set<String> = []) throws -> SubjectCallPlan {
        let outcome = SubjectCallPlan.outcome(for: try evidence(source, named: name), typeUniverse: universe)
        guard case let .plan(plan) = outcome else {
            Issue.record("expected a plan, got \(outcome)")
            throw PlanDeclined()
        }
        return plan
    }

    static func reason(_ source: String, named name: String) throws -> String {
        try #require(SubjectCallPlan.declineReason(for: try evidence(source, named: name)))
    }

    struct PlanDeclined: Error {}

    // MARK: - What a plan holds

    @Test func aStaticMemberIsQualifiedByItsOwner() throws {
        let plan = try Self.plan("""
            enum BeadCorrelation {
                static func correlation(for observations: [BeadObservation]) -> Double? { nil }
            }
            """, named: "correlation")
        #expect(plan.callee.qualifier == "BeadCorrelation")
        #expect(plan.callee.isInstanceMethod == false)
        #expect(plan.callee.call(["value"]) == "BeadCorrelation.correlation(for: value)")
        #expect(plan.argumentTypes == ["[BeadObservation]"])
        #expect(plan.returnTypeText == "Double?")
        #expect(plan.isAsync == false)
        #expect(plan.isThrows == false)
    }

    @Test func anInstanceMethodDrawsItsReceiverFirst() throws {
        let plan = try Self.plan("""
            struct WorkspaceJail {
                func relative(_ url: URL) -> String { "" }
            }
            """, named: "relative")
        #expect(plan.callee.isInstanceMethod)
        #expect(plan.argumentTypes == ["WorkspaceJail", "URL"])
        #expect(plan.callee.call(["args.0", "args.1"]) == "args.0.relative(args.1)")
    }

    @Test func anOperatorIsSpelledAsAWord() throws {
        let plan = try Self.plan("""
            struct Money {
                static func + (lhs: Money, rhs: Money) -> Money { lhs }
            }
            """, named: "+")
        #expect(plan.callee.identifierName == "plus")
        #expect(plan.argumentTypes == ["Money", "Money"])
        #expect(plan.callee.call(["args.0", "args.1"]) == "(args.0 + args.1)")
    }

    @Test("effects are the function's own, typed throws included", arguments: [
        ("static func parse(from text: String) throws -> Int { 0 }", false, true),
        ("static func parse(from text: String) throws(ParseError) -> Int { 0 }", false, true),
        ("static func parse(from text: String) async -> Int { 0 }", true, false),
        ("static func parse(from text: String) async throws -> Int { 0 }", true, true)
    ])
    func effectsAreRead(declaration: String, isAsync: Bool, isThrows: Bool) throws {
        let plan = try Self.plan("enum CoverageReport {\n    \(declaration)\n}", named: "parse")
        #expect(plan.isAsync == isAsync)
        #expect(plan.isThrows == isThrows)
        #expect(plan.returnTypeText == "Int")
    }

    /// A test file has no `Self`: the owner is written in its place, so a resolver can derive it.
    @Test func selfInAStaticMembersParametersBecomesTheOwner() throws {
        let plan = try Self.plan("""
            struct Point {
                static func merge(_ lhs: Self, _ rhs: [Self]) -> Self { lhs }
            }
            """, named: "merge")
        #expect(plan.argumentTypes == ["Point", "[Point]"])
        #expect(plan.returnTypeText == "Self", "the result keeps its spelling; only the drawn arguments move")
    }

    @Test func aNestedParameterIsQualifiedAgainstTheUniverseOnly() throws {
        let source = """
            struct Outer {
                struct Inner {}
                static func count(_ one: Inner, _ many: [Inner]) -> Int { 0 }
            }
            """
        let qualified = try Self.plan(source, named: "count", universe: ["Outer", "Outer.Inner"])
        #expect(qualified.argumentTypes == ["Outer.Inner", "[Outer.Inner]"])
        let unchanged = try Self.plan(source, named: "count")
        #expect(unchanged.argumentTypes == ["Inner", "[Inner]"])
    }

    // MARK: - What declines, and the reason it gives

    /// **The latent defect.** The scanner strips `inout` from the type it renders, so the old check
    /// for an `inout ` prefix never fired on a scanned row, and the stub passed a drawn `let`.
    @Test func aScannedInoutParameterDeclines() throws {
        let source = """
            enum Tokenizer {
                static func consume(_ scanner: inout Scanner) -> Token { fatalError() }
            }
            """
        let row = try Self.evidence(source, named: "consume")
        #expect(row.signature.contains("inout") == false, "the scanner's spelling, which the old check read")
        #expect(row.inoutParameterIndices == [0])
        let reason = try Self.reason(source, named: "consume")
        #expect(reason.contains("inout"))
    }

    @Test("a closure parameter is named as one, not as a label-count mismatch", arguments: [
        "(Int) -> Bool",
        "((Int) -> Bool)?",
        "@escaping (Int) throws -> Bool"
    ])
    func aFunctionTypedParameterDeclines(type: String) throws {
        let reason = try Self.reason(
            "enum Filter {\n    static func count(_ items: [Int], where test: \(type)) -> Int { 0 }\n}",
            named: "count"
        )
        #expect(reason.contains("function-typed parameter"))
        #expect(reason.contains(type))
        #expect(reason.contains("argument label(s)") == false)
    }

    @Test func aFunctionTypedResultDeclines() throws {
        let reason = try Self.reason(
            "enum Adders {\n    static func adder(_ step: Int) -> (Int) -> Int { { $0 + step } }\n}",
            named: "adder"
        )
        #expect(reason == "adder(_:) returns a function (`(Int) -> Int`), which `==` cannot compare")
    }

    @Test func aValueReturningMutatingMethodDeclines() throws {
        let reason = try Self.reason(
            "struct Counter {\n    mutating func advance(by step: Int) -> Int { step }\n}",
            named: "advance"
        )
        #expect(reason.contains("`mutating`"))
        #expect(reason.contains("drawn receiver"))
    }

    /// The sentence no longer names a law: the reference oracle reaches it through the same plan.
    @Test func aThrowingTupleDeclinesWithoutNamingALaw() throws {
        let reason = try Self.reason(
            "enum Pairs {\n    static func x(_ value: Int) throws -> (Int, Int) { (value, value) }\n}",
            named: "x"
        )
        #expect(reason.hasPrefix("x(_:) throws and returns a tuple"))
        #expect(reason.contains("the law would compare"))
        #expect(reason.contains("determinism law") == false)
    }

    @Test func aSevenTupleDeclines() throws {
        let reason = try Self.reason(
            "enum Spread {\n    static func s(_ value: Int) -> (Int, Int, Int, Int, Int, Int, Int) { fatalError() }\n}",
            named: "s"
        )
        #expect(reason.contains("tuple"))
    }

    @Test func aStaticComputedPropertyTakesNoArguments() throws {
        let reason = try Self.reason("enum Config {\n    static var limit: Int { 3 }\n}", named: "limit")
        #expect(reason.contains("takes no arguments"))
    }
}
