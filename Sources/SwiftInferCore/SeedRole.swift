/// What a seeded piece of logic **is**, as the linter classified it.
///
/// `symbol` says where to look and `SeedKind` says whether this tool can call it yet. Neither says
/// what the code *does* — and that is the one thing the linter knows which this tool otherwise has
/// to infer from a signature and a name.
///
/// The gap was visible from this side first. On a manifest that does not name a subject, discover
/// already warns that a law "is owed by the code's ROLE" and that "the manifest SHOULD have named
/// it: this is a LINTER gap". This type is that field arriving.
///
/// ## Roles are not template names, and must not be conflated with them
///
/// `Refutability.roleEntailedTemplates` holds **template** names — `filter-subset`,
/// `caseiterable-key-injectivity` — which are laws this tool proposes. A role is what the *code*
/// is. The two overlap (`comparator`, `predicate`, `partition` appear in both) and are not the same
/// vocabulary: there is no `filter-subset` role, and there is no `transform` template.
///
/// So the mapping is a deliberate, reviewable function (`entailedTemplateName`), not an identity.
/// Merging the two vocabularies would prevent a spelling mismatch at the cost of asserting a
/// correspondence that does not hold.
///
/// ## What can actually drift
///
/// Not the spelling — `unrecognised` handles that, loudly. What can rot is the **entailment claim**.
/// The producer's `PBTSeedRole.impliesEntailedLaw` says `comparator`, `predicate` and `partition`
/// are laws a correct implementation cannot fail. If this tool ever demotes one of them from
/// `roleEntailedTemplates`, that producer-side flag becomes a lie, and a lie in that direction is
/// the specific failure `Refutability` exists to prevent: proposing a law that correct code fails.
///
/// `SeedRoleContractTests` pins the correspondence from this side, so the demotion breaks a test
/// here rather than surfacing as a red property test in someone's repository.
public enum SeedRole: Sendable, Equatable, Hashable {

    /// Ordering logic. Owes a strict weak ordering.
    case comparator

    /// A classification. Owes totality.
    case predicate

    /// A mapping. Owes only that it is a function of its input.
    case transform

    /// A combine step. *Usually* associative, *often* has an identity — both conjectures.
    case reducer

    /// Logic cutting a whole into parts. Owes a tiling.
    case partition

    /// Logic deriving one value from another in the same domain. Owes a round-trip and an
    /// idempotent normalisation — both conjectures.
    case normalizer

    /// A role emitted by a newer linter than this build knows.
    ///
    /// Same asymmetry as `SeedKind.unrecognised`, and the same resolution: an unknown role is
    /// **never** treated as entailed, and is **said out loud**. Guessing "entailed" for a role this
    /// build cannot interpret would propose a law nobody verified; guessing "not entailed" only
    /// loses a hint, and the reader is told which.
    case unrecognised(String)

    public var rawValue: String {
        switch self {
        case .comparator: return "comparator"
        case .predicate: return "predicate"
        case .transform: return "transform"
        case .reducer: return "reducer"
        case .partition: return "partition"
        case .normalizer: return "normalizer"
        case .unrecognised(let raw): return raw
        }
    }

    /// The template whose law this role **entails** — a law a correct implementation cannot fail.
    ///
    /// `nil` for roles whose laws are conjectures (`transform`, `reducer`, `normalizer`) and for
    /// anything this build does not recognise. Every non-nil value here must be a member of
    /// `Refutability.roleEntailedTemplates`; `SeedRoleContractTests` enforces exactly that, which is
    /// what keeps the producer's `impliesEntailedLaw` honest across two independently-versioned
    /// repositories.
    public var entailedTemplateName: String? {
        switch self {
        case .comparator: return "comparator"
        case .predicate: return "predicate"
        case .partition: return "partition"
        case .transform, .reducer, .normalizer, .unrecognised: return nil
        }
    }

    /// A one-line statement of the law, for the refactor-pending listing.
    ///
    /// A kernel seed can never be analysed — it has no name to call — so this sentence is the whole
    /// product of carrying the role. "A comparator at Foo.swift:42, which owes a strict weak
    /// ordering" is a different instruction from "extractable kernel at Foo.swift:42".
    public var lawSentence: String? {
        switch self {
        case .comparator:
            return "a comparator — it owes a strict weak ordering (irreflexive, antisymmetric, "
                + "transitive), and sorting with one that is not can trap"

        case .predicate:
            return "a predicate — it owes totality: an answer for every input its type admits"

        case .partition:
            return "a partition — it owes a tiling: the parts reassemble the whole, no gap, no "
                + "overlap"

        case .transform:
            return "a transform — the interesting law is domain-specific, so state what the result "
                + "must satisfy"

        case .reducer:
            return "a reducer — usually associative and often with an identity, both worth checking"

        case .normalizer:
            return "a normalizer — it owes a round-trip, and applying it twice should equal applying "
                + "it once"

        case .unrecognised:
            return nil
        }
    }
}

extension SeedRole: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "comparator": self = .comparator
        case "predicate": self = .predicate
        case "transform": self = .transform
        case "reducer": self = .reducer
        case "partition": self = .partition
        case "normalizer": self = .normalizer
        default: self = .unrecognised(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
