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

    /// Single source of truth for the templates `verify` supports, used both to validate an
    /// incoming template and to populate the `unsupportedTemplate` error's `expected` list.
    /// Previously this list was hand-copied at each throw site, and the copies drifted — the
    /// `resolveFunctionCalls` error list had lost `codable-round-trip` even though that function
    /// handles it. Deriving every error message from this one constant makes the drift impossible.
    static let supportedTemplates: [String] = TemplateName.verifiable.rawValues

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
        guard supportedTemplates.contains(entry.templateName) else {
            // A template with no composer is normally `unsupportedTemplate` — a swift-infer
            // gap. For the equality-shaped templates it is worth checking whether a composer
            // would even help, because for a non-Equatable carrier it would not: the law it
            // emits cannot be written. Reported as its own cause rather than as a gap that
            // could one day close.
            try requireEquatableCarrierIfLawNeedsIt(entry: entry, allShapes: allShapes)
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
    private static let v146HardcodedTemplates: Set<String> = Set(TemplateName.v146Hardcoded.rawValues)

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
                expected: TemplateName.v146Hardcoded.rawValues
            )
        }
    }

    /// The type a `round-trip` law quantifies over, when that is *not* the
    /// declaring type. `nil` means "no opinion" and the caller keeps the
    /// `carrierTypeName ?? typeName` behaviour it had before this existed.
    ///
    /// The composer emits `inverse(forward(value)) != value`, so `value` must have
    /// the type `forward` **accepts** — which is the declaring type only when the
    /// forward half is the receiver. For a parse/print pair the forward is a static
    /// factory over someone else's type:
    ///
    ///     static func parse(_ text: String) -> Self     // forward
    ///     func serialized() -> String                   // inverse
    ///
    /// Here the round trip is anchored at `String`, not at the carrier. Measured on
    /// SwiftFormatRuleStudio (issue #235): the entry generated
    /// `Generator<SwiftFormatConfig>` and then fed it to `parse`, which takes a
    /// `String` — `cannot convert value of type 'SwiftFormatConfig' to expected
    /// argument type 'String'`, twice, before anything ran.
    ///
    /// Anchoring at the parameter also *dissolves* the isolation failure that was
    /// first reported as the defect: nothing constructs the carrier inside a
    /// `@Sendable` generator closure any more, so a MainActor-isolated carrier stops
    /// mattering for this shape.
    ///
    /// Three guards, and each excludes a case the rule would get wrong:
    /// - **instance-method forward** — the value IS the receiver, so the declaring
    ///   type is already right;
    /// - **exactly one parameter** — a two-argument forward has no single domain,
    ///   and guessing one is how `parameterTypeNames` was needed in the first place;
    /// - **non-empty `parameterTypeNames`** — empty means *not recorded* (an index
    ///   written before that field), and the fallback must be the old behaviour
    ///   rather than a guess.
    ///
    /// Bit-identical for the curated `Complex`/`Double`/`Int` pairs: `Complex.exp`
    /// takes one `Complex<Double>`, which is what `typeName` already said.
    static func roundTripDomainCarrier(entry: SemanticIndexEntry) -> String? {
        guard entry.templateName == "round-trip",
              !entry.isInstanceMethod,
              entry.parameterTypeNames.count == 1,
              let domain = entry.parameterTypeNames.first,
              !domain.isEmpty else { return nil }
        return domain
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
        // The `selfType:` overload rebinds a bare `Self` carrier to the owning
        // type; `Self.Index` / `Self.Element` keep their curated bindings.
        let boundCarrier = GenericBindingResolver.bound(
            roundTripDomainCarrier(entry: entry)
                ?? monotonicityReceiverCarrier(entry: entry)
                ?? entry.carrierTypeName ?? entry.typeName ?? "(none)",
            selfType: entry.typeName
        )
        // Homomorphism quantifies over arrays `[T]`; its composer draws arrays by
        // wrapping an ELEMENT generator, so the generator carrier is the element
        // type — strip the array brackets (`[Int]` → `Int`).
        let elementCarrier = entry.templateName == "homomorphism"
            ? arrayElementType(of: boundCarrier)
            : boundCarrier
        let generatorCarrier = qualifyingNestedCarrier(elementCarrier, in: allShapes)
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
            returnsSelfType: entry.returnsSelfType,
            isComputedProperty: entry.isComputedProperty,
            parameterCount: argumentLabels(from: entry.primaryFunctionName).count,
            parameterTypeNames: entry.parameterTypeNames,
            // Only when the emitted call actually has a receiver — see `receiverCallExpression`,
            // whose guard this mirrors. `typeName` is the declaring type; `carrierTypeName` is
            // the first parameter's, and using it here would generate the wrong type.
            receiverTypeName: entry.isInstanceMethod && !entry.isMutatingMethod
                ? entry.typeName
                : nil
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
    /// - Parameter diagnostic: reports a call-resolution failure. Defaults to a no-op.
    ///
    /// **The guard used to conflate two outcomes.** A template that is not
    /// `regressionAutoDerivable` is the normal, expected skip — most templates are not, and
    /// saying so on every refutation would be noise. A template that IS auto-derivable but
    /// whose calls fail to resolve is a different fact: the tool refuted a law, could have
    /// banked the counterexample as a regression test, and silently did not.
    ///
    /// That matters because a survey verdict is a measurement, not regression protection —
    /// `roadtest-self-dogfood-2026-08-08.md` §8.6 makes the point that "81 Proven" is not 81
    /// tests, and banking is what converts one into the other. A bank that quietly declines
    /// leaves the refutation unprotected with nothing to notice.
    static func emitRegressionTest(
        entry: SemanticIndexEntry,
        detail: DefaultFailDetail,
        packageRoot: URL,
        diagnostic: (String) -> Void = { _ in /* no-op */ }
    ) -> URL? {
        let autoDerivable = Set(TemplateName.regressionAutoDerivable.rawValues)
        // Not auto-derivable: the normal case, deliberately silent.
        guard autoDerivable.contains(entry.templateName) else { return nil }
        let calls: ResolvedCalls
        do {
            calls = try resolveFunctionCalls(for: entry)
        } catch {
            diagnostic(
                "warning: \(entry.primaryFunctionName) was refuted and its template supports "
                    + "an auto-derived regression test, but its calls could not be resolved — "
                    + "\(error). The counterexample is NOT banked; nothing will re-check this "
                    + "refutation."
            )
            return nil
        }
        // Prefer the minimal (shrunk) counterexample; fall back to the first
        // failing input when the carrier wasn't shrinkable.
        let counterexample = detail.shrink?.minimal ?? detail.input
        let args = ConvertCounterexampleEngine.Args(
            template: entry.templateName,
            callee: calls.rendererForwardName,
            // The type the law QUANTIFIES OVER, which is the declaring type only when the forward
            // half is the receiver — see `roundTripDomainCarrier`. Passing `typeName` bound the
            // regression stub's `value` to the carrier while the verifier generated the parameter
            // type, so the two disagreed about the law's domain and the stub could not compile
            // (#249). #236 fixed this on the verify side and did not reach here.
            type: roundTripDomainCarrier(entry: entry) ?? entry.typeName ?? "(none)",
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

    /// Templates whose emitted law compares two values with `==`.
    ///
    /// **Curated, and deliberately only the two that were measured.** Widening this by
    /// eyeballing template names would re-attribute rows on a guess, and the whole point of
    /// this cause is that it is *more* precise than the two it sits between. A template joins
    /// when someone has looked at its emitted law and seen the `==`.
    static let equalityShapedTemplates: Set<String> = ["inverse-pair", "identity-element"]

    /// Throw `carrierNotEquatable` when the law needs `==` and the carrier provably lacks it.
    ///
    /// **Conservative in the direction that matters: silence unless certain.** Answering
    /// "not Equatable" wrongly would relabel a row whose real blocker is the composer, hiding
    /// a gap that *can* close behind one that cannot. So this fires only when a shape for the
    /// carrier was actually scanned and lists none of `Equatable` / `Hashable` / `Comparable`
    /// — each of which requires or implies `Equatable`. No shape, no claim: an unscanned
    /// carrier, a stdlib type, or a conformance added in a module we did not read all fall
    /// through to the previous behaviour.
    static func requireEquatableCarrierIfLawNeedsIt(
        entry: SemanticIndexEntry,
        allShapes: [String: IndexedTypeShape]
    ) throws {
        guard equalityShapedTemplates.contains(entry.templateName) else { return }
        guard let carrier = entry.carrierTypeName ?? entry.typeName else { return }
        let bare = GenericBindingResolver.bound(carrier)
        // A generic carrier's shape is keyed by its bare name; try both spellings before
        // concluding anything, since concluding requires a shape.
        guard let shape = allShapes[bare] ?? allShapes[carrier] else { return }
        let equalityConformances: Set<String> = ["Equatable", "Hashable", "Comparable"]
        guard shape.inheritedTypes.allSatisfy({ !equalityConformances.contains($0) }) else {
            return
        }
        throw VerifyError.carrierNotEquatable(carrier: carrier, template: entry.templateName)
    }
}
