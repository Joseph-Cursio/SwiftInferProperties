import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `TestTargetScope` — lifting is scoped to the test targets that could be
/// exercising the production target being scanned.
///
/// Closes the defect measured in `docs/measurements/roadtest-self-dogfood-2026-08-08.md`
/// §1: `discover --target X` resolved production code to `Sources/X/` but lifted
/// from `<package-root>/Tests/` wholesale, so the same lifted rows were attributed
/// to every target in the package. Strong-tier rows on this repo: **26 → 7**.
///
/// **The fallback arms are the ones that matter.** Getting the happy path wrong
/// shows up immediately; getting a fallback wrong silently switches lifting *off*
/// for a whole class of user, and a tool that suggests nothing looks exactly like a
/// tool with nothing to suggest. Every arm below that returns `nil` is asserted to
/// return `nil` rather than empty, and separately asserted to reach the old
/// whole-`Tests/` behaviour through the resolver.
@Suite("TestTargetScope — lifting is scoped by test-target dependency", .tags(.subprocess))
struct TestTargetScopeTests {

    // MARK: - Fixture
    //
    // A real, evaluable manifest, because the subject reads `swift package
    // dump-package` — a hand-written JSON stub would test the stub. The shape
    // mirrors this repo's own: a leaf (`Leaf`) nothing else depends on, a base
    // (`Base`) everything reaches, and a middle (`Mid`) that reaches `Base` so
    // `MidTests` reaches `Base` only TRANSITIVELY — the case a direct-dependency
    // rule would drop.
    //
    //   Base   <- BaseTests
    //   Mid    -> Base           <- MidTests   (reaches Base transitively)
    //   Leaf                     <- LeafTests  (reaches nothing else)

    private static let manifest = """
    // swift-tools-version: 5.9
    import PackageDescription

    let package = Package(
        name: "Fixture",
        targets: [
            .target(name: "Base"),
            .target(name: "Mid", dependencies: ["Base"]),
            .target(name: "Leaf"),
            .testTarget(name: "BaseTests", dependencies: ["Base"]),
            .testTarget(name: "MidTests", dependencies: ["Mid"]),
            .testTarget(name: "LeafTests", dependencies: ["Leaf"])
        ]
    )
    """

    private static func makePackage() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestTargetScope-\(UUID().uuidString)")
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        try manifest.write(
            to: base.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        for module in ["Base", "Mid", "Leaf"] {
            let directory = base.appendingPathComponent("Sources/\(module)")
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try "public struct \(module) {}\n".write(
                to: directory.appendingPathComponent("\(module).swift"),
                atomically: true,
                encoding: .utf8
            )
        }
        for suite in ["BaseTests", "MidTests", "LeafTests"] {
            let directory = base.appendingPathComponent("Tests/\(suite)")
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try "import Testing\n@Test func \(suite.lowercased())() {}\n".write(
                to: directory.appendingPathComponent("\(suite).swift"),
                atomically: true,
                encoding: .utf8
            )
        }
        return base
    }

    private static func names(_ urls: [URL]?) -> [String]? {
        urls?.map(\.lastPathComponent).sorted()
    }

    // MARK: - Scoping

