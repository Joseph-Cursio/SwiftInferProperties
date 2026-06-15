import Foundation
import PropertyLawCore
import SwiftInferCore

/// V2.0 M3.B / M4.D / M8.A / M8.D — emits the verifier `main.swift`
/// source for `swift-infer verify-interaction`. Runs N action
/// sequences, prints an outcome marker on the clean path. M4.D
/// embeds family-aware predicate checks; M8.A captures-and-discards
/// `Effect<A>` per PRD §16 #1; M8.D adds stderr per-sequence marker
/// + env-var-driven single-sequence replay (the shrinker primitive).
/// Traps + `precondition` violations → non-zero exit →
/// `.measuredDefaultFails`. Supported: all four `ReducerSignatureShape`
/// cases via free / static-call form. Rejected: `.tca` carrier
/// (closure-relative init is separate scope).
public enum ActionSequenceStubEmitter {

    /// Number of action sequences per verifier run. PRD §15 perf
    /// target: 1k sequences in <100ms; default 1024.
    public static let defaultSequenceCount = 1_024

    /// V2.0 M8.D.3 — upper bound on action-list length per
    /// generated sequence. Matches `Inputs.init`'s default; lifted
    /// to a public constant so the shrinker can use it without
    /// hard-coding the same number.
    public static let defaultLengthUpperBound = 16

    /// Outcome marker the verifier prints on the clean path. M3.E.3's
    /// parser keys on this byte-stable string.
    public static let cleanOutcomeMarker = "INTERACTION-VERIFY-OUTCOME: bothPass"

    /// Header marker (first non-blank line) — tests pin the format
    /// without depending on emit-time variables.
    public static let stubHeaderMarker = "// swift-infer verify-interaction stub (V2.0 M3.B)"

    /// V2.0 M8.D.1 — per-sequence stderr marker the stub writes
    /// before each generator step. Parser scans for the *last*
    /// occurrence on non-zero exit; stderr is unbuffered so it
    /// survives the trap that follows.
    public static let traceCurrentSequenceMarker = "TRACE-CURRENT-SEQ:"

