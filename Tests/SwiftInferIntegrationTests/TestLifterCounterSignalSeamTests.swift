import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M7.0 acceptance — `counterSignalsFromTestLifter` seam.
/// Asymmetric-assertion counter-signals from the test corpus (a)
/// apply `-25 .asymmetricAssertion` to TE-side suggestions whose
/// `crossValidationKey` matches and (b) filter lifted-side
/// suggestions whose key matches out of the visible discover stream.
@Suite("TestLifter — counter-signal seam end-to-end (M7.0)")
struct TestLifterCounterSignalSeamTests {

    @Test("Counter-signal applies -25 .asymmetricAssertion to matching TE-side suggestion")
    func counterSignalDemotesTeSide() throws {
        // Production: `merge(_:_:)` is in `CommutativityTemplate.curatedVerbs`
        // (the curated +25 commutativity-verb list). Score signals add up
        // to >= Possible at baseline.
        let merge = makeBinaryIntListFunction(name: "merge", file: "Merge.swift")

        let baseline = TemplateRegistry.discover(in: [merge])
        let baselineCommutativity = try #require(
            baseline.first { $0.templateName == "commutativity" }
        )
        let baselineTotal = baselineCommutativity.score.total

        // Counter-signal: a test body asserts `merge(a, b) != merge(b, a)`.
        let counterKeys: Set<CrossValidationKey> = [
            CrossValidationKey(templateName: "commutativity", calleeNames: ["merge"])
        ]
        let counterSignaled = TemplateRegistry.discover(
            in: [merge],
            counterSignalsFromTestLifter: counterKeys
        )
        let demoted = try #require(
            counterSignaled.first { $0.templateName == "commutativity" }
        )
        #expect(demoted.score.total == baselineTotal - 25)
        #expect(demoted.score.signals.contains { $0.kind == .asymmetricAssertion && $0.weight == -25 })
        #expect(
            demoted.explainability.whyMightBeWrong.contains { $0.contains("Counter-signal") }
        )
    }

    @Test("Cross-validation +20 and counter-signal -25 coexist on different callees")
    func crossValidationAndCounterSignalCoexist() throws {
        // Two functions: `merge` (gets +20 from cross-validation) and
        // `combine` (gets -25 from counter-signal). The two seams operate
        // independently per callee.
        let merge = makeBinaryIntListFunction(name: "merge", file: "Merge.swift")
        let combine = makeBinaryIntListFunction(name: "combine", file: "Combine.swift")
        let cvKeys: Set<CrossValidationKey> = [
            CrossValidationKey(templateName: "commutativity", calleeNames: ["merge"])
        ]
        let csKeys: Set<CrossValidationKey> = [
            CrossValidationKey(templateName: "commutativity", calleeNames: ["combine"])
        ]
        let result = TemplateRegistry.discover(
            in: [merge, combine],
            crossValidationFromTestLifter: cvKeys,
            counterSignalsFromTestLifter: csKeys
        )
        let mergeSignals = signals(in: result, matching: "merge") ?? []
        let combineSignals = signals(in: result, matching: "combine") ?? []
        #expect(mergeSignals.contains { $0.kind == .crossValidation && $0.weight == 20 })
        #expect(!mergeSignals.contains { $0.kind == .asymmetricAssertion })
        #expect(combineSignals.contains { $0.kind == .asymmetricAssertion && $0.weight == -25 })
        #expect(!combineSignals.contains { $0.kind == .crossValidation })
    }

    private func signals(
        in suggestions: [Suggestion],
        matching name: String
    ) -> [Signal]? {
        suggestions.first { suggestion in
            suggestion.templateName == "commutativity"
                && (suggestion.evidence.first?.displayName.contains(name) ?? false)
        }?.score.signals
    }

    private func makeBinaryIntListFunction(name: String, file: String) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(label: nil, internalName: "lhs", typeText: "[Int]", isInout: false),
                Parameter(label: nil, internalName: "rhs", typeText: "[Int]", isInout: false)
            ],
            returnTypeText: "[Int]",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: file, line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }

    @Test("Counter-signal pass on a suggestion that's also cross-validated lands at base+20-25")
    func crossValidatedAndCounterSignaledOnSameKey() throws {
        let merge = makeBinaryIntListFunction(name: "merge", file: "Merge.swift")
        let baseline = TemplateRegistry.discover(in: [merge])
        let baselineTotal = try #require(
            baseline.first { $0.templateName == "commutativity" }?.score.total
        )

        let key = CrossValidationKey(templateName: "commutativity", calleeNames: ["merge"])
        let bothSeams = TemplateRegistry.discover(
            in: [merge],
            crossValidationFromTestLifter: [key],
            counterSignalsFromTestLifter: [key]
        )
        let bothSignals = try #require(
            bothSeams.first { $0.templateName == "commutativity" }?.score.signals
        )
        // base + 20 - 25 = base - 5
        let total = bothSignals.reduce(0) { $0 + $1.weight }
        // The total here includes ALL signals (template-side + +20 + -25),
        // so the diff between baseline-total and both-seams-total is (-5).
        let bothTotal = try #require(
            bothSeams.first { $0.templateName == "commutativity" }?.score.total
        )
        #expect(bothTotal == baselineTotal + 20 - 25)
        #expect(total == bothTotal)
    }

    @Test("Empty counter-signal set is a no-op fast path")
    func emptyCounterSignalSetIsNoop() throws {
        let merge = makeBinaryIntListFunction(name: "merge", file: "Merge.swift")
        let baseline = TemplateRegistry.discover(in: [merge])
        let withEmptyCS = TemplateRegistry.discover(
            in: [merge],
            counterSignalsFromTestLifter: []
        )
        #expect(baseline == withEmptyCS)
    }
}

