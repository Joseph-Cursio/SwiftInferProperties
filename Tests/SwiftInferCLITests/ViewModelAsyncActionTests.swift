import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
import Testing

/// The interaction-path async-main slice (collections/async workplan
/// Phase 4 follow-up): clock-deterministic-annotated async actions join
/// the synthetic action surface, the dispatcher and `@main` go `async`
/// exactly when one is present, and the all-sync output stays
/// byte-identical.
@Suite
struct ViewModelAsyncActionTests {

    private func action(
        _ name: String,
        isAsync: Bool = false,
        isClockDeterministic: Bool = false
    ) -> ViewModelAction {
        ViewModelAction(
            name: name,
            parameterTypes: [],
            isAsync: isAsync,
            isThrows: false,
            mutatesStateDirectly: true,
            isClockDeterministic: isClockDeterministic
        )
    }

    @Test("Annotated async action is lifted with an awaited arm in an async dispatcher")
    func annotatedAsyncActionIsLifted() {
        let result = ViewModelActionEnumEmitter.emit(
            typeName: "CartModel",
            actions: [
                action("checkout"),
                action("load", isAsync: true, isClockDeterministic: true)
            ]
        )
        #expect(result.skipped.isEmpty)
        #expect(result.isAsyncDispatcher)
        #expect(result.source.contains("func drive(_ model: CartModel, _ action: CartModelAction) async {"))
        #expect(result.source.contains(".load: await model.load()"))
        // Sync arms inside the async dispatcher stay bare.
        #expect(result.source.contains(".checkout: model.checkout()"))
    }

    @Test("Bare async action stays skipped with the recorded reason")
    func bareAsyncActionStaysSkipped() {
        let result = ViewModelActionEnumEmitter.emit(
            typeName: "CartModel",
            actions: [action("load", isAsync: true)]
        )
        #expect(result.skipped == [.init(action: "load", reason: .asyncMethod)])
        #expect(result.isAsyncDispatcher == false)
    }

    @Test("All-sync surface emits the pre-Phase-4 dispatcher byte-identically")
    func allSyncDispatcherIsUnchanged() {
        let result = ViewModelActionEnumEmitter.emit(
            typeName: "CartModel",
            actions: [action("checkout")]
        )
        #expect(result.isAsyncDispatcher == false)
        #expect(result.source.contains("func drive(_ model: CartModel, _ action: CartModelAction) {"))
        #expect(result.source.contains(" async") == false)
    }

    @Test("Stub emitter goes async main and awaits drive for an async surface")
    func stubEmitterEmitsAsyncMain() throws {
        let source = try ViewModelActionSequenceStubEmitter.emit(.init(
            typeName: "CartModel",
            userModuleName: nil,
            predicate: "true",
            actions: [
                action("checkout"),
                action("load", isAsync: true, isClockDeterministic: true)
            ]
        ))
        #expect(source.contains("static func main() async {"))
        #expect(source.contains("await drive(probe, action)"))
    }

    @Test("Stub emitter keeps the synchronous main for an all-sync surface")
    func stubEmitterKeepsSyncMain() throws {
        let source = try ViewModelActionSequenceStubEmitter.emit(.init(
            typeName: "CartModel",
            userModuleName: nil,
            predicate: "true",
            actions: [action("checkout")]
        ))
        #expect(source.contains("static func main() {"))
        #expect(source.contains("await") == false)
    }

    @Test("Records persisted before the flag existed still decode")
    func decodesLegacyRecordWithoutFlag() throws {
        let legacy = """
        {"name":"load","parameterTypes":[],"parameters":[],"isAsync":true,
         "isThrows":false,"mutatesStateDirectly":true}
        """
        let decoded = try JSONDecoder().decode(
            ViewModelAction.self,
            from: Data(legacy.utf8)
        )
        #expect(decoded.isClockDeterministic == false)
        #expect(decoded.isAsync)
    }

    @Test("Discovery populates the flag from the method declaration")
    func discoveryPopulatesFlag() {
        let source = """
        @Observable final class CartModel {
            var items: [String] = []
            /// @lint.determinism clock_deterministic
            func load() async { items = ["a"] }
            func checkout() { items.removeAll() }
        }
        """
        let candidates = ViewModelDiscoverer.discover(source: source, file: "Cart.swift")
        let load = candidates.first?.actions.first { $0.name == "load" }
        #expect(load?.isClockDeterministic == true)
        #expect(load?.isAsync == true)
        let checkout = candidates.first?.actions.first { $0.name == "checkout" }
        #expect(checkout?.isClockDeterministic == false)
    }
}
