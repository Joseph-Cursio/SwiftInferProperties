import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// A stub is never written over another suggestion's stub (#467).
///
/// The declaring-type prefix separates namesakes on different types — every collision the corpus
/// funnel census sampled. It cannot separate two overloads on one type, a sanitiser clash, or a file
/// an earlier run left for a suggestion this run does not re-offer, and each of those ended in the
/// same silent `Data.write(options: .atomic)` replacement. The write now checks whose file it is.
@Suite("Stub writes do not replace another suggestion's file")
struct StubCollisionGuardTests {

    private static func suggestion(_ canonical: String) -> Suggestion {
        Suggestion(
            templateName: "predicate",
            evidence: [
                Evidence(
                    displayName: "matches(_:)",
                    signature: "(String) -> Bool",
                    location: SourceLocation(file: "F.swift", line: 1, column: 1),
                    qualifiedTypeName: "Rules"
                )
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: canonical)
        )
    }

    private static func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StubCollisionGuardTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func writeStub(for suggestion: Suggestion, named name: String, in directory: URL) throws {
        let file = InteractiveTriage.wrappedFileContents(
            stub: "@Test func f() {}", suggestion: suggestion, fileName: name
        )
        try Data(file.utf8).write(to: directory.appendingPathComponent(name))
    }

    @Test func anEmptyPathIsUsedAsIs() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resolved = InteractiveTriage.collisionFreeStubFileName(
            preferred: "Rules_matches_predicate.swift", for: Self.suggestion("a"), in: directory
        )
        #expect(resolved.fileName == "Rules_matches_predicate.swift")
        #expect(resolved.displaced == nil)
    }

    /// **The control.** Re-accepting the same suggestion regenerates its own file in place.
    @Test func theSameSuggestionRewritesItsOwnFile() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = Self.suggestion("a")
        try Self.writeStub(for: suggestion, named: "Rules_matches_predicate.swift", in: directory)
        let resolved = InteractiveTriage.collisionFreeStubFileName(
            preferred: "Rules_matches_predicate.swift", for: suggestion, in: directory
        )
        #expect(resolved.fileName == "Rules_matches_predicate.swift")
        #expect(resolved.displaced == nil)
    }

    /// **The load-bearing case.** Two overloads share a display name, a type and a template, so they
    /// share a preferred name — the second must not replace the first.
    @Test func aDifferentSuggestionAtThePathGetsItsOwnName() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = Self.suggestion("matches(String)")
        let second = Self.suggestion("matches(Int)")
        try Self.writeStub(for: first, named: "Rules_matches_predicate.swift", in: directory)
        let resolved = InteractiveTriage.collisionFreeStubFileName(
            preferred: "Rules_matches_predicate.swift", for: second, in: directory
        )
        #expect(resolved.fileName == "Rules_matches_predicate_\(second.identity.normalized.prefix(8)).swift")
        #expect(resolved.displaced == first.identity.display)
    }

    /// A file with no identity line is not provably this stub, so it is never written over.
    @Test func aFileWithNoIdentityLineIsNotOverwritten() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// hand-written\n".utf8).write(to: directory.appendingPathComponent("Rules_matches_predicate.swift"))
        let resolved = InteractiveTriage.collisionFreeStubFileName(
            preferred: "Rules_matches_predicate.swift", for: Self.suggestion("a"), in: directory
        )
        #expect(resolved.fileName != "Rules_matches_predicate.swift")
    }

    /// **End to end, through a real triage run.** Two overloads — `normalize(_: String)` and
    /// `normalize(_: Int)` — share a name, a template and (as free functions) no declaring type, so
    /// both prefer `normalize_idempotence.swift`. Accepting both writes two files, not one, says so,
    /// and puts the shared test name `normalize_isIdempotent()` in two different suites.
    @Test func acceptingTwoOverloadsInOneRunWritesBoth() throws {
        let directory = try makeTriageFixtureDirectory(name: "OverloadCollision")
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = TriageRecordingDiagnosticOutput()
        let result = try InteractiveTriage.run(
            suggestions: [
                makeIdempotentSuggestion(funcName: "normalize", typeName: "String"),
                makeIdempotentSuggestion(funcName: "normalize", typeName: "Int")
            ],
            existingDecisions: .empty,
            context: makeTriageContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["A", "A"]),
                diagnostics: diagnostics,
                outputDirectory: directory
            )
        )
        #expect(result.writtenFiles.count == 2)
        #expect(Set(result.writtenFiles.map(\.lastPathComponent)).count == 2)
        let contents = try result.writtenFiles.map { try String(contentsOf: $0, encoding: .utf8) }
        #expect(contents.allSatisfy { $0.contains("@Test func normalize_isIdempotent()") })
        let suites = contents.compactMap { $0.split(separator: "\n").first { $0.hasPrefix("struct ") } }
        #expect(Set(suites).count == 2)
        #expect(diagnostics.lines.contains { $0.contains("so neither is lost") })
    }

    @Test func theRecordedIdentityIsReadFromTheHeader() {
        let suggestion = Self.suggestion("a")
        let file = InteractiveTriage.wrappedFileContents(stub: "@Test func f() {}", suggestion: suggestion)
        #expect(InteractiveTriage.recordedIdentity(in: file) == suggestion.identity.display)
        #expect(InteractiveTriage.recordedIdentity(in: "// nothing here") == nil)
    }
}
