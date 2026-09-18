import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `Sources/<name>` is SwiftPM's default for a `.target`; a `.testTarget` defaults to
/// `Tests/<name>`. Reporting the first for both named a directory that does not exist, so no
/// consumer could resolve a file under `Tests/` (SwiftInferProperties#521).
///
/// **Each consumer was correct BY ACCIDENT, and the accident is now a stated scope.** Both
/// module-resolving consumers confirm the directory on disk, so the bogus `Sources/<TestName>`
/// was rejected before it could answer. Now that the map is right, each one has to choose its
/// population — and they do not choose the same one:
///
/// - a subject's **module** wants regular targets only, because a test target is not something
///   a stub can `@testable import`, and a subject inside one needs no import at all;
/// - a subject's **isolation** wants every target, because the compiler applies a test target's
///   `.defaultIsolation` exactly as it applies a library target's.
@Suite("Manifest target directories — the test-target default")
struct TestTargetDirectoryDefaultTests {

    /// A package with one regular and one test target, neither declaring `path:`.
    static func makePackage(isolated: Bool) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tt-\(UUID().uuidString)")
        let settings = isolated
            ? ",\n            swiftSettings: [.defaultIsolation(MainActor.self)]"
            : ""
        for relative in ["Sources/Core", "Tests/CoreTests"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(relative), withIntermediateDirectories: true
            )
            try "public struct Placeholder { public init() {} }".write(
                to: root.appendingPathComponent(relative).appendingPathComponent("P.swift"),
                atomically: true, encoding: .utf8
            )
        }
        try """
        // swift-tools-version: 6.2
        import PackageDescription

        let package = Package(
            name: "TT",
            targets: [
                .target(
                    name: "Core"\(settings)
                ),
                .testTarget(
                    name: "CoreTests",
                    dependencies: ["Core"]\(settings)
                )
            ]
        )
        """.write(
            to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8
        )
        return root
    }

    // MARK: - The map

    @Test("a test target defaults to Tests/<name>, a regular one to Sources/<name>")
    func defaultsFollowTheKind() throws {
        let root = try Self.makePackage(isolated: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let declared = TargetIsolation.declaredTargetDirectories(packageRoot: root)
        let core = try #require(declared.first { $0.name == "Core" })
        let tests = try #require(declared.first { $0.name == "CoreTests" })

        #expect(core.path == "Sources/Core")
        #expect(core.isTest == false)
        // The defect: this read "Sources/CoreTests", a directory no package has.
        #expect(tests.path == "Tests/CoreTests")
        #expect(tests.isTest == true)
    }

    // MARK: - Isolation takes every target

    /// The gap #482 could not close: a subject in a MainActor-default TEST target.
    @Test("isolation resolves a file inside a test target")
    func isolationReachesTestTargets() throws {
        let root = try Self.makePackage(isolated: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let inTests = root.appendingPathComponent("Tests/CoreTests/P.swift").path
        let inSources = root.appendingPathComponent("Sources/Core/P.swift").path

        #expect(TargetIsolation.defaultIsolation(forFile: inTests) == "MainActor")
        #expect(TargetIsolation.defaultIsolation(forFile: inSources) == "MainActor")
    }

    @Test("a test target with no isolation setting still answers nil")
    func plainTestTargetIsUntouched() throws {
        let root = try Self.makePackage(isolated: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let inTests = root.appendingPathComponent("Tests/CoreTests/P.swift").path
        #expect(TargetIsolation.defaultIsolation(forFile: inTests) == nil)
    }

    // MARK: - Module resolution keeps regular targets only

    /// **The scope pin.** Deleting either `!$0.isTest` filter makes this go red, which is the
    /// point: with the map corrected, a `Tests/` directory now *would* resolve, and the answer
    /// would be a module name no stub can import.
    @Test("a scan directory inside a test target resolves to NO module")
    func moduleResolutionSkipsTestTargets() throws {
        let root = try Self.makePackage(isolated: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let testsDirectory = root.appendingPathComponent("Tests/CoreTests")
        #expect(
            GeneratedStubDestination.module(forScanDirectory: testsDirectory, packageRoot: root)
                == nil,
            """
            A scan directory inside a test target resolved to a module name. `rankedCandidates` \
            would then look for test targets exercising `CoreTests` and prefer `CoreTestsTests`.
            """
        )
    }

    @Test("control — a scan directory inside a regular target still resolves")
    func moduleResolutionStillWorks() throws {
        let root = try Self.makePackage(isolated: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let sources = root.appendingPathComponent("Sources/Core")
        #expect(
            GeneratedStubDestination.module(forScanDirectory: sources, packageRoot: root) == "Core"
        )
    }

    @Test("a subject under Tests/ resolves to no module for the verify import either")
    func verifyImportSkipsTestTargets() throws {
        let root = try Self.makePackage(isolated: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let location = root.appendingPathComponent("Tests/CoreTests/P.swift").path + ":4:1"
        #expect(VerifyTargetInference.module(forLocation: location, packageRoot: root) == nil)
    }

    // MARK: - Looking a target up BY NAME does take test targets

    /// Asked for a target by name, answering where it actually lives is right — and before #521
    /// this reported `Sources/CoreTests`, failed its on-disk check, and said *target not found*.
    @Test("--target naming a test target now resolves to its real directory")
    func targetLookupResolvesTestTargets() throws {
        let root = try Self.makePackage(isolated: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let resolved = TargetDirectory.manifestDirectory(for: "CoreTests", packageRoot: root)
        #expect(
            resolved?.standardizedFileURL.path
                == root.appendingPathComponent("Tests/CoreTests").standardizedFileURL.path
        )
    }
}
