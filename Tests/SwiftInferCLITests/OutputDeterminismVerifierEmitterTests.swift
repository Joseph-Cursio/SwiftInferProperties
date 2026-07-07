@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Slice B — `OutputDeterminismVerifierEmitter` emits a verifier that constructs
/// a convention role twice (recording fake for the output, no-op fakes for other
/// deps), drives the same actions, and compares the recorded output logs.
struct OutputDeterminismVerifierEmitterTests {

    private static let fixture = """
    protocol ProfileViewProtocol {
        func show(title: String)
        func clear()
    }
    protocol AnalyticsProtocol {
        func track(event: String)
    }
    final class ProfilePresenter {
        var loaded: Bool = false
        let view: ProfileViewProtocol
        let analytics: AnalyticsProtocol
        init(view: ProfileViewProtocol, analytics: AnalyticsProtocol) {
            self.view = view
            self.analytics = analytics
        }
        func refresh() { loaded = true; view.clear() }
    }
    """

    private func emitFixtureVerifier() -> String? {
        let role = ConventionRoleDiscoverer.discover(source: Self.fixture, file: "F.swift").first!
        let protocols = ViewModelProtocolScanner.scan(source: Self.fixture)
        let output = protocols.first { $0.name == "ProfileViewProtocol" }!
        return OutputDeterminismVerifierEmitter.emit(
            role: role,
            outputProtocol: output,
            dependencyProtocols: protocols,
            moduleName: "Corpus"
        )
    }

    @Test("emits the recording fake, dependency-faked construction, drive, and compare")
    func emitsVerifier() throws {
        let source = try #require(emitFixtureVerifier())
        #expect(source.contains("import Corpus"))
        // Recording fake for the output; no-op fake for the other dependency.
        #expect(source.contains("final class Recording_ProfileViewProtocol: ProfileViewProtocol"))
        #expect(source.contains("struct Fake_AnalyticsProtocol: AnalyticsProtocol"))
        // Construction injects the recorder for the output param, a no-op for the dep.
        #expect(source.contains("let recorder = Recording_ProfileViewProtocol()"))
        #expect(source.contains("ProfilePresenter(view: recorder, analytics: Fake_AnalyticsProtocol())"))
        // Drives the no-arg action, runs twice, compares logs.
        #expect(source.contains("subject.refresh()"))
        #expect(source.contains("let first = runOnce()"))
        #expect(source.contains("let second = runOnce()"))
        #expect(source.contains("if first == second"))
        #expect(source.contains("VERIFY_DEFAULT_RESULT: PASS"))
        #expect(source.contains("VERIFY_DEFAULT_RESULT: FAIL"))
    }

    @Test("gated: an output protocol with a non-recordable requirement returns nil")
    func gatesNonRecordableOutput() {
        let source = """
        protocol BadViewProtocol {
            func load() async
        }
        final class BadPresenter {
            let view: BadViewProtocol
            init(view: BadViewProtocol) { self.view = view }
            func go() {}
        }
        """
        let role = ConventionRoleDiscoverer.discover(source: source, file: "F.swift").first!
        let protocols = ViewModelProtocolScanner.scan(source: source)
        let output = protocols.first { $0.name == "BadViewProtocol" }!
        #expect(
            OutputDeterminismVerifierEmitter.emit(
                role: role,
                outputProtocol: output,
                dependencyProtocols: protocols,
                moduleName: "Corpus"
            ) == nil
        )
    }
}
