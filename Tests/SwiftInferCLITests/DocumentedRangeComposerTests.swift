@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `documented-range`'s emitted pass, its gates and its phrasing (#701). Split from
/// `DocumentedRangeVerifySupportTests`, which covers the index and the call, for the type-body cap.
@Suite("documented-range — composition and phrasing")
struct DocumentedRangeComposerTests {

    private static func inputs(
        calls: [String],
        range: DocumentedRange?,
        carrier: String = "Int",
        parameterCount: Int = 1,
        parameterTypeNames: [String] = [],
        receiverTypeName: String? = nil
    ) -> StrategistDispatchEmitter.Inputs {
        StrategistDispatchEmitter.Inputs(
            carrier: carrier,
            typeShape: nil,
            template: "documented-range",
            functionCalls: calls,
            seedHex: .init(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
            trialBudget: .small,
            parameterCount: parameterCount,
            parameterTypeNames: parameterTypeNames,
            receiverTypeName: receiverTypeName,
            documentedRange: range
        )
    }

    private static let intRecipe = StrategistDispatchEmitter.GeneratorRecipe(
        expression: "Gen<Int>.int()", carrierTypeName: "Int", imports: []
    )

    private static func compose(_ inputs: StrategistDispatchEmitter.Inputs) throws -> String {
        try StrategistDispatchEmitter.defaultPassSection(inputs: inputs, recipe: Self.intRecipe)
    }

    // MARK: - The bounds

    /// Integer-only bounds would infer `ClosedRange<Int>` without the annotation, and
    /// `contains(Double(result))` would not compile.
    @Test(
        "the bounds are spliced verbatim inside `as ClosedRange<Double>`, spaced so a negative upper bound lexes",
        arguments: [
            (DocumentedRange(lower: "0.0", upper: "1.0"), "(0.0 ... 1.0 as ClosedRange<Double>)"),
            (DocumentedRange(lower: "0", upper: "100"), "(0 ... 100 as ClosedRange<Double>)"),
            (DocumentedRange(lower: "-1", upper: "1"), "(-1 ... 1 as ClosedRange<Double>)"),
            (DocumentedRange(lower: "-10", upper: "-1"), "(-10 ... -1 as ClosedRange<Double>)"),
        ]
    )
    func boundsAreSplicedVerbatim(range: DocumentedRange, expected: String) throws {
        let source = try Self.compose(Self.inputs(calls: ["{ scaled($0) }"], range: range))
        #expect(source.contains("let documentedRange = \(expected)"), "got:\n\(source)")
        #expect(source.contains("if !documentedRange.contains(Double(result)) {"))
        #expect(source.contains("VERIFY_DEFAULT_INVERSE: <within \(range.lower)...\(range.upper)>"))
    }

    /// Widened as-is, a correct `Float` clamp to 0.3 returns 0.30000001192… and lies above the
    /// `Double` 0.3, so the bounds are rounded through `Float` the way the result is.
    @Test("a Float result is checked against bounds rounded through Float; a Double result is not")
    func floatBoundsRoundThroughFloat() throws {
        let float = try Self.compose(Self.inputs(
            calls: ["{ gain($0) }"],
            range: DocumentedRange(lower: "0.0", upper: "0.3", resultTypeName: "Float")
        ))
        #expect(float.contains(
            "let documentedRange = (Double(Float(0.0)) ... Double(Float(0.3)) as ClosedRange<Double>)"
        ), "got:\n\(float)")
        // The verdict still names the range as the doc comment wrote it.
        #expect(float.contains("VERIFY_DEFAULT_INVERSE: <within 0.0...0.3>"))
        let double = try Self.compose(Self.inputs(
            calls: ["{ gain($0) }"],
            range: DocumentedRange(lower: "0.0", upper: "0.3", resultTypeName: "Double")
        ))
        #expect(double.contains("let documentedRange = (0.0 ... 0.3 as ClosedRange<Double>)"))
    }

    // MARK: - The operands

    @Test("a free unary function draws one value from the carrier's recipe")
    func freeUnaryUsesTheCarrierRecipe() throws {
        let source = try Self.compose(
            Self.inputs(calls: ["{ scaled($0) }"], range: DocumentedRange(lower: "0", upper: "1"))
        )
        #expect(source.contains("let defaultGenerator: Generator<Int, some SendableSequenceType>"))
        #expect(source.contains("let result = { scaled($0) }(candidate)"))
        #expect(source.contains("VERIFY_DEFAULT_INPUT: \\(candidate)"))
    }

    /// The receiver is an implicit first argument of `{ $0.f($1) }`, so a receiver and a
    /// parameter each need a generator, and the input prints as one tuple.
    @Test("an instance method draws the receiver and each parameter, through totality's operands")
    func instanceMethodDrawsEveryOperand() throws {
        let source = try Self.compose(
            Self.inputs(
                calls: ["{ $0.ratio(of: $1) }"],
                range: DocumentedRange(lower: "0.0", upper: "1.0"),
                parameterTypeNames: ["Int"],
                receiverTypeName: "Bool"
            )
        )
        #expect(source.contains("let generator0: Generator<Bool, some SendableSequenceType>"))
        #expect(source.contains("let generator1: Generator<Int, some SendableSequenceType>"))
        #expect(source.contains("let result = { $0.ratio(of: $1) }(candidate0, candidate1)"))
        #expect(source.contains("VERIFY_DEFAULT_INPUT: \\((candidate0, candidate1))"))
    }

    // MARK: - The contract

    /// Fails by ASSERTION. Totality's `VERIFY_TRIAL_INPUT` / `VERIFY_TRIAL_CARRIER` would make
    /// the parser read a trap in the subject as a refutation of a law that is not totality.
    @Test("the pass prints the assertion contract and none of totality's trap markers")
    func passPrintsTheAssertionContract() throws {
        let source = try Self.compose(
            Self.inputs(calls: ["{ scaled($0) }"], range: DocumentedRange(lower: "0", upper: "1"))
        )
        for marker in [
            "VERIFY_DEFAULT_RESULT: FAIL", "VERIFY_DEFAULT_TRIAL:", "VERIFY_DEFAULT_FORWARD: \\(result)",
            "VERIFY_DEFAULT_RESULT: PASS", "VERIFY_DEFAULT_TRIALS:", "exit(1)",
        ] {
            #expect(source.contains(marker), "missing \(marker)")
        }
        #expect(!source.contains("VERIFY_TRIAL_"))
    }

    @Test("an Inputs without the range refuses as stale rather than invent bounds")
    func missingRangeRefusesAsStale() {
        #expect {
            _ = try Self.compose(Self.inputs(calls: ["{ scaled($0) }"], range: nil))
        } throws: { error in
            guard case let VerifyError.staleIndexEntry(template, _, reason) = error else { return false }
            return template == "documented-range" && reason.contains("documentedRange")
        }
    }

    /// The edge pass re-runs the SAME composer on a boundary recipe; a body the relabel did not
    /// understand would fall back to the zero-trial sentinel and claim an edge pass that never ran.
    @Test("the emitted stub carries a real boundary pass of the same law")
    func edgePassRunsTheSameLaw() throws {
        let source = try StrategistDispatchEmitter.emit(
            Self.inputs(calls: ["{ scaled($0) }"], range: DocumentedRange(lower: "0", upper: "1"))
        )
        #expect(source.contains("VERIFY_EDGE_INVERSE: <within 0...1>"))
        #expect(!source.contains("VERIFY_EDGE_TRIALS: 0"), "fell back to the zero-trial sentinel")
    }

    /// On the per-parameter path the carrier's recipe is never read, so swapping in the
    /// carrier's edge recipe re-drew the ordinary domain under a "boundary values" banner.
    @Test("an n-ary subject's boundary pass swaps each parameter's own edge recipe in")
    func naryEdgePassSwapsEachParameter() throws {
        let source = try StrategistDispatchEmitter.emit(Self.inputs(
            calls: ["{ $0.ratio(of: $1) }"],
            range: DocumentedRange(lower: "0.0", upper: "1.0"),
            parameterTypeNames: ["Int"],
            receiverTypeName: "Bool"
        ))
        let edge = try #require(source.range(of: "// --- Pass 2: curated boundary values"))
        let pass1 = String(source[..<edge.lowerBound])
        let pass2 = String(source[edge.lowerBound...])
        #expect(!pass1.contains("Gen<Int?>.element(of:"), "got:\n\(source)")
        #expect(pass2.contains("Gen<Int?>.element(of:"), "got:\n\(source)")
        // `Bool` has no curated boundary set, so the receiver stays on its ordinary generator.
        #expect(pass2.contains("let generator0: Generator<Bool, some SendableSequenceType>"))
        #expect(pass2.contains("VERIFY_EDGE_INVERSE: <within 0.0...1.0>"))
        #expect(!source.contains("VERIFY_EDGE_TRIALS: 0"))
    }

    @Test("an n-ary subject with no parameter on a boundary set says no boundary pass ran")
    func naryWithoutEdgeSetsEmitsTheSentinel() throws {
        let source = try StrategistDispatchEmitter.emit(Self.inputs(
            calls: ["{ $0.ratio(of: $1) }"],
            range: DocumentedRange(lower: "0.0", upper: "1.0"),
            carrier: "Bool",
            parameterTypeNames: ["Bool"],
            receiverTypeName: "Bool"
        ))
        #expect(source.contains("VERIFY_EDGE_TRIALS: 0"), "got:\n\(source)")
        #expect(!source.contains("VERIFY_EDGE_INVERSE"))
    }

    // MARK: - The gates

    @Test("verifiable and dispatchable, beside predicate rather than in the algebraic route")
    func gatesAgree() {
        #expect(TemplateName.verifiable.contains(.documentedRange))
        #expect(SwiftInferCommand.Verify.supportedTemplates.contains("documented-range"))
        #expect(!TemplateName.strategistAlgebraicLaws.contains(.documentedRange))
        #expect(DeliberateVerifyDecline.reason(forTemplate: "documented-range") == nil)
    }

    // MARK: - The phrasing

    @Test("it has its own verdict phrasing rather than the round-trip fallback")
    func hasOwnRenderShape() throws {
        let shape = try #require(RenderShape.byTemplateName["documented-range"])
        let subject = shape.subjectLine(
            context: .init(
                templateName: "documented-range",
                forwardName: "AnalysisProgress.progress",
                inverseName: "0.0...1.0",
                carrierType: "AnalysisProgress"
            )
        )
        #expect(subject == "documented-range on AnalysisProgress.progress over AnalysisProgress")
    }

    /// The bounds ride the renderer's inverse name, so the verdict names the contract it checked,
    /// and the caveat says either side may be the one to change.
    @Test("a refutation prints the value, the stated range and the disagreement reading")
    func refutationNamesTheRange() {
        let rendered = VerifyResultRenderer.render(
            .defaultFails(
                DefaultFailDetail(trial: 0, input: "p", forwardResult: "4.3", inverseResult: "<within 0.0...1.0>")
            ),
            context: .init(
                templateName: "documented-range",
                forwardName: "AnalysisProgress.progress",
                inverseName: "0.0...1.0",
                carrierType: "AnalysisProgress"
            )
        )
        #expect(rendered.contains("AnalysisProgress.progress(input) = 4.3"), "got:\n\(rendered)")
        #expect(rendered.contains("within 0.0...1.0, as its doc comment states"), "got:\n\(rendered)")
        #expect(rendered.contains("correct the comment"), "got:\n\(rendered)")
        #expect(!rendered.contains("round-trip"))
    }
}
