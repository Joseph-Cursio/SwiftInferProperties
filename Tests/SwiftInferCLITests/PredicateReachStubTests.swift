import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// A `predicate` stub carries a reach test after its totality law (#665 commit 4b, the W form #724's
/// re-take decided: `docs/measurements/predicate-reach-check-reopen.md`).
///
/// The reach test is only worth its note if it sees what the census measured: the law's own draws,
/// through the law's own call, after the law's 100 calls. The census's `Again` reading is the one
/// #665 §9's crosscheck holds it to. So these tests pin it to the law **line for line**: the same
/// draw statements in the same order, pairings included, and the same call text. They also pin the
/// three shapes the crosscheck's normalisation removes (`strip_reach` in
/// `scripts/predicate_outcome_reach.py`), because an addition outside them blocks the crosscheck.
///
/// Measured end to end on the V1 toy (`fixtures/predicate-outcome-reach/toy`). Every stub built under
/// `-warnings-as-errors`. Every reach verdict with a known class matched the toy's `class_again`,
/// including the stateful `isFirstSighting` when its law ran first, and the 20 stubs equalled
/// `main`'s after the crosscheck's normalisation.
@Suite("Predicate reach — the W-form reach test beside a predicate's law")
struct PredicateReachStubTests {

    private static func suggestion(
        displayName: String,
        signature: String,
        template: String = "predicate",
        carrier: String? = nil,
        isInstanceMethod: Bool = false,
        globalActor: String? = nil,
        inoutParameterIndices: [Int] = []
    ) -> Suggestion {
        Suggestion(
            templateName: template,
            evidence: [
                Evidence(
                    displayName: displayName,
                    signature: signature,
                    location: SourceLocation(file: "F.swift", line: 1, column: 1),
                    isInstanceMethod: isInstanceMethod,
                    qualifiedTypeName: carrier,
                    globalActor: globalActor,
                    inoutParameterIndices: inoutParameterIndices
                ),
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "F.swift::\(displayName)")
        )
    }

    /// A static predicate over one `String`: the plain shape.
    private static let isBlank = suggestion(displayName: "isBlank(_:)", signature: "(String) -> Bool", carrier: "Text")

    private static func stub(_ suggestion: Suggestion) throws -> String {
        try #require(InteractiveTriage.entailedTemplateStub(for: suggestion))
    }

    /// The text of one `@Test func` in `stub`, from its line to the brace that closes it, by indentation.
    private static func test(named name: String, in stub: String) throws -> String {
        let lines = stub.components(separatedBy: "\n")
        let start = try #require(lines.firstIndex { $0.contains("@Test func \(name)(") })
        let indent = lines[start].prefix { $0 == " " }
        let end = try #require(lines[(start + 1)...].firstIndex { $0 == indent + "}" })
        return lines[start ... end].joined(separator: "\n")
    }

    // MARK: - Which stubs carry it

