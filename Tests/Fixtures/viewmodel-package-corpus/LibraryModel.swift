// PROTOTYPE — a verify-ready view model packaged as its OWN SwiftPM module
// and verified via a package PATH-DEPENDENCY (not inlined): the verifier
// `import`s this module, so the view model + its `Store` protocol come from
// a real compiled package. This is the productionization shape — the MVVM
// analog of the algebraic `--corpus-module` path-dependency, and the route
// by which an app's own packaged ViewModels would be verified. Public
// surface so the cross-module verifier can construct + read it.

import Combine

public protocol Store: Sendable {
    func save(_ id: Int) async throws
    func count() -> Int
}

public final class LibraryModel: ObservableObject {
    @Published public var selectedIDs: Set<Int> = []
    @Published public var items: [Int] = [1, 2, 3]
    @Published public var cursor: Int = 0
    let store: Store

    public init(store: Store) {
        self.store = store
    }

    /// Idempotent → bothPass.
    public func selectAll() {
        selectedIDs = Set(items)
    }

    /// NOT idempotent — advances the cursor → defaultFails.
    public func selectNext() {
        cursor = min(cursor + 1, items.count - 1)
    }
}
