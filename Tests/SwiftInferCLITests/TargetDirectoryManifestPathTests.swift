import Foundation
@testable import SwiftInferCLI
import Testing

/// `--target` must resolve a target whose manifest declares a `path:`.
///
/// `Sources/<target>/` is a convention, not a rule. This trap has now been paid for in three
/// separate subsystems — the census instrument (GRDB, `path: "GRDB"`), verify's module
/// resolution (swift-system, `path: "Sources/System"`), and `index --target` (Euclid,
/// `path: "Sources"`, which could not be indexed at all). The negative arms matter as much as
/// the positive one: a fallback that resolved *anything* would hide the confident-zero failure
/// `TargetDirectory` exists to prevent.
@Suite("TargetDirectory — a manifest's declared path is consulted before failing")
struct TargetDirectoryManifestPathTests {

    private func makePackage(manifest: String, directories: [String]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("target-dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for directory in directories {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(directory),
                withIntermediateDirectories: true
            )
        }
        try manifest.write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        return root
    }

    @Test("a target declaring `path: \"Sources\"` resolves to Sources itself (the Euclid shape)")
    func flatSourcesTargetResolves() throws {
        let root = try makePackage(
            manifest: """
            // swift-tools-version:5.9
            import PackageDescription
            let package = Package(
                name: "Euclid",
                targets: [.target(name: "Euclid", path: "Sources")]
            )
            """,
            directories: ["Sources"]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let resolved = try TargetDirectory.resolve("Euclid", relativeTo: root)
        #expect(resolved.standardizedFileURL.path
            == root.appendingPathComponent("Sources").standardizedFileURL.path)
    }

    @Test("the Sources/<target> convention still wins when it exists")
    func conventionTakesPrecedence() throws {
        let root = try makePackage(
            manifest: """
            // swift-tools-version:5.9
            import PackageDescription
            let package = Package(
                name: "Thing",
                targets: [.target(name: "Thing", path: "Elsewhere")]
            )
            """,
            directories: ["Sources/Thing", "Elsewhere"]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let resolved = try TargetDirectory.resolve("Thing", relativeTo: root)
        #expect(resolved.standardizedFileURL.path
            == root.appendingPathComponent("Sources/Thing").standardizedFileURL.path)
    }

    @Test("a declared path that is NOT on disk still fails, rather than being believed")
    func declaredButAbsentPathStillFails() throws {
        let root = try makePackage(
            manifest: """
            // swift-tools-version:5.9
            import PackageDescription
            let package = Package(
                name: "Ghost",
                targets: [.target(name: "Ghost", path: "NotThere")]
            )
            """,
            directories: ["Sources"]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: (any Error).self) { try TargetDirectory.resolve("Ghost", relativeTo: root) }
    }

    @Test("an unknown target still fails when the manifest names no such target")
    func unknownTargetStillFails() throws {
        let root = try makePackage(
            manifest: """
            // swift-tools-version:5.9
            import PackageDescription
            let package = Package(
                name: "Thing",
                targets: [.target(name: "Thing", path: "Sources")]
            )
            """,
            directories: ["Sources"]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: (any Error).self) { try TargetDirectory.resolve("Mistyped", relativeTo: root) }
    }
}
