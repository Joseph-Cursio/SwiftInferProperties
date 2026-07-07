@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Slice B — `RecordingFakeEmitter` synthesizes a recording conformer for a
/// role's output protocol: a class logging every call (name + args) to
/// `callLog`, with defaults for properties / non-`Void` returns.
struct RecordingFakeEmitterTests {

    private func decl(_ source: String) -> ViewModelProtocolScanner.ProtocolDecl {
        ViewModelProtocolScanner.scan(source: source).first!
    }

    @Test("records Void methods with their arguments")
    func recordsVoidMethods() throws {
        let proto = decl("""
        protocol ViewP {
            func show(title: String)
            func update(_ count: Int, flag: Bool)
            func clear()
        }
        """)
        let source = try #require(RecordingFakeEmitter.recordingClass(for: proto))
        #expect(source.contains("final class Recording_ViewP: ViewP {"))
        #expect(source.contains("var callLog: [String] = []"))
        // Labelled + positional params get internal names arg0, arg1…
        #expect(source.contains("func show(title arg0: String) { callLog.append(\"show(\\(arg0))\") }"))
        // The two params get distinct internal names, both recorded.
        #expect(source.contains("func update(_ arg0: Int, flag arg1: Bool)"))
        #expect(source.contains("update(\\(arg0), \\(arg1))"))
        #expect(source.contains("func clear() { callLog.append(\"clear()\") }"))
    }

    @Test("non-Void method logs then returns a default; property gets a stored default")
    func nonVoidAndProperty() throws {
        let proto = decl("""
        protocol MetricsP {
            var label: String { get }
            func score() -> Int
        }
        """)
        let source = try #require(RecordingFakeEmitter.recordingClass(for: proto))
        #expect(source.contains("var label: String = \"\""))
        #expect(source.contains("func score() -> Int { callLog.append(\"score()\"); return 0 }"))
    }

    @Test("gated: an unsupported requirement (init) is not recordable")
    func gatesUnsupportedRequirement() {
        let proto = decl("""
        protocol BadP {
            init(x: Int)
            func go()
        }
        """)
        #expect(RecordingFakeEmitter.recordingClass(for: proto) == nil)
    }

    @Test("gated: a non-defaultable return type is not recordable")
    func gatesNonDefaultableReturn() {
        let proto = decl("""
        protocol FactoryP {
            func make() -> SomeCustomType
        }
        """)
        #expect(RecordingFakeEmitter.recordingClass(for: proto) == nil)
    }

    @Test("gated: an async / throws requirement is not recordable")
    func gatesAsyncThrows() {
        let asyncProto = decl("protocol AP { func load() async }")
        let throwsProto = decl("protocol TP { func load() throws }")
        #expect(RecordingFakeEmitter.recordingClass(for: asyncProto) == nil)
        #expect(RecordingFakeEmitter.recordingClass(for: throwsProto) == nil)
    }
}
