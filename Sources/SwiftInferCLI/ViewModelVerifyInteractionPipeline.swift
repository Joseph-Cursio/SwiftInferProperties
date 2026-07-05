import Foundation
import SwiftInferCore

/// PROTOTYPE — execution-backed interaction verify for `@Observable` carriers
/// (Observable Carrier milestone, Slice 1). The sibling of the reducer
/// `VerifyInteractionPipeline`: it takes a `ViewModelCandidate` + a resolved
/// invariant predicate, emits the M1′ multi-step verifier
/// (`ViewModelActionSequenceStubEmitter`), builds a kit-linked `.interaction`
/// workdir with the model **inlined** into the verifier target, runs it, and
/// maps the `VERIFY_*` markers to a `VerifyOutcome`.
///
/// **Injectable runner.** The build+run step is a closure (`VerifyRunner`) so
/// the routing/gating/emit logic is unit-testable without spawning a real
/// `swift build`. `liveRunner()` is the production seam (workdir synthesize →
/// subprocess build → subprocess run → parse); tests inject a canned outcome.
public enum ViewModelVerifyInteractionPipeline {

    /// Build + run a stub against an inlined model, yielding a `VerifyOutcome`.
    /// `throws` for I/O / process failures; a *build* failure is reported as
    /// `.error` inside the outcome, not thrown.
    public typealias VerifyRunner = @Sendable (
        _ stubSource: String,
        _ inlinedSources: [CorpusPackager.SourceFile],
        _ workdir: URL
    ) throws -> VerifyOutcome

    /// The result of a single candidate × invariant verify attempt.
    public enum StepResult: Equatable, Sendable {
        /// The verifier was emitted, built, and run — carrying its outcome.
        case ran(VerifyOutcome)
        /// The candidate was not verifiable; `reason` is human-facing
        /// (disclosed, never a silent drop).
        case skipped(reason: String)
    }

    /// Resolve → gate → emit → run one candidate against one predicate.
    ///
    /// - `predicate`: the invariant over a `probe` instance (from the
    ///   `ViewModel*Resolver` family — resolution stays with the resolvers;
    ///   this pipeline orchestrates).
    /// - `sourceFiles`: the candidate's originating source, compiled into the
    ///   verifier target so `Type()` is in-module (used by the *inlined* runner;
    ///   empty for the *imported* runner).
    /// - `userModuleName`: `nil` (inlined — model in the verifier target) or the
    ///   module to `import` (imported — model in a path-dependency product).
    ///   Must match the runner's workdir shape.
    public static func verify(
        candidate: ViewModelCandidate,
        predicate: String,
        sourceFiles: [CorpusPackager.SourceFile],
        userModuleName: String? = nil,
        workdir: URL,
        runner: VerifyRunner
    ) -> StepResult {
        // Gate 1 — the verifier must construct `Type()`.
        if case let .requiresArguments(fields) = candidate.constructibility {
            return .skipped(
                reason: "\(candidate.typeName): not zero-arg constructible — "
                    + "requires \(fields.joined(separator: ", "))"
            )
        }

        // Gate 2 — emit the M1′ verifier over the (inlined) model.
        let stub: String
        do {
            stub = try ViewModelActionSequenceStubEmitter.emit(
                ViewModelActionSequenceStubEmitter.Inputs(
                    typeName: candidate.typeName,
                    userModuleName: userModuleName,
                    predicate: predicate,
                    actions: candidate.actions
                )
            )
        } catch {
            return .skipped(reason: "\(candidate.typeName): \(error)")
        }

        // Build + run (injected).
        do {
            return .ran(try runner(stub, sourceFiles, workdir))
        } catch {
            return .skipped(reason: "\(candidate.typeName): verifier run failed — \(error)")
        }
    }

    /// The production runner: synthesize a kit-linked `.interaction` workdir
    /// with `inlinedSources`, `swift build`, run the binary, parse the markers.
    public static func liveRunner() -> VerifyRunner {
        { stubSource, inlinedSources, workdir in
            _ = try VerifierWorkdir.synthesize(
                VerifierWorkdir.Inputs(
                    workdir: workdir,
                    userPackage: nil,
                    stubSource: stubSource,
                    mode: .interaction,
                    inlinedSources: inlinedSources
                )
            )
            let build = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
            guard build.exitCode == 0 else {
                return .error(reason: "build failed: \(build.stderr)")
            }
            let run = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
            return VerifyResultParser.parse(run)
        }
    }

    /// The runner for a **real user package**: the model stays in its own
    /// module (imported, not inlined), reached via a `.package(path:)`
    /// dependency on `userPackage`. Pair with `verify(..., userModuleName: <the
    /// module>)` so the emitted stub imports it. `inlinedSources` is ignored.
    public static func importedRunner(
        userPackage: VerifierWorkdir.UserPackageReference
    ) -> VerifyRunner {
        { stubSource, _, workdir in
            _ = try VerifierWorkdir.synthesize(
                VerifierWorkdir.Inputs(
                    workdir: workdir,
                    userPackage: userPackage,
                    stubSource: stubSource,
                    mode: .interaction,
                    inlinedSources: []
                )
            )
            let build = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
            guard build.exitCode == 0 else {
                return .error(reason: "build failed: \(build.stderr)")
            }
            let run = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
            return VerifyResultParser.parse(run)
        }
    }
}