    @Test func aPredicateCarriesTheReachTestAfterItsLaw() throws {
        let stub = try Self.stub(Self.isBlank)
        let law = try #require(stub.range(of: "@Test func isBlank_isTotal()"))
        let reach = try #require(stub.range(of: "@Test func isBlank_reachesBothOutcomes() async {"))
        let helper = try #require(stub.range(of: "nonisolated private static func reachNote(_ text: String) {"))
        #expect(law.lowerBound < reach.lowerBound && reach.lowerBound < helper.lowerBound,
                "the reach test follows the law in source order, so it runs after the law's 100 calls")
    }

    /// The census decided W for `predicate` alone; `input-totality` states the same law over a
    /// subject whose answer is not a `Bool`, and `measure-non-negativity` checks its own result.
    @Test func inputTotalityAndNonNegativityCarryNone() throws {
        let totality = try Self.stub(Self.suggestion(
            displayName: "parse(_:)", signature: "(String) -> Bool", template: "input-totality", carrier: "Parser"
        ))
        let measure = try Self.stub(Self.suggestion(
            displayName: "count(_:)", signature: "(String) -> Int", template: "measure-non-negativity", carrier: "Text"
        ))
        #expect(!totality.contains("reachesBothOutcomes") && !totality.contains("reachNote"))
        #expect(!measure.contains("reachesBothOutcomes") && !measure.contains("reachNote"))
    }

    /// `PredicateTemplate` admits no throwing or async subject (#665 N5). One that slipped through
    /// keeps its law and gets no reach test, rather than one whose answer cannot be read.
    @Test func aThrowingOrAsyncSubjectGetsNoReachTest() throws {
        let throwing = try Self.stub(Self.suggestion(
            displayName: "check(_:)", signature: "(String) throws -> Bool", carrier: "Text"
        ))
        let async = try Self.stub(Self.suggestion(
            displayName: "probe(_:)", signature: "(String) async -> Bool", carrier: "Text"
        ))
        #expect(throwing.contains("check_isTotal") && !throwing.contains("reachesBothOutcomes"))
        #expect(async.contains("probe_isTotal") && !async.contains("reachesBothOutcomes"))
    }

    // MARK: - It sees the law's draws through the law's call

    /// The law's sample closure and the reach loop draw the same statements in the same order,
    /// pairing included. A pairing draws a random number, so dropping or reordering one would
    /// shift every later draw.
    @Test func theReachLoopDrawsExactlyTheLawsInputs() throws {
        let stub = try Self.stub(Self.suggestion(
            displayName: "isMatching(searchPattern:)",
            signature: "(String) -> Bool",
            carrier: "String",
            isInstanceMethod: true
        ))
        let law = try Self.test(named: "isMatching_isTotal", in: stub)
        let reach = try Self.test(named: "isMatching_reachesBothOutcomes", in: stub)
        let drawLines = { (text: String) in
            text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.contains("using: &rng") }
        }
        #expect(drawLines(law).contains { $0.hasPrefix("if Int.random(in: 0 ..< 4") }, "the pairing is exercised")
        #expect(drawLines(reach) == drawLines(law))
    }

    @Test func itDrawsFromTheLawsSeedWords() throws {
        let stub = try Self.stub(Self.isBlank)
        let law = try Self.test(named: "isBlank_isTotal", in: stub)
        let lines = law.components(separatedBy: "\n")
        let words = ["stateA", "stateB", "stateC", "stateD"].compactMap { word -> String? in
            guard let line = lines.first(where: { $0.contains("\(word): 0x") }) else { return nil }
            let value = line.components(separatedBy: ": ").last ?? ""
            return value.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        }
        #expect(words.count == 4)
        #expect(stub.contains("var rng = Xoshiro(seed: (\(words.joined(separator: ", "))))"))
        #expect(stub.contains("for _ in 0 ..< \(LiftedTestEmitter.stubTrialCount) {"))
    }

    /// An `inout` argument is copied into a `var` and passed with `&`, as the law does, and a
    /// global actor hops once around the copy and the call.
    @Test func aMainActorInoutCallIsTheLawsCall() throws {
        let stub = try Self.stub(Self.suggestion(
            displayName: "trimsLeading(_:)", signature: "(String) -> Bool", carrier: "Layout",
            globalActor: "MainActor", inoutParameterIndices: [0]
        ))
        #expect(stub.contains("_ = Layout.trimsLeading(&inout0)"))
        let hop = "let reachAnswer = await MainActor.run { var inout0 = value; return Layout.trimsLeading(&inout0) }"
        #expect(stub.contains(hop))
    }

    /// A constructed receiver that throws while it is built (`try #require(…)`) is legal inside the law's
    /// `async throws` property closure, and needs a throwing reach test. Commit 5's crosscheck set aside
    /// two SwiftProjectLint stubs whose reach test was plain `async`: "errors thrown from here are not
    /// handled".
    @Test func aThrowingReceiverMakesTheReachTestThrow() {
        let callee = CalleeReference(
            bareName: "isAnimationModifierCall",
            qualifier: "AnimationPerformanceVisitor(pattern: try #require(Pattern.first))",
            isInstanceMethod: false
        )
        let stub = LiftedTestEmitter.reachesBothOutcomes(
            callee: callee, seed: SamplingSeed.Value(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
            generators: ["Gen<Int>.int()"], subjectLabel: "isAnimationModifierCall(_:)"
        )
        #expect(stub.contains("@Test func isAnimationModifierCall_reachesBothOutcomes() async throws {"))
        let plain = LiftedTestEmitter.reachesBothOutcomes(
            callee: CalleeReference(bareName: "isBlank", qualifier: "Text"),
            seed: SamplingSeed.Value(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
            generators: ["Gen<Int>.int()"], subjectLabel: "isBlank(_:)"
        )
        #expect(plain.contains("@Test func isBlank_reachesBothOutcomes() async {"))
    }

    @Test func aPlainCallIsTheLawsCall() throws {
        let stub = try Self.stub(Self.isBlank)
        #expect(stub.contains("_ = Text.isBlank(value); return true"))
        #expect(stub.contains("let reachAnswer = Text.isBlank(value)"))
    }

    /// An actor receiver awaits the call, and only the call: awaiting an `inout` copy of a drawn
    /// value would add a warning the law's call does not need.
    @Test func anActorReceiverAwaitsTheCallAlone() {
        let callee = CalleeReference(
            bareName: "holds", isolation: CalleeReference.actorReceiverIsolation, isInstanceMethod: true
        )
        let call = TotalityCall(callee: callee, drawCount: 2, isThrowing: false, isAsync: false, inoutArguments: [1])
        #expect(LiftedTestEmitter.answerStatements(call, callee: callee)
            == ["var inout1 = args.1", "let reachAnswer = await args.0.holds(&inout1)"])
    }

    // MARK: - What it says, and the shapes the crosscheck removes

    /// `corpus_funnel_stage5.py` sorts a reach warning by `^NOT APPLIED — the (true|false) side: `;
    /// any other first line lands in `reach_other`, an emitter defect under #665 §9.
    @Test func eachNoteNamesItsSideInTheShapeTheHarnessReads() throws {
        let stub = try Self.stub(Self.isBlank)
        for side in [true, false] {
            #expect(stub.contains("if !reachedAnswers.contains(\(side)) {"))
            let first = "NOT APPLIED — the \(side) side: no draw made Text.isBlank(_:) return \(side) in 100 trials "
            #expect(stub.contains("\"\(first)\""))
            let note = NotApplied.reachSide(side, subject: "f(_:)", lawTest: "f_isTotal", trials: 100)
            #expect(note.hasPrefix("NOT APPLIED — the \(side) side: "))
            #expect(note.contains("or delete this test"), "a constant-by-design predicate's right response is named")
        }
    }

    /// The warning is the W form: it never fails the run on Swift 6.3+, and before 6.3, where
    /// Swift Testing has no warning severity, it is a known issue rather than a failure.
    @Test func theHelperWarnsAndNeverFails() throws {
        let stub = try Self.stub(Self.isBlank)
        #expect(stub.contains("Issue.record(\"\\(text)\", severity: .warning)"))
        #expect(stub.contains("withKnownIssue { Issue.record(\"\\(text)\") }"))
        #expect(stub.components(separatedBy: "#if compiler(>=6.3)").count == 2, "the helper holds the only #if")
    }

    /// The header says the file carries a reach test, in the two lines #665 §9 drops: a `// Reach:`
    /// line and one indented line under it, and nothing for a stub without one.
    @Test func theHeaderCarriesTheTwoReachLines() throws {
        let suggestion = Self.isBlank
        let file = InteractiveTriage.wrappedFileContents(stub: try Self.stub(suggestion), suggestion: suggestion)
        let lines = file.components(separatedBy: "\n")
        let start = try #require(lines.firstIndex { $0.hasPrefix("// Reach:") })
        #expect(lines.filter { $0.hasPrefix("// Reach:") }.count == 1)
        // What `strip_reach` drops: the `// Reach:` line, then each indented comment line after it.
        let dropped = lines[(start + 1)...].prefix { $0.hasPrefix("//  ") }
        #expect(dropped.count == 1, "one indented line, and the line after it is not a comment")
        #expect(InteractiveTriage.reachLines(for: "@Test func f_isTotal() async {}").isEmpty)
    }

    /// Only a serialized suite runs the reach test after its law. In parallel the two raced the toy's
    /// stateful `isFirstSighting` and crashed the test process in 10 of 10 runs (#724's amendment A2).
    @Test func aSuiteWithAReachTestIsSerialized() throws {
        let stub = try Self.stub(Self.isBlank)
        let predicate = InteractiveTriage.wrappedFileContents(stub: stub, suggestion: Self.isBlank)
        #expect(predicate.contains("@Suite(.serialized)\nstruct "))
        let totality = Self.suggestion(
            displayName: "parse(_:)", signature: "(String) -> Bool", template: "input-totality", carrier: "Parser"
        )
        let plain = InteractiveTriage.wrappedFileContents(stub: try Self.stub(totality), suggestion: totality)
        #expect(!plain.contains("@Suite"), "a stub without a reach test keeps its bytes")
    }
}
