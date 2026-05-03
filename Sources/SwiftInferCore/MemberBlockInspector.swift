import ProtoLawCore
import SwiftSyntax

/// Member-block inspection helpers that feed `TypeDecl` construction.
/// Ported from SwiftProtocolLaws's `ProtoLawMacroImpl.MemberBlockInspector`
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

    private static func isStaticOrClass(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { mod in
            mod.name.tokenKind == .keyword(.static) || mod.name.tokenKind == .keyword(.class)
        }
    }
}
