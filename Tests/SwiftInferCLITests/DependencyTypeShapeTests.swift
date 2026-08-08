import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// #118 — a type declared in a dependency had no recorded shape, so any law whose
/// signature reached one declined.
///
/// `FunctionSummary` was the largest carrier-decline bucket in the whole-corpus survey
/// (32 of 105) for exactly this reason: two of its initializer parameters are declared in
/// SwiftEffectInference, and **zero** of the index's 745 recorded source files pointed
/// outside the package. Invisible by construction, not by omission.
@Suite("Dependency type shapes — recorded, but never at the cost of a wrong one")
struct DependencyTypeShapeTests {

    /// Build a package root with `.build/checkouts/<name>/Sources/<name>/<file>`.
    private static func makeCheckouts(_ declarations: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dep-shapes-\(UUID().uuidString)")
        for (dependency, source) in declarations {
            let sources = root.appendingPathComponent(".build/checkouts")
                .appendingPathComponent(dependency)
                .appendingPathComponent("Sources")
                .appendingPathComponent(dependency)
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            try source.write(
                to: sources.appendingPathComponent("Types.swift"),
                atomically: true, encoding: .utf8
            )
        }
        return root
    }

    @Test("a dependency's type gets a recorded shape")
    func dependencyTypeIsRecorded() throws {
        let root = try Self.makeCheckouts([
            "DepA": "public struct Widget { public let size: Int }\n"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let scanned = DependencyTypeShapes.scan(packageRoot: root, localTypeNames: [])
        #expect(scanned.shapes["Widget"] != nil)
        #expect(scanned.sourceFiles["Widget"]?.contains("DepA") == true)
        #expect(scanned.collisions.isEmpty)
    }

    /// **Local always wins.** The scanned package is the subject; its own type is the one a
    /// law is about, and a dependency must never displace it.
    @Test("a name the package declares is not overwritten")
    func localDeclarationWins() throws {
        let root = try Self.makeCheckouts([
            "DepA": "public struct Widget { public let size: Int }\n"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let scanned = DependencyTypeShapes.scan(packageRoot: root, localTypeNames: ["Widget"])
        #expect(scanned.shapes["Widget"] == nil, "a dependency displaced a local type")
    }

    /// **The rule that keeps the widening safe.** The index keys on the BARE name, so two
    /// dependencies declaring `Mutex` cannot both be recorded — and picking one silently
    /// would hand verify a shape for the wrong type. A wrong shape is worse than no shape,
    /// which is the whole reason the decline existed.
    @Test("a name two dependencies both declare is recorded from neither")
    func dependencyCollisionRecordsNeither() throws {
        let root = try Self.makeCheckouts([
            "DepA": "public struct Mutex { public let a: Int }\n",
            "DepB": "public struct Mutex { public let b: String }\n"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let scanned = DependencyTypeShapes.scan(packageRoot: root, localTypeNames: [])
        #expect(scanned.shapes["Mutex"] == nil, "a colliding name was recorded anyway")
        #expect(scanned.sourceFiles["Mutex"] == nil)
        #expect(scanned.collisions == ["Mutex"], "the collision was swallowed rather than reported")
    }

    /// A collision must not take unrelated types down with it.
    @Test("a collision does not suppress the dependencies' other types")
    func collisionIsScopedToTheName() throws {
        let root = try Self.makeCheckouts([
            "DepA": "public struct Mutex { public let a: Int }\npublic struct OnlyA { public let x: Int }\n",
            "DepB": "public struct Mutex { public let b: String }\npublic struct OnlyB { public let y: Int }\n"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let scanned = DependencyTypeShapes.scan(packageRoot: root, localTypeNames: [])
        #expect(scanned.shapes["OnlyA"] != nil)
        #expect(scanned.shapes["OnlyB"] != nil)
        #expect(scanned.shapes["Mutex"] == nil)
    }

    /// A package that was never resolved has no dependency source to read, and that is not
    /// an error — the scan must be silent and empty rather than throwing.
    @Test("no .build means no shapes and no complaint")
    func unresolvedPackageIsSilent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dep-shapes-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let scanned = DependencyTypeShapes.scan(packageRoot: root, localTypeNames: [])
        #expect(scanned.shapes.isEmpty)
        #expect(scanned.roots.isEmpty)
        #expect(scanned.collisions.isEmpty)
    }
}
