import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// `swift-infer discover --interactive` triage orchestrator (M6.4 +
/// M7.5 RefactorBridge extension).
/// Walks each surviving suggestion, prompts the user with
/// `[A/s/n/?]` (or `[A/B/s/n/?]` when a `RefactorBridgeProposal` is
/// attached to the suggestion's type per the M7.5 orchestrator), and
/// dispatches:
///
/// - `A` — accept Option A. For `idempotence` / `round-trip` /
///   `monotonicity` / `invariant-preservation` suggestions, emit a
///   peer `@Test func` via `LiftedTestEmitter` (M6.3 + M7.3) and
///   write it to `Tests/Generated/SwiftInfer/<TemplateName>/<FunctionName>.swift`.
///   For other templates (`commutativity`, `associativity`,
///   `identity-element`), record the decision but emit a "no stub
///   writeout available for <template> in v1" note — those templates
///   will gain their writeouts in M8's algebraic-structure cluster.
///   In every case the suggestion's identity-derived seed (M4.3,
///   widened to 256 bits in M5.2.a) is used so re-running the
///   emitted test produces identical trial sequences per PRD §16 #6.
/// - `B` — accept Option B (RefactorBridge conformance). Surfaced
///   only when `context.proposalsByType` carries a proposal for the
///   suggestion's type AND the suggestion contributed signals to it
///   (its identity is in `proposal.relatedIdentities`). Emits a
///   conformance extension via `LiftedConformanceEmitter` (M7.4) and
///   writes to `Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift`.
///   Per the M7 plan's per-type aggregation rule, once the user picks
///   `B` for type `T`, subsequent suggestions on `T` collapse back to
///   `[A/s/n/?]` — the conformance is written, the type is "decided."
/// - `s` — skip. Record `Decision.skipped` so future runs of
///   `--interactive` know the user has acknowledged this suggestion
///   without committing. `drift` (M6.5) will not warn on skipped
///   suggestions — the user has already seen them.
/// - `n` — reject. Record `Decision.rejected`. Future runs hide the
///   suggestion entirely.
/// - `?` — help. Show the legend, re-prompt without advancing.
///
/// Suggestions whose identity already has a recorded decision are
/// skipped silently — this lets the user `--interactive` repeatedly
/// against an evolving corpus and only see new things.
///
/// Per the M6 plan, M5.5's `--dry-run` flag flips meaningful here:
/// when set, `A` shows the would-be file path on stdout but skips
/// both the file write and the decisions update; `s` and `n` skip
/// the decisions update too. The orchestrator returns the
/// `(updatedDecisions, writtenFiles)` tuple regardless; callers
/// that opt into the dry-run path get an empty `writtenFiles` and
/// an `updatedDecisions` equal to the input.
public enum InteractiveTriage {

    /// Outcome of a triage session. `updatedDecisions` reflects every
    /// `A` / `s` / `n` gesture (in production) or matches the input
    /// (in dry-run); `writtenFiles` lists the files actually emitted
    /// (empty in dry-run). Caller writes `updatedDecisions` to disk
    /// via `DecisionsLoader.write` after the session ends — keeping
    /// persistence outside this orchestrator means tests don't need
    /// to mock the filesystem to verify the decisions logic.
    public struct Result: Equatable {
        public let updatedDecisions: Decisions
        public let writtenFiles: [URL]

        public init(updatedDecisions: Decisions, writtenFiles: [URL]) {
            self.updatedDecisions = updatedDecisions
            self.writtenFiles = writtenFiles
        }
    }

    /// Bundle of triage dependencies — keeps `run`'s parameter list
    /// short and lets sub-helpers share the same set without
    /// re-threading individual deps. SwiftLint also caps function
    /// parameter counts at 5; bundling keeps both `run` and
    /// `handleAccept` under that limit.
    public struct Context {
        public let prompt: any PromptInput
        public let output: any DiscoverOutput
        public let diagnostics: any DiagnosticOutput
        public let outputDirectory: URL
        public let dryRun: Bool
        public let clock: @Sendable () -> Date
        /// Per-type RefactorBridge proposals keyed by type name, built
        /// by `RefactorBridgeOrchestrator.proposals(from:)` (M7.5b).
        /// Empty when the caller didn't run the orchestrator (M5.x and
        /// earlier non-CLI consumers); the prompt loop falls back to
        /// the M6.4 `[A/s/n/?]` shape when no proposal matches.
        public let proposalsByType: [String: RefactorBridgeProposal]

