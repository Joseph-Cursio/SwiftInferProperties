import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
import Testing

/// `Discover.docstringAdvice(summaries:suggestions:unfocusedSuggestions:seedManifest:)` takes TWO
/// suggestion lists, and each half of the advice is decided on its own one.
///
/// - A **seeded** function is decided on the FOCUSED list, because that is where the synthesized
///   determinism law lives — the source its runnable scaffold is drawn from.
/// - An **unseeded** function is decided on the UNFOCUSED list, so its advisory is the value a run
///   without seeds computes. Today the two lists give an unseeded function the same advisory
///   *arm*: every role-entailed law survives the focus (`keepRoleEntailedLaws`) and the tier cut,
///   and a lifted law never joins a production function (its evidence names the test file). They
///   differ in the conjectures the focus drops, which a fallback names as its red herrings. The
///   compact block prints none of that, so these tests read the advisory, not the text.
///
/// Neither half may be "simplified" onto the other's list. One test pins each direction on the
/// function, and one pins the discover path's call site, where the lists are chosen.
@Suite("Discover — each half of the docstring advice is decided on its own list")
struct DocstringAdviceSplitTests {

    private static let file = "/fixture/Source.swift"
    private static let backoffDoc = "Delay is capped at the ceiling and never negative."
    private static let clampDoc = "Returns the value clamped to the range, never negative."

    /// The conjecture is reachable: the focus drops it, because the manifest does not name
    /// `backoffDelay` and `monotonicity` is not role-entailed, so nothing puts it back.
    @Test("an unseeded function's red herrings come from the unfocused suggestions")
    func unseededRedHerringsComeFromUnfocusedSuggestions() {
        let summary = Self.summary(name: "backoffDelay", doc: Self.backoffDoc)
        let guess = Self.suggestion(template: "monotonicity", function: "backoffDelay(_:)")

        // The premise: on what the focus keeps, the fallback names no red herring.
        let onFocused = DocstringAdvisor.advisory(forFunctionWith: Self.backoffDoc, suggestions: [])
        #expect(onFocused == .fallbackContract(.init(docComment: Self.backoffDoc, redHerrings: [])))

        let advice = SwiftInferCommand.Discover.docstringAdvice(
            summaries: [summary],
            suggestions: [],
            unfocusedSuggestions: [guess],
            seedManifest: SeedManifest(seeds: [.init(file: "Source.swift", line: 1, symbol: "elsewhere")])
        )

        #expect(advice.seeded.isEmpty)
        #expect(advice.unseeded.first?.advisory == .fallbackContract(
            .init(docComment: Self.backoffDoc, redHerrings: ["monotonicity"])
        ))
        #expect(advice.unseeded.first?.runnableScaffold == nil)
    }

    @Test("a seeded function keeps the scaffold the focused list's determinism law supplies")
    func seededAdviceIsDecidedOnFocusedSuggestions() {
        let summary = Self.summary(name: "backoffDelay", doc: Self.backoffDoc)
        let determinism = Self.suggestion(template: "determinism", function: "backoffDelay(_:)")

        let advice = SwiftInferCommand.Discover.docstringAdvice(
            summaries: [summary],
            suggestions: [determinism],
            unfocusedSuggestions: [],
            seedManifest: SeedManifest(seeds: [.init(file: "Source.swift", line: 3, symbol: "backoffDelay")])
        )

        #expect(advice.unseeded.isEmpty)
        #expect(advice.seeded.map(\.displayName) == ["backoffDelay(_:)"])
        #expect(advice.seeded.first?.runnableScaffold?.contains("backoffDelay_reference") == true)
    }

    /// The call site is where the lists are chosen, and swapping either argument there changes
    /// no rendered line on any fixture or on SwiftAssist — so only a test that reads the
    /// advisory can see it.
    @Test("the discover path hands the unseeded half pipeline.suggestions and the seeded half visible")
    func discoverPathHandsEachHalfItsOwnList() {
        let pipeline = SwiftInferCommand.Discover.PipelineResult(
            suggestions: [Self.suggestion(template: "monotonicity", function: "backoffDelay(_:)")],
            packageRoot: nil,
            summaries: [
                Self.summary(name: "backoffDelay", doc: Self.backoffDoc),
                Self.summary(name: "clampedValue", doc: Self.clampDoc)
            ],
            docstringAdvice: true
        )

        let advice = SwiftInferCommand.Discover.docstringAdviceIfEnabled(
            pipeline: pipeline,
            visible: [Self.suggestion(template: "determinism", function: "clampedValue(_:)")],
            seedManifest: SeedManifest(seeds: [.init(file: "Source.swift", line: 3, symbol: "clampedValue")])
        )

        #expect(advice.unseeded.map(\.displayName) == ["backoffDelay(_:)"])
        #expect(advice.unseeded.first?.advisory == .fallbackContract(
            .init(docComment: Self.backoffDoc, redHerrings: ["monotonicity"])
        ))
        #expect(advice.seeded.map(\.displayName) == ["clampedValue(_:)"])
        #expect(advice.seeded.first?.runnableScaffold?.contains("clampedValue_reference") == true)
    }

    @Test("with no manifest everything is seeded, decided on the focused list")
    func noManifestPutsEverythingInTheSeededHalf() {
        let summary = Self.summary(name: "backoffDelay", doc: Self.backoffDoc)

        let advice = SwiftInferCommand.Discover.docstringAdvice(
            summaries: [summary],
            suggestions: [],
            unfocusedSuggestions: [Self.suggestion(template: "monotonicity", function: "backoffDelay(_:)")],
            seedManifest: nil
        )

        #expect(advice.unseeded.isEmpty)
        #expect(advice.seeded.first?.advisory == .fallbackContract(
            .init(docComment: Self.backoffDoc, redHerrings: [])
        ))
    }

    /// A `carrier` seed joins on a TYPE name (`SeedFocus.filter`), so it vouches for no function:
    /// a carrier-only manifest focuses, and every documented function lands outside it.
    @Test("a carrier-only manifest focuses, and names no function")
    func carrierOnlyManifestNamesNoFunction() {
        let summary = Self.summary(name: "backoffDelay", doc: Self.backoffDoc)

        let advice = SwiftInferCommand.Discover.docstringAdvice(
            summaries: [summary],
            suggestions: [],
            unfocusedSuggestions: [],
            seedManifest: SeedManifest(seeds: [
                .init(file: "Source.swift", line: 3, symbol: "backoffDelay", kind: .carrier)
            ])
        )

        #expect(advice.seeded.isEmpty)
        #expect(advice.unseeded.map(\.displayName) == ["backoffDelay(_:)"])
    }

    // MARK: - Builders

    private static func summary(name: String, doc: String) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "value", typeText: "Int", isInout: false)],
            returnTypeText: "Int",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: file, line: 3, column: 5),
            containingTypeName: nil,
            bodySignals: .empty,
            docComment: doc
        )
    }

    private static func suggestion(template: String, function: String) -> Suggestion {
        Suggestion(
            templateName: template,
            evidence: [
                Evidence(
                    displayName: function,
                    signature: "(Int) -> Int",
                    location: SourceLocation(file: file, line: 3, column: 5)
                )
            ],
            score: Score(signals: [Signal(kind: .typeSymmetrySignature, weight: 30, detail: "")]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "\(template)|\(function)")
        )
    }
}
