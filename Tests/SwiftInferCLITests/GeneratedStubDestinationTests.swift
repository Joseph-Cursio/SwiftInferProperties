import Foundation
@testable import SwiftInferCLI
import Testing

/// `discover --interactive` wrote every accepted file to `<packageRoot>/Tests/Generated/`,
/// which is inside **no SwiftPM target on any package** — so the file was compiled by
/// nothing and nothing said so (#414).
///
/// Each arm here builds a real package on disk and shells out to SwiftPM through
/// `TestTargetScope`, because the whole defect was a path composed without asking the
/// manifest; a fixture that stubs the manifest read would assert the convention this
/// exists to stop trusting.
@Suite("GeneratedStubDestination — where an accepted suggestion's file goes (#414)")
struct GeneratedStubDestinationTests {

    // MARK: - Derivation

    @Test("a conventional package resolves to its test target, not Tests/Generated")
    func conventionalPackageResolvesToTestTarget() throws {
        let root = try PackageFixture.make(
            name: "Demo",
            sourcePath: "Sources/Demo",
            testTargets: [("DemoTests", "Tests/DemoTests")]
        )
        defer { PackageFixture.remove(root) }

        let resolved = GeneratedStubDestination.resolve(
            packageRoot: root,
            scanDirectory: root.appendingPathComponent("Sources/Demo"),
            outputDirectoryOverride: nil
        )

        #expect(resolved.generatedRoot == root.appendingPathComponent("Tests/DemoTests/Generated"))
        #expect(resolved.compiledWhereItSits)
        #expect(resolved.note.contains("DemoTests"))
    }

    /// The Xcode-originated layout #414 was found on: targets rooted at `<Name>/` and
    /// `<Name>Tests/`, with nothing at `Tests/` at all.
    @Test("a manifest-relocated test target is found where the manifest puts it")
    func relocatedTestTargetIsHonoured() throws {
        let root = try PackageFixture.make(
            name: "Demo",
            sourcePath: "Demo",
            testTargets: [("DemoTests", "DemoTests")]
        )
        defer { PackageFixture.remove(root) }

        let resolved = GeneratedStubDestination.resolve(
            packageRoot: root,
            scanDirectory: root.appendingPathComponent("Demo"),
            outputDirectoryOverride: nil
        )

        #expect(resolved.generatedRoot == root.appendingPathComponent("DemoTests/Generated"))
        #expect(resolved.compiledWhereItSits)
    }

    /// The tie-break that matters. Sorting by path alone picks `DemoIntegrationTests`,
    /// which is the wrong answer on the real subject (SwiftMarkdownWiki declares exactly
    /// this shape and both of its test targets depend on the scanned module).
    @Test("several reaching test targets pick <Module>Tests and name the alternatives")
    func ambiguityPicksConventionalNameAndDisclosesTheRest() throws {
        let root = try PackageFixture.make(
            name: "Demo",
            sourcePath: "Sources/Demo",
            testTargets: [
                ("DemoTests", "Tests/DemoTests"),
                ("DemoIntegrationTests", "Tests/DemoIntegrationTests")
            ]
        )
        defer { PackageFixture.remove(root) }

        let resolved = GeneratedStubDestination.resolve(
            packageRoot: root,
            scanDirectory: root.appendingPathComponent("Sources/Demo"),
            outputDirectoryOverride: nil
        )

        #expect(resolved.generatedRoot == root.appendingPathComponent("Tests/DemoTests/Generated"))
        #expect(resolved.note.contains("DemoIntegrationTests"))
        #expect(resolved.note.contains("--output-dir"))
    }

    // MARK: - The arms that cannot derive

    /// Behaviour is unchanged from before #414 — the *note* is the whole of the fix here.
    @Test("a package with no test target keeps the old path and says nothing builds it")
    func noTestTargetFallsBackAndSaysSo() throws {
        let root = try PackageFixture.make(
            name: "Demo",
            sourcePath: "Sources/Demo",
            testTargets: []
        )
        defer { PackageFixture.remove(root) }

        let resolved = GeneratedStubDestination.resolve(
            packageRoot: root,
            scanDirectory: root.appendingPathComponent("Sources/Demo"),
            outputDirectoryOverride: nil
        )

        #expect(resolved.generatedRoot == root.appendingPathComponent("Tests/Generated"))
        #expect(!resolved.compiledWhereItSits)
        #expect(resolved.note.contains("NO SwiftPM target builds"))
    }

