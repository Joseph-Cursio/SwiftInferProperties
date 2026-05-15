import Foundation
import SwiftInferCore

/// V2.0 M3.C → M3.E — orchestration glue for the in-process
/// interaction verify path. Threads M1's reducer discovery → M1.C's
/// pin resolution → M3.B's stub emission → M3.E's workdir-synthesis
/// → build + run + outcome parsing → rendered five-category outcome.
///
/// **Two entries:**
///   - `resolveAndEmit(target:pinRaw:...:)` — pure, no subprocess.
///     Discovers reducers, applies the pin filter, emits the verifier
///     stub source. Used by tests; consumed by `runPipeline` as the
///     pre-execution leg.
///   - `runPipeline(target:pinRaw:...:)` — the full path. Wraps
///     `resolveAndEmit` + `executeAndParse` + outcome render. The
///     CLI subcommand (M3.D) calls this.
public enum VerifyInteractionPipeline {

    /// V2.0 M3.C — pure leg: discover candidates, apply pin filter,
    /// emit the stub source. No subprocess; no disk writes outside
    /// the source-tree walk. Returns the resolved candidate plus
    /// the M3.B-emitted main.swift source so callers can route into
    /// the build/run leg (M3.E) or render a dry-run stub-only output
    /// (the M3.C ship before M3.E landed).
    public static func resolveAndEmit(
        target: String,
        pinRaw: String? = nil,
        sequenceCount: Int = ActionSequenceStubEmitter.defaultSequenceCount,
        userModuleName: String? = nil,
        workingDirectory: URL
    ) throws -> (candidate: ReducerCandidate, stubSource: String) {
        let directory = workingDirectory
            .appendingPathComponent("Sources")
            .appendingPathComponent(target)
        let candidates = try ReducerDiscoverer.discover(directory: directory)
        let matched = try resolveCandidate(candidates: candidates, pinRaw: pinRaw)
        let resolvedModuleName = userModuleName ?? target
        let inputs = ActionSequenceStubEmitter.Inputs(
            candidate: matched,
            userModuleName: resolvedModuleName,
            sequenceCount: sequenceCount
        )
        let stubSource: String
        do {
            stubSource = try ActionSequenceStubEmitter.emit(inputs)
        } catch let error as ActionSequenceStubEmitter.EmitError {
            throw VerifyInteractionError.unsupported(reason: error.description)
        }
        return (matched, stubSource)
    }

    /// V2.0 M3.E.4 — full path: resolveAndEmit → synthesize a
    /// workdir under `<packageRoot>/.swiftinfer/verify-interaction-workdir/`
    /// → `swift build` → run the verifier binary → parse outcome
    /// via `InteractionVerifyOutcomeParser` → render in the v1.42
    /// five-category format.
    ///
    /// **Until SwiftPropertyLaws v2.2.0 is published on remote**:
    /// the synthesized workdir's `swift build` step will fail to
    /// resolve the kit pin and the outcome surfaces as
    /// `.architecturalCoveragePending` with a "kit pin v2.2.0 not yet
    /// available" detail. This is normal — see
    /// `docs/calibration-cycle-73-findings.md` "kit-tag-publication
    /// gap" for the next-action.
    public static func runPipeline(
        target: String,
        pinRaw: String? = nil,
        sequenceCount: Int = ActionSequenceStubEmitter.defaultSequenceCount,
        userModuleName: String? = nil,
        workingDirectory: URL
    ) throws -> String {
        let (candidate, stubSource) = try resolveAndEmit(
            target: target,
            pinRaw: pinRaw,
            sequenceCount: sequenceCount,
            userModuleName: userModuleName,
            workingDirectory: workingDirectory
        )
        let result = try executeAndParse(
            candidate: candidate,
            stubSource: stubSource,
            userModuleName: userModuleName ?? target,
            workingDirectory: workingDirectory
        )
        return renderOutcome(candidate: candidate, result: result)
    }

    // MARK: - Pin resolution

    /// V2.0 M3.C — pin-resolution sub-step. Pulled to a static so
    /// tests can drive it without the directory walk. Errors map
    /// 1:1 with the user-facing failure modes.
    static func resolveCandidate(
        candidates: [ReducerCandidate],
        pinRaw: String?
    ) throws -> ReducerCandidate {
        if let pinRaw {
            let pin = try ReducerPin.parse(pinRaw)
            let matched = candidates.filter { pin.matches($0) }
            switch matched.count {
            case 0:
                throw VerifyInteractionError.noMatchingReducer(pin: pinRaw)
            case 1:
                return matched[0]
            default:
                throw VerifyInteractionError.ambiguousPin(
                    pin: pinRaw,
                    matches: matched.map(\.qualifiedName)
                )
            }
        }
        switch candidates.count {
        case 0:
            throw VerifyInteractionError.noReducersDetected
        case 1:
            return candidates[0]
        default:
            throw VerifyInteractionError.requiresPin(
                candidates: candidates.map(\.qualifiedName)
            )
        }
    }

    // MARK: - Build + run + parse (M3.E.4)

