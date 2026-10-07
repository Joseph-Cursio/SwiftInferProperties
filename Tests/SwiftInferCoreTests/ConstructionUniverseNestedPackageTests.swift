import Foundation
import SwiftEffectInference
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
        #".package(name: "Core", path: ("Core"))"#
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
            "Sources/Lib/Row.swift": Self.row
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
    /// holds none.
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
                return directory.isEmpty || packages.contains(directory) ? [.unreadable] : []
            }
        )
    }

    @Test("the root's local path dependencies, followed transitively")
    func transitiveClosure() {
        let reached = Self.compiled([
            "": #".package(path: "Packages/A")"#,
            "Packages/A": #".package(path: "../B")"#,
            "Packages/B": #".package(url: "https://x/y.git", from: "1.0.0")"#,
            "Packages/C": #".package(path: "../../Demo")"#
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
            "Vendor/Lib": "", "Demo": "", "Packages/C": ""
        ])
        // `../App/Demo` climbs out and back in: it names `/work/App/Demo`, which is under the root.
        #expect(reached == ["Vendor/Lib", "Demo", "Packages/C"])
    }

    @Test("doubt anywhere in the closure includes every nested package")
    func doubtIncludesAll() {
        let computed = Self.compiled([
            "": #".package(path: "Packages/A")"#,
            "Packages/A": ".package(path: siblingPath)"
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
        let packages: Set<String> = ["A", "A/B"]
        #expect(ConstructionUniverse.owningPackage(of: "A/B/Sources/X.swift", among: packages) == "A/B")
        #expect(ConstructionUniverse.owningPackage(of: "A/Sources/X.swift", among: packages) == "A")
        #expect(ConstructionUniverse.owningPackage(of: "AB/Sources/X.swift", among: packages) == nil)
        #expect(ConstructionUniverse.owningPackage(of: "Sources/X.swift", among: packages) == nil)
        #expect(ConstructionUniverse.owningPackage(of: "A", among: packages) == nil)
    }
}

// MARK: - On disk, through the scan

extension ConstructionUniverseNestedPackageTests {

    static let row = "public struct Row { public let n: Int }\npublic func make(n: Int) -> Row { Row(n: n) }"
    static let mintingRow = "import Foundation\nstruct Row { let id = UUID(); let n: Int }\nprint(Row(n: 1))"
    static let demoManifest = """
    // swift-tools-version:5.9
    import PackageDescription
    let package = Package(name: "Demo")

    """

    static func manifest(dependingOn path: String) -> String {
        "// swift-tools-version:5.9\nlet package = Package(name: \"P\", dependencies: [.package(path: \"\(path)\")])"
    }

    static func verdict(_ name: String, scanning directory: URL) throws -> PurityVerdict? {
        ConstructionPurityWiringTests.verdict(name, in: try FunctionScanner.scanCorpus(directory: directory))
    }

    /// The critic's scenario: main advised `make(n:)` pure, and the unbounded universe withdrew it
    /// because a package the root never compiles declares a `Row` that mints a `UUID`.
    @Test("a nested package the root does not compile neither refutes nor joins the universe")
    func unreferencedNestedPackageIsOutside() throws {
        let root = try ConstructionPurityWiringTests.makePackage([
            "Package.swift": "// swift-tools-version:5.9\nimport PackageDescription\n"
                + "let package = Package(name: \"Root\", targets: [.target(name: \"Lib\")])\n",
            "Sources/Lib/Row.swift": Self.row,
            "Demo/Package.swift": Self.demoManifest,
            "Demo/Sources/Demo/main.swift": Self.mintingRow
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appendingPathComponent("Sources/Lib")
        let universe = ConstructionUniverse.universe(forScanOf: lib)
        #expect(universe.members.map(\.relativePath) == ["Sources/Lib/Row.swift"])
        // Not a member, but watched: an edit that adds `.package(path: "Demo")` moves the bound.
        #expect(universe.manifests.map(\.path) == ["Package.swift", "Demo/Package.swift"].map {
            universe.root.appendingPathComponent($0).path
        })
        #expect(try Self.verdict("make", scanning: lib) == .pure, "an uncompiled package's `Row` refuted the root's")
    }

    @Test("a nested package the root reaches by path — transitively — is in the universe")
    func referencedNestedPackageIsInside() throws {
        let root = try ConstructionPurityWiringTests.makePackage([
            "Package.swift": Self.manifest(dependingOn: "Packages/Feature"),
            "Sources/Lib/Row.swift": Self.row,
            "Packages/Feature/Package.swift": Self.manifest(dependingOn: "../Core"),
            "Packages/Feature/Sources/Feature/Feature.swift": "public struct Feature {}",
            "Packages/Core/Package.swift": Self.demoManifest,
            "Packages/Core/Sources/Core/Row.swift": Self.mintingRow,
            "Demo/Package.swift": Self.demoManifest,
            "Demo/Sources/Demo/Demo.swift": "struct Demo {}"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appendingPathComponent("Sources/Lib")
        #expect(ConstructionUniverse.files(forScanOf: lib).map(\.relativePath) == [
            "Packages/Core/Sources/Core/Row.swift",
            "Packages/Feature/Sources/Feature/Feature.swift",
            "Sources/Lib/Row.swift"
        ])
        #expect(try Self.verdict("make", scanning: lib) == .refuted, "the closure's `Row` is compiled, so it refutes")
    }

    @Test("a computed path in the root's manifest includes every nested package")
    func doubtfulRootIncludesEveryNestedPackage() throws {
        let root = try ConstructionPurityWiringTests.makePackage([
            "Package.swift": """
            // swift-tools-version:5.9
            let base = "Demo"
            let package = Package(name: "P", dependencies: [.package(path: base)])
            """,
            "Sources/Lib/Row.swift": Self.row,
            "Demo/Package.swift": Self.demoManifest,
            "Demo/Sources/Demo/main.swift": Self.mintingRow
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appendingPathComponent("Sources/Lib")
        #expect(ConstructionUniverse.files(forScanOf: lib).map(\.relativePath).contains("Demo/Sources/Demo/main.swift"))
        #expect(try Self.verdict("make", scanning: lib) == .refuted)
    }

    @Test("a root with no manifest takes every nested package, nearest package owning each file")
    func manifestlessRootTakesEveryNestedPackage() throws {
        let root = try ConstructionPurityWiringTests.makePackage([
            "App/Row.swift": Self.row,
            "Demo/Package.swift": Self.demoManifest,
            "Demo/Sources/Demo/main.swift": Self.mintingRow
        ], manifest: false)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ConstructionUniverse.files(forScanOf: root).map(\.relativePath) == [
            "App/Row.swift", "Demo/Sources/Demo/main.swift"
        ])
        #expect(try Self.verdict("make", scanning: root) == .refuted)
    }

    @Test("a package nested in a compiled one is judged by its own manifest's reach")
    func nearestManifestDecides() throws {
        let root = try ConstructionPurityWiringTests.makePackage([
            "Package.swift": Self.manifest(dependingOn: "A"),
            "Sources/Lib/Row.swift": Self.row,
            "A/Package.swift": Self.demoManifest,
            "A/Sources/A/A.swift": "public struct A {}",
            "A/B/Package.swift": Self.demoManifest,
            "A/B/Sources/B/main.swift": Self.mintingRow
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appendingPathComponent("Sources/Lib")
        // `A/B/…` belongs to `A/B`, which nothing reaches, even though `A` is compiled.
        let paths = ConstructionUniverse.files(forScanOf: lib).map(\.relativePath)
        #expect(paths == ["A/Sources/A/A.swift", "Sources/Lib/Row.swift"])
        #expect(try Self.verdict("make", scanning: lib) == .pure)
    }

    /// This repo's own manifest names no local package, so its `fixtures/<package>/` are not in its
    /// universe — the bound's largest effect here, and why the census's universe shrank.
    @Test("this repository's fixture packages are outside its own universe")
    func ownFixturePackagesAreOutside() {
        let sources = CensusPurity.packageRoot.appendingPathComponent("Sources")
        let universe = ConstructionUniverse.universe(forScanOf: sources)
        let fixturePackages = universe.manifests.compactMap { manifest -> String? in
            let directory = manifest.deletingLastPathComponent().path
            let prefix = universe.root.path + "/"
            return directory.hasPrefix(prefix + "fixtures/") ? String(directory.dropFirst(prefix.count)) : nil
        }
        #expect(!fixturePackages.isEmpty, "found no fixture package — the check below would be vacuous")
        let leaked = universe.members.filter { member in
            fixturePackages.contains { member.relativePath.hasPrefix($0 + "/") }
        }
        #expect(leaked.isEmpty, "uncompiled fixture packages in the universe: \(leaked.prefix(5).map(\.relativePath))")
        #expect(universe.members.contains { $0.relativePath.hasPrefix("Sources/SwiftInferCore/") })
    }
}
