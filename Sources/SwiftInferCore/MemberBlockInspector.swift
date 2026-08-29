import PropertyLawCore
import PropertyLawSyntaxSupport
import SwiftSyntax

/// Member-block inspection helpers that feed `TypeDecl` construction.
/// Ported from SwiftPropertyLaws's `PropertyLawMacroImpl.MemberBlockInspector`
/// — the macro impl can't be a runtime dep here, so the logic is
/// duplicated by design (matches the in-tree port the discovery plugin
/// uses for the same reason).
enum MemberBlockInspector {

    /// Stored properties declared in `memberBlock`, in source order.
    /// Returns only `let` / `var` declarations with explicit type
    /// annotations that are not computed. `static` / `class` properties are also
    /// filtered. Multi-binding lines (`let x: Int, y: Int`) produce one entry per binding.
    ///
    /// **An accessor block does not make a property computed** — `willSet` / `didSet`
    /// observers leave it stored, and Swift includes it in the synthesized memberwise
    /// initializer. This rule was `accessorBlock != nil` until 2026-08-28, which dropped
    /// every observed property from the shape.
    ///
    /// **Measured**: `Euclid.PathPoint` declares `public var position: Vector { didSet { … } }`
    /// beside three plain stored properties, so the emitted generator called
    /// `PathPoint(texcoord:color:isCurved:)` — a three-argument call against a four-argument
    /// initializer, worth 40 of the kit scaffold's compile errors
    /// (`docs/measurements/kit-scaffold-conversion.md` §3.1).
    ///
    /// **Second time an accessor list has been read too coarsely.** `isReadOnlyGetter` gated on
    /// `!contains("set")` and admitted `_modify` coroutines, offering a MUTABLE property as a law
    /// subject (`docs/measurements/modify-accessor-misclassification.md`). Both are the same
    /// mistake: Swift has more accessor kinds than the two a quick check imagines, so the rule is
    /// an ALLOWLIST of the kinds that keep a property stored, never a denylist of the rest.
    static func storedMembers(in memberBlock: MemberBlockSyntax) -> [StoredMember] {
        var result: [StoredMember] = []
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard !isStaticOrClass(varDecl.modifiers) else { continue }
            for binding in varDecl.bindings {
                if let accessorBlock = binding.accessorBlock,
                   !isObserverOnly(accessorBlock) { continue }
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

    /// `true` when an accessor block contains ONLY `willSet` / `didSet` observers, which
    /// leave the property stored.
    ///
    /// **Conservative by construction, and the direction is deliberate.** The `.getter` case —
    /// `var x: Int { 42 }` — returns `false`, and so does any list containing `get`, `set`,
    /// `_read` or `_modify`. Anything this cannot positively identify as observer-only stays
    /// classified as computed, which is the behaviour that existed before. **An allowlist, per
    /// the rule above**: naming the kinds that keep a property stored is stable against Swift
    /// growing new accessor kinds, while naming the kinds that make it computed is not.
    static func isObserverOnly(_ accessorBlock: AccessorBlockSyntax) -> Bool {
        guard case .accessors(let accessors) = accessorBlock.accessors else { return false }
        guard !accessors.isEmpty else { return false }
        return accessors.allSatisfy { accessor in
            let specifier = accessor.accessorSpecifier.text
            return specifier == "willSet" || specifier == "didSet"
        }
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
            // **A `private` initializer is not a candidate, and admitting one emits code
            // that does not compile.** Measured 2026-08-21 on `swift-http-types`:
            // `HTTPField.Name` declares two `public init?`s and one
            // `private init(rawName:canonicalName:)` whose labels match the stored members
            // exactly. The strategist preferred the memberwise-shaped one — the private
            // one — and the emitted stub failed with `extra argument 'canonicalName' in
            // call`, because from a test module that initializer does not exist. The
            // cascade error (`value of optional type 'HTTPField.Name?' must be unwrapped`)
            // is Swift resolving the call to a *different*, failable initializer, and it
            // is the error that gets reported.
            //
            // 95 of 163 laws on that subject died this way. The kit's
            // `InitializerSignature` has since grown an `accessLevel` field, so the
            // strategist *could* decide this; the filter stays at capture because it is the
            // stricter of the two and an uncaptured initializer cannot be chosen by any
            // later stage. The field is deliberately not carried — see
            // `IndexedTypeShape.InitializerSignature`.
            //
            // `fileprivate` is excluded on the same grounds and `internal` is kept:
            // `@testable import` reaches `internal`, which is the same line
            // `AccessRestriction.internalOrSPI` and `SpeculativeWidening` already draw.
            guard !Self.isTestInaccessible(initDecl) else { continue }
            let effects = initDecl.signature.effectSpecifiers
            if effects?.asyncSpecifier != nil { continue }

            var parameters: [InitializerParameter] = []
            var hasVariadic = false
            for param in initDecl.signature.parameterClause.parameters {
                if param.ellipsis != nil { hasVariadic = true; break }
                let firstName = param.firstName.text
                let label = firstName == "_" ? nil : firstName
                let normalized = SequenceInitializerNormalizer.normalizedTypeName(
                    declared: param.type.trimmedDescription, initializer: initDecl
                )
                parameters.append(InitializerParameter(
                    label: label,
                    typeName: normalized
                ))
            }
            if hasVariadic { continue }

            result.append(InitializerSignature(
                parameters: parameters,
                isFailable: initDecl.optionalMark != nil,
                isThrowing: effects?.throwsClause != nil,
                assertsPrecondition: InitializerPreconditionDetector
                    .statesPrecondition(initDecl),
                // **A precondition one hop away is still a precondition, and this flag was
                // never computed here until 2026-08-28.** `statesPrecondition` reads the body
                // it is given; `delegatesToSelf` is what lets the strategist pair "this init
                // forwards" with "some init on this type asserts", which is the only way a
                // clean-looking delegating initializer gets declined.
                //
                // **Measured on `Euclid.Plane`**: the strategist picked
                // `init(unchecked normal:pointOnPlane:)`, whose body is a bare
                // `self.init(unchecked: normal, w: normal.dot(pointOnPlane))` — it asserts
                // nothing itself and forwards to the sibling holding
                // `assert(normal.isNormalized)`. Without this flag the pairing in
                // `InitializerBasedDerivation.isDeclined` can never fire, so the first kit
                // suite that ever compiled trapped at `Plane.swift:230`
                // (`docs/measurements/kit-scaffold-conversion.md` §3.2). The kit's own
                // `MemberBlockInspector` has computed both flags all along; this port
                // computed one.
                delegatesToSelf: InitializerPreconditionDetector.delegatesToSelf(initDecl)
            ))
        }
        return result
    }

    /// `private` and `fileprivate` are file-scoped, so no test file can name the
    /// initializer — not even with `@testable import`, which promotes `internal` and
    /// does not defeat file scope. Every other level is reachable from a test target.
    static func isTestInaccessible(_ initDecl: InitializerDeclSyntax) -> Bool {
        initDecl.modifiers.contains { modifier in
            let name = modifier.name.text
            guard name == "private" || name == "fileprivate" else { return false }
            // `private(set)` restricts the SETTER, not the initializer, and is not a
            // spelling that appears on an `init` — but detail-bearing modifiers are
            // checked rather than assumed, because reading a modifier by name alone is
            // how `isReadOnlyGetter` admitted `_modify` coroutines as read-only.
            return modifier.detail == nil
        }
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

extension MemberBlockInspector {

    /// Replace a carrier generic parameter with `Int` inside an array type.
    ///
    /// Narrow on purpose: only `[T]` where `T` is one of the carrier's own generic parameter
    /// names. That is the exact shape `SequenceInitializerNormalizer` produces for the
    /// canonical collection constructor, and nothing else. A broader textual substitution
    /// would rewrite types it does not understand, and the cost of being wrong is emitted
    /// code that does not compile.
    ///
    /// `Int` matches `ConcreteInstantiation` — the carrier is named `Deque<Int>`, so its
    /// elements must be `Int` for the call to typecheck — and matches the kit's own recipes,
    /// which bind element types to `Int` and say so.
    static func substitutingCarrierGenerics(
        _ typeName: String,
        carrierGenericParameters: [String]
    ) -> String {
        guard !carrierGenericParameters.isEmpty,
              typeName.hasPrefix("["), typeName.hasSuffix("]") else { return typeName }
        let element = String(typeName.dropFirst().dropLast())
        guard carrierGenericParameters.contains(element) else { return typeName }
        return "[Int]"
    }
}
