import SwiftSyntax

/// TestLifter M4.0 — pure-syntactic type recovery from a sliced test
/// body's setup + property regions.
///
/// The M3.1 `LiftedSuggestionRecovery` does strict FunctionSummary
/// lookup: when a test-only callee isn't in the production-side
/// scanner output, type recovery returns `nil` and the promoted
/// `Suggestion` ships with `?`-sentinel evidence + a `.todo<?>()`
/// accept-flow stub. M4 widens recovery with this scanner: when the
/// test body itself carries the type info via `let x: T = ...`
/// annotations or `let x = T(...)` bare-constructor bindings, we can
/// recover `T` *without* a corresponding production-side function.
///
/// **Per-binding recovery rules:**
/// - `let x: T = expr` → `x → T` (read T from the type annotation)
/// - `let x = T(arg: 42)` → `x → T` (read T from the called
///   expression's identifier when it looks like a type — UpperCamelCase
///   first letter, the conventional Swift rule)
/// - `let x = makeThing()` → NOT recovered (the called expression's
///   name is lowercase, so it's a function call whose return type
///   lives in the function's signature — a FunctionSummary-side
///   concern that already failed by the time we got here)
/// - `let (a, b) = ...` → NOT recovered (tuple patterns out of scope;
///   silently skipped, the binding falls through to no-type-info)
///
/// **Scope:** walks both `slice.setup` AND `slice.propertyRegion`.
/// Bindings inside the property region whose initializer references a
/// test-only callee still need annotation recovery — the slicer pulls
/// them into the property region exactly because they're referenced
/// by the assertion, but their callee may not be in the production
/// scanner index.
public enum SetupRegionTypeAnnotationScanner {

    /// Recover `[bindingName: typeName]` for every typed-binding or
    /// bare-constructor-binding statement in the slice. Returns an
    /// empty map when no qualifying bindings are present. Pure
    /// function — no FunctionSummary, no corpus context, no semantic
    /// resolution.
    public static func annotations(in slice: SlicedTestBody) -> [String: String] {
        var result: [String: String] = [:]
        for item in slice.setup {
            if let recovered = recover(item: item) {
                result[recovered.bindingName] = recovered.typeName
            }
        }
        for item in slice.propertyRegion {
            if let recovered = recover(item: item) {
                result[recovered.bindingName] = recovered.typeName
            }
        }
        return result
    }

    private struct Recovered {
        let bindingName: String
        let typeName: String
    }

    private static func recover(item: CodeBlockItemSyntax) -> Recovered? {
        guard case .decl(let decl) = item.item,
              let varDecl = decl.as(VariableDeclSyntax.self),
              let firstBinding = varDecl.bindings.first,
              let identifierPattern = firstBinding.pattern.as(IdentifierPatternSyntax.self) else {
            return nil
        }
        let bindingName = identifierPattern.identifier.text
        // Tier 1: explicit type annotation `let x: T = ...`. Wins over
        // bare-constructor recovery — when the user wrote both, the
        // annotation is the load-bearing source of truth.
        if let annotation = firstBinding.typeAnnotation {
            return Recovered(
                bindingName: bindingName,
                typeName: annotation.type.trimmedDescription
            )
        }
        // Tier 2: bare-constructor `let x = T(...)` / `let x = T()`.
        // Recover T from the called expression's identifier when it
        // looks like a type per the Swift naming convention
        // (UpperCamelCase first letter).
        if let initializer = firstBinding.initializer?.value,
           let typeName = constructorTypeName(of: initializer) {
            return Recovered(bindingName: bindingName, typeName: typeName)
        }
        return nil
    }

    /// Returns the type name when `expr` is a `T(...)` or `T()` call
    /// whose called expression is a bare type-shaped identifier.
    /// Other call shapes (`a.f()`, `Module.T()`, `f()`) return `nil`.
    private static func constructorTypeName(of expr: ExprSyntax) -> String? {
        guard let call = expr.as(FunctionCallExprSyntax.self),
              let ref = call.calledExpression.as(DeclReferenceExprSyntax.self) else {
            return nil
        }
        let name = ref.baseName.text
        guard isTypeShapedIdentifier(name) else {
            return nil
        }
        return name
    }

    /// UpperCamelCase first-letter check. `Doc` → true; `doc` → false;
    /// `_Doc` → false (non-letter first char); empty → false. Matches
    /// Swift's nominal-type naming convention without doing semantic
    /// resolution.
    private static func isTypeShapedIdentifier(_ name: String) -> Bool {
        guard let first = name.first else {
            return false
        }
        return first.isLetter && first.isUppercase
    }
}