        public init(
            prompt: any PromptInput,
            output: any DiscoverOutput,
            diagnostics: any DiagnosticOutput,
            outputDirectory: URL,
            dryRun: Bool,
            clock: @escaping @Sendable () -> Date = { Date() },
            proposalsByType: [String: RefactorBridgeProposal] = [:]
        ) {
            self.prompt = prompt
            self.output = output
            self.diagnostics = diagnostics
            self.outputDirectory = outputDirectory
            self.dryRun = dryRun
            self.clock = clock
            self.proposalsByType = proposalsByType
        }
    }

    /// Run the prompt loop. `context.outputDirectory` is typically
    /// the package root; the orchestrator appends
    /// `Tests/Generated/SwiftInfer/<TemplateName>/<FunctionName>.swift`
    /// per accepted suggestion. Throws only on filesystem I/O
    /// failures during the file write — the prompt loop itself
    /// never throws.
    /// Mutable state threaded through `processOne`. Bundling
    /// `decisions` + `writtenFiles` + `conformanceWrittenForTypes`
    /// into one inout argument keeps `processOne`'s param count
    /// under SwiftLint's cap of 5. `conformanceWrittenForTypes`
    /// implements the M7.5 per-type aggregation rule (open decision
    /// #7) — once the user picks `B` for type `T`, the prompt for
    /// subsequent suggestions on `T` collapses to `[A/s/n/?]`.
    struct State {
        var decisions: Decisions
        var writtenFiles: [URL]
        var conformanceWrittenForTypes: Set<String>
    }

    public static func run(
        suggestions: [Suggestion],
        existingDecisions: Decisions,
        context: Context
    ) throws -> Result {
        let pending = suggestions.filter { suggestion in
            existingDecisions.record(for: suggestion.identity.normalized) == nil
        }
        if pending.isEmpty {
            context.output.write("No new suggestions to triage.")
            return Result(updatedDecisions: existingDecisions, writtenFiles: [])
        }
        if context.dryRun {
            context.output.write(
                "--dry-run in effect: accept gestures will print the would-be path but not write files."
            )
        }
        var state = State(
            decisions: existingDecisions,
            writtenFiles: [],
            conformanceWrittenForTypes: []
        )
        for (index, suggestion) in pending.enumerated() {
            try processOne(
                suggestion: suggestion,
                position: index + 1,
                total: pending.count,
                state: &state,
                context: context
            )
        }
        return Result(updatedDecisions: state.decisions, writtenFiles: state.writtenFiles)
    }

    private static func processOne(
        suggestion: Suggestion,
        position: Int,
        total: Int,
        state: inout State,
        context: Context
    ) throws {
        context.output.write(SuggestionRenderer.render(suggestion))
        let activeProposal = activeRefactorBridgeProposal(
            for: suggestion,
            state: state,
            context: context
        )
        context.output.write(promptLine(
            position: position,
            total: total,
            proposalAvailable: activeProposal != nil
        ))
        let choice = readChoice(
            prompt: context.prompt,
            output: context.output,
            proposalAvailable: activeProposal != nil
        )
        let decision: Decision
        switch choice {
        case .accept:
            if let path = try handleAccept(suggestion: suggestion, context: context) {
                state.writtenFiles.append(path)
            }
            decision = .accepted
        case .conformance:
            // Guard rail: readChoice only returns `.conformance` when a
            // proposal is offered, so activeProposal is always non-nil here.
            guard let proposal = activeProposal else {
                decision = .skipped
                break
            }
            if let path = try handleConformanceAccept(
                suggestion: suggestion,
                proposal: proposal,
                context: context
            ) {
                state.writtenFiles.append(path)
            }
            state.conformanceWrittenForTypes.insert(proposal.typeName)
            decision = .acceptedAsConformance
        case .skip:
            decision = .skipped
        case .reject:
            decision = .rejected
        }
        if !context.dryRun {
            state.decisions = state.decisions.upserting(makeRecord(
                for: suggestion,
                decision: decision,
                timestamp: context.clock()
            ))
        }
    }

