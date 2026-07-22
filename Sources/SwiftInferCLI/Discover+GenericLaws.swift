import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// Seed-driven generic laws for `swift-infer discover --seeds`.
///
/// The lint seed set (any pure function) is broader than the discover templates'
/// pattern-matched set (idempotence / round-trip / algebraic shapes). For a
/// seeded function that no template matched, this synthesizes the one law that
/// holds for *every* pure function — **determinism**, `f(x) == f(x)` — so the
/// `--seeds` focus always produces something actionable for a clean seed.
///
/// Determinism can't be inferred from a signature (any function "could" be
/// deterministic); it's the lint seed (external evidence of purity) that
/// justifies the law. That's why this lives outside the template engine and is
/// emitted only on the seeds path.
extension SwiftInferCommand.Discover {

    /// Synthesizes determinism suggestions for seeded functions not already
    /// covered by a (focused) template suggestion.
    static func synthesizeGenericLaws(
        for manifest: SeedManifest,
        summaries: [FunctionSummary],
        covered: [Suggestion],
        diagnostics: any DiagnosticOutput,
        restrictedFunctions: [RestrictedFunction] = []
    ) -> [Suggestion] {
        let seedKeys = Set(manifest.seeds.map { genericLawKey(file: $0.file, symbol: $0.symbol) })
        guard !seedKeys.isEmpty else { return [] }

        // Functions a focused suggestion already speaks to — don't duplicate.
        let coveredKeys = Set(covered.flatMap { suggestion in
            suggestion.evidence.map {
                genericLawKey(file: $0.location.file, symbol: functionBaseName($0.displayName))
            }
        })

        var synthesized: [Suggestion] = []
        var seen: Set<String> = []
        for summary in summaries {
            let key = genericLawKey(file: summary.location.file, symbol: summary.name)
            guard seedKeys.contains(key), !coveredKeys.contains(key), !seen.contains(key) else { continue }
            guard qualifiesForDeterminism(summary) else { continue }
            seen.insert(key)
            synthesized.append(determinismSuggestion(for: summary))
        }

        // A seed naming a function the scan set aside is an explicit request from a producer that
        // has already examined it. The scan is right that no external test can *call* it — but the
        // answer to that is to say so, not to drop the reader's best candidate without a word.
        for restricted in restrictedFunctions {
            let summary = restricted.summary
            let key = genericLawKey(file: summary.location.file, symbol: summary.name)
            guard seedKeys.contains(key), !coveredKeys.contains(key), !seen.contains(key) else { continue }
            guard qualifiesForDeterminism(summary) else { continue }
            seen.insert(key)
            synthesized.append(
                determinismSuggestion(for: summary, accessRestriction: restricted.restriction)
            )
            diagnostics.writeDiagnostic(
                "note: seeded function `\(summary.name)` "
                    + "(\(summary.location.file):\(summary.location.line)) is not reachable from a "
                    + "test as written — \(restricted.restriction.remedy)"
            )
        }

        if synthesized.isEmpty == false {
            diagnostics.writeDiagnostic(
                "synthesized \(synthesized.count) generic determinism law(s) for seeded functions"
            )
        }
        return synthesized
    }

    /// A seeded function earns the determinism law when it takes inputs and returns a value. The
    /// lint seed is what vouches for purity; these are the shape requirements for *writing* the law.
    ///
    /// **Instance methods qualify.** They used to be refused here — "an instance method could read
    /// mutable `self`" — which was the same blanket refusal the producing linter made, in the same
    /// words, and it is redundant twice over. The seed is the purity claim: a producer that
    /// analyses what a method reads from `self` has already answered the objection, and this end
    /// has no way to re-litigate it anyway. And the law is self-falsifying — as its own "why this
    /// might be wrong" says, a hidden state read "would falsify it, which is exactly what the test
    /// catches." Refusing to *write* a law because it might fail is refusing to test.
    ///
    /// The cost of the old gate was concrete: in an app almost all logic is instance methods, so
    /// every seed the linter handed over was discarded here, and the pipeline reported nothing.
    ///
    /// **Throwing functions qualify** — the identical mistake, un-fixed until the SwiftLintRuleStudio
    /// road-test hit it: a seeded throwing pure function (`serialize(_:) throws -> String`) fell
    /// through and earned *nothing*, a confident zero, while a non-throwing sibling got the floor.
    /// A pure function is deterministic whether or not it throws. The emitted stub handles the throw
    /// soundly by comparing `try? f(x)` on both sides (`LiftedTestEmitter.deterministic(isThrows:)`),
    /// so an input in the throwing domain collapses to `nil == nil` and only a *value* difference —
    /// the hidden nondeterminism this law exists to catch — can falsify it. No false positives.
    ///
    /// **Async relaxation (collections/async workplan Phase 4):** an `async`
    /// function qualifies only when it carries the clock-determinism claim
    /// (`/// @lint.determinism clock_deterministic` / `@ClockDeterministic`)
    /// — the conjunction posture SwiftEffectInference's annotation
    /// documents. Purity can't vouch for an async function (async refutes
    /// `.pure` by contract), so the user-declared claim substitutes for the
    /// seed's purity justification, and the emitted determinism law is
    /// exactly the check that falsifies a wrong claim. Bare async stays
    /// vetoed.
    private static func qualifiesForDeterminism(_ summary: FunctionSummary) -> Bool {
        guard let returnType = summary.returnTypeText, returnType != "Void", returnType != "()" else {
            return false
        }
        guard summary.parameters.isEmpty == false else { return false }
        if summary.isAsync {
            guard summary.isClockDeterministic else { return false }
        }
        return true
    }

