import PropertyLawCore

/// Bridge from SwiftInfer's per-decl `TypeDecl` records (M3.2 + M4.1) to
/// `PropertyLawCore.TypeShape` — the strategist's input contract per
/// `Sources/PropertyLawCore/DerivationStrategy.swift:120` in SwiftPropertyLaws.
/// M4.2's `GeneratorSelection` calls `DerivationStrategist.strategy(for:)`
/// against the `TypeShape`s this enum produces.
///
/// Folding logic per the M4 plan:
/// - Group `TypeDecl`s by `name`. The corpus may declare the same type
///   in multiple records (one primary + N extensions) per the M3 plan's
///   open decision #2 mergeable-multimap shape.
/// - Pick the primary decl (kind ∈ {struct, class, enum, actor}) for
///   `TypeShape.kind`, `storedMembers`, `hasUserInit`. Extensions can't
///   add stored properties (Swift compile error) and don't suppress the
///   synthesised init even when they declare one (per the strategist
///   contract).
/// - Same-file extensions merge into `inheritedTypes` (so
///   `extension Foo: Hashable {}` in the same file as `struct Foo`
///   propagates `Hashable` into the shape's inheritance) and OR into
///   `hasUserGen` (per the M4 plan's open decision #1 default of
///   same-file-only for `gen()` discovery — matches the strategist's
///   docstring contract that user `gen()` lives "on the type or via an
///   extension in the same file").
/// - Extensions in *different* files contribute neither inheritance nor
///   `hasUserGen`. The M3.3 `EquatableResolver` reaches into raw
///   `TypeDecl`s for cross-file conformance evidence; the strategist's
///   shape doesn't need it.
/// - Records with only `.extension` entries (no primary decl in the
///   corpus) are skipped — `TypeShape.Kind` doesn't model
///   `.extension`, and a strategist call against a third-party type
///   would short-circuit on `hasUserGen` only anyway.
public enum TypeShapeBuilder {

    /// Fold a flat list of `TypeDecl`s into one `TypeShape` per
    /// distinct primary type. Output is sorted by `name` so the result
    /// is deterministic across runs (PRD §16 #6 byte-stability).
    /// Grouped by `TypeDecl.qualifiedName`, not `name`.
    ///
    /// Grouping by the bare name silently merged every same-named type in the
    /// scanned target into one shape — eight `Kind`s, seven `Visitor`s and six
    /// `CodingKeys` in this repo alone — with the primary decided by scan order
    /// and same-file extension merging able to graft one type's conformances onto
    /// another's namesake. See `TypeDecl.qualifiedName`.
    ///
    /// The emitted `TypeShape.name` is therefore the **qualified** spelling, which
    /// is also what makes the generated code correct: a nested type must be
    /// spelled `Enclosing.Nested` to be nameable from a verifier, and every
    /// emitter interpolates the name verbatim, so no emitter needed changing.
    public static func shapes(from typeDecls: [TypeDecl]) -> [TypeShape] {
        var byName: [String: [TypeDecl]] = [:]
        for decl in typeDecls {
            byName[decl.qualifiedName, default: []].append(decl)
        }
        let qualifiedNames = Set(byName.keys)
        return byName.keys
            .sorted()
            .compactMap { name in
                shape(name: name, group: byName[name] ?? [], universe: qualifiedNames)
            }
    }

    /// Resolve a member's type *spelling* against the scanned universe the way
    /// Swift resolves it: innermost enclosing scope first, then outward, then
    /// file scope.
    ///
    /// Source writes `kind: Kind` inside `IndexedTypeShape`, so qualifying the
    /// shape *names* without also qualifying the *references* would leave every
    /// nested member unresolvable — trading a wrong answer for no answer. For a
    /// member of `A.B` spelled `X` this tries `A.B.X`, then `A.X`, then `X`.
    ///
    /// Substitution is whole-word so composite spellings carry through:
    /// `[StoredMember]` becomes `[IndexedTypeShape.StoredMember]`, and
    /// `[String: Kind]` rewrites only the `Kind`.
    static func resolvedSpelling(
        _ spelling: String,
        enclosing: String,
        universe: Set<String>
    ) -> String {
        // Candidate scopes, innermost first: `A.B` → ["A.B", "A", ""].
        var scopes: [String] = []
        var components = enclosing.split(separator: ".").map(String.init)
        while !components.isEmpty {
            scopes.append(components.joined(separator: "."))
            components.removeLast()
        }

        var result = spelling
        for identifier in Self.identifiers(in: spelling) {
            // Belt-and-braces, not the mechanism. What actually protects an
            // already-qualified spelling is that BOTH `identifiers(in:)` and
            // `replacingWholeWord` treat `.` as part of an identifier, so
            // `Outer.Kind` arrives as one token and never matches a bare `Kind`.
            // Mutation-tested: removing this line changes nothing, while dropping
            // `.` from both charsets breaks seven tests. Kept as a cheap early
            // exit and as a guard against a future charset change.
            guard !identifier.contains(".") else { continue }
            for scope in scopes {
                let candidate = "\(scope).\(identifier)"
                guard universe.contains(candidate) else { continue }
                result = Self.replacingWholeWord(identifier, with: candidate, in: result)
                break
            }
        }
        return result
    }

