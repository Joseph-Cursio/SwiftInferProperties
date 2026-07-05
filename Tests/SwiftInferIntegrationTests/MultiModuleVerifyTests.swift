import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// M3 (multi-module measured verify) — fast (no-build) proof that multi-target
/// discovery tags each interaction-invariant suggestion with its module
/// (`InteractionInvariantSuggestion.moduleName`), which the survey then uses to
/// verify each identity against its own module's product. Exercises the
/// Core + Templates threading + `collectSuggestions(targets:)` without the ~60s
/// measured build.
@Suite("Multi-module verify — module tagging (M3)")
struct MultiModuleVerifyTests {

    @Test("collectSuggestions(targets:) tags each identity with its module")
    func suggestionsCarryModule() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("multi-module-verify-tag")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.packageMultiModule(
            packageName: "MultiModuleVerifyCorpus",
            modules: [
                ("Alpha", Self.moduleDirectory("Alpha")),
                ("Beta", Self.moduleDirectory("Beta"))
            ],
            into: parent
        )

        let suggestions = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
            targets: ["Alpha", "Beta"],
            workingDirectory: root
        )

        #expect(suggestions.contains {
            $0.moduleName == "Alpha" && $0.reducerQualifiedName == "AlphaCounter.reduce"
        })
        #expect(suggestions.contains {
            $0.moduleName == "Beta" && $0.reducerQualifiedName == "BetaCounter.reduce"
        })
        // No suggestion is left untagged (both targets present → tagging on).
        #expect(suggestions.allSatisfy { $0.moduleName != nil })
    }

    static func moduleDirectory(_ module: String) -> URL {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("multi-module-verify-corpus")
            .appendingPathComponent(module)
    }
}
