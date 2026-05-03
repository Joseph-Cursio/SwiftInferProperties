import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// `swift-infer discover --interactive` triage orchestrator (M6.4 +
/// M7.5 RefactorBridge extension). Walks each surviving suggestion,
/// prompts the user with `[A/s/n/?]` (or `[A/B/s/n/?]` when a
/// `RefactorBridgeProposal` is attached to the suggestion's type per
/// the M7.5 orchestrator), and dispatches:
///
/// - `A` — accept Option A. For `idempotence` / `round-trip` /
///   `monotonicity` / `invariant-preservation` suggestions, emit a
///   peer `@Test func` via `LiftedTestEmitter` (M6.3 + M7.3) and
///   write it to `Tests/Generated/SwiftInfer/<TemplateName>/<FunctionName>.swift`.
///   In every case the suggestion's identity-derived seed (M4.3,
///   widened to 256 bits in M5.2.a) is used so re-running the
///   emitted test produces identical trial sequences per PRD §16 #6.
/// - `B` / `B'` — accept Option B (RefactorBridge conformance).
///   Surfaced only when `context.proposalsByType` carries a proposal
///   for the suggestion's type AND the suggestion contributed signals
///   to it (its identity is in `proposal.relatedIdentities`). Emits a
///   conformance extension via `LiftedConformanceEmitter` (M7.4) and
///   writes to `Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift`.
///   Per the M7 plan's per-type aggregation rule, once the user picks
///   `B` for type `T`, subsequent suggestions on `T` collapse back to
///   `[A/s/n/?]` — the conformance is written, the type is "decided."
/// - `s` — skip. Record `Decision.skipped`. `drift` (M6.5) will not
///   warn on skipped suggestions.
/// - `n` — reject. Record `Decision.rejected`. Future runs hide the
///   suggestion entirely.
/// - `?` — help. Show the legend, re-prompt without advancing.
///
/// Suggestions whose identity already has a recorded decision are
/// skipped silently. Per the M6 plan, M5.5's `--dry-run` flag flips
/// meaningful here: when set, `A` shows the would-be file path on
/// stdout but skips both the file write and the decisions update.
public enum InteractiveTriage {

    /// Outcome of a triage session. `updatedDecisions` reflects every
    /// `A` / `s` / `n` gesture (in production) or matches the input
    /// (in dry-run); `writtenFiles` lists the files actually emitted
    /// (empty in dry-run).
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
        /// by `RefactorBridgeOrchestrator.proposals(from:)` (M7.5b +
        /// M8.4.b.1). Each value is a list — M7.5 emitted a single
        /// proposal per type; M8.4.b.1 widens to list-shaped for
        /// incomparable arms (CommutativeMonoid + Group on the same
        /// type) and primary/secondary pairs (Semilattice + SetAlgebra
        /// when curated set-named ops fire). The prompt loop renders
        /// position 0 as `B` and position 1 as `B'` in the extended
        /// `[A/B/B'/s/n/?]` prompt.
        ///
        /// Empty when the caller didn't run the orchestrator (M5.x and
        /// earlier non-CLI consumers); the prompt loop falls back to
        /// the M6.4 `[A/s/n/?]` shape when no proposal matches.
        public let proposalsByType: [String: [RefactorBridgeProposal]]

