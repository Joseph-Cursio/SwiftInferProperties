import Foundation
import SwiftInferCore

/// V2.0 M3.B — emits the Swift source for the verifier executable
/// that `swift-infer verify-interaction` builds + runs. The emitted
/// `main.swift` imports the user's module + `PropertyLawKit`, builds
/// an action-sequence generator via `ActionSequenceFactory`, runs
/// N sequences through the discovered reducer, and prints a structured
/// outcome line on the clean path.
///
/// **Trap-as-exit-code outcome model.** Swift traps (array-out-of-bounds,
/// force-unwrap-nil, `fatalError`) terminate the process with a non-zero
/// exit code. The harness exploits this: a clean exit + the expected
/// outcome marker means every sequence ran without trapping; a non-zero
/// exit or a missing marker means at least one sequence trapped. The
/// parent (`swift-infer verify-interaction`) reads the exit code +
/// stdout to map to the v1.42 five-category outcome scheme.
///
/// **What it does NOT do at M3.0:** invariant checking. Every sequence
/// runs through the reducer; the only failure mode is a trap. M4–M7
/// template families attach an invariant predicate to each candidate
/// and extend this stub to check `predicate(state)` at each step.
///
/// **Supported signature shapes (M3.0):**
///   - `.stateActionReturnsState` — `state = reduce(state, action)`
///   - `.inoutStateActionReturnsVoid` — `reduce(&state, action)`
///
/// The two effect-shaped signatures (`.stateActionReturnsStateAndEffect`,
/// `.inoutStateActionReturnsEffect`) route to the subprocess path at
/// M8 (PRD §7.4); the emitter throws `.unsupportedShape` for them.
///
/// **Supported call contexts (M3.0):** free function (no enclosing
/// type), or a function nested in a `Reducer`-conforming type (called
/// as `<Type>.functionName`). Instance methods needing an instance
/// constructor (`<Type>().functionName(...)`) defer until calibration
/// shows the simpler static-style call site doesn't cover most picks.
public enum ActionSequenceStubEmitter {

    /// Number of action sequences to run per verifier invocation.
    /// PRD §15 perf target is "1k action sequences ... in < 100ms wall"
    /// on a small reducer, so 1024 is the default upper bound. The
    /// caller can override via `Inputs.sequenceCount` for tighter
    /// budgets or longer fuzzing campaigns.
    public static let defaultSequenceCount = 1024

    /// Outcome marker the verifier prints on the clean path. Parsed
    /// by `Verify.runInteractionPipeline` (M3.C). Public so tests on
    /// both ends agree on the byte-stable string.
    public static let cleanOutcomeMarker = "INTERACTION-VERIFY-OUTCOME: bothPass"

    /// Header marker (first non-blank line of stub output) so tests
    /// can pin the format without depending on emit-time variables
    /// like the swift-infer version.
    public static let stubHeaderMarker = "// swift-infer verify-interaction stub (V2.0 M3.B)"

