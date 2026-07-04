// Item 2 slice 3 — the child of an `IdentifiedActionOf<Child>` composition.
// A self-contained TCA reducer (no custom DependencyKey, so it co-compiles
// against CA alone) whose State is `Identifiable` with a `UUID` id — the
// dominant real-world `IdentifiedArray` id shape (slice-3 recount: 6/8). Its
// `increment` case is payload-free, so `IdentifiedActionResolver` picks it as
// the depth-0 child action for the parent's `.element(id:action:)` value.
//
// `import Foundation` is required: the verify workdir co-compiles this file into
// an isolated target where `import ComposableArchitecture` does not re-export
// `Foundation`, so `UUID` must be imported explicitly (a faithful self-contained
// file using `UUID` would do the same).
import ComposableArchitecture
import Foundation

@Reducer
struct Row {
    // `id` is defaulted (explicit `UUID` annotation, fixed literal) so `Row`'s
    // State is zero-arg constructible — the child then also surfaces a
    // standalone determinism identity in the survey (deterministic: the default
    // is a constant, not `UUID()`). The parent drives real `Row` state via
    // `.forEach`; the canned-UUID element the parent emits is a *different*
    // (all-zero) id and no-ops against the empty initial `rows`.
    @ObservableState
    struct State: Equatable, Identifiable {
        var id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        var count = 0
    }

    enum Action {
        case increment
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .increment:
                state.count += 1
                return .none
            }
        }
    }
}
