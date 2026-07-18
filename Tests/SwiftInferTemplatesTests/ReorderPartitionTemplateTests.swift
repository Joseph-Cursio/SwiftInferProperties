import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The *reorder* sense of "partition" — an in-place rearrange-by-predicate that
/// returns the pivot — as distinct from the tiling partition the catalogue
/// already had. Motivated by the swift-algorithms `stablePartition(subrange:by:)`
/// count bug (`0dba0e5`), which the tiling template was structurally blind to.
@Suite("ReorderPartitionTemplate — in-place partition-by-predicate")
struct ReorderPartitionTemplateTests {

    private static let loc = SourceLocation(file: "Partition.swift", line: 1, column: 1)

    private func member(
        _ name: String,
        _ parameters: [Parameter],
        returns: String?,
        type: String? = "Array",
        isMutating: Bool = true,
        isThrows: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returns,
            isThrows: isThrows,
            isAsync: false,
            isMutating: isMutating,
            isStatic: false,
            location: Self.loc,
            containingTypeName: type,
            bodySignals: .empty,
            docComment: nil
        )
    }

    private func predicate(_ label: String = "by", type: String = "(Element) -> Bool") -> Parameter {
        Parameter(label: label, internalName: "belongsInSecondPartition", typeText: type, isInout: false)
    }

    private func value(_ label: String?, _ type: String) -> Parameter {
        Parameter(label: label, internalName: "value", typeText: type, isInout: false)
    }

    // MARK: - The shape fires, at Likely, with the right law

    @Test("a mutating stablePartition(by:) -> Int is a reorder-partition at Likely 70")
    func stablePartitionFires() throws {
        let summary = member("stablePartition", [predicate()], returns: "Int")
        #expect(ReorderPartitionTemplate.isReorderPartition(summary))

        let suggestion = try #require(ReorderPartitionTemplate.suggest(for: summary))
        #expect(suggestion.templateName == "reorder-partition")
        #expect(suggestion.score.total == 70)
        #expect(suggestion.score.tier == .likely)

        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")
        // The two free laws, always present.
        #expect(caveats.contains("PIN THE CONVENTION"))
        #expect(caveats.contains("IT IS A PERMUTATION"))
    }

    @Test("the stdlib rethrows -> Index shape fires")
    func stdlibShapeFires() {
        // `mutating func partition(by: (Element) throws -> Bool) rethrows -> Index`
        let summary = member(
            "partition",
            [predicate(type: "(Element) throws -> Bool")],
            returns: "Index",
            isThrows: true
        )
        #expect(ReorderPartitionTemplate.isReorderPartition(summary))
    }

    // MARK: - Stability is name-dependent

    @Test("`stable` in the name promises within-group order; a plain partition does not")
    func stabilityCaveatIsNameGated() throws {
        let stable = try #require(
            ReorderPartitionTemplate.suggest(for: member("stablePartition", [predicate()], returns: "Int"))
        )
        let stableCaveats = stable.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(stableCaveats.contains("STABILITY is promised"))
        #expect(!stableCaveats.contains("NOT guaranteed STABLE"))

        let plain = try #require(
            ReorderPartitionTemplate.suggest(for: member("partition", [predicate()], returns: "Index"))
        )
        let plainCaveats = plain.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(plainCaveats.contains("NOT guaranteed STABLE"))
        #expect(!plainCaveats.contains("STABILITY is promised"))
    }

    // MARK: - The subrange fence — the exact 0dba0e5 failure mode

    @Test("a subrange variant adds the fence caveat")
    func subrangeAddsFenceCaveat() throws {
        let summary = member(
            "stablePartition",
            [value("subrange", "Range<Int>"), predicate()],
            returns: "Int"
        )
        #expect(ReorderPartitionTemplate.isReorderPartition(summary))
        let suggestion = try #require(ReorderPartitionTemplate.suggest(for: summary))
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: "\n")
        #expect(caveats.contains("SUBRANGE IS A FENCE"))
    }

    // MARK: - False-positive guards (the name-gate + shape-gate earn their keep)

    @Test("a non-mutating partitioned(by:) is NOT a reorder-partition")
    func nonMutatingIsRejected() {
        // Returning a fresh pair is a different (still valid) shape; the in-place
        // reorder law is specifically about mutation.
        let summary = member(
            "partitioned",
            [predicate()],
            returns: "([Element], [Element])",
            isMutating: false
        )
        #expect(ReorderPartitionTemplate.isReorderPartition(summary) == false)
        #expect(ReorderPartitionTemplate.suggest(for: summary) == nil)
    }

    @Test("a partition without a predicate is NOT a reorder-partition")
    func noPredicateIsRejected() {
        let summary = member("partition", [value("at", "Int")], returns: "Int")
        #expect(ReorderPartitionTemplate.isReorderPartition(summary) == false)
    }

    @Test("a predicate mutator NOT named partition is rejected (the name-gate)")
    func nonPartitionNameIsRejected() {
        // Without the name-gate every `mutating func f(by: (Element) -> Bool)` would flood.
        let summary = member("rearrange", [predicate()], returns: "Int")
        #expect(ReorderPartitionTemplate.isReorderPartition(summary) == false)
    }

    @Test("a Bool-returning partitionCheck is rejected (no pivot)")
    func boolReturnIsRejected() {
        let summary = member("partitionCheck", [predicate()], returns: "Bool")
        #expect(ReorderPartitionTemplate.isReorderPartition(summary) == false)
    }

    @Test("more than a predicate-plus-subrange is rejected")
    func tooManyParamsRejected() {
        let summary = member(
            "partition",
            [value("a", "Int"), value("b", "Int"), predicate()],
            returns: "Int"
        )
        #expect(ReorderPartitionTemplate.isReorderPartition(summary) == false)
    }

    // MARK: - The predicate-closure detector

    @Test("isPredicateClosure recognizes -> Bool closures, rejects others")
    func predicateClosureDetection() {
        #expect(ReorderPartitionTemplate.isPredicateClosure(predicate(type: "(Element) -> Bool")))
        #expect(ReorderPartitionTemplate.isPredicateClosure(predicate(type: "(Self.Element) throws -> Bool")))
        #expect(ReorderPartitionTemplate.isPredicateClosure(value(nil, "(Element) -> Int")) == false)
        #expect(ReorderPartitionTemplate.isPredicateClosure(value(nil, "Int")) == false)
    }
}
