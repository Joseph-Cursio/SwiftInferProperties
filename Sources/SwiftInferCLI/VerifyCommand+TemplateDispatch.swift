import Foundation
import SwiftInferCore

/// V1.44.D — template dispatch lives here so `VerifyCommand.swift`
/// stays under the file-length cap. Extends `SwiftInferCommand.Verify`
/// with the per-template stub-bundle builders.
///
/// Bundle of the synthesized stub source + the renderer context it
/// implies. File-scoped (not nested in `Verify`) to keep the type-
/// hierarchy within SwiftLint's `nesting` rule.
struct VerifyStubBundle {
    let source: String
    let rendererContext: VerifyResultRenderer.Context
}

extension SwiftInferCommand.Verify {

    /// V1.47.F carrier-name set the v1.46 hardcoded emitters
    /// (`RoundTripStubEmitter` / `IdempotenceStubEmitter` /
    /// `CommutativityStubEmitter` / `AssociativityStubEmitter`)
    /// continue to own. These carriers encode floating-point edge-pass
    /// intelligence — `Complex<Double>` has the 12-entry curated
    /// `Gen<Complex<Double>>.edgeCaseBiased()` list (V1.43.C);
    /// `Double` has the inlined `doubleWithNaN` pass (V1.44.B). The
    /// `DerivationStrategist`'s `.rawRepresentable(.double)` strategy
    /// emits a finite-domain `Gen<Double>` only, which loses that
    /// edge intelligence — so v1.47 explicitly keeps these two
    /// carriers on the v1.46 path. Folding them into the strategist
    /// (probably as a new `.curatedFP` strategy case) is a v1.48+
    /// kit-side cleanup target.
    static let v146HardcodedCarriers: Set<String> = ["Complex<Double>", "Double"]

    /// V1.47.F — top-level dispatch. First normalizes the carrier via
    /// `GenericBindingResolver` (e.g. `"Base.Index"` → `"Int"`), then
    /// routes:
    ///   1. v1.46 hardcoded carriers (`Complex<Double>` / `Double`)
    ///      → existing per-template builders.
    ///   2. everything else → `StrategistDispatchEmitter` (handles
    ///      `Int` / `String` / `Bool` / fixed-width ints / enums).
    ///   3. strategist throws (unknown carrier without `typeShape`,
    ///      strategist returns `.todo` / `.memberwiseArbitrary`) →
    ///      fall back to the v1.46 per-template builder so existing
    ///      Int / Complex<Double> / Double pipelines stay green even
    ///      when the strategist path can't help.
    static func buildStubBundle(
        entry: SemanticIndexEntry,
        budget: RoundTripStubEmitter.TrialBudget
    ) throws -> VerifyStubBundle {
        let supportedTemplates: [String] = [
            "round-trip", "idempotence", "commutativity", "associativity",
            "idempotence-lifted", "dual-style-consistency", "monotonicity"
        ]
        guard supportedTemplates.contains(entry.templateName) else {
            throw VerifyError.unsupportedTemplate(
                template: entry.templateName,
                expected: supportedTemplates
            )
        }
        let rawCarrier = entry.typeName ?? "(none)"
        let boundCarrier = GenericBindingResolver.bound(rawCarrier)
        // Route 1: v1.46 hardcoded carriers + v1.46-supported templates
        // keep their existing path. **V1.51.C routing flip**: v1.48
        // templates (idempotence-lifted / dual-style-consistency /
        // monotonicity) always route through the strategist even when
        // the carrier is in v146HardcodedCarriers — the v1.46
        // hardcoded path doesn't implement them and the strategist
        // handles them via the v1.49 emitter family. Cycle-47 found 2
        // monotonicity × Double picks misrouted to v1_46HardcodedBundle's
        // default branch; v1.51.C closes that gap.
        let isV146TemplateOnV146Carrier = v146HardcodedCarriers.contains(boundCarrier)
            && v146HardcodedTemplates.contains(entry.templateName)
        if isV146TemplateOnV146Carrier {
            return try v1_46HardcodedBundle(
                entry: rebound(entry, toCarrier: boundCarrier),
                budget: budget
            )
        }
        // Route 2: strategist-routed carriers. Falls back to v1.46
        // when the strategist throws **only for templates the v1.46
        // path supports** (round-trip / idempotence / commutativity /
        // associativity). v1.48 templates (idempotence-lifted /
        // dual-style-consistency / monotonicity) have no v1.46
        // hardcoded path — the fallback for those would surface a
        // misleading `.unsupportedTemplate` instead of the original
        // strategist error. **V1.50.B finding**: the cycle-47 full-
        // surface measurement revealed this misrouting — 49 of the
        // 109 picks were classified as "unsupported-template" when
        // the real reason was strategist-side carrier-unsupported.
        do {
            return try strategistBundle(
                entry: rebound(entry, toCarrier: boundCarrier),
                budget: budget
            )
        } catch let error as VerifyError {
            if Self.v146HardcodedTemplates.contains(entry.templateName) {
                return try v1_46HardcodedBundle(
                    entry: rebound(entry, toCarrier: boundCarrier),
                    budget: budget
                )
            }
            throw error
        }
    }

