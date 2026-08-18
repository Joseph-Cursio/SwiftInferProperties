import SwiftEffectInference

/// Copy-with builders for `FunctionSummary`.
///
/// Extracted on 2026-08-04, when carrying the three-state `purityVerdict` took
/// `FunctionSummary.swift` from 399 lines to 403 against a 400-line cap. The
/// alternative was shaving a rationale until it fit — the move this project
/// rejects for exactly this case (`Signal+Kind.swift`'s overflow doc: relocate,
/// do not trim).
///
/// The seam is a real one: `FunctionSummary.swift` is a *model* — fields and the
/// reasoning behind each — while this is the one place a summary is rebuilt
/// after the scan. A builder that forgets a field compiles silently, so keeping
/// them together and away from the field list is the safer shape.
///
/// **That failure happened, and it is why `BuilderFieldParityTests` exists.** Three
/// fields were dropped here — `qualifiedContainingTypeName`, `declaresUnknownEffect` and
/// `bodyFingerprint` — because each is a *defaulted* parameter, so omitting one compiles
/// and silently substitutes its default. `declaresUnknownEffect` is the sharpest: open
/// item 20's entire chain exists to carry `@EffectUnknown` from a sibling repo to a
/// template, and this builder reset it to `false` on exactly the summaries an effect had
/// just been resolved for. Found 2026-08-18 while adding a field, which is the only way
/// a silent drop ever surfaces.

public extension FunctionSummary {

    /// A copy carrying a body-resolved effect. Written as a copy rather than a
    /// `var` because `FunctionSummary` is otherwise immutable and every other
    /// field is set once at scan time — `EffectResolver` runs after the scan and
    /// should not be the one thing that can mutate a summary in place.
    func withInferredEffect(_ effect: Effect) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returnTypeText,
            isThrows: isThrows,
            isAsync: isAsync,
            isMutating: isMutating,
            isStatic: isStatic,
            location: location,
            containingTypeName: containingTypeName,
            bodySignals: bodySignals,
            qualifiedContainingTypeName: qualifiedContainingTypeName,
            discoverableGroup: discoverableGroup,
            invariantKeypath: invariantKeypath,
            isInferredPure: isInferredPure,
            isClockDeterministic: isClockDeterministic,
            declaresUnknownEffect: declaresUnknownEffect,
            isComputedProperty: isComputedProperty,
            isInitializer: isInitializer,
            docComment: docComment,
            declaredEffect: declaredEffect,
            inferredEffect: effect,
            purityVerdict: purityVerdict,
            bodyFingerprint: bodyFingerprint
        )
    }
}
