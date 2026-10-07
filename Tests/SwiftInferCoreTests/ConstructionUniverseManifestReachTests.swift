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

    /// A directory's version-specific manifests are read whatever its `Package.swift` is — the
    /// directory is a package by `Package.swift` alone, and its references are every manifest's —
    /// as SwiftProjectLint reads them: a dependency on `Bridge/`, which holds only a
    /// `Package@swift-6.0.swift` naming `../Packages/A`, reaches `A`.
    @Test("a version-specific manifest is read where Package.swift is none")
    func versionSpecificManifestWithoutPackageSwiftIsRead() throws {
        let root = try Wiring.makePackage([
            "Package.swift": Self.rootManifest(dependencies: #".package(path: "Bridge")"#, targets: Self.appTarget),
            "Bridge/Package@swift-6.0.swift": Self.rootManifest(
                tools: "6.0", dependencies: #".package(path: "../Packages/A")"#, targets: ""
            ),
            "Packages/A/Package.swift": Self.library("A"),
            "Packages/A/Sources/A/Tok.swift": Self.tok,
            "Sources/App/App.swift": Self.app(importing: "A")
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try Self.tokenCount(in: root) == .refuted)
        #expect(!ConstructionUniverse.holdsManifest(root.appendingPathComponent("Bridge")), "Bridge/ is no package")
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

    /// A package under `Tests/` is a nested package — the walk enters a test directory for the
    /// packages it holds, as SwiftProjectLint's walk does — so a target path into one reaches it,
    /// and its own dependencies with it. Pruned at `Tests/`, the walk never recorded `Tests/Fixture`,
    /// the target path reached nothing, and the two consumers bounded one root two ways.
    @Test("a nested package under Tests/ is one the closure can reach")
    func packageUnderTestsIsANestedPackage() throws {
        let root = try Wiring.makePackage([
            "Package.swift": Self.rootManifest(
                targets: #".target(name: "F", path: "Tests/Fixture/Sources/F"), "#
                    + #".target(name: "App", dependencies: ["F"])"#
            ),
            "Tests/Fixture/Package.swift": Nested.manifest(dependingOn: "../../Packages/A"),
            "Tests/Fixture/Sources/F/F.swift": "public struct F {}",
            "Packages/A/Package.swift": Self.library("A"),
            "Packages/A/Sources/A/Tok.swift": Self.tok,
            "Sources/App/App.swift": Self.app(importing: "A")
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let universe = ConstructionUniverse.universe(forScanOf: root.appendingPathComponent("Sources/App"))
        #expect(universe.members.map(\.relativePath) == ["Packages/A/Sources/A/Tok.swift", "Sources/App/App.swift"])
        #expect(try Self.tokenCount(in: root) == .refuted)
    }

    /// The shared spec's amendment T, the final review's `f11`: a target whose path HOLDS a nested
    /// package compiles that package's sources — `swift package describe` and `swift build` show
    /// `.target(name: "All", path: "Packages", exclude: ["A/Package.swift"])` building
    /// `Packages/A/Sources/A` into `All`. The bound looked for a package holding `Packages`, found
    /// none, and `A`'s UUID-minting `Tok` left the table.
    @Test("a target whose path holds a nested package reaches it")
    func targetPathOverANestedPackageReachesIt() throws {
        let root = try Wiring.makePackage([
            "Package.swift": Self.rootManifest(
                targets: #".target(name: "All", path: "Packages", exclude: ["A/Package.swift"])"#
            ),
            "Packages/A/Package.swift": Self.library("A"),
            "Packages/A/Sources/A/Tok.swift": Self.tok,
            "Packages/Loose/L.swift": "struct Loose { let n: Int }",
            "Sources/App/App.swift": Self.app(importing: "All")
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Sources/App")
        let paths = ConstructionUniverse.files(forScanOf: app).map(\.relativePath)
        #expect(paths.contains("Packages/A/Sources/A/Tok.swift"), "\(paths)")
        #expect(try Self.tokenCount(in: root) == .refuted)
    }

    /// The shared spec's amendment T′: a root target whose `path:` is `"."` compiles everything
    /// below the root, every nested package's sources included. `"."` resolves to the root, `""`,
    /// and `package.hasPrefix("" + "/")` is false, so before T′'s `location.isEmpty ||` it reached
    /// none of them — here `Packages/A`, which nothing else names, and its UUID-minting `Tok`.
    @Test("a root target with path \".\" reaches every nested package")
    func rootTargetPathReachesEveryNestedPackage() throws {
        let root = try Wiring.makePackage([
            "Package.swift": Self.rootManifest(targets: #".target(name: "App", path: ".")"#),
            "Packages/A/Package.swift": Self.library("A"),
            "Packages/A/Sources/A/Tok.swift": Self.tok,
            "Sources/App/App.swift": Self.app(importing: "A")
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Sources/App")
        let paths = ConstructionUniverse.files(forScanOf: app).map(\.relativePath)
        #expect(paths.contains("Packages/A/Sources/A/Tok.swift"), "\(paths)")
        #expect(try Self.tokenCount(in: root) == .refuted)
        // In memory: `"."` from the root reaches every walked package, with each one's closure.
        let packages: Set<String> = ["Packages/A", "Packages/B", "Demo"]
        #expect(Nested.compiled(
            ["": #".target(name: "App", path: ".")"#, "Packages/A": "", "Packages/B": "", "Demo": ""],
            packages: packages
        ) == packages)
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
        // A path inside no nested package, and holding none, reaches none.
        #expect(Nested.compiled(["": #".target(name: "X", path: "Sources/X")"#]).isEmpty)
        // Amendment T: `Packages` lies in no package but holds three, and SwiftPM compiles their
        // sources into `All`; `Packages/C`'s closure brings `Demo`. A path is matched by component:
        // `Pack` holds nothing.
        #expect(Nested.compiled([
            "": #"[.target(name: "All", path: "Packages")]"#,
            "Packages/A": "", "Packages/B": "", "Packages/C": #".package(path: "../../Demo")"#, "Demo": ""
        ]) == ["Packages/A", "Packages/B", "Packages/C", "Demo"])
        #expect(Nested.compiled(["": #".target(name: "X", path: "Pack")"#]).isEmpty)
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
