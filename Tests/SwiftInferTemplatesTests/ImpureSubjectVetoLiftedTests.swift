import Foundation
import SwiftEffectInference
import Testing

@testable import SwiftInferCore
@testable import SwiftInferTemplates

/// **The veto for lifted suggestions — by callee name, and unanimous.**
///
/// TestLifter's promoted suggestions join after `TemplateRegistry.discover`, so they never met
/// `applyImpureSubjectVeto`, and their evidence sits at the test assertion they were lifted from,
/// so a location-keyed veto could not match them anyway. ``locationVetoCannotSeeALiftedRow()``
/// pins that gap; the rest pin the callee-name veto that closes it, and the namesake rule that
/// keeps it from vetoing a pure function's law.
@Suite("Veto — a lifted law is withheld when every function of its callee's name is impure")
struct ImpureSubjectVetoLiftedTests {

    /// A lifted row: the callee named, the location a test file's assertion.
    static func lifted(callee: String, template: String = "idempotence") -> Suggestion {
        Suggestion(
            templateName: template,
            evidence: [
                Evidence(
                    displayName: "\(callee)(_:)",
                    signature: "(String) -> String",
                    location: SourceLocation(file: "Tests/FTests.swift", line: 12, column: 9)
                ),
            ],
            score: Score(signals: [Signal(kind: .predicateSignature, weight: 30, detail: "lifted")]),
            generator: GeneratorMetadata(source: .derivedComposite, confidence: .high, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: ["lifted (+30)"], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "\(template)::\(callee)")
        )
    }

    private static func impure(_ name: String, line: Int) -> FunctionSummary {
        ImpureSubjectVetoTests.summary(name: name, line: line, verdict: .refuted)
    }

    private static func pure(_ name: String, line: Int) -> FunctionSummary {
        ImpureSubjectVetoTests.summary(name: name, line: line, verdict: .pure)
    }

    @Test("the location-keyed veto cannot see a lifted row: its location is the test's")
    func locationVetoCannotSeeALiftedRow() {
        let row = Self.lifted(callee: "open")
        let result = TemplateRegistry.applyImpureSubjectVeto(to: [row], summaries: [Self.impure("open", line: 40)])
        #expect(result[0].score.tier != .suppressed)
    }

    @Test("a lifted row whose only callee namesake is impure with a witness is vetoed, with its reason")
    func liftedRowOnAnImpureCalleeIsVetoed() throws {
        let result = TemplateRegistry.applyImpureSubjectVetoByCallee(
            to: [Self.lifted(callee: "open")],
            summaries: [Self.impure("open", line: 40)]
        )
        #expect(result[0].score.tier == .suppressed)
        let reason = try #require(result[0].explainability.whyMightBeWrong.last)
        #expect(reason.contains("impure with a witness (open)"))
    }

    @Test("every namesake impure: still vetoed, and the reason names the function once")
    func impureNamesakesAreNamedOnce() throws {
        let result = TemplateRegistry.applyImpureSubjectVetoByCallee(
            to: [Self.lifted(callee: "open")],
            summaries: [Self.impure("open", line: 40), Self.impure("open", line: 90)]
        )
        #expect(result[0].score.tier == .suppressed)
        let reason = try #require(result[0].explainability.whyMightBeWrong.last)
        #expect(reason.contains("(open)"))
    }

    @Test("a pure namesake keeps the lifted row: the test may have meant it")
    func pureNamesakeKeepsTheRow() {
        let row = Self.lifted(callee: "open")
        let result = TemplateRegistry.applyImpureSubjectVetoByCallee(
            to: [row],
            summaries: [Self.impure("open", line: 40), Self.pure("open", line: 90)]
        )
        #expect(result == [row])
    }

    @Test("control: a callee with no production function of its name is left alone")
    func unknownCalleeIsLeftAlone() {
        let row = Self.lifted(callee: "helperOnlyInTests")
        let result = TemplateRegistry.applyImpureSubjectVetoByCallee(
            to: [row], summaries: [Self.impure("open", line: 40)]
        )
        #expect(result == [row])
    }

    @Test("control: an unanalysed namesake is not evidence, whatever its defaulted verdict")
    func unanalysedNamesakeIsNotEvidence() {
        let row = Self.lifted(callee: "open")
        let unanalysed = ImpureSubjectVetoTests.summary(name: "open", line: 40, verdict: .refuted, analysed: false)
        let result = TemplateRegistry.applyImpureSubjectVetoByCallee(to: [row], summaries: [unanalysed])
        #expect(result == [row])
    }

    @Test("a round trip with one impure callee is vetoed, and only that callee is named")
    func roundTripWithOneImpureCalleeIsVetoed() throws {
        let rows = [("encode", 12), ("decode", 13)].map { name, line in
            Evidence(
                displayName: "\(name)(_:)",
                signature: "(Value) -> Data",
                location: SourceLocation(file: "Tests/CodecTests.swift", line: line, column: 9)
            )
        }
        var roundTrip = Self.lifted(callee: "encode", template: "round-trip")
        roundTrip.evidence = rows
        let result = TemplateRegistry.applyImpureSubjectVetoByCallee(
            to: [roundTrip],
            summaries: [Self.impure("encode", line: 40), Self.pure("decode", line: 60)]
        )
        #expect(result[0].score.tier == .suppressed)
        let reason = try #require(result[0].explainability.whyMightBeWrong.last)
        #expect(reason.contains("(encode)"))
    }

    @Test("a corpus-wide advisory names its callee and is vetoed the same way")
    func corpusAnchoredAdvisoryIsVetoed() {
        var chain = Self.lifted(callee: "matchGlobs", template: "consumer-producer-chain")
        chain.evidence = [
            Evidence(
                displayName: "matchGlobs(_:)",
                signature: "([Glob]) -> ?",
                location: SourceLocation(file: "<corpus>", line: 0, column: 0)
            ),
        ]
        let result = TemplateRegistry.applyImpureSubjectVetoByCallee(
            to: [chain],
            summaries: [Self.impure("matchGlobs", line: 225)]
        )
        #expect(result[0].score.tier == .suppressed)
    }

    @Test("an operator callee is its whole spelling: `..<` is never matched to `<`")
    func operatorCalleeIsNotSplitOnItsDots() {
        let row = Self.lifted(callee: "..<", template: "commutativity")
        let result = TemplateRegistry.applyImpureSubjectVetoByCallee(to: [row], summaries: [Self.impure("<", line: 40)])
        #expect(result == [row])
    }

    @Test("a qualified callee spelling resolves to its last component")
    func qualifiedCalleeResolves() {
        let result = TemplateRegistry.applyImpureSubjectVetoByCallee(
            to: [Self.lifted(callee: "Launcher.open")],
            summaries: [Self.impure("open", line: 40)]
        )
        #expect(result[0].score.tier == .suppressed)
    }
}
