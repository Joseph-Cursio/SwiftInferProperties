/// **What a template matched, carried as data rather than rendered into prose (#477).**
///
/// ## The defect this closes
///
/// Four templates computed a structured match, spent it on a signal detail or a caveat sentence,
/// and dropped it. `guard-domain` knows the condition, the returned expression, the parameter the
/// law quantifies over and which way the guard fires — and by the time a `Suggestion` reaches the
/// accept path, all four facts survive only inside
/// `"the body states it: !(source.hasPrefix(\"---\")) ⟹ parse(source) == (Self(), source)"`.
///
/// So a stub writer had two options: parse that sentence back apart, or emit nothing. It emitted
/// nothing — **62 declined `guard-domain` suggestions in the corpus funnel census, the largest
/// population of the nine templates #468 found without a writer.**
///
/// Parsing it back is the option that must not be taken. This project has recorded the shape often
/// enough to name it: a measurement that pattern-matches on text measures the text.
/// `Evidence.parameterTypeNames` exists for exactly this reason on the evidence side — *"that
/// string is a rendering, and splitting it back apart is wrong the moment a parameter is itself
/// generic over two arguments"* — and this is the same rule applied to the match.
///
/// ## Why an enum rather than optional fields on `Suggestion`
///
/// Per-template optional fields would put four properties on `Suggestion` of which at most one is
/// ever non-`nil`, and nothing would say so. A closed enum says *this suggestion carries exactly
/// one template's match, or none*, and a writer that switches on it cannot read `partition`'s
/// fields off a `guard-domain` row.
///
/// ## Text only — no `FunctionSummary` crosses this line
///
/// `PartitionShape` holds two whole `FunctionSummary` values, and `PartitionMatch` flattens them to
/// names. That is deliberate and it is `Evidence`'s rule, stated where `Evidence` states it:
/// *"captured as text rather than a pointer back to the `FunctionSummary` so renderer output is
/// decoupled from the parsing pipeline."* A payload that dragged the parse tree into the render
/// model would couple every consumer of a `Suggestion` to the scanner.
///
/// ## Adding a case is a claim about a writer
///
/// A match is carried so that something can *read* it. Three of the four cases below have a
/// measured population of **one or zero** — see `docs/measurements/template-match-payloads.md` —
/// and are carried anyway because the cost is one case and the alternative is a seam that exists
/// for one template and looks arbitrary. Do not read their presence as evidence that a writer for
/// them is warranted; read the population.
public enum TemplateMatch: Sendable, Equatable {

    /// `guard-domain` — the sub-domain the body's own early return carves out. See `GuardDomain`.
    case guardDomain(GuardDomain)

    /// `selection-subset` — the container member the result must be drawn from.
    case selectionSubset(SelectionSubsetMatch)

    /// `diff-disjointness` — the complementary member pair that must not overlap.
    case diffDisjointness(DiffDisjointnessMatch)

    /// `partition` — the tiler, its form, and the optional progress member.
    case partition(PartitionMatch)

    /// `rewrite-postcondition` — the tokens a string-rewriting body removes. See `RewritePostcondition`.
    case rewritePostcondition(RewritePostcondition)

    /// The `GuardDomain` this match carries, or `nil` for any other template.
    ///
    /// Present so a writer reads one accessor rather than spelling a `switch` with three
    /// `return nil` arms at every call site. Each case gets one as it gains a reader.
    public var guardDomainMatch: GuardDomain? {
        guard case .guardDomain(let domain) = self else { return nil }
        return domain
    }

    /// The `RewritePostcondition` this match carries, or `nil` for any other template.
    public var rewritePostconditionMatch: RewritePostcondition? {
        guard case .rewritePostcondition(let postcondition) = self else { return nil }
        return postcondition
    }
}

/// `selection-subset`'s match: the result is a subset of `containerType.collectionMember`.
///
/// `filter-subset`'s haystack is an argument and is recoverable from the signature, which is why
/// that template needs no payload. This one's lives *inside* a container argument, so nothing in
/// the signature names it — `layerChain(URL, ConfigTree) -> [DiscoveredConfig]` says nothing about
/// `ConfigTree.configs`. The member name is the whole of what a writer needs and the whole of what
/// was being discarded.
public struct SelectionSubsetMatch: Sendable, Equatable {

    /// The container the selection reads from — `ConfigTree`.
    public let containerType: String

    /// Its `[T]`-typed stored member — `configs`.
    public let collectionMember: String

    /// The element type shared by the member and the return — `DiscoveredConfig`.
    public let elementType: String

    public init(containerType: String, collectionMember: String, elementType: String) {
        self.containerType = containerType
        self.collectionMember = collectionMember
        self.elementType = elementType
    }
}

/// `diff-disjointness`'s match: `added ∩ removed = ∅` over one returned type's two members.
public struct DiffDisjointnessMatch: Sendable, Equatable {

    /// The returned diff type — `FileDiff`.
    public let diffType: String

    /// The first of the complementary members — `added`.
    public let memberA: String

    /// The second — `removed`.
    public let memberB: String

    /// The element type both members hold.
    public let elementType: String

    public init(diffType: String, memberA: String, memberB: String, elementType: String) {
        self.diffType = diffType
        self.memberA = memberA
        self.memberB = memberB
        self.elementType = elementType
    }
}

/// How a partition's tiler names the part it produces.
///
/// Declared here rather than nested in `PartitionShape` so one definition serves both the pairing
/// pass and the carried match; `PartitionShape.TilerForm` is a typealias to it. **The tiling law
/// reads differently for each**, and stating the wrong one at a reader is worse than stating none.
public enum PartitionTilerForm: Sendable, Equatable {

    /// `(Int) -> Range<Int>` — the part is a range *into* the whole. Consecutive parts must abut.
    case range

    /// `(C, Int) -> C` — the part *is* a slice of the whole. The parts must concatenate to it.
    case slice
}

/// `partition`'s match, flattened to names — see the type-level note on why no `FunctionSummary`
/// crosses this line.
public struct PartitionMatch: Sendable, Equatable {

    /// The type doing the partitioning — `ChunkPlan`.
    public let typeName: String

    /// The member mapping a part index to the part — `byteRange(ofChunk:)`'s bare name.
    public let tilerName: String

    /// Which of the two tiler shapes it is. Decides which tiling law a writer states.
    public let tilerForm: PartitionTilerForm

    /// The tiler's integer part-index parameter, by internal name — what a generator must supply
    /// out-of-range values for, and without which the totality clause is decoration.
    public let indexParameterName: String?

    /// The `(Int) -> Double` progress member over the same index domain, or `nil`. Its law is a
    /// separate clause — monotonic, within `0...1`, terminating at `1.0` — so a writer needs to
    /// know whether there is one before it can state it.
    public let progressName: String?

    public init(
        typeName: String,
        tilerName: String,
        tilerForm: PartitionTilerForm,
        indexParameterName: String?,
        progressName: String?
    ) {
        self.typeName = typeName
        self.tilerName = tilerName
        self.tilerForm = tilerForm
        self.indexParameterName = indexParameterName
        self.progressName = progressName
    }
}
