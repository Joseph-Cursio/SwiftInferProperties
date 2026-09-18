import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// A target built with `.defaultIsolation(MainActor.self)` isolates every declaration in the
/// module with nothing on the declaration to read, so a stub that calls one from a nonisolated
/// context does not compile (SwiftInferProperties#482).
///
/// **The issue proposed resolving this once per run, for a manifest target only, and the
/// measurement corrected both halves.** Resolution is per FILE because a package may split
/// isolation across targets — SwiftProjectLint's manifest does exactly that, and says so in a
/// comment — and it must work under `--sources`, because the two packages known to set the flag
/// are both scanned that way.
@Suite("Discover — isolation inherited from a target's default")
struct TargetDefaultIsolationTests {

    // MARK: - Resolving the setting for one file

    /// The decisive arm: one package, two targets, two different answers.
    ///
    /// This is SwiftProjectLint's shape reduced — its `engineSwiftSettings` targets carry a
    /// comment saying MainActor default isolation *"would be wrong here"*, while only the SwiftUI
    /// target adds it. A run-wide answer has to be wrong for one of them, and the corpus scans
    /// both directories in a single pass.
    @Test("one package, two targets: the answer follows the FILE, not the run")
    func splitPackageResolvesPerFile() throws {
        let root = try TargetIsolationGateTests.makePackage(
            named: "Split",
            targets: [("Isolated", "MainActor"), ("Plain", nil)]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let isolated = root.appendingPathComponent("Sources/Isolated/Placeholder.swift").path
        let plain = root.appendingPathComponent("Sources/Plain/Placeholder.swift").path

        #expect(TargetIsolation.defaultIsolation(forFile: isolated) == "MainActor")
        #expect(TargetIsolation.defaultIsolation(forFile: plain) == nil)
    }

    @Test("a file under no declared target answers nil rather than guessing")
    func fileOutsideAnyTarget() throws {
        let root = try TargetIsolationGateTests.makePackage(
            named: "Outside",
            targets: [("Isolated", "MainActor")]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        // Inside the package, outside every target directory the manifest declares. Attributing
        // a target's settings to it would be the guess this resolver exists to avoid.
        let stray = root.appendingPathComponent("Scripts/Helper.swift")
        try FileManager.default.createDirectory(
            at: stray.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "let x = 1".write(to: stray, atomically: true, encoding: .utf8)

        #expect(TargetIsolation.defaultIsolation(forFile: stray.path) == nil)
        #expect(TargetIsolation.declaredTarget(owning: stray, packageRoot: root) == nil)
    }

    @Test("a file outside the package root entirely answers nil")
    func fileOutsideTheRoot() throws {
        let root = try TargetIsolationGateTests.makePackage(
            named: "Elsewhere",
            targets: [("Isolated", "MainActor")]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let outside = URL(fileURLWithPath: "/tmp/not-in-this-package/File.swift")
        #expect(TargetIsolation.declaredTarget(owning: outside, packageRoot: root) == nil)
    }

    // MARK: - The post-pass

    private static func suggestion(
        globalActor: String? = nil,
        declaresNonisolated: Bool = false,
        file: String
    ) -> Suggestion {
        Suggestion(
            templateName: "idempotence",
            evidence: [
                Evidence(
                    displayName: "normalize(_:)",
                    signature: "(String) -> String",
                    location: SourceLocation(file: file, line: 4, column: 1),
                    qualifiedTypeName: "Formatter",
                    globalActor: globalActor,
                    declaresNonisolated: declaresNonisolated
                )
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "\(file)::normalize")
        )
    }

    private static func actor(of suggestions: [Suggestion]) -> String? {
        suggestions.first?.evidence.first?.globalActor
    }

    @Test("a row with no isolation gains the target's default")
    func fillsANilRow() throws {
        let root = try TargetIsolationGateTests.makePackage(
            named: "Fills",
            targets: [("Isolated", "MainActor")]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Sources/Isolated/Placeholder.swift").path

        let result = SwiftInferCommand.Discover.withTargetDefaultIsolation(
            [Self.suggestion(file: file)]
        )
        #expect(Self.actor(of: result) == "MainActor")
    }

    /// The soundness guard, and the reason `declaresNonisolated` had to be recorded at all.
    ///
    /// Before #482 the scanner computed this keyword and discarded it, so a member that opted OUT
    /// of isolation and a member nobody isolated both reached here as `globalActor == nil`. A
    /// fallback keyed on that alone hops precisely the declarations that said not to.
    @Test("an explicitly nonisolated row is left alone, although its target is isolated")
    func leavesNonisolatedAlone() throws {
        let root = try TargetIsolationGateTests.makePackage(
            named: "OptOut",
            targets: [("Isolated", "MainActor")]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Sources/Isolated/Placeholder.swift").path

        let result = SwiftInferCommand.Discover.withTargetDefaultIsolation(
            [Self.suggestion(declaresNonisolated: true, file: file)]
        )
        #expect(Self.actor(of: result) == nil)
    }

    @Test("a row that already names an actor keeps it — innermost fact wins")
    func doesNotOverride() throws {
        let root = try TargetIsolationGateTests.makePackage(
            named: "Override",
            targets: [("Isolated", "MainActor")]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Sources/Isolated/Placeholder.swift").path

        let result = SwiftInferCommand.Discover.withTargetDefaultIsolation(
            [Self.suggestion(globalActor: "CustomActor", file: file)]
        )
        #expect(Self.actor(of: result) == "CustomActor")
    }

    /// The control. Without it, every arm above would pass on a resolver that always answered
    /// `nil`, which is the failure mode `TargetIsolation`'s own degradation notes make easy.
    @Test("a row in a target with no setting is untouched")
    func plainTargetIsUntouched() throws {
        let root = try TargetIsolationGateTests.makePackage(
            named: "Control",
            targets: [("Plain", nil)]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Sources/Plain/Placeholder.swift").path

        let result = SwiftInferCommand.Discover.withTargetDefaultIsolation(
            [Self.suggestion(file: file)]
        )
        #expect(Self.actor(of: result) == nil)
    }
}
