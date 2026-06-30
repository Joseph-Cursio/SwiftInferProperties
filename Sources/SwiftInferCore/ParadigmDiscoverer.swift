import Foundation

/// Corpus-level discovery seam for `StatefulRole` (Phase 1 of
/// `docs/stateful-role-discoverer-design.md`).
///
/// ## Why corpus-level, not per-declaration
///
/// Phase 0 introduced a per-declaration `RolePolicy` engine. Phase 1 found it is
/// the wrong granularity for the existing discoverers:
///
/// - `ReducerDiscoverer` is single-pass per file — a per-decl fit.
/// - `ViewModelDiscoverer` is **corpus-level + two-phase**: it *accumulates*
///   per-type info across files (a view model's methods routinely live in
///   `extension VM {}` blocks in other files), then *assembles* candidates from
///   the merged table, with a fixed-point transitive-action resolution that
///   needs the type's full method set. A per-decl `buildRole(classDecl)` cannot
///   see the class's extensions — even in the same file — so it cannot
///   reproduce that.
///
/// So the seam sits at the corpus level, and each paradigm **wraps its existing,
/// heavily-tested discoverer** and adapts the result to `StatefulRole` via the
/// Phase 0 adapters. This reuses the recognition + extraction + cross-file
/// machinery wholesale (the design's "reuse" column) and makes parity with the
/// legacy discoverers true by construction rather than something a reimplemented
/// extraction has to chase.
public protocol ParadigmDiscoverer: Sendable {

    /// Identifier for diagnostics (`"reducer"`, `"mvvm"`). Not a `Paradigm` —
    /// the reducer discoverer spans the `tca` and `redux` families; the precise
    /// paradigm is set per-role by the adapter from `ReducerCarrierKind`.
    var name: String { get }

    /// Discover roles in a single source string.
    func discover(source: String, file: String) -> [StatefulRole]

    /// Discover roles across every `.swift` file under a directory (handles the
    /// cross-file accumulation internally where the paradigm needs it).
    func discover(directory: URL) throws -> [StatefulRole]
}

/// TCA / Elm / ReSwift / Mobius / Workflow reducers, via `ReducerDiscoverer`.
public struct TCAReducerParadigm: ParadigmDiscoverer {
    public let name = "reducer"

    public init() { /* stateless */ }

    public func discover(source: String, file: String) -> [StatefulRole] {
        ReducerDiscoverer.discover(source: source, file: file).map { $0.asStatefulRole() }
    }

    public func discover(directory: URL) throws -> [StatefulRole] {
        try ReducerDiscoverer.discover(directory: directory).map { $0.asStatefulRole() }
    }
}

/// SwiftUI MVVM view models (`@Observable` / `ObservableObject`), via
/// `ViewModelDiscoverer` — including its cross-file accumulate/assemble.
public struct MVVMParadigm: ParadigmDiscoverer {
    public let name = "mvvm"

    public init() { /* stateless */ }

    public func discover(source: String, file: String) -> [StatefulRole] {
        ViewModelDiscoverer.discover(source: source, file: file).map { $0.asStatefulRole() }
    }

    public func discover(directory: URL) throws -> [StatefulRole] {
        try ViewModelDiscoverer.discover(directory: directory).map { $0.asStatefulRole() }
    }
}

/// Runs a set of `ParadigmDiscoverer`s and unifies their output into one
/// `[StatefulRole]` stream — the single entry point a caller uses instead of
/// reaching for `ReducerDiscoverer` / `ViewModelDiscoverer` directly.
public struct UnifiedRoleDiscoverer: Sendable {

    public let paradigms: [any ParadigmDiscoverer]

    public init(paradigms: [any ParadigmDiscoverer]) {
        self.paradigms = paradigms
    }

    /// The standard registry: the two paradigms with first-class support today.
    /// Phase 2 appends `ReduxPolicy` and the convention-driven VIPER/MVP/MVC
    /// discoverers.
    public static let standard = Self(
        paradigms: [TCAReducerParadigm(), MVVMParadigm()]
    )

    public func discover(source: String, file: String) -> [StatefulRole] {
        paradigms.flatMap { $0.discover(source: source, file: file) }
    }

    public func discover(directory: URL) throws -> [StatefulRole] {
        try paradigms.flatMap { try $0.discover(directory: directory) }
    }
}
