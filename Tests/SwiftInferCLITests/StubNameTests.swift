import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// A stub file is named for the suite it declares (`InteractiveTriage+StubName.swift`).
///
/// The names used to be underscored — `AnalysisProgress_progress_documented-range.swift`
/// declaring `AnalysisProgress_progress_documented_rangeTests` — which SwiftLint's `type_name`
/// rejects as an error and `file_name` flags in every stub, since no type matched the file.
@Suite("Stub file names — named for the suite they declare")
struct StubNameTests {

    static func suggestion(
        _ displayName: String,
        template: String,
        owner: String? = nil,
        pairedWith partner: String? = nil,
        signature: String = "(String) -> String"
    ) -> Suggestion {
        let location = SourceLocation(file: "F.swift", line: 1, column: 1)
        let evidence = ([displayName] + (partner.map { [$0] } ?? [])).map { name in
            Evidence(displayName: name, signature: signature, location: location, qualifiedTypeName: owner)
        }
        return Suggestion(
            templateName: template,
            evidence: evidence,
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "\(owner ?? "")::\(displayName)::\(template)")
        )
    }

    static let preservingIsValid = "(Account) -> Account preserving \\.isValid"

    /// Each suggestion and the file name it gets. Typed, so the type-checker is not left to infer
    /// a heterogeneous literal inside the `@Test` macro.
    static let names: [(Suggestion, String)] = [
        (suggestion("progress()", template: "documented-range", owner: "AnalysisProgress"),
         "AnalysisProgressProgressDocumentedRangeTests.swift"),
        (suggestion("normalize(_:)", template: "idempotence"), "NormalizeIdempotenceTests.swift"),
        (suggestion("tokenizeLine(_:)", template: "determinism", owner: "Editor.Tokenizer"),
         "EditorTokenizerTokenizeLineDeterminismTests.swift"),
        (suggestion("+(_:_:)", template: "commutativity", owner: "BigInt"), "BigIntPlusCommutativityTests.swift"),
        (suggestion("<=(_:_:)", template: "monotonicity", owner: "Version"), "VersionLessEqualMonotonicityTests.swift"),
        (suggestion("encode(_:)", template: "round-trip", owner: "Codec", pairedWith: "decode(_:)"),
         "CodecEncodeDecodeRoundTripTests.swift"),
        (suggestion("apply(_:)", template: "invariant-preservation", signature: preservingIsValid),
         "ApplyIsValidInvariantPreservationTests.swift")
    ]

    @Test("the words are the type, the function and the template, in UpperCamelCase", arguments: names)
    func theNameIsTheSuite(suggestion: Suggestion, expected: String) throws {
        let name = try #require(InteractiveTriage.stubFileName(for: suggestion))
        #expect(name == expected)
        #expect(!name.contains("_") && !name.contains("-"))
        #expect(InteractiveTriage.suiteName(forStubFileName: name) + ".swift" == name)
    }

    /// A name that would start with a digit gets `Stub` in front: a type name cannot.
    @Test func aLeadingDigitIsPrefixed() {
        #expect(InteractiveTriage.upperCamelIdentifier(["3d", "round-trip"]) == "Stub3dRoundTrip")
    }

    /// With nothing to name a stub for, its identity names it — still a suite name.
    @Test func theFallbackIsNamedForTheIdentity() {
        let suggestion = Self.suggestion("normalize(_:)", template: "idempotence")
        let name = InteractiveTriage.fallbackStubFileName(for: suggestion)
        #expect(name == "Suggestion\(suggestion.identity.normalized)Tests.swift")
        #expect(InteractiveTriage.suiteName(forStubFileName: name) + ".swift" == name)
    }

    // MARK: - The names an older run wrote

    /// The old algorithm, kept so a re-accept can find what an older run wrote.
    static let legacyNames: [(Suggestion, String)] = [
        (suggestion("progress()", template: "documented-range", owner: "AnalysisProgress"),
         "AnalysisProgress_progress_documented-range.swift"),
        (suggestion("normalize(_:)", template: "idempotence"), "normalize_idempotence.swift"),
        (suggestion("encode(_:)", template: "round-trip", owner: "Codec", pairedWith: "decode(_:)"),
         "Codec_encode_decode_round-trip.swift"),
        (suggestion("apply(_:)", template: "invariant-preservation", signature: preservingIsValid),
         "apply_isValid_invariant-preservation.swift")
    ]

    @Test("the legacy name is the one stubs had before", arguments: legacyNames)
    func theLegacyName(suggestion: Suggestion, expected: String) {
        #expect(InteractiveTriage.legacyStubFileName(for: suggestion) == expected)
    }

    private static func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("StubNameTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func write(_ suggestion: Suggestion, named name: String, in directory: URL) throws {
        let file = InteractiveTriage.wrappedFileContents(
            stub: "@Test func f() {}", suggestion: suggestion, fileName: name
        )
        try Data(file.utf8).write(to: directory.appendingPathComponent(name))
    }

    /// The file an older run wrote for this suggestion — by its legacy name, or that name with the
    /// clash suffix — is found by the identity it records, and nothing else is.
    @Test func anOlderFileForTheSameSuggestionIsSuperseded() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = Self.suggestion("progress()", template: "documented-range", owner: "AnalysisProgress")
        let clashName = "AnalysisProgress_progress_documented-range_\(suggestion.identity.normalized.prefix(8)).swift"
        try Self.write(suggestion, named: "AnalysisProgress_progress_documented-range.swift", in: directory)
        try Self.write(suggestion, named: clashName, in: directory)
        let superseded = InteractiveTriage.supersededStubFiles(for: suggestion, in: directory).map(\.lastPathComponent)
        #expect(Set(superseded) == ["AnalysisProgress_progress_documented-range.swift", clashName])
    }

    /// **The guard.** A file at the legacy name that records a different identity — or none — is
    /// someone else's, and is never removed.
    @Test func anotherSuggestionsFileIsNotSuperseded() throws {
        let directory = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = Self.suggestion("progress()", template: "documented-range", owner: "AnalysisProgress")
        let other = Self.suggestion("progress()", template: "documented-range", owner: "Elsewhere")
        try Self.write(other, named: "AnalysisProgress_progress_documented-range.swift", in: directory)
        #expect(InteractiveTriage.supersededStubFiles(for: suggestion, in: directory).isEmpty)
        try Data("// hand-written\n".utf8).write(
            to: directory.appendingPathComponent("AnalysisProgress_progress_documented-range.swift")
        )
        #expect(InteractiveTriage.supersededStubFiles(for: suggestion, in: directory).isEmpty)
    }

    /// **End to end.** Re-accepting a suggestion whose stub an older run wrote replaces that file
    /// rather than writing a second copy beside it, and says so.
    @Test func reacceptingReplacesTheOlderFile() throws {
        let directory = try makeTriageFixtureDirectory(name: "LegacyStubRename")
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestion = makeIdempotentSuggestion(funcName: "normalize", typeName: "String")
        let stubs = directory.appendingPathComponent("Tests/Generated/SwiftInfer/idempotence")
        try FileManager.default.createDirectory(at: stubs, withIntermediateDirectories: true)
        try Self.write(suggestion, named: "normalize_idempotence.swift", in: stubs)
        let diagnostics = TriageRecordingDiagnosticOutput()
        let result = try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: makeTriageContext(
                prompt: TriageRecordingPromptInput(scriptedLines: ["A"]),
                diagnostics: diagnostics,
                outputDirectory: directory
            )
        )
        #expect(result.writtenFiles.map(\.lastPathComponent) == ["NormalizeIdempotenceTests.swift"])
        let remaining = try FileManager.default.contentsOfDirectory(atPath: stubs.path)
        #expect(remaining == ["NormalizeIdempotenceTests.swift"])
        #expect(diagnostics.lines.contains { $0.contains("replaced normalize_idempotence.swift") })
    }
}