/// TestLifter M7.0 acceptance bar item (c) — lifted-side suggestions
/// matching a counter-signal are filtered entirely from the visible
/// discover stream. The user's explicit negative assertion is
/// dispositive on the lifted side.
@Suite("TestLifter — counter-signal filters lifted side end-to-end (M7.0)")
struct TestLifterCounterSignalLiftedFilterTests {

    @Test("Counter-signal in tests filters the matching lifted-only count-invariance suggestion")
    func liftedSideFilteredByCounterSignal() throws {
        let directory = try makeFixture(name: "LiftedFiltered")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePackageManifest(in: directory)
        try writeSourcesUnannotatedFilter(in: directory)
        // Test body asserts NEGATIVE form: filter(xs).count != xs.count.
        // Without M7, this would surface a freestanding lifted-only
        // count-invariance suggestion (annotation-only on TE side per
        // PRD §5.2). With M7, the counter-signal filters the lifted.
        try writeTestsCountInvariantNegative(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory.appendingPathComponent("Sources/Foo"),
            includePossible: true,
            diagnostics: SilentCounterSignalDiagnostics()
        )
        let lifted = result.suggestions.first { suggestion in
            suggestion.liftedOrigin != nil && suggestion.templateName == "invariant-preservation"
        }
        #expect(lifted == nil, "Lifted count-invariance should be filtered by counter-signal")
    }

    @Test("Positive test body still surfaces the lifted suggestion (no false positive)")
    func liftedSurvivesWithoutCounterSignal() throws {
        let directory = try makeFixture(name: "LiftedSurvives")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePackageManifest(in: directory)
        try writeSourcesUnannotatedFilter(in: directory)
        // Positive form — no counter-signal fires; lifted should
        // surface as before.
        try writeTestsCountInvariantPositive(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory.appendingPathComponent("Sources/Foo"),
            includePossible: true,
            diagnostics: SilentCounterSignalDiagnostics()
        )
        let lifted = result.suggestions.first { suggestion in
            suggestion.liftedOrigin != nil && suggestion.templateName == "invariant-preservation"
        }
        #expect(lifted != nil, "Without counter-signal the lifted should surface")
    }

    // MARK: - Fixture helpers

    private func makeFixture(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("CounterSignalLifted-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writePackageManifest(in directory: URL) throws {
        try "// swift-tools-version: 5.9\nimport PackageDescription\n"
            .write(
                to: directory.appendingPathComponent("Package.swift"),
                atomically: true,
                encoding: .utf8
            )
    }

    private func writeSourcesUnannotatedFilter(in directory: URL) throws {
        let sources = directory.appendingPathComponent("Sources/Foo")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        public func filter(_ xs: [Int]) -> [Int] {
            return xs
        }
        """.write(
            to: sources.appendingPathComponent("Filter.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeTestsCountInvariantNegative(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests/FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest

        final class FilterTests: XCTestCase {
            func testFilterChangesCount() {
                let xs = [1, 2, 3, 4]
                XCTAssertNotEqual(filter(xs).count, xs.count)
            }
        }
        """.write(
            to: tests.appendingPathComponent("FilterTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeTestsCountInvariantPositive(in directory: URL) throws {
        let tests = directory.appendingPathComponent("Tests/FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        import XCTest

        final class FilterTests: XCTestCase {
            func testFilterPreservesCount() {
                let xs = [1, 2, 3, 4]
                XCTAssertEqual(filter(xs).count, xs.count)
            }
        }
        """.write(
            to: tests.appendingPathComponent("FilterTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }
}

private struct SilentCounterSignalDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_ message: String) {}
}
