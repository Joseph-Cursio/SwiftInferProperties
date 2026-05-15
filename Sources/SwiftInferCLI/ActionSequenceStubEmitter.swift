import Foundation
import SwiftInferCore

/// V2.0 M3.B / M4.D / M8.A — emits the verifier `main.swift` source
/// for `swift-infer verify-interaction`. Imports the user module +
/// PropertyLawKit, builds an action-sequence generator, runs N
/// sequences, and prints an outcome marker on the clean path. M4.D
/// embeds family-aware predicate checks (Conservation / Cardinality
/// / Ref-integrity / Biconditional per-step; Idempotence post-loop).
/// M8.A accepts effect-bearing shapes and **captures-and-discards**
/// the returned `Effect<A>` per PRD §16 #1.
///
/// **Trap-as-exit-code outcome.** Swift traps (`fatalError`, array-
/// out-of-bounds, force-unwrap-nil) and `precondition` violations
/// terminate with non-zero exit → `.measuredDefaultFails` via
/// M3.E.3's parser.
///
/// **Supported:** all four `ReducerSignatureShape` cases via free /
/// static-call form. **Rejected:** `.tca` carrier (closure-relative
/// `feature.reduce(into:action:)` init is separate scope).
public enum ActionSequenceStubEmitter {

    /// Number of action sequences per verifier run. PRD §15 perf
    /// target: 1k sequences in <100ms; default 1024.
    public static let defaultSequenceCount = 1024

    /// Outcome marker the verifier prints on the clean path. M3.E.3's
    /// parser keys on this byte-stable string.
    public static let cleanOutcomeMarker = "INTERACTION-VERIFY-OUTCOME: bothPass"

    /// Header marker (first non-blank line) — tests pin the format
    /// without depending on emit-time variables.
    public static let stubHeaderMarker = "// swift-infer verify-interaction stub (V2.0 M3.B)"

    // `Inputs` + `EmitError` are nested via extension in
    // ActionSequenceStubEmitter+Types.swift (M8.A split keeps the
    // type body under SwiftLint's `type_body_length` cap).

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

    /// V2.0 M4.D / M8.A — assemble the stub source. Extracted from
    /// `emit(_:)` to keep the outer function under SwiftLint's
    /// `function_body_length` cap as the per-step / post-loop
    /// check blocks landed. M8.A switched `applyStep` to `[String]`
    /// so effect-tuple shapes can render a two-line destructure-
    /// and-assign block at the right indent.
    private static func assembleStub(
        inputs: Inputs,
        stateInit: String,
        applyStep: [String],
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
        for line in applyStep {
            lines.append("                \(line)")
        }
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

    /// V2.0 M4.D / M5 / M6 — per-step invariant check
    /// (Conservation + Cardinality + Referential Integrity). Three
    /// families embed a boolean predicate evaluated at each action
    /// step. Idempotence uses the post-loop double-apply check
    /// instead.
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
        case .referentialIntegrity:
            return [
                "precondition(\(invariant.predicate), "
                    + "\"Referential-integrity invariant violated\")"
            ]
        case .biconditional:
            return [
                "precondition(\(invariant.predicate), "
                    + "\"Biconditional invariant violated\")"
            ]
        case .idempotence:
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
        case .conservation, .cardinality, .referentialIntegrity, .biconditional:
            return []
        case .idempotence:
            return makeIdempotenceCheck(
                actionExpr: invariant.predicate,
                shape: shape,
                reducerCall: reducerCall
            )
        }
    }

    /// V2.0 M4.D / M8.A — the idempotence check body, parameterized
    /// over the signature shape. Pulled to a static so tests can
    /// drive the body shape independently of the surrounding stub.
    /// M8.A extends with two effect-bearing arms: the `Effect<A>`
    /// half of the tuple / return is **captured and discarded** per
    /// PRD §16 #1 (swift-infer never runs user-side Effects).
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
        case .stateActionReturnsStateAndEffect:
            return [
                "let (once, _) = \(reducerCall)(state, \(actionExpr))",
                "let (twice, _) = \(reducerCall)(once, \(actionExpr))",
                assertion
            ]
        case .inoutStateActionReturnsEffect:
            return [
                "var once = state",
                "_ = \(reducerCall)(&once, \(actionExpr))",
                "var twice = once",
                "_ = \(reducerCall)(&twice, \(actionExpr))",
                assertion
            ]
        }
    }

    /// V2.0 M4.D / M5 / M6 — reject invariant families that don't
    /// have an emission path yet. Conservation + Idempotence ship
    /// V2.0 M4.D / M5 / M6 / M7 — all five interaction families now
    /// have an emission path. The error case stays for forward-
    /// compatibility (future PRD families would slot in here).
    private static func validateInvariant(_ family: InteractionInvariantFamily) throws {
        switch family {
        case .conservation, .idempotence, .cardinality,
             .referentialIntegrity, .biconditional:
            return
        }
    }

    // MARK: - Internals

    /// Reject carrier kinds the emitter doesn't support. All four
    /// signature shapes are now accepted (M8.A lifted the
    /// effect-shape rejection — effects are captured and discarded
    /// per PRD §16 #1). `.tca` carrier still rejected: closure-
    /// relative init via `feature.reduce(into:action:)` is separate
    /// scope.
    private static func validate(_ candidate: ReducerCandidate) throws {
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
    /// statement(s) that mutate `state` for the given signature
    /// shape. Effect-bearing shapes (M8.A) discard the returned
    /// `Effect<A>` — captured into `_` and never executed (PRD
    /// §16 #1). Returned as an array so the assembler can append
    /// each line at the caller's indent depth — the effect-tuple
    /// shape needs two lines (destructure + assign).
    static func makeApplyStep(
        shape: ReducerSignatureShape,
        reducerCall: String
    ) -> [String] {
        switch shape {
        case .stateActionReturnsState:
            return ["state = \(reducerCall)(state, action)"]
        case .inoutStateActionReturnsVoid:
            return ["\(reducerCall)(&state, action)"]
        case .stateActionReturnsStateAndEffect:
            return [
                "let (newState, _) = \(reducerCall)(state, action)",
                "state = newState"
            ]
        case .inoutStateActionReturnsEffect:
            return ["_ = \(reducerCall)(&state, action)"]
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
