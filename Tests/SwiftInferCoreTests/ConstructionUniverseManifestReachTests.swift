import Foundation
import SwiftEffectInference
import Testing

@testable import SwiftInferCore

private typealias Wiring = ConstructionPurityWiringTests
private typealias Nested = ConstructionUniverseNestedPackageTests

/// **What else in a manifest reaches a package** — the shared spec's amendment 3b (O, P, Q), each
/// case the critic's fixture (`s6v`, `s6c`, `s7`, `s11`) rebuilt on disk: `App`'s `tokenCount`
/// constructs a `Tok` whose `id` mints a `UUID`, in a nested package only the rule under test
/// reaches. Every one advised `tokenCount` pure before; each must refute it.
@Suite("Construction universe — version-specific manifests, target paths, canonical locations")
struct ConstructionUniverseManifestReachTests {

    static let tok = """
    import Foundation
    public struct Tok { public let id = UUID(); public let n: Int; public init(n: Int) { self.n = n } }
    """

    static func app(importing module: String) -> String {
        "import \(module)\npublic func tokenCount(_ n: Int) -> Int {\n    Tok(n: n).n * 2\n}"
    }

    static func library(_ name: String) -> String {
        """
        // swift-tools-version:5.9
        import PackageDescription
        let package = Package(name: "\(name)", products: [.library(name: "\(name)", targets: ["\(name)"])], \
        targets: [.target(name: "\(name)")])
        """
    }

    static func rootManifest(tools: String = "5.9", dependencies: String = "", targets: String) -> String {
        """
        // swift-tools-version:\(tools)
        import PackageDescription
        let package = Package(name: "Root", dependencies: [\(dependencies)], targets: [\(targets)])
        """
    }

    static let appTarget = #".target(name: "App", dependencies: [.product(name: "A", package: "A")])"#

    /// `tokenCount`'s verdict on a scan of `Sources/App`, which is what `discover --target App` scans.
    static func tokenCount(in root: URL) throws -> PurityVerdict? {
        try Nested.verdict("tokenCount", scanning: root.appendingPathComponent("Sources/App"))
    }

    // MARK: - O: Package@swift-*.swift

    /// The critic's `s6v`: the plain manifest names no dependency, and `Package@swift-6.0.swift` —
    /// what a 6.x toolchain reads — names `Packages/A`. `s6c`, the same dependency in the plain
    /// manifest, is the control.
    @Test("a version-specific manifest's dependencies are the directory's too", arguments: ["s6v", "s6c"])
    func versionSpecificManifestIsRead(fixture: String) throws {
        let dependency = #".package(path: "Packages/A")"#
        var files = [
            "Packages/A/Package.swift": Self.library("A"),
            "Packages/A/Sources/A/Tok.swift": Self.tok,
            "Sources/App/App.swift": Self.app(importing: "A")
        ]
        if fixture == "s6v" {
            files["Package.swift"] = Self.rootManifest(targets: #".target(name: "App")"#)
            files["Package@swift-6.0.swift"] = Self.rootManifest(
                tools: "6.0", dependencies: dependency, targets: Self.appTarget
            )
        } else {
            files["Package.swift"] = Self.rootManifest(tools: "6.0", dependencies: dependency, targets: Self.appTarget)
        }
        let root = try Wiring.makePackage(files)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try Self.tokenCount(in: root) == .refuted, "\(fixture): `Packages/A` was not reached")
        // Every file that can move the bound is watched — the version-specific manifest too.
        let universe = ConstructionUniverse.universe(forScanOf: root.appendingPathComponent("Sources/App"))
        let watched = universe.manifests.map(\.lastPathComponent)
        #expect(watched.contains("Package@swift-6.0.swift") == (fixture == "s6v"), "\(watched)")
    }

