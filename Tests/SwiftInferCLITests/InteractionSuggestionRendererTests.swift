import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// V2.0 M4.E — InteractionSuggestionRenderer tests. Pure: take a
// hand-built suggestion list, assert on the rendered string shape.

@Suite("InteractionSuggestionRenderer — V2.0 M4.E tiered output rendering")
struct InteractionSuggestionRendererTests {

    private let firstSeenAt = ISO8601DateFormatter().date(from: "2026-05-15T10:00:00Z")!

    private func suggestion(
        family: InteractionInvariantFamily = .conservation,
        reducerQualifiedName: String = "Inbox.body",
        predicate: String = "state.count == state.items.count",
        score: Int = 30,
        tier: Tier = .possible,
        whySuggested: [String] = ["structural witness fired"],
        whyMightBeWrong: [String] = ["calibration pending"]
    ) -> InteractionInvariantSuggestion {
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: family,
            reducerQualifiedName: reducerQualifiedName,
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: family,
            reducerQualifiedName: reducerQualifiedName,
            reducerLocation: "Sources/MyApp/F.swift:1",
            stateTypeName: "Inbox.State",
            actionTypeName: "Inbox.Action",
            predicate: predicate,
            score: score,
            tier: tier,
            whySuggested: whySuggested,
            whyMightBeWrong: whyMightBeWrong,
            firstSeenAt: firstSeenAt
        )
    }

    // MARK: - Empty / sentinel paths

    @Test("empty list returns the 0-suggestions sentinel")
    func renderEmpty() {
        let rendered = InteractionSuggestionRenderer.render([], includePossible: false)
        #expect(rendered == "0 interaction-invariant suggestions.")
    }

    @Test("all-.possible suggestions hidden without --include-possible — calibration-aware sentinel")
    func renderAllPossibleHidden() {
        let rendered = InteractionSuggestionRenderer.render(
            [suggestion(), suggestion(predicate: "state.count == state.tags.count")],
            includePossible: false
        )
        #expect(rendered.contains("0 interaction-invariant suggestions shown"))
        #expect(rendered.contains("2 at .possible tier hidden"))
        #expect(rendered.contains("--include-possible"))
    }

    @Test("all-.possible suggestions visible with --include-possible")
    func renderAllPossibleVisible() {
        let rendered = InteractionSuggestionRenderer.render(
            [suggestion()],
            includePossible: true
        )
        #expect(rendered.contains("1 interaction-invariant suggestion."))
        #expect(rendered.contains("[Interaction-Invariant Suggestion]"))
    }

    // MARK: - Suggestion-block shape

    @Test("rendered block carries family / score / reducer / state / action / predicate")
    func renderBlockFields() {
        let target = suggestion()
        let rendered = InteractionSuggestionRenderer.render(target)
        #expect(rendered.contains("Family:    conservation"))
        #expect(rendered.contains("Score:     30 (Possible)"))
        #expect(rendered.contains("Reducer:   Inbox.body"))
        #expect(rendered.contains("Location:  Sources/MyApp/F.swift:1"))
        #expect(rendered.contains("State:     Inbox.State"))
        #expect(rendered.contains("Action:    Inbox.Action"))
        #expect(rendered.contains("Predicate: state.count == state.items.count"))
    }

    @Test("rendered block lists why-suggested as ✓ bullets")
    func renderWhySuggestedBullets() {
        let target = suggestion(whySuggested: ["aggregate + collection witness", "reducer-shaped signature"])
        let rendered = InteractionSuggestionRenderer.render(target)
        #expect(rendered.contains("Why suggested:"))
        #expect(rendered.contains("  ✓ aggregate + collection witness"))
        #expect(rendered.contains("  ✓ reducer-shaped signature"))
    }

    @Test("rendered block lists why-might-be-wrong as ⚠ bullets")
    func renderWhyMightBeWrongBullets() {
        let target = suggestion(whyMightBeWrong: ["structural detection only", "initial-state caveat"])
        let rendered = InteractionSuggestionRenderer.render(target)
        #expect(rendered.contains("Why this might be wrong:"))
        #expect(rendered.contains("  ⚠ structural detection only"))
        #expect(rendered.contains("  ⚠ initial-state caveat"))
    }

    @Test("rendered block exposes the suggestion's identity-hash display form")
    func renderIdentityHash() {
        let target = suggestion()
        let rendered = InteractionSuggestionRenderer.render(target)
        #expect(rendered.contains("Identity:  0x"))
    }

    // MARK: - Tier filtering

    @Test("filter keeps .verified / .strong / .likely / .advisory unconditionally")
    func filterAlwaysVisibleTiers() {
        let always = [Tier.verified, .strong, .likely, .advisory].map { tier in
            suggestion(score: 80, tier: tier)
        }
        let kept = InteractionSuggestionRenderer.filter(always, includePossible: false)
        #expect(kept.count == 4)
    }

    @Test("filter drops .possible without flag; keeps .possible with flag")
    func filterPossibleObeysFlag() {
        let target = [suggestion(tier: .possible)]
        // `InteractionSuggestionRenderer.filter` is a domain method, not
        // `Sequence.filter` — bind its result before asserting so the
        // contains_over_filter_is_empty rule doesn't false-positive.
        let withoutFlag = InteractionSuggestionRenderer.filter(target, includePossible: false)
        let withFlag = InteractionSuggestionRenderer.filter(target, includePossible: true)
        #expect(withoutFlag.isEmpty)
        #expect(withFlag.count == 1)
    }

    @Test("filter always drops .suppressed regardless of flag")
    func filterSuppressedAlwaysHidden() {
        let target = [suggestion(score: 5, tier: .suppressed)]
        // Domain method, not `Sequence.filter` — see filterPossibleObeysFlag.
        let withoutFlag = InteractionSuggestionRenderer.filter(target, includePossible: false)
        let withFlag = InteractionSuggestionRenderer.filter(target, includePossible: true)
        #expect(withoutFlag.isEmpty)
        #expect(withFlag.isEmpty)
    }

    // MARK: - Multi-suggestion ordering

    @Test("multi-suggestion render preserves input order (engine sort honored)")
    func renderPreservesInputOrder() {
        let rendered = InteractionSuggestionRenderer.render(
            [
                suggestion(family: .conservation, predicate: "state.count == state.items.count"),
                suggestion(family: .idempotence, predicate: ".refresh")
            ],
            includePossible: true
        )
        let conservationIdx = rendered.range(of: "conservation")!.lowerBound
        let idempotenceIdx = rendered.range(of: "idempotence")!.lowerBound
        #expect(conservationIdx < idempotenceIdx)
    }
}