    /// The bare identifiers in a type spelling — everything that is not
    /// punctuation, whitespace, or a leading `[`/`?`/`:` decoration.
    private static func identifiers(in spelling: String) -> [String] {
        var found: [String] = []
        var current = ""
        for character in spelling {
            if character.isLetter || character.isNumber || character == "_" || character == "." {
                current.append(character)
            } else {
                if !current.isEmpty { found.append(current) }
                current = ""
            }
        }
        if !current.isEmpty { found.append(current) }
        return found
    }

    /// Replace `identifier` with `replacement` only where it stands as a whole
    /// identifier — so rewriting `Kind` never touches `CardinalityFieldKind`.
    private static func replacingWholeWord(
        _ identifier: String,
        with replacement: String,
        in text: String
    ) -> String {
        var result = ""
        var current = ""
        for character in text {
            if character.isLetter || character.isNumber || character == "_" || character == "." {
                current.append(character)
            } else {
                result += (current == identifier ? replacement : current)
                result.append(character)
                current = ""
            }
        }
        result += (current == identifier ? replacement : current)
        return result
    }

    /// Build a `TypeShape` for the named type from its corpus records.
    /// Returns `nil` when `group` is extension-only *and* supplies no user
    /// `gen()` (no kind to assign).
    private static func shape(
        name: String,
        group: [TypeDecl],
        universe: Set<String>
    ) -> TypeShape? {
        guard let primary = group.first(where: { $0.kind != .extension }) else {
            // WS-4 — no primary decl: an external/opaque type referenced only via
            // an extension in the scanned target. If that extension supplies a
            // user `static func gen()`, emit a synthetic `hasUserGen` shape so the
            // escape hatch works for external carriers (e.g. `extension URL {
            // static func gen() }` unblocks a `URL` carrier). The strategist's
            // `.userGen` short-circuits before any kind/member checks, so the
            // placeholder `.struct` kind is irrelevant.
            guard group.contains(where: \.hasUserGen) else { return nil }
            return TypeShape(name: name, kind: .struct, inheritedTypes: [], hasUserGen: true)
        }
        guard let kind = TypeShape.Kind(swiftInferKind: primary.kind) else {
            return nil
        }
        let sameFileExtensions = group.filter { decl in
            decl.kind == .extension && decl.location.file == primary.location.file
        }
        let mergedInherited = primary.inheritedTypes
            + sameFileExtensions.flatMap(\.inheritedTypes)
        // `hasUserGen` is OR'd across the WHOLE group (any-file extensions), not
        // just same-file ones: a `static func gen()` supplied in a separate file
        // (e.g. a dedicated `PBTGenerators.swift`) is a valid escape hatch for a
        // type declared elsewhere in the scanned target. Merged conformances /
        // enum cases stay same-file-scoped (they can be conditional and
        // file-local); the gen() signal is a plain boolean "a generator exists".
        let hasUserGen = primary.hasUserGen
            || group.contains { $0.kind == .extension && $0.hasUserGen }
        // Enum cases can be added by same-file extensions; union them.
        let mergedEnumCases = primary.enumCases
            + sameFileExtensions.flatMap(\.enumCases)
        // The enclosing scope of this type's own members is the type itself, so
        // `Kind` written inside `IndexedTypeShape` resolves to
        // `IndexedTypeShape.Kind` if such a nested type was scanned.
        let resolve = { (spelling: String) in
            Self.resolvedSpelling(spelling, enclosing: name, universe: universe)
        }
        return TypeShape(
            name: name,
            kind: kind,
            inheritedTypes: mergedInherited,
            hasUserGen: hasUserGen,
            storedMembers: primary.storedMembers.map {
                StoredMember(name: $0.name, typeName: resolve($0.typeName))
            },
            hasUserInit: primary.hasUserInit,
            initializers: primary.initializers.map { signature in
                InitializerSignature(
                    parameters: signature.parameters.map {
                        InitializerParameter(label: $0.label, typeName: resolve($0.typeName))
                    },
                    isFailable: signature.isFailable,
                    isThrowing: signature.isThrowing
                )
            },
            enumCases: mergedEnumCases
        )
    }
}

private extension TypeShape.Kind {

    /// Map SwiftInfer's `TypeDecl.Kind` (which adds `.extension` and `.protocol`) onto
    /// the strategist's `TypeShape.Kind`. Returns `nil` for both of those — neither is a
    /// primary kind, so records of that kind are skipped.
    ///
    /// The `.protocol` arm is the load-bearing half of the 2026-07-30 scanner change.
    /// Protocol decls are now recorded (for their inheritance clause), and returning `nil`
    /// here is what keeps them from leaking into the rest of the pipeline: a protocol is not
    /// a concrete type, has no values to generate, and must never become a strategist target.
    init?(swiftInferKind kind: TypeDecl.Kind) {
        switch kind {
        case .struct: self = .struct
        case .class: self = .class
        case .enum: self = .enum
        case .actor: self = .actor
        case .extension, .protocol: return nil
        }
    }
}
