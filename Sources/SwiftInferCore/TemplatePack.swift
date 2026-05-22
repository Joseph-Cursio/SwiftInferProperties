import Foundation

/// V1.32.A — Domain Template Packs (PRD §20.3). Splits the monolithic
/// 10-template registry into 5 named domain packs so users can opt their
/// codebase into the templates that fit its character and skip the rest.
///
/// PRD §20.3 made this contingent on benchmark data: *"v1 registry is
/// monolithic by design — splitting requires benchmark data to know
/// which signals fire too often outside their natural domain."* Cycles
/// 1–28 are that benchmark data; the per-template per-corpus rate
/// tables in `docs/calibration-cycle-*-findings.md` directly inform
/// the pack groupings below.
///
/// Pack membership is **non-exclusive**: a template can be in multiple
/// packs (e.g., `monotonicity` is in both `numeric` and `collections`;
/// `commutativity` is in both `numeric` and `algebraic`). The grouping
/// describes "this template is useful for codebases of type X," not
/// "this template *only* applies to X."
public enum TemplatePack: String, CaseIterable, Sendable {

    /// Algebraic ops on numeric types: distributivity, additive/
    /// multiplicative identities, ordering relations. Targets math-
    /// heavy corpora (swift-numerics ComplexModule was the calibration
    /// anchor for this pack).
    case numeric

    /// Forward/inverse pairs: encode/decode, parse/format, pack/unpack.
    /// Targets codec and serialization-heavy corpora.
    case serialization

    /// Collection-shaped properties: sort/normalize idempotence,
    /// form/non-form dual-style consistency, monotone iteration,
    /// composition over indexing. Targets collection-library corpora
    /// (swift-collections OrderedCollections was the calibration anchor).
    case collections

    /// Algebraic-structure laws: semigroup, monoid, group, semilattice,
    /// semiring. Targets algebra-modeling corpora.
    case algebraic

    /// Aspirational per PRD §20.3 — task composition, cancellation
    /// idempotence, merge associativity. No current SwiftInfer templates
    /// target concurrency primitives; the pack name is reserved for
    /// future template additions.
    case concurrency

    /// Set of `Suggestion.templateName` values associated with this pack.
    ///
    /// Membership grounded in PRD §20.3 wording + cycle-1..28 surface
    /// evidence. Templates that surface canonical patterns for the
    /// pack's domain are included; templates that primarily noise the
    /// domain are excluded.
    public var templateNames: Set<String> {
        switch self {
        case .numeric:
            return [
                "commutativity",
                "associativity",
                "identity-element",
                "monotonicity"
            ]

        case .serialization:
            return [
                "round-trip",
                "inverse-pair"
            ]

        case .collections:
            return [
                "idempotence",
                "monotonicity",
                "dual-style-consistency",
                "composition",
                "invariant-preservation"
            ]

        case .algebraic:
            return [
                "commutativity",
                "associativity",
                "identity-element",
                "idempotence",
                "composition"
            ]

        case .concurrency:
            // Aspirational — no current templates target concurrency.
            return []
        }
    }

    /// Returns the union of `templateNames` across `packs`. Used by
    /// `TemplateRegistry.discover`'s `templateFilter` parameter
    /// (V1.32.B) and by the CLI `--packs` flag parser (V1.32.C).
    ///
    /// Empty set when `packs` is empty — caller's responsibility to
    /// emit a diagnostic warning if zero effective templates is
    /// unexpected (V1.32.C handles this in the CLI layer).
    public static func resolve(_ packs: Set<Self>) -> Set<String> {
        Set(packs.flatMap(\.templateNames))
    }

    /// All shipped template names, computed as the union across every
    /// non-empty pack. Equivalent to running every template (the
    /// monolithic-registry behavior). Used by the V1.32.C CLI layer as
    /// the "no `--packs` flag, no config setting" default.
    public static var allTemplateNames: Set<String> {
        resolve(Set(Self.allCases))
    }

    /// Parses a comma-separated pack-name string like `"numeric,serialization"`
    /// into a `Set<TemplatePack>`. Unknown pack names are silently
    /// dropped; the CLI layer (V1.32.C) is responsible for diagnostic
    /// warnings on dropped entries.
    public static func parse(_ commaSeparated: String) -> Set<Self> {
        let names = commaSeparated
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var result: Set<Self> = []
        for name in names {
            if let pack = Self(rawValue: name) {
                result.insert(pack)
            }
        }
        return result
    }

    /// Pack names that appear in `commaSeparated` but do not resolve to
    /// a `TemplatePack` raw value. Used by the CLI layer (V1.32.C) to
    /// emit per-name diagnostic warnings.
    public static func unknownPackNames(in commaSeparated: String) -> [String] {
        commaSeparated
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && Self(rawValue: $0) == nil }
    }
}
