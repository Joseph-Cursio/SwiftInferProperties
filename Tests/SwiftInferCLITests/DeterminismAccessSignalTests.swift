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
}
