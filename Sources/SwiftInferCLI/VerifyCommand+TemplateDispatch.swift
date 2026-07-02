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
    ///      strategist returns `.todo`) → the error propagates. **WS-3a**
    ///      removed the old v1.46 fallback here: a v1.46-template pick that
    ///      reaches Route 2 always has a non-numeric carrier, so the fallback
    ///      could only mask the strategist's real reason with a bogus
    ///      `[Complex<Double>, Double, Int]` list against the owner type.
    static func buildStubBundle(
        entry: SemanticIndexEntry,
        budget: RoundTripStubEmitter.TrialBudget,
        extraImports: [String] = [],
        allShapes: [String: IndexedTypeShape] = [:]
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
        // Route 2: strategist-routed carriers. WS-3a — no v1.46 fallback.
        // By the time a v1.46-template pick (round-trip / idempotence /
        // commutativity / associativity) reaches here, its carrier is
        // necessarily non-numeric: numeric carriers either took Route 1
        // (Complex<Double> / Double) or derive as RawTypes inside the
        // strategist (Int). A fallback to the v1.46 hardcoded path could
        // therefore only re-throw `.unsupportedCarrier([Complex<Double>,
        // Double, Int])` against the *owner* type, masking the strategist's
        // real reason (the actual non-derivable generator carrier, or a
        // `.todo` naming the missing generator). The V1.50.B fallback already
        // excluded the v1.48 templates for exactly this reason; WS-3a extends
        // that to the v1.46 templates — let the strategist's truthful error
        // propagate. (`v146HardcodedTemplates` / `v1_46HardcodedBundle` remain
        // in use for Route 1's direct numeric-carrier dispatch above.)
        return try strategistBundle(
            entry: rebound(entry, toCarrier: boundCarrier),
            budget: budget,
            extraImports: extraImports,
            allShapes: allShapes
        )
    }

    /// The 4 templates the v1.46 hardcoded emitters support. Gates Route 1's
    /// direct numeric-carrier dispatch (paired with `v146HardcodedCarriers`).
    /// The V1.50.B strategist→v1.46 fallback that also read this was removed in
    /// WS-3a (it only masked the strategist's real error).
    private static let v146HardcodedTemplates: Set<String> = [
        "round-trip", "idempotence", "commutativity", "associativity"
    ]

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
        budget: StrategistDispatchEmitter.TrialBudget,
        extraImports: [String] = [],
        allShapes: [String: IndexedTypeShape] = [:]
    ) throws -> VerifyStubBundle {
        let calls = try resolveFunctionCalls(for: entry)
        // V1.149 — generator carrier is `carrierTypeName` (param `T`), distinct
        // from `typeName` (the call-site owner `resolveFunctionCalls` already
        // used); `?? typeName` keeps pre-v1.149 entries bit-identical.
        let generatorCarrier = GenericBindingResolver.bound(entry.carrierTypeName ?? entry.typeName ?? "(none)")
        let inputs = StrategistDispatchEmitter.Inputs(
            carrier: generatorCarrier,
            typeShape: entry.typeShape,
            template: entry.templateName,
            functionCalls: calls.expressions,
            extraImports: extraImports,
            seedHex: makeSeedHex(from: entry.identityHash),
            trialBudget: budget,
            // WS-6 Slice 2 — pass the whole-module shape universe so the emitter
            // can build a recursive resolver for nested custom-type carriers.
            allShapes: allShapes,
            isInstanceMethod: entry.isInstanceMethod,
            isMutatingMethod: entry.isMutatingMethod,
            isNullary: entry.isNullary,
            returnsSelfType: entry.returnsSelfType
        )
        let source = try StrategistDispatchEmitter.emit(inputs)
        let context = VerifyResultRenderer.Context(
            templateName: entry.templateName,
            forwardName: calls.rendererForwardName,
            inverseName: calls.rendererInverseName,
            carrierType: generatorCarrier
        )
        return VerifyStubBundle(source: source, rendererContext: context)
    }

    /// V1.142 auto-bridge — render + write a focused regression test from a
    /// verify counterexample (`.defaultFails`) via `ConvertCounterexampleEngine`.
    /// Returns the written path, or `nil` when the template isn't auto-derivable
    /// from the index entry (identity-element / invariant-preservation /
    /// reduce-equivalence / count-invariance need args the entry doesn't carry;
    /// dual-style / idempotence-lifted aren't `ConvertCounterexampleEngine`
    /// shapes) — a graceful skip, since the verify stub already reported the
    /// counterexample. Best-effort: never throws into the verify gesture.
    static func emitRegressionTest(
        entry: SemanticIndexEntry,
        detail: DefaultFailDetail,
        packageRoot: URL
    ) -> URL? {
        let autoDerivable: Set<String> = [
            "round-trip", "idempotence", "commutativity", "associativity", "monotonicity"
        ]
        guard autoDerivable.contains(entry.templateName),
            let calls = try? resolveFunctionCalls(for: entry) else { return nil }
        // Prefer the minimal (shrunk) counterexample; fall back to the first
        // failing input when the carrier wasn't shrinkable.
        let counterexample = detail.shrink?.minimal ?? detail.input
        let args = ConvertCounterexampleEngine.Args(
            template: entry.templateName,
            callee: calls.rendererForwardName,
            type: entry.typeName ?? "(none)",
            counterexample: counterexample,
            reverseCallee: entry.templateName == "round-trip" ? calls.rendererInverseName : nil
        )
        guard let stub = try? ConvertCounterexampleEngine.renderRegressionStub(args: args),
            let path = try? ConvertCounterexampleEngine.writeRegressionStub(
                args: args,
                stub: stub,
                packageRoot: packageRoot
            ) else { return nil }
        return path
    }

    /// Pair / single-function resolution layer shared across templates
    /// when the strategist path emits. Round-trip resolves the curated
    /// forward+inverse pair; idempotence / commutativity / associativity
    /// resolve the single function call.
    struct ResolvedCalls {
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

        case "idempotence":
            // Static/free shape; idempotence's own composer emits the receiver
            // form for mutating / self-returning instance methods.
            return singleCallResolved(
                entry: entry, typeQualifier: typeQualifier, funcName: funcName, receiverShape: false
            )

        case "commutativity", "associativity":
            // Binary instance ops emit the receiver shape here.
            return singleCallResolved(
                entry: entry, typeQualifier: typeQualifier, funcName: funcName, receiverShape: true
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
