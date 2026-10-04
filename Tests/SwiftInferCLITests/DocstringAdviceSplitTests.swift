import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
import Testing

/// `Discover.docstringAdvice(summaries:suggestions:unfocusedSuggestions:seedManifest:)` takes TWO
/// suggestion lists, and each half of the advice must be decided on its own one.
///
/// - An **unseeded** function is decided on the UNFOCUSED list — what a run without seeds sees.
///   The focus keeps a role-entailed law for a function it does not name but drops a law lifted
///   from a test whose subject the scan declared, so on the focused list the advisor can fall
///   from arm 2 (lifted → reference definition) to arm 5 (served → no advisory) and the entry
///   vanishes: the very silent drop the compact block exists to prevent.
/// - A **seeded** function is decided on the FOCUSED list, because that is where the synthesized
///   determinism law lives — the source its runnable scaffold is drawn from.
///
/// Neither half may be "simplified" onto the other's list; one test pins each direction.
@Suite("Discover — each half of the docstring advice is decided on its own list")
struct DocstringAdviceSplitTests {

    private static let file = "/fixture/Source.swift"

    @Test("an unseeded function's advice is decided on the unfocused suggestions")
    func unseededAdviceIsDecidedOnUnfocusedSuggestions() {
        let doc = "Returns the value clamped to the range, never negative."
        let summary = Self.summary(name: "clampedValue", doc: doc)
        let owed = Self.suggestion(template: "guard-domain", function: "clampedValue(_:)")
        let lifted = Self.lifted(Self.suggestion(template: "idempotence", function: "clampedValue(_:)"))

        // The premise: on what the focus keeps, the advisor says nothing at all.
        #expect(DocstringAdvisor.advisory(forFunctionWith: doc, suggestions: [owed]) == nil)

        let advice = SwiftInferCommand.Discover.docstringAdvice(
            summaries: [summary],
            suggestions: [owed],
            unfocusedSuggestions: [owed, lifted],
            seedManifest: SeedManifest(seeds: [.init(file: "Source.swift", line: 1, symbol: "elsewhere")])
        )

        #expect(advice.seeded.isEmpty)
        #expect(advice.unseeded.map(\.displayName) == ["clampedValue(_:)"])
        #expect(advice.unseeded.first?.advisory == .referenceDefinition(
            .init(docComment: doc, template: "idempotence", fromLiftedTest: true)
        ))
        #expect(advice.unseeded.first?.runnableScaffold == nil)
    }

    @Test("an unseeded function's red herrings come from the unfocused suggestions")
    func unseededRedHerringsComeFromUnfocusedSuggestions() {
        let doc = "Delay is capped at the ceiling and never negative."
        let summary = Self.summary(name: "backoffDelay", doc: doc)
        let guess = Self.suggestion(template: "monotonicity", function: "backoffDelay(_:)")

        let advice = SwiftInferCommand.Discover.docstringAdvice(
            summaries: [summary],
            suggestions: [],
            unfocusedSuggestions: [guess],
            seedManifest: SeedManifest(seeds: [.init(file: "Source.swift", line: 1, symbol: "elsewhere")])
        )

        #expect(advice.unseeded.first?.advisory == .fallbackContract(
            .init(docComment: doc, redHerrings: ["monotonicity"])
        ))
    }

    @Test("a seeded function keeps the scaffold the focused list's determinism law supplies")
    func seededAdviceIsDecidedOnFocusedSuggestions() {
        let summary = Self.summary(name: "backoffDelay", doc: "Delay is capped at the ceiling and never negative.")
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

    @Test("with no manifest everything is seeded, decided on the focused list")
    func noManifestPutsEverythingInTheSeededHalf() {
        let summary = Self.summary(name: "backoffDelay", doc: "Delay is capped at the ceiling and never negative.")

        let advice = SwiftInferCommand.Discover.docstringAdvice(
            summaries: [summary],
            suggestions: [],
            unfocusedSuggestions: [Self.suggestion(template: "monotonicity", function: "backoffDelay(_:)")],
            seedManifest: nil
        )

        #expect(advice.unseeded.isEmpty)
        #expect(advice.seeded.first?.advisory == .fallbackContract(
            .init(docComment: "Delay is capped at the ceiling and never negative.", redHerrings: [])
        ))
    }

    /// A `carrier` seed joins on a TYPE name (`SeedFocus.filter`), so it vouches for no function:
    /// a carrier-only manifest focuses, and every documented function lands outside it.
    @Test("a carrier-only manifest focuses, and names no function")
    func carrierOnlyManifestNamesNoFunction() {
        let summary = Self.summary(name: "backoffDelay", doc: "Delay is capped at the ceiling and never negative.")

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

    private static func lifted(_ suggestion: Suggestion) -> Suggestion {
        var lifted = suggestion
        lifted.liftedOrigin = LiftedOrigin(
            testMethodName: "testClamp",
            sourceLocation: SourceLocation(file: "SourceTests.swift", line: 10, column: 1)
        )
        return lifted
    }
}
