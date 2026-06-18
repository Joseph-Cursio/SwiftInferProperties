import Foundation
import SwiftInferCore
import Testing

/// PROTOTYPE — the SwiftUI MVVM carrier recognizer. Detects `@Observable`
/// / `ObservableObject` view models, extracts their stored properties
/// (State) and their state-mutating methods (the Action alphabet), and
/// merges methods declared in extensions across files.
@Suite("ViewModelDiscoverer — MVVM carrier recognizer (prototype)")
struct ViewModelDiscovererTests {

    /// A self-contained `@Observable` selection view model modelled on the
    /// real `ViolationInspectorViewModel+Selection`: a dual selection
    /// representation, direct mutators, a transitive mutator, and a pure
    /// query that must NOT be classified as an action.
    private static let selectionSource = """
    import Observation

    @Observable
    final class SelectionViewModel {
        var selectedID: UUID?
        var selectedIDs: Set<UUID> = []
        var items: [Item] = []
        var isUpdating: Bool = false
        static let shared = SelectionViewModel()

        func selectAll() {
            selectedIDs = Set(items.map(\\.id))
        }

        func deselectAll() {
            selectedIDs.removeAll()
        }

        func setPrimary(_ id: UUID?) {
            selectedID = id
            selectedIDs = id.map { [$0] } ?? []
        }

        func selectFirst() {
            setPrimary(items.first?.id)
        }

        func isEmpty() -> Bool {
            selectedIDs.isEmpty
        }

        private func internalReset() {
            selectedIDs.removeAll()
        }
    }
    """

    @Test("detects an @Observable view model with its state fields")
    func detectsObservableMacroAndState() {
        let candidates = ViewModelDiscoverer.discover(source: Self.selectionSource, file: "VM.swift")
        #expect(candidates.count == 1)
        let viewModel = candidates[0]
        #expect(viewModel.typeName == "SelectionViewModel")
        #expect(viewModel.observability == .observableMacro)
        // `static let shared` is excluded; the four instance stored props remain.
        let fieldNames = Set(viewModel.stateFields.map(\.name))
        #expect(fieldNames == ["selectedID", "selectedIDs", "items", "isUpdating"])
    }

    @Test("emits state-mutating methods as the action alphabet, excluding pure queries")
    func actionAlphabetExcludesQueries() {
        let viewModel = ViewModelDiscoverer.discover(source: Self.selectionSource, file: "VM.swift")[0]
        let actionNames = Set(viewModel.actions.map(\.name))
        // selectAll / deselectAll / setPrimary mutate directly; selectFirst
        // mutates transitively (calls setPrimary). isEmpty is a pure query;
        // internalReset is private — both excluded.
        #expect(actionNames == ["selectAll", "deselectAll", "setPrimary", "selectFirst"])
        #expect(!actionNames.contains("isEmpty"))
        #expect(!actionNames.contains("internalReset"))
    }

    @Test("marks transitive mutators (drives another action) distinctly from direct mutators")
    func transitiveMutatorMarked() {
        let viewModel = ViewModelDiscoverer.discover(source: Self.selectionSource, file: "VM.swift")[0]
        let direct = Set(viewModel.actions.filter(\.mutatesStateDirectly).map(\.name))
        let transitive = Set(viewModel.actions.filter { !$0.mutatesStateDirectly }.map(\.name))
        #expect(direct == ["selectAll", "deselectAll", "setPrimary"])
        #expect(transitive == ["selectFirst"])
    }

    @Test("captures action payload types + async/throws")
    func actionPayloadAndEffects() {
        let viewModel = ViewModelDiscoverer.discover(source: Self.selectionSource, file: "VM.swift")[0]
        let setPrimary = viewModel.actions.first { $0.name == "setPrimary" }
        #expect(setPrimary?.parameterTypes == ["UUID?"])
        let selectAll = viewModel.actions.first { $0.name == "selectAll" }
        #expect(selectAll?.parameterTypes.isEmpty == true)
        #expect(selectAll?.isAsync == false)
    }

