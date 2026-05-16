import Foundation
import Testing
@testable import SwiftInferCLI
@testable import SwiftInferCore

/// V1.67 — `collectVisibleSuggestions` folds verify evidence into the
/// grade *before* the visibility cut, so a `bothPass` outcome can lift a
/// sub-threshold pick into view and a `defaultFails` veto drops one.
///
/// The fixture function `wrangle(_:Int) -> Int` produces two `.possible`
/// picks — an `idempotence` pick (`typeSymmetrySignature` +30) and a
/// `monotonicity` pick (`orderedCodomainSignature` +25). The tests
/// target the `idempotence` pick by template name; the `monotonicity`
/// pick is the natural control for "untouched picks are unaffected."
@Suite("Discover pipeline — V1.67 verify-evidence scoring before the visibility cut")
struct DiscoverPipelineVerifyEvidenceTests {

    private let possibleTierSource = "public func wrangle(_ value: Int) -> Int { value &+ 1 }\n"

    private func collect(
        _ directory: URL,
        includePossible: Bool? = nil,
        evidence: [String: VerifyEvidence] = [:]
    ) throws -> [Suggestion] {
        try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory,
            includePossible: includePossible,
            verifyEvidenceByIdentity: evidence,
            diagnostics: DPRecordingDiagnosticOutput()
        ).suggestions
    }

    private func evidenceMap(
        _ suggestion: Suggestion,
        _ outcome: VerifyEvidenceOutcome,
        detail: String?
    ) -> [String: VerifyEvidence] {
        [
            suggestion.identity.normalized: VerifyEvidence(
                identityHash: suggestion.identity.normalized,
                template: suggestion.templateName,
                outcome: outcome,
                detail: detail,
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                swiftInferVersion: "1.67.0"
            )
        ]
    }

    @Test("both .possible picks are hidden by default with no evidence")
    func possiblePicksHiddenByDefault() throws {
        let directory = try writeDPFixture(name: "V167-control", contents: possibleTierSource)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(try collect(directory).isEmpty)
    }

    @Test("--include-possible surfaces the idempotence pick at .possible tier")
    func includePossibleSurfacesIdempotencePick() throws {
        let directory = try writeDPFixture(name: "V167-possible", contents: possibleTierSource)
        defer { try? FileManager.default.removeItem(at: directory) }
        let idempotence = try collect(directory, includePossible: true)
            .first { $0.templateName == "idempotence" }
        #expect(idempotence != nil)
        #expect(idempotence?.score.tier == .possible)
        #expect(idempotence?.score.total == 30)
    }

    @Test("bothPass evidence lifts the idempotence pick past the default visibility cut")
    func bothPassRescuesSubThresholdPick() throws {
        let directory = try writeDPFixture(name: "V167-rescue", contents: possibleTierSource)
        defer { try? FileManager.default.removeItem(at: directory) }

        let idempotence = try #require(
            try collect(directory, includePossible: true)
                .first { $0.templateName == "idempotence" }
        )
        // No --include-possible: the .possible pick would normally be
        // filtered — bothPass grades it +50 before the cut → .strong.
        let rescued = try collect(
            directory,
            evidence: evidenceMap(
                idempotence,
                .measuredBothPass,
                detail: "defaultTrials=100 edgeTrials=100 edgeSampled=6"
            )
        )
        let lifted = rescued.first { $0.identity.normalized == idempotence.identity.normalized }
        #expect(lifted != nil)
        #expect(lifted?.score.tier == .strong)
        #expect(lifted?.score.total == 30 + VerifyEvidenceScoring.verifyBothPassWeight)
        // The untouched monotonicity pick stays .possible — still hidden.
        #expect(!rescued.contains { $0.templateName == "monotonicity" })
    }

    @Test("defaultFails evidence vetoes the pick — absent even with --include-possible")
    func defaultFailsVetoesEvenWithIncludePossible() throws {
        let directory = try writeDPFixture(name: "V167-veto", contents: possibleTierSource)
        defer { try? FileManager.default.removeItem(at: directory) }

        let idempotence = try #require(
            try collect(directory, includePossible: true)
                .first { $0.templateName == "idempotence" }
        )
        let vetoed = try collect(
            directory,
            includePossible: true,
            evidence: evidenceMap(idempotence, .measuredDefaultFails, detail: "trial=4")
        )
        // The idempotence pick is vetoed → .suppressed → never shown,
        // even with --include-possible. The monotonicity pick is
        // untouched and still present.
        #expect(!vetoed.contains { $0.identity.normalized == idempotence.identity.normalized })
        #expect(vetoed.contains { $0.templateName == "monotonicity" })
    }

    @Test("an empty evidence map leaves the pipeline result unchanged")
    func emptyEvidenceMapIsANoOp() throws {
        let directory = try writeDPFixture(name: "V167-noop", contents: possibleTierSource)
        defer { try? FileManager.default.removeItem(at: directory) }
        let withDefault = try collect(directory, includePossible: true)
        let withEmptyMap = try collect(directory, includePossible: true, evidence: [:])
        #expect(withDefault == withEmptyMap)
    }
}
