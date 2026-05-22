import Foundation
import SwiftInferCore

// V2.0 M8.A — `ActionSequenceStubEmitter.Inputs` + `EmitError` lifted
// out of the main file via extension so the parent enum's body stays
// under SwiftLint's `type_body_length` cap as M8 adds the effect-
// discard arms. Pure relocation — no behavior change.

extension ActionSequenceStubEmitter {

    public struct Inputs: Sendable, Equatable {
        public let candidate: ReducerCandidate
        public let userModuleName: String
        public let sequenceCount: Int
        public let lengthLowerBound: Int
        public let lengthUpperBound: Int
        /// Optional invariant the stub should verify. `nil` → M3.B's
        /// "ran cleanly / trapped" posture. Supplied → emitter
        /// branches on `family` (per-step `precondition` for
        /// Conservation / Cardinality / Ref-integrity / Biconditional;
        /// post-loop double-apply for Idempotence).
        public let invariant: InteractionInvariantSuggestion?

        public init(
            candidate: ReducerCandidate,
            userModuleName: String,
            sequenceCount: Int = ActionSequenceStubEmitter.defaultSequenceCount,
            lengthLowerBound: Int = 0,
            lengthUpperBound: Int = 16,
            invariant: InteractionInvariantSuggestion? = nil
        ) {
            self.candidate = candidate
            self.userModuleName = userModuleName
            self.sequenceCount = sequenceCount
            self.lengthLowerBound = lengthLowerBound
            self.lengthUpperBound = lengthUpperBound
            self.invariant = invariant
        }
    }

    public enum EmitError: Error, CustomStringConvertible, Equatable {
        case unsupportedShape(ReducerSignatureShape)
        case unsupportedCarrier(ReducerCarrierKind)
        case unsupportedFamily(InteractionInvariantFamily)

        public var description: String {
            switch self {
            case let .unsupportedShape(shape):
                return "ActionSequenceStubEmitter does not support reducer shape "
                    + "'\(shape.rawValue)' — forward-compat slot for future PRD §6.2 "
                    + "shapes."

            case let .unsupportedCarrier(kind):
                return "ActionSequenceStubEmitter does not yet support carrier kind "
                    + "'\(kind.rawValue)' (TCA `.tca` reducers need closure-relative "
                    + "state init via `feature.reduce(into:action:)` — deferred)."

            case let .unsupportedFamily(family):
                return "ActionSequenceStubEmitter does not yet support invariant "
                    + "family '\(family.rawValue)' — forward-compat slot for future "
                    + "PRD §5 families."
            }
        }
    }
}
