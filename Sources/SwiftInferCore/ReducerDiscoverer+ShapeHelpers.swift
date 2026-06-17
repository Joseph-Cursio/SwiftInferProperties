import Foundation
import SwiftSyntax

/// V1.92 lint pass — shape-classification + scalar-filter helpers
/// extracted from `ReducerDiscoverer.swift` so the main file stays
/// under SwiftLint's 400-line cap. V1.93 added the
/// `hasReducerAttribute` helper for the M1.D macro path. All
/// helpers are static-internal (callable from the Visitor in the
/// main file); none depend on per-Visitor state, so they're
/// naturally pure.
extension ReducerDiscoverer {

    /// V1.93 (cycle-90 fix for cycle-87 finding #3) — does an attribute
    /// list contain `@Reducer`? Matches the canonical macro name
    /// with or without parameter clause (`@Reducer` or
    /// `@Reducer(state: .equatable)`) — both have the same
    /// `attributeName.trimmedDescription`. Modern TCA (1.0+) attaches
    /// `Reducer` conformance via this macro rather than the explicit
    /// `: Reducer` inheritance clause; cycle-87 measured every TCA
    /// 1.25.5 example as 0 detections because v1.92's M1.B walker
    /// only recognized the conformance clause.
    static func hasReducerAttribute(_ attributes: AttributeListSyntax) -> Bool {
        for element in attributes {
            guard let attribute = element.as(AttributeSyntax.self) else { continue }
            let name = attribute.attributeName.trimmedDescription
            if name == "Reducer" {
                return true
            }
        }
        return false
    }

    /// V1.92 (cycle-89 fix for cycle-87 finding #4) — does `returnType`
    /// look like `Effect<...>`? Matches the canonical TCA effect
    /// shape; doesn't validate the type argument since M1.B's
    /// closure walker also leaves it unchecked (mirror the existing
    /// posture). Accepts both `Effect<Action>` and namespaced
    /// `Effect<Module.Action>`.
    static func looksLikeEffect(_ returnType: String) -> Bool {
        returnType.hasPrefix("Effect<") && returnType.hasSuffix(">")
    }

    /// Does `returnType` look like Mobius's `Next<Model, Effect>` with
    /// `Model == expectedFirst`? Mobius's `update(_ model:_ event:) ->
    /// Next<Model, Effect>` keeps the canonical `(State, Action)` param
    /// order — only the effect-bearing return differs from the curated
    /// `(S, Effect)` tuple — so the first generic argument must be the
    /// State type. Matched by name prefix + first-generic only, mirroring
    /// `looksLikeEffect`'s no-type-resolution posture (§3.5 absorbs false
    /// matches via default-`Possible` visibility).
    static func looksLikeMobiusNext(_ returnType: String, expectedFirst: String) -> Bool {
        guard returnType.hasPrefix("Next<"), returnType.hasSuffix(">") else { return false }
        let inner = returnType.dropFirst("Next<".count).dropLast()
        var depth = 0
        for index in inner.indices {
            switch inner[index] {
            case "<", "(", "[": depth += 1

            case ">", ")", "]": depth -= 1

            case "," where depth == 0:
                let first = inner[..<index].trimmingCharacters(in: .whitespaces)
                return first == expectedFirst

            default:
                break
            }
        }
        return false
    }

