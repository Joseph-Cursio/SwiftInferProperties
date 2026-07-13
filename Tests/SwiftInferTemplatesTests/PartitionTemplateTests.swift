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
}