    /// A leaf target is reached by its own test target and nothing else. This is the
    /// measured case: `SwiftInferKitEvidence` and `SwiftInferMacroImpl` each took
    /// **4 of 4** suggestions from other targets' tests before the fix.
    @Test("a leaf target is scoped to its own test target only")
    func leafTargetScopesToItsOwnTests() throws {
        let package = try Self.makePackage()
        defer { try? FileManager.default.removeItem(at: package) }
        #expect(
            Self.names(TestTargetScope.testDirectories(exercising: "Leaf", packageRoot: package))
                == ["LeafTests"]
        )
    }

    /// **Transitive reachability.** `MidTests` depends on `Mid`, which depends on
    /// `Base` — so `MidTests` may be exercising `Base` without declaring it. A
    /// direct-dependency rule would drop it, which is a false negative.
    @Test("a transitively-dependent test target is in scope")
    func transitiveDependencyIsInScope() throws {
        let package = try Self.makePackage()
        defer { try? FileManager.default.removeItem(at: package) }
        #expect(
            Self.names(TestTargetScope.testDirectories(exercising: "Base", packageRoot: package))
                == ["BaseTests", "MidTests"]
        )
    }

    /// The complement of the law above, and the one that makes the scoping mean
    /// anything: `LeafTests` is **excluded** from `Base`'s scope. Without this, a
    /// rule that returned every test target would pass the transitivity test.
    @Test("an unrelated test target is excluded")
    func unrelatedTestTargetIsExcluded() throws {
        let package = try Self.makePackage()
        defer { try? FileManager.default.removeItem(at: package) }
        let scoped = Self.names(
            TestTargetScope.testDirectories(exercising: "Base", packageRoot: package)
        )
        #expect(scoped?.contains("LeafTests") == false)
    }

    // MARK: - The fallback arms

    /// **An unknown module is `nil`, not `[]`.** `--sources` can point at any
    /// directory inside a package. Answering "no test target reaches it" would
    /// silently switch lifting off for every Xcode-project user; `nil` falls back to
    /// the pre-fix whole-`Tests/` behaviour.
    @Test("an unknown module answers nil, so the caller can fall back")
    func unknownModuleAnswersNil() throws {
        let package = try Self.makePackage()
        defer { try? FileManager.default.removeItem(at: package) }
        #expect(TestTargetScope.testDirectories(exercising: "NotATarget", packageRoot: package) == nil)
    }

    /// No manifest at all — `dump-package` fails and the answer is `nil`.
    @Test("a directory with no manifest answers nil")
    func missingManifestAnswersNil() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestTargetScope-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        #expect(TestTargetScope.testDirectories(exercising: "Base", packageRoot: base) == nil)
    }

    /// A declared test target whose directory does not exist is dropped rather than
    /// returned as a phantom scan root.
    @Test("a declared test target with no directory on disk is dropped")
    func missingTestDirectoryIsDropped() throws {
        let package = try Self.makePackage()
        defer { try? FileManager.default.removeItem(at: package) }
        try FileManager.default.removeItem(at: package.appendingPathComponent("Tests/LeafTests"))
        #expect(
            TestTargetScope.testDirectories(exercising: "Leaf", packageRoot: package)?.isEmpty == true
        )
    }

    // MARK: - The resolver's precedence

    /// The explicit `--test-dir` override wins and is **not** scoped — the user has
    /// said where to look, and second-guessing that would make the flag useless.
    @Test("explicit --test-dir wins over scoping")
    func explicitTestDirWinsOverScoping() throws {
        let package = try Self.makePackage()
        defer { try? FileManager.default.removeItem(at: package) }
        let override = package.appendingPathComponent("Tests/BaseTests")
        let resolved = SwiftInferCommand.Discover.effectiveTestDirectories(
            productionTarget: package.appendingPathComponent("Sources/Leaf"),
            explicitTestDir: override
        ) { _ in /* diagnostics are not the subject here */ }
        #expect(resolved.map(\.standardizedFileURL) == [override.standardizedFileURL])
    }

    /// End to end through the resolver: scanning `Leaf` yields only `LeafTests`.
    @Test("the resolver scopes a leaf target to its own tests")
    func resolverScopesLeafTarget() throws {
        let package = try Self.makePackage()
        defer { try? FileManager.default.removeItem(at: package) }
        let resolved = SwiftInferCommand.Discover.effectiveTestDirectories(
            productionTarget: package.appendingPathComponent("Sources/Leaf"),
            explicitTestDir: nil
        ) { _ in /* diagnostics are not the subject here */ }
        #expect(resolved.map(\.lastPathComponent) == ["LeafTests"])
    }

    /// **The fallback reaches the OLD behaviour, not silence.** A production
    /// directory that is not a declared target resolves to the whole `Tests/` tree —
    /// exactly what the resolver did before scoping existed.
    @Test("a non-target directory falls back to the whole Tests tree")
    func nonTargetDirectoryFallsBackToWholeTests() throws {
        let package = try Self.makePackage()
        defer { try? FileManager.default.removeItem(at: package) }
        let resolved = SwiftInferCommand.Discover.effectiveTestDirectories(
            productionTarget: package.appendingPathComponent("Sources/NotATarget"),
            explicitTestDir: nil
        ) { _ in /* diagnostics are not the subject here */ }
        #expect(
            resolved.map(\.standardizedFileURL)
                == [package.appendingPathComponent("Tests").standardizedFileURL]
        )
    }

    /// The degraded tmpdir arm: no `Package.swift` anywhere up the tree, so the
    /// production target itself is the scan root. Preserved from the singular
    /// resolver, and the reason many fixtures in this suite still lift anything.
    @Test("no package manifest degrades to scanning the production target")
    func noManifestDegradesToProductionTarget() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestTargetScope-bare-\(UUID().uuidString)")
        let target = base.appendingPathComponent("Loose")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let resolved = SwiftInferCommand.Discover.effectiveTestDirectories(
            productionTarget: target,
            explicitTestDir: nil
        ) { _ in /* diagnostics are not the subject here */ }
        #expect(resolved.map(\.standardizedFileURL) == [target.standardizedFileURL])
    }
}