    /// V2.0 M8.D.2 / M8.D.4 — env-var names the stub reads at
    /// start-up for single-sequence replay (the shrinker's
    /// re-invocation primitive). Public so the shrinker keys on
    /// the same names. The action slice is computed as
    /// `rawActions.dropFirst(suffixStart).prefix(prefixLength)` —
    /// nil defaults mean "no drop / no truncation."
    public static let pinSequenceEnvVar = "SWIFT_INFER_PIN_SEQUENCE"
    public static let pinPrefixLengthEnvVar = "SWIFT_INFER_PIN_PREFIX_LENGTH"
    public static let pinSuffixStartEnvVar = "SWIFT_INFER_PIN_SUFFIX_START"

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
            validateInvariant(invariant.family)
        }
        let isTCA = inputs.candidate.carrierKind == .tca
        let reducerCall = makeReducerCall(inputs.candidate)
        let stateInit = "\(inputs.candidate.stateTypeName)()"
        let applyStep = makeApplyStep(
            shape: inputs.candidate.signatureShape,
            reducerCall: reducerCall,
            isTCA: isTCA
        )
        let perStepCheck = makePerStepCheck(invariant: inputs.invariant)
        let postLoopCheck = makePostLoopCheck(
            invariant: inputs.invariant,
            shape: inputs.candidate.signatureShape,
            reducerCall: reducerCall,
            isTCA: isTCA
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
        let isTCA = inputs.candidate.carrierKind == .tca
        lines.append("import Foundation")
        // Cycle 122 (Phase A): a `.tca` reducer's sources are compiled
        // INTO this target (direct source inclusion) — no `import
        // <userModule>` — but it needs `ComposableArchitecture` to name
        // `Reduce`/`Effect` and call `reduce(into:action:)`.
        if isTCA {
            lines.append("import ComposableArchitecture")
        } else {
            lines.append("import \(inputs.userModuleName)")
        }
        lines.append("import PropertyBased")
        lines.append("import PropertyLawKit")
        lines.append("")
        lines.append("@main")
        lines.append("struct InteractionVerifier {")
        lines.append("    static func main() {")
        // M8.D.2 — env-var-driven single-sequence replay. nil
        // (env var unset) → full N-sequence loop (M8.D.1 posture).
        // Non-nil → skip-then-replay-one (the shrinker's primitive).
        lines.append("        let env = ProcessInfo.processInfo.environment")
        lines.append("        let pinSequence = env[\"\(pinSequenceEnvVar)\"].flatMap(Int.init)")
        lines.append("        let pinPrefix = env[\"\(pinPrefixLengthEnvVar)\"].flatMap(Int.init)")
        lines.append("        let pinSuffixStart = env[\"\(pinSuffixStartEnvVar)\"].flatMap(Int.init)")
        lines.append("        var rng = Xoshiro(seed: (\(seedTuple(for: inputs.candidate))))")
        lines.append(contentsOf: makeGeneratorBlock(inputs: inputs, isTCA: isTCA))
        lines.append("        var clean = 0")
        lines.append("        for sequenceIndex in 0..<\(inputs.sequenceCount) {")
        lines.append(contentsOf: makeIterationBody(
            stateInit: stateInit,
            applyStep: applyStep,
            perStepCheck: perStepCheck,
            postLoopCheck: postLoopCheck
        ))
        lines.append("        }")
        lines.append("        print(\"\(cleanOutcomeMarker) totalRuns=\\(\(inputs.sequenceCount)) clean=\\(clean)\")")
        lines.append("    }")
        lines.append("}")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// V2.0 M8.D.2 — body of the per-sequence loop. Pulled to a helper
    /// so `assembleStub` stays under SwiftLint's `function_body_length`
    /// cap as the M8.D.1 stderr-marker write + M8.D.2 pin-sequence
    /// branches landed. Lines are pre-indented to 12 spaces (the
    /// `for sequenceIndex` block's interior depth).
    private static func makeIterationBody(
        stateInit: String,
        applyStep: [String],
        perStepCheck: [String],
        postLoopCheck: [String]
    ) -> [String] {
        // M8.D.4: drop-prefix (suffixStart) applied first, then
        // drop-suffix (prefixLength). Both slicing operations are
        // bound-safe (`dropFirst(N)`: empty if N ≥ count; `.prefix(M)`:
        // up to M elements).
        var lines: [String] = [
            "            FileHandle.standardError.write(",
            "                Data(\"\(traceCurrentSequenceMarker) \\(sequenceIndex)\\n\".utf8)",
            "            )",
            "            let rawActions = generator.run(using: &rng)",
            "            if let pin = pinSequence, sequenceIndex != pin { continue }",
            "            let dropped = pinSuffixStart.map { Array(rawActions.dropFirst($0)) } "
                + "?? rawActions",
            "            let actions = pinPrefix.map { Array(dropped.prefix($0)) } ?? dropped",
            "            var state = \(stateInit)",
            "            for action in actions {"
        ]
        lines.append(contentsOf: applyStep.map { "                \($0)" })
        lines.append(contentsOf: perStepCheck.map { "                \($0)" })
        lines.append("            }")
        lines.append(contentsOf: postLoopCheck.map { "            \($0)" })
        lines.append("            clean += 1")
        lines.append("            if pinSequence != nil { break }")
        return lines
    }

    // `makePerStepCheck` / `makePostLoopCheck` / `makeIdempotenceCheck`
    // are nested via extension in ActionSequenceStubEmitter+FamilyChecks.swift.

    /// V2.0 M4.D / M5 / M6 — reject invariant families that don't
    /// have an emission path yet. Conservation + Idempotence ship
    /// V2.0 M4.D / M5 / M6 / M7 — all five interaction families now
    /// have an emission path. The error case stays for forward-
    /// compatibility (future PRD families would slot in here).
    private static func validateInvariant(_ family: InteractionInvariantFamily) {
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
        // Cycle 122/125 — `.tca` is supported when the Action has at least
        // one *constructible* case (payload-free or single recognized-raw
        // payload). Phase B's relaxed exploration verifies over that subset
        // and discloses the rest as excluded; only an Action with no
        // constructible case at all (or no Action enum found) is rejected.
        if candidate.carrierKind == .tca, constructibleCases(candidate).isEmpty {
            throw EmitError.tcaActionNotEnumerable(actionType: candidate.actionTypeName)
        }
    }

    // MARK: - Cycle 125 (Phase B) — Action-case constructibility

    /// The constructible Action cases — payload-free, or a single
    /// associated value of a recognized raw type. These are what the
    /// relaxed generator explores; everything else (composition cases like
    /// `binding`/`child`, multi-value or non-raw payloads) is excluded.
    static func constructibleCases(_ candidate: ReducerCandidate) -> [ActionCaseInfo] {
        candidate.actionCases.filter { $0.payloadTypes.isEmpty || rawGenerator(for: $0) != nil }
    }

    /// Names of the excluded (non-constructible) cases, in source order —
    /// the partial-exploration disclosure (guardrail #1, cycle 124).
    static func excludedCaseNames(_ candidate: ReducerCandidate) -> [String] {
        let constructible = Set(constructibleCases(candidate).map(\.name))
        return candidate.actionCases.map(\.name).filter { !constructible.contains($0) }
    }

    /// The raw scalar generator expression for a single-raw-payload case
    /// (delegated to `DerivationStrategist`'s `RawType`, PRD §11), or nil
    /// when the case isn't a single recognized-raw-payload case.
    private static func rawGenerator(for caseInfo: ActionCaseInfo) -> String? {
        guard caseInfo.payloadTypes.count == 1,
              let raw = RawType(typeName: caseInfo.payloadTypes[0]) else { return nil }
        return raw.generatorExpression
    }

    /// The `let actionGen = …` lines for a `.tca` reducer (8-space base
    /// indent): `Gen.always(.free)` per payload-free case,
    /// `<rawGen>.map(Action.case)` per raw-payload case, combined with
    /// `Gen.oneOf(...)` (or used directly when there's exactly one).
    private static func tcaActionGenLines(_ candidate: ReducerCandidate) -> [String] {
        let action = candidate.actionTypeName
        let gens = constructibleCases(candidate).map { caseInfo -> String in
            if let raw = rawGenerator(for: caseInfo) {
                return "\(raw).map(\(action).\(caseInfo.name))"
            }
            return "Gen.always(\(action).\(caseInfo.name))"
        }
        if gens.count == 1 { return ["        let actionGen = \(gens[0])"] }
        var lines = ["        let actionGen = Gen.oneOf("]
        for (index, gen) in gens.enumerated() {
            lines.append("            \(gen)" + (index == gens.count - 1 ? "" : ","))
        }
        lines.append("        )")
        return lines
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

    /// The action-generator + (for TCA) reducer-instance setup lines,
    /// pre-indented to 8 spaces. Generic carriers enumerate via
    /// `forCaseIterable:`; `.tca` carriers use an explicit payload-free
    /// case list (real TCA Actions don't declare `CaseIterable`) and a
    /// `let reducer = T()` instance to drive `reduce(into:action:)`.
    private static func makeGeneratorBlock(inputs: Inputs, isTCA: Bool) -> [String] {
        let length = "\(inputs.lengthLowerBound)...\(inputs.lengthUpperBound)"
        guard isTCA else {
            return [
                "        let generator = ActionSequenceFactory.actionSequence(",
                "            forCaseIterable: \(inputs.candidate.actionTypeName).self,",
                "            length: \(length)",
                "        )"
            ]
        }
        // Cycle 125 (Phase B) — relaxed generator over the constructible
        // case subset (payload-free + raw-payload); non-derivable cases are
        // skipped (disclosed as excluded by the pipeline).
        let reducerType = inputs.candidate.enclosingTypeName ?? inputs.candidate.actionTypeName
        var lines = tcaActionGenLines(inputs.candidate)
        lines.append("        let generator = ActionSequenceFactory.actionSequence(")
        lines.append("            from: actionGen,")
        lines.append("            length: \(length)")
        lines.append("        )")
        lines.append("        let reducer = \(reducerType)()")
        return lines
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
        reducerCall: String,
        isTCA: Bool = false
    ) -> [String] {
        // Cycle 122 (Phase A) — a `.tca` reducer is driven instance-
        // relative: `reducer.reduce(into:&state, action:)` on a `let
        // reducer = <Type>()` the assembler emits before the loop. The
        // returned `Effect` is captured + discarded (PRD §16 #1).
        if isTCA {
            return ["_ = reducer.reduce(into: &state, action: action)"]
        }
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