    /// V1.50.B — the 4 templates the v1.46 hardcoded emitters
    /// support. Used to gate the strategist→v1.46 fallback in
    /// `buildStubBundle` so v1.48-template entries surface their
    /// real strategist error rather than a misleading
    /// `.unsupportedTemplate` from the v1.46 path's default case.
    private static let v146HardcodedTemplates: Set<String> = [
        "round-trip", "idempotence", "commutativity", "associativity"
    ]

    /// Helper — produce a copy of `entry` with `typeName` set to
    /// `carrier`. Used to thread the `GenericBindingResolver`-bound
    /// carrier into the per-template builders without leaking the
    /// bound form back to the SemanticIndex.
    private static func rebound(
        _ entry: SemanticIndexEntry,
        toCarrier carrier: String
    ) -> SemanticIndexEntry {
        guard entry.typeName != carrier else { return entry }
        return SemanticIndexEntry(
            identityHash: entry.identityHash,
            templateName: entry.templateName,
            typeName: carrier,
            score: entry.score,
            tier: entry.tier,
            primaryFunctionName: entry.primaryFunctionName,
            location: entry.location,
            decision: entry.decision,
            decisionAt: entry.decisionAt,
            firstSeenAt: entry.firstSeenAt,
            lastSeenAt: entry.lastSeenAt,
            typeShape: entry.typeShape
        )
    }

    /// Route 1 — existing v1.46 per-template dispatch.
    private static func v1_46HardcodedBundle(
        entry: SemanticIndexEntry,
        budget: RoundTripStubEmitter.TrialBudget
    ) throws -> VerifyStubBundle {
        switch entry.templateName {
        case "round-trip":
            return try roundTripStubBundle(entry: entry, budget: budget)

        case "idempotence":
            return try idempotenceStubBundle(entry: entry, budget: budget)

        case "commutativity":
            return try commutativityStubBundle(entry: entry, budget: budget)

        case "associativity":
            return try associativityStubBundle(entry: entry, budget: budget)

        default:
            throw VerifyError.unsupportedTemplate(
                template: entry.templateName,
                expected: ["round-trip", "idempotence", "commutativity", "associativity"]
            )
        }
    }

    /// Route 2 — strategist-routed dispatch. Resolves the call
    /// expressions per template (reusing the existing pair resolvers),
    /// then emits via `StrategistDispatchEmitter`.
    private static func strategistBundle(
        entry: SemanticIndexEntry,
        budget: StrategistDispatchEmitter.TrialBudget
    ) throws -> VerifyStubBundle {
        let calls = try resolveFunctionCalls(for: entry)
        let inputs = StrategistDispatchEmitter.Inputs(
            carrier: entry.typeName ?? "(none)",
            typeShape: entry.typeShape,
            template: entry.templateName,
            functionCalls: calls.expressions,
            extraImports: [],
            seedHex: makeSeedHex(from: entry.identityHash),
            trialBudget: budget
        )
        let source = try StrategistDispatchEmitter.emit(inputs)
        let context = VerifyResultRenderer.Context(
            templateName: entry.templateName,
            forwardName: calls.rendererForwardName,
            inverseName: calls.rendererInverseName,
            carrierType: entry.typeName ?? "(none)"
        )
        return VerifyStubBundle(source: source, rendererContext: context)
    }

    /// Pair / single-function resolution layer shared across templates
    /// when the strategist path emits. Round-trip resolves the curated
    /// forward+inverse pair; idempotence / commutativity / associativity
    /// resolve the single function call.
    private struct ResolvedCalls {
        let expressions: [String]
        let rendererForwardName: String
        let rendererInverseName: String
    }

    /// Build call expressions for the strategist path, inlining the
    /// resolvers' call-construction logic to sidestep their v1.46
    /// `supportedCarriers` validation (which would reject `String` /
    /// `Bool` / enum / `.userGen` carriers that the strategist emits
    /// fine). Round-trip still looks up the curated pair list to
    /// discover the inverse half — strategist routing doesn't change
    /// that piece of the design.
    private static func resolveFunctionCalls(for entry: SemanticIndexEntry) throws -> ResolvedCalls {
        let carrier = entry.typeName ?? "(none)"
        let typeQualifier = RoundTripPairResolver.bareTypeName(from: carrier)
        let funcName = RoundTripPairResolver.stripParameterLabels(entry.primaryFunctionName)
        switch entry.templateName {
        case "round-trip":
            return try resolveRoundTripCalls(entry: entry, typeQualifier: typeQualifier)

        case "idempotence", "commutativity", "associativity":
            let call = CallExpressionShape.render(
                typeQualifier: typeQualifier,
                bareFunctionName: funcName
            )
            return ResolvedCalls(
                expressions: [call],
                rendererForwardName: call,
                rendererInverseName: call
            )

        case "idempotence-lifted", "monotonicity":
            // V1.48.B — single-function shape. V1.69 — monotonicity's OC
            // composer also needs the un-stripped `primaryFunctionName`
            // (e.g. `"index(after:)"`) to recover the labeled-arg name;
            // the Int/String composer reads only `functionCalls.first`.
            let call = CallExpressionShape.render(typeQualifier: typeQualifier, bareFunctionName: funcName)
            let expressions = entry.templateName == "monotonicity"
                ? [call, entry.primaryFunctionName]
                : [call]
            return ResolvedCalls(
                expressions: expressions,
                rendererForwardName: call,
                rendererInverseName: call
            )

        case "dual-style-consistency":
            // V1.48.B — pair of expressions: [nonMutCall, mutMethodName].
            // Resolver fires its own validation (carrier-agnostic;
            // curated pair list check). Renderer surfaces both halves
            // as forward / inverse names.
            let pair = try DualStyleConsistencyPairResolver.resolve(entry)
            return ResolvedCalls(
                expressions: [pair.nonMutCall, pair.mutMethodName],
                rendererForwardName: pair.nonMutCall,
                rendererInverseName: pair.mutMethodName
            )

        default:
            throw VerifyError.unsupportedTemplate(
                template: entry.templateName,
                expected: [
                    "round-trip", "idempotence", "commutativity", "associativity",
                    "idempotence-lifted", "dual-style-consistency", "monotonicity"
                ]
            )
        }
    }

