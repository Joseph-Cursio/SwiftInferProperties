import Foundation
import SwiftInferCore

/// V1.98 (cycle-95) — interactive triage loop for
/// `swift-infer discover-interaction --interactive`. Walks the
/// user through each interaction-invariant suggestion one at a
/// time, prompts `[A/C/s/n/?]`, records the chosen
/// `InteractionDecision` to `.swiftinfer/interaction-decisions.json`
/// via the existing `InteractionDecisionsLoader`.
///
/// **The N-arm framing.** PRD §9.4 sketched an `[A/B/B'/B''/.../s/n/?]`
/// prompt for M9's bridge-level peer proposals (multiple conformance
/// options per bridge). This v1.98 ship is the per-suggestion form
/// — simpler, immediately useful for the cycle-7 76-suggestion
/// corpus. Bridge-level N-arm peer triage is a separate follow-up
/// (would reuse `readChoice`'s arm-driver shape).
///
/// **Sibling of v1's `InteractiveTriage`.** Same prompt-loop pattern
/// (`PromptInput` → readLine → switch on choice → record), different
/// data type. v1 walks `[Suggestion]` from `discover`; v1.98 walks
/// `[InteractionInvariantSuggestion]` from `discover-interaction`.
/// The two suites stay independent because the data shapes diverge
/// (interaction invariants carry predicate / family / reducer
/// metadata that algebraic Suggestions don't).
public enum InteractionInteractiveTriage {

    /// V1.98 — one prompt outcome from `readChoice`.
    public enum Choice: Equatable, Sendable {
        case accept
        case acceptAsConformance
        case skip
        case reject
    }

    /// V1.98 — input bundle for the triage session. Sources its
    /// prompts from `prompt`, writes session output to `output`,
    /// diagnostics to `diagnostics`. `dryRun` skips the final
    /// `InteractionDecisionsLoader.write` (skip / reject / accept
    /// all decisions still flow through, just no disk write).
    public struct Inputs {
        public let prompt: any PromptInput
        public let output: any DiscoverOutput
        public let diagnostics: any DiagnosticOutput
        public let dryRun: Bool
        public let now: Date

        public init(
            prompt: any PromptInput,
            output: any DiscoverOutput,
            diagnostics: any DiagnosticOutput,
            dryRun: Bool,
            now: Date = Date()
        ) {
            self.prompt = prompt
            self.output = output
            self.diagnostics = diagnostics
            self.dryRun = dryRun
            self.now = now
        }
    }

    /// V1.98 — drive a full triage session. Loads existing decisions,
    /// walks each suggestion through `readChoice`, upserts the new
    /// record, persists (unless `dryRun`). Returns the updated
    /// `InteractionDecisions` for testability.
    @discardableResult
    public static func run(
        suggestions: [InteractionInvariantSuggestion],
        packageRoot: URL,
        explicitDecisionsPath: URL? = nil,
        inputs: Inputs
    ) throws -> InteractionDecisions {
        let load = InteractionDecisionsLoader.load(
            startingFrom: packageRoot,
            explicitPath: explicitDecisionsPath
        )
        for warning in load.warnings {
            inputs.diagnostics.writeDiagnostic("warning: \(warning)")
        }
        var decisions = load.decisions
        for (index, suggestion) in suggestions.enumerated() {
            renderSuggestion(suggestion, position: index + 1, total: suggestions.count, inputs: inputs)
            inputs.output.write(promptLine(position: index + 1, total: suggestions.count))
            let choice = readChoice(prompt: inputs.prompt, output: inputs.output)
            guard let decision = decisionFor(choice) else {
                // .skip — no record written; suggestion re-surfaces
                // next run. Matches v1's interactive skip semantics.
                inputs.output.write("Skipped.")
                continue
            }
            decisions = decisions.upserting(InteractionDecisionRecord(
                identityHash: suggestion.identity.normalized,
                family: suggestion.family,
                scoreAtDecision: suggestion.score,
                tier: suggestion.tier,
                reducerQualifiedName: suggestion.reducerQualifiedName,
                decision: decision,
                timestamp: inputs.now
            ))
            inputs.output.write("Recorded \(decision.rawValue).")
        }
        if !inputs.dryRun, decisions != load.decisions {
            let path = explicitDecisionsPath
                ?? InteractionDecisionsLoader.defaultPath(for: load.packageRoot ?? packageRoot)
            try InteractionDecisionsLoader.write(decisions, to: path)
        }
        return decisions
    }

    /// V1.98 — read one valid choice from `prompt`, looping on `?`
    /// (help) and invalid input. Returns `.skip` on EOF as a safe
    /// default — piped input running out shouldn't auto-accept
    /// anything. Mirrors v1's `InteractiveTriage.readChoice` posture.
    public static func readChoice(
        prompt: any PromptInput,
        output: any DiscoverOutput
    ) -> Choice {
        while true {
            output.write("> ")
            guard let line = prompt.readLine() else { return .skip }
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            switch trimmed {
            case "a": return .accept
            case "c": return .acceptAsConformance
            case "s", "": return .skip
            case "n": return .reject

            case "?", "h", "help":
                output.write(helpText())

            default:
                output.write("Unrecognized input '\(trimmed)'. Type ? for help.")
            }
        }
    }

    /// V1.98 — translate a `Choice` to the persisted
    /// `InteractionDecision`. `.skip` returns `nil` because the
    /// recorder writes no record for skipped suggestions (matches
    /// v1's interactive skip semantics — the suggestion re-surfaces
    /// in future runs).
    static func decisionFor(_ choice: Choice) -> InteractionDecision? {
        switch choice {
        case .accept: return .accepted
        case .acceptAsConformance: return .acceptedAsConformance
        case .reject: return .rejected
        case .skip: return nil
        }
    }

    static func promptLine(position: Int, total: Int) -> String {
        "[\(position)/\(total)] Accept (A) / Conformance (C) / Skip (s) / Reject (n) / Help (?)"
    }

    static func helpText() -> String {
        """
        A — accept this interaction invariant. Records `accepted` in
            .swiftinfer/interaction-decisions.json; subsequent
            drift-interaction runs stop warning on this identity.
        C — accept as a kit-side conformance candidate. Records
            `accepted-as-conformance`; signals that this invariant
            should be expressed via a SwiftPropertyLaws-side protocol
            conformance (M9 InteractionInvariantBridge target).
        s — skip for now. No record written; re-surfaces in future
            --interactive runs. (Also the default if you press Enter.)
        n — reject. Records `rejected`; hides this suggestion from
            future drift warnings.
        ? — show this help.
        """
    }

    /// V1.98 — render one suggestion's summary line block ahead of
    /// the prompt. Pulled out so the orchestrator stays under
    /// SwiftLint's function-body length cap and so tests can pin
    /// the rendered shape independently.
    private static func renderSuggestion(
        _ suggestion: InteractionInvariantSuggestion,
        position: Int,
        total: Int,
        inputs: Inputs
    ) {
        inputs.output.write("")
        inputs.output.write("[\(position)/\(total)] [Interaction-Invariant Suggestion]")
        inputs.output.write("Family:    \(suggestion.family.rawValue)")
        inputs.output.write("Score:     \(suggestion.score) (\(suggestion.tier.label))")
        inputs.output.write("Reducer:   \(suggestion.reducerQualifiedName)")
        inputs.output.write("Predicate: \(suggestion.predicate)")
        inputs.output.write("Identity:  \(suggestion.identity.display)")
    }
}
