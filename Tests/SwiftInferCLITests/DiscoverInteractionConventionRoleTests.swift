import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Slice B3a — `discover-interaction.collectSuggestions` surfaces convention
/// roles' (VIPER/MVP) `outputDeterminism` invariant as a first-class
/// `InteractionInvariantSuggestion` alongside reducer- and MVVM-derived ones.
/// AST-only (no build).
@Suite("discover-interaction — convention roles (productionization)")
struct DiscoverInteractionConventionRoleTests {

    @Test("collectSuggestions includes a VIPER/MVP outputDeterminism suggestion at Possible")
    func collectsConventionRoleSuggestion() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("conv-prod-\(UUID().uuidString)")
        let sources = temp.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let source = """
        protocol ProfileViewProtocol { func display(_ text: String) }
        final class ProfilePresenter {
            private var count: Int = 0
            private let view: ProfileViewProtocol
            init(view: ProfileViewProtocol) { self.view = view }
            func refresh() { count += 1; view.display("hi") }
        }
        """
        try Data(source.utf8).write(to: sources.appendingPathComponent("ProfilePresenter.swift"))

        let suggestions = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
            target: "App",
            workingDirectory: temp
        )
        let presenter = suggestions.filter { $0.reducerQualifiedName == "ProfilePresenter" }
        #expect(presenter.count == 1)
        #expect(presenter.allSatisfy { $0.tier == .possible })
        #expect(presenter.allSatisfy { $0.family == .outputDeterminism })
    }
}
