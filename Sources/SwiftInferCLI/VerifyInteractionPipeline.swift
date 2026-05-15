import Foundation
import SwiftInferCore

/// V2.0 M3.C — orchestration glue for the in-process interaction
/// verify path. Threads M1's reducer discovery → M1.C's pin
/// resolution → M3.B's stub emission. Returns a rendered outcome
/// string the CLI prints.
///
/// **M3.C scope.** Stub emission only. The workdir-synthesis +
/// `swift build` + binary-run integration that v1.42's VerifyCommand
/// uses for round-trip verify isn't reused here yet — that path bakes
/// in SwiftPropertyLaws v2.1.0 + PropertyLawComplex dependencies that
/// interaction verify doesn't need (it needs v2.2.0+ for the
/// ActionSequenceFactory / StatefulGuard surface). Workdir/build/run
/// integration follows in an M3.E sub-cycle once the v2.2.0 kit tag
/// is published.
///
/// **The clean ship today**: surface the emitted stub source + a
/// "pending kit publication" outcome that names what's left. Once
/// the kit tag publishes, M3.E adds the build/run loop and the
/// outcome flows through the v1.42 five-category scheme.
public enum VerifyInteractionPipeline {

    /// V2.0 M3.C — pipeline entry. Tests drive it without going
    /// through the AsyncParsableCommand shell.
    ///
    /// Pipeline steps:
    ///   1. Discover reducers under `Sources/<target>/` via
    ///      `ReducerDiscoverer.discover(directory:)`.
    ///   2. If `pinRaw` is present, parse it via `ReducerPin.parse`
    ///      and filter the candidate list. Zero / multiple matches
    ///      throw clear errors. When `pinRaw` is `nil` and the target
    ///      has more than one reducer, error asks the user to pin.
    ///   3. Emit the verifier stub via `ActionSequenceStubEmitter`.
    ///      Unsupported shapes / carriers (M8 deferrals, TCA closure
    ///      state-init) surface as clear errors.
    ///   4. Render the outcome — for M3.C, "stub emitted, harness
    ///      pending kit v2.2.0 publication"; M3.E swaps this for
    ///      the build/run loop.
    public static func runPipeline(
        target: String,
        pinRaw: String? = nil,
        sequenceCount: Int = ActionSequenceStubEmitter.defaultSequenceCount,
        userModuleName: String? = nil,
        workingDirectory: URL
    ) throws -> String {
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
        return renderPendingHarness(candidate: matched, stubSource: stubSource)
    }

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

    /// V2.0 M3.C — "stub emitted, harness pending" rendering. M3.E
    /// replaces the body of this with the actual build/run loop +
    /// the v1.42-shape five-category outcome. The stub-source dump
    /// makes the M3.C output useful in its own right: users can
    /// inspect / hand-build the emitted verifier even before M3.E.
    static func renderPendingHarness(
        candidate: ReducerCandidate,
        stubSource: String
    ) -> String {
        [
            "swift-infer verify-interaction — V2.0 M3.C (stub-emission only):",
            "  Reducer: \(candidate.qualifiedName)",
            "  Carrier: \(candidate.carrierKind.rawValue)",
            "  Signature: \(candidate.signatureShape.rawValue)",
            "  State: \(candidate.stateTypeName)",
            "  Action: \(candidate.actionTypeName)",
            "",
            "  M3.C ships the orchestration + stub-emission surface. The",
            "  build-and-run loop that turns this stub into a v1.42-shape",
            "  outcome lands at M3.E once SwiftPropertyLaws v2.2.0 is",
            "  published (see docs/calibration-cycle-73-findings.md for the",
            "  kit-tag-publication next-action).",
            "",
            "  Emitted verifier source (\(stubSource.split(separator: "\n").count) lines):",
            "",
            stubSource
        ].joined(separator: "\n")
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