    @Test("recognizes ObservableObject conformance + async/throws actions")
    func detectsObservableObject() {
        let source = """
        import Combine

        final class LoaderViewModel: ObservableObject {
            @Published var items: [String] = []
            @Published var isLoading = false

            func load() async throws {
                isLoading = true
                items = try await fetch()
            }
        }
        """
        let candidates = ViewModelDiscoverer.discover(source: source, file: "Loader.swift")
        #expect(candidates.count == 1)
        #expect(candidates[0].observability == .observableObject)
        let load = candidates[0].actions.first { $0.name == "load" }
        #expect(load?.isAsync == true)
        #expect(load?.isThrows == true)
    }

    @Test("merges methods declared in extensions across files")
    func mergesExtensionMethodsAcrossFiles() throws {
        // The recognizer must attribute extension methods (a common MVVM
        // layout: VM+Selection.swift, VM+Loading.swift) to the @Observable
        // class declared in another file. Exercised via the directory scan
        // over two staged sources.
        let base = """
        import Observation
        @Observable final class SplitViewModel {
            var count: Int = 0
        }
        """
        let ext = """
        extension SplitViewModel {
            func bump() { count += 1 }
            func reset() { count = 0 }
        }
        """
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-split-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(base.utf8).write(to: dir.appendingPathComponent("SplitViewModel.swift"))
        try Data(ext.utf8).write(to: dir.appendingPathComponent("SplitViewModel+Actions.swift"))

        let candidates = try ViewModelDiscoverer.discover(directory: dir)
        #expect(candidates.count == 1)
        #expect(Set(candidates[0].actions.map(\.name)) == ["bump", "reset"])
    }

    @Test("filters injected dependencies + @ObservationIgnored plumbing out of State")
    func filtersDependenciesFromState() {
        // Mirrors the real ViolationInspectorViewModel: genuine observed
        // state alongside a protocol-typed service, an existential service,
        // an AnyCancellable bag, and @ObservationIgnored control flags.
        let source = """
        import Observation
        import Combine

        @Observable
        final class InspectorViewModel {
            var violations: [Violation] = []
            var selectedID: UUID?
            var storage: ViolationStorageProtocol
            var analyzer: (any WorkspaceAnalyzerProtocol)?
            @ObservationIgnored var cancellables = Set<AnyCancellable>()
            @ObservationIgnored var isUpdating = false

            func select(_ id: UUID) { selectedID = id }
        }
        """
        let viewModel = ViewModelDiscoverer.discover(source: source, file: "Inspector.swift")[0]
        // State keeps only the genuine observed properties.
        #expect(Set(viewModel.stateFields.map(\.name)) == ["violations", "selectedID"])
        // The rest are excluded, tagged with why.
        let byName = Dictionary(uniqueKeysWithValues: viewModel.excludedFields.map { ($0.name, $0.reason) })
        #expect(byName["storage"] == .dependency)
        #expect(byName["analyzer"] == .dependency)
        #expect(byName["cancellables"] == .observationIgnored)
        #expect(byName["isUpdating"] == .observationIgnored)
        // `select` still detected — it assigns the real State field selectedID.
        #expect(viewModel.actions.map(\.name) == ["select"])
    }

    @Test("constructibility: all-defaulted view model is zero-arg, a required dependency gates it")
    func constructibilityGate() {
        let constructible = """
        import Observation
        @Observable final class A {
            var count = 0
            var selected: Int?
            func reset() { count = 0 }
        }
        """
        #expect(ViewModelDiscoverer.discover(source: constructible, file: "A.swift")[0].isZeroArgConstructible)

        // A required (non-defaulted, non-Optional) dependency + a custom
        // parameterized init → not zero-arg constructible; verify must skip.
        let gated = """
        import Observation
        @Observable final class B {
            var ready = false
            let storage: StorageProtocol
            init(storage: StorageProtocol) { self.storage = storage }
            func reset() { ready = false }
        }
        """
        let candidate = ViewModelDiscoverer.discover(source: gated, file: "B.swift")[0]
        #expect(candidate.constructibility == .requiresArguments(["storage"]))
        #expect(!candidate.isZeroArgConstructible)
    }

    @Test("plain (non-observable) classes are not emitted")
    func nonObservableClassIgnored() {
        let source = """
        final class PlainService {
            var cache: [String: Int] = [:]
            func store(_ key: String, _ value: Int) { cache[key] = value }
        }
        """
        #expect(ViewModelDiscoverer.discover(source: source, file: "Plain.swift").isEmpty)
    }
}