    public struct Inputs: Sendable, Equatable {
        public let candidate: ReducerCandidate
        public let userModuleName: String
        public let sequenceCount: Int
        public let lengthLowerBound: Int
        public let lengthUpperBound: Int
        /// V2.0 M4.D — optional invariant suggestion the stub
        /// should verify. When `nil`, the stub falls back to the
        /// M3.0 "ran cleanly / trapped" posture (no predicate
        /// check; the only failure mode is a Swift trap inside the
        /// reducer body). When supplied, the emitter branches on
        /// `invariant.family`:
        ///   - `.conservation` → embeds `precondition(<predicate>)`
        ///     after each `state = reduce(...)` step
        ///   - `.idempotence` → emits a post-loop double-apply check
        ///     using `<predicate>` (the action-case dot-shorthand)
        ///   - other families (`.cardinality` / `.referentialIntegrity`
        ///     / `.biconditional`) → `EmitError.unsupportedFamily`
        ///     until M5–M7 ship them.
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
                return "M3.B does not support reducer shape '\(shape.rawValue)' "
                    + "(effect-bearing shapes route to the subprocess path at M8)."
            case let .unsupportedCarrier(kind):
                return "M3.B does not yet support carrier kind '\(kind.rawValue)' "
                    + "(TCA `.tca` reducers need closure-relative state init — deferred to M3.E)."
            case let .unsupportedFamily(family):
                return "M4.D does not yet support invariant family '\(family.rawValue)' "
                    + "— Conservation (M4.B) and Idempotence (M4.C) ship; the three "
                    + "new families (Cardinality / Referential integrity / Biconditional) "
                    + "land at M5 / M6 / M7."
            }
        }
    }

    /// V2.0 M3.B / M4.D — emit the verifier `main.swift` source.
    /// Throws if the candidate's signature shape or carrier kind isn't
    /// supported (M3.B), or if the supplied invariant's family isn't
    /// yet handled (M4.D).
    public static func emit(_ inputs: Inputs) throws -> String {
        try validate(inputs.candidate)
        if let invariant = inputs.invariant {
            try validateInvariant(invariant.family)
        }
        let reducerCall = makeReducerCall(inputs.candidate)
        let stateInit = "\(inputs.candidate.stateTypeName)()"
        let applyStep = makeApplyStep(
            shape: inputs.candidate.signatureShape,
            reducerCall: reducerCall
        )
        let perStepCheck = makePerStepCheck(invariant: inputs.invariant)
        let postLoopCheck = makePostLoopCheck(
            invariant: inputs.invariant,
            shape: inputs.candidate.signatureShape,
            reducerCall: reducerCall
        )
        return assembleStub(
            inputs: inputs,
            stateInit: stateInit,
            applyStep: applyStep,
            perStepCheck: perStepCheck,
            postLoopCheck: postLoopCheck
        )
    }

    /// V2.0 M4.D — assemble the stub source. Extracted from
    /// `emit(_:)` to keep the outer function under SwiftLint's
    /// `function_body_length` cap as the per-step / post-loop
    /// check blocks landed.
    private static func assembleStub(
        inputs: Inputs,
        stateInit: String,
        applyStep: String,
        perStepCheck: [String],
        postLoopCheck: [String]
    ) -> String {
        var lines: [String] = [
            stubHeaderMarker,
            "// Reducer: \(inputs.candidate.qualifiedName)",
            "// Carrier: \(inputs.candidate.carrierKind.rawValue)",
            "// Signature: \(inputs.candidate.signatureShape.rawValue)"
        ]
        if let invariant = inputs.invariant {
            lines.append("// Invariant family: \(invariant.family.rawValue)")
            lines.append("// Predicate: \(invariant.predicate)")
        }
        lines.append("// DO NOT EDIT — regenerated on each `swift-infer verify-interaction` run.")
        lines.append("")
        lines.append("import \(inputs.userModuleName)")
        lines.append("import PropertyBased")
        lines.append("import PropertyLawKit")
        lines.append("")
        lines.append("@main")
        lines.append("struct InteractionVerifier {")
        lines.append("    static func main() {")
        lines.append("        var rng = Xoshiro(seed: (\(seedTuple(for: inputs.candidate))))")
        lines.append("        let generator = ActionSequenceFactory.actionSequence(")
        lines.append("            forCaseIterable: \(inputs.candidate.actionTypeName).self,")
        lines.append("            length: \(inputs.lengthLowerBound)...\(inputs.lengthUpperBound)")
        lines.append("        )")
        lines.append("        var clean = 0")
        lines.append("        for _ in 0..<\(inputs.sequenceCount) {")
        lines.append("            let actions = generator.run(using: &rng)")
        lines.append("            var state = \(stateInit)")
        lines.append("            for action in actions {")
        lines.append("                \(applyStep)")
        for line in perStepCheck {
            lines.append("                \(line)")
        }
        lines.append("            }")
        for line in postLoopCheck {
            lines.append("            \(line)")
        }
        lines.append("            clean += 1")
        lines.append("        }")
        lines.append("        print(\"\(cleanOutcomeMarker) totalRuns=\\(\(inputs.sequenceCount)) clean=\\(clean)\")")
        lines.append("    }")
        lines.append("}")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// V2.0 M4.D / M5 — per-step invariant check (Conservation +
    /// Cardinality). Both families embed a boolean predicate
    /// evaluated at each action step. Idempotence uses the post-loop
    /// double-apply check instead.
    static func makePerStepCheck(invariant: InteractionInvariantSuggestion?) -> [String] {
        guard let invariant else { return [] }
        switch invariant.family {
        case .conservation:
            return [
                "precondition(\(invariant.predicate), "
                    + "\"Conservation invariant violated\")"
            ]
        case .cardinality:
            return [
                "precondition(\(invariant.predicate), "
                    + "\"Cardinality invariant violated\")"
            ]
        case .idempotence:
            return []
        case .referentialIntegrity, .biconditional:
            // Unreachable — `validateInvariant` rejects these before emit.
            return []
        }
    }

    /// V2.0 M4.D — post-loop invariant check (Idempotence). After
    /// the action sequence has driven `state` to a varied position,
    /// applies the candidate action twice and asserts state-equality.
    /// Branches on `signatureShape` because `(inout S, A) -> Void`
    /// needs a copy-and-mutate dance vs. `(S, A) -> S`'s direct
    /// assignment. Returns empty for nil invariant or non-Idempotence
    /// families.
    static func makePostLoopCheck(
        invariant: InteractionInvariantSuggestion?,
        shape: ReducerSignatureShape,
        reducerCall: String
    ) -> [String] {
        guard let invariant else { return [] }
        switch invariant.family {
        case .conservation, .cardinality:
            return []
        case .idempotence:
            return makeIdempotenceCheck(
                actionExpr: invariant.predicate,
                shape: shape,
                reducerCall: reducerCall
            )
        case .referentialIntegrity, .biconditional:
            return []
        }
    }

    /// V2.0 M4.D — the idempotence check body, parameterized over
    /// the signature shape. Pulled to a static so tests can drive
    /// the body shape independently of the surrounding stub.
    static func makeIdempotenceCheck(
        actionExpr: String,
        shape: ReducerSignatureShape,
        reducerCall: String
    ) -> [String] {
        let assertion =
            "precondition(once == twice, "
                + "\"Idempotence invariant violated for \(actionExpr)\")"
        switch shape {
        case .stateActionReturnsState:
            return [
                "let once = \(reducerCall)(state, \(actionExpr))",
                "let twice = \(reducerCall)(once, \(actionExpr))",
                assertion
            ]
        case .inoutStateActionReturnsVoid:
            return [
                "var once = state",
                "\(reducerCall)(&once, \(actionExpr))",
                "var twice = once",
                "\(reducerCall)(&twice, \(actionExpr))",
                assertion
            ]
        case .stateActionReturnsStateAndEffect, .inoutStateActionReturnsEffect:
            // Unreachable — `validate` rejects effect-bearing shapes.
            return []
        }
    }

    /// V2.0 M4.D / M5 — reject invariant families that don't have
    /// an emission path yet. Conservation + Idempotence ship at
    /// M4.B/C; Cardinality at M5. Referential integrity (M6) and
    /// Biconditional (M7) still throw.
    private static func validateInvariant(_ family: InteractionInvariantFamily) throws {
        switch family {
        case .conservation, .idempotence, .cardinality:
            return
        case .referentialIntegrity, .biconditional:
            throw EmitError.unsupportedFamily(family)
        }
    }

    // MARK: - Internals

    /// Reject signature shapes / carrier kinds that M3.0 doesn't
    /// support. The thrown error names the case so the caller can
    /// surface a clear "route to M8 instead" message.
    private static func validate(_ candidate: ReducerCandidate) throws {
        switch candidate.signatureShape {
        case .stateActionReturnsState, .inoutStateActionReturnsVoid:
            break
        case .stateActionReturnsStateAndEffect, .inoutStateActionReturnsEffect:
            throw EmitError.unsupportedShape(candidate.signatureShape)
        }
        // M3.0 covers `.elmStyle` + `.generic`. `.tca` needs
        // closure-relative state init that the static-call convention
        // doesn't cover — Reduce { state, action in ... } is a
        // closure value, not a callable on the conforming type.
        if candidate.carrierKind == .tca {
            throw EmitError.unsupportedCarrier(candidate.carrierKind)
        }
    }

    /// `<EnclosingType>.<functionName>` if the candidate has an
    /// enclosing type; just `<functionName>` for free functions.
    /// M3.0 assumes static-call posture for methods — instance-method
    /// dispatch (`<Type>().<functionName>(...)`) is deferred.
    static func makeReducerCall(_ candidate: ReducerCandidate) -> String {
        if let enclosing = candidate.enclosingTypeName {
            return "\(enclosing).\(candidate.functionName)"
        }
        return candidate.functionName
    }

    /// One iteration of the action-application loop. Returns the
    /// statement that mutates `state` for the given signature shape.
    static func makeApplyStep(
        shape: ReducerSignatureShape,
        reducerCall: String
    ) -> String {
        switch shape {
        case .stateActionReturnsState:
            return "state = \(reducerCall)(state, action)"
        case .inoutStateActionReturnsVoid:
            return "\(reducerCall)(&state, action)"
        case .stateActionReturnsStateAndEffect, .inoutStateActionReturnsEffect:
            // Unreachable — `validate` rejects these.
            return "// unsupported shape"
        }
    }

    /// Derive a deterministic Xoshiro256** seed from the candidate's
    /// `qualifiedName` so re-running verify against the same reducer
    /// produces the same action sequences. Mirrors v1's
    /// `RoundTripStubEmitter.makeSeedHex` posture — same input →
    /// same seed → byte-stable verifier output.
    static func seedTuple(for candidate: ReducerCandidate) -> String {
        var hash = SipHasher()
        hash.combine(candidate.qualifiedName)
        let seedA = hash.finalize()
        hash = SipHasher()
        hash.combine(candidate.qualifiedName + ".b")
        let seedB = hash.finalize()
        hash = SipHasher()
        hash.combine(candidate.qualifiedName + ".c")
        let seedC = hash.finalize()
        hash = SipHasher()
        hash.combine(candidate.qualifiedName + ".d")
        let seedD = hash.finalize()
        return "0x\(String(seedA, radix: 16)), 0x\(String(seedB, radix: 16)), "
            + "0x\(String(seedC, radix: 16)), 0x\(String(seedD, radix: 16))"
    }
}

/// Minimal SipHash-style accumulator — just enough for deterministic
/// seed derivation from string identifiers. We can't use Swift's
/// built-in Hasher (its output is randomized per-process via
/// `Hasher.seedOverride`); we need byte-stable output across runs so
/// the verifier's seed is reproducible.
///
/// Tiny FNV-1a-shape mixer with an extra avalanche step. Not
/// cryptographic — that's fine; the seed only needs to be uniform
/// enough that Xoshiro's state isn't pathological.
private struct SipHasher {
    private var state: UInt64 = 0xCBF2_9CE4_8422_2325 // FNV offset basis

    mutating func combine(_ value: String) {
        for byte in value.utf8 {
            state ^= UInt64(byte)
            state &*= 0x0000_0100_0000_01B3 // FNV prime
        }
    }

    mutating func finalize() -> UInt64 {
        // xxhash avalanche step — borrowed from v1's
        // `RoundTripStubEmitter.spread`. Ensures high bits get mixed.
        var hash = state ^ (state >> 32)
        hash &*= 0xC2B2_AE3D_27D4_EB4F
        hash ^= hash >> 29
        hash &*= 0x1656_67B1_9E37_79F9
        return hash | 1 // Xoshiro state must not be all-zero.
    }
}
