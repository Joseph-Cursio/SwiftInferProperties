import SwiftInferCore
import SwiftInferTemplates

/// TestLifter M5.5 — lifted-only dispatch helpers for promoted
/// `LiftedSuggestion` records that route through `liftedTestStub` with
/// `liftedOrigin != nil`. Split out of `InteractiveTriage+Accept.swift`
/// to keep that file under SwiftLint's 400-line file-length limit.
///
/// **Why a separate dispatch.** Two M5 patterns produce promoted
/// suggestions whose `templateName` matches an existing TemplateEngine
/// template (`countInvariance` → `"invariant-preservation"`,
/// `reduceEquivalence` → `"associativity"`) but whose semantically-
/// honest test stub differs from what the TemplateEngine-side arm
/// emits. PRD §3.5 conservative-bias posture: the lifted side surfaces
/// what the test body actually claimed (direct `f(xs).count == xs.count`
/// equality, direct `xs.reduce(s, op) == xs.reversed().reduce(s, op)`
/// equality), not a more general algebraic shape (Bool-keypath
/// implication, full algebraic associativity).
extension InteractiveTriage {

    /// Returns a lifted-only stub if `suggestion` was promoted from
    /// TestLifter (`liftedOrigin != nil`) AND its `templateName` has a
    /// dedicated lifted-only arm; nil otherwise. Caller's switch
    /// continues to the existing TemplateEngine-side arms when this
    /// returns nil.
    static func liftedOnlyTestStub(for suggestion: Suggestion) -> String? {
        guard suggestion.liftedOrigin != nil else { return nil }
        switch suggestion.templateName {
        case "invariant-preservation":
            return liftedCountInvarianceStub(for: suggestion)
        case "associativity":
            return liftedReduceEquivalenceStub(for: suggestion)
        default:
            return nil
        }
    }

    /// TestLifter M5.5 — lifted countInvariance dispatch helper.
    /// Promoted countInvariance evidence has signature
    /// `"(\(typeT)) -> \(typeT)"` (no `preserving` clause; the lifted
    /// side hard-codes `\.count` per M5.2 OD #2). Routes to
    /// `LiftedTestEmitter.liftedCountInvariance` which emits the
    /// direct `f(xs).count == xs.count` test over a `Gen<[T]>`
    /// collection sample.
    private static func liftedCountInvarianceStub(for suggestion: Suggestion) -> String? {
        guard let evidence = suggestion.evidence.first,
              let funcName = functionName(from: evidence.displayName),
              let typeName = paramType(from: evidence.signature) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        return LiftedTestEmitter.liftedCountInvariance(
            funcName: funcName,
            typeName: typeName,
            seed: seed,
            generator: chooseGenerator(for: suggestion, typeName: typeName)
        )
    }

    /// TestLifter M5.5 — lifted reduceEquivalence dispatch helper.
    /// Promoted reduceEquivalence evidence has signature
    /// `"(\(typeT), \(typeT)) -> \(typeT) seed \(seedSource)"` —
    /// `seedSource` extracted via `seedSource(from:)`. Routes to
    /// `LiftedTestEmitter.liftedReduceEquivalence` which emits the
    /// `xs.reduce(s, op) == xs.reversed().reduce(s, op)` test over a
    /// `Gen<[T]>` collection sample. Defaults seed to `"0"` when
    /// extraction fails (older promotion-shape compatibility).
    private static func liftedReduceEquivalenceStub(for suggestion: Suggestion) -> String? {
        guard let evidence = suggestion.evidence.first,
              let opName = functionName(from: evidence.displayName),
              let typeName = paramType(from: evidence.signature) else {
            return nil
        }
        let seed = SamplingSeed.derive(from: suggestion.identity)
        let seedSourceText = seedSource(from: evidence.signature) ?? "0"
        return LiftedTestEmitter.liftedReduceEquivalence(
            opName: opName,
            elementTypeName: typeName,
            seedSource: seedSourceText,
            seed: seed,
            generator: chooseGenerator(for: suggestion, typeName: typeName)
        )
    }
}
