import SwiftEffectInference
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// M1 coverage for `ReplayIdempotenceTemplate` — Branches A (annotation) and
/// B (`IdempotencyKey` parameter). The four SwiftIdempotency fixtures are the
/// acceptance set (see `docs/ideas/replay-idempotence-template-sketch.md` §6);
/// the two *annotated* fixtures are matchable in M1, the two unannotated ones are
/// deliberately deferred to M2 and asserted here as non-matches so the boundary
/// is pinned rather than silently drifting.
@Suite("ReplayIdempotenceTemplate — M1 (annotation + key parameter)")
struct ReplayIdempotenceTemplateTests {

    // MARK: - Fixtures / builders

    /// A `FunctionSummary` shaped like a replay handler. Mirrors
    /// `makeIdempotenceSummary` but exposes async/throws/static, which the replay
    /// shapes care about.
    private func makeReplaySummary(
        name: String,
        parameters: [Parameter] = [],
        returnType: String?,
        isAsync: Bool = true,
        isThrows: Bool = true,
        isStatic: Bool = true,
        containingType: String? = "Handler",
        bodySignals: BodySignals = .empty,
        dedupGateShape: DedupGateShape? = nil,
        declaredEffect: Effect? = nil
    ) -> FunctionSummary {
        let signals = dedupGateShape.map { shape in
            BodySignals(
                hasNonDeterministicCall: bodySignals.hasNonDeterministicCall,
                hasSelfComposition: bodySignals.hasSelfComposition,
                nonDeterministicAPIsDetected: bodySignals.nonDeterministicAPIsDetected,
                dedupGateShape: shape
            )
        } ?? bodySignals
        return FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returnType,
            isThrows: isThrows,
            isAsync: isAsync,
            isMutating: false,
            isStatic: isStatic,
            location: SourceLocation(file: "Handler.swift", line: 1, column: 1),
            containingTypeName: containingType,
            bodySignals: signals,
            declaredEffect: declaredEffect
        )
    }

    private func keyParam(label: String = "idempotencyKey") -> Parameter {
        Parameter(label: label, internalName: label, typeText: "IdempotencyKey", isInout: false)
    }

    // MARK: - Branch A: annotation

    @Test("Branch A: @ExternallyIdempotent handler is proposed")
    func annotationMatches() {
        // Shape of AcronymService.notifyCache: annotated, no key-typed param here.
        let summary = makeReplaySummary(
            name: "notifyCache",
            parameters: [Parameter(label: "acronym", internalName: "acronym", typeText: "Acronym", isInout: false)],
            returnType: nil,
            declaredEffect: .externallyIdempotent(keyParameter: "idempotencyKey")
        )
        let suggestion = ReplayIdempotenceTemplate.suggest(for: summary)
        #expect(suggestion != nil)
        #expect(suggestion?.templateName == "replay-idempotence")
        // +35 annotation alone → .possible band (20..<40).
        #expect(suggestion?.score.tier == .possible)
        #expect(
            suggestion?.score.signals.contains { $0.kind == .replayExternallyIdempotentAnnotation } ?? false
        )
    }

    @Test("Branch A + B: annotated AND key-typed handler reaches .likely")
    func annotatedAndKeyedReachesLikely() {
        // Shape of OfflineManager.download: @ExternallyIdempotent(by: "idempotencyKey")
        // AND an idempotencyKey: IdempotencyKey parameter.
        let summary = makeReplaySummary(
            name: "download",
            parameters: [
                Parameter(label: "album", internalName: "album", typeText: "Album", isInout: false),
                keyParam(),
                Parameter(label: "in", internalName: "container", typeText: "ModelContainer", isInout: false)
            ],
            returnType: "OfflineAlbum",
            declaredEffect: .externallyIdempotent(keyParameter: "idempotencyKey")
        )
        let suggestion = ReplayIdempotenceTemplate.suggest(for: summary)
        #expect(suggestion?.templateName == "replay-idempotence")
        // 35 + 25 = 60 → .likely band (40..<75).
        #expect(suggestion?.score.tier == .likely)
    }

    // MARK: - Branch B: key parameter

    @Test("Branch B: a bare IdempotencyKey parameter is proposed")
    func keyParameterMatches() {
        let summary = makeReplaySummary(
            name: "chargeCard",
            parameters: [
                Parameter(label: "amount", internalName: "amount", typeText: "Int", isInout: false),
                keyParam()
            ],
            returnType: nil
        )
        let suggestion = ReplayIdempotenceTemplate.suggest(for: summary)
        #expect(suggestion != nil)
        #expect(suggestion?.score.tier == .possible)
        #expect(
            suggestion?.score.signals.contains { $0.kind == .replayIdempotencyKeyParameter } ?? false
        )
    }

    // MARK: - Vetoes / non-matches

    @Test("@NonIdempotent vetoes even with a key parameter")
    func declaredNonIdempotentVetoes() {
        let summary = makeReplaySummary(
            name: "handle",
            parameters: [keyParam()],
            returnType: nil,
            declaredEffect: .nonIdempotent
        )
        #expect(ReplayIdempotenceTemplate.suggest(for: summary) == nil)
    }

    @Test("No annotation, no key, and no detected gate → not a candidate")
    func plainHandlerWithNoGateIsNotACandidate() {
        // A handler the walker found no dedup gate in (the ungated buggy twin, or
        // any effectful function that isn't a replay handler). No gate, no proposal.
        let summary = makeReplaySummary(
            name: "handle",
            parameters: [Parameter(label: nil, internalName: "order", typeText: "Order", isInout: false)],
            returnType: "Bool"
        )
        #expect(ReplayIdempotenceTemplate.suggest(for: summary) == nil)
    }

    // MARK: - Branch C: dedup gate (M2)

    @Test("Branch C: a detected dedup gate is proposed, even unannotated & unkeyed")
    func dedupGateMatches() {
        // OrderCreatedHandler.handle: no annotation, no IdempotencyKey parameter,
        // but the walker found an early-return dedup gate.
        let summary = makeReplaySummary(
            name: "handle",
            parameters: [Parameter(label: nil, internalName: "order", typeText: "Order", isInout: false)],
            returnType: "Bool",
            dedupGateShape: .earlyReturnDedup(keyRoot: "order")
        )
        let suggestion = ReplayIdempotenceTemplate.suggest(for: summary)
        #expect(suggestion?.templateName == "replay-idempotence")
        // +30 gate alone → .possible band.
        #expect(suggestion?.score.tier == .possible)
        #expect(suggestion?.score.signals.contains { $0.kind == .replayDedupGate } ?? false)
    }

    @Test("Branch C + B: a gate plus a key parameter reaches .likely")
    func gateAndKeyReachesLikely() {
        let summary = makeReplaySummary(
            name: "download",
            parameters: [keyParam()],
            returnType: "Row",
            dedupGateShape: .fetchThenInsert
        )
        // 30 + 25 = 55 → .likely.
        #expect(ReplayIdempotenceTemplate.suggest(for: summary)?.score.tier == .likely)
    }

    @Test("A pure value function is not a replay candidate")
    func pureFunctionIsNotACandidate() {
        // Shape of PricingCalculator.priceInCents — value idempotence's turf.
        let summary = makeReplaySummary(
            name: "priceInCents",
            parameters: [Parameter(label: "kg", internalName: "kg", typeText: "Int", isInout: false)],
            returnType: "Int",
            isAsync: false,
            isThrows: false
        )
        #expect(ReplayIdempotenceTemplate.suggest(for: summary) == nil)
    }

    @Test("Non-deterministic body demotes an otherwise-possible key handler")
    func nonDeterministicBodyDemotesToSuppressed() {
        // Branch B alone is +25; a -15 non-determinism counter drops it to 10,
        // below the .possible floor (20) → suppressed → nil.
        let summary = makeReplaySummary(
            name: "enqueue",
            parameters: [keyParam()],
            returnType: nil,
            bodySignals: BodySignals(
                hasNonDeterministicCall: true,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: ["UUID.init"]
            )
        )
        #expect(ReplayIdempotenceTemplate.suggest(for: summary) == nil)
    }

    // MARK: - Emitter

    @Test("Emitter produces an assertIdempotentEffects scaffold that fails until completed")
    func emitterScaffoldShape() {
        let stub = LiftedTestEmitter.replayIdempotent(
            funcName: "download",
            keyLabel: "idempotencyKey",
            ownerType: "OfflineManager",
            isAsync: true,
            isThrows: true
        )
        #expect(stub.contains("download_isReplayIdempotent"))
        #expect(stub.contains("assertIdempotentEffects"))
        #expect(stub.contains("IdempotentEffectRecorder"))
        // No silent green: an incomplete scaffold records an issue.
        #expect(stub.contains("Issue.record"))
        // Key label threaded into the guidance.
        #expect(stub.contains("idempotencyKey"))
    }
}
