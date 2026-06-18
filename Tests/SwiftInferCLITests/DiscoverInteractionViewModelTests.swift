import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Productionization — `discover-interaction.collectSuggestions` surfaces
/// SwiftUI MVVM view-model invariants as first-class
/// `InteractionInvariantSuggestion`s alongside reducer-derived ones, so
/// they flow through the same render / scoring / drift pipeline. AST-only
/// (no build).
@Suite("discover-interaction — MVVM view models (productionization)")
struct DiscoverInteractionViewModelTests {

    @Test("collectSuggestions includes MVVM view-model invariants at Possible")
    func collectsViewModelSuggestions() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-prod-\(UUID().uuidString)")
        let sources = temp.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let source = """
        import Observation

        @Observable
        final class InboxViewModel {
            var selectedID: UUID?
            var items: [Int] = []

            func selectAll() { items = [1, 2, 3] }
            func deselect() { selectedID = nil }
        }
        """
        try Data(source.utf8).write(to: sources.appendingPathComponent("InboxViewModel.swift"))

        let suggestions = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
            target: "App",
            workingDirectory: temp
        )
        // The MVVM view model surfaces idempotence + referential-integrity,
        // both at Possible (a new inference source, default-hidden).
        let inbox = suggestions.filter { $0.reducerQualifiedName == "InboxViewModel" }
        #expect(!inbox.isEmpty)
        #expect(inbox.allSatisfy { $0.tier == .possible })
        #expect(inbox.contains { $0.family == .idempotence })
        #expect(inbox.contains { $0.family == .referentialIntegrity })
    }
}
