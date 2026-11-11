import Foundation
import SwiftEffectInference
import Testing

@testable import SwiftInferCore

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
            "Demo/Sources/Demo/main.swift": Self.mintingRow,
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
            "Demo/Sources/Demo/Demo.swift": "struct Demo {}",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appendingPathComponent("Sources/Lib")
        #expect(ConstructionUniverse.files(forScanOf: lib).map(\.relativePath) == [
            "Packages/Core/Sources/Core/Row.swift",
            "Packages/Feature/Sources/Feature/Feature.swift",
            "Sources/Lib/Row.swift",
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
            "Demo/Sources/Demo/main.swift": Self.mintingRow,
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
            "Demo/Sources/Demo/main.swift": Self.mintingRow,
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
            "A/B/Sources/B/main.swift": Self.mintingRow,
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
