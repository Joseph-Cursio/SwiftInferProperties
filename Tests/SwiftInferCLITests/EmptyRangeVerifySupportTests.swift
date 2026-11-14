@testable import SwiftInferCLI
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// `empty-range` verify support (#701): `f(from: v, to: v).isEmpty`, measured rather than only
/// written by `accept`.
///
/// `accept` has written the law complete since commit 18f8eb2e, and it killed
/// SwiftLintRuleStudioCore's `&&` → `||` mutant in `rulesAdded(from:to:)`. Verify declined it
/// `unsupported-template` only because none of the five enumerations named it. The index already
/// carried the labels, the owner and the bound type, so no column was added.
///
/// The precedent this suite follows is `DifferentialVerifySupportTests`. The end-to-end run in
/// both directions, a correct subject passing and an inclusive-range mutant failing, needs a real
/// build and lives in `VerifyPipelineEmptyRangeTests` (batch 3).
@Suite("empty-range — verify support")
struct EmptyRangeVerifySupportTests {

    private static let subjectSource = """
        public enum Deprecations {
            public static func rulesAdded(from fromVersion: String, to toVersion: String) -> [String] { [] }
        }
        public func versions(from start: Int, to end: Int) -> [Int] { [] }
        """

    /// The index entry the real pipeline builds: scan, the real template, the real projection.
    /// Built this way rather than by hand so the test proves the projection already persists
    /// what the resolver needs, which is the claim that let #701 add no column.
    private static func indexedEntry(_ name: String) throws -> SemanticIndexEntry {
        let corpus = FunctionScanner.scanCorpus(source: subjectSource, file: "Ranges.swift")
        let summary = try #require(corpus.summaries.first { $0.name == name })
        let suggestion = try #require(EmptyRangeTemplate.suggest(for: summary))
        return SwiftInferCommand.Index.buildEntry(
            from: suggestion,
            decisionsByHash: [:],
            now: "2026-11-13T00:00:00Z"
        )
    }