    /// The determinism law for `summary`.
    ///
    /// `accessRestriction` is non-nil when the scan set the function aside as uncallable from an
    /// external test and only a seed rescued it. The law is still worth stating — the reader asked
    /// for it, and it is the right law — but it cannot be *run* until the access is widened, so the
    /// caveat leads with the remedy rather than leaving them to discover it at verify time.
    private static func determinismSuggestion(
        for summary: FunctionSummary,
        accessRestriction: AccessRestriction? = nil
    ) -> Suggestion {
        let evidence = makeEvidence(for: summary)
        let signal = summary.isAsync
            ? Signal(
                kind: .deterministicPurity,
                weight: 30,
                detail: "Clock-deterministic-annotated async function — deterministic "
                    + "given an injected Clock: f(x) == f(x) awaited twice"
            )
            : Signal(
                kind: .deterministicPurity,
                weight: 30,
                detail: "Lint-seeded pure function — a pure function is deterministic: f(x) == f(x)"
            )
        let whyMightBeWrong = summary.isAsync
            ? [
                "Holds only if time is genuinely injected — a wall-clock read, Task.sleep "
                    + "on the continuous clock, or any await on shared mutable state would "
                    + "falsify the @ClockDeterministic claim, which is exactly what the test catches.",
                "The return type must be Equatable for the law to compile."
            ]
            : [
                "Holds only if the function is genuinely pure — a hidden global read or "
                    + "nondeterministic dependency would falsify it, which is exactly what the test catches.",
                "The return type must be Equatable for the law to compile."
            ]
        let throwsCaveat = summary.isThrows
            ? ["The function throws, so the law compares `try? f(x)` on both sides: an input in the "
                + "throwing domain collapses to `nil == nil` (never a false alarm), and only a value "
                + "difference on a non-throwing input falsifies it."]
            : []
        let caveats = (accessRestriction.map { restriction in
            ["No test can run this law as written: \(restriction.remedy)"] + whyMightBeWrong
        } ?? whyMightBeWrong) + throwsCaveat
        return Suggestion(
            templateName: "determinism",
            evidence: [evidence],
            score: Score(advisorySignals: [signal]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(
                whySuggested: ["\(evidence.displayName) \(evidence.signature)", signal.formattedLine],
                whyMightBeWrong: caveats
            ),
            identity: SuggestionIdentity(
                canonicalInput: "determinism|" + canonicalInput(for: summary, evidence: evidence)
            ),
            carrier: summary.containingTypeName
        )
    }

    /// Builds the renderer's `Evidence` row from a summary: a labelled display
    /// name (`add(_:_:)`) and a trimmed signature (`(Int, Int) -> Int`, or
    /// `(Int) async -> String` for a clock-deterministic async candidate).
    /// Mirrors the templates' internal `inferenceEvidence` (not accessible
    /// cross-module) — including its ` async` marker, which the acceptance
    /// path's `deterministicStub` reads to emit the awaited stub form. Sync
    /// signatures are byte-identical to before (identity hashes stable);
    /// async candidates are new with the Phase 4 relaxation, so their
    /// identities have no prior corpus to drift from.
    private static func makeEvidence(for summary: FunctionSummary) -> Evidence {
        let labels = summary.parameters.map { "\($0.label ?? "_"):" }.joined()
        let displayName = "\(summary.name)(\(labels))"
        let paramTypes = summary.parameters.map(\.typeText).joined(separator: ", ")
        let returnType = summary.returnTypeText ?? "Void"
        // Effect markers in Swift order (`async throws`); the accept path's
        // `deterministicStub` reads them to emit the awaited / `try?` stub form.
        let asyncMarker = summary.isAsync ? " async" : ""
        let throwsMarker = summary.isThrows ? " throws" : ""
        let effectMarker = asyncMarker + throwsMarker
        return Evidence(
            displayName: displayName,
            signature: "(\(paramTypes))\(effectMarker) -> \(returnType)",
            location: summary.location
        )
    }

    private static func canonicalInput(for summary: FunctionSummary, evidence: Evidence) -> String {
        let owner = summary.containingTypeName.map { "\($0)." } ?? ""
        return "\(owner)\(evidence.displayName)|\(evidence.signature)"
    }

    /// The bare function name from an evidence display name: `add(_:_:)` → `add`.
    /// Internal (not private) so the docstring-advice pass shares the exact same
    /// function-keying — the two must agree or advice would attach to the wrong
    /// suggestion set.
    static func functionBaseName(_ displayName: String) -> String {
        guard let paren = displayName.firstIndex(of: "(") else { return displayName }
        return String(displayName[..<paren])
    }

    /// `(file basename, symbol)` join key — robust to relative-vs-absolute path
    /// spellings between the linter and the scanner. Internal (see
    /// `functionBaseName`) so the docstring-advice pass keys identically.
    static func genericLawKey(file: String, symbol: String) -> String {
        "\(URL(fileURLWithPath: file).lastPathComponent)::\(symbol)"
    }
}
