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
        diagnostics: any DiagnosticOutput
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
        if synthesized.isEmpty == false {
            diagnostics.writeDiagnostic(
                "synthesized \(synthesized.count) generic determinism law(s) for seeded functions"
            )
        }
        return synthesized
    }

    /// A seeded function earns the determinism law when it takes inputs, returns
    /// a value, runs without throwing, and is free or `static` (an instance
    /// method could read mutable `self`). The lint seed already vouched for
    /// purity; these are the shape requirements for writing the law.
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
        guard summary.isThrows == false else { return false }
        if summary.isAsync {
            guard summary.isClockDeterministic else { return false }
        }
        return summary.containingTypeName == nil || summary.isStatic
    }

    private static func determinismSuggestion(for summary: FunctionSummary) -> Suggestion {
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
        return Suggestion(
            templateName: "determinism",
            evidence: [evidence],
            score: Score(advisorySignals: [signal]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(
                whySuggested: ["\(evidence.displayName) \(evidence.signature)", signal.formattedLine],
                whyMightBeWrong: whyMightBeWrong
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
        let effectMarker = summary.isAsync ? " async" : ""
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
    private static func functionBaseName(_ displayName: String) -> String {
        guard let paren = displayName.firstIndex(of: "(") else { return displayName }
        return String(displayName[..<paren])
    }

    /// `(file basename, symbol)` join key — robust to relative-vs-absolute path
    /// spellings between the linter and the scanner.
    private static func genericLawKey(file: String, symbol: String) -> String {
        "\(URL(fileURLWithPath: file).lastPathComponent)::\(symbol)"
    }
}
