import SwiftInferCore
import SwiftSyntax

// Quantifier recognition, split out of `Slicer.swift` when that file hit SwiftLint's
// 400-line cap. This is the *call* form of the tail-repetition idea the slicer already
// modelled for `for`/`while`/`repeat`: a property test quantifies over a generator with a
// trailing closure instead of looping over a collection.
//
// Kept together because the callee list and the unwrapping that consults it are one
// decision — the list is the entire precision story, and separating it from its only
// consumer is how a vocabulary drifts from the code that reads it.

extension Slicer {

    /// Callees whose trailing closure is a **quantified law** rather than an arbitrary block.
    ///
    /// Curated, and that is the whole precision story. Unwrapping *any* trailing closure would
    /// be the Daikon trap: `measure { }`, `withThrowingTaskGroup { }` and `#expect(throws:) { }`
    /// all wrap assertion-shaped interiors that quantify over nothing, and lifting a law from
    /// one would claim a domain the test never ran over. A name list is the same instrument
    /// `VariantMarkers` and `MarkerTable` use for the same reason.
    ///
    /// `propertyCheck` is swift-property-based's entry point and the only spelling this repo
    /// uses (57 call sites). The others are listed because a missing spelling fails **silently**
    /// — the failure mode this catalog keeps relearning — and each is the primary quantifier of
    /// a property-testing library a Swift codebase might already be using.
    static let quantifierCallees: Set<String> = [
        "propertyCheck",   // swift-property-based (this toolchain's kit)
        "forAll",          // SwiftCheck, and the QuickCheck lineage generally
        "property",        // SwiftCheck's labelled form
        "checkProperty",   // common hand-rolled harness name
        "quickCheck"       // direct QuickCheck port naming
    ]

    /// The closure body of a quantifier call, or `nil` when this item is not one.
    ///
    /// Accepts both spellings of the same call — a trailing closure and an explicit
    /// `perform:` argument — because they are one call and treating them differently would
    /// make lifting depend on formatting.
    static func quantifierClosureBody(
        of item: CodeBlockItemSyntax
    ) -> [CodeBlockItemSyntax]? {
        guard case .expr(let expression) = item.item else { return nil }
        guard let call = unwrappingEffects(expression).as(FunctionCallExprSyntax.self) else {
            return nil
        }
        guard let callee = calleeBaseName(of: call),
              quantifierCallees.contains(callee)
        else { return nil }

        if let trailing = call.trailingClosure {
            return Array(trailing.statements)
        }
        // `perform:` is the declared parameter name; a caller not using trailing syntax
        // reaches the same closure through the argument list.
        for argument in call.arguments where argument.label?.text == "perform" {
            if let closure = argument.expression.as(ClosureExprSyntax.self) {
                return Array(closure.statements)
            }
        }
        return nil
    }

    /// Strip `await` / `try` wrappers to reach the call underneath. `propertyCheck` is `async`,
    /// so every real call site is wrapped in at least one of them.
    static func unwrappingEffects(_ expression: ExprSyntax) -> ExprSyntax {
        var current = expression
        while true {
            if let awaited = current.as(AwaitExprSyntax.self) {
                current = awaited.expression
                continue
            }
            if let tried = current.as(TryExprSyntax.self) {
                current = tried.expression
                continue
            }
            return current
        }
    }

    /// `propertyCheck(…)` → `"propertyCheck"`, and `PropertyBased.propertyCheck(…)` likewise —
    /// a module-qualified call is the same call.
    static func calleeBaseName(of call: FunctionCallExprSyntax) -> String? {
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }
}
