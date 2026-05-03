import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import SwiftInferTestLifter
import Testing

/// TestLifter M6.3 acceptance bar item (f) — `.swiftinfer/decisions.json`
/// writeouts for accepted/rejected/skipped lifted suggestions stay
/// rooted under `<package-root>/.swiftinfer/`. No source-tree
/// modification. Mirrors the existing accept-flow §16 #1 hard-
/// guarantee already shipped at TestLifter M3.3 (which covers the
/// `Tests/Generated/SwiftInfer/` writeout path; M6.3 extends to the
/// `.swiftinfer/decisions.json` path).
@Suite("Discover — decisions.json writeout sandbox for lifted suggestions (M6.3)")
struct LiftedDecisionsHardGuaranteeTests {

    @Test("Accepting a lifted suggestion writes decisions.json under <package-root>/.swiftinfer/")
    func decisionsWriteoutStaysSandboxed() throws {
        let packageRoot = try makeFixture(name: "DecisionsSandbox")
        defer { try? FileManager.default.removeItem(at: packageRoot) }
        try writePackageManifest(in: packageRoot)
        try writeSourcesUnannotatedFilter(in: packageRoot)
        try writeTestsCountInvariantBody(in: packageRoot)

        let beforeFiles = try fileSet(in: packageRoot, includingDotDirs: true)
        let lifted = try discoverLifted(directory: packageRoot)
        let outcome = try acceptLifted(suggestion: lifted, packageRoot: packageRoot)

        let decisionsPath = DecisionsLoader.defaultPath(for: packageRoot)
        try DecisionsLoader.write(outcome.updatedDecisions, to: decisionsPath)

        let afterFiles = try fileSet(in: packageRoot, includingDotDirs: true)
        let newFiles = Set(afterFiles).subtracting(beforeFiles)
        try assertNewFilesAreSandboxed(newFiles: newFiles, packageRoot: packageRoot)

        let swiftinferRoot = packageRoot.appendingPathComponent(".swiftinfer")
            .standardizedFileURL.path
        #expect(FileManager.default.fileExists(atPath: decisionsPath.path))
        #expect(decisionsPath.path.hasPrefix(swiftinferRoot + "/"))
        try assertOriginalSourceSurvived(packageRoot: packageRoot)
    }

    /// Drive the M3.3 accept-flow against `suggestion`. Encapsulated
    /// here so the main test body stays under SwiftLint's
    /// 50-line cap.
    private func acceptLifted(
        suggestion: Suggestion,
        packageRoot: URL
    ) throws -> InteractiveTriage.Result {
        let context = InteractiveTriage.Context(
            prompt: HGScriptedPromptInput(scriptedLines: ["A"]),
            output: HGSilentOutput(),
            diagnostics: HGSilentDiagnosticOutput(),
            outputDirectory: packageRoot,
            dryRun: false
        )
        return try InteractiveTriage.run(
            suggestions: [suggestion],
            existingDecisions: .empty,
            context: context
        )
    }

    /// Every newly-appearing file must be rooted under
    /// `<package-root>/.swiftinfer/` (the decisions write target)
    /// OR `<package-root>/Tests/Generated/SwiftInfer/` (the M3.3
    /// accept-flow stub target). Pre-M6.0 this contract held for
    /// TE-side suggestions; M6.3 extends it to the lifted-side
    /// accept-flow.
    private func assertNewFilesAreSandboxed(
        newFiles: Set<URL>,
        packageRoot: URL
    ) throws {
        let swiftinferRoot = packageRoot.appendingPathComponent(".swiftinfer")
            .standardizedFileURL.path
        let stubsRoot = packageRoot.appendingPathComponent("Tests/Generated/SwiftInfer")
            .standardizedFileURL.path
        for newFile in newFiles {
            let newStandardized = newFile.standardizedFileURL.path
            #expect(
                newStandardized.hasPrefix(swiftinferRoot + "/")
                    || newStandardized.hasPrefix(stubsRoot + "/"),
                "M6 accept created a file outside .swiftinfer/ or Tests/Generated/SwiftInfer/: \(newFile.path)"
            )
        }
    }

    /// Pin the pre-M6 source-tree-immutable contract: each
    /// originally-written fixture file is still present after the
    /// accept run.
    private func assertOriginalSourceSurvived(packageRoot: URL) throws {
        let sourceFiles = [
            packageRoot.appendingPathComponent("Sources/Foo/Filter.swift"),
            packageRoot.appendingPathComponent("Tests/FooTests/FilterTests.swift"),
            packageRoot.appendingPathComponent("Package.swift")
        ]
        for sourceFile in sourceFiles {
            #expect(
                FileManager.default.fileExists(atPath: sourceFile.path),
                "Source file \(sourceFile.path) should still exist after M6 accept"
            )
        }
    }

    // MARK: - Fixture helpers (parallel to LiftedDecisionsPersistenceTests)

    private func makeFixture(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiftedDecisionsHG-\(name)-\(UUID().uuidString)")
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

    private func writeTestsCountInvariantBody(in directory: URL) throws {
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

    private func discoverLifted(directory: URL) throws -> Suggestion {
        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: directory.appendingPathComponent("Sources/Foo"),
            includePossible: true,
            diagnostics: HGSilentDiagnosticOutput()
        )
        return try #require(result.suggestions.first { suggestion in
            suggestion.liftedOrigin != nil && suggestion.templateName == "invariant-preservation"
        })
    }

    private func fileSet(in directory: URL, includingDotDirs: Bool) throws -> [URL] {
        let manager = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions =
            includingDotDirs ? [] : [.skipsHiddenFiles]
        guard let enumerator = manager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: options
        ) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
            var isDir: ObjCBool = false
            manager.fileExists(atPath: url.path, isDirectory: &isDir)
            if !isDir.boolValue {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }
}
