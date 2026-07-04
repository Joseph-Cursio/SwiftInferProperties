import Foundation
import SwiftSyntax

// V1.B + V1.D — the TCA-conformance walk leg of the discovery `Visitor`.
// Split out of `ReducerDiscoverer.swift` in cycle 109 to keep that file
// under SwiftLint's `file_length` cap (the nested-State/Action
// pre-qualification work pushed it over). Pure relocation — no behavior
// change. `Visitor` is `internal` (not `private`) so this extension can
// live here; only `extractTCACandidatesIfReducerConformer` is called from
// the main file (the type-decl `visit` methods), so it is the only
// internal entry — the rest stay `private` to this file.

extension ReducerDiscoveryVisitor {

    /// V1.B + V1.D — entry point for the TCA path. Fires when the
    /// file imports `ComposableArchitecture` AND **either** the
    /// declaration's inheritance clause names `Reducer` (V1.B
    /// pre-macro form: `struct Foo: Reducer`) **or** the declaration
    /// has the `@Reducer` macro attribute (V1.D modern form,
    /// dominant since TCA 1.0+ — `@Reducer struct Foo`). Private /
    /// fileprivate types are skipped, matching the function-scan
    /// posture. The body walk is idempotent for a single decl, so
    /// a type with both forms (`@Reducer struct Foo: Reducer`)
    /// emits one set of candidates, not two.
    func extractTCACandidatesIfReducerConformer(
        attributes: AttributeListSyntax,
        modifiers: DeclModifierListSyntax,
        inheritanceClause: InheritanceClauseSyntax?,
        memberBlock: MemberBlockSyntax,
        enclosingTypeName: String
    ) {
        guard importsComposableArchitecture else { return }
        let viaConformance = Self.declaresReducerConformance(inheritanceClause)
        let viaMacro = ReducerDiscoverer.hasReducerAttribute(attributes)
        guard viaConformance || viaMacro else { return }
        let modifierNames = modifiers.map(\.name.text)
        if modifierNames.contains("private") || modifierNames.contains("fileprivate") {
            return
        }
        extractTCACandidates(from: memberBlock, enclosingTypeName: enclosingTypeName)
    }

    /// Does an inheritance clause name TCA's `Reducer` protocol?
    /// Matches the literal `Reducer` plus `Reducer<...>` and
    /// `ReducerOf<...>` generic variants. Static so test fixtures can
    /// drive it without spinning up a full walk.
    static func declaresReducerConformance(_ clause: InheritanceClauseSyntax?) -> Bool {
        guard let clause else { return false }
        for inherited in clause.inheritedTypes {
            let text = inherited.type.trimmedDescription
            if text == "Reducer" || text.hasPrefix("Reducer<") || text.hasPrefix("ReducerOf<") {
                return true
            }
        }
        return false
    }

    /// Find `var body` and walk its initializer / accessor block for
    /// `Reduce { state, action in ... }` calls.
    private func extractTCACandidates(
        from memberBlock: MemberBlockSyntax,
        enclosingTypeName: String
    ) {
        // Cycle 122/125 — capture the nested Action enum's cases (name +
        // payload types) so the verifier can enumerate actions without
        // `CaseIterable` (real TCA Actions don't declare it). Phase B's
        // emitter picks the constructible subset; no bail on payloads.
        let actionCases = Self.actionCases(in: memberBlock)
        // Item 2 slice 3 — capture the nested `State` struct's `id` type so a
        // *parent* reducer whose Action carries `IdentifiedActionOf<Self>` can
        // resolve this reducer's `State.ID` when building an `.element` value.
        let stateIDTypeName = Self.stateIDType(in: memberBlock)
        for member in memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in variable.bindings {
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                      identifier.identifier.text == "body" else { continue }
                if let initializer = binding.initializer?.value {
                    walkForReduceClosures(
                        in: Syntax(initializer),
                        enclosingTypeName: enclosingTypeName,
                        actionCases: actionCases,
                        stateIDTypeName: stateIDTypeName
                    )
                }
                if let accessor = binding.accessorBlock {
                    walkForReduceClosures(
                        in: Syntax(accessor),
                        enclosingTypeName: enclosingTypeName,
                        actionCases: actionCases,
                        stateIDTypeName: stateIDTypeName
                    )
                }
            }
        }
    }

    /// Item 2 slice 3 — the nested `State` struct's `id` member type
    /// (`"UUID"` / `"Int"` / `"String"` / a custom type), or `nil` when no
    /// `State` struct is present or it declares no `id`. Reads an explicit
    /// type annotation (`let id: UUID`, `var id: UUID { … }`) first, then
    /// falls back to inferring the type from a simple call-expression
    /// initializer (`let id = UUID()` → `"UUID"`). Literal-only initializers
    /// (`var id = 0`) are left unresolved — the id types slice 3 supports are
    /// exactly the annotated / call-constructed forms real TCA uses.
    static func stateIDType(in memberBlock: MemberBlockSyntax) -> String? {
        guard let stateStruct = memberBlock.members
            .compactMap({ $0.decl.as(StructDeclSyntax.self) })
            .first(where: { $0.name.text == "State" })
        else { return nil }

        for member in stateStruct.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in variable.bindings {
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                      identifier.identifier.text == "id" else { continue }
                if let annotation = binding.typeAnnotation {
                    return annotation.type.trimmedDescription
                }
                if let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
                   let callee = call.calledExpression.as(DeclReferenceExprSyntax.self) {
                    return callee.baseName.text
                }
            }
        }
        return nil
    }

    /// Cycle 122/125 — the nested `enum Action`'s cases, in source order,
    /// each with its associated-value payload types (`[]` = payload-free).
    /// Returns `[]` when no `Action` enum is found in this member block.
    /// Unlike Phase A this does **not** bail on payload cases — Phase B's
    /// relaxed emitter classifies constructibility per case and explores
    /// the constructible subset.
    static func actionCases(in memberBlock: MemberBlockSyntax) -> [ActionCaseInfo] {
        guard let actionEnum = memberBlock.members
            .compactMap({ $0.decl.as(EnumDeclSyntax.self) })
            .first(where: { $0.name.text == "Action" })
        else { return [] }

        var cases: [ActionCaseInfo] = []
        for member in actionEnum.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in caseDecl.elements {
                let payloadTypes = element.parameterClause?.parameters
                    .map(\.type.trimmedDescription) ?? []
                cases.append(ActionCaseInfo(name: element.name.text, payloadTypes: payloadTypes))
            }
        }
        return cases
    }

    /// Recursively walk `subtree` looking for `Reduce { ... }` calls
    /// with an arity-2 trailing closure. Each match emits one
    /// `ReducerCandidate`. Composed reducers (`Scope`, `BindingReducer`,
    /// `CombineReducers`, `EmptyReducer`, etc.) are walked past — only
    /// `Reduce` introduces the closure shape M1.B is after.
    private func walkForReduceClosures(
        in subtree: Syntax,
        enclosingTypeName: String,
        actionCases: [ActionCaseInfo],
        stateIDTypeName: String?
    ) {
        let walker = ReduceClosureWalker(
            file: file,
            converter: converter,
            enclosingTypeName: enclosingTypeName,
            actionCases: actionCases,
            stateIDTypeName: stateIDTypeName
        )
        walker.walk(subtree)
        candidates.append(contentsOf: walker.candidates)
    }
}
