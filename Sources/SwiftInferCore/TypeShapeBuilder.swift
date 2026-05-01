import ProtoLawCore

/// Bridge from SwiftInfer's per-decl `TypeDecl` records (M3.2 + M4.1) to
/// `ProtoLawCore.TypeShape` — the strategist's input contract per
/// `Sources/ProtoLawCore/DerivationStrategy.swift:120` in SwiftProtocolLaws.
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
    /// Returns `nil` when `group` is extension-only (no kind to assign).
    private static func shape(name: String, group: [TypeDecl]) -> TypeShape? {
        guard let primary = group.first(where: { $0.kind != .extension }) else {
            return nil
        }
        guard let kind = TypeShape.Kind(swiftInferKind: primary.kind) else {
            return nil
        }
        let sameFileExtensions = group.filter { decl in
            decl.kind == .extension && decl.location.file == primary.location.file
        }
        let mergedInherited = primary.inheritedTypes
            + sameFileExtensions.flatMap(\.inheritedTypes)
        let hasUserGen = primary.hasUserGen
            || sameFileExtensions.contains(where: \.hasUserGen)
        return TypeShape(
            name: name,
            kind: kind,
            inheritedTypes: mergedInherited,
            hasUserGen: hasUserGen,
            storedMembers: primary.storedMembers,
            hasUserInit: primary.hasUserInit
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
