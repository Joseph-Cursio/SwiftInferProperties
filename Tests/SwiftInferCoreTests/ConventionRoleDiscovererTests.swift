import Foundation
@testable import SwiftInferCore
import Testing

/// Slice A — `ConventionRoleDiscoverer` recognizes VIPER/MVP roles by naming /
/// conformance convention and emits `StatefulRole`s: State surface, action
/// alphabet, and collaborators (flagging the assertable output sink). Reuses the
/// MVVM scan machinery, so these focus on the convention-specific behavior.
struct ConventionRoleDiscovererTests {

    // MARK: - MVP presenter recognition + extraction

    @Test("recognizes an MVP presenter: State, actions, and the output collaborator")
    func recognizesMvpPresenter() throws {
        let source = """
        final class LoginPresenter {
            var title: String = ""
            var isBusy: Bool = false
            weak var view: LoginViewProtocol?
            let service: AuthServiceProtocol
            init(service: AuthServiceProtocol) { self.service = service }
            func present(_ user: String) { title = user }
            func begin() { isBusy = true }
            private func helper() { title = "x" }
        }
        """
        let roles = ConventionRoleDiscoverer.discover(source: source, file: "F.swift")
        #expect(roles.count == 1)
        let role = try #require(roles.first)

        #expect(role.paradigm == .mvp)
        #expect(role.recognizedBy == .convention)
        #expect(role.typeName == "LoginPresenter")

        // Genuine mutable State only — the two protocol deps are excluded.
        #expect(role.state == .storedFields([
            RoleStateField(name: "isBusy", typeText: "Bool", isMutable: true),
            RoleStateField(name: "title", typeText: "String", isMutable: true)
        ]))

        // Action alphabet — the private helper is not an action.
        #expect(role.actions.map(\.name) == ["begin", "present"])

        // Collaborators: view is the assertable output sink; service is a plain dep.
        let view = try #require(role.collaborators.first { $0.propertyName == "view" })
        #expect(view.role == .output(assertable: true))
        let service = try #require(role.collaborators.first { $0.propertyName == "service" })
        #expect(service.role == .dependency)

        // Constructed as an instance injecting the faked collaborators.
        guard case let .instance(initParameters, faked) = role.construction else {
            Issue.record("expected .instance construction; got \(role.construction)")
            return
        }
        #expect(initParameters.map(\.typeText) == ["AuthServiceProtocol"])
        #expect(faked.count == 2)
    }

    // MARK: - VIPER interactor recognition (name suffix infers the Output-typed sink)

    @Test("recognizes a VIPER interactor and flags its presenter as the output sink")
    func recognizesViperInteractor() throws {
        let source = """
        final class LoginInteractor: LoginInteractorInput {
            var attempts: Int = 0
            let presenter: LoginPresenterOutput
            init(presenter: LoginPresenterOutput) { self.presenter = presenter }
            func authenticate() { attempts += 1 }
        }
        """
        let roles = ConventionRoleDiscoverer.discover(source: source, file: "F.swift")
        #expect(roles.count == 1)
        let role = try #require(roles.first)
        #expect(role.paradigm == .viper)
        #expect(role.state == .storedFields([RoleStateField(name: "attempts", typeText: "Int", isMutable: true)]))
        #expect(role.actions.map(\.name) == ["authenticate"])
        // `presenter` (non-Optional let of a *Output type) is a dependency by the
        // non-self-initializing rule, and its name flags it as the output sink.
        let presenter = try #require(role.collaborators.first { $0.propertyName == "presenter" })
        #expect(presenter.role == .output(assertable: true))
    }

    @Test("recognizes a role by conformance alone when the name doesn't match")
    func recognizesByConformanceOnly() {
        let source = """
        final class LoginService: SomeInteractorInput {
            var count = 0
            func go() { count += 1 }
        }
        """
        let roles = ConventionRoleDiscoverer.discover(source: source, file: "F.swift")
        #expect(roles.map(\.typeName) == ["LoginService"])
        #expect(roles.first?.paradigm == .viper)
    }

    // MARK: - Precision guards

    @Test("a plain class matching no rule is not a convention role")
    func plainClassNotRecognized() {
        let source = """
        final class Helper {
            var value = 0
            func bump() { value += 1 }
        }
        """
        #expect(ConventionRoleDiscoverer.discover(source: source, file: "F.swift").isEmpty)
    }

    @Test("an @Observable class is left to MVVM even if its name matches a rule")
    func observableClassIsNotAConventionRole() {
        let source = """
        @Observable
        final class DashboardPresenter {
            var title = ""
            func setTitle(_ text: String) { title = text }
        }
        """
        // Named *Presenter, but it's an observable view model — MVVM owns it, so
        // the convention discoverer must not double-count it.
        #expect(ConventionRoleDiscoverer.discover(source: source, file: "F.swift").isEmpty)
    }

    @Test("a struct is not a convention role — presenters/interactors are reference types")
    func structIsNotAConventionRole() {
        let source = """
        struct ProfilePresenter {
            var title = ""
            func setTitle(_ text: String) { title = text }
        }
        """
        #expect(ConventionRoleDiscoverer.discover(source: source, file: "F.swift").isEmpty)
    }

    // MARK: - Cross-file assembly (presenter methods in an extension)

    @Test("a presenter whose methods span files assembles into one role")
    func crossFileAssembly() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConventionRole-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try """
        final class FeedPresenter {
            var items: [String] = []
            weak var view: FeedViewProtocol?
        }
        """.write(to: dir.appendingPathComponent("FeedPresenter.swift"), atomically: true, encoding: .utf8)

        try """
        extension FeedPresenter {
            func reload() { items.removeAll() }
        }
        """.write(to: dir.appendingPathComponent("FeedPresenter+Reload.swift"), atomically: true, encoding: .utf8)

        let roles = try ConventionRoleDiscoverer.discover(directory: dir)
        #expect(roles.count == 1)
        // The extension method in the other file is attributed to the class.
        #expect(roles.first?.actions.map(\.name) == ["reload"])
    }
}
