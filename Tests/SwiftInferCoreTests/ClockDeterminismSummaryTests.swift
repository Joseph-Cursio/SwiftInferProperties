import Testing
@testable import SwiftInferCore

/// Scan-time population of `FunctionSummary.isClockDeterministic`
/// (collections/async workplan Phase 4) — the same posture as
/// `isInferredPure`: computed where the `FunctionDeclSyntax` is live.
@Suite
struct ClockDeterminismSummaryTests {

    @Test
    func docCommentMarkerPopulatesFlag() throws {
        let source = """
        /// @lint.determinism clock_deterministic
        func fetchLabel(_ n: Int) async -> String { "#\\(n)" }
        """
        let summary = try #require(FunctionScanner.scan(source: source, file: "Test.swift").first)
        #expect(summary.isAsync)
        #expect(summary.isClockDeterministic)
    }

    @Test
    func attributeMarkerPopulatesFlag() throws {
        let source = """
        @ClockDeterministic
        func fetchLabel(_ n: Int) async -> String { "#\\(n)" }
        """
        let summary = try #require(FunctionScanner.scan(source: source, file: "Test.swift").first)
        #expect(summary.isClockDeterministic)
    }

    @Test
    func bareAsyncFunctionStaysUnmarked() throws {
        let source = "func fetchLabel(_ n: Int) async -> String { \"#\\(n)\" }"
        let summary = try #require(FunctionScanner.scan(source: source, file: "Test.swift").first)
        #expect(summary.isAsync)
        #expect(summary.isClockDeterministic == false)
    }
}
