import Foundation
import Testing

@testable import SwiftInferCore

/// Which nested packages the universe takes: those the root compiles — the shared spec's
/// amendment B. The pure half mirrors SwiftProjectLint's `ConstructionUniverseNestedPackageTests`
/// case for case (the manifest reader's own cases are the shared JSON's, in
/// `ConstructionUniverseCasesTests`); the on-disk half drives the scan, so a bound computed and
/// then ignored is caught where the verdict is.
@Suite("Construction universe — the nested-package bound")
struct ConstructionUniverseNestedPackageTests {

    // MARK: - Reading a manifest

    @Test("a whole manifest: literals in source order, comments and other paths ignored")
    func wholeManifest() {
        let manifest = """
        // swift-tools-version:6.2
        import PackageDescription

        // .package(path: "Retired"),
        let package = Package(
            name: "App",
            dependencies: [
                .package(path: "Packages/Models"),
                .package(url: "https://github.com/x/y.git", from: "1.0.0"),
                Package.Dependency.package(name: "Engine", path: "./Packages/Engine/")
            ],
            targets: [
                .executableTarget(name: "App", dependencies: ["Models"], path: "Sources/App"),
                .testTarget(name: "AppTests", path: "Tests/AppTests")
            ]
        )
        """
        #expect(ConstructionUniverse.localPackageDependencies(manifest: manifest) == [
            "Packages/Models", "./Packages/Engine/"
        ])
    }

    @Test("an interpolated or computed path is doubt", arguments: [
        #".package(path: "\(root)/Core")"#,
        ".package(path: localPath)",
        #".package(name: "Core", path: ("Core"))"#,
    ])
    func computedPathIsDoubt(manifest: String) {
        #expect(ConstructionUniverse.localPackageDependencies(manifest: manifest) == nil)
    }

    /// A manifest with a function whose `else if` chain has `arms` arms, depending on `../Leaf`.
    static func deepManifest(arms: Int) -> String {
        var chain = "if n == 0 { return 0 }"
        for arm in 1..<arms { chain += " else if n == \(arm) { return \(arm) }" }
        return """
        // swift-tools-version:5.9
        import PackageDescription
        func pick(_ n: Int) -> Int { \(chain) else { return -1 } }
        let package = Package(name: "Dep", dependencies: [.package(path: "../Leaf")])
        """
    }

    /// The shared spec's amendment K. A nested package's manifest holding a 1,000-arm `else if`
    /// chain `SIGBUS`ed `discover` — the parse and the visitor's walk recurse per arm, and the CLI,
    /// like this test, runs on a ~512 KB cooperative stack. The universe runs the closure on a large
    /// stack; 3,000 arms, so this test kills its own process when it runs on the caller's again.
    @Test("a manifest that nests deep is read on a large stack")
    func deepManifestIsReadOnALargeStack() throws {
        let root = try ConstructionPurityWiringTests.makePackage([
            "Package.swift": Self.manifest(dependingOn: "Packages/Dep"),
            "Packages/Dep/Package.swift": Self.deepManifest(arms: 3_000),
            "Packages/Leaf/Package.swift": Self.demoManifest,
            "Packages/Leaf/Sources/Leaf/Row.swift": Self.mintingRow,
            "Sources/Lib/Row.swift": Self.row,
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appendingPathComponent("Sources/Lib")
        let paths = ConstructionUniverse.files(forScanOf: lib).map(\.relativePath)
        #expect(paths == ["Packages/Leaf/Sources/Leaf/Row.swift", "Sources/Lib/Row.swift"])
    }

    // MARK: - The closure

    private static let packages: Set<String> = ["Packages/A", "Packages/B", "Packages/C", "Demo", "Vendor/Lib"]

    /// The closure over an in-memory tree: a directory in `manifests` holds that text; the root
    /// and a package of `packages` with no entry hold a manifest that cannot be read; anything else
    /// holds none — `[.absent]`, as `manifests(inDirectory:)` answers for a directory on disk.
    static func compiled(
        _ manifests: [String: String],
        packages: Set<String> = Self.packages,
        reported: Set<String> = [],
        rootHasManifest: Bool = true
    ) -> Set<String> {
        ConstructionUniverse.compiledNestedPackages(
            packages,
            reported: reported,
            rootHasManifest: rootHasManifest,
            rootPath: "/work/App",
            resolvingSymlinks: { $0 },
            manifests: { directory in
                if let text = manifests[directory] { return [.text(text)] }
                return directory.isEmpty || packages.contains(directory) ? [.unreadable] : [.absent]
            }
        )
    }

    @Test("the root's local path dependencies, followed transitively")
    func transitiveClosure() {
        let reached = Self.compiled([
            "": #".package(path: "Packages/A")"#,
            "Packages/A": #".package(path: "../B")"#,
            "Packages/B": #".package(url: "https://x/y.git", from: "1.0.0")"#,
            "Packages/C": #".package(path: "../../Demo")"#,
        ])
        // C depends on Demo, but nothing the root compiles depends on C.
        #expect(reached == ["Packages/A", "Packages/B"])
    }

    @Test("paths are standardised as absolute paths and kept only under the root")
    func pathsAreStandardisedAgainstTheRoot() {
        let reached = Self.compiled([
            "": """
            let dependencies: [Package.Dependency] = [
                .package(path: "/work/App/Vendor/./Lib"),
                .package(path: "/elsewhere/Demo"),
                .package(path: "../Outside"),
                .package(path: "../App/Demo"),
                .package(path: "./Packages/A/../C/")
            ]
            """,
            "Vendor/Lib": "", "Demo": "", "Packages/C": "",
        ])
        // `../App/Demo` climbs out and back in: it names `/work/App/Demo`, which is under the root.
        #expect(reached == ["Vendor/Lib", "Demo", "Packages/C"])
    }

    @Test("doubt anywhere in the closure includes every nested package")
    func doubtIncludesAll() {
        let computed = Self.compiled([
            "": #".package(path: "Packages/A")"#,
            "Packages/A": ".package(path: siblingPath)",
        ])
        #expect(computed == Self.packages)
        // A manifest the closure reaches but cannot read is doubt too.
        let unreadable = Self.compiled(["": #".package(path: "Packages/A")"#])
        #expect(unreadable == Self.packages)
        // Doubt outside the closure is not: nothing the root compiles reads that manifest.
        let unreached = Self.compiled([
            "": #".package(path: "Packages/A")"#, "Packages/A": "", "Demo": ".package(path: p)"
        ])
        #expect(unreached == ["Packages/A"])
    }

    /// Amendment I: a dependency on a directory that holds no manifest passes nothing on, and is
    /// no doubt — SwiftPM would refuse the package, but nothing here says what it compiles.
    @Test("a dependency on a directory with no manifest passes nothing on, and is no doubt")
    func dependencyOnNoManifestIsNoDoubt() {
        let root = #"let dependencies = [.package(path: "Nowhere"), .package(path: "Packages/A")]"#
        #expect(Self.compiled(["": root, "Packages/A": ""]) == ["Packages/A"])
    }

    /// Amendment J: a package the run judges is reached with its own closure, whatever the root
    /// names; one the root already compiles adds nothing.
    @Test("a judged package is reached, with its own closure")
    func judgedPackageSeedsTheClosure() {
        let manifests = ["": "", "Demo": #".package(path: "../Packages/C")"#, "Packages/C": "", "Packages/A": ""]
        #expect(Self.compiled(manifests).isEmpty)
        #expect(Self.compiled(manifests, reported: ["Demo"]) == ["Demo", "Packages/C"])
        #expect(Self.compiled(["": #".package(path: "Packages/A")"#, "Packages/A": ""], reported: ["Packages/A"])
            == ["Packages/A"])
    }

    @Test("a root with no manifest includes every nested package")
    func noRootManifestIncludesAll() {
        #expect(Self.compiled([:], rootHasManifest: false) == Self.packages)
    }

    @Test("a file belongs to the nearest package above it, or to the root's own")
    func nearestPackageWins() {
        let packagePaths: Set<String> = ["A", "A/B"]
        #expect(ConstructionUniverse.owningPackage(of: "A/B/Sources/X.swift", among: packagePaths) == "A/B")
        #expect(ConstructionUniverse.owningPackage(of: "A/Sources/X.swift", among: packagePaths) == "A")
        #expect(ConstructionUniverse.owningPackage(of: "AB/Sources/X.swift", among: packagePaths) == nil)
        #expect(ConstructionUniverse.owningPackage(of: "Sources/X.swift", among: packagePaths) == nil)
        #expect(ConstructionUniverse.owningPackage(of: "A", among: packagePaths) == nil)
    }
}
