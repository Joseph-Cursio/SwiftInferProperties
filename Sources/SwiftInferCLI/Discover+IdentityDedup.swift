import Foundation
import SwiftInferCore

extension SwiftInferCommand.Discover {

    /// **Collapse suggestions that are the same law about the same function.**
    ///
    /// `SuggestionIdentity` is `SHA256(template ID + canonical signature)` — so two suggestions
    /// sharing an identity are not merely similar, they are *the same claim*. Every downstream
    /// consumer already treats them that way and always has: `// swiftinfer: skip <hash>`
    /// suppresses all copies at once, `VerifyEvidence` is keyed by identity so one verify run
    /// answers for all of them, and the persisted index stores one entry per identity. The
    /// renderer was the only component counting them separately, which made the output
    /// disagree with the index about how many laws exist.
    ///
    /// ## The measurement that found it
    ///
    /// Applying the toolchain to this repo (findings §10.4) rendered **174** rows against
    /// **170** distinct identities. All four extras were one lifted `differential-equivalence`
    /// law emitted five times — and because that law scores 80, the duplication landed
    /// *entirely in `Strong`*, reporting 7 top-tier rows where there are 3. The tier a reader
    /// is told to trust was more than half one law wearing a hat.
    ///
    /// The cause is not a bug in lifting. `GeneratorSelectionIntegrationTests` contains five
    /// golden tests that each assert `SuggestionRenderer.render(x) == expectedRender(...)`;
    /// the lifter correctly reads five test bodies, and they correctly reduce to one law.
    /// Nothing between `promote` and the renderer asked whether two rows were the same claim.
    ///
    /// ## Why here, and why first-wins
    ///
    /// This runs at the TemplateEngine ⧺ lifted join, before scoring and before the visibility
    /// cut, so the index, `accept`, `verify` and the renderer all see one list. Deduping at
    /// render time would have fixed the display and left the index disagreeing.
    ///
    /// **First occurrence wins, and the order is load-bearing**: `artifacts.suggestions`
    /// (TemplateEngine) precedes the promoted lifted rows, so a law the engine derived
    /// structurally outranks the same law recovered from a test body. That is the same
    /// precedence `crossValidationKey` suppression already applies one step earlier — this
    /// only catches the pairs whose keys differ but whose identities do not.
    ///
    /// ## Collapsing is reported, never silent
    ///
    /// A dedup that quietly drops rows is the "no silent caps" failure: output that looks like
    /// it covered everything. When copies are collapsed the survivor gains a `whySuggested`
    /// line saying how many there were, so the five golden tests read as *corroboration* —
    /// which is what they are — rather than vanishing.
    ///
    /// The line does not name the test methods. `LiftedOrigin` carries a `testMethodName` and a
    /// `sourceLocation`, but these rows render `<test-body>:0`: the origin is a placeholder on
    /// this path, so there is nothing truthful to name yet. Populating it is the natural
    /// follow-up, and would turn the count into a list.
    static func dedupedByIdentity(_ suggestions: [Suggestion]) -> [Suggestion] {
        var countsByIdentity: [String: Int] = [:]
        for suggestion in suggestions {
            countsByIdentity[suggestion.identity.normalized, default: 0] += 1
        }
        guard countsByIdentity.contains(where: { $0.value > 1 }) else { return suggestions }

        var seen: Set<String> = []
        var result: [Suggestion] = []
        result.reserveCapacity(countsByIdentity.count)
        for suggestion in suggestions {
            let key = suggestion.identity.normalized
            guard seen.insert(key).inserted else { continue }
            let copies = countsByIdentity[key] ?? 1
            result.append(copies > 1 ? annotatingCollapse(suggestion, copies: copies) : suggestion)
        }
        return result
    }

    /// Record the collapse on the survivor, so the dropped rows are accounted for.
    private static func annotatingCollapse(_ suggestion: Suggestion, copies: Int) -> Suggestion {
        suggestion.withExplainability(
            ExplainabilityBlock(
                whySuggested: suggestion.explainability.whySuggested + [
                    "Stated \(copies) times by the scan — \(copies) sources reduce to this one "
                        + "law, identical under `SuggestionIdentity` (same template, same "
                        + "canonical signature), so they are corroboration rather than separate "
                        + "findings. Collapsed to one row; `// swiftinfer: skip "
                        + "\(suggestion.identity.display)` already suppressed all \(copies)."
                ],
                whyMightBeWrong: suggestion.explainability.whyMightBeWrong
            )
        )
    }
}