    /// V1.89 lint pass — extracted from `resolveFunctionCalls` so the
    /// switch body stays under SwiftLint's 50-line cap. Mirrors
    /// `RoundTripPairResolver.resolve`'s curated-first /
    /// `secondaryFunctionName`-fallback chain; skips the carrier check
    /// because the strategist owns carrier validation at this layer.
    private static func resolveRoundTripCalls(
        entry: SemanticIndexEntry,
        typeQualifier: String
    ) throws -> ResolvedCalls {
        let forwardBare = entry.primaryFunctionName
        if let pair = RoundTripPairResolver.curated.first(
            where: { $0.forwardName == forwardBare }
        ) {
            let forwardCall = CallExpressionShape.render(
                typeQualifier: typeQualifier,
                bareFunctionName: RoundTripPairResolver.stripParameterLabels(pair.forwardName)
            )
            let inverseCall = CallExpressionShape.render(
                typeQualifier: typeQualifier,
                bareFunctionName: RoundTripPairResolver.stripParameterLabels(pair.inverseName)
            )
            return ResolvedCalls(
                expressions: [forwardCall, inverseCall],
                rendererForwardName: forwardCall,
                rendererInverseName: inverseCall
            )
        }
        if let inverseBare = entry.secondaryFunctionName {
            let forwardCall = CallExpressionShape.render(
                typeQualifier: typeQualifier,
                bareFunctionName: RoundTripPairResolver.stripParameterLabels(forwardBare)
            )
            let inverseCall = CallExpressionShape.render(
                typeQualifier: typeQualifier,
                bareFunctionName: RoundTripPairResolver.stripParameterLabels(inverseBare)
            )
            return ResolvedCalls(
                expressions: [forwardCall, inverseCall],
                rendererForwardName: forwardCall,
                rendererInverseName: inverseCall
            )
        }
        throw VerifyError.unsupportedPair(
            forward: forwardBare,
            supported: RoundTripPairResolver.curated.map(\.forwardName)
        )
    }

    private static func roundTripStubBundle(
        entry: SemanticIndexEntry,
        budget: RoundTripStubEmitter.TrialBudget
    ) throws -> VerifyStubBundle {
        let pair = try RoundTripPairResolver.resolve(entry)
        let source = try RoundTripStubEmitter.emit(
            RoundTripStubEmitter.Inputs(
                forwardCall: pair.forwardCall,
                inverseCall: pair.inverseCall,
                extraImports: [],
                carrierType: entry.typeName ?? "(none)",
                seedHex: makeSeedHex(from: entry.identityHash),
                trialBudget: budget
            )
        )
        let context = VerifyResultRenderer.Context(
            templateName: "round-trip",
            forwardName: pair.forwardCall,
            inverseName: pair.inverseCall,
            carrierType: entry.typeName ?? "(none)"
        )
        return VerifyStubBundle(source: source, rendererContext: context)
    }

    private static func idempotenceStubBundle(
        entry: SemanticIndexEntry,
        budget: IdempotenceStubEmitter.TrialBudget
    ) throws -> VerifyStubBundle {
        let resolved = try IdempotencePairResolver.resolve(entry)
        let source = try IdempotenceStubEmitter.emit(
            IdempotenceStubEmitter.Inputs(
                functionCall: resolved.functionCall,
                extraImports: [],
                carrierType: entry.typeName ?? "(none)",
                seedHex: makeSeedHex(from: entry.identityHash),
                trialBudget: budget
            )
        )
        let context = VerifyResultRenderer.Context(
            templateName: "idempotence",
            forwardName: resolved.functionCall,
            inverseName: resolved.functionCall,
            carrierType: entry.typeName ?? "(none)"
        )
        return VerifyStubBundle(source: source, rendererContext: context)
    }
}
