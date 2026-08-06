import Foundation
import SwiftEffectInference

/// Applies effects a linter resolved to the summaries this tool scored.
///
/// The sibling of `EffectResolver`, and the division of labour is the point.
/// `EffectResolver` re-parses the corpus and walks bodies itself, which costs a
/// second pass and is therefore opt-in behind a flag. This does the same job for
/// free when a seed manifest is present, because the linter already paid.
///
/// **What it adds that the local pass cannot.** `EffectResolver` runs
/// `applyBodyInference(multiHop: false)` — one hop — against a 30-second budget
/// it must fit inside §13's 2-second discover budget. A linter running ahead of
/// the pipeline has no such constraint and resolves to a fixed point across
/// every file. So a `@NonIdempotent` three calls down, which the local pass
/// structurally cannot see, arrives here already resolved.
///
/// **What it acts on.** A declared callee, and — since the producer began
/// emitting `anchor` — an upward chain that bottoms out on one. A
/// name-heuristic effect never. See `SeedEffect.carriesEnoughEvidenceToDemote`.
///
/// The upward case is the one this exists for. It was refused wholesale at
/// first, because the producer's chains admit name-guessed anchors and
/// `provenance` describes only the final hop — and that refusal cost the
/// multi-hop reach entirely, which was most of the value on offer. With the
/// anchor tracked end to end through `BodyEffectInferrer`, the two are
/// distinguishable, and the precision stance now costs only the chains that
/// actually rest on a guess.
public enum SeedEffectResolver {

    /// Fills `inferredEffect` from the manifest on every summary a seed names.
    /// Returns the summaries in input order.
    ///
    /// Written into `inferredEffect` rather than `declaredEffect` because that
    /// is what the manifest's `resolved` field *is*: a statement about what a
    /// body reaches, not about what its author wrote on it. It is the same claim
    /// `EffectResolver` makes, sourced better. Putting it in `declaredEffect`
    /// would promote a callee's annotation into a claim by the caller, and
    /// `IdempotenceTemplate` would then veto rather than demote — turning a
    /// stronger *source* into a stronger *verdict*, which does not follow.
    ///
    /// **Unlike `EffectResolver`, this fills `inferredEffect` even when the
    /// function declares its own effect — and that case is the entire point.**
    ///
    /// The first draft guarded on `declaredEffect == nil`, copying the local
    /// resolver, and was therefore dead code: every `idempotency` seed names a
    /// function that *is* annotated, because an unannotated function cannot
    /// violate an idempotency claim it never made. The guard and the seed
    /// population were mutually exclusive, and only an end-to-end run against a
    /// real manifest showed it.
    ///
    /// The guard is right for `EffectResolver`, whose inference is a weaker
    /// signal that must not dilute a declaration. Here the two are not competing
    /// descriptions of one function — they are a **claim and its refutation**.
    /// `declaredEffectSignal` reads `@Idempotent` as +15 corroboration; the
    /// manifest says a linter followed the call graph and found the body reaches
    /// non-idempotent work. Both should be heard: the annotation is real
    /// evidence, and so is the contradiction. `inferredRetryHostileCallee` at
    /// -45 against that +15 lands the suggestion at a net demotion with both
    /// reasons attached, which is the honest rendering of "the author says yes,
    /// their own call graph says no".
    ///
    /// Suppressing either one would be worse. Dropping the annotation hides that
    /// someone made a claim; dropping the refutation restates a claim the code
    /// contradicts.
    public static func resolve(
        summaries: [FunctionSummary],
        manifest: SeedManifest,
        diagnostic: (String) -> Void = { _ in /* no-op */ }
    ) -> [FunctionSummary] {
        // Reported unconditionally, not only when nothing was actionable. A
        // manifest usually carries a mix, and announcing the withheld ones only
        // in the all-withheld case would hide them behind whatever *did* apply —
        // which is precisely when a reader is least likely to wonder what else
        // was in the file.
        reportWithheld(manifest: manifest, diagnostic: diagnostic)
        let actionable = manifest.seeds.filter {
            $0.effect?.carriesEnoughEvidenceToDemote == true
        }
        guard !actionable.isEmpty else { return summaries }
        var effectBySymbol: [String: SeedEffect] = [:]
        for seed in actionable {
            guard let effect = seed.effect else { continue }
            // Last writer wins, which only matters when one manifest carries two
            // seeds for one symbol name — and then the tiers agree, because they
            // came from one analysis of one function.
            effectBySymbol[seed.symbol] = effect
        }

        var applied = 0
        let updated = summaries.map { summary -> FunctionSummary in
            guard let effect = effectBySymbol[summary.name],
                  EffectResolver.carriesInformationUpward(effect.resolved.asEffect)
            else {
                return summary
            }
            applied += 1
            return summary.withInferredEffect(effect.resolved.asEffect)
        }
        if applied > 0 {
            diagnostic(
                "applied \(applied) linter-resolved effect(s) from the seed manifest — "
                    + "cross-file and multi-hop, which the local one-hop pass cannot reach"
            )
        }
        return updated
    }

    /// Say what was dropped and why.
    ///
    /// A manifest can carry effects this resolver refuses, and refusing them
    /// silently would look identical to a producer that emitted none — the same
    /// confident-zero shape the seed pipeline keeps rediscovering. The reader
    /// should be able to tell "the linter said nothing" from "the linter said
    /// something I am not willing to score."
    private static func reportWithheld(manifest: SeedManifest, diagnostic: (String) -> Void) {
        let withheld = manifest.seeds.compactMap(\.effect).filter {
            !$0.carriesEnoughEvidenceToDemote
        }
        guard !withheld.isEmpty else { return }
        let upward = withheld.filter { $0.provenance == .inferredUpward }.count
        let downward = withheld.filter { $0.provenance == .inferredDownward }.count
        diagnostic(
            "withheld \(withheld.count) linter-resolved effect(s) as evidence "
                + "(\(upward) inferred-upward whose chain bottoms out on a name guess, "
                + "\(downward) inferred-downward): an effect is acted on when a human declared "
                + "it, or when an upward chain reaches one — this tool does not veto on names"
        )
    }
}
