import ArgumentParser
import Foundation
import SwiftInferCore

/// `swift-infer discover --seeds` — the consumer side of the lint → infer
/// pipeline. SwiftProjectLint's `--format pbt-seeds` names the functions worth
/// property-testing; these helpers load that manifest and focus discovery's
/// output down to exactly those functions.
extension SwiftInferCommand.Discover {

    /// Loads and decodes a `pbt-seeds` manifest. Throws a readable error when
    /// the file is absent or malformed: `--seeds` is an explicit focusing
    /// request, so failing loudly beats silently emitting the full, unfocused
    /// result in a pipeline.
    static func loadSeedManifest(at url: URL) throws -> SeedManifest {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ValidationError("could not read seeds file at \(url.path): \(error.localizedDescription)")
        }
        do {
            return try JSONDecoder().decode(SeedManifest.self, from: data)
        } catch {
            throw ValidationError("could not parse seeds file at \(url.path) as a pbt-seeds manifest: \(error)")
        }
    }

    /// Applies the `--seeds` focus. With no manifest this is the identity. With
    /// one, it keeps only suggestions touching a seeded function, warns on an
    /// unknown schema version, and reports the focus ratio to stderr so stdout
    /// stays a clean suggestion stream.
    ///
    /// The two ways focusing can silently destroy the run get a loud warning each, because a
    /// tool that answers "0 suggestions" when it found several is worse than a tool that answers
    /// nothing at all — the reader believes it.
    static func focus(
        _ pipeline: PipelineResult,
        with seedManifest: SeedManifest?,
        diagnostics: any DiagnosticOutput
    ) -> [Suggestion] {
        guard let seedManifest else { return pipeline.suggestions }
        if seedManifest.version != SeedManifest.supportedVersion {
            diagnostics.writeDiagnostic(
                "warning: seeds manifest version \(seedManifest.version) is not the supported "
                    + "version \(SeedManifest.supportedVersion); consuming best-effort"
            )
        }

        // Say what a human must do before any tool can help. These seeds never focus — see below.
        reportRefactorPending(in: seedManifest, diagnostics: diagnostics)

        let focusing = seedManifest.analysableSeeds
        let analysableManifest = SeedManifest(version: seedManifest.version, seeds: focusing)

        // No *analysable* seed is not a request to see nothing. There are two ways to arrive here
        // and the reader needs to be told which, because the remedy differs.
        if focusing.isEmpty {
            diagnostics.writeDiagnostic(noFocusWarning(for: seedManifest, pipeline: pipeline))
            let unfocused = pipeline.suggestions + synthesizeGenericLaws(
                for: analysableManifest,
                summaries: pipeline.summaries,
                covered: pipeline.suggestions,
                diagnostics: diagnostics,
                restrictedFunctions: pipeline.restrictedFunctions
            )
            // This path synthesizes determinism laws too, so it can hand back a confident pile of
            // tautologies exactly as the focused path can — the tier cut may still be holding the
            // only law that could fail. Same guard, same reason.
            return guardFinalAnswer(unfocused, pipeline: pipeline, diagnostics: diagnostics)
        }

        return focusOnAnalysableSeeds(
            focusing: focusing,
            analysableManifest: analysableManifest,
            pipeline: pipeline,
            diagnostics: diagnostics
        )
    }

    /// **Never replace a function's real law with a tautology about that same function.**
    ///
    /// The determinism law is a *fallback*: `synthesizeGenericLaws` emits it for a seeded pure
    /// function that **no template matched**, so that `--seeds` always surfaces something. Its entire
    /// justification is "I had nothing better." When a template *did* match and the tier cut merely
    /// hid it, that justification evaporates — and without this promotion the tool does something
    /// indefensible:
    ///
    /// > `isImmediateChild` earns a **predicate** law, which scores `Possible` and is hidden. The
    /// > fallback then fires *because nothing is covering that function* and prints
    /// > `isImmediateChild(x) == isImmediateChild(x)`. The reader is shown a tautology about the very
    /// > function whose real law is sitting in the bin — and the real law is the one carrying *"state
    /// > the reference definition in one English sentence; that sentence is the property"*, which is
    /// > the only thing in the run that leads to the bug living in that predicate.
    ///
    /// The `Refutability` guard does not catch this, and should not: the answer as a whole *does*
    /// contain a refutable law (the comparator on `precedes`), so the invariant is satisfied. This is
    /// a per-function claim, not a per-run one — hence a separate rule.
    ///
    /// **The linter has already vouched for this function.** It is in the manifest precisely because
    /// the linter judged it worth property-testing. Proposing a law for it and then hiding that law
    /// on confidence grounds, while printing a tautology in its place, is the scorer overruling the
    /// producer to no one's benefit. A weak real law beats a strong fake one.
    /// **The focus narrows guesses. It never hides a law the code OWES.**
    ///
    /// A cold reader found this the hard way, and their sentence is the specification: *"Doing what
    /// the tool asked **lost** coverage."* They performed the extraction the linter demanded, the
    /// linter then failed to seed the value type it had just told them to create (it cannot see
    /// through a computed-property read), the focus therefore found no match for the `partition` law
    /// discovery had produced — and dropped it. The single sharpest law in the run, about the code
    /// the whole exercise is aimed at, silently vanished *because the reader complied*.
    ///
    /// `Refutability`'s run-level guard does not save it, and cannot: that guard only fires when the
    /// answer would otherwise be **all tautologies**, and by then the run had a comparator and a
    /// predicate law. One good law was buying silence for the loss of another. A guarantee of
    /// *"at least one refutable law somewhere"* is not a guarantee about the law you needed.
    ///
    /// So the rule is stated on the law itself, not on the run. A **role-entailed** law — totality,
    /// an ordering, a tiling — is one a *correct* implementation cannot fail, so surfacing it can
    /// never waste the reader's time on a false alarm. There is therefore nothing for the focus to
    /// protect them *from*, and no honest reason to hide it. Conjectures (`monotonicity`,
    /// `idempotence`, guessed from a name) are exactly what focusing exists to narrow, and they are
    /// still narrowed.
    ///
    /// This does not weaken the seed focus in the case it was built for. It weakens it in the case it
    /// was getting wrong.
    static func keepRoleEntailedLaws(
        in suggestions: [Suggestion],
        alreadyShown: [Suggestion],
        diagnostics: any DiagnosticOutput
    ) -> [Suggestion] {
        let shown = Set(alreadyShown.map(\.identity))
        let owed = suggestions.filter { suggestion in
            Refutability.isRoleEntailed(suggestion) && !shown.contains(suggestion.identity)
        }
        guard !owed.isEmpty else { return [] }

        diagnostics.writeDiagnostic(owedLawWarning(for: owed))
        return owed
    }

    /// Built from an array, not a `+` chain — see `promotionWarning`.
    private static func owedLawWarning(for owed: [Suggestion]) -> String {
        let subjects = owed
            .map { "`\($0.templateName)` on `\($0.evidence.first?.displayName ?? "?")`" }
            .joined(separator: ", ")
        return [
            "warning: \(subjects) — the seed manifest does not name the subject, but this law is owed",
            "by the code's ROLE (a correct implementation cannot fail it), so the focus does not get",
            "to hide it. The manifest SHOULD have named it: this is a LINTER gap, and the usual cause",
            "is a shape the linter cannot see — methods on a value type it just told you to extract,",
            "a computed-property read, a call to `min`. Seed it, and this warning goes away."
        ].joined(separator: " ")
    }

    /// **Four gates, and the first draft had none of them.** Each was put there by a failure.
    ///
    /// - **Role-entailed only.** This is the one that matters. A law shown *below the confidence cut*
    ///   must be one a **correct** implementation cannot fail — totality, an ordering, a tiling —
    ///   because the cut is the only thing standing between the reader and every low-confidence
    ///   guess the catalogue can make. The first draft promoted a `monotonicity` law onto
    ///   `func get(_ key: String) -> Int { key.count }`, which is **not monotone** (`"aa" < "b"` yet
    ///   `count("aa") > count("b")`) — a law a correct function fails. That is the
    ///   `selectAllFiles`/`deselectAllFiles` mistake wearing a promotion's clothes, and **a tool that
    ///   proposes a false law is worse than one that proposes nothing.** `Refutability` names the two
    ///   axes: *refutable* (a wrong implementation **can** fail it) and *role-entailed* (a right one
    ///   **cannot**). A promotion needs both.
    /// - **Unary only.** A *pair* law (round-trip, dual-style) carries two subjects, and the focus
    ///   keeps a pair when **either** half is seeded. Promote one and it drags its partner into the
    ///   output — a function the manifest never named. The first draft surfaced `sanitize` because it
    ///   partners `normalize`, and keeping `sanitize` out is the entire job of the focus.
    /// - **Only if the function has nothing else.** The justification is *"do not print a tautology in
    ///   place of a real law"*. If a real law for that function is already on screen, there is no
    ///   tautology to displace and nothing to justify overriding the score.
    /// - **Only if the manifest named it.** The promotion trades on the linter's judgement, so a
    ///   suggestion the linter never vouched for gets no such credit.
    static func promoteTierHiddenLaws(
        for manifest: SeedManifest,
        pipeline: PipelineResult,
        alreadyShown: [Suggestion],
        diagnostics: any DiagnosticOutput
    ) -> [Suggestion] {
        guard !pipeline.tierHiddenRefutableLaws.isEmpty else { return [] }

        // Functions that already have a real law on screen. They are not at risk of being handed a
        // tautology, so the score stands.
        let covered = Set(alreadyShown.flatMap { $0.evidence.map { baseName(of: $0.displayName) } })
        let shown = Set(alreadyShown.map(\.identity))

        let candidates = pipeline.tierHiddenRefutableLaws.filter { suggestion in
            guard Refutability.isRoleEntailed(suggestion),
                  !shown.contains(suggestion.identity),
                  !SeedFocus.seedIndependentTemplates.contains(suggestion.templateName),
                  suggestion.evidence.count == 1,
                  let subject = suggestion.evidence.first
            else { return false }
            return !covered.contains(baseName(of: subject.displayName))
        }
        guard !candidates.isEmpty else { return [] }

        let promoted = SeedFocus.filter(candidates, to: manifest)
        for suggestion in promoted {
            diagnostics.writeDiagnostic(promotionWarning(for: suggestion))
        }
        return promoted
    }

    /// `isImmediateChild(_:of:)` → `isImmediateChild`. The argument labels are part of the display
    /// name but not of the identity we are comparing on.
    private static func baseName(of displayName: String) -> String {
        String(displayName.prefix { $0 != "(" })
    }

    /// Built from an array, not a `+` chain — a long concatenation of interpolated strings is the
    /// shape that blows the Swift type-checker's time budget.
    private static func promotionWarning(for suggestion: Suggestion) -> String {
        let subject = suggestion.evidence.first?.displayName ?? "a seeded function"
        let score = "\(suggestion.score.total), \(suggestion.score.tier.rawValue)"
        return [
            "note: `\(suggestion.templateName)` on `\(subject)` scored \(score) — below the default",
            "visibility cut — but the linter seeded that function, so it is shown rather than",
            "replaced by a determinism tautology about the same function. A weak law that can fail",
            "beats a strong one that cannot."
        ].joined(separator: " ")
    }

    /// **The reader is never handed a non-empty answer containing zero refutable laws, when this
    /// run found one.**
    ///
    /// Two filters stand between discovery and the reader — the tier cut and the seed focus — and
    /// each can independently discard the last law that could fail. On the road-test fixture both
    /// did. The guard is applied *here*, once, on the finished answer, rather than inside either
    /// filter, and the reason is worth stating because the first attempt got it wrong:
    ///
    /// **A filter cannot tell, on its own, whether hiding a law is honest.** When the tier cut hides
    /// every `Possible` pick and the run then prints "0 suggestions", that is the cut working as
    /// designed — a `Possible` law is a guess, defaulting to hide guesses is the point, and
    /// `--include-possible` is right there. Guarding *inside* the cut would make that flag a no-op.
    /// What turns the same hiding into a lie is a *later* stage: `--seeds` synthesizes determinism
    /// laws downstream, and the reader is handed a confident "6 suggestions", every one of them a
    /// tautology, with the only refutable claim in the run in the bin. Whether a filter told the
    /// truth is therefore a property of the **final answer**, and only this stage can see it.
    ///
    /// So: an **empty** answer stays empty — that is an honest "nothing confident here". A
    /// **non-empty** answer that cannot fail, when something in the run could have, is the lie, and
    /// the laws come back.
    static func guardFinalAnswer(
        _ answer: [Suggestion],
        pipeline: PipelineResult,
        diagnostics: any DiagnosticOutput
    ) -> [Suggestion] {
        // An honest empty. Say nothing and hide nothing: the reader was told there is no confident
        // finding, which is true, and `--include-possible` is the documented next step.
        guard !answer.isEmpty else { return answer }

        let pool = pipeline.suggestions + pipeline.tierHiddenRefutableLaws
        let guarded = Refutability.preservingLastRefutable(filtered: answer, from: pool)
        guard !guarded.rescued.isEmpty else { return guarded.kept }

        // A rescue is a bug report. Which upstream stage is at fault depends on which filter ate
        // the law, and the two demand opposite fixes — so they get opposite messages.
        let tierHidden = Set(pipeline.tierHiddenRefutableLaws.map(\.identity))
        let scored = guarded.rescued.filter { tierHidden.contains($0.identity) }
        let unjoined = guarded.rescued.filter { !tierHidden.contains($0.identity) }

        if !scored.isEmpty {
            diagnostics.writeDiagnostic(scoringRescueWarning(for: scored))
        }
        if !unjoined.isEmpty {
            diagnostics.writeDiagnostic(focusRescueWarning(for: unjoined))
        }
        return guarded.kept
    }

    /// Said when the *tier cut* hid the only law in the run that could fail, and the answer the
    /// reader would otherwise have received was a pile of tautologies.
    ///
    /// Built from an array, not a `+` chain: a long concatenation of interpolated strings is the
    /// shape that blows the Swift type-checker's time budget, and it does so on a CI runner's
    /// slower toolchain long before it does so locally.
    private static func scoringRescueWarning(for rescued: [Suggestion]) -> String {
        let subjects = rescued
            .map { "`\($0.templateName)` (\($0.score.total), \($0.score.tier.rawValue))" }
            .joined(separator: ", ")
        return [
            "warning: \(subjects) scored below the default visibility cut, but every other",
            "suggestion in this run is a tautology — so it is shown anyway rather than handing you",
            "a confident answer that cannot fail. Treat this as a SCORING bug: a law that can be",
            "refuted is worth more than any number of laws that cannot, and the score does not yet",
            "say so."
        ].joined(separator: " ")
    }

    /// Said when the *seed focus* discarded the only law in the run that could fail.
    ///
    /// This names the **linter** as the culprit on purpose. A rescue here does not mean the focus is
    /// too aggressive; it means the manifest was missing a function it should have contained, and
    /// the commonest way that happens is the linter failing to see methods on a value type it
    /// *itself* asked the reader to extract. Sending the reader to `--seeds` would send them to the
    /// wrong repo — which is exactly what the old warning did, while discarding the law anyway.
    ///
    /// Note this is NOT `seedIndependentTemplates`, and the distinction is why both exist. That set
    /// means *a manifest could never name this subject* — an impure `Void` mutator — a permanent,
    /// principled exemption. This is the opposite claim: the subject is an ordinary pure function a
    /// manifest **should** have named, and the join failed regardless. That is a producer defect,
    /// and the rescue only keeps the reader from paying for it.
    private static func focusRescueWarning(for rescued: [Suggestion]) -> String {
        let subjects = rescued.map { "`\($0.templateName)`" }.joined(separator: ", ")
        return [
            "warning: the focus discarded every law in this run that could fail, so \(subjects) is",
            "shown anyway — narrowing a reader down to nothing but tautologies is not a narrowing,",
            "it is an erasure. Treat this as a LINTER bug, not a swift-infer one: the subject is an",
            "ordinary pure function the seed manifest should have named and did not. The usual cause",
            "is a shape the linter cannot see — methods on a value type it just told you to extract,",
            "for one. Seed it, and this warning goes away."
        ].joined(separator: " ")
    }

    /// The two ways a manifest can carry no *analysable* seed, told apart — because "the linter
    /// found nothing" and "the linter found only work you have to do first" call for opposite next
    /// steps, and a single message for both would send half of its readers the wrong way.
    private static func noFocusWarning(
        for seedManifest: SeedManifest,
        pipeline: PipelineResult
    ) -> String {
        let shown = "no focus was applied and all \(pipeline.suggestions.count) suggestion(s) "
            + "are shown."

        guard !seedManifest.seeds.isEmpty else {
            return "warning: the seeds manifest is empty, so \(shown) An empty manifest usually "
                + "means the producing linter found no candidates — not that this code has none. "
                + "If the linter cannot see the shape of your code (instance methods, for one), "
                + "seed it by hand or re-run without --seeds."
        }

        return "warning: all \(seedManifest.seeds.count) seed(s) in the manifest name work that "
            + "must be done by hand first — not a function this tool can analyse — so \(shown) "
            + "Extract the kernels listed above into named functions and re-run the linter; they "
            + "will come back as ordinary seeds, and their laws with them."
    }

    /// Announce the seeds that name pure logic with **no name yet**.
    ///
    /// This is the whole reason `kind` exists. A kernel cannot be focused on — its symbol is the
    /// impure method the logic is trapped inside, so narrowing to it would make this tool refuse the
    /// function and report `kept 0` for code that demonstrably has property-testable logic in it.
    /// Silently skipping them would be no better: the reader would see a smaller number and no
    /// reason for it.
    ///
    /// So they are neither focused on nor dropped. They are *named*, with the one instruction that
    /// unblocks them.
    private static func reportRefactorPending(
        in seedManifest: SeedManifest,
        diagnostics: any DiagnosticOutput
    ) {
        let pending = seedManifest.refactorPendingSeeds
        guard !pending.isEmpty else { return }

        let kernels = pending.filter { $0.kind == .extractableKernel }
        let unknown = pending.filter { seed in
            if case .unrecognised = seed.kind { return true }
            return false
        }

        if !kernels.isEmpty {
            diagnostics.writeDiagnostic(
                "\(kernels.count) extractable kernel(s) — pure logic with no name yet, so there is "
                    + "nothing here to index, call, or generate inputs for. No law can be proposed "
                    + "until a human draws the boundary:"
            )
            for seed in kernels {
                diagnostics.writeDiagnostic(
                    "  \(seed.file):\(seed.line): inside `\(seed.symbol)` — extract it into a "
                        + "named value type, then re-run the linter to seed it properly."
                )
            }
        }

        for seed in unknown {
            diagnostics.writeDiagnostic(
                "warning: seed `\(seed.symbol)` (\(seed.file):\(seed.line)) has kind "
                    + "'\(seed.kind.rawValue)', which this build does not recognise. It was NOT "
                    + "focused on: narrowing to a symbol whose meaning is unknown is how a tool "
                    + "ends up reporting a confident zero. Upgrade swift-infer, or re-run without "
                    + "--seeds."
            )
        }
    }
}