    private static func inputs(calls: [String], carrier: String = "Int") -> StrategistDispatchEmitter.Inputs {
        StrategistDispatchEmitter.Inputs(
            carrier: carrier,
            typeShape: nil,
            template: "empty-range",
            functionCalls: calls,
            seedHex: .init(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
            trialBudget: .small
        )
    }

    private static let intRecipe = StrategistDispatchEmitter.GeneratorRecipe(
        expression: "Gen<Int>.int()", carrierTypeName: "Int", imports: []
    )

    // MARK: - Projection and call resolution

    @Test("the projection persists the labels, the bound type and no second function")
    func projectionCarriesWhatTheResolverNeeds() throws {
        let entry = try Self.indexedEntry("rulesAdded")
        #expect(entry.templateName == "empty-range")
        #expect(entry.primaryFunctionName == "rulesAdded(from:to:)")
        #expect(entry.carrierTypeName == "String", "the generator draws the bound type, not the owner")
        #expect(entry.isInstanceMethod == false)
        #expect(entry.secondaryFunctionName == nil, "a single-function law has no second half")
    }

    /// The labels are what make the call compile: `Deprecations.rulesAdded(value, value)` does
    /// not, so the resolver must write the trampoline that carries `from:` and `to:`.
    @Test("a static subject resolves to the label-carrying trampoline")
    func staticSubjectResolvesWithLabels() throws {
        let calls = try SwiftInferCommand.Verify.resolveFunctionCalls(for: try Self.indexedEntry("rulesAdded"))
        #expect(calls.expressions == ["{ Deprecations.rulesAdded(from: $0, to: $1) }"])
        #expect(calls.rendererForwardName == "Deprecations.rulesAdded")
    }

    @Test("a free subject resolves without an owner")
    func freeSubjectResolvesWithoutOwner() throws {
        let calls = try SwiftInferCommand.Verify.resolveFunctionCalls(for: try Self.indexedEntry("versions"))
        #expect(calls.expressions == ["{ versions(from: $0, to: $1) }"])
    }

    /// Through the real first gate, the resolver, the strategist and the composer at once: the
    /// path that `role-postcondition` and `predicate` each found broken only end to end.
    @Test("the whole dispatch builds a stub that applies one value as both ends")
    func dispatchBuildsTheStub() throws {
        let bundle = try SwiftInferCommand.Verify.buildStubBundle(
            entry: try Self.indexedEntry("rulesAdded"),
            budget: .small
        )
        #expect(bundle.source.contains("{ Deprecations.rulesAdded(from: $0, to: $1) }(value, value)"))
        #expect(bundle.source.contains("if !result.isEmpty {"))
        #expect(bundle.source.contains("Generator<String, some SendableSequenceType>"))
        #expect(bundle.rendererContext.templateName == "empty-range")
    }

    // MARK: - Composition

    /// Fails by ASSERTION. Totality's `VERIFY_TRIAL_INPUT` / `VERIFY_TRIAL_CARRIER` would make
    /// the parser read a trap in the subject as a refutation of a law that is not totality.
    @Test("the pass prints the assertion contract and none of totality's trap markers")
    func passPrintsTheAssertionContract() {
        let source = StrategistDispatchEmitter.composeEmptyRangePass(
            inputs: Self.inputs(calls: ["{ versions(from: $0, to: $1) }"]), recipe: Self.intRecipe
        )
        for marker in [
            "VERIFY_DEFAULT_RESULT: FAIL", "VERIFY_DEFAULT_TRIAL:", "VERIFY_DEFAULT_INPUT: \\(value)",
            "VERIFY_DEFAULT_FORWARD: \\(result)", "VERIFY_DEFAULT_INVERSE: <empty>",
            "VERIFY_DEFAULT_RESULT: PASS", "VERIFY_DEFAULT_TRIALS:", "exit(1)",
        ] {
            #expect(source.contains(marker), "missing \(marker)")
        }
        #expect(!source.contains("VERIFY_TRIAL_INPUT"))
        #expect(!source.contains("VERIFY_TRIAL_CARRIER"))
    }

    /// The edge pass re-runs the SAME composer on a boundary recipe; a body the relabel did not
    /// understand would fall back to the zero-trial sentinel and claim an edge pass that never ran.
    @Test("the emitted stub carries a real boundary pass of the same law")
    func edgePassRunsTheSameLaw() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(calls: ["{ versions(from: $0, to: $1) }"])
        )
        #expect(source.contains("VERIFY_EDGE_INVERSE: <empty>"))
        #expect(!source.contains("VERIFY_EDGE_TRIALS: 0"), "fell back to the zero-trial sentinel")
    }

    // MARK: - The gates

    @Test("the template is in the verifiable vocabulary, the dispatch gate and the algebraic route")
    func gatesAgree() {
        #expect(TemplateName.verifiable.contains(.emptyRange))
        #expect(SwiftInferCommand.Verify.supportedTemplates.contains("empty-range"))
        #expect(TemplateName.strategistAlgebraicLaws.contains(.emptyRange))
        #expect(DeliberateVerifyDecline.reason(forTemplate: "empty-range") == nil)
    }

    @Test("it has its own verdict phrasing rather than the round-trip fallback")
    func hasOwnRenderShape() throws {
        let shape = try #require(RenderShape.byTemplateName["empty-range"])
        let context = VerifyResultRenderer.Context(
            templateName: "empty-range",
            forwardName: "Deprecations.rulesAdded",
            inverseName: "Deprecations.rulesAdded",
            carrierType: "String"
        )
        let subject = shape.subjectLine(context: context)
        #expect(subject.contains("empty-range"))
        #expect(!subject.contains("round-trip"))
    }

    /// A refutation may be a naming finding rather than a defect: the law assumes `to:` is
    /// exclusive, and an author who meant it inclusive fails it by design.
    @Test("a refutation says an inclusive `to:` fails by design")
    func refutationNamesTheNamingReading() {
        let rendered = VerifyResultRenderer.render(
            .defaultFails(DefaultFailDetail(trial: 0, input: "3", forwardResult: "[3]", inverseResult: "<empty>")),
            context: .init(
                templateName: "empty-range",
                forwardName: "versions",
                inverseName: "versions",
                carrierType: "Int"
            )
        )
        #expect(rendered.contains("versions(from: input, to: input) = [3]"), "got:\n\(rendered)")
        #expect(rendered.contains("through:"), "got:\n\(rendered)")
        #expect(rendered.contains("not necessarily a defect"), "got:\n\(rendered)")
        #expect(!rendered.contains("round-trip"))
    }
}
