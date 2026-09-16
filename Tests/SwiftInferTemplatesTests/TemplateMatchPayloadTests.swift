import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// **Four templates computed a match and spent it on prose (#477).** These pin that the match now
/// survives onto the `Suggestion` as data.
///
/// The thing being guarded is not that a field exists — it is that **a writer never has to parse
/// a signal detail back apart**. `guard-domain`'s law is
/// `!(source.hasPrefix("---")) ⟹ parse(source) == (Self(), source)`, and until this the only
/// place the condition, the returned expression, the quantified parameter and the guard's
/// direction existed after `suggest` returned was inside that sentence. Recovering them from it
/// is the defect this repository keeps recording: a measurement that pattern-matches on text
/// measures the text.
///
/// So each test below asserts the payload **and** that the payload agrees with the prose the same
/// value produced, because a payload that disagreed with the rendering would be worse than none.
@Suite("Template match payloads — what the template matched, carried as data")
struct TemplateMatchPayloadTests {

    private static let loc = SourceLocation(file: "Subject.swift", line: 12, column: 5)

    private func summary(
        _ name: String,
        parameters: [Parameter],
        returns: String?,
        owner: String? = "FrontMatter",
        guardDomain: GuardDomain? = nil,
        isThrows: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returns,
            isThrows: isThrows,
            isAsync: false,
            isMutating: false,
            isStatic: true,
            location: Self.loc,
            containingTypeName: owner,
            bodySignals: BodySignals(
                guardDomain: guardDomain,
                hasNonDeterministicCall: false,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: []
            )
        )
    }

    private func param(_ label: String?, _ type: String, internalName: String? = nil) -> Parameter {
        Parameter(
            label: label,
            internalName: internalName ?? label ?? "value",
            typeText: type,
            isInout: false
        )
    }

    // MARK: - guard-domain

    /// The template's own documented example, carried whole.
    @Test("guard-domain carries the condition, the expression, the parameter and the direction")
    func guardDomainPayload() throws {
        let domain = GuardDomain(
            condition: "source.hasPrefix(\"---\")",
            returnedExpression: "(Self(), source)",
            parameterName: "source",
            firesWhenConditionHolds: false
        )
        let suggestion = try #require(
            GuardDomainTemplate.suggest(
                for: summary(
                    "parse",
                    parameters: [param("from", "String", internalName: "source")],
                    returns: "(FrontMatter, String)",
                    guardDomain: domain
                )
            )
        )
        let carried = try #require(suggestion.match?.guardDomainMatch)
        #expect(carried == domain)
        #expect(carried.firesWhenConditionHolds == false, "a `guard` states the OPPOSITE sub-domain")
    }

    /// **The payload and the prose are built from one value, so they cannot disagree.** Asserted
    /// rather than assumed: the failure this closes is a payload that drifts from the sentence a
    /// reader is shown, which would be worse than carrying nothing.
    @Test("guard-domain's payload agrees with the signal it renders")
    func guardDomainPayloadAgreesWithProse() throws {
        let domain = GuardDomain(
            condition: "scale > 0",
            returnedExpression: "0",
            parameterName: "scale",
            firesWhenConditionHolds: false
        )
        let suggestion = try #require(
            GuardDomainTemplate.suggest(
                for: summary(
                    "wordCount",
                    parameters: [param("forScale", "Int", internalName: "scale")],
                    returns: "Int",
                    guardDomain: domain
                )
            )
        )
        let carried = try #require(suggestion.match?.guardDomainMatch)
        let prose = suggestion.explainability.whySuggested.joined(separator: "\n")
        #expect(prose.contains(carried.condition))
        #expect(prose.contains(carried.returnedExpression))
    }

    /// A template that carries no payload says so, rather than carrying an empty one. `nil` is the
    /// answer for most of the catalogue and has to stay distinguishable from *matched nothing*.
    @Test("a template with no payload carries nil")
    func noPayloadIsNil() throws {
        let suggestion = try #require(
            FilterSubsetTemplate.suggest(
                for: summary(
                    "filterRules",
                    parameters: [param(nil, "[Rule]")],
                    returns: "[Rule]",
                    owner: "Analyzer"
                )
            )
        )
        #expect(suggestion.match == nil)
        #expect(suggestion.match?.guardDomainMatch == nil)
    }

    // MARK: - selection-subset

    @Test("selection-subset carries the container member the result is drawn from")
    func selectionSubsetPayload() throws {
        let shapes = [
            "ConfigTree": TypeShape(
                name: "ConfigTree",
                kind: .struct,
                inheritedTypes: [],
                hasUserGen: false,
                storedMembers: [StoredMember(name: "configs", typeName: "[DiscoveredConfig]")],
                hasUserInit: false
            )
        ]
        let suggestion = try #require(
            SelectionSubsetTemplate.suggest(
                for: summary(
                    "layerChain",
                    parameters: [param(nil, "URL"), param(nil, "ConfigTree")],
                    returns: "[DiscoveredConfig]",
                    owner: "Engine"
                ),
                shapesByName: shapes
            )
        )
        guard case .selectionSubset(let match) = try #require(suggestion.match) else {
            Issue.record("expected a selection-subset payload")
            return
        }
        // Nothing in the SIGNATURE names `configs` — that is the whole reason this one needs a
        // payload where `filter-subset`, whose haystack is an argument, does not.
        #expect(match.containerType == "ConfigTree")
        #expect(match.collectionMember == "configs")
        #expect(match.elementType == "DiscoveredConfig")
    }

    // MARK: - diff-disjointness

    @Test("diff-disjointness carries the complementary member pair")
    func diffDisjointnessPayload() throws {
        let shapes = [
            "FileDiff": TypeShape(
                name: "FileDiff",
                kind: .struct,
                inheritedTypes: [],
                hasUserGen: false,
                storedMembers: [
                    StoredMember(name: "added", typeName: "[Line]"),
                    StoredMember(name: "removed", typeName: "[Line]")
                ],
                hasUserInit: false
            )
        ]
        let suggestion = try #require(
            DiffDisjointnessTemplate.suggest(
                for: summary(
                    "diff",
                    parameters: [param(nil, "[Line]"), param(nil, "[Line]")],
                    returns: "FileDiff",
                    owner: "Differ"
                ),
                shapesByName: shapes
            )
        )
        guard case .diffDisjointness(let match) = try #require(suggestion.match) else {
            Issue.record("expected a diff-disjointness payload")
            return
        }
        #expect(match.diffType == "FileDiff")
        #expect([match.memberA, match.memberB] == ["added", "removed"])
        #expect(match.elementType == "Line")
    }

    // MARK: - partition

    /// **No `FunctionSummary` crosses onto the `Suggestion`.** `PartitionShape` holds two whole
    /// summaries; the payload holds names. That is `Evidence`'s rule applied one layer out — a
    /// payload carrying the parse tree would couple every consumer of a `Suggestion` to the
    /// scanner.
    @Test("partition carries the tiler by NAME, its form, the index parameter and the progress member")
    func partitionPayload() throws {
        let tiler = summary(
            "byteRange",
            parameters: [param("ofChunk", "Int", internalName: "chunk")],
            returns: "Range<Int>",
            owner: "ChunkPlan"
        )
        let progress = summary(
            "progress",
            parameters: [param("afterCompleting", "Int", internalName: "completed")],
            returns: "Double",
            owner: "ChunkPlan"
        )
        let shape = PartitionShape(
            typeName: "ChunkPlan",
            tiler: tiler,
            tilerForm: .range,
            progress: progress
        )
        let suggestion = try #require(PartitionTemplate.suggest(for: shape))
        guard case .partition(let match) = try #require(suggestion.match) else {
            Issue.record("expected a partition payload")
            return
        }
        #expect(match.typeName == "ChunkPlan")
        #expect(match.tilerName == "byteRange")
        #expect(match.tilerForm == .range)
        // The index the totality clause needs out-of-range values for; without it that clause is
        // decoration, which is why the payload carries it rather than leaving a writer to guess.
        #expect(match.indexParameterName == "chunk")
        #expect(match.progressName == "progress")
    }

    /// The progress member is optional and its absence is a different law, so `nil` has to be
    /// distinguishable rather than defaulted to a name.
    @Test("partition carries nil progress when the type declares none")
    func partitionWithoutProgress() throws {
        let shape = PartitionShape(
            typeName: "ChunkPlan",
            tiler: summary(
                "slice",
                parameters: [param(nil, "[UInt8]"), param("at", "Int", internalName: "index")],
                returns: "[UInt8]",
                owner: "ChunkPlan"
            ),
            tilerForm: .slice,
            progress: nil
        )
        let suggestion = try #require(PartitionTemplate.suggest(for: shape))
        guard case .partition(let match) = try #require(suggestion.match) else {
            Issue.record("expected a partition payload")
            return
        }
        #expect(match.progressName == nil)
        #expect(match.tilerForm == .slice, "the slice law reads differently from the range law")
        #expect(match.indexParameterName == "index")
    }

    // MARK: - The trap `Suggestion` documents

    /// **A field added to `Suggestion` has been silently dropped by a rebuild site before**, which
    /// is why `withGenerator(_:)` mutates a copy and carries a comment saying so. The payload goes
    /// through `GeneratorSelection` on every real run, so this pins that it survives.
    @Test("the payload survives the generator-metadata rebuild")
    func payloadSurvivesGeneratorSelection() throws {
        let domain = GuardDomain(
            condition: "values.isEmpty",
            returnedExpression: "[]",
            parameterName: "values",
            firesWhenConditionHolds: true
        )
        let suggestion = try #require(
            GuardDomainTemplate.suggest(
                for: summary(
                    "compacted",
                    parameters: [param(nil, "[Int]", internalName: "values")],
                    returns: "[Int]",
                    guardDomain: domain
                )
            )
        )
        let rebuilt = suggestion.withGenerator(.m1Placeholder)
        #expect(rebuilt.match?.guardDomainMatch == domain)
    }
}
