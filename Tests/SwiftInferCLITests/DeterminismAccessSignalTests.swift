@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// A determinism law over an unreachable subject says so in the file it writes, not only in the
/// terminal (#465).
///
/// `determinismSuggestion` copied `withAccessRestrictionCaveats`' prose verbatim and not its
/// signal. The stub file's `Access:` header reads `.subjectNotVisibleToTests`, so a `private`
/// member's determinism stub carried no header at all — invisible while the call was spelled bare
/// and failed for that reason first, and the first thing a reader would hit once calls are
/// qualified: `'tokenizeLine' is inaccessible due to 'private' protection level`, unexplained.
@Suite("Determinism rows carry the access signal")
struct DeterminismAccessSignalTests {

    private struct SilentDiagnostics: DiagnosticOutput {
        func writeDiagnostic(_: String) { /* no-op */ }
    }

    private static let summary = FunctionSummary(
        name: "tokenizeLine",
        parameters: [Parameter(label: nil, internalName: "line", typeText: "String", isInout: false)],
        returnTypeText: "[Token]",
        isThrows: false,
        isAsync: false,
        isMutating: false,
        isStatic: true,
        location: SourceLocation(file: "Tokenizer.swift", line: 54, column: 5),
        containingTypeName: "Tokenizer",
        bodySignals: .empty
    )

    private static func law(restriction: AccessRestriction) throws -> Suggestion {
        let manifest = SeedManifest(seeds: [
            SeedManifest.Seed(
                file: "Tokenizer.swift", line: 54, symbol: "tokenizeLine", kind: .restrictedFunction
            )
        ])
        let laws = SwiftInferCommand.Discover.synthesizeGenericLaws(
            for: manifest,
            summaries: [],
            covered: [],
            diagnostics: SilentDiagnostics(),
            restrictedFunctions: [RestrictedFunction(summary: summary, restriction: restriction)]
        )
        return try #require(laws.first { $0.templateName == "determinism" })
    }

    @Test func aPrivateSubjectCarriesTheSignal() throws {
        let law = try Self.law(restriction: .notVisibleToTests)
        #expect(law.score.signals.contains { $0.kind == .subjectNotVisibleToTests })
    }

    /// The point of the signal: the header a reader sees in the file that will not compile.
    @Test func theStubFileSaysWhyItWillNotCompile() throws {
        let law = try Self.law(restriction: .enclosingTypeNotVisibleToTests)
        let header = InteractiveTriage.accessCaveat(for: law)
        #expect(header.hasPrefix("// Access: no test can name the subject:"))
        #expect(header.contains("This file will not compile until that is done."))
    }

    /// **The control.** `@testable` reaches `internal`, so a law over one must not be marked
    /// unrunnable — the same exclusion `blocksEveryTest` makes for template rows.
    @Test func anInternalSubjectCarriesNoSignal() throws {
        let law = try Self.law(restriction: .internalOrSPI)
        #expect(law.score.signals.contains { $0.kind == .subjectNotVisibleToTests } == false)
        #expect(InteractiveTriage.accessCaveat(for: law).isEmpty)
    }

    /// Weight 0: the signal records a fact about where the test can live, and must not demote the
    /// law — the remedy is to lift or widen, and a lower tier would hide that advice.
    @Test func theSignalDoesNotMoveTheScore() throws {
        let blocked = try Self.law(restriction: .notVisibleToTests)
        let reachable = try Self.law(restriction: .internalOrSPI)
        #expect(blocked.score.total == reachable.score.total)
    }

    // MARK: - The shape a real scan produces

    /// **The shape the tests above missed, and the one the scan actually hands over.** Since
    /// privacy stopped gating discovery, a restricted function is in `summaries` AND in
    /// `restrictedFunctions`. It is met in `summaries` first — so the fixtures above, which passed it
    /// only as restricted, exercised a path no real run takes, and the signal they pinned never
    /// reached a stub: re-measured on SwiftMarkdownWiki, 13 determinism stubs failed with
    /// "inaccessible due to 'private' protection level" and no `Access:` header.
    @Test func aRestrictedFunctionAlsoInSummariesCarriesTheSignal() throws {
        let manifest = SeedManifest(seeds: [
            SeedManifest.Seed(file: "Tokenizer.swift", line: 54, symbol: "tokenizeLine", kind: .pureFunction)
        ])
        let laws = SwiftInferCommand.Discover.synthesizeGenericLaws(
            for: manifest,
            summaries: [Self.summary],
            covered: [],
            diagnostics: SilentDiagnostics(),
            restrictedFunctions: [RestrictedFunction(summary: Self.summary, restriction: .notVisibleToTests)]
        )
        let law = try #require(laws.first { $0.templateName == "determinism" })
        #expect(laws.filter { $0.templateName == "determinism" }.count == 1, "met once, not once per list")
        #expect(law.score.signals.contains { $0.kind == .subjectNotVisibleToTests })
        #expect(law.explainability.whyMightBeWrong.first?.hasPrefix("NO TEST CAN RUN THIS LAW AS WRITTEN") == true)
    }

    /// The join is on the declaration's exact coordinate: a namesake elsewhere in the file that is
    /// restricted must not lend a visible function its verdict — the collision
    /// `withAccessRestrictionCaveats` was narrowed to exact coordinates to stop.
    @Test func aRestrictedNamesakeDoesNotLendItsVerdict() throws {
        let namesake = FunctionSummary(
            name: "tokenizeLine",
            parameters: Self.summary.parameters,
            returnTypeText: "[Token]",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: true,
            location: SourceLocation(file: "Tokenizer.swift", line: 120, column: 5),
            containingTypeName: "Other",
            bodySignals: .empty
        )
        let manifest = SeedManifest(seeds: [
            SeedManifest.Seed(file: "Tokenizer.swift", line: 54, symbol: "tokenizeLine", kind: .pureFunction)
        ])
        let laws = SwiftInferCommand.Discover.synthesizeGenericLaws(
            for: manifest,
            summaries: [Self.summary],
            covered: [],
            diagnostics: SilentDiagnostics(),
            restrictedFunctions: [RestrictedFunction(summary: namesake, restriction: .notVisibleToTests)]
        )
        let law = try #require(laws.first { $0.templateName == "determinism" })
        #expect(law.score.signals.contains { $0.kind == .subjectNotVisibleToTests } == false)
    }
}
