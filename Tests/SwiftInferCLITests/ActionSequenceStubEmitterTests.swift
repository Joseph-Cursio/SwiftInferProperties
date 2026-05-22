import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

// V2.0 M3.B — ActionSequenceStubEmitter assertions. Pure text
// emission: no subprocess, no disk I/O. Tests pin the structural
// shape of the emitted stub (imports, generator construction, the
// reducer-call statement for each signature shape, the outcome
// marker, supported-vs-rejected shapes/carriers) without
// byte-exact-matching the whole source (which would brittle on
// every emitter tweak).

@Suite("ActionSequenceStubEmitter — V2.0 M3.B verifier source emission")
struct ActionSequenceStubEmitterTests {

    private func candidate(
        location: String = "Sources/MyApp/Inbox.swift:42",
        enclosingTypeName: String? = nil,
        functionName: String = "reduce",
        signatureShape: ReducerSignatureShape = .stateActionReturnsState,
        stateTypeName: String = "AppState",
        actionTypeName: String = "AppAction",
        carrierKind: ReducerCarrierKind = .elmStyle
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: location,
            enclosingTypeName: enclosingTypeName,
            functionName: functionName,
            signatureShape: signatureShape,
            stateTypeName: stateTypeName,
            actionTypeName: actionTypeName,
            carrierKind: carrierKind
        )
    }

    private func inputs(
        _ candidate: ReducerCandidate,
        userModuleName: String = "MyApp",
        sequenceCount: Int = 1_024,
        lengthLowerBound: Int = 0,
        lengthUpperBound: Int = 16
    ) -> ActionSequenceStubEmitter.Inputs {
        ActionSequenceStubEmitter.Inputs(
            candidate: candidate,
            userModuleName: userModuleName,
            sequenceCount: sequenceCount,
            lengthLowerBound: lengthLowerBound,
            lengthUpperBound: lengthUpperBound
        )
    }

    // MARK: - Shape support

    @Test("free (S, A) -> S reducer — `state = reduce(state, action)`")
    func freeStateActionReturnsState() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(candidate()))
        #expect(source.contains("state = reduce(state, action)"))
        #expect(source.contains("var state = AppState()"))
    }

    @Test("(inout S, A) -> Void reducer — `reduce(&state, action)`")
    func freeInoutStateActionReturnsVoid() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(candidate(
            signatureShape: .inoutStateActionReturnsVoid
        )))
        #expect(source.contains("reduce(&state, action)"))
    }

    @Test("method on a type — `<EnclosingType>.<functionName>` static-call form")
    func methodOnTypeUsesStaticCallForm() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(candidate(
            enclosingTypeName: "Inbox",
            functionName: "reduce",
            carrierKind: .generic
        )))
        #expect(source.contains("state = Inbox.reduce(state, action)"))
    }

    @Test("effect-tuple shape `(S, A) -> (S, Effect<A>)` — captures-and-discards effect (M8.A)")
    func effectTupleShapeEmitsEffectDiscard() throws {
        let candidate = candidate(signatureShape: .stateActionReturnsStateAndEffect)
        let source = try ActionSequenceStubEmitter.emit(inputs(candidate))
        // Effect-discard form: destructure the tuple, bind State to
        // `newState`, throw the `Effect<A>` half away into `_`.
        #expect(source.contains("let (newState, _) = reduce(state, action)"))
        #expect(source.contains("state = newState"))
    }

    @Test("inout-effect shape `(inout S, A) -> Effect<A>` — captures-and-discards effect (M8.A)")
    func inoutEffectShapeEmitsEffectDiscard() throws {
        // `.tca` carrier still rejected; use `.generic` (free / method
        // static-call form) for the effect-discard surface.
        let candidate = candidate(
            signatureShape: .inoutStateActionReturnsEffect,
            carrierKind: .generic
        )
        let source = try ActionSequenceStubEmitter.emit(inputs(candidate))
        #expect(source.contains("_ = reduce(&state, action)"))
    }

    @Test("`.tca` carrier with a supported shape — throws unsupportedCarrier (closure-relative init deferred)")
    func tcaCarrierIsUnsupportedEvenWithCompatibleShape() {
        // A TCA candidate WITH a state-action-returns-state shape (synthetic
        // — TCA closures normally use .inoutStateActionReturnsEffect, but
        // the shape and carrier are independently validated).
        let candidate = candidate(signatureShape: .stateActionReturnsState, carrierKind: .tca)
        // Shape passes, carrier fails.
        let captured = candidate
        #expect(throws: ActionSequenceStubEmitter.EmitError.unsupportedCarrier(.tca)) {
            _ = try ActionSequenceStubEmitter.emit(inputs(captured))
        }
    }

    // MARK: - Imports

    @Test("emitted stub imports the user's module + PropertyLawKit + PropertyBased")
    func emittedStubHasRequiredImports() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(candidate(), userModuleName: "Inbox"))
        #expect(source.contains("import Inbox"))
        #expect(source.contains("import PropertyBased"))
        #expect(source.contains("import PropertyLawKit"))
    }

    // MARK: - Generator construction

    @Test("emitted stub builds the action generator via ActionSequenceFactory")
    func emittedStubBuildsGenerator() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(candidate(
            actionTypeName: "Inbox.Action"
        )))
        #expect(source.contains("ActionSequenceFactory.actionSequence("))
        #expect(source.contains("forCaseIterable: Inbox.Action.self"))
        #expect(source.contains("length: 0...16"))
    }

    @Test("length range overrides via inputs propagate to the emitted stub")
    func lengthRangeOverridePropagates() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(
            candidate(),
            lengthLowerBound: 4,
            lengthUpperBound: 8
        ))
        #expect(source.contains("length: 4...8"))
    }

    // MARK: - Outcome marker

    @Test("emitted stub prints the clean-outcome marker on the success path")
    func emittedStubPrintsCleanOutcomeMarker() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(candidate()))
        #expect(source.contains(ActionSequenceStubEmitter.cleanOutcomeMarker))
    }

    @Test("sequence-count override propagates to the loop bound")
    func sequenceCountOverridePropagates() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(candidate(), sequenceCount: 100))
        // M8.D.1 — the loop variable is now `sequenceIndex` so the
        // stub can write a per-iteration stderr marker for failing-
        // sequence recovery.
        #expect(source.contains("for sequenceIndex in 0..<100 {"))
    }

    // MARK: - Header marker

    @Test("first line is the byte-stable header marker — parsers can pin it")
    func firstLineIsHeaderMarker() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(candidate()))
        let firstLine = source.split(separator: "\n").first.map(String.init) ?? ""
        #expect(firstLine == ActionSequenceStubEmitter.stubHeaderMarker)
    }

    // MARK: - Seed determinism

    @Test("seed tuple is byte-stable for the same qualifiedName across calls")
    func seedTupleIsDeterministic() {
        let first = ActionSequenceStubEmitter.seedTuple(for: candidate(functionName: "reduce"))
        let second = ActionSequenceStubEmitter.seedTuple(for: candidate(functionName: "reduce"))
        #expect(first == second)
    }

    @Test("different qualifiedNames produce different seed tuples")
    func seedTupleVariesByQualifiedName() {
        let alpha = ActionSequenceStubEmitter.seedTuple(for: candidate(functionName: "reduceA"))
        let beta = ActionSequenceStubEmitter.seedTuple(for: candidate(functionName: "reduceB"))
        #expect(alpha != beta)
    }

    // MARK: - V2.0 M8.D.1 — failing-sequence-index trace marker

    @Test("stub imports Foundation for FileHandle access (M8.D.1)")
    func stubImportsFoundation() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(candidate()))
        #expect(source.contains("import Foundation"))
    }

    @Test("stub writes TRACE-CURRENT-SEQ to stderr inside the iteration loop (M8.D.1)")
    func stubWritesTraceMarkerToStderr() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(candidate()))
        #expect(source.contains("FileHandle.standardError.write("))
        #expect(source.contains(ActionSequenceStubEmitter.traceCurrentSequenceMarker))
        #expect(source.contains("\\(sequenceIndex)"))
    }

    // MARK: - V2.0 M8.D.2 — pin-sequence env-var replay mode

    @Test("stub reads SWIFT_INFER_PIN_SEQUENCE + SWIFT_INFER_PIN_PREFIX_LENGTH env vars (M8.D.2)")
    func stubReadsPinSequenceEnvVars() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(candidate()))
        #expect(source.contains("ProcessInfo.processInfo.environment"))
        #expect(source.contains(ActionSequenceStubEmitter.pinSequenceEnvVar))
        #expect(source.contains(ActionSequenceStubEmitter.pinPrefixLengthEnvVar))
    }

    @Test("stub skips non-target sequences via `continue` when pinSequence is set (M8.D.2)")
    func stubSkipsNonTargetSequences() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(candidate()))
        #expect(source.contains("if let pin = pinSequence, sequenceIndex != pin { continue }"))
    }

    @Test("stub truncates the action list via pinPrefix when supplied (M8.D.2)")
    func stubTruncatesActionListByPrefix() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(candidate()))
        // M8.D.4 — drop-prefix applies first (producing `dropped`),
        // then drop-suffix via `.prefix($0)` truncates that.
        #expect(source.contains("Array(dropped.prefix($0))"))
    }

    @Test("stub breaks after one execution in pinned mode — single-sequence replay (M8.D.2)")
    func stubBreaksAfterOneExecutionWhenPinned() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(candidate()))
        #expect(source.contains("if pinSequence != nil { break }"))
    }

    @Test("stub names match the public env-var constants — byte-stable (M8.D.2)")
    func stubEnvVarNamesAreStable() {
        #expect(ActionSequenceStubEmitter.pinSequenceEnvVar == "SWIFT_INFER_PIN_SEQUENCE")
        #expect(
            ActionSequenceStubEmitter.pinPrefixLengthEnvVar
                == "SWIFT_INFER_PIN_PREFIX_LENGTH"
        )
    }

    // MARK: - V2.0 M8.D.4 — drop-prefix env-var (suffix-start)

    @Test("stub reads SWIFT_INFER_PIN_SUFFIX_START env var (M8.D.4)")
    func stubReadsSuffixStartEnvVar() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(candidate()))
        #expect(source.contains(ActionSequenceStubEmitter.pinSuffixStartEnvVar))
        #expect(source.contains("let pinSuffixStart"))
    }

    @Test("stub drops leading actions via pinSuffixStart before truncating (M8.D.4)")
    func stubDropsLeadingActionsBeforePrefix() throws {
        let source = try ActionSequenceStubEmitter.emit(inputs(candidate()))
        // The drop-prefix step produces `dropped`; the drop-suffix
        // step then truncates `dropped`. Order matters.
        #expect(source.contains("Array(rawActions.dropFirst($0))"))
        #expect(source.contains("Array(dropped.prefix($0))"))
        // Ensure ordering: dropFirst occurs in the source before
        // dropped.prefix.
        let dropFirstIndex = source.range(of: "rawActions.dropFirst")!.lowerBound
        let prefixIndex = source.range(of: "dropped.prefix")!.lowerBound
        #expect(dropFirstIndex < prefixIndex)
    }

    @Test("M8.D.4 env-var name is byte-stable")
    func suffixStartEnvVarIsStable() {
        #expect(
            ActionSequenceStubEmitter.pinSuffixStartEnvVar
                == "SWIFT_INFER_PIN_SUFFIX_START"
        )
    }
}