    /// V2.0 M3.E.4 — synthesize the workdir, run `swift build`, run
    /// the resulting binary, parse the outcome. Returns the
    /// classified result; the caller renders it.
    static func executeAndParse(
        candidate: ReducerCandidate,
        stubSource: String,
        userModuleName: String,
        workingDirectory: URL
    ) throws -> InteractionVerifyOutcomeParser.Result {
        let packageRoot = findPackageRoot(startingFrom: workingDirectory) ?? workingDirectory
        let workdir = packageRoot
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("verify-interaction-workdir")
            .appendingPathComponent(workdirSegment(for: candidate))
        let userPackage = VerifierWorkdir.UserPackageReference(
            packagePath: packageRoot,
            packageDeclaredName: userModuleName,
            productNames: [userModuleName]
        )
        let workdirInputs = VerifierWorkdir.Inputs(
            workdir: workdir,
            userPackage: userPackage,
            stubSource: stubSource,
            mode: .interaction
        )
        _ = try VerifierWorkdir.synthesize(workdirInputs)

        let buildOutput = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
        if buildOutput.exitCode != 0 {
            return InteractionVerifyOutcomeParser.parseBuildFailure(
                buildExitCode: buildOutput.exitCode,
                stderr: buildOutput.stderr
            )
        }
        let runOutput = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
        return InteractionVerifyOutcomeParser.parseRunOutput(
            binaryExitCode: runOutput.exitCode,
            stdout: runOutput.stdout
        )
    }

    /// Walk up from `directory` looking for `Package.swift`. Same
    /// shape as v1.42 verify's package-root resolution + every other
    /// loader in the project — kept inlined here for the same
    /// independent-loader posture.
    static func findPackageRoot(startingFrom directory: URL) -> URL? {
        var current = directory.standardizedFileURL
        while true {
            let manifest = current.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: manifest.path) {
                return current
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent == current {
                return nil
            }
            current = parent
        }
    }

    /// Filename-safe workdir segment derived from the candidate's
    /// qualified name. `.` → `_` so a candidate `Inbox.body` lands
    /// under `verify-interaction-workdir/Inbox_body/`. Mirrors
    /// v1.42's `workdirSegment(for:)` posture (hash-prefix-based
    /// there; name-based here since interaction-verify has no
    /// stable identity hash yet).
    static func workdirSegment(for candidate: ReducerCandidate) -> String {
        candidate.qualifiedName.replacingOccurrences(of: ".", with: "_")
    }

    // MARK: - Outcome render

    /// V2.0 M3.E.4 — five-category outcome rendering. Mirrors
    /// `VerifyResultRenderer.render` shape but for interaction-
    /// invariant outcomes. M3.0 doesn't ship verify-evidence
    /// persistence — that comes alongside M9's `metrics --interaction`
    /// consumer.
    static func renderOutcome(
        candidate: ReducerCandidate,
        result: InteractionVerifyOutcomeParser.Result
    ) -> String {
        let header = [
            "swift-infer verify-interaction — V2.0 M3.E (in-process):",
            "  Reducer: \(candidate.qualifiedName)",
            "  Carrier: \(candidate.carrierKind.rawValue)",
            "  Signature: \(candidate.signatureShape.rawValue)",
            "  State: \(candidate.stateTypeName)",
            "  Action: \(candidate.actionTypeName)",
            "",
            "  Outcome: \(result.outcome.rawValue)"
        ]
        var lines = header
        if let totalRuns = result.totalRuns, let clean = result.cleanRuns {
            lines.append("  Total runs: \(totalRuns)")
            lines.append("  Clean runs: \(clean)")
        }
        if let detail = result.detail {
            lines.append("  Detail: \(detail)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// V2.0 M3.C — errors thrown by the interaction-verify pipeline.
/// Hoisted to file scope for the SwiftLint nesting cap; public so
/// tests can pattern-match on the case rather than the rendered text.
public enum VerifyInteractionError: Error, CustomStringConvertible, Equatable {
    case noReducersDetected
    case noMatchingReducer(pin: String)
    case ambiguousPin(pin: String, matches: [String])
    case requiresPin(candidates: [String])
    case unsupported(reason: String)

    public var description: String {
        switch self {
        case .noReducersDetected:
            return "swift-infer verify-interaction: no reducer-shaped functions detected in target."
        case let .noMatchingReducer(pin):
            return "swift-infer verify-interaction: no reducer matches pin '\(pin)'."
        case let .ambiguousPin(pin, matches):
            return "swift-infer verify-interaction: pin '\(pin)' is ambiguous — matches "
                + "\(matches.count) reducers: \(matches.joined(separator: ", ")). "
                + "Lengthen the pin to disambiguate."
        case let .requiresPin(candidates):
            return "swift-infer verify-interaction: \(candidates.count) reducer candidates "
                + "detected. Pin one via --reducer <typeName>.<funcName>. "
                + "Candidates: \(candidates.joined(separator: ", "))"
        case let .unsupported(reason):
            return "swift-infer verify-interaction: \(reason)"
        }
    }
}
