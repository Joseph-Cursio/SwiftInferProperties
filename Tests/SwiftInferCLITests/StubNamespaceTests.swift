import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Every emitted stub's tests live in a suite named for its file (#467).
///
/// Emitters name a test from the bare function name at the top level of the file, so five
/// `matches(_:)` predicates on five types declare `matches_isTotal()` five times — `invalid
/// redeclaration`, and the whole test target stops building. It never surfaced because the five
/// files overwrote one another at a single path. Namespacing comes first so that the file names can
/// then be made distinct without breaking the build.
@Suite("Stub files namespace their tests")
struct StubNamespaceTests {

    private static func suggestion(_ displayName: String, template: String = "predicate") -> Suggestion {
        Suggestion(
            templateName: template,
            evidence: [
                Evidence(
                    displayName: displayName,
                    signature: "(String) -> Bool",
                    location: SourceLocation(file: "F.swift", line: 1, column: 1)
                )
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "F.swift::\(displayName)::\(template)")
        )
    }

    private static let stub = """
    @Test func matches_isTotal() async {
        _ = 1
    }
    """

    // MARK: - The name

    @Test("a file name becomes a Swift identifier", arguments: [
        ("normalize_idempotence.swift", "normalize_idempotenceTests"),
        ("parse_input-totality.swift", "parse_input_totalityTests"),
        ("Editor_Tokenizer_tokenizeLine_determinism.swift", "Editor_Tokenizer_tokenizeLine_determinismTests"),
        ("3d_round-trip.swift", "_3d_round_tripTests")
    ])
    func theSuiteNameIsAnIdentifier(fileName: String, expected: String) {
        #expect(InteractiveTriage.suiteName(forStubFileName: fileName) == expected)
    }

    // MARK: - The wrapper

    @Test func theStubIsIndentedInsideTheSuite() {
        let wrapped = InteractiveTriage.namespaced(Self.stub, suiteName: "S")
        #expect(wrapped == "struct S {\n    @Test func matches_isTotal() async {\n        _ = 1\n    }\n}\n")
    }

    /// Indenting a multi-line string literal changes its value, so a stub holding one is wrapped
    /// but left as written. No census stub holds one; this keeps a future emitter safe.
    @Test func aMultiLineStringLiteralIsNotReindented() {
        let literal = "@Test func f() {\n    let text = \"\"\"\n    body\n    \"\"\"\n}"
        let wrapped = InteractiveTriage.namespaced(literal, suiteName: "S")
        #expect(wrapped == "struct S {\n\(literal)\n}\n")
    }

    // MARK: - The written file

    /// **The load-bearing case.** Two stubs whose emitters chose the same test function name land
    /// in different suites, so the module declares no name twice.
    @Test func twoStubsWithOneTestNameGetDistinctSuites() {
        let suggestion = Self.suggestion("matches(_:)")
        let first = InteractiveTriage.wrappedFileContents(
            stub: Self.stub, suggestion: suggestion, fileName: "RegistrationVerb_matches_predicate.swift"
        )
        let second = InteractiveTriage.wrappedFileContents(
            stub: Self.stub, suggestion: suggestion, fileName: "MockTypeName_matches_predicate.swift"
        )
        #expect(first.contains("struct RegistrationVerb_matches_predicateTests {\n    @Test func matches_isTotal()"))
        #expect(second.contains("struct MockTypeName_matches_predicateTests {\n    @Test func matches_isTotal()"))
    }

    /// The imports stay at file scope, outside the suite; only the stub moves.
    @Test func theImportsStayAtFileScope() throws {
        let file = InteractiveTriage.wrappedFileContents(
            stub: Self.stub, suggestion: Self.suggestion("matches(_:)"), fileName: "matches_predicate.swift"
        )
        let suiteStart = try #require(file.range(of: "struct matches_predicateTests {"))
        let lastImport = try #require(file.range(of: "import PropertyLawKit", options: .backwards))
        #expect(lastImport.upperBound <= suiteStart.lowerBound)
        #expect(file.hasSuffix("}\n"))
    }

    /// With no file name passed, the suite is named the way the accept path names the file, so a
    /// caller that omits it still gets one suite per file rather than a collision.
    @Test func anOmittedFileNameFallsBackToTheStubFileName() throws {
        let suggestion = Self.suggestion("matches(_:)")
        let fileName = try #require(InteractiveTriage.stubFileName(for: suggestion))
        let file = InteractiveTriage.wrappedFileContents(stub: Self.stub, suggestion: suggestion)
        #expect(file.contains("struct \(InteractiveTriage.suiteName(forStubFileName: fileName)) {"))
    }
}
