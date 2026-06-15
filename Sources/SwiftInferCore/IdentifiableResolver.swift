/// Three-valued evidence about whether a Swift type can host the `$0.id`
/// reference the referential-integrity verifier emits. Mirrors
/// `EquatableEvidence` / `EquatableResolver` (PRD §5.6's textual-classifier
/// posture): `.notIdentifiable` is reserved for *clear* evidence (a
/// corpus-declared type with neither `Identifiable` conformance nor an `id`
/// member); `.unknown` is the default when textual analysis can't decide
/// (e.g. an external/dependency type whose declaration isn't in the corpus).
///
/// Cycle 139 consumer policy: the refint verify gate
/// (`VerifyInteractionPipeline`) **skips** the build on `.notIdentifiable`
/// (the `$0.id` predicate provably can't compile) and **proceeds** on
/// `.identifiable` / `.unknown` — biasing toward *not* skipping a refint
/// that might verify (an attempted-but-doomed build is the pre-cycle-139
/// behavior, no regression; a wrongly-skipped verifiable refint would be a
/// regression).
public enum IdentifiableEvidence: Sendable, Equatable {
    case identifiable
    case notIdentifiable
    case unknown
}

/// Best-effort textual `Identifiable` classifier built from
/// `ScannedCorpus.typeDecls`. A type lifts to `.identifiable` when a
/// corpus `TypeDecl` (primary or extension, merged by `name` exactly as
/// `EquatableResolver` does) either declares `Identifiable` in its
/// inheritance clause **or** declares a stored `id` member — both make the
/// emitted `state.collection.contains { $0.id == … }` predicate compile.
///
/// Limitations (accepted, same spirit as `EquatableResolver`): a computed
/// `id` added in a separate extension isn't a stored member and won't lift
/// the type — it classifies `.notIdentifiable` (a possible false skip). The
/// gate's conservative consumer policy keeps that to a skipped-but-verifiable
/// edge rather than a crash, and external types (not in the corpus) stay
/// `.unknown` so the gate never skips a dependency model.
public struct IdentifiableResolver: Sendable {

    /// Inheritance-clause names that imply an `id` member. `Identifiable`
    /// is the canonical (and only standard) one.
    static let knownIdentifiableConformance: Set<String> = ["Identifiable"]

    /// Corpus type names that host `$0.id` (Identifiable conformance or a
    /// stored `id` member).
    private let identifiable: Set<String>

    /// Every corpus-declared type name seen — lets `classify` distinguish a
    /// *seen-but-non-identifiable* type (`.notIdentifiable`) from an
    /// *unseen/external* one (`.unknown`).
    private let declaredNames: Set<String>

    public init(typeDecls: [TypeDecl]) {
        var idable: Set<String> = []
        var declared: Set<String> = []
        for decl in typeDecls {
            declared.insert(decl.name)
            let conforms = decl.inheritedTypes.contains { Self.knownIdentifiableConformance.contains($0) }
            let hasIDMember = decl.storedMembers.contains { $0.name == "id" }
            if conforms || hasIDMember {
                idable.insert(decl.name)
            }
        }
        self.identifiable = idable
        self.declaredNames = declared
    }

    /// Classify a collection element type written as source text.
    /// Resolution order:
    /// 1. Corpus type with `Identifiable` conformance or an `id` member →
    ///    `.identifiable`.
    /// 2. Corpus type seen but with neither → `.notIdentifiable`.
    /// 3. Type not declared in the corpus (external) → `.unknown`.
    public func classify(typeText: String) -> IdentifiableEvidence {
        let trimmed = typeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if identifiable.contains(trimmed) { return .identifiable }
        if declaredNames.contains(trimmed) { return .notIdentifiable }
        return .unknown
    }
}
