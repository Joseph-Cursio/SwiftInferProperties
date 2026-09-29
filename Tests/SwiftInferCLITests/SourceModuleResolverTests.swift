import Foundation
@testable import SwiftInferCLI
import Testing

/// A source file's module comes from the manifest first, and from its `Sources/<Module>/` path only
/// where no declared target contains it. Harbeth's one target, `Harbeth`, sits at `path: "Sources"`
/// with its files in `Sources/Basic/…`, and the path alone answered `Basic` — 0 of 230 stubs compiled.
@Suite("Source module resolution — manifest before path", .serialized)
struct SourceModuleResolverTests {

    private func package(_ manifest: String, files: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceModuleResolverTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try manifest.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        for file in files {
            let url = root.appendingPathComponent(file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try "struct Placeholder {}\n".write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    private static let header = "// swift-tools-version: 5.9\nimport PackageDescription\n"

    @Test("a target declared at `path: \"Sources\"` owns its subdirectories")
    func pathSourcesTargetOwnsSubdirectories() throws {
        let root = try package(Self.header + """
            let package = Package(name: "Harbeth", targets: [.target(name: "Harbeth", path: "Sources")])
            """, files: ["Sources/Basic/C7Point2D.swift"])
        defer { try? FileManager.default.removeItem(at: root) }
        let resolver = SourceModuleResolver(packageRoot: root)
        let file = root.appendingPathComponent("Sources/Basic/C7Point2D.swift").path
        #expect(resolver.module(forSourceFile: file) == "Harbeth")
        #expect(InteractiveTriage.moduleName(fromSourceFile: file) == "Basic")
    }

    @Test("a nested target wins over one whose directory encloses it")
    func nestedTargetWins() throws {
        let root = try package(Self.header + """
            let package = Package(name: "P", targets: [
                .target(name: "Outer", path: "Sources", exclude: ["Inner"]),
                .target(name: "Inner", path: "Sources/Inner")
            ])
            """, files: ["Sources/A/a.swift", "Sources/Inner/b.swift"])
        defer { try? FileManager.default.removeItem(at: root) }
        let resolver = SourceModuleResolver(packageRoot: root)
        #expect(resolver.module(forSourceFile: root.appendingPathComponent("Sources/A/a.swift").path) == "Outer")
        #expect(resolver.module(forSourceFile: root.appendingPathComponent("Sources/Inner/b.swift").path) == "Inner")
    }

    @Test("a conventional package resolves as it did before")
    func conventionalPackageUnchanged() throws {
        let root = try package(Self.header + """
            let package = Package(name: "P", targets: [.target(name: "my-lib")])
            """, files: ["Sources/my-lib/x.swift"])
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Sources/my-lib/x.swift").path
        #expect(SourceModuleResolver(packageRoot: root).module(forSourceFile: file) == "my_lib")
        #expect(InteractiveTriage.moduleName(fromSourceFile: file) == "my_lib")
    }

    @Test("with no package, the path convention still answers")
    func noPackageFallsBack() {
        let resolver = SourceModuleResolver(packageRoot: nil)
        #expect(resolver.module(forSourceFile: "/x/Sources/Core/File.swift") == "Core")
        #expect(resolver.module(forSourceFile: "/x/App/File.swift") == nil)
    }
}
