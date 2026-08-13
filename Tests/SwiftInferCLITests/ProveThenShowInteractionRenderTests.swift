import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// V1.148 — prove-then-show over the interaction surface: classify the
/// interaction survey's `Entry`s into the same buckets.
@Suite("ProveThenShow interaction — V1.148 render")
struct ProveThenShowInteractionRenderTests {

    private func entry(
        _ family: InteractionInvariantFamily,
        _ reducer: String,
        _ outcome: VerifyEvidenceOutcome,
        detail: String? = nil,
        failingIndex: Int? = nil
    ) -> VerifyInteractionSurvey.Entry {
        let suggestion = InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: "\(family.rawValue)::\(reducer)"),
            family: family,
            reducerQualifiedName: reducer,
            reducerLocation: "/x.swift:1",
            stateTypeName: "State",
            actionTypeName: "Action",
            predicate: "p",
            score: 40,
            tier: .likely,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: Date(timeIntervalSince1970: 1_770_000_000)
        )
        return VerifyInteractionSurvey.Entry(
            suggestion: suggestion,
            result: InteractionVerifyOutcomeParser.Result(
                outcome: outcome, detail: detail, failingSequenceIndex: failingIndex
            )
        )
    }

    @Test("V1.148 — empty → interaction-specific guidance")
    func emptyEntries() {
        let out = ProveThenShowRenderer.render(interactionEntries: [])
        #expect(out.contains("No interaction identities"))
        #expect(out.contains("discover-interaction"))
    }

    @Test("V1.148 — the buckets classify interaction outcomes, labelled by family + reducer")
    func fourBuckets() {
        let entries = [
            entry(.idempotence, "NavFeature.reduce", .measuredBothPass),
            entry(.cardinality, "RouterFeature.reduce", .measuredDefaultFails, failingIndex: 3),
            entry(
                .referentialIntegrity, "LibFeature.reduce", .architecturalCoveragePending,
                detail: "non-Identifiable element"
            ),
            entry(.conservation, "CartFeature.reduce", .measuredError, detail: "build-failed")
        ]
        let out = ProveThenShowRenderer.render(interactionEntries: entries)
        #expect(out.contains("Prove-then-show — 4 pick(s) tested"))
        // Expected-to-hold is 0 here because these fixture rows carry no
        // invariant-check attribution, not because the surface is excluded — the
        // interaction fold is built (scope note §13).
        #expect(out.contains(
            "Proven 1 · Expected-to-hold 0 · Disproven 1 · Unverifiable 1 · Inconclusive 1"
        ))
        #expect(out.contains("✓ idempotence  NavFeature.reduce"))
        #expect(out.contains("✗ cardinality  RouterFeature.reduce   [counterexample: failing action-sequence #3]"))
        #expect(out.contains("? referential-integrity  LibFeature.reduce   (non-Identifiable element)"))
        #expect(out.contains("· conservation  CartFeature.reduce   (build-failed)"))
        // **Was `#expect(out.contains("static func gen()"))`, and this fixture is the clearest
        // case for why that was wrong.** The Unverifiable row here declines with
        // `(non-Identifiable element)` — a shape problem, not a missing generator — and the
        // old renderer answered it with "add a `static func gen()`", which would not have
        // moved it. The cause is unrecognised by the classifier, so it is now reported as
        // unrecognised and no remedy is claimed.
        #expect(out.contains("Unverifiable by cause: unrecognised 1"))
        #expect(!out.contains("static func gen()"))
    }

    @Test("V1.150 — no cause breakdown at all when nothing is Unverifiable")
    func noHintWithoutUnverifiable() {
        let out = ProveThenShowRenderer.render(interactionEntries: [
            entry(.idempotence, "NavFeature.reduce", .measuredBothPass)
        ])
        #expect(!out.contains("static func gen()"))
        // Strengthened alongside the 2026-08-13 rewrite: asserting only the absence of the
        // `gen()` string would now pass for the wrong reason, since that string is absent for
        // most Unverifiable causes too. The claim is that the whole section is absent.
        #expect(!out.contains("Unverifiable by cause"))
    }
}
