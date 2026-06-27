import PropertyLawCore
import SwiftSyntax

/// Member-block inspection helpers that feed `TypeDecl` construction.
/// Ported from SwiftPropertyLaws's `PropertyLawMacroImpl.MemberBlockInspector`
/// — the macro impl can't be a runtime dep here, so the logic is
/// duplicated by design (matches the in-tree port the discovery plugin
/// uses for the same reason).
enum MemberBlockInspector {

    /// Stored properties declared in `memberBlock`, in source order.
    /// Returns only `let` / `var` declarations with explicit type
    /// annotations and no accessor block (computed properties skipped).
    /// `static` / `class` properties are also filtered. Multi-binding
    /// lines (`let x: Int, y: Int`) produce one entry per binding.
    static func storedMembers(in memberBlock: MemberBlockSyntax) -> [StoredMember] {
        var result: [StoredMember] = []
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard !isStaticOrClass(varDecl.modifiers) else { continue }
            for binding in varDecl.bindings {
                if binding.accessorBlock != nil { continue }
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                    continue
                }
                guard let typeAnnotation = binding.typeAnnotation else { continue }
                result.append(StoredMember(
                    name: identifier.identifier.text,
                    typeName: typeAnnotation.type.trimmedDescription
                ))
            }
        }
        return result
    }

    /// `true` when `memberBlock` declares any `init(...)`. Used by the
    /// memberwise-Arbitrary derivation gate per the strategist contract.
    static func hasUserInit(in memberBlock: MemberBlockSyntax) -> Bool {
        for member in memberBlock.members
        where member.decl.as(InitializerDeclSyntax.self) != nil {
            return true
        }
        return false
    }

    /// `true` when `memberBlock` declares a `static func gen(...)` —
    /// the user-supplied generator that wins PRD §5.7's Strategy A
    /// short-circuit. Parameter-list shape isn't checked: the strategist
    /// honours any `static gen` in the body, and emitting a non-zero-arg
    /// `gen()` is a user error the compiler catches.
    static func hasUserGen(in memberBlock: MemberBlockSyntax) -> Bool {
        for member in memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            guard funcDecl.name.text == "gen" else { continue }
            if isStaticOrClass(funcDecl.modifiers) { return true }
        }
        return false
    }

    /// TestLifter M14.0 — case identifiers declared in `memberBlock`,
    /// in source order. Walks `EnumCaseDeclSyntax` nodes and reads each
    /// element's identifier from `EnumCaseElementListSyntax`. Strips
    /// associated-value parameter clauses (`case small(Int)` → `small`)
    /// and raw-value initializers (`case small = "S"` → `small`).
    /// Multi-binding lines (`case small, medium, large`) produce one
    /// entry per binding. The caller (M14.0c `FunctionScannerVisitor`)
    /// invokes this only for `kind == .enum` and `kind == .extension`
    /// (the extension may add cases to a same-name enum).
    static func enumCaseNames(in memberBlock: MemberBlockSyntax) -> [String] {
        var result: [String] = []
        for member in memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in caseDecl.elements {
                result.append(element.name.text)
            }
        }
        return result
    }

    /// User-declared initializers (parameters with resolved call labels,
    /// failable/throwing flags) for the Tier 6 `initializerBased` strategy.
    /// Async and variadic-parameter inits are skipped — neither composes
    /// into a synchronous fixed-arity generator. Mirrors the in-tree port
    /// the discovery plugin uses.
    static func initializers(in memberBlock: MemberBlockSyntax) -> [InitializerSignature] {
        var result: [InitializerSignature] = []
        for member in memberBlock.members {
            guard let initDecl = member.decl.as(InitializerDeclSyntax.self) else { continue }
            let effects = initDecl.signature.effectSpecifiers
            if effects?.asyncSpecifier != nil { continue }

            var parameters: [InitializerParameter] = []
            var hasVariadic = false
            for param in initDecl.signature.parameterClause.parameters {
                if param.ellipsis != nil { hasVariadic = true; break }
                let firstName = param.firstName.text
                let label = firstName == "_" ? nil : firstName
                parameters.append(InitializerParameter(
                    label: label,
                    typeName: param.type.trimmedDescription
                ))
            }
            if hasVariadic { continue }

            result.append(InitializerSignature(
                parameters: parameters,
                isFailable: initDecl.optionalMark != nil,
                isThrowing: effects?.throwsClause != nil
            ))
        }
        return result
    }

    /// Enum cases with their associated values for the Tier 4 `enumCases`
    /// strategy. Each associated value's label is its first name (the
    /// construction label), or `nil` when unlabeled.
    static func enumCases(in memberBlock: MemberBlockSyntax) -> [EnumCase] {
        var result: [EnumCase] = []
        for member in memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in caseDecl.elements {
                var associatedValues: [InitializerParameter] = []
                if let parameters = element.parameterClause?.parameters {
                    for param in parameters {
                        let first = param.firstName?.text
                        let label = (first == nil || first == "_") ? nil : first
                        associatedValues.append(InitializerParameter(
                            label: label,
                            typeName: param.type.trimmedDescription
                        ))
                    }
                }
                result.append(EnumCase(name: element.name.text, associatedValues: associatedValues))
            }
        }
        return result
    }

    private static func isStaticOrClass(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { mod in
            mod.name.tokenKind == .keyword(.static) || mod.name.tokenKind == .keyword(.class)
        }
    }
}