    /// The wrapped type of a single-level Optional spelling (`X?` or
    /// `Optional<X>`), or `nil` if `typeName` isn't optional. Used to
    /// recognize ReSwift's Optional incoming-State parameter
    /// (`(Action, State?) -> State`).
    static func optionalWrappedType(_ typeName: String) -> String? {
        let trimmed = typeName.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("?"), trimmed.count > 1 {
            return String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        if trimmed.hasPrefix("Optional<"), trimmed.hasSuffix(">") {
            return String(trimmed.dropFirst("Optional<".count).dropLast())
                .trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Recognize Square's Workflow `func apply(toState state: inout State)
    /// -> Output?` action method and return the State type + the mapped
    /// signature shape, or `nil`. Unlike every other carrier the Action is
    /// the enclosing type (`Self`), so this is an arity-ONE `inout` method
    /// — the caller supplies the Action from the enclosing-type stack.
    ///
    /// Keyed on the distinctive `apply` name + `toState:` argument label +
    /// `inout` parameter (the `WorkflowAction` requirement's spelling), not
    /// on conformance — matching the signature-only M1.A posture; §3.5
    /// default-`Possible` absorbs the rare false match. State must be
    /// non-scalar. The optional `Output` return maps to the effect-bearing
    /// shape (effects are discarded at verify); a bare `Void` apply maps to
    /// the void shape.
    static func classifyWorkflowApply(
        node: FunctionDeclSyntax
    ) -> (state: String, shape: ReducerSignatureShape)? {
        guard node.name.text == "apply" else { return nil }
        let params = node.signature.parameterClause.parameters
        guard params.count == 1 else { return nil }
        let param = params[params.startIndex]
        guard param.firstName.text == "toState" else { return nil }
        let raw = param.type.trimmedDescription
        guard raw.hasPrefix("inout ") else { return nil }
        let stateType = String(raw.dropFirst("inout ".count)).trimmingCharacters(in: .whitespaces)
        if isScalarTypeName(stateType) { return nil }
        let returnRaw = node.signature.returnClause?.type.trimmedDescription ?? "Void"
        let shape: ReducerSignatureShape = (returnRaw == "Void" || returnRaw.isEmpty)
            ? .inoutStateActionReturnsVoid
            : .inoutStateActionReturnsEffect
        return (state: stateType, shape: shape)
    }

    /// Recognize ReSwift's `(Action, State?) -> State` reducer shape and
    /// return the un-reversed `(state, action)` type names, or `nil`.
    /// ReSwift's `Reducer` typealias is `(_ action: Action, _ state:
    /// State?) -> State` — Action first, Optional incoming State, the
    /// returned State equal to the parameter's wrapped type.
    ///
    /// This shape is looser than the canonical ones (`(X, Y?) -> Y` also
    /// matches a `coalesce(_:_:)`-style helper), so it carries a stricter
    /// false-positive guard: neither the State nor the Action may be a
    /// scalar (a real ReSwift reducer's State is a struct, its Action an
    /// enum). PRD §3.5 conservative posture.
    static func classifyReSwift(
        firstRaw: String,
        secondRaw: String,
        returnType: String
    ) -> (state: String, action: String)? {
        // Action param isn't `inout`; State param is Optional; the return
        // is the State param's wrapped (non-optional) type.
        guard !firstRaw.hasPrefix("inout "), !secondRaw.hasPrefix("inout ") else { return nil }
        guard let stateType = optionalWrappedType(secondRaw), stateType == returnType else { return nil }
        let actionType = firstRaw
        if isScalarTypeName(stateType) || isScalarTypeName(actionType) { return nil }
        return (state: stateType, action: actionType)
    }

    /// Does `returnType` look like `(<expectedFirst>, Effect<...>)`?
    /// Tuple-shape match by depth-counting comma split — handles
    /// generic args like `Effect<Action>` and `Effect<S.Action>`
    /// without choking on nested `<>` / `()` / `[]`.
    static func isStateEffectTuple(_ returnType: String, expectedFirst: String) -> Bool {
        guard returnType.hasPrefix("("), returnType.hasSuffix(")") else { return false }
        let inner = returnType.dropFirst().dropLast()
        var depth = 0
        var commaIdx: String.Index?
        for index in inner.indices {
            let char = inner[index]
            switch char {
            case "<", "(", "[": depth += 1
            case ">", ")", "]": depth -= 1

            case ",":
                if depth == 0 {
                    commaIdx = index
                }

            default:
                break
            }
            if commaIdx != nil { break }
        }
        guard let commaIdx else { return false }
        let firstHalf = inner[..<commaIdx].trimmingCharacters(in: .whitespaces)
        let secondHalf = inner[inner.index(after: commaIdx)...]
            .trimmingCharacters(in: .whitespaces)
        return firstHalf == expectedFirst && secondHalf.hasPrefix("Effect")
    }

    /// V1.92 (cycle-89 fix for cycle-87 finding #1) — curated scalar
    /// type set. Two-scalar reducer shapes (both State and Action
    /// in this set) are rejected as false positives — no plausible
    /// reducer has both halves scalar. Set covers Swift's stdlib
    /// numeric tower + Bool / String / Character; excludes
    /// `Optional<X>` (which is `X?` syntactically) and collection
    /// types like `[T]` since those occasionally legitimately
    /// stand in for compact State.
    static func isScalarTypeName(_ typeName: String) -> Bool {
        scalarTypeNames.contains(typeName)
    }

    private static let scalarTypeNames: Set<String> = [
        "Int", "UInt",
        "Int8", "Int16", "Int32", "Int64",
        "UInt8", "UInt16", "UInt32", "UInt64",
        "Bool",
        "Double", "Float", "Float80",
        "String", "Character",
        "Swift.Int", "Swift.UInt",
        "Swift.Int8", "Swift.Int16", "Swift.Int32", "Swift.Int64",
        "Swift.UInt8", "Swift.UInt16", "Swift.UInt32", "Swift.UInt64",
        "Swift.Bool",
        "Swift.Double", "Swift.Float",
        "Swift.String", "Swift.Character"
    ]

    // MARK: - Cycle 109 — nested State/Action qualification (Blocker A)

    /// The names of every type a member block declares directly (one
    /// level deep): `struct` / `enum` / `class` / `actor` / `typealias`.
    /// `Visitor` records this per enclosing type so `matchReducer` can
    /// tell whether a reducer's bare `State`/`Action` param type is a
    /// nested member of its enclosing type.
    static func nestedTypeNames(in memberBlock: MemberBlockSyntax) -> Set<String> {
        var names: Set<String> = []
        for member in memberBlock.members {
            let decl = member.decl
            if let structDecl = decl.as(StructDeclSyntax.self) {
                names.insert(structDecl.name.text)
            } else if let enumDecl = decl.as(EnumDeclSyntax.self) {
                names.insert(enumDecl.name.text)
            } else if let classDecl = decl.as(ClassDeclSyntax.self) {
                names.insert(classDecl.name.text)
            } else if let actorDecl = decl.as(ActorDeclSyntax.self) {
                names.insert(actorDecl.name.text)
            } else if let aliasDecl = decl.as(TypeAliasDeclSyntax.self) {
                names.insert(aliasDecl.name.text)
            }
        }
        return names
    }

    /// Qualify `name` as `<enclosing>.<name>` when it is a nested member
    /// of the enclosing type, so the stub emitters produce a resolvable
    /// `<Enclosing>.State()` / `<Enclosing>.Action.self`. No-op when there
    /// is no enclosing type, when the name is already dotted (M1.B
    /// pre-qualifies — avoid double-qualifying), or when the name is not
    /// in the enclosing type's nested-type set (a top-level type
    /// referenced by bare name stays bare).
    static func qualifyIfNested(_ name: String, enclosing: String?, nested: Set<String>) -> String {
        guard let enclosing, !name.contains("."), nested.contains(name) else {
            return name
        }
        return "\(enclosing).\(name)"
    }
}
