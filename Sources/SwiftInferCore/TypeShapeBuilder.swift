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
    public static func shapes(from typeDecls: [TypeDecl]) -> [TypeShape] {
        var byName: [String: [TypeDecl]] = [:]
        for decl in typeDecls {
            byName[decl.name, default: []].append(decl)
        }
        return byName.keys
            .sorted()
            .compactMap { name in shape(name: name, group: byName[name] ?? []) }
    }

    /// Build a `TypeShape` for the named type from its corpus records.
    /// Returns `nil` when `group` is extension-only *and* supplies no user
    /// `gen()` (no kind to assign).
    private static func shape(name: String, group: [TypeDecl]) -> TypeShape? {
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
        return TypeShape(
            name: name,
            kind: kind,
            inheritedTypes: mergedInherited,
            hasUserGen: hasUserGen,
            storedMembers: primary.storedMembers,
            hasUserInit: primary.hasUserInit,
            initializers: primary.initializers,
            enumCases: mergedEnumCases
        )
    }
}

private extension TypeShape.Kind {

    /// Map SwiftInfer's `TypeDecl.Kind` (which adds `.extension`) onto
    /// the strategist's `TypeShape.Kind`. Returns `nil` for `.extension`
    /// — extension-only records have no primary kind and are skipped.
    init?(swiftInferKind kind: TypeDecl.Kind) {
        switch kind {
        case .struct: self = .struct
        case .class: self = .class
        case .enum: self = .enum
        case .actor: self = .actor
        case .extension: return nil
        }
    }
}
