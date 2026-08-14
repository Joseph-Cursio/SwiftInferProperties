import Foundation
import Testing

@testable import SwiftInferCLI

/// A target's sources are wherever its manifest says, not always `Sources/<target>`.
///
/// **`Sources/<target>` is SwiftPM's default, not a rule**, and assuming it made whole
/// packages unreachable rather than partially covered. Measured on GRDB `b83108d10`
/// (`docs/measurements/exploratory-swiftformat-grdb.md` §7): it declares `path: "GRDB"`, so its
/// 167 sources sit at repo root and `prove-then-show --target GRDB` scanned a directory that
/// does not exist — surveying nothing, and not reporting that it had.
///
/// The knowledge was already in the tree: `TargetIsolation.packageRoot(containing:)` documents
/// that "a manifest may place a target anywhere via `path`" and walks up rather than assuming.
/// The callers resolving a target *forward* assumed the opposite.
///
/// **The fallback arms are the ones that matter.** Every can't-answer path must return
/// `Sources/<target>` — the pre-existing behaviour — because this resolves a directory a scan
/// then walks, and a wrong answer turns a working package into an empty scan that reports
/// *nothing to suggest* rather than an error. That is the same failure direction
/// `TargetIsolation.defaultIsolation` chose, for the same reason.
@Suite("Target sources resolve through the manifest, with the default as the fallback")
struct ProveThenShowSourcesReachTests {

    private func makePackage(manifest: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("layout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try manifest.write(
            to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8
        )
        return root
    }

    private func manifest(targetName: String, path: String?) -> String {
        let pathClause = path.map { ", path: \"\($0)\"" } ?? ""
        return """
        // swift-tools-version: 5.9
        import PackageDescription
        let package = Package(
            name: "Subject",
            targets: [.target(name: "\(targetName)"\(pathClause))]
        )
        """
    }

    @Test("a target declaring a custom path resolves to that path")
    func customPathIsHonoured() throws {
        // GRDB's shape, reduced: sources at repo root under a directory named for the target.
        let root = try makePackage(manifest: manifest(targetName: "Subject", path: "Subject"))
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Subject"), withIntermediateDirectories: true
        )

        let resolved = TargetIsolation.sourceDirectory(packageRoot: root, targetName: "Subject")

        #expect(resolved.lastPathComponent == "Subject")
        // The point of the fix: NOT under `Sources/`.
        #expect(!resolved.path.contains("/Sources/"))
    }

    @Test("a custom path nested more than one level deep resolves whole")
    func nestedCustomPathIsHonoured() throws {
        let root = try makePackage(
            manifest: manifest(targetName: "Subject", path: "Modules/Core/Subject")
        )
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(
            TargetIsolation.sourceDirectory(packageRoot: root, targetName: "Subject").path
                .hasSuffix("Modules/Core/Subject")
        )
    }

    @Test("a target with no declared path keeps the Sources default")
    func defaultLayoutIsUnchanged() throws {
        // The control. Every package in every previous run has this shape, so a regression
        // here is a regression everywhere at once.
        let root = try makePackage(manifest: manifest(targetName: "Subject", path: nil))
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(
            TargetIsolation.sourceDirectory(packageRoot: root, targetName: "Subject").path
                .hasSuffix("Sources/Subject")
        )
    }

    // MARK: - The fallback arms

    @Test("no manifest falls back to the Sources default")
    func missingManifestFallsBack() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("layout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(
            TargetIsolation.sourceDirectory(packageRoot: root, targetName: "Subject").path
                .hasSuffix("Sources/Subject")
        )
    }

    @Test("an unreadable manifest falls back rather than inventing a path")
    func brokenManifestFallsBack() throws {
        let root = try makePackage(manifest: "this is not a manifest {{{")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(
            TargetIsolation.sourceDirectory(packageRoot: root, targetName: "Subject").path
                .hasSuffix("Sources/Subject")
        )
    }

    @Test("a target the manifest does not declare falls back")
    func unknownTargetFallsBack() throws {
        // Asking for a target that is not there is a user error, and the honest response is
        // the default path — which then fails to scan and says so — not a guess.
        let root = try makePackage(manifest: manifest(targetName: "Other", path: "Other"))
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(
            TargetIsolation.sourceDirectory(packageRoot: root, targetName: "Subject").path
                .hasSuffix("Sources/Subject")
        )
    }
}

/// Reading a module back OUT of a path must consult the manifest too.
///
/// Fixing only the forward direction (`--target` → directory) made native GRDB **worse** than
/// the hand-staged arm: the scan reached all 307 picks and then every stub lost its
/// `@testable import GRDB`, trading *no such directory* for *cannot find type 'SQL' in scope*.
/// Proven went 5 → 2 and Inconclusive 24 → 39.
///
/// That is the day's recurring shape for the fifth time — a blocker that fires first hides
/// every blocker behind it — and here the second blocker was created by fixing the first.
@Suite("A module resolves back out of a path through the manifest")
struct VerifyTargetInferenceLayoutTests {

    private func makePackage(target: String, path: String?) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("infer-\(UUID().uuidString)")
        let clause = path.map { ", path: \"\($0)\"" } ?? ""
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
        // swift-tools-version: 5.9
        import PackageDescription
        let package = Package(
            name: "Subject",
            targets: [.target(name: "\(target)"\(clause))]
        )
        """.write(
            to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(path ?? "Sources/\(target)"),
            withIntermediateDirectories: true
        )
        return root
    }

    @Test("a file under a custom target path resolves to that target")
    func customPathResolvesBackToTheModule() throws {
        // GRDB's shape: sources at `<root>/GRDB/`, not `<root>/Sources/GRDB/`.
        let root = try makePackage(target: "GRDB", path: "GRDB")
        defer { try? FileManager.default.removeItem(at: root) }
        let location = root.appendingPathComponent("GRDB/Core/Row.swift").path + ":42"
        #expect(
            VerifyTargetInference.module(forLocation: location, packageRoot: root) == "GRDB"
        )
    }

    @Test("the conventional layout still resolves — the control")
    func conventionalLayoutUnchanged() throws {
        // Every package in every previous run has this shape. A regression here is a
        // regression everywhere, so this arm matters more than the one above.
        let root = try makePackage(target: "Core", path: nil)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = root.appendingPathComponent("Sources/Core/Thing.swift").path + ":7:3"
        #expect(
            VerifyTargetInference.module(forLocation: location, packageRoot: root) == "Core"
        )
    }

    @Test("a file in no declared target resolves to nothing, not to a guess")
    func fileOutsideAnyTargetIsNil() throws {
        let root = try makePackage(target: "GRDB", path: "GRDB")
        defer { try? FileManager.default.removeItem(at: root) }
        let location = root.appendingPathComponent("Scripts/gen.swift").path + ":1"
        #expect(VerifyTargetInference.module(forLocation: location, packageRoot: root) == nil)
    }

    @Test("with no manifest the path-shape rule still applies")
    func noManifestKeepsThePathShapeRule() throws {
        // The fallback that keeps every pre-existing corpus working when `dump-package`
        // cannot run at all.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("infer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources/Core"), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let location = root.appendingPathComponent("Sources/Core/Thing.swift").path + ":9"
        #expect(
            VerifyTargetInference.module(forLocation: location, packageRoot: root) == "Core"
        )
    }
}