        public init(
            prompt: any PromptInput,
            output: any DiscoverOutput,
            diagnostics: any DiagnosticOutput,
            outputDirectory: URL,
            dryRun: Bool,
            clock: @escaping @Sendable () -> Date = { Date() },
            proposalsByType: [String: [RefactorBridgeProposal]] = [:]
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

    /// Mutable state threaded through `processOne`. Bundling
    /// `decisions` + `writtenFiles` + `conformanceWrittenForTypes`
    /// into one inout argument keeps `processOne`'s param count
    /// under SwiftLint's cap of 5. `conformanceWrittenForTypes`
    /// implements the M7.5 per-type aggregation rule.
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
        let activeProposals = activeRefactorBridgeProposals(
            for: suggestion,
            state: state,
            context: context
        )
        context.output.write(promptLine(
            position: position,
            total: total,
            primaryAvailable: !activeProposals.isEmpty,
            secondaryAvailable: activeProposals.count >= 2
        ))
        let choice = readChoice(
            prompt: context.prompt,
            output: context.output,
            primaryAvailable: !activeProposals.isEmpty,
            secondaryAvailable: activeProposals.count >= 2
        )
        let decision = try resolveChoice(
            choice: choice,
            suggestion: suggestion,
            activeProposals: activeProposals,
            state: &state,
            context: context
        )
        if !context.dryRun {
            state.decisions = state.decisions.upserting(makeRecord(
                for: suggestion,
                decision: decision,
                timestamp: context.clock()
            ))
        }
    }

    /// Convert a parsed `Choice` into a `Decision`, side-effecting on
    /// state (writing files, recording conformance-written types) as
    /// needed.
    private static func resolveChoice(
        choice: Choice,
        suggestion: Suggestion,
        activeProposals: [RefactorBridgeProposal],
        state: inout State,
        context: Context
    ) throws -> Decision {
        switch choice {
        case .accept:
            if let path = try handleAccept(suggestion: suggestion, context: context) {
                state.writtenFiles.append(path)
            }
            return .accepted
        case .conformance:
            return try acceptConformance(
                proposal: activeProposals.first,
                suggestion: suggestion,
                state: &state,
                context: context
            )
        case .conformancePrime:
            // activeProposals.count >= 2 is the readChoice gate
            // condition; defensively read the index.
            let secondary = activeProposals.count >= 2 ? activeProposals[1] : nil
            return try acceptConformance(
                proposal: secondary,
                suggestion: suggestion,
                state: &state,
                context: context
            )
        case .skip:
            return .skipped
        case .reject:
            return .rejected
        }
    }

    /// Shared accept-conformance side-effect path — `handleConformanceAccept`
    /// for the file write + `conformanceWrittenForTypes` update +
    /// decision outcome. Single source of truth for the `.conformance`
    /// and `.conformancePrime` arms; both differ only in which
    /// proposal index they pluck from `activeProposals`.
    private static func acceptConformance(
        proposal: RefactorBridgeProposal?,
        suggestion: Suggestion,
        state: inout State,
        context: Context
    ) throws -> Decision {
        guard let proposal else { return .skipped }
        if let path = try handleConformanceAccept(
            suggestion: suggestion,
            proposal: proposal,
            context: context
        ) {
            state.writtenFiles.append(path)
        }
        state.conformanceWrittenForTypes.insert(proposal.typeName)
        return .acceptedAsConformance
    }

    /// Resolve the RefactorBridge proposals active for `suggestion`,
    /// if any. M7.5 returned at most one proposal per type; M8.4.b.1
    /// returns up to two — position 0 is the primary (`B`), position 1
    /// is the secondary (`B'`). Three conditions must hold for each
    /// proposal in the type's list:
    ///   1. `context.proposalsByType` carries a list for the
    ///      suggestion's candidate type (extracted via `paramType`).
    ///   2. The suggestion's identity is in `proposal.relatedIdentities`
    ///      — only suggestions that actually contributed signals to the
    ///      proposal get the `B` / `B'` arm.
    ///   3. The user hasn't already chosen any conformance for this
    ///      type in the current run (per-type aggregation per M7 plan
    ///      open decision #7 — preserved for M8.4.b.1).
    static func activeRefactorBridgeProposals(
        for suggestion: Suggestion,
        state: State,
        context: Context
    ) -> [RefactorBridgeProposal] {
        guard let signature = suggestion.evidence.first?.signature,
              let typeName = paramType(from: signature),
              let proposals = context.proposalsByType[typeName],
              !state.conformanceWrittenForTypes.contains(typeName) else {
            return []
        }
        return proposals.filter { proposal in
            proposal.relatedIdentities.contains(suggestion.identity)
        }
    }
}
