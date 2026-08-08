import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `differential-equivalence` verify support, added 2026-08-08.
///
/// The template was one of three `Strong`-tier entries declining
/// `unsupported-template` in the whole-corpus survey — the only tier where
/// nothing ran at all. Verify could not attempt the suggestions discovery is
/// most confident in.
///
/// Nothing about the law was hard: one generated value, two calls, compare —
/// structurally simpler than `round-trip`, which nests them. What blocked it was
/// that `IndexCommand+Projection` persisted `secondaryFunctionName` for
/// `round-trip` only, so `DifferentialTemplate`'s
/// `evidence = [reference, variant]` was computed and discarded. Verify declined
/// for want of data discover already had.
@Suite("differential-equivalence — verify support")
struct DifferentialVerifySupportTests {

    private static let seed = StrategistDispatchEmitter.SeedHex(
        stateA: 0x01, stateB: 0x02, stateC: 0x03, stateD: 0x04
    )

    private static func entry(
        primary: String,
        secondary: String?,
        carrier: String = "Int"
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0xDIFF0001",
            templateName: "differential-equivalence",
            typeName: carrier,
            score: 80,
            tier: "Strong",
            primaryFunctionName: primary,
            location: "/Module.swift:1",
            firstSeenAt: "2026-08-08T00:00:00Z",
            lastSeenAt: "2026-08-08T00:00:00Z",
            secondaryFunctionName: secondary
        )
    }

    private static func twoHalfSuggestion(templateName: String) -> Suggestion {
        func evidence(_ name: String) -> Evidence {
            Evidence(
                displayName: name,
                signature: "([Int]) -> [Int]",
                location: SourceLocation(file: "/Sorting.swift", line: 1, column: 1)
            )
        }
        return Suggestion(
            templateName: templateName,
            evidence: [evidence("referenceSort(_:)"), evidence("fastSort(_:)")],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 35, detail: "pair")]),
            generator: GeneratorMetadata(source: .notYetComputed, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: ["why"], whyMightBeWrong: ["caveat"]),
            identity: SuggestionIdentity(canonicalInput: "\(templateName)|pair"),
            carrier: "Sorting"
        )
    }

    // MARK: - Projection

    /// The change that actually unblocks real entries. `DifferentialTemplate`
    /// emits `evidence = [reference, variant]`, the same two-element shape
    /// round-trip uses — but the projection persisted the second half for
    /// round-trip alone, so the variant name was computed and thrown away one
    /// function before the index.
    @Test("the differential pair survives projection into the index")
    func differentialPairIsPersisted() {
        let entry = SwiftInferCommand.Index.buildEntry(
            from: Self.twoHalfSuggestion(templateName: "differential-equivalence"),
            decisionsByHash: [:],
            now: "2026-08-08T00:00:00Z"
        )
        #expect(entry.primaryFunctionName == "referenceSort(_:)")
        #expect(
            entry.secondaryFunctionName == "fastSort(_:)",
            "without this the verify resolver has nothing to compare the reference against"
        )
    }

    /// The set is named rather than "any template with two evidence entries",
    /// because several single-function templates emit a second entry for the
    /// carrier or a corroborating test. Persisting that as a *function* name
    /// would hand the resolver a call expression that does not exist.
    @Test("a single-function template's second evidence entry is NOT persisted as a function")
    func singleFunctionTemplateKeepsNilSecondary() {
        let entry = SwiftInferCommand.Index.buildEntry(
            from: Self.twoHalfSuggestion(templateName: "idempotence"),
            decisionsByHash: [:],
            now: "2026-08-08T00:00:00Z"
        )
        #expect(
            entry.secondaryFunctionName == nil,
            "idempotence names one function; a second evidence entry is corroboration, not a call"
        )
    }

    // MARK: - Call resolution

    @Test("the pair resolves from the entry, with no curated table")
    func resolvesPairFromEntry() throws {
        let calls = try SwiftInferCommand.Verify.resolveDifferentialCalls(
            entry: Self.entry(primary: "referenceSort(_:)", secondary: "fastSort(_:)"),
            typeQualifier: "Sorting"
        )
        #expect(calls.expressions.count == 2)
        #expect(calls.expressions[0].contains("referenceSort"))
        #expect(calls.expressions[1].contains("fastSort"))
        #expect(calls.rendererForwardName.contains("referenceSort"))
        #expect(calls.rendererInverseName.contains("fastSort"))
    }

    /// The failure has to name the right remedy. A missing second half is a
    /// STALE ENTRY — this template has no curated list to be absent from — so
    /// `.unsupportedPair` would send the reader to expand a table that does not
    /// exist for it.
    @Test("an entry with no second half reports a stale entry, not a missing curated pair")
    func missingSecondaryIsAStaleEntry() {
        #expect(throws: VerifyError.self) {
            try SwiftInferCommand.Verify.resolveDifferentialCalls(
                entry: Self.entry(primary: "referenceSort(_:)", secondary: nil),
                typeQualifier: "Sorting"
            )
        }
        do {
            _ = try SwiftInferCommand.Verify.resolveDifferentialCalls(
                entry: Self.entry(primary: "referenceSort(_:)", secondary: nil),
                typeQualifier: "Sorting"
            )
            Issue.record("expected a throw")
        } catch let error as VerifyError {
            let text = error.description
            #expect(text.contains("swift-infer index"), "the message must name the remedy: \(text)")
            #expect(
                !text.contains("curated round-trip pair list"),
                "must not send the reader to a curated list this template does not have: \(text)"
            )
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    // MARK: - Composition

    /// The law compares two calls on the SAME input. Round-trip nests
    /// (`inverse(forward(x))`), and a differential stub that nested would be
    /// stating a law nobody proposed — and would usually not compile, since the
    /// reference's return type need not be its own input type.
    @Test("the emitted pass applies both calls to the same value, not nested")
    func emittedPassIsNotNested() throws {
        let inputs = StrategistDispatchEmitter.Inputs(
            carrier: "Int",
            typeShape: nil,
            template: "differential-equivalence",
            functionCalls: ["Sorting.referenceSort", "Sorting.fastSort"],
            seedHex: Self.seed,
            trialBudget: .small
        )
        let recipe = StrategistDispatchEmitter.GeneratorRecipe(
            expression: "Gen<Int>.int()",
            carrierTypeName: "Int",
            imports: ["PropertyBased"]
        )
        let source = try StrategistDispatchEmitter.composeDifferentialPass(
            inputs: inputs, recipe: recipe
        )
        #expect(source.contains("Sorting.referenceSort(value)"))
        #expect(source.contains("Sorting.fastSort(value)"))
        #expect(
            !source.contains("Sorting.fastSort(Sorting.referenceSort("),
            "the differential law must not nest its calls the way round-trip does"
        )
    }

    /// Both results are printed because a differential refutation names two
    /// functions and is silent about which is wrong. Printing only the mismatch
    /// would leave the reader unable to tell the oracle from the suspect.
    @Test("the counterexample carries both results")
    func counterexampleCarriesBothResults() throws {
        let inputs = StrategistDispatchEmitter.Inputs(
            carrier: "Int",
            typeShape: nil,
            template: "differential-equivalence",
            functionCalls: ["ref", "variant"],
            seedHex: Self.seed,
            trialBudget: .small
        )
        let recipe = StrategistDispatchEmitter.GeneratorRecipe(
            expression: "Gen<Int>.int()", carrierTypeName: "Int", imports: []
        )
        let source = try StrategistDispatchEmitter.composeDifferentialPass(
            inputs: inputs, recipe: recipe
        )
        #expect(source.contains("VERIFY_DEFAULT_FORWARD: \\(referenceResult)"))
        #expect(source.contains("VERIFY_DEFAULT_INVERSE: \\(variantResult)"))
    }

    @Test("a pass that is handed the wrong number of calls is rejected before the build")
    func wrongCallCountRejected() {
        let inputs = StrategistDispatchEmitter.Inputs(
            carrier: "Int",
            typeShape: nil,
            template: "differential-equivalence",
            functionCalls: ["onlyOne"],
            seedHex: Self.seed,
            trialBudget: .small
        )
        let recipe = StrategistDispatchEmitter.GeneratorRecipe(
            expression: "Gen<Int>.int()", carrierTypeName: "Int", imports: []
        )
        #expect(throws: VerifyError.self) {
            _ = try StrategistDispatchEmitter.composeDifferentialPass(inputs: inputs, recipe: recipe)
        }
    }

    // MARK: - The gates

    /// Five separate enumerations of the template vocabulary have to agree, and
    /// the repo has already paid for missing one: shipping the `predicate`
    /// composer without its `resolveFunctionCalls` arm was a no-op that declined
    /// all 49 indexed entries. This asserts the two that are plain membership;
    /// the composer and resolver are covered above, and the renderer by
    /// `VerifiableTemplateReachTests`.
    @Test("the template is in the verifiable vocabulary and the dispatch gate")
    func gatesAgree() {
        #expect(TemplateName.verifiable.contains(.differentialEquivalence))
        #expect(SwiftInferCommand.Verify.supportedTemplates.contains("differential-equivalence"))
    }

    /// It must NOT render as a round trip. `shape(forTemplate:)` falls back to
    /// `.roundTrip` on a miss, which has already shipped wrong output for five
    /// templates — a passing run printing an inverse the law does not have.
    @Test("it has its own verdict phrasing rather than the round-trip fallback")
    func hasOwnRenderShape() {
        let shape = RenderShape.byTemplateName["differential-equivalence"]
        #expect(shape != nil)
        let context = VerifyResultRenderer.Context(
            templateName: "differential-equivalence",
            forwardName: "referenceSort",
            inverseName: "fastSort",
            carrierType: "Int"
        )
        let subject = shape?.subjectLine(context: context) ?? ""
        #expect(subject.contains("differential equivalence"))
        #expect(!subject.contains("round-trip"))
        #expect(shape?.inverseExpression(context: context) == "fastSort(input)")
    }
}
