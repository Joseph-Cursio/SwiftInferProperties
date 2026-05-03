import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M6.1 acceptance — `// swiftinfer: skip <hash>` markers
/// suppress matching lifted suggestions, regardless of which
/// directory the marker lives in (production target OR resolved test
/// directory). Mirrors the existing `SkipMarkerScanner` contract
/// shipped for TE-side suggestions at TemplateEngine M1.5.
///
/// Uses the count-invariance template because it's annotation-only
/// on the TE side (`InvariantPreservationTemplate` requires
/// `@CheckProperty(.preservesInvariant(\.count))` per PRD §5.2). This
/// keeps the lifted-only path clean — without the annotation, the TE
/// side stays silent and the lifted enters the visible stream as a
/// freestanding suggestion that the M6.1 skip-marker filter operates
/// on directly. Idempotence + commutativity wouldn't work here
/// because TE fires on the type-shape signal alone, suppressing the
/// lifted via cross-validation dedup before the M6.1 filter runs.
@Suite("Discover — // swiftinfer: skip honoring for lifted suggestions (M6.1)")
struct LiftedSkipMarkerHonoringTests {

    @Test("Test-side skip marker suppresses the matching lifted count-invariance suggestion")
    func testSideSkipMarkerSuppressesLifted() throws {
        let directory = try makeFixture(name: "TestSideSkip")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePackageManifest(in: directory)
        try writeSourcesUnannotatedFilter(in: directory)
        let liftedHash = try discoverLiftedHash(directory: directory)
        try writeTestsCountInvariantBody(in: directory, withSkipMarkerHash: liftedHash)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory.appendingPathComponent("Sources/Foo"),
            includePossible: true,
            diagnostics: SilentSkipDiagnostics()
        )
        let lifted = result.suggestions.first { suggestion in
            suggestion.liftedOrigin != nil && suggestion.templateName == "invariant-preservation"
        }
        #expect(lifted == nil, "Test-side // swiftinfer: skip should suppress the lifted suggestion")
    }

    @Test("Production-side skip marker suppresses the matching lifted count-invariance suggestion")
    func productionSideSkipMarkerSuppressesLifted() throws {
        let directory = try makeFixture(name: "ProductionSideSkip")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePackageManifest(in: directory)
        try writeSourcesUnannotatedFilter(in: directory)
        let liftedHash = try discoverLiftedHash(directory: directory)
        // Marker lives in the production source file. SkipMarkerScanner
        // walks the whole production-target tree so markers anywhere
        // in it are honored; the M6.1 union fold brings them through
        // to the lifted-side filter.
        try writeSourcesUnannotatedFilter(in: directory, withSkipMarkerHash: liftedHash)
        try writeTestsCountInvariantBody(in: directory)

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory.appendingPathComponent("Sources/Foo"),
            includePossible: true,
            diagnostics: SilentSkipDiagnostics()
        )
        let lifted = result.suggestions.first { suggestion in
            suggestion.liftedOrigin != nil && suggestion.templateName == "invariant-preservation"
        }
        #expect(lifted == nil, "Production-side // swiftinfer: skip should suppress the lifted suggestion")
    }

    @Test("Skip marker for an unrelated hash is a no-op")
    func unrelatedSkipMarkerIsNoOp() throws {
        let directory = try makeFixture(name: "UnrelatedSkip")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePackageManifest(in: directory)
        try writeSourcesUnannotatedFilter(in: directory)
        // Skip marker for a hash that doesn't match any suggestion.
        try writeTestsCountInvariantBody(
            in: directory,
            withSkipMarkerHash: "0000000000000000000000000000000000000000000000000000000000000000"
        )

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory.appendingPathComponent("Sources/Foo"),
            includePossible: true,
            diagnostics: SilentSkipDiagnostics()
        )
        let lifted = result.suggestions.first { suggestion in
            suggestion.liftedOrigin != nil && suggestion.templateName == "invariant-preservation"
        }
        #expect(lifted != nil, "An unrelated skip marker should not suppress any lifted suggestion")
    }

    @Test("Malformed skip marker (non-hex) is a no-op")
    func malformedSkipMarkerIsNoOp() throws {
        let directory = try makeFixture(name: "MalformedSkip")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePackageManifest(in: directory)
        try writeSourcesUnannotatedFilter(in: directory)
        try writeTestsCountInvariantBody(in: directory, withSkipMarkerHash: "not-a-hash")

        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory.appendingPathComponent("Sources/Foo"),
            includePossible: true,
            diagnostics: SilentSkipDiagnostics()
        )
        let lifted = result.suggestions.first { suggestion in
            suggestion.liftedOrigin != nil && suggestion.templateName == "invariant-preservation"
        }
        #expect(lifted != nil, "A malformed skip marker should not suppress any lifted suggestion")
    }

    // MARK: - Fixture helpers

    private func makeFixture(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiftedSkipMarker-\(name)-\(UUID().uuidString)")
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

    /// Production source has `filter(_:)` *without* the
    /// `@CheckProperty(.preservesInvariant(\.count))` annotation.
    /// `InvariantPreservationTemplate` is annotation-only (PRD §5.2
    /// caveat) — it stays silent without the annotation. The
    /// test-side body asserting `filter(xs).count == xs.count`
    /// triggers the M5.2 lifted detector; the lifted enters the
    /// visible discover stream as a freestanding suggestion.
    private func writeSourcesUnannotatedFilter(
        in directory: URL,
        withSkipMarkerHash skipHash: String? = nil
    ) throws {
        let sources = directory.appendingPathComponent("Sources/Foo")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let prefix = skipHash.map { "// swiftinfer: skip \($0)\n\n" } ?? ""
        try """
        \(prefix)public func filter(_ xs: [Int]) -> [Int] {
            return xs
        }
        """.write(
            to: sources.appendingPathComponent("Filter.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeTestsCountInvariantBody(
        in directory: URL,
        withSkipMarkerHash skipHash: String? = nil
    ) throws {
        let tests = directory.appendingPathComponent("Tests/FooTests")
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        let prefix = skipHash.map { "// swiftinfer: skip \($0)\n" } ?? ""
        try """
        \(prefix)import XCTest

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

    /// Run discover once without any skip marker to capture the
    /// lifted suggestion's identity hash. The hash is a pure function
    /// of the suggestion's identity (`lifted|invariant-preservation|filter`),
    /// so a second run with the marker can target it precisely.
    private func discoverLiftedHash(directory: URL) throws -> String {
        try writeTestsCountInvariantBody(in: directory)
        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory.appendingPathComponent("Sources/Foo"),
            includePossible: true,
            diagnostics: SilentSkipDiagnostics()
        )
        let lifted = try #require(result.suggestions.first { suggestion in
            suggestion.liftedOrigin != nil && suggestion.templateName == "invariant-preservation"
        })
        return lifted.identity.normalized
    }
}

private struct SilentSkipDiagnostics: DiagnosticOutput {
    func writeDiagnostic(_ message: String) {}
}
