import Foundation
@testable import SwiftInferCLI
import Testing

/// **`--target` derived from the entry, which is where it was always available.**
///
/// The flag decides whether the verifier path-depends on the user's package and
/// `@testable`-imports the module — so without it, no law can reach a carrier or function the user
/// defined. It was optional and its absence was silent, and the measured cost was an entire
/// survey: `verify --all-from-index` over this repo returned 114 `build-failed` and zero verdicts.
/// The help text had claimed the target "resolves from the SemanticIndex entry" since v1.149; the
/// entry carried an absolute path the whole time and nothing read it.
///
/// These build a real directory tree rather than stubbing a file system, because the property
/// under test is *the directory is actually there* — the guard that separates a module name from
/// a string that merely looks like one. A mock would agree with whatever the parser produced.
@Suite("Verify target inference — module from an entry's source path")
struct VerifyTargetInferenceTests {

    /// A throwaway package root with `Sources/<modules>/` laid out under it.
    private func makePackage(modules: [String]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("verify-target-\(UUID().uuidString)")
        for module in modules {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("Sources").appendingPathComponent(module),
                withIntermediateDirectories: true
            )
        }
        return root
    }

    private func location(_ root: URL, _ relative: String, line: Int = 12) -> String {
        "\(root.appendingPathComponent(relative).path):\(line)"
    }

    @Test func derivesTheModuleFromAConventionalLayout() throws {
        let root = try makePackage(modules: ["SwiftInferCore"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(
            VerifyTargetInference.module(
                forLocation: location(root, "Sources/SwiftInferCore/Refutability.swift"),
                packageRoot: root
            ) == "SwiftInferCore"
        )
    }

    /// Nested directories inside the target are common and must not change the answer — the
    /// module is the FIRST component under `Sources/`, not the last directory before the file.
    @Test func aFileNestedInsideTheTargetStillNamesTheTarget() throws {
        let root = try makePackage(modules: ["Core"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(
            VerifyTargetInference.module(
                forLocation: location(root, "Sources/Core/Deep/Deeper/File.swift"),
                packageRoot: root
            ) == "Core"
        )
    }

    /// A name parsed out of a path is a guess until the disk agrees. `TargetDirectory.resolve`
    /// makes the same check in the forward direction, and for the same reason: a plausible name
    /// that resolves to nothing produces a `.product` no manifest declares.
    @Test func aModuleDirectoryThatDoesNotExistIsNotInferred() throws {
        let root = try makePackage(modules: ["Real"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(
            VerifyTargetInference.module(
                forLocation: location(root, "Sources/Imaginary/File.swift"),
                packageRoot: root
            ) == nil
        )
    }

    /// A file sitting directly in `Sources/` belongs to no target directory.
    @Test func aFileDirectlyUnderSourcesHasNoModule() throws {
        let root = try makePackage(modules: ["Core"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(
            VerifyTargetInference.module(
                forLocation: location(root, "Sources/main.swift"),
                packageRoot: root
            ) == nil
        )
    }

    @Test func aPathOutsideThePackageIsNotInferred() throws {
        let root = try makePackage(modules: ["Core"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(
            VerifyTargetInference.module(
                forLocation: "/somewhere/else/Sources/Core/File.swift:3",
                packageRoot: root
            ) == nil
        )
    }

    /// `Tests/` is not `Sources/`, and a test target cannot be imported as a library product.
    @Test func aTestTargetIsNotInferred() throws {
        let root = try makePackage(modules: ["Core"])
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Tests").appendingPathComponent("CoreTests"),
            withIntermediateDirectories: true
        )
        #expect(
            VerifyTargetInference.module(
                forLocation: location(root, "Tests/CoreTests/File.swift"),
                packageRoot: root
            ) == nil
        )
    }

    /// A nested package is declined deliberately, not by accident. The wiring this feeds
    /// path-depends on `packageRoot` and resolves the product from *its* manifest, so naming a
    /// module the outer manifest never declares trades "cannot find type" for "no such product" —
    /// both fail, and only the first points at the real problem.
    @Test func aModuleInsideANestedPackageIsDeclined() throws {
        let root = try makePackage(modules: [])
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root
            .appendingPathComponent("Packages/Sub/Sources/Nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        #expect(
            VerifyTargetInference.module(
                forLocation: location(root, "Packages/Sub/Sources/Nested/File.swift"),
                packageRoot: root
            ) == nil
        )
    }

    /// A dependency's own `Sources/` is not this package's target, and the curated-corpus fixtures
    /// depend on it: `fixtures/cycle27-surface`'s 53 entries all point into
    /// `.build/checkouts/swift-collections/Sources/…`. Requiring `Sources/` to be a **direct**
    /// child of the package root excludes them for free, which is why derivation could be added to
    /// the survey path without disturbing the corpus runs that pass no `--corpus-module`.
    @Test func aDependencyCheckoutIsNotThisPackagesTarget() throws {
        let root = try makePackage(modules: ["Core"])
        defer { try? FileManager.default.removeItem(at: root) }
        let checkout = root
            .appendingPathComponent(".build/checkouts/swift-collections/Sources/OrderedCollections")
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        #expect(
            VerifyTargetInference.module(
                forLocation: location(
                    root,
                    ".build/checkouts/swift-collections/Sources/OrderedCollections/Set.swift"
                ),
                packageRoot: root
            ) == nil
        )
    }

    // MARK: - Location suffix parsing

    @Test func aLineSuffixIsStripped() {
        #expect(
            VerifyTargetInference.sourcePath(from: "/a/b/File.swift:124") == "/a/b/File.swift"
        )
    }

    @Test func aLineAndColumnSuffixAreStripped() {
        #expect(
            VerifyTargetInference.sourcePath(from: "/a/b/File.swift:124:7") == "/a/b/File.swift"
        )
    }

    @Test func aPathWithNoSuffixIsUnchanged() {
        #expect(VerifyTargetInference.sourcePath(from: "/a/b/File.swift") == "/a/b/File.swift")
    }

    /// Only entirely-numeric trailing components are dropped. Splitting on the first colon would
    /// truncate any path that contains one, and a wrong path resolves to a wrong module or to nil
    /// — neither of which announces itself.
    @Test func aColonInThePathIsNotMistakenForALineNumber() {
        let path = "/a/od:d/File.swift"
        #expect(VerifyTargetInference.sourcePath(from: path) == path)
        #expect(VerifyTargetInference.sourcePath(from: path + ":9") == path)
    }

    /// Stops at two, so a directory named for a number cannot be eaten by the same loop.
    @Test func onlyTwoNumericComponentsAreStripped() {
        #expect(
            VerifyTargetInference.sourcePath(from: "/a/1:2:3:4") == "/a/1:2"
        )
    }

    /// The end-to-end claim, on THIS package: the entry for a real source file resolves to the
    /// module that owns it, with no flag passed.
    @Test func thisRepositoryResolvesItsOwnModule() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftInferCLITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
        let entryLocation = root
            .appendingPathComponent("Sources/SwiftInferCore/Refutability.swift")
            .path + ":124"
        #expect(
            VerifyTargetInference.module(forLocation: entryLocation, packageRoot: root)
                == "SwiftInferCore"
        )
    }
}
