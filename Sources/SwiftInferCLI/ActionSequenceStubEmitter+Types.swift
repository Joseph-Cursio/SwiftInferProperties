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

        /// TestStore Trace Mining — developer-authored action orderings
        /// mined from the repo's own `TestStore` tests, replayed through the
        /// same per-step invariant loop *before* random generation
        /// (replay-then-extend). Empty (the default) → byte-identical output
        /// to the un-mined stub. The selector guarantees every case
        /// expression compiles against the candidate's Action alphabet.
        public let seedTraces: [SeedTrace]

        /// Slice 3d — also run each mined trace as a *prefix* extended by a
        /// random tail (mode (b) prefix-biased generation): reach the
        /// developer-set-up state, then explore outward. Off by default. (The
        /// mode (c) Markov mode needs no emitter flag — it's realized in the
        /// selector as extra synthesized `seedTraces`.)
        public let prefixBias: Bool

        public init(
            candidate: ReducerCandidate,
            userModuleName: String,
            sequenceCount: Int = ActionSequenceStubEmitter.defaultSequenceCount,
            lengthLowerBound: Int = 0,
            lengthUpperBound: Int = 16,
            invariant: InteractionInvariantSuggestion? = nil,
            seedTraces: [SeedTrace] = [],
            prefixBias: Bool = false
        ) {
            self.candidate = candidate
            self.userModuleName = userModuleName
            self.sequenceCount = sequenceCount
            self.lengthLowerBound = lengthLowerBound
            self.lengthUpperBound = lengthUpperBound
            self.invariant = invariant
            self.seedTraces = seedTraces
            self.prefixBias = prefixBias
        }
    }

    /// One mined ordering ready for emission: an optional verifier-constructible
    /// initial-State expression (Slice 3c — nil uses the reducer's default
    /// `State()`) plus the case expressions *minus* the leading dot
    /// (`"dismiss"`, `"select(0)"`, `"setColor(color: 0)"`). The selector
    /// guarantees each element compiles against the Action alphabet.
    public struct SeedTrace: Sendable, Equatable {
        public let initialState: String?
        public let actions: [String]

        public init(initialState: String?, actions: [String]) {
            self.initialState = initialState
            self.actions = actions
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
