import Foundation
@testable import SwiftInferCore
import Testing

/// Phase 1 — the corpus-level `UnifiedRoleDiscoverer` wraps the existing
/// `ReducerDiscoverer` / `ViewModelDiscoverer` and unifies their output as
/// `StatefulRole`. These prove (a) both paradigms surface through one seam and
/// (b) MVVM's cross-file accumulate/assemble survives the wrapping — the case
/// the per-decl Phase 0 engine could not express.
@Suite("UnifiedRoleDiscoverer (Phase 1)")
struct UnifiedRoleDiscovererTests {

    // MARK: - Both paradigms through one seam

    @Test("Discovers a reducer and a view model from one source")
    func discoversBothParadigms() {
        let source = """
        struct AppState { var count = 0 }
        enum AppAction { case bump }

        func reduce(_ state: AppState, _ action: AppAction) -> AppState {
            return state
        }

        @Observable
        final class TodoViewModel {
            var items: [String] = []
            func add(_ item: String) { items.append(item) }
        }
        """
        let roles = UnifiedRoleDiscoverer.standard.discover(source: source, file: "F.swift")

        let byParadigm = Dictionary(grouping: roles, by: \.paradigm)
        // Free-function (S,A)->S reducer → redux family; the @Observable class → mvvm.
        #expect(byParadigm[.redux]?.count == 1)
        #expect(byParadigm[.mvvm]?.count == 1)

        let reducer = byParadigm[.redux]?.first
        #expect(reducer?.typeName == "reduce")
        #expect(reducer?.state == .namedType("AppState"))
        #expect(reducer?.construction == .freeFunction(name: "reduce"))

        let viewModel = byParadigm[.mvvm]?.first
        #expect(viewModel?.typeName == "TodoViewModel")
        #expect(viewModel?.actions.map(\.name) == ["add"])
    }

    // MARK: - Cross-file MVVM through the seam (the Phase 1 finding)

    @Test("A view model whose methods span files assembles into one role")
    func crossFileViewModelAssembles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StatefulRoleP1-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try """
        @Observable
        final class TodoViewModel {
            var items: [String] = []
            func add(_ item: String) { items.append(item) }
        }
        """.write(to: dir.appendingPathComponent("TodoViewModel.swift"), atomically: true, encoding: .utf8)

        try """
        extension TodoViewModel {
            func clear() { items.removeAll() }
        }
        """.write(to: dir.appendingPathComponent("TodoViewModel+Clear.swift"), atomically: true, encoding: .utf8)

        let roles = try UnifiedRoleDiscoverer.standard.discover(directory: dir)
        let mvvm = roles.filter { $0.paradigm == .mvvm }
        #expect(mvvm.count == 1)
        // The extension method in the *other* file is attributed to the class —
        // the cross-file merge a per-decl policy could never have done.
        #expect(mvvm.first?.actions.map(\.name) == ["add", "clear"])
    }

    // MARK: - Wrapper fidelity (no information lost vs the legacy discoverer)

    @Test("MVVMParadigm is a faithful pass-through of ViewModelDiscoverer")
    func mvvmWrapperParity() {
        let source = """
        @Observable
        final class VM {
            var x = 0
            func bump() { x += 1 }
        }
        """
        let viaSeam = MVVMParadigm().discover(source: source, file: "F.swift")
        let viaLegacy = ViewModelDiscoverer.discover(source: source, file: "F.swift").map { $0.asStatefulRole() }
        #expect(viaSeam == viaLegacy)
    }

    @Test("TCAReducerParadigm is a faithful pass-through of ReducerDiscoverer")
    func reducerWrapperParity() {
        let source = """
        func reduce(_ state: AppState, _ action: AppAction) -> AppState { return state }
        """
        let viaSeam = TCAReducerParadigm().discover(source: source, file: "F.swift")
        let viaLegacy = ReducerDiscoverer.discover(source: source, file: "F.swift").map { $0.asStatefulRole() }
        #expect(viaSeam == viaLegacy)
    }
}
