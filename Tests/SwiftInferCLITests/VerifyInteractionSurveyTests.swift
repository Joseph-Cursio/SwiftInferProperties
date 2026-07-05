import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
import Testing

/// Cycle 114 — fast tests for the `verify-interaction --all` survey: the
/// argument surface, the `--family` filter parse, and the pure summary
/// renderer. The build+run+record end-to-end proof lives in the
/// `.subprocess`-tagged `VerifyInteractionSurveyMeasuredTests`.
@Suite("verify-interaction --all survey — surface + parse + render (cycle 114)")
struct VerifyInteractionSurveyTests {

    // MARK: - Argument surface

    @Test("--all and --family parse alongside --target")
    func argumentParsing() throws {
        let parsed = try SwiftInferCommand.VerifyInteraction.parse([
            "--target", "MyApp",
            "--all",
            "--family", "idempotence"
        ])
        #expect(parsed.target == ["MyApp"])
        #expect(parsed.all == true)
        #expect(parsed.family == "idempotence")
    }

    @Test("--target is repeatable (M3 multi-module survey)")
    func repeatableTarget() throws {
        let parsed = try SwiftInferCommand.VerifyInteraction.parse([
            "--target", "Alpha", "--target", "Beta", "--all"
        ])
        #expect(parsed.target == ["Alpha", "Beta"])
    }

    @Test("--all defaults off; --family defaults nil")
    func defaultsOff() throws {
        let parsed = try SwiftInferCommand.VerifyInteraction.parse(["--target", "MyApp"])
        #expect(parsed.all == false)
        #expect(parsed.family == nil)
    }

    // MARK: - parseFamily

    @Test("parseFamily maps known raw values, passes nil through")
    func parseFamilyKnown() throws {
        #expect(try VerifyInteractionSurvey.parseFamily(nil) == nil)
        #expect(try VerifyInteractionSurvey.parseFamily("idempotence") == .idempotence)
        #expect(try VerifyInteractionSurvey.parseFamily("referential-integrity") == .referentialIntegrity)
    }

    @Test("parseFamily rejects an unknown family")
    func parseFamilyUnknown() {
        #expect(throws: VerifyInteractionSurvey.SurveyError.unknownFamily(raw: "bogus")) {
            _ = try VerifyInteractionSurvey.parseFamily("bogus")
        }
    }

    // MARK: - render (pure)

    @Test("render lists each identity, a count-by-outcome tally, and the evidence line")
    func renderSummary() {
        let entries = [
            entry(predicate: ".refresh", reducer: "CounterReducer.reduce", outcome: .measuredBothPass),
            entry(
                predicate: ".reset",
                reducer: "SettingsReducer.reduce",
                outcome: .measuredDefaultFails,
                detail: "at sequence index 3"
            )
        ]
        let rendered = VerifyInteractionSurvey.render(target: "MyApp", family: .idempotence, entries: entries)

        #expect(rendered.contains("Identities: 2 (--family idempotence)"))
        #expect(rendered.contains("[measured-bothPass]"))
        #expect(rendered.contains("CounterReducer.reduce"))
        #expect(rendered.contains("[measured-defaultFails]"))
        #expect(rendered.contains("— at sequence index 3"))
        // Tally in canonical outcome order, only non-zero outcomes.
        #expect(rendered.contains("Summary: 1 measured-bothPass, 1 measured-defaultFails"))
        #expect(rendered.contains("Evidence recorded to .swiftinfer/verify-evidence.json (2 identities)."))
    }

    @Test("render emits a sentinel for an empty survey")
    func renderEmpty() {
        let rendered = VerifyInteractionSurvey.render(target: "MyApp", family: .idempotence, entries: [])
        #expect(rendered.contains("0 interaction-invariant identities (--family idempotence) — nothing to verify."))
    }

    // MARK: - Helpers

    private func entry(
        predicate: String,
        reducer: String,
        outcome: VerifyEvidenceOutcome,
        detail: String? = nil
    ) -> VerifyInteractionSurvey.Entry {
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: .idempotence,
            reducerQualifiedName: reducer,
            predicate: predicate
        )
        let suggestion = InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: .idempotence,
            reducerQualifiedName: reducer,
            reducerLocation: "Sources/MyApp/\(reducer).swift:1",
            stateTypeName: "S",
            actionTypeName: "A",
            predicate: predicate,
            score: 40,
            tier: .likely,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: ISO8601DateFormatter().date(from: "2026-05-15T10:00:00Z")!
        )
        return VerifyInteractionSurvey.Entry(
            suggestion: suggestion,
            result: InteractionVerifyOutcomeParser.Result(outcome: outcome, detail: detail)
        )
    }
}
