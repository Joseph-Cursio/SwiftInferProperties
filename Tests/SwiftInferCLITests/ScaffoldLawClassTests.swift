import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// A scaffold's header says it is a to-do, not a law (#466).
///
/// A `replay-idempotence` stub cannot construct its own fixture, so it records an issue on
/// purpose, naming the steps left to complete, and fails until a person completes them. It
/// carried the CONJECTURE line — *"a pass means no counterexample was found in the trials
/// drawn"* — on a file that cannot pass as written. The
/// corpus funnel census found four such stubs, and had to reclassify them by reading their bodies
/// because the header said the opposite of what the file does.
@Suite("Scaffold stubs say they fail by design")
struct ScaffoldLawClassTests {

    private static let suggestion = Suggestion(
        templateName: "replay-idempotence",
        evidence: [
            Evidence(
                displayName: "download(album:idempotencyKey:)",
                signature: "(Album, IdempotencyKey) -> OfflineAlbum",
                location: SourceLocation(file: "OfflineManager.swift", line: 53, column: 5)
            )
        ],
        score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
        generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
        explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
        identity: SuggestionIdentity(canonicalInput: "OfflineManager.swift::download")
    )

    /// Both scaffold emitters, as they really render — not a hand-written string that could
    /// drift from what they produce.
    private static let scaffolds = [
        LiftedTestEmitter.replayIdempotent(
            funcName: "download", keyLabel: "idempotencyKey", ownerType: "OfflineManager",
            isAsync: false, isThrows: true
        ),
        LiftedTestEmitter.replayKeyBuilder(
            funcName: "makeChargeRequest", ownerType: "StripeWebhookHandler", isThrows: false
        )
    ]

    @Test func bothReplayEmittersAreRecognisedAsScaffolds() {
        for stub in Self.scaffolds {
            #expect(InteractiveTriage.isScaffold(stub))
        }
    }

    /// **The control.** A real law — one that can pass — is not a scaffold, including the
    /// determinism and totality arms whose bodies also contain `Issue.record`.
    @Test func aLawThatCanPassIsNotAScaffold() {
        let seed = SamplingSeed.Value(stateA: 1, stateB: 2, stateC: 3, stateD: 4)
        let laws = [
            LiftedTestEmitter.deterministic(
                funcName: "f", parameters: [.init(label: nil, generator: "Gen<Int>.int()")], seed: seed
            ),
            LiftedTestEmitter.total(
                callee: "parse", seed: seed, generator: "Gen<Int>.int()", isThrowing: false, isAsync: false
            )
        ]
        for law in laws {
            #expect(law.contains("Issue.record"), "the control must share the call the detector looks near")
            #expect(InteractiveTriage.isScaffold(law) == false)
        }
    }

    @Test func aScaffoldSaysItFailsByDesign() {
        let line = InteractiveTriage.lawClassLine(for: Self.suggestion, isScaffold: true)
        #expect(line.contains("SCAFFOLD"))
        #expect(line.contains("fails by design"))
        #expect(line.contains("CONJECTURE") == false)
        #expect(line.contains("a pass means") == false)
    }

    /// End to end through the file wrapper: the scaffold's written header is the scaffold line,
    /// and the same suggestion wrapped around a law is not.
    @Test func theWrittenFileCarriesTheScaffoldLine() throws {
        let scaffold = try #require(Self.scaffolds.first)
        let scaffoldFile = InteractiveTriage.wrappedFileContents(stub: scaffold, suggestion: Self.suggestion)
        #expect(scaffoldFile.contains("// Law class: SCAFFOLD"))
        #expect(scaffoldFile.contains("// Law class: CONJECTURE") == false)

        let lawFile = InteractiveTriage.wrappedFileContents(stub: "@Test func f() {}", suggestion: Self.suggestion)
        #expect(lawFile.contains("// Law class: SCAFFOLD") == false)
    }
}
