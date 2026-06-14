import Foundation
@testable import SwiftInferCLI
import Testing

/// Cycle 113 — file-structure tests for the corpus packager (fast; no
/// subprocess build). The end-to-end build+run+measure proof lives in the
/// `.subprocess`-tagged `IdempotenceCorpusMeasuredTests`.
@Suite("CorpusPackager — standalone module-named package scaffolding (cycle 113)")
struct CorpusPackagerTests {

    @Test("packages sources under a module-named root with a library-product manifest")
    func packagesIntoModuleNamedRoot() throws {
        let parent = try makeTempDir(name: "PackagerRoot")
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "IdempotenceCorpus",
            sourceFiles: [
                .init(name: "Counter.swift", contents: "public struct Counter {}"),
                .init(name: "Toggle.swift", contents: "public struct Toggle {}")
            ],
            into: parent
        )

        // Root directory is named after the module — the SwiftPM path-dep
        // identity invariant.
        #expect(root.lastPathComponent == "IdempotenceCorpus")

        let manifest = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        #expect(manifest.contains("name: \"IdempotenceCorpus\""))
        #expect(manifest.contains(".library(name: \"IdempotenceCorpus\", targets: [\"IdempotenceCorpus\"])"))
        #expect(manifest.contains(".target(name: \"IdempotenceCorpus\")"))
        #expect(manifest.contains("// swift-tools-version: 6.1"))

        // Sources landed under Sources/<module>/.
        let sourcesDir = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("IdempotenceCorpus")
        for name in ["Counter.swift", "Toggle.swift"] {
            #expect(
                FileManager.default.fileExists(atPath: sourcesDir.appendingPathComponent(name).path),
                "\(name) should be copied into the module sources"
            )
        }
    }

    @Test("fromSourcesDirectory reads top-level .swift files and skips non-Swift entries")
    func fromSourcesDirectoryFiltersToSwift() throws {
        let parent = try makeTempDir(name: "PackagerFromDir")
        defer { try? FileManager.default.removeItem(at: parent) }

        // A loose corpus Sources dir: two reducers + an asset/plist that
        // must NOT be packaged.
        let loose = parent.appendingPathComponent("loose")
        try FileManager.default.createDirectory(at: loose, withIntermediateDirectories: true)
        try Data("public struct A {}".utf8).write(to: loose.appendingPathComponent("A.swift"))
        try Data("public struct B {}".utf8).write(to: loose.appendingPathComponent("B.swift"))
        try Data("{}".utf8).write(to: loose.appendingPathComponent("Info.plist"))

        let root = try CorpusPackager.package(
            moduleName: "Corpus",
            fromSourcesDirectory: loose,
            into: parent.appendingPathComponent("out")
        )

        let sourcesDir = root.appendingPathComponent("Sources").appendingPathComponent("Corpus")
        let copied = try FileManager.default
            .contentsOfDirectory(atPath: sourcesDir.path)
            .sorted()
        #expect(copied == ["A.swift", "B.swift"])
    }

    @Test("empty module name and empty source list are rejected")
    func rejectsDegenerateInputs() throws {
        let parent = try makeTempDir(name: "PackagerReject")
        defer { try? FileManager.default.removeItem(at: parent) }

        #expect(throws: CorpusPackager.PackagerError.emptyModuleName) {
            _ = try CorpusPackager.package(
                moduleName: "",
                sourceFiles: [.init(name: "X.swift", contents: "")],
                into: parent
            )
        }
        #expect(throws: CorpusPackager.PackagerError.noSourceFiles) {
            _ = try CorpusPackager.package(moduleName: "Corpus", sourceFiles: [], into: parent)
        }
    }

    // MARK: - Helpers

    private func makeTempDir(name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CorpusPackager-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
