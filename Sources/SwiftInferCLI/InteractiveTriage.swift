import Foundation
import SwiftInferCore
import SwiftInferTemplates

// swiftlint:disable file_length type_body_length
// M8.4.b.1 extended the prompt UX to `[A/B/B'/s/n/?]` and the Choice
// enum to four cases, with extracted `resolveChoice` + `acceptConformance`
// helpers keeping `processOne` under the complexity cap. The InteractiveTriage
// enum's body now exceeds the 250-line cap; splitting further would
// scatter the prompt-UI surface across multiple files.

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
        /// by `RefactorBridgeOrchestrator.proposals(from:)` (M7.5b +
        /// M8.4.b.1). Each value is a list — M7.5 emitted a single
        /// proposal per type; M8.4.b.1 widens to list-shaped for
        /// incomparable arms (CommutativeMonoid + Group on the same
        /// type) and primary/secondary pairs (Semilattice + SetAlgebra
        /// when curated set-named ops fire). The prompt loop renders
        /// position 0 as `B` and position 1 as `B'` in the extended
        /// `[A/B/B'/s/n/?]` prompt; positions ≥ 2 aren't currently
        /// surfaced (no M8 promotion produces ≥ 3 proposals per type).
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
    /// needed. Extracted from `processOne` to keep the latter under
    /// SwiftLint's complexity + body-length caps after M8.4.b.1 added
    /// the `.conformancePrime` arm.
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

    /// Shared accept-conformance side-effect path — handleConformanceAccept
    /// for the file write + conformanceWrittenForTypes update + decision
    /// outcome. Single source of truth for the .conformance and
    /// .conformancePrime arms; both differ only in which proposal index
    /// they pluck from `activeProposals`.
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
    /// returns up to two — position 0 is the primary (`B`),
    /// position 1 is the secondary (`B'`). Three conditions must hold
    /// for each proposal in the type's list:
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

    // MARK: - Prompt rendering

    /// Compose the prompt line. M6.4 ships `[A/s/n/?]`; M7.5b extends
    /// to `[A/B/s/n/?]` when a primary proposal is attached; M8.4.b.1
    /// further extends to `[A/B/B'/s/n/?]` when a secondary proposal
    /// is also attached (incomparable arms or the SetAlgebra
    /// secondary). `B` and `B'` arms are ordered per the proposals
    /// list — position 0 is primary, position 1 is secondary.
    static func promptLine(
        position: Int,
        total: Int,
        primaryAvailable: Bool,
        secondaryAvailable: Bool = false
    ) -> String {
        let arms: String
        if primaryAvailable && secondaryAvailable {
            arms = "Accept (A) / Conformance (B) / Conformance' (B') "
                + "/ Skip (s) / Reject (n) / Help (?)"
        } else if primaryAvailable {
            arms = "Accept (A) / Conformance (B) / Skip (s) / Reject (n) / Help (?)"
        } else {
            arms = "Accept (A) / Skip (s) / Reject (n) / Help (?)"
        }
        return "[\(position)/\(total)] \(arms)"
    }

    // MARK: - Prompt-input parsing

    enum Choice {
        case accept, conformance, conformancePrime, skip, reject
    }

    /// Read one valid choice from `prompt`, looping on `?` (help) and
    /// invalid input. Returns `.skip` on EOF as a safe default —
    /// piped input running out shouldn't auto-accept anything. `b` is
    /// only recognized when `primaryAvailable` is `true`; `b'` and `c`
    /// (typing-friendly alias) are only recognized when
    /// `secondaryAvailable` is `true`. Unrecognized input falls
    /// through (so users
    /// don't accidentally trigger a non-existent conformance write).
    static func readChoice(
        prompt: any PromptInput,
        output: any DiscoverOutput,
        primaryAvailable: Bool = false,
        secondaryAvailable: Bool = false
    ) -> Choice {
        while true {
            output.write("> ")
            guard let line = prompt.readLine() else { return .skip }
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            switch trimmed {
            case "a": return .accept
            case "b" where primaryAvailable: return .conformance
            // M8.4.b.1 — `b'` matches the rendered prompt notation
            // verbatim; `c` is a typing-friendly alias since some
            // terminals/keyboards make the apostrophe awkward.
            case "b'" where secondaryAvailable: return .conformancePrime
            case "c" where secondaryAvailable: return .conformancePrime
            case "s", "": return .skip // empty line = skip-for-now (default-on-Enter)
            case "n": return .reject
            case "?", "h", "help":
                output.write(helpText(
                    primaryAvailable: primaryAvailable,
                    secondaryAvailable: secondaryAvailable
                ))
            default:
                output.write("Unrecognized input '\(trimmed)'. Type ? for help.")
            }
        }
    }

    static func helpText(
        primaryAvailable: Bool,
        secondaryAvailable: Bool = false
    ) -> String {
        var text = """
            A — accept this suggestion. For idempotence / round-trip /
                monotonicity / invariant-preservation / commutativity /
                associativity / identity-element / inverse-pair, a
                property-test stub is written to
                Tests/Generated/SwiftInfer/<TemplateName>/<FunctionName>.swift.
            """
        if primaryAvailable {
            text += "\n"
            text += """
                B — accept Option B (RefactorBridge conformance). A
                    conformance extension is written to
                    Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift.
                    Once chosen for a type, subsequent suggestions on
                    that type collapse to [A/s/n/?].
                """
        }
        if secondaryAvailable {
            text += "\n"
            text += """
                B' — accept the secondary RefactorBridge conformance
                    (incomparable arms or stdlib secondary like
                    SetAlgebra). Type `b'` or `c` (alias). Same
                    writeout shape as B; once chosen for a type,
                    subsequent suggestions on that type collapse to
                    [A/s/n/?].
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
// swiftlint:enable file_length type_body_length
