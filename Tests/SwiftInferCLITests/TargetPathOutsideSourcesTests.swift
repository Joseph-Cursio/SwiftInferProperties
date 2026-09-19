import Foundation
@testable import SwiftInferCLI
import Testing

/// `--target` resolves `Sources/<target>` by convention, and a manifest may place a target
/// anywhere via `path:`. The manifest fallback existed, but **only under the `Sources/` guard** —
/// so a package with no `Sources/` directory at all never reached it (SwiftInferProperties#528).
///
/// **Fourth recurrence of this trap, and the first three fixes each left this branch
/// unreachable**: GRDB (`path: "GRDB"`) resolved to zero files in `measurement.py`, swift-system
/// (`path: "Sources/System"`) reported 21 failures under a carrier label, and Euclid
/// (`path: "Sources"`) was unreachable until the fallback was added below the guard.
///
/// Measured cost of this one: `index --target` failed outright on SwiftMarkdownWiki while
/// `discover --sources` scanned it happily, so the corpus census recorded **0 laws for a
/// repository that had just written 35 stubs** — a number that could not be true, which is how it
/// was found.
@Suite("--target reaches a target the manifest places outside Sources/")
struct TargetPathOutsideSourcesTests {

    /// A package whose only target lives at `<root>/Engine`, with no `Sources/` anywhere.
    static func makePackage(targetPath: String, createSources: Bool) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(targetPath), withIntermediateDirectories: true
        )
        if createSources {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true
            )
        }
        try "public struct Placeholder { public init() {} }".write(
            to: root.appendingPathComponent(targetPath).appendingPathComponent("P.swift"),
            atomically: true, encoding: .utf8
        )
        try """
        // swift-tools-version: 6.2
        import PackageDescription

        let package = Package(
            name: "TP",
            targets: [
                .target(
                    name: "Engine",
                    path: "\(targetPath)"
                )
            ]
        )
        """.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        return root
    }

    /// The defect: no `Sources/` at all, so the fallback was never consulted.
    @Test("a package with NO Sources/ still resolves its declared target")
    func resolvesWithoutASourcesDirectory() throws {
        let root = try Self.makePackage(targetPath: "Engine", createSources: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let resolved = try TargetDirectory.resolve("Engine", relativeTo: root)
        #expect(
            resolved.standardizedFileURL.path
                == root.appendingPathComponent("Engine").standardizedFileURL.path
        )
    }

    /// The case the previous fix covered, pinned so restructuring cannot lose it.
    @Test("a package WITH Sources/ still resolves a target declared elsewhere")
    func resolvesAlongsideASourcesDirectory() throws {
        let root = try Self.makePackage(targetPath: "Engine", createSources: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let resolved = try TargetDirectory.resolve("Engine", relativeTo: root)
        #expect(
            resolved.standardizedFileURL.path
                == root.appendingPathComponent("Engine").standardizedFileURL.path
        )
    }

    /// The control. Without it the two arms above would pass on a resolver that returned any
    /// directory it was handed, which is the shape this repository's own guards keep catching.
    @Test("a target the manifest does not declare still fails, and says why")
    func unknownTargetStillFails() throws {
        let root = try Self.makePackage(targetPath: "Engine", createSources: false)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: (any Error).self) {
            _ = try TargetDirectory.resolve("Nope", relativeTo: root)
        }
    }

    /// The convention must still win where it applies, so no package that resolved before
    /// resolves differently now.
    @Test("the Sources/<target> convention is still tried first")
    func conventionStillWins() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tp-\(UUID().uuidString)")
        let conventional = root.appendingPathComponent("Sources/Engine")
        try FileManager.default.createDirectory(at: conventional, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let resolved = try TargetDirectory.resolve("Engine", relativeTo: root)
        #expect(resolved.standardizedFileURL.path == conventional.standardizedFileURL.path)
    }
}
