import Foundation

// V2.0 M3.C — the interaction-verify pipeline error type, lifted out of
// `VerifyInteractionPipeline.swift` so that file stays under SwiftLint's
// `file_length` cap (the slice-3 resolver call pushed it over). Pure
// relocation — no behavior change.

/// V2.0 M3.C — errors thrown by the interaction-verify pipeline.
/// Hoisted to file scope for the SwiftLint nesting cap; public so
/// tests can pattern-match on the case rather than the rendered text.
public enum VerifyInteractionError: Error, CustomStringConvertible, Equatable {
    case noReducersDetected
    case noMatchingReducer(pin: String)
    case ambiguousPin(pin: String, matches: [String])
    case requiresPin(candidates: [String])
    case unsupported(reason: String)
    /// V2.0 M8.B — body writes to a static / global var; running N
    /// action sequences against it produces meaningless outcomes
    /// because state persists across runs. PRD §4.1 `-∞` veto.
    case hiddenMutability(reducer: String)

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

        case let .hiddenMutability(reducer):
            return "swift-infer verify-interaction: reducer '\(reducer)' has hidden "
                + "mutability (writes to static / global state). Running random action "
                + "sequences against it produces non-deterministic outcomes; PRD §4.1 "
                + "vetoes the verify path here. Rework the reducer to be pure or move "
                + "the static state to the State type."
        }
    }
}