    @Test("no manifest keeps the old path and says nothing builds it")
    func missingManifestFallsBackAndSaysSo() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GSD-NoManifest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { PackageFixture.remove(root) }

        let resolved = GeneratedStubDestination.resolve(
            packageRoot: root,
            scanDirectory: root,
            outputDirectoryOverride: nil
        )

        #expect(resolved.generatedRoot == root.appendingPathComponent("Tests/Generated"))
        #expect(!resolved.compiledWhereItSits)
        #expect(resolved.note.contains("no Package.swift"))
    }

    // MARK: - Override

    /// `--output-dir` wins without consulting the manifest, which is the point of it: the
    /// manifest narrows to several candidates on a real package and cannot pick.
    @Test("--output-dir wins over a derivable destination")
    func overrideWinsOverDerivation() throws {
        let root = try PackageFixture.make(
            name: "Demo",
            sourcePath: "Sources/Demo",
            testTargets: [("DemoTests", "Tests/DemoTests")]
        )
        defer { PackageFixture.remove(root) }
        let chosen = root.appendingPathComponent("Tests/DemoTests/Elsewhere")

        let resolved = GeneratedStubDestination.resolve(
            packageRoot: root,
            scanDirectory: root.appendingPathComponent("Sources/Demo"),
            outputDirectoryOverride: chosen
        )

        #expect(resolved.generatedRoot == chosen.standardizedFileURL)
        #expect(resolved.note.contains("--output-dir"))
    }

    // MARK: - Module resolution

    @Test("the scanned module is read from the manifest, not from the path shape")
    func moduleComesFromTheManifest() throws {
        let root = try PackageFixture.make(
            name: "Demo",
            sourcePath: "Demo",
            testTargets: [("DemoTests", "DemoTests")]
        )
        defer { PackageFixture.remove(root) }

        let module = GeneratedStubDestination.module(
            forScanDirectory: root.appendingPathComponent("Demo"),
            packageRoot: root
        )

        #expect(module == "Demo")
    }

    @Test("a scan directory inside no declared target resolves to no module")
    func unknownScanDirectoryResolvesToNil() throws {
        let root = try PackageFixture.make(
            name: "Demo",
            sourcePath: "Sources/Demo",
            testTargets: [("DemoTests", "Tests/DemoTests")]
        )
        defer { PackageFixture.remove(root) }
        let stray = root.appendingPathComponent("Scratch")
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)

        #expect(GeneratedStubDestination.module(forScanDirectory: stray, packageRoot: root) == nil)
    }
}

/// A real package on disk — manifest, one source target, zero or more test targets, each at
/// whatever path the caller names.
enum PackageFixture {

    static func make(
        name: String,
        sourcePath: String,
        testTargets: [(name: String, path: String)]
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GSD-\(name)-\(UUID().uuidString)")
        let sources = root.appendingPathComponent(sourcePath)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try "public func demo() {}\n"
            .write(to: sources.appendingPathComponent("Demo.swift"), atomically: true, encoding: .utf8)
        for target in testTargets {
            let directory = root.appendingPathComponent(target.path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "import Testing\n"
                .write(to: directory.appendingPathComponent("T.swift"), atomically: true, encoding: .utf8)
        }
        try manifest(name: name, sourcePath: sourcePath, testTargets: testTargets)
            .write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        return root
    }

    static func remove(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    private static func manifest(
        name: String,
        sourcePath: String,
        testTargets: [(name: String, path: String)]
    ) -> String {
        let tests = testTargets
            .map { target in
                "        .testTarget(name: \"\(target.name)\", dependencies: [\"\(name)\"],"
                    + " path: \"\(target.path)\")"
            }
            .joined(separator: ",\n")
        let targets = tests.isEmpty
            ? "        .target(name: \"\(name)\", path: \"\(sourcePath)\")"
            : "        .target(name: \"\(name)\", path: \"\(sourcePath)\"),\n\(tests)"
        return """
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(
                name: "\(name)",
                targets: [
            \(targets)
                ]
            )

            """
    }
}
