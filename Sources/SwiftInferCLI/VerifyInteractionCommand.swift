import ArgumentParser
import Foundation
import SwiftInferCore

/// V2.0 M3.D — `swift-infer verify-interaction` subcommand surface.
///
/// **What it does.** Discovers reducer-shaped functions under
/// `Sources/<target>/`, applies the optional `--reducer` pin, emits
/// a verifier `main.swift` source via M3.B's `ActionSequenceStubEmitter`,
/// and renders the result. At M3.C/M3.D ship (this cycle), the
/// rendered output is "stub emitted, harness pending kit publication"
/// — the build-and-run loop lands at M3.E once the SwiftPropertyLaws
/// v2.2.0 tag is published. See `docs/calibration-cycle-73-findings.md`
/// "kit-tag-publication gap" for the next-action.
///
/// **CLI shape mirrors v1's verify-as-separate-subcommand posture.**
/// PRD v2.0 §3.6 step 5 sketches this as a `--interaction` flag on
/// the existing `verify`; v1.42's `verify` is rooted around a
/// suggestion-hash-prefix lookup against the SemanticIndex, so a
/// `--interaction` mode would force a structurally different output
/// path. Separate `verify-interaction` subcommand keeps the
/// boundaries clean — same posture as `discover-reducers`
/// (M1.A.3) vs `discover`.
extension SwiftInferCommand {

    public struct VerifyInteraction: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "verify-interaction",
            abstract: "Build + run a verifier executable against a "
                + "discovered reducer to check it doesn't trap under "
                + "random action sequences (PRD v2.0 §7.2). Opt-in / "
                + "human-driven; the in-process verify counterpart to "
                + "v1.42's algebraic-property `verify`."
        )

        @Option(
            name: .long,
            help: """
            Name of the SwiftPM target containing the reducer. \
            Resolved to Sources/<target>/ relative to the working \
            directory — mirrors `swift-infer discover-reducers`.
            """
        )
        public var target: String

        @Option(
            name: .long,
            help: """
            Optional `<typeName>.<funcName>` (or just `<funcName>` \
            for free functions) pin selecting which reducer to \
            verify. Required when ≥ 2 reducer-shaped functions are \
            detected; zero / multiple matches are an error. Module-\
            prefixed pins (`MyModule.Inbox.body`) defer to M2+ when \
            multi-module plumbing lands.
            """
        )
        public var reducer: String?

        @Option(
            name: .long,
            help: """
            Override the user module name imported by the synthesized \
            verifier stub. Defaults to the target name. Set this when \
            the SwiftPM target name doesn't match the actual module \
            name (rare).
            """
        )
        public var userModule: String?

        @Option(
            name: .long,
            help: """
            Number of action sequences the synthesized verifier runs \
            in one invocation. Default 1024 matches PRD §15's "1k \
            action sequences" perf-budget target. Tighten for faster \
            smoke tests, widen for longer fuzzing campaigns.
            """
        )
        public var sequenceCount: Int = ActionSequenceStubEmitter.defaultSequenceCount

        @Flag(
            name: .long,
            help: """
            Survey mode (cycle 114): discover every interaction-invariant \
            identity in --target, run measured verify against each, record \
            evidence to .swiftinfer/verify-evidence.json, and print a \
            per-identity outcome summary. The campaign harvest step — one \
            command instead of N hand-pinned runs. Ignores --reducer; \
            narrow with --family. Serial (a real build per identity).
            """
        )
        public var all: Bool = false

        @Option(
            name: .long,
            help: """
            With --all, restrict the survey to one interaction-invariant \
            family (e.g. `idempotence`). Unknown values are an error. \
            No-op without --all.
            """
        )
        public var family: String?

        public init() { /* no-op */ }

        public func run() async throws {
            let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            if all {
                if reducer != nil {
                    FileHandle.standardError.write(
                        Data("warning: --reducer is ignored in --all survey mode\n".utf8)
                    )
                }
                let rendered = try VerifyInteractionSurvey.run(
                    target: target,
                    familyFilter: family,
                    sequenceCount: sequenceCount,
                    userModuleName: userModule,
                    workingDirectory: workingDirectory
                )
                print(rendered, terminator: "")
                return
            }
            let rendered = try VerifyInteractionPipeline.runPipeline(
                target: target,
                pinRaw: reducer,
                sequenceCount: sequenceCount,
                userModuleName: userModule,
                workingDirectory: workingDirectory
            )
            print(rendered, terminator: "")
        }
    }
}
