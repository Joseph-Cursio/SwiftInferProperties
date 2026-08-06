import Foundation
import SwiftEffectInference
@testable import SwiftInferCore
import Testing

/// Effects a linter resolved, arriving through the seed manifest.
///
/// This closes a loop the two repositories had been describing to each other in
/// prose: `IdempotenceTemplate+DeclaredEffect` recorded that SwiftProjectLint
/// resolves effects cross-file and multi-hop while none of it crossed into
/// `.pbt/seeds.json`, and the producer now emits it. What arrives is strictly
/// better sourced than what `EffectResolver` can compute locally — that pass
/// runs one hop, against a budget it must fit inside §13's — but it is not
/// uniformly trustworthy, and most of these tests are about the difference.
@Suite("Seed effect resolver — linter-resolved effects as evidence")
struct SeedEffectResolverTests {

    // MARK: - Helpers

    private func summary(
        name: String,
        declaredEffect: Effect? = nil
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [],
            returnTypeText: "Void",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Orders.swift", line: 11, column: 1),
            containingTypeName: nil,
            bodySignals: BodySignals(
                hasNonDeterministicCall: false,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: []
            ),
            declaredEffect: declaredEffect
        )
    }

    private func manifest(
        symbol: String = "confirmOrder",
        effect: SeedEffect?
    ) -> SeedManifest {
        SeedManifest(seeds: [
            SeedManifest.Seed(
                file: "Orders.swift", line: 11, symbol: symbol,
                rule: "Idempotency Violation", kind: .idempotency, effect: effect
            )
        ])
    }

    private func declaredEffect(
        resolved: SeedEffect.Tier = .nonIdempotent
    ) -> SeedEffect {
        SeedEffect(declared: .idempotent, resolved: resolved, provenance: .declared)
    }

    // MARK: - What it applies

    @Test("a declared-provenance effect reaches the summary")
    func declaredProvenanceApplies() {
        let result = SeedEffectResolver.resolve(
            summaries: [summary(name: "confirmOrder")],
            manifest: manifest(effect: declaredEffect())
        )
        #expect(result.first?.inferredEffect == .nonIdempotent)
    }

    /// Written to `inferredEffect`, never `declaredEffect`. The manifest's
    /// `resolved` is a statement about what a body *reaches* — the same claim
    /// `EffectResolver` makes, sourced better. Promoting it to a declaration
    /// would make `IdempotenceTemplate` veto where it should demote, turning a
    /// stronger source into a stronger verdict, which does not follow.
    @Test("it lands as an inference, not as the function's own claim")
    func landsAsInference() {
        let result = SeedEffectResolver.resolve(
            summaries: [summary(name: "confirmOrder")],
            manifest: manifest(effect: declaredEffect())
        )
        #expect(result.first?.inferredEffect == .nonIdempotent)
        #expect(result.first?.declaredEffect == nil)
    }

    @Test("externally-idempotent carries upward too")
    func externallyIdempotentApplies() {
        let result = SeedEffectResolver.resolve(
            summaries: [summary(name: "confirmOrder")],
            manifest: manifest(effect: declaredEffect(resolved: .externallyIdempotent))
        )
        #expect(result.first?.inferredEffect == .externallyIdempotent(keyParameter: nil))
    }

    // MARK: - What it refuses, and why

    /// `EffectResolver` disables the heuristic classifier on purpose, because it
    /// *"guesses effects for unannotated callees from their NAMES … and a veto
    /// built on a name guess would suppress a true law because a callee was
    /// called `save`."* Accepting a name guess from a JSON file would be the
    /// same mistake wearing a different hat.
    @Test("a name-heuristic effect is not acted on")
    func heuristicProvenanceWithheld() {
        let effect = SeedEffect(
            declared: .idempotent, resolved: .nonIdempotent,
            provenance: .inferredDownward, reason: "from the callee name `save`"
        )
        let result = SeedEffectResolver.resolve(
            summaries: [summary(name: "confirmOrder")], manifest: manifest(effect: effect)
        )
        #expect(result.first?.inferredEffect == nil)
    }

    /// **The case this whole three-repository chain was built for.** A
    /// `@NonIdempotent` several calls down, resolved to a fixed point across
    /// every file by a producer with no §13 budget to respect — reach that
    /// `EffectResolver` is structurally incapable of, since it runs one hop.
    ///
    /// It was refused wholesale until the anchor existed, which cost exactly
    /// this.
    @Test("an upward chain anchored in an annotation is acted on")
    func declarationAnchoredUpwardIsActedOn() {
        let effect = SeedEffect(
            declared: .idempotent, resolved: .nonIdempotent,
            provenance: .inferredUpward, depth: 3, anchor: .declaration
        )
        let result = SeedEffectResolver.resolve(
            summaries: [summary(name: "confirmOrder")], manifest: manifest(effect: effect)
        )
        #expect(result.first?.inferredEffect == .nonIdempotent)
    }

    /// The same shape, same tier, same distance — refused, because the bottom of
    /// the chain is a name match. `EffectResolver` disables its own heuristic
    /// classifier for this reason, and a guess laundered through three hops and
    /// a JSON file is still a guess.
    @Test("an upward chain bottoming out on a guess is not acted on")
    func guessAnchoredUpwardWithheld() {
        let effect = SeedEffect(
            declared: .idempotent, resolved: .nonIdempotent,
            provenance: .inferredUpward, depth: 3, anchor: .heuristic
        )
        let result = SeedEffectResolver.resolve(
            summaries: [summary(name: "confirmOrder")], manifest: manifest(effect: effect)
        )
        #expect(result.first?.inferredEffect == nil)
    }

    /// A producer predating the field sends an upward tier with no anchor. That
    /// must read as "not established", not as "fine" — the same answer this tool
    /// gave before the field existed, so an older linter cannot silently gain
    /// trust it never earned.
    @Test("an upward effect with no anchor is withheld")
    func anchorlessUpwardWithheld() {
        let effect = SeedEffect(
            declared: .idempotent, resolved: .nonIdempotent,
            provenance: .inferredUpward, depth: 3
        )
        let result = SeedEffectResolver.resolve(
            summaries: [summary(name: "confirmOrder")], manifest: manifest(effect: effect)
        )
        #expect(result.first?.inferredEffect == nil)
    }

    /// An anchor cannot rescue a name heuristic. The provenance settles it
    /// before the anchor is consulted, and a producer that emitted one here
    /// would be contradicting itself.
    @Test("a declaration anchor does not rescue a name heuristic")
    func anchorDoesNotRescueDownward() {
        let effect = SeedEffect(
            declared: .idempotent, resolved: .nonIdempotent,
            provenance: .inferredDownward, anchor: .declaration
        )
        let result = SeedEffectResolver.resolve(
            summaries: [summary(name: "confirmOrder")], manifest: manifest(effect: effect)
        )
        #expect(result.first?.inferredEffect == nil)
    }

    /// Refusing silently would look identical to a producer that emitted
    /// nothing — the confident-zero shape this pipeline keeps rediscovering. The
    /// reader must be able to tell "the linter said nothing" from "the linter
    /// said something I will not score."
    @Test("withheld effects are reported, not dropped in silence")
    func withheldEffectsAreReported() {
        var lines: [String] = []
        _ = SeedEffectResolver.resolve(
            summaries: [summary(name: "confirmOrder")],
            manifest: manifest(effect: SeedEffect(
                declared: .idempotent, resolved: .nonIdempotent,
                provenance: .inferredUpward, anchor: .heuristic
            )),
            diagnostic: { lines.append($0) }
        )
        #expect(lines.contains { $0.contains("withheld") && $0.contains("inferred-upward") })
    }

    /// **The case the whole feature exists for, and the one the first draft
    /// could not reach.** Every `idempotency` seed names an annotated function —
    /// an unannotated one cannot violate a claim it never made — so a resolver
    /// that skipped summaries with a declared effect would apply to nothing at
    /// all. That draft shipped past unit tests and was caught only by running a
    /// real manifest end to end.
    ///
    /// Both signals must survive: the annotation is real evidence, and so is the
    /// call graph that contradicts it.
    @Test("a declared claim and its refutation are both kept")
    func declarationAndRefutationCoexist() {
        let result = SeedEffectResolver.resolve(
            summaries: [summary(name: "confirmOrder", declaredEffect: .idempotent)],
            manifest: manifest(effect: declaredEffect())
        )
        #expect(result.first?.declaredEffect == .idempotent)
        #expect(result.first?.inferredEffect == .nonIdempotent)
    }

    /// An inferred `pure` / `idempotent` means only "nothing this calls is worse
    /// than that", which does not make the caller idempotent. `EffectResolver`
    /// discards those rather than manufacture corroboration out of an absence,
    /// and a better-sourced absence is still an absence.
    @Test("a retry-safe tier carries no information upward")
    func retrySafeTierIsDiscarded() {
        for tier in [SeedEffect.Tier.pure, .idempotent, .observational] {
            let result = SeedEffectResolver.resolve(
                summaries: [summary(name: "confirmOrder")],
                manifest: manifest(effect: declaredEffect(resolved: tier))
            )
            #expect(result.first?.inferredEffect == nil, "\(tier) should not propagate")
        }
    }

    // MARK: - Shape

    @Test("a manifest with no effects leaves every summary untouched")
    func noEffectsIsANoOp() {
        let result = SeedEffectResolver.resolve(
            summaries: [summary(name: "confirmOrder")], manifest: manifest(effect: nil)
        )
        #expect(result.first?.inferredEffect == nil)
    }

    @Test("summaries a manifest does not name are untouched")
    func unnamedSummariesUntouched() {
        let result = SeedEffectResolver.resolve(
            summaries: [summary(name: "somethingElse")],
            manifest: manifest(effect: declaredEffect())
        )
        #expect(result.first?.inferredEffect == nil)
    }

    @Test("input order is preserved")
    func orderPreserved() {
        let result = SeedEffectResolver.resolve(
            summaries: [summary(name: "a"), summary(name: "confirmOrder"), summary(name: "b")],
            manifest: manifest(effect: declaredEffect())
        )
        #expect(result.map(\.name) == ["a", "confirmOrder", "b"])
    }
}
