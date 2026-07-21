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

        /// TestStore Trace Mining (Slice 2) — developer-authored,
        /// payload-free action orderings mined from the repo's own
        /// `TestStore` tests. Each element is a trace: an ordered list of
        /// enum case names (`["dismiss", "refresh"]`), emitted as
        /// `[.dismiss, .refresh]` and checked through the same per-step
        /// invariant loop *before* random generation (replay-then-extend).
        /// Empty (the default) → byte-identical output to the pre-Slice-2
        /// stub. The selector guarantees every name is a payload-free case
        /// in the candidate's Action alphabet, so the literals compile.
        public let seedTraces: [[String]]

        public init(
            candidate: ReducerCandidate,
            userModuleName: String,
            sequenceCount: Int = ActionSequenceStubEmitter.defaultSequenceCount,
            lengthLowerBound: Int = 0,
            lengthUpperBound: Int = 16,
            invariant: InteractionInvariantSuggestion? = nil,
            seedTraces: [[String]] = []
        ) {
            self.candidate = candidate
            self.userModuleName = userModuleName
            self.sequenceCount = sequenceCount
            self.lengthLowerBound = lengthLowerBound
            self.lengthUpperBound = lengthUpperBound
            self.invariant = invariant
            self.seedTraces = seedTraces
        }
    }

    public enum EmitError: Error, CustomStringConvertible, Equatable {
        case unsupportedShape(ReducerSignatureShape)
        case unsupportedCarrier(ReducerCarrierKind)
        case unsupportedFamily(InteractionInvariantFamily)
        /// Cycle 122/125 — a `.tca` candidate whose Action has **no**
        /// constructible case (every case is a composition / multi-value /
        /// non-raw payload), so there's nothing for the relaxed generator
        /// to explore. Distinct from `unsupportedCarrier` because `.tca` IS
        /// supported — just not for an entirely non-derivable Action.
        case tcaActionNotEnumerable(actionType: String)

        public var description: String {
            switch self {
            case let .unsupportedShape(shape):
                return "ActionSequenceStubEmitter does not support reducer shape "
                    + "'\(shape.rawValue)' — forward-compat slot for future PRD §6.2 "
                    + "shapes."

            case let .unsupportedCarrier(kind):
                return "ActionSequenceStubEmitter does not support carrier kind "
                    + "'\(kind.rawValue)'."

            case let .tcaActionNotEnumerable(actionType):
                return "ActionSequenceStubEmitter can't enumerate the action space for "
                    + "'\(actionType)': no constructible (payload-free or raw-payload) "
                    + "case — every case is a composition / multi-value / non-raw payload, "
                    + "which relaxed partial exploration can't generate."

            case let .unsupportedFamily(family):
                return "ActionSequenceStubEmitter does not yet support invariant "
                    + "family '\(family.rawValue)' — forward-compat slot for future "
                    + "PRD §5 families."
            }
        }
    }
}