    /// Doubt in any one manifest of a directory is doubt for the directory; a `Package@swift-*`
    /// file whose first line is no tools-version comment is no manifest, and says nothing.
    @Test("doubt in a version-specific manifest is doubt; a non-manifest one is ignored", arguments: [
        (
            "// swift-tools-version:6.0\nlet base = \"Demo\"\n"
                + "let package = Package(name: \"R\", dependencies: [.package(path: base)])",
            true
        ),
        ("let package = Package(name: \"R\", dependencies: [.package(path: \"Demo\")])", false)
    ])
    func versionSpecificDoubtIsDoubt(variant: String, demoIsIn: Bool) throws {
        let root = try Wiring.makePackage([
            "Package@swift-6.0.swift": variant,
            "Sources/Lib/Row.swift": Nested.row,
            "Demo/Package.swift": Nested.demoManifest,
            "Demo/Sources/Demo/main.swift": Nested.mintingRow
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appendingPathComponent("Sources/Lib")
        let paths = ConstructionUniverse.files(forScanOf: lib).map(\.relativePath)
        #expect(paths.contains("Demo/Sources/Demo/main.swift") == demoIsIn, "\(paths)")
        #expect(try Nested.verdict("make", scanning: lib) == (demoIsIn ? .refuted : .pure))
    }

    // MARK: - P: target paths

    /// The critic's `s7`: the root's own target `Core` has `path: "Core/Sources/Core"`, inside a
    /// directory that holds its own `Package.swift`. The root compiles those files as its target,
    /// but no `.package(path:)` names `Core/`, so the bound dropped them.
    @Test("a nested package holding a root target's path is reached")
    func targetPathInsideANestedPackageReachesIt() throws {
        let root = try Wiring.makePackage([
            "Package.swift": Self.rootManifest(
                targets: #".target(name: "Core", path: "Core/Sources/Core"), "#
                    + #".target(name: "App", dependencies: ["Core"])"#
            ),
            "Core/Package.swift": Self.library("Core"),
            "Core/Sources/Core/Tok.swift": Self.tok,
            "Sources/App/App.swift": Self.app(importing: "Core")
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try Self.tokenCount(in: root) == .refuted)
    }

    /// A target path is followed in every manifest the closure reaches, and a computed one is doubt.
    @Test("target paths are read across the closure, and a computed one is doubt")
    func targetPathsAcrossTheClosure() {
        let reached = Nested.compiled([
            "": #".package(path: "Packages/A")"#,
            "Packages/A": #".target(name: "X", path: "../C/Sources/X")"#,
            "Packages/C": ""
        ])
        #expect(reached == ["Packages/A", "Packages/C"])
        let doubt = Nested.compiled(["": #"let p = "Sources"; .target(name: "X", path: p)"#])
        #expect(doubt == ["Packages/A", "Packages/B", "Packages/C", "Demo", "Vendor/Lib"])
        // A path inside no nested package reaches none.
        #expect(Nested.compiled(["": #".target(name: "X", path: "Sources/X")"#]).isEmpty)
    }

    // MARK: - Q: canonical locations

    /// The critic's `s11`: `Packages/Core` is a symlink to `../Vendor/Core`. The walk never descends
    /// a symlink, so it found the package as `Vendor/Core`; the dependency names it as
    /// `Packages/Core`. Compared by spelling, the two never met.
    @Test("a dependency through a symlinked package directory reaches the walked package")
    func symlinkedPackageDirectoryReachesTheWalkedPackage() throws {
        let root = try Wiring.makePackage([
            "Package.swift": Self.rootManifest(
                dependencies: #".package(path: "Packages/Core")"#,
                targets: #".target(name: "App", dependencies: [.product(name: "Core", package: "Core")])"#
            ),
            "Vendor/Core/Package.swift": Self.library("Core"),
            "Vendor/Core/Sources/Core/Tok.swift": Self.tok,
            "Sources/App/App.swift": Self.app(importing: "Core")
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        try ConstructionUniverseSymlinkTests.link("Packages/Core", in: root, to: "../Vendor/Core")
        #expect(try Self.tokenCount(in: root) == .refuted)
    }
}
