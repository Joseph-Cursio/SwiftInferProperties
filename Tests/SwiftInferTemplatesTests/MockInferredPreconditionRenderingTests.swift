import SwiftInferCore
import Testing
@testable import SwiftInferTemplates

@Suite("LiftedTestEmitter — mock-inferred precondition rendering (M9.2)")
struct MockInferredPreconditionRenderingTests {

    // MARK: - Helpers

    private static func mock(
        typeName: String = "Doc",
        siteCount: Int = 5,
        argumentSpec: [MockGenerator.Argument],
        hints: [PreconditionHint] = []
    ) -> MockGenerator {
        MockGenerator(
            typeName: typeName,
            argumentSpec: argumentSpec,
            siteCount: siteCount,
            preconditionHints: hints
        )
    }

    private static func intArg(label: String?) -> MockGenerator.Argument {
        MockGenerator.Argument(label: label, swiftTypeName: "Int", observedLiterals: [])
    }

    private static func stringArg(label: String?) -> MockGenerator.Argument {
        MockGenerator.Argument(label: label, swiftTypeName: "String", observedLiterals: [])
    }

    // MARK: - No-hint baseline (M4.4 behavior preserved)

    @Test("No hints — empty constructor renders unchanged")
    func emptyConstructorNoHint() {
        let rendered = LiftedTestEmitter.mockInferredGenerator(
            Self.mock(argumentSpec: [])
        )
        #expect(rendered == "Gen<Doc> { _ in Doc() }")
        #expect(!rendered.contains("Inferred precondition"))
    }

    @Test("No hints — single-arg renders without comment line")
    func singleArgNoHint() {
        let rendered = LiftedTestEmitter.mockInferredGenerator(
            Self.mock(argumentSpec: [Self.intArg(label: "count")])
        )
        #expect(!rendered.contains("Inferred precondition"))
        #expect(rendered.contains(".map { Doc(count: $0) }"))
    }

    // MARK: - Single-arg with hint

    @Test("Single-arg with positiveInt hint emits inline comment line")
    func singleArgPositiveIntHintRendered() {
        let hint = PreconditionHint(
            position: 0,
            argumentLabel: "count",
            pattern: .positiveInt,
            siteCount: 5,
            suggestedGenerator: "Gen.int(in: 1...)"
        )
        let rendered = LiftedTestEmitter.mockInferredGenerator(
            Self.mock(argumentSpec: [Self.intArg(label: "count")], hints: [hint])
        )
        #expect(rendered.contains("// Inferred precondition: count"))
        #expect(rendered.contains("all observed values are positive Int"))
        #expect(rendered.contains("across 5 sites"))
        #expect(rendered.contains("consider Gen.int(in: 1...)"))
    }

    // MARK: - Multi-arg with hints

    @Test("Multi-arg renders multi-line zip with per-position hints")
    func multiArgPerPositionHintsRendered() {
        // Canonical sort: count(integer) < title(string) by label.
        let countHint = PreconditionHint(
            position: 0,
            argumentLabel: "count",
            pattern: .positiveInt,
            siteCount: 5,
            suggestedGenerator: "Gen.int(in: 1...)"
        )
        let titleHint = PreconditionHint(
            position: 1,
            argumentLabel: "title",
            pattern: .nonEmptyString,
            siteCount: 5,
            suggestedGenerator: "Gen.string()  // verify empty-string case is acceptable"
        )
        let rendered = LiftedTestEmitter.mockInferredGenerator(
            Self.mock(
                argumentSpec: [
                    Self.intArg(label: "count"),
                    Self.stringArg(label: "title")
                ],
                hints: [countHint, titleHint]
            )
        )
        // Both hints surface as separate comment lines.
        let lines = rendered.components(separatedBy: "\n")
        let hintLines = lines.filter { $0.contains("// Inferred precondition:") }
        #expect(hintLines.count == 2)
        #expect(rendered.contains("count — all observed values are positive Int"))
        #expect(rendered.contains("title — all observed strings are non-empty"))
        // Multi-line zip shape preserved.
        #expect(rendered.contains("zip(\n"))
        #expect(rendered.contains(".map { Doc("))
    }

    @Test("Multi-arg with partial hints emits only the matching positions")
    func multiArgPartialHintsRendered() {
        let countHint = PreconditionHint(
            position: 0,
            argumentLabel: "count",
            pattern: .intRange(low: 1, high: 5),
            siteCount: 5,
            suggestedGenerator: "Gen.int(in: 1...5)"
        )
        // No hint for position 1 (title).
        let rendered = LiftedTestEmitter.mockInferredGenerator(
            Self.mock(
                argumentSpec: [
                    Self.intArg(label: "count"),
                    Self.stringArg(label: "title")
                ],
                hints: [countHint]
            )
        )
        let hintLines = rendered.components(separatedBy: "\n")
            .filter { $0.contains("// Inferred precondition:") }
        #expect(hintLines.count == 1)
        #expect(rendered.contains("count — all observed values are in [1, 5]"))
        #expect(!rendered.contains("title — "))
    }

    // MARK: - Pattern coverage in description text

    @Test("Each pattern's description text matches the curated phrasing")
    func patternDescriptionsAllRender() {
        let cases: [(PreconditionPattern, String)] = [
            (.positiveInt, "all observed values are positive Int"),
            (.nonNegativeInt, "all observed values are non-negative Int"),
            (.negativeInt, "all observed values are negative Int"),
            (.intRange(low: 0, high: 9), "all observed values are in [0, 9]"),
            (.nonEmptyString, "all observed strings are non-empty"),
            (.stringLength(low: 1, high: 8), "all observed strings have length in [1, 8]"),
            (.constantBool(value: true), "all observed values are true"),
            (.constantBool(value: false), "all observed values are false")
        ]
        for (pattern, description) in cases {
            let hint = PreconditionHint(
                position: 0,
                argumentLabel: "x",
                pattern: pattern,
                siteCount: 3,
                suggestedGenerator: "<gen>"
            )
            let rendered = LiftedTestEmitter.mockInferredGenerator(
                Self.mock(argumentSpec: [Self.intArg(label: "x")], hints: [hint])
            )
            #expect(rendered.contains(description), "missing description for pattern: \(pattern)")
        }
    }

    // MARK: - Nil-label fallback

    @Test("Nil-label argument is rendered as positional[N] in the hint")
    func nilLabelRendersAsPositional() {
        let hint = PreconditionHint(
            position: 0,
            argumentLabel: nil,
            pattern: .positiveInt,
            siteCount: 4,
            suggestedGenerator: "Gen.int(in: 1...)"
        )
        let rendered = LiftedTestEmitter.mockInferredGenerator(
            Self.mock(argumentSpec: [Self.intArg(label: nil)], hints: [hint])
        )
        #expect(rendered.contains("positional[0]"))
    }

    @Test("siteCount == 1 renders singular 'site' (defensive — synthesizer requires ≥3)")
    func siteCountOneRendersSingular() {
        let hint = PreconditionHint(
            position: 0,
            argumentLabel: "x",
            pattern: .positiveInt,
            siteCount: 1,
            suggestedGenerator: "Gen.int(in: 1...)"
        )
        let rendered = LiftedTestEmitter.mockInferredGenerator(
            Self.mock(siteCount: 1, argumentSpec: [Self.intArg(label: "x")], hints: [hint])
        )
        #expect(rendered.contains("across 1 site"))
        #expect(!rendered.contains("across 1 sites"))
    }
}
