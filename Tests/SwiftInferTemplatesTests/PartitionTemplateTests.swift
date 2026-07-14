import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The partition / tiling law — the first template in this catalogue that proposes a law which can
/// **fail**.
///
/// The catalogue was algebraic (`T -> T`, `(T, T) -> T`, encode/decode) and calibrated on libraries,
/// whose interesting surface *is* an algebra. Application code is not shaped like that, and the
/// consequence was measurable: on a real iOS app the pipeline returned **six suggestions and zero
/// refutable claims** — all six determinism laws, `f(x) == f(x)`, which a pure function satisfies by
/// definition and which therefore cannot go red for any reason having to do with what it computes.
///
/// Purity is a licence, not a hypothesis. A law comes from a function's **role**, and a role is what
/// a template encodes.
@Suite("Partition — the parts must tile the whole")
struct PartitionTemplateTests {

    private static let loc = SourceLocation(file: "ChunkPlan.swift", line: 1, column: 1)

    private func member(
        _ name: String,
        parameters: [Parameter],
        returns: String?,
        type: String? = "ChunkPlan"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returns,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: Self.loc,
            containingTypeName: type,
            bodySignals: .empty
        )
    }

    private func parameter(_ label: String?, _ name: String, _ type: String) -> Parameter {
        Parameter(label: label, internalName: name, typeText: type, isInout: false)
    }

    /// The road-test's `ChunkPlan`, reduced to the two members that carry the shape.
    private var chunkPlan: [FunctionSummary] {
        [
            member(
                "byteRange",
                parameters: [parameter("ofChunk", "index", "Int")],
                returns: "Range<Int>"
            ),
            member(
                "progress",
                parameters: [parameter("afterCompleting", "index", "Int")],
                returns: "Double"
            )
        ]
    }

    // MARK: - The motivating case

    @Test("an index-to-range member is a partition")
    func chunkPlanIsAPartition() throws {
        let shapes = PartitionPairing.candidates(in: chunkPlan)

        #expect(shapes.count == 1)
        let shape = try #require(shapes.first)
        #expect(shape.typeName == "ChunkPlan")
        #expect(shape.tiler.name == "byteRange")
        #expect(shape.progress?.name == "progress")
    }

    @Test("the suggested laws are ones an implementation can fail")
    func lawsAreRefutable() throws {
        let shape = try #require(PartitionPairing.candidates(in: chunkPlan).first)
        let suggestion = try #require(PartitionTemplate.suggest(for: shape))
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")

        #expect(suggestion.templateName == "partition")

        // The tiling law. Rejects a chunker that drops the remainder or double-counts a boundary.
        #expect(caveats.contains("tile the whole exactly") || caveats.contains("cover the whole"))

        // Totality. Rejects the `dropFirst(negative)` family — and a negative index is precisely what
        // a corrupt server counter supplies. This is bug #2.
        #expect(caveats.contains("empty range, not a trap"))

        // The empty-whole progress case. This is bug #3, and it is worth naming EXPLICITLY: the
        // general "monotonic and ends at 1.0" property passes vacuously on an empty input, because
        // its sample array is empty and there is no last element to check. A boundary case still has
        // to be named, even under PBT.
        #expect(caveats.contains("including for an empty whole"))

        // The resume clamp. Bug #2's other half.
        #expect(caveats.contains("CLAMPED"))
    }

    // MARK: - Precision

    @Test("the shape is recognised by signature, not by name")
    func namingIsIrrelevant() throws {
        // `ChunkPlan` says `byteRange(ofChunk:)`; another author says `slice(at:)`. A template keyed
        // on vocabulary finds one and misses the other — which is the mistake the effect lattice made
        // when it graded `createRequest` by its prefix. The signature is the evidence.
        let differentlyNamed = [
            member("slice", parameters: [parameter("at", "index", "Int")], returns: "Range<Int>", type: "Pager")
        ]

        let shape = try #require(PartitionPairing.candidates(in: differentlyNamed).first)
        #expect(shape.typeName == "Pager")
        #expect(shape.tiler.name == "slice")
        #expect(shape.progress == nil)
    }

    @Test("a range over an opaque index type is not a partition")
    func opaqueIndexIsNotAPartition() {
        // `Range<String.Index>` has no arithmetic a generator can drive, so there is no tiling law to
        // state over it.
        let opaque = [
            member("range", parameters: [parameter("at", "index", "Int")], returns: "Range<String.Index>")
        ]
        #expect(PartitionPairing.candidates(in: opaque).isEmpty)
    }

    @Test("an ordinary Int-returning member is not a partition")
    func plainMemberIsNotAPartition() {
        let ordinary = [
            member("chunkCount", parameters: [parameter(nil, "size", "Int")], returns: "Int"),
            member("describe", parameters: [parameter(nil, "index", "Int")], returns: "String")
        ]
        #expect(PartitionPairing.candidates(in: ordinary).isEmpty)
    }

    @Test("a free function is not a partition — the shape lives on a type")
    func freeFunctionIsNotAPartition() {
        let free = [
            member(
                "byteRange",
                parameters: [parameter("ofChunk", "index", "Int")],
                returns: "Range<Int>",
                type: nil
            )
        ]
        #expect(PartitionPairing.candidates(in: free).isEmpty)
    }

    @Test("a partition with no progress member still earns its tiling law")
    func tilingWithoutProgress() throws {
        let tilerOnly = [
            member("byteRange", parameters: [parameter("ofChunk", "index", "Int")], returns: "Range<Int>")
        ]
        let shape = try #require(PartitionPairing.candidates(in: tilerOnly).first)
        let suggestion = try #require(PartitionTemplate.suggest(for: shape))
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")

        #expect(caveats.contains("empty range, not a trap"))
        // No progress member ⇒ no progress law to state.
        #expect(caveats.contains("including for an empty whole") == false)
    }

    // MARK: - The OTHER way to write a tiler (B12)

    /// **The shape three cold readers actually wrote.**
    ///
    /// This template recognised only `(Int) -> Range<Int>` — the signature the *reference*
    /// implementation happened to use. Three independent readers, each performing the extraction the
    /// linter demanded, each wrote `chunk(of:at:) -> Data` instead. None was offered a partition law,
    /// so none reached the unclamped-resume-counter bug that the law's own caveat names. The template
    /// was keyed on one author's signature, which is the "keyed on names" mistake in a better
    /// disguise.
    @Test("a tiler that returns the PART, not the range, is still a partition")
    func sliceTilerIsATiler() throws {
        let members = [
            member(
                "chunk",
                parameters: [parameter("of", "data", "Data"), parameter("at", "index", "Int")],
                returns: "Data"
            ),
            member(
                "progress",
                parameters: [parameter("afterSending", "index", "Int")],
                returns: "Double"
            )
        ]

        let shape = try #require(PartitionPairing.candidates(in: members).first)
        #expect(shape.tilerForm == .slice)
        #expect(shape.tiler.name == "chunk")
        #expect(shape.progress?.name == "progress")
    }

    /// The tiling law reads differently for each form, and stating a *range* law at a function that
    /// hands back bytes would send the reader hunting for upper bounds it does not have. A law the
    /// reader cannot encode is worse than silence.
    @Test("a slice tiler is told to assert on the JOIN, not on bounds")
    func sliceTilerStatesTheJoinLaw() {
        let shape = PartitionShape(
            typeName: "ChunkPlan",
            tiler: member(
                "chunk",
                parameters: [parameter("of", "data", "Data"), parameter("at", "index", "Int")],
                returns: "Data"
            ),
            tilerForm: .slice,
            progress: nil
        )
        let caveats = PartitionTemplate.makeCaveats(for: shape).joined(separator: " ")

        #expect(caveats.contains("CONCATENATING the parts"))
        #expect(caveats.contains("Assert on the join"))
        // The totality clause — the one that reaches the resume-counter bug — survives in slice form.
        #expect(caveats.contains("EMPTY part, not a trap"))
        #expect(caveats.contains("dropFirst(negative)"))
        // And it must NOT tell a byte-returning function about upper bounds it does not have.
        #expect(caveats.contains("part `i`'s upper bound") == false)
    }

    /// **The false positive this nearly shipped, and the reason the slice form needs a tiebreak.**
    ///
    /// `(C, Int) -> C` is a filter-with-a-scalar, a prefix, a page, *and* a partition — the signature
    /// does not choose. Uncorroborated, the template proposed a tiling law over `above(_:threshold:)`,
    /// which tiles nothing; a reader would have watched it fail for a reason that is not a bug. The
    /// range form needs no tiebreak precisely because `Range<Int>` already made the claim.
    @Test("a filter with a scalar parameter is NOT a partition")
    func filterWithScalarIsNotATiler() {
        let members = [
            member(
                "above",
                parameters: [parameter(nil, "items", "[Int]"), parameter("threshold", "threshold", "Int")],
                returns: "[Int]",
                type: "Library"
            )
        ]

        #expect(PartitionPairing.candidates(in: members).isEmpty)
    }

    @Test("a prefix taking a COUNT is not a partition either")
    func prefixByCountIsNotATiler() {
        let members = [
            member(
                "first",
                parameters: [parameter(nil, "docs", "[String]"), parameter("count", "count", "Int")],
                returns: "[String]",
                type: "Library"
            )
        ]

        #expect(PartitionPairing.candidates(in: members).isEmpty)
    }

    /// A one-parameter slice form is not distinctive at all — every `item(at:) -> [Tag]` lookup in
    /// existence has that signature. Requiring the whole to appear, with the type the function
    /// returns, is what makes "these are parts *of that*" legible from the signature alone.
    @Test("a lookup returning a sub-collection is not a partition")
    func lookupWithoutTheWholeIsNotATiler() {
        let members = [
            member(
                "tags",
                parameters: [parameter("at", "index", "Int")],
                returns: "[String]",
                type: "Library"
            )
        ]

        #expect(PartitionPairing.candidates(in: members).isEmpty)
    }

    // MARK: - The law ships the generator it needs

    /// **A generator over `0..<count` checks totality against the indices that were never in
    /// question.** The clause claims something about the indices the code did *not* expect, and the
    /// only way to refute it is to supply them: negative, and past the end. `dropFirst(negative)`
    /// traps — and a negative index is what a corrupt resume counter supplies, which is the bug this
    /// law exists to catch.
    @Test("the partition law ships an out-of-range index generator")
    func partitionShipsOutOfRangeIndexGenerator() throws {
        let shape = PartitionShape(
            typeName: "ChunkPlan",
            tiler: member(
                "chunk",
                parameters: [parameter("of", "data", "Data"), parameter("at", "index", "Int")],
                returns: "Data"
            ),
            tilerForm: .slice,
            progress: nil
        )

        let recipe = try #require(PartitionTemplate.makeGenerators(for: shape).first)
        #expect(recipe.subject == "index")
        #expect(recipe.expression.contains("-50...500"))
        #expect(recipe.rationale.contains("corrupt resume counter"))
    }

    /// The recipe must survive the whole pipeline, not just the template. A `Suggestion` copy that
    /// silently drops the field renders correctly in every respect except that the generators are
    /// gone — which is the half that decides whether the law can fail.
    @Test("the generator survives into the Suggestion")
    func generatorSurvivesIntoSuggestion() throws {
        let shape = PartitionShape(
            typeName: "ChunkPlan",
            tiler: member(
                "chunk",
                parameters: [parameter("of", "data", "Data"), parameter("at", "index", "Int")],
                returns: "Data"
            ),
            tilerForm: .slice,
            progress: nil
        )

        let suggestion = try #require(PartitionTemplate.suggest(for: shape))
        #expect(suggestion.generatorRecipes.isEmpty == false)
        #expect(suggestion.generatorRecipes.first?.subject == "index")
    }

    /// When a type offers both, the range form is the stronger evidence and wins.
    @Test("a range tiler outranks a slice tiler on the same type")
    func rangeTilerWins() throws {
        let members = [
            member(
                "chunk",
                parameters: [parameter("of", "data", "Data"), parameter("at", "index", "Int")],
                returns: "Data"
            ),
            member(
                "byteRange",
                parameters: [parameter("ofChunk", "index", "Int")],
                returns: "Range<Int>"
            )
        ]

        let shape = try #require(PartitionPairing.candidates(in: members).first)
        #expect(shape.tilerForm == .range)
        #expect(shape.tiler.name == "byteRange")
    }
}
