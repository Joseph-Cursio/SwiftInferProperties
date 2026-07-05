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
            directory — mirrors `swift-infer discover-reducers`. \
            Repeatable: with --all (M3), pass --target more than once to \
            survey reducers across several modules in one run, each verified \
            against its own library product.
            """
        )
        public var target: [String] = []

        @Option(
            name: .long,
            help: """
            Optional `<typeName>.<funcName>` (or just `<funcName>` \
            for free functions) pin selecting which reducer to \
            verify. Required when ≥ 2 reducer-shaped functions are \
            detected; zero / multiple matches are an error. Module-\
            prefixed pins (`MyModule.Inbox.body`) disambiguate across \
            modules (M3); the single-reducer path verifies within the \
            first --target.
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
            narrow with --family. Bounded-parallel (see --max-parallel).
            """
        )
        public var all: Bool = false

        @Option(
            name: .long,
            help: """
            With --all, the maximum number of identities verified \
            concurrently. Each is a real `swift build`, so concurrent \
            builds contend for cores; default 4 (matches the algebraic \
            `verify --all-from-index` survey). No-op without --all.
            """
        )
        public var maxParallel: Int = 4

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

        /// M3 — `--target` became a repeatable `[String]` (an empty array is a
        /// valid *parse*), so enforce "at least one" here; ArgumentParser calls
        /// `validate()` after decoding and before `run()`.
        public func validate() throws {
            guard !target.isEmpty else {
                throw ValidationError("at least one --target is required.")
            }
        }

        public func run() async throws {
            let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            if all {
                if reducer != nil {
                    FileHandle.standardError.write(
                        Data("warning: --reducer is ignored in --all survey mode\n".utf8)
                    )
                }
                // M3 — survey across every --target module, each verified
                // against its own product.
                let rendered = try await VerifyInteractionSurvey.run(
                    targets: target,
                    familyFilter: family,
                    sequenceCount: sequenceCount,
                    userModuleName: userModule,
                    maxParallel: maxParallel,
                    workingDirectory: workingDirectory
                )
                print(rendered, terminator: "")
                // Observable Carrier (milestone S4) — additive ViewModel verify
                // pass: execution-back the @Observable carriers in each target
                // (previously discover-only at `.possible`) and append their
                // VERIFIED / REFUTED verdicts. Guarded (`try?`) so it never
                // destabilizes the reducer survey output.
                let packageRoot = VerifyInteractionPipeline
                    .findPackageRoot(startingFrom: workingDirectory) ?? workingDirectory
                for module in target {
                    let sourceDir = workingDirectory
                        .appendingPathComponent("Sources")
                        .appendingPathComponent(module)
                    let vmRender = (try? ViewModelVerifyInteractionSurvey.runLive(
                        sourceDirectory: sourceDir,
                        userModuleName: module,
                        packageRoot: packageRoot,
                        workdirRoot: packageRoot
                    )) ?? ""
                    print(vmRender, terminator: "")
                }
                return
            }
            // Single-reducer path: multi-target only applies to --all; verify
            // within the first target (a module-prefixed --reducer still
            // disambiguates if it resolves there).
            if target.count > 1 {
                FileHandle.standardError.write(Data(
                    "warning: multiple --target only apply with --all; using '\(target[0])'\n".utf8
                ))
            }
            let rendered = try VerifyInteractionPipeline.runPipeline(
                target: target[0],
                pinRaw: reducer,
                sequenceCount: sequenceCount,
                userModuleName: userModule,
                workingDirectory: workingDirectory
            )
            print(rendered, terminator: "")
        }
    }
}