    /// Resolve the RefactorBridge proposal active for `suggestion`, if
    /// any. Three conditions must hold:
    ///   1. `context.proposalsByType` carries a proposal for the
    ///      suggestion's candidate type (extracted via `paramType`).
    ///   2. The suggestion's identity is in `proposal.relatedIdentities`
    ///      — only suggestions that actually contributed signals to the
    ///      proposal get the `B` arm.
    ///   3. The user hasn't already chosen `B` for this type in the
    ///      current run (per-type aggregation per M7 plan open
    ///      decision #7).
    static func activeRefactorBridgeProposal(
        for suggestion: Suggestion,
        state: State,
        context: Context
    ) -> RefactorBridgeProposal? {
        guard let signature = suggestion.evidence.first?.signature,
              let typeName = paramType(from: signature),
              let proposal = context.proposalsByType[typeName],
              proposal.relatedIdentities.contains(suggestion.identity),
              !state.conformanceWrittenForTypes.contains(typeName) else {
            return nil
        }
        return proposal
    }

    // MARK: - Prompt rendering

    static func promptLine(position: Int, total: Int, proposalAvailable: Bool) -> String {
        let arms = proposalAvailable
            ? "Accept (A) / Conformance (B) / Skip (s) / Reject (n) / Help (?)"
            : "Accept (A) / Skip (s) / Reject (n) / Help (?)"
        return "[\(position)/\(total)] \(arms)"
    }

    // MARK: - Prompt-input parsing

    enum Choice {
        case accept, conformance, skip, reject
    }

    /// Read one valid choice from `prompt`, looping on `?` (help) and
    /// invalid input. Returns `.skip` on EOF as a safe default —
    /// piped input running out shouldn't auto-accept anything. `b` is
    /// only recognized when `proposalAvailable` is `true`; otherwise
    /// it falls through to the unrecognized-input branch (so users
    /// don't accidentally trigger a non-existent conformance write).
    static func readChoice(
        prompt: any PromptInput,
        output: any DiscoverOutput,
        proposalAvailable: Bool = false
    ) -> Choice {
        while true {
            output.write("> ")
            guard let line = prompt.readLine() else { return .skip }
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            switch trimmed {
            case "a": return .accept
            case "b" where proposalAvailable: return .conformance
            case "s", "": return .skip // empty line = skip-for-now (default-on-Enter)
            case "n": return .reject
            case "?", "h", "help":
                output.write(helpText(proposalAvailable: proposalAvailable))
            default:
                output.write("Unrecognized input '\(trimmed)'. Type ? for help.")
            }
        }
    }

    static func helpText(proposalAvailable: Bool) -> String {
        var text = """
            A — accept this suggestion. For idempotence / round-trip /
                monotonicity / invariant-preservation, a property-test
                stub is written to
                Tests/Generated/SwiftInfer/<TemplateName>/<FunctionName>.swift.
                For other templates the decision is recorded but no file
                is written (M8 ships the algebraic-structure stubs).
            """
        if proposalAvailable {
            text += "\n"
            text += """
                B — accept Option B (RefactorBridge conformance). A
                    conformance extension is written to
                    Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift.
                    Once chosen for a type, subsequent suggestions on
                    that type collapse to [A/s/n/?].
                """
        }
        text += "\n"
        text += """
            s — skip for now. Re-surfaces in future --interactive runs.
                (Also the default if you press Enter.)
            n — reject. Hides this suggestion from future runs.
            ? — show this help.
            """
        return text
    }

}
