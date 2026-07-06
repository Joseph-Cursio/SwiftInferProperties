import Foundation

/// Recognizes value-semantics verification candidates from a scanned corpus.
/// Slice 2 of the ValueSemantic build plan (`docs/valuesemantic-build-plan.md`):
/// a textual/corpus fold over `TypeDecl`s + `FunctionSummary`s — no new AST
/// pass, mirroring `EquatableResolver` / `IdentifiableResolver`.
///
/// A `struct` is a candidate iff (§4 of the plan):
///   1. it is a `struct` (classes/actors have reference semantics by
///      definition — out of scope for copy-independence), AND
///   2. it declares ≥ 1 reference-backed stored member (closure / curated
///      mutable container / a corpus `class`/`actor`), AND
///   3. it has ≥ 1 instance method in its mutation surface (something to test).
///
/// Pure-value structs, and members whose type is `.unknown` (external, unseen),
/// are excluded — the conservative, precision-first posture.
public enum ValueSemanticDiscoverer {

    /// Curated Foundation mutable reference containers. A struct holding one of
    /// these — matched by base name after stripping optionals/generics — is
    /// reference-backed (Example 1).
    static let referenceContainerTypes: Set<String> = [
        "NSMutableArray", "NSMutableDictionary", "NSMutableSet",
        "NSMutableString", "NSMutableData", "NSMutableOrderedSet",
        "NSMutableAttributedString", "NSCache", "NSHashTable",
        "NSMapTable", "NSPointerArray"
    ]

    /// Discover value-semantics candidates. Deterministic order (file, line,
    /// name). `functions` supplies the mutation surface (cross-file/extension
    /// methods included via `containingTypeName`); `typeDecls` supplies stored
    /// members + the class/actor kind lookup for corpus-reference resolution.
    public static func discover(
        typeDecls: [TypeDecl],
        functions: [FunctionSummary]
    ) -> [ValueSemanticCandidate] {
        let kindByName = foldKinds(typeDecls)
        let equatable = EquatableResolver(typeDecls: typeDecls)

        var candidates: [ValueSemanticCandidate] = []
        var seen: Set<String> = []
        for decl in typeDecls where decl.kind == .struct {
            guard !seen.contains(decl.name) else { continue }
            seen.insert(decl.name)

            let refMembers = decl.storedMembers.compactMap { member in
                classifyMember(name: member.name, typeName: member.typeName, kindByName: kindByName)
            }
            guard !refMembers.isEmpty else { continue }        // pure value struct → excluded

            let surface = mutationSurface(of: decl.name, functions: functions)
            guard !surface.isEmpty else { continue }           // nothing to test

            candidates.append(ValueSemanticCandidate(
                typeName: decl.name,
                location: decl.location,
                referenceBackedMembers: refMembers,
                mutationSurface: surface,
                equatability: equatable.classify(typeText: decl.name)
            ))
        }
        return candidates.sorted { lhs, rhs in
            (lhs.location.file, lhs.location.line, lhs.typeName)
                < (rhs.location.file, rhs.location.line, rhs.typeName)
        }
    }

    // MARK: - Reference-backed classification

    /// Classify a stored member as reference-backed, or `nil` if it is a value
    /// type or an unresolved (`.unknown`) type — the conservative default.
    static func classifyMember(
        name: String,
        typeName: String,
        kindByName: [String: TypeDecl.Kind]
    ) -> ReferenceBackedMember? {
        let normalized = stripAttributes(typeName)
        if isClosureType(normalized) {
            return ReferenceBackedMember(name: name, typeName: typeName, kind: .closure)
        }
        let base = baseName(of: normalized)
        if referenceContainerTypes.contains(base) {
            return ReferenceBackedMember(name: name, typeName: typeName, kind: .referenceContainer)
        }
        if let kind = kindByName[base], kind == .class || kind == .actor {
            return ReferenceBackedMember(name: name, typeName: typeName, kind: .corpusReference)
        }
        return nil
    }

    /// The mutation surface of a type: non-`static` instance methods that are
    /// either `mutating` (mutate `self` directly) or `Void`-returning (a
    /// non-`mutating` side-effecting method — the Example-1 reference-leak
    /// shape). A non-`mutating`, non-`Void` method is a query (getter) and is
    /// excluded. Sorted by name for deterministic output.
    static func mutationSurface(
        of typeName: String,
        functions: [FunctionSummary]
    ) -> [MutationMethod] {
        functions
            .filter { summary in
                summary.containingTypeName == typeName
                    && !summary.isStatic
                    && (summary.isMutating || returnsVoid(summary.returnTypeText))
            }
            .map { summary in
                MutationMethod(
                    name: summary.name,
                    isMutating: summary.isMutating,
                    parameterCount: summary.parameters.count
                )
            }
            .sorted { ($0.name, $0.parameterCount) < ($1.name, $1.parameterCount) }
    }

    // MARK: - Text helpers

    /// Fold primary (non-extension) decls into a name → kind lookup for
    /// corpus-reference resolution.
    private static func foldKinds(_ typeDecls: [TypeDecl]) -> [String: TypeDecl.Kind] {
        var kindByName: [String: TypeDecl.Kind] = [:]
        for decl in typeDecls where decl.kind != .extension {
            kindByName[decl.name] = decl.kind
        }
        return kindByName
    }

    private static func returnsVoid(_ returnTypeText: String?) -> Bool {
        guard let text = returnTypeText else { return true }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed == "Void" || trimmed == "()"
    }

    /// A closure type contains a top-level `->`. (A false positive on an exotic
    /// `[K: () -> V]` container is acceptable in recognition — it is still a
    /// reference-capturing shape worth a human's eye.)
    private static func isClosureType(_ type: String) -> Bool {
        type.contains("->")
    }

    /// Strip leading type attributes (`@escaping`, `@Sendable`, `@autoclosure`)
    /// and surrounding whitespace.
    private static func stripAttributes(_ type: String) -> String {
        var text = type.trimmingCharacters(in: .whitespaces)
        for attribute in ["@escaping", "@Sendable", "@autoclosure"] {
            while text.hasPrefix(attribute) {
                text = String(text.dropFirst(attribute.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return text
    }

    /// Leading identifier of a type: strip trailing optional markers and any
    /// generic argument clause. `"Box?"` → `"Box"`, `"Cache<Int>"` → `"Cache"`.
    private static func baseName(of type: String) -> String {
        var text = type.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("?") || text.hasSuffix("!") {
            text = String(text.dropLast())
        }
        if let angle = text.firstIndex(of: "<") {
            text = String(text[..<angle])
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
