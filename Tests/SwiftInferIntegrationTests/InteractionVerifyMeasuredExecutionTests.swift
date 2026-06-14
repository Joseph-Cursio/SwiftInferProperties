import Foundation
import SwiftInferCLI
import SwiftInferCore
import Testing

/// Cycle 110 (Blocker B) — end-to-end proof that the interaction verify
/// path builds **and runs from a plain process** (not under a
/// swift-testing host) and reports `measured-bothPass`.
///
/// This is the M3.E integration test deferred "pending kit tag." It now
/// passes given two fixes:
///   - cycle 109 (Blocker A): nested `State`/`Action` are pre-qualified so
///     the synthesized verifier compiles (`IDemo.State()` /
///     `IDemo.Action.self`).
///   - cycle 110 (Blocker B): `VerifierSubprocess` injects
///     `DYLD_FRAMEWORK_PATH` so the verifier can load `Testing.framework`
///     (linked transitively via swift-property-based) outside a test host.
///
/// Spawns a real `swift build` + verifier run (kit-resolving; tens of
/// seconds) — tagged `.subprocess` like the algebraic suite.
@Suite("Verify interaction — Blocker B end-to-end measured execution", .tags(.subprocess))
struct InteractionVerifyMeasuredExecutionTests {

    @Test("nested-State/Action identity reducer → measured-bothPass from a plain process")
    func identityReducerMeasuresBothPass() throws {
        // The package-root directory MUST be named after the module:
        // SwiftPM derives a path-dependency's package identity from the
        // directory's last path component, and the synthesized verifier
        // workdir references the user package by module name ("IDemo").
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("verify-interaction-integration")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("IDemo")
        let sources = root.appendingPathComponent("Sources").appendingPathComponent("IDemo")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        try """
        // swift-tools-version: 6.1
        import PackageDescription
        let package = Package(
            name: "IDemo",
            products: [.library(name: "IDemo", targets: ["IDemo"])],
            targets: [.target(name: "IDemo")]
        )
        """.write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        try """
        public struct IDemo {
            public struct State: Equatable, Sendable {
                public var count: Int
                public init(count: Int = 0) { self.count = count }
            }
            public enum Action: CaseIterable, Sendable { case refresh, noop }
            public static func reduce(_ s: State, _ a: Action) -> State {
                switch a {
                case .refresh: return s
                case .noop: return s
                }
            }
        }
        """.write(
            to: sources.appendingPathComponent("Reducer.swift"),
            atomically: true,
            encoding: .utf8
        )

        let rendered = try VerifyInteractionPipeline.runPipeline(
            target: "IDemo",
            workingDirectory: root
        )

        // Blocker B: the binary launched and ran all sequences cleanly.
        #expect(rendered.contains("measured-bothPass"))
        // Blocker A: the nested State type was pre-qualified for emission.
        #expect(rendered.contains("IDemo.State"))
        // Must NOT have degraded to a build/launch failure.
        #expect(!rendered.contains("architectural-coverage-pending"))
        #expect(!rendered.contains("measured-defaultFails"))
    }
}
