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
    static let v1_46HardcodedCarriers: Set<String> = ["Complex<Double>", "Double"]

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
        // Route 1: v1.46 hardcoded carriers keep their existing path.
        if v1_46HardcodedCarriers.contains(boundCarrier) {
            return try v1_46HardcodedBundle(
                entry: rebound(entry, toCarrier: boundCarrier),
                budget: budget
            )
        }
        // Route 2: strategist-routed carriers. Falls back to v1.46
        // when the strategist throws (e.g. carrier == "Int" with no
        // typeShape would hit the strategist's direct-RawType fast
        // path, but a typeShape-less unknown carrier would throw).
        do {
            return try strategistBundle(
                entry: rebound(entry, toCarrier: boundCarrier),
                budget: budget
            )
        } catch is VerifyError {
            return try v1_46HardcodedBundle(
                entry: rebound(entry, toCarrier: boundCarrier),
                budget: budget
            )
        }
    }

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
            // Curated-pair lookup mirrors RoundTripPairResolver but
            // skips the carrier check — the strategist owns carrier
            // validation here.
            let forwardBare = entry.primaryFunctionName
            guard let pair = RoundTripPairResolver.curated.first(
                where: { $0.forwardName == forwardBare }
            ) else {
                throw VerifyError.unsupportedPair(
                    forward: forwardBare,
                    supported: RoundTripPairResolver.curated.map(\.forwardName)
                )
            }
            let forwardCall = "\(typeQualifier).\(RoundTripPairResolver.stripParameterLabels(pair.forwardName))"
            let inverseCall = "\(typeQualifier).\(RoundTripPairResolver.stripParameterLabels(pair.inverseName))"
            return ResolvedCalls(
                expressions: [forwardCall, inverseCall],
                rendererForwardName: forwardCall,
                rendererInverseName: inverseCall
            )
        case "idempotence", "commutativity", "associativity":
            let call = "\(typeQualifier).\(funcName)"
            return ResolvedCalls(
                expressions: [call],
                rendererForwardName: call,
                rendererInverseName: call
            )
        case "idempotence-lifted", "monotonicity":
            // V1.48.B — same single-function shape as idempotence /
            // commutativity / associativity; the per-template emitter
            // wraps the call differently (idempotence-lifted lifts
            // through Gen<[T]>; monotonicity sorts before comparing).
            let call = "\(typeQualifier).\(funcName)"
            return ResolvedCalls(
                expressions: [call],
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

    private static func commutativityStubBundle(
        entry: SemanticIndexEntry,
        budget: CommutativityStubEmitter.TrialBudget
    ) throws -> VerifyStubBundle {
        let resolved = try CommutativityPairResolver.resolve(entry)
        let source = try CommutativityStubEmitter.emit(
            CommutativityStubEmitter.Inputs(
                functionCall: resolved.functionCall,
                extraImports: [],
                carrierType: entry.typeName ?? "(none)",
                seedHex: makeSeedHex(from: entry.identityHash),
                trialBudget: budget
            )
        )
        // For commutativity, both `forwardName` and `inverseName` slots
        // hold the same single function call. The renderer's
        // `RenderShape.commutativity` reads it once and produces
        // `f(lhs, rhs)` and `f(rhs, lhs)` for the two value lines.
        let context = VerifyResultRenderer.Context(
            templateName: "commutativity",
            forwardName: resolved.functionCall,
            inverseName: resolved.functionCall,
            carrierType: entry.typeName ?? "(none)"
        )
        return VerifyStubBundle(source: source, rendererContext: context)
    }

    private static func associativityStubBundle(
        entry: SemanticIndexEntry,
        budget: AssociativityStubEmitter.TrialBudget
    ) throws -> VerifyStubBundle {
        let resolved = try AssociativityPairResolver.resolve(entry)
        let source = try AssociativityStubEmitter.emit(
            AssociativityStubEmitter.Inputs(
                functionCall: resolved.functionCall,
                extraImports: [],
                carrierType: entry.typeName ?? "(none)",
                seedHex: makeSeedHex(from: entry.identityHash),
                trialBudget: budget
            )
        )
        // For associativity, both `forwardName` and `inverseName` slots
        // hold the same single function call. The renderer's
        // `RenderShape.associativity` reads it once and produces
        // `f(f(a, b), c)` and `f(a, f(b, c))` for the two value lines.
        let context = VerifyResultRenderer.Context(
            templateName: "associativity",
            forwardName: resolved.functionCall,
            inverseName: resolved.functionCall,
            carrierType: entry.typeName ?? "(none)"
        )
        return VerifyStubBundle(source: source, rendererContext: context)
    }
}
