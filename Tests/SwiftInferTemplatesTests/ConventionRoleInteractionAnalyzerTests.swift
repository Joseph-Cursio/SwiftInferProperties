import Foundation
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Slice B3a — `ConventionRoleInteractionAnalyzer` maps a convention role's
/// assertable output collaborator onto an `outputDeterminism` suggestion.
struct ConventionRoleInteractionAnalyzerTests {

    private static let epoch = Date(timeIntervalSince1970: 0)

    @Test("a role with an output collaborator surfaces one outputDeterminism suggestion")
    func surfacesOutputDeterminism() throws {
        let source = """
        protocol ProfileViewProtocol { func display(_ text: String) }
        final class ProfilePresenter {
            private var count: Int = 0
            private let view: ProfileViewProtocol
            init(view: ProfileViewProtocol) { self.view = view }
            func refresh() { count += 1; view.display("\\(count)") }
        }
        """
        let role = try #require(ConventionRoleDiscoverer.discover(source: source, file: "F.swift").first)
        let suggestions = ConventionRoleInteractionAnalyzer.suggestions(for: role, firstSeenAt: Self.epoch)

        #expect(suggestions.count == 1)
        let suggestion = try #require(suggestions.first)
        #expect(suggestion.family == .outputDeterminism)
        #expect(suggestion.reducerQualifiedName == "ProfilePresenter")
        #expect(suggestion.score == 30)
        #expect(suggestion.tier == .possible)
        #expect(suggestion.predicate.contains("view: ProfileViewProtocol"))
        #expect(suggestion.whySuggested.contains { $0.contains("MVP convention role") })
    }

    @Test("a role with no assertable output collaborator surfaces nothing")
    func noOutputCollaboratorNoSuggestion() {
        let source = """
        final class AuditInteractor {
            private var hits: Int = 0
            private let service: AuthServiceProtocol
            init(service: AuthServiceProtocol) { self.service = service }
            func run() { hits += 1 }
        }
        """
        // `service` is a plain dependency (not the VIPER output name), so the
        // role has no output sink → no outputDeterminism candidate.
        let role = ConventionRoleDiscoverer.discover(source: source, file: "F.swift").first!
        #expect(ConventionRoleInteractionAnalyzer.suggestions(for: role, firstSeenAt: Self.epoch).isEmpty)
    }
}
