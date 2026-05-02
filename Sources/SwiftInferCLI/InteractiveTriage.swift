import Foundation
import SwiftInferCore

/// `swift-infer discover --interactive` triage orchestrator (M6.4).
/// Walks each surviving suggestion, prompts the user with
/// `[A/s/n/?]`, and dispatches:
///
/// - `A` — accept. For `idempotence` / `round-trip` suggestions,
///   emit a peer `@Test func` via `LiftedTestEmitter` (M6.3) and
///   write it to `Tests/Generated/SwiftInfer/<TemplateName>/<FunctionName>.swift`.
///   For other templates (`commutativity`, `associativity`,
///   `identity-element`), record the decision but emit a "no stub
///   writeout available for <template> in v1" note — `LiftedTestEmitter`
///   only ships `idempotent` + `roundTrip` arms in M6.3, and the
///   M7+ algebraic-structure cluster will own those writeouts.
///   In every case the suggestion's identity-derived seed (M4.3,
///   widened to 256 bits in M5.2.a) is used so re-running the
///   emitted test produces identical trial sequences per PRD §16 #6.
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
/// against an evolving corpus and only see new things. Open decision
/// #1 in the M6 plan defers Option B (RefactorBridge) to M7; the
/// prompt is `[A/s/n/?]`, not `[A/B/s/n/?]`.
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

        public init(
            prompt: any PromptInput,
            output: any DiscoverOutput,
            diagnostics: any DiagnosticOutput,
            outputDirectory: URL,
            dryRun: Bool,
            clock: @escaping @Sendable () -> Date = { Date() }
        ) {
            self.prompt = prompt
            self.output = output
            self.diagnostics = diagnostics
            self.outputDirectory = outputDirectory
            self.dryRun = dryRun
            self.clock = clock
        }
    }

    /// Run the prompt loop. `context.outputDirectory` is typically
    /// the package root; the orchestrator appends
    /// `Tests/Generated/SwiftInfer/<TemplateName>/<FunctionName>.swift`
    /// per accepted suggestion. Throws only on filesystem I/O
    /// failures during the file write — the prompt loop itself
    /// never throws.
    /// Mutable state threaded through `processOne`. Bundling
    /// `decisions` + `writtenFiles` into one inout argument keeps
    /// `processOne`'s param count under SwiftLint's cap of 5.
    private struct State {
        var decisions: Decisions
        var writtenFiles: [URL]
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
        var state = State(decisions: existingDecisions, writtenFiles: [])
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
        context.output.write(
            "[\(position)/\(total)] Accept (A) / Skip (s) / Reject (n) / Help (?)"
        )
        let choice = readChoice(prompt: context.prompt, output: context.output)
        let decision: Decision
        switch choice {
        case .accept:
            if let path = try handleAccept(suggestion: suggestion, context: context) {
                state.writtenFiles.append(path)
            }
            decision = .accepted
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

    // MARK: - Prompt-input parsing

    private enum Choice {
        case accept, skip, reject
    }

    /// Read one valid choice from `prompt`, looping on `?` (help) and
    /// invalid input. Returns `.skip` on EOF as a safe default —
    /// piped input running out shouldn't auto-accept anything.
    private static func readChoice(prompt: any PromptInput, output: any DiscoverOutput) -> Choice {
        while true {
            output.write("> ")
            guard let line = prompt.readLine() else { return .skip }
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            switch trimmed {
            case "a": return .accept
            case "s", "": return .skip // empty line = skip-for-now (default-on-Enter)
            case "n": return .reject
            case "?", "h", "help":
                output.write(helpText)
            default:
                output.write("Unrecognized input '\(trimmed)'. Type ? for help.")
            }
        }
    }

    private static let helpText = """
        A — accept this suggestion. For idempotence / round-trip, a
            property-test stub is written to
            Tests/Generated/SwiftInfer/<TemplateName>/<FunctionName>.swift.
            For other templates the decision is recorded but no file
            is written (M7's RefactorBridge ships the rest).
        s — skip for now. Re-surfaces in future --interactive runs.
            (Also the default if you press Enter.)
        n — reject. Hides this suggestion from future runs.
        ? — show this help.
        """

}
