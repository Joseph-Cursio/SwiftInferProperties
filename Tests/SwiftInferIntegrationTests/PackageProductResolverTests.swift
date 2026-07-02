import Foundation
@testable import SwiftInferCLI
import Testing

/// Tier 2 — `PackageProductResolver` maps a target *module* name to the library
/// *product* that vends it, distinct from the module name. Shells out to
/// `swift package dump-package` against on-disk fixture packages, so tagged
/// `.subprocess`.
@Suite("PackageProductResolver — product vs module resolution", .tags(.subprocess))
struct PackageProductResolverTests {

    /// Write a `Package.swift` (plus a stub source per named target) into a
    /// fresh temp directory and return its root. `dump-package` only evaluates
    /// the manifest, but real sources keep the fixture buildable/realistic.
    private static func makePackage(
        manifest: String,
        targets: [String],
        directoryName: String
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("product-resolver-\(directoryName)-\(UUID().uuidString)")
            .appendingPathComponent(directoryName)
        for target in targets {
            let sources = root.appendingPathComponent("Sources").appendingPathComponent(target)
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            try "public let placeholder = 0\n"
                .write(to: sources.appendingPathComponent("Placeholder.swift"), atomically: true, encoding: .utf8)
        }
        try manifest.write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        return root
    }

    @Test("Resolves the product name when it differs from the module name")
    func productDiffersFromModule() throws {
        let root = try Self.makePackage(
            manifest: """
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(
                name: "DemoPackage",
                products: [.library(name: "DemoLib", targets: ["DemoCore"])],
                targets: [.target(name: "DemoCore")]
            )
            """,
            targets: ["DemoCore"],
            directoryName: "demo-pkg"
        )
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        #expect(
            PackageProductResolver.libraryProduct(exposingModule: "DemoCore", packageRoot: root) == "DemoLib"
        )
    }

    @Test("Returns the module name when a product is named after it")
    func productEqualsModule() throws {
        let root = try Self.makePackage(
            manifest: """
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(
                name: "Solo",
                products: [.library(name: "Solo", targets: ["Solo"])],
                targets: [.target(name: "Solo")]
            )
            """,
            targets: ["Solo"],
            directoryName: "solo"
        )
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        #expect(
            PackageProductResolver.libraryProduct(exposingModule: "Solo", packageRoot: root) == "Solo"
        )
    }

    @Test("Returns nil when no library product vends the module")
    func moduleNotVended() throws {
        let root = try Self.makePackage(
            manifest: """
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(
                name: "DemoPackage",
                products: [.library(name: "DemoLib", targets: ["DemoCore"])],
                targets: [.target(name: "DemoCore")]
            )
            """,
            targets: ["DemoCore"],
            directoryName: "demo-pkg"
        )
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        #expect(
            PackageProductResolver.libraryProduct(exposingModule: "Ghost", packageRoot: root) == nil
        )
    }

    @Test("Prefers the product named exactly after the module when several vend it")
    func prefersExactNameMatch() throws {
        let root = try Self.makePackage(
            manifest: """
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(
                name: "Multi",
                products: [
                    .library(name: "Umbrella", targets: ["Shared", "Other"]),
                    .library(name: "Shared", targets: ["Shared"])
                ],
                targets: [.target(name: "Shared"), .target(name: "Other")]
            )
            """,
            targets: ["Shared", "Other"],
            directoryName: "multi"
        )
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        #expect(
            PackageProductResolver.libraryProduct(exposingModule: "Shared", packageRoot: root) == "Shared"
        )
    }

    @Test("userPackageWiring lands all three names on their own axes")
    func wiringSeparatesAllThreeNames() throws {
        // dir `demo-pkg` (→ package identity), product `DemoLib`, module
        // `DemoCore` (→ import) — all distinct. The wiring must produce a
        // reference whose identity is the basename, whose product is the
        // resolved library product, and whose import is the module.
        let root = try Self.makePackage(
            manifest: """
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(
                name: "DemoPackage",
                products: [.library(name: "DemoLib", targets: ["DemoCore"])],
                targets: [.target(name: "DemoCore")]
            )
            """,
            targets: ["DemoCore"],
            directoryName: "demo-pkg"
        )
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let wiring = SwiftInferCommand.Verify.userPackageWiring(target: "DemoCore", packageRoot: root)
        let reference = try #require(wiring.userPackage)
        #expect(reference.productNames == ["DemoLib"])      // .product(name:)
        #expect(reference.packageIdentity == "demo-pkg")    // .package(path:) identity
        #expect(wiring.extraImports == ["@testable DemoCore"]) // stub import
    }

    @Test("Ignores executable products — only library products are dependable")
    func ignoresExecutableProducts() throws {
        let root = try Self.makePackage(
            manifest: """
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(
                name: "ToolPackage",
                products: [
                    .executable(name: "tool", targets: ["ToolCore"]),
                    .library(name: "ToolKit", targets: ["ToolCore"])
                ],
                targets: [.target(name: "ToolCore")]
            )
            """,
            targets: ["ToolCore"],
            directoryName: "tool-pkg"
        )
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        // The executable "tool" also vends ToolCore, but only the library
        // product "ToolKit" is a valid `.product` dependency.
        #expect(
            PackageProductResolver.libraryProduct(exposingModule: "ToolCore", packageRoot: root) == "ToolKit"
        )
    }
}
