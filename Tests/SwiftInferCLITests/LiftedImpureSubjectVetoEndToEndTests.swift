import Foundation
import SwiftInferCLI
import SwiftInferCore
import Testing

/// **A lifted law over an impure subject never reaches the reader.** TestLifter's promoted rows
/// join after `TemplateRegistry.discover` runs the impure-subject veto, so until 2026-11-12 a law
/// lifted from a test of an impure function stayed live, at Strong tier in this fixture, and could
/// be accepted into a stub that executes the impurity once per trial.
///
/// The law is reference equivalence, `tidy(input) == input.lowercased()`, because the template
/// engine cannot pair `tidy` with `lowercased` itself, so the lifted row stands alone. An
/// idempotence test would not do: the engine proposes idempotence for any `(T) -> T` subject, and
/// the lifted twin is then folded into that row as cross-validation, which the old veto covered.
///
/// A lifted row is recognised by its evidence location, the test file it was lifted from. The
/// control, the same package with the impurity removed, shows the lifted row exists at all, so the
/// impure case's silence is the veto and not a fixture TestLifter never read.
@Suite("Discover — a lifted law over a witness-refuted subject is vetoed end to end")
struct LiftedImpureSubjectVetoEndToEndTests {

    private struct SilentDiagnostics: DiagnosticOutput {
        func writeDiagnostic(_: String) { /* no-op */ }
    }

    private static let testSource = """
    import XCTest
    @testable import Foo

    final class TidyTests: XCTestCase {
        func testMatchesReference() {
            let input = "Hello"
            XCTAssertEqual(tidy(input), input.lowercased())
        }
    }
    """

    /// A package whose `tidy(_:)` is impure (it writes to standard error) or pure.
    private static func package(impure: Bool) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiftedImpureVeto-\(UUID().uuidString)")
        let body = impure
            ? "FileHandle.standardError.write(Data(value.utf8))\n    return value.lowercased()"
            : "return value.lowercased()"
        let files = [
            "Package.swift": "// swift-tools-version: 5.9\nimport PackageDescription\n",
            "Sources/Foo/Tidy.swift":
                "import Foundation\n\npublic func tidy(_ value: String) -> String {\n    \(body)\n}\n",
            "Tests/FooTests/TidyTests.swift": testSource,
        ]
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    private static func liftedRows(impure: Bool) throws -> [Suggestion] {
        let root = try package(impure: impure)
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: root.appendingPathComponent("Sources/Foo"),
            diagnostics: SilentDiagnostics(),
            includePossible: true
        )
        return result.suggestions.filter { suggestion in
            suggestion.evidence.contains { $0.location.file.hasSuffix("TidyTests.swift") }
        }
    }

    @Test("control: the lifted reference-equivalence law over a pure tidy(_:) is shown")
    func liftedLawOverAPureSubjectIsShown() throws {
        #expect(try Self.liftedRows(impure: false).contains { $0.templateName == "differential-equivalence" })
    }

    @Test("the same lifted law over an impure tidy(_:) is withheld")
    func liftedLawOverAnImpureSubjectIsWithheld() throws {
        #expect(try Self.liftedRows(impure: true).isEmpty)
    }
}
