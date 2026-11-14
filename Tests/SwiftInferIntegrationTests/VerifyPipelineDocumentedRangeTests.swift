@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `documented-range` (#701) built and run against a planted subject, in both directions.
///
/// The unit suites inspect the emitted text. This one compiles it, because two claims only a build
/// can check: that `(0 ... 100 as ClosedRange<Double>)` type-checks against an `Int` result, and
/// that the receiver access `{ $0.fraction }` the resolver writes applies to a derived receiver.
/// The planted pair is the template's own witness in miniature, SwiftLintRuleStudioCore's
/// `AnalysisProgress.progress`: an unclamped ratio leaves `0.0 to 1.0`, and the clamped one stays.
///
/// The calls come from `resolveFunctionCalls` over an index entry carrying the bounds, and the
/// `Inputs` mirror `strategistBundle`'s. Spawns real `swift build`s; tagged `.subprocess` and
/// placed in batch 3 by the `VerifyPipeline` name.
@Suite("Verify pipeline — documented-range on a planted subject", .tags(.subprocess))
struct VerifyPipelineDocumentedRangeTests {

    private static let progressShape = IndexedTypeShape(
        name: "Progress",
        kind: .struct,
        inheritedTypes: ["Sendable"],
        hasUserGen: false,
        storedMembers: [
            IndexedTypeShape.StoredMember(name: "done", typeName: "Int"),
            IndexedTypeShape.StoredMember(name: "total", typeName: "Int"),
        ],
        hasUserInit: false
    )

    private static func entry(
        primary: String,
        typeName: String?,
        isInstanceMethod: Bool,
        parameterTypeNames: [String],
        range: DocumentedRange
    ) -> SemanticIndexEntry {
        // The planted instance subject is a property, and the free one takes a parameter, so
        // "property" is exactly "instance with no parameters" here.
        SemanticIndexEntry(
            identityHash: "0xDOCRANGE00001",
            templateName: "documented-range",
            score: 60,
            tier: "Likely",
            primaryFunctionName: primary,
            location: "/Planted.swift:1",
            firstSeenAt: "2026-11-13T00:00:00Z",
            lastSeenAt: "2026-11-13T00:00:00Z",
            typeName: typeName,
            documentedRange: range,
            carrierTypeName: parameterTypeNames.first ?? typeName,
            isInstanceMethod: isInstanceMethod,
            isNullary: parameterTypeNames.isEmpty,
            isComputedProperty: isInstanceMethod && parameterTypeNames.isEmpty,
            parameterTypeNames: parameterTypeNames
        )
    }

    /// Runs `entry` through the real resolver and `strategistBundle`'s field mapping.
    private static func run(
        _ entry: SemanticIndexEntry,
        typeShape: IndexedTypeShape?,
        preamble: String,
        allShapes: [String: IndexedTypeShape] = [:]
    ) throws -> VerifyOutcome {
        let calls = try SwiftInferCommand.Verify.resolveFunctionCalls(for: entry)
        return try VerifyPipelineIntegrationFixture.runStrategistPipeline(
            inputs: StrategistDispatchEmitter.Inputs(
                carrier: entry.carrierTypeName ?? "(none)",
                typeShape: typeShape,
                template: entry.templateName,
                functionCalls: calls.expressions,
                seedHex: VerifyPipelineIntegrationFixture.canonicalSeed,
                trialBudget: .small,
                preamble: preamble,
                allShapes: allShapes,
                isInstanceMethod: entry.isInstanceMethod,
                isNullary: entry.isNullary,
                isComputedProperty: entry.isComputedProperty,
                parameterCount: SwiftInferCommand.Verify.argumentLabels(from: entry.primaryFunctionName).count,
                parameterTypeNames: entry.parameterTypeNames,
                receiverTypeName: entry.isInstanceMethod ? entry.typeName : nil,
                documentedRange: entry.documentedRange
            )
        )
    }

    private static let fractionEntry = entry(
        primary: "fraction",
        typeName: "Progress",
        isInstanceMethod: true,
        parameterTypeNames: [],
        range: DocumentedRange(lower: "0.0", upper: "1.0")
    )

    private static func progress(fractionBody: String) -> String {
        """
        struct Progress: Sendable {
            let done: Int
            let total: Int
            /// Fraction of work done (0.0 to 1.0)
            var fraction: Double {
        \(fractionBody)
            }
        }
        """
    }

    /// Clamped into the range the comment states, at the ordinary draws and at `Int.min` /
    /// `Int.max` alike.
    @Test("a clamped ratio holds the law in both passes")
    func clampedRatioPasses() throws {
        let preamble = Self.progress(fractionBody: """
                guard total > 0 else { return 0 }
                return min(max(Double(done) / Double(total), 0), 1)
            """)
        let outcome = try Self.run(Self.fractionEntry, typeShape: Self.progressShape, preamble: preamble)
        guard case let .bothPass(defaultTrials, edgeTrials, _) = outcome else {
            Issue.record("expected .bothPass; got \(outcome)")
            return
        }
        #expect(defaultTrials > 0)
        #expect(edgeTrials > 0, "the boundary pass must run the law, not the zero-trial sentinel")
    }

    /// Nothing ties `done` to `total`, so a receiver that over-counts leaves the range — the
    /// template's witness. Refuted by assertion, with the out-of-range value as FORWARD.
    @Test("an unclamped ratio is refuted, with the out-of-range value shown")
    func unclampedRatioFails() throws {
        let preamble = Self.progress(fractionBody: """
                guard total > 0 else { return 0 }
                return Double(done) / Double(total)
            """)
        let outcome = try Self.run(Self.fractionEntry, typeShape: Self.progressShape, preamble: preamble)
        guard case let .defaultFails(detail) = outcome else {
            Issue.record("expected .defaultFails; got \(outcome)")
            return
        }
        let value = try #require(Double(detail.forwardResult), "forward was \(detail.forwardResult)")
        #expect(!(0.0 ... 1.0).contains(value))
        #expect(detail.inverseResult == "<within 0.0...1.0>")
    }

    /// Integer bounds against an `Int` result: compiles only because the bounds are annotated
    /// `ClosedRange<Double>` and the result converted, never inferred as `ClosedRange<Int>`.
    @Test("a free function with integer bounds and an Int result builds and holds the law")
    func integerBoundsBuildAndPass() throws {
        let entry = Self.entry(
            primary: "percent(of:)",
            typeName: nil,
            isInstanceMethod: false,
            parameterTypeNames: ["Int"],
            range: DocumentedRange(lower: "0", upper: "100")
        )
        let outcome = try Self.run(entry, typeShape: nil, preamble: """
            /// Between 0 and 100
            func percent(of x: Int) -> Int { Int(x.magnitude % 101) }
            """)
        guard case .bothPass = outcome else {
            Issue.record("expected .bothPass; got \(outcome)")
            return
        }
    }

    /// Two claims only a build can check. An instance method with a parameter takes the
    /// per-parameter operand path, whose boundary pass swaps each parameter's own edge recipe in
    /// (`Int.min`, `Int.max`, `0` …), so that pass must compile and run. And a `Float` clamp to
    /// 0.3 returns `Float(0.3)`, which widens to 0.30000001192…: against the verbatim `Double`
    /// bound it was refuted at every draw at or above 0.3, which is most of them.
    @Test("an n-ary Float subject clamped to its bound holds the law in both passes")
    func naryFloatClampPasses() throws {
        let entry = Self.entry(
            primary: "gain(at:)",
            typeName: "Progress",
            isInstanceMethod: true,
            parameterTypeNames: ["Int"],
            range: DocumentedRange(lower: "0.0", upper: "0.3", resultTypeName: "Float")
        )
        let outcome = try Self.run(entry, typeShape: nil, preamble: """
            struct Progress: Sendable {
                let done: Int
                let total: Int
                /// Gain (0.0 to 0.3)
                func gain(at x: Int) -> Float { min(max(Float(x), 0), 0.3) }
            }
            """, allShapes: ["Progress": Self.progressShape])
        guard case let .bothPass(defaultTrials, edgeTrials, _) = outcome else {
            Issue.record("expected .bothPass; got \(outcome)")
            return
        }
        #expect(defaultTrials > 0)
        #expect(edgeTrials > 0, "the boundary pass must run the law, not the zero-trial sentinel")
    }
}
