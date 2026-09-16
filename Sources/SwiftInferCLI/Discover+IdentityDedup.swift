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
    /// **That reading is not safe merely because two rows share a key.** Six templates used to
    /// key on the declaring type and the bare name, so overloads differing only by argument label
    /// shared one key and the collapse folded together laws that were genuinely different (#490).
    /// Every template now carries the full signature; the note still distinguishes the two cases
    /// by what the copies were ABOUT rather than by trusting the key.
    ///
    /// The line does not name the test methods, and that is now a choice rather than a
    /// limitation. It used to be the latter: `LiftedOrigin` carried a `testMethodName` and a
    /// `sourceLocation`, but the renderer ignored them and every lifted row printed
    /// `<test-body>:0`, so there was nothing truthful to name. **That is fixed** —
    /// `LiftedSuggestion.provenanceLine()` now resolves through the origin, and each row names
    /// the test file, line and method it came from
    /// (`docs/measurements/roadtest-self-dogfood-2026-08-08.md` §7.4).
    ///
    /// Turning this count into a LIST is therefore unblocked and deliberately not done here:
    /// the collapse line answers *how much corroboration*, and the per-row provenance already
    /// answers *from where*. Listing five paths on the survivor would restate, at the point of
    /// collapse, what the surviving row's own `whySuggested` block says one line above.
    static func dedupedByIdentity(_ suggestions: [Suggestion]) -> [Suggestion] {
        var countsByIdentity: [String: Int] = [:]
        var declarationsByIdentity: [String: Set<String>] = [:]
        for suggestion in suggestions {
            let key = suggestion.identity.normalized
            countsByIdentity[key, default: 0] += 1
            declarationsByIdentity[key, default: []].insert(declarationFingerprint(of: suggestion))
        }
        guard countsByIdentity.contains(where: { $0.value > 1 }) else { return suggestions }

        var seen: Set<String> = []
        var result: [Suggestion] = []
        result.reserveCapacity(countsByIdentity.count)
        for suggestion in suggestions {
            let key = suggestion.identity.normalized
            guard seen.insert(key).inserted else { continue }
            let copies = countsByIdentity[key] ?? 1
            guard copies > 1 else {
                result.append(suggestion)
                continue
            }
            result.append(
                annotatingCollapse(
                    suggestion,
                    copies: copies,
                    distinctDeclarations: declarationsByIdentity[key]?.count ?? 1
                )
            )
        }
        return result
    }

    /// What the suggestion is *about*, as far as the collapse can see: each evidence row's
    /// signature and location.
    ///
    /// **This is the discriminator, and the template name is not.** A collapse is corroboration
    /// when the copies are one declaration observed more than once — the measured §10.4 case,
    /// five golden tests lifting to one law — and a conflation when they are different
    /// declarations that happen to share a key. `differential-equivalence` produces both, so any
    /// rule keyed on the template gets one of them wrong; the existing five-golden-tests test is
    /// what caught that.
    ///
    /// ⚠ **A lifted row carries no evidence rows**, so every copy of one fingerprints to the same
    /// empty string and reads as corroboration. That is the right answer for the case on record
    /// and it is an assumption, not a proof: if lifted rows ever carry per-test evidence, five
    /// golden tests would start reading as five declarations. `fiveGoldenTestsAreCorroboration`
    /// fails the day that changes, which is the point of stating it here.
    static func declarationFingerprint(of suggestion: Suggestion) -> String {
        suggestion.evidence
            .map { "\($0.signature)@\($0.location.file):\($0.location.line)" }
            .sorted()
            .joined(separator: "|")
    }

    /// Record the collapse on the survivor, so the dropped rows are accounted for.
    ///
    /// **The note reports the collapse; it asserts corroboration only where the key can support
    /// that.** It used to say *"so they are corroboration rather than separate findings"*
    /// unconditionally, which is true when the identity carries argument labels and false when it
    /// does not: six templates key on the declaring type and the bare name, so `ChannelPipeline`'s
    /// one `addHandler` and six `removeHandler` overloads collapse into a single row that claimed
    /// six sources agreed about one law. They are six different laws (#490).
    ///
    /// A reader who takes that for agreement has been told something the tool cannot know — the
    /// same failure the `TAUTOLOGY` and `CHARACTERISATION` law-class lines exist to prevent, one
    /// layer out.
    private static func annotatingCollapse(
        _ suggestion: Suggestion,
        copies: Int,
        distinctDeclarations: Int
    ) -> Suggestion {
        suggestion.withExplainability(
            ExplainabilityBlock(
                whySuggested: suggestion.explainability.whySuggested + [
                    collapseNote(
                        for: suggestion,
                        copies: copies,
                        distinctDeclarations: distinctDeclarations
                    )
                ],
                whyMightBeWrong: suggestion.explainability.whyMightBeWrong
            )
        )
    }

    /// The sentence the survivor carries, chosen by what the collapsed copies were **about**.
    ///
    /// One declaration seen `copies` times is corroboration and says so. More than one declaration
    /// under one key is not, and says *that*.
    ///
    /// The second case used to name its cause — six templates keyed on the declaring type and the
    /// bare function name, so overloads differing only by argument label shared a key (#490).
    /// Every template now carries the full signature, so there is no longer a standing cause to
    /// name. The branch stays because a collapse over distinct declarations would still be worth
    /// reporting honestly if one ever happened, and "should not happen" is not a reason to tell a
    /// reader something the tool has not checked.
    static func collapseNote(
        for suggestion: Suggestion,
        copies: Int,
        distinctDeclarations: Int
    ) -> String {
        let skip = "`// swiftinfer: skip \(suggestion.identity.display)`"
        guard distinctDeclarations > 1 else {
            return "Stated \(copies) times by the scan — \(copies) sources reduce to this one law, "
                + "identical under `SuggestionIdentity` and about the same declaration, so they are "
                + "corroboration rather than separate findings. Collapsed to one row; \(skip) "
                + "already suppressed all \(copies)."
        }
        return "Collapsed \(copies) suggestions over \(distinctDeclarations) DIFFERENT "
            + "declarations into this row — NOT corroboration. They share a `SuggestionIdentity`, "
            + "so this row states one of them and \(skip) suppresses all \(copies). Read the "
            + "declarations before treating the count as agreement."
    }
}
