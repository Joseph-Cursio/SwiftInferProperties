import Foundation
import SwiftParser
import SwiftSyntax

/// PROTOTYPE — SwiftSyntax pass that recognises SwiftUI MVVM view models
/// (`@Observable` macro or `: ObservableObject`) and emits each as a
/// `ViewModelCandidate`: its stored properties (State) + its
/// state-mutating methods (the Action alphabet). This is the MVVM
/// carrier `ReducerDiscoverer` is missing — a view model is a reducer in
/// disguise (stored props = State, each mutating method = an Action),
/// but its methods are ordinary instance methods, not a `(State, Action)
/// -> State` signature, so the signature scanner never sees them.
///
/// **Cross-file / extension-aware.** A view model's methods routinely
/// live in `extension VM { … }` blocks across several files (e.g.
/// `VM+Selection.swift`, `VM+Filtering.swift`). The directory scan
/// therefore accumulates per-type info from *all* files into one table
/// keyed by type name, then assembles candidates — so methods in
/// extensions are attributed to the `@Observable` class declared
/// elsewhere.
///
/// **Action heuristic (two-pass).** A method is an action if it mutates
/// state directly (assigns a stored field, or calls a curated mutator on
/// one) OR transitively (calls another action). Pure queries (no
/// mutation, e.g. computed-value helpers) are excluded. This is a
/// prototype heuristic — body-level data-flow, not type-checked — and
/// stays conservative + curated like the algebraic vocabulary lists.
public enum ViewModelDiscoverer {

    public static func discover(source: String, file: String) -> [ViewModelCandidate] {
        var table: [String: RawTypeInfo] = [:]
        accumulate(source: source, file: file, into: &table)
        return assemble(table)
    }

    public static func discover(file: URL) throws -> [ViewModelCandidate] {
        let source = try String(contentsOf: file, encoding: .utf8)
        return discover(source: source, file: file.path)
    }

    /// Recursively scan every `.swift` file under `directory`, merging
    /// per-type info across files (sorted-path order for determinism)
    /// before assembling candidates.
    public static func discover(directory: URL) throws -> [ViewModelCandidate] {
        let swiftFiles = SwiftSourceFiles.sorted(in: directory)
        var table: [String: RawTypeInfo] = [:]
        for fileURL in swiftFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            accumulate(source: source, file: fileURL.path, into: &table)
        }
        return assemble(table)
    }

    // MARK: - Phase 1 — accumulate

    private static func accumulate(
        source: String,
        file: String,
        into table: inout [String: RawTypeInfo]
    ) {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: file, tree: tree)
        let visitor = ViewModelDiscoveryVisitor(file: file, converter: converter)
        visitor.walk(tree)
        for (typeName, partial) in visitor.collected {
            table[typeName, default: RawTypeInfo()].merge(partial)
        }
    }

    // MARK: - Phase 2 — assemble

    /// Resolve each `@Observable` / `ObservableObject` type's action
    /// alphabet and emit a `ViewModelCandidate`. Non-observable types in
    /// the table (collected because they declared methods) are dropped.
    static func assemble(_ table: [String: RawTypeInfo]) -> [ViewModelCandidate] {
        var candidates: [ViewModelCandidate] = []
        for (typeName, info) in table {
            guard let observability = info.observability,
                  let location = info.declLocation else {
                continue
            }
            var state: [ViewModelStateField] = []
            var excluded: [ViewModelExcludedField] = []
            for field in info.rawFields {
                if let reason = classifyExclusion(field) {
                    excluded.append(
                        ViewModelExcludedField(name: field.name, typeText: field.typeText, reason: reason)
                    )
                } else {
                    state.append(
                        ViewModelStateField(name: field.name, typeText: field.typeText, isMutable: field.isMutable)
                    )
                }
            }
            // Action detection keys on the *State* surface only — assigning
            // an injected dependency or a transient `@ObservationIgnored`
            // flag is reconfiguration / bookkeeping, not a state transition.
            let storedNames = Set(state.map(\.name))
            let actions = resolveActions(methods: info.methods, storedNames: storedNames)
            candidates.append(
                ViewModelCandidate(
                    location: location,
                    typeName: typeName,
                    observability: observability,
                    stateFields: state.sorted { $0.name < $1.name },
                    excludedFields: excluded.sorted { $0.name < $1.name },
                    actions: actions,
                    constructibility: constructibility(of: info),
                    initParameters: info.declaredInits.first ?? []
                )
            )
        }
        return candidates.sorted { lhs, rhs in
            if lhs.location != rhs.location { return lhs.location < rhs.location }
            return lhs.typeName < rhs.typeName
        }
    }

    /// Classify a stored field as a non-State exclusion, or `nil` if it is
    /// genuine observable State. `@ObservationIgnored` → plumbing /
    /// control flag; an existential (`any Foo`) / `*Protocol`-typed /
    /// `AnyCancellable` field → an injected dependency.
    static func classifyExclusion(_ field: RawStoredField) -> ViewModelFieldExclusion? {
        if field.isObservationIgnored { return .observationIgnored }
        if isDependencyType(field.typeText) { return .dependency }
        // A stored field that doesn't self-initialize (no default, not an
        // Optional `var`) must be supplied at construction — structurally an
        // injected dependency, not observable State (and often non-Equatable,
        // so it must stay out of the verifier's field comparison).
        if !(field.hasDefault || (field.isOptional && field.isMutable)) {
            return .dependency
        }
        return nil
    }

    /// `Type()` constructs the view model iff every stored property is
    /// self-initializing (has a default, or is an Optional `var` →
    /// auto-nil) AND a no-arg initializer is reachable (no custom init, or
    /// an explicit zero-arg one). A field that needs an init value — an
    /// injected dependency `let storage: Foo` — makes it `.requiresArguments`.
    static func constructibility(of info: RawTypeInfo) -> ViewModelConstructibility {
        let needsValue = info.rawFields
            .filter { !($0.hasDefault || ($0.isOptional && $0.isMutable)) }
            .map(\.name)
        if !needsValue.isEmpty {
            return .requiresArguments(needsValue.sorted())
        }
        // A custom parameterized init suppresses the synthesized `init()`.
        let initParamCounts = info.declaredInits.map(\.count)
        if !initParamCounts.isEmpty, !initParamCounts.contains(0) {
            return .requiresArguments(["<no zero-argument initializer>"])
        }
        return .zeroArgument
    }

    private static func isDependencyType(_ typeText: String) -> Bool {
        if typeText.contains("any ") { return true }          // existential service
        if typeText.contains("AnyCancellable") { return true } // Combine bag
        let base = typeText.trimmingCharacters(in: CharacterSet(charactersIn: "?! "))
        return base.hasSuffix("Protocol")
    }

    /// Two-pass action resolution: seed with direct mutators, then add
    /// methods that transitively drive an action until the set is stable.
    /// Internal (not `private`) so `ConventionRoleDiscoverer` reuses the same
    /// action alphabet resolution for VIPER/MVP roles.
    static func resolveActions(
        methods: [RawMethod],
        storedNames: Set<String>
    ) -> [ViewModelAction] {
        let ownNames = Set(methods.map(\.name))
        func directlyMutates(_ method: RawMethod) -> Bool {
            !method.signals.assignedRoots.isDisjoint(with: storedNames)
                || !method.signals.mutatorCallReceivers.isDisjoint(with: storedNames)
        }
        var actionNames = Set(methods.filter(directlyMutates).map(\.name))
        var changed = true
        while changed {
            changed = false
            for method in methods where !actionNames.contains(method.name) {
                let drivesAction = !method.signals.calledMethodNames
                    .intersection(ownNames)
                    .isDisjoint(with: actionNames)
                if drivesAction {
                    actionNames.insert(method.name)
                    changed = true
                }
            }
        }
        return methods
            .filter { actionNames.contains($0.name) }
            .map { method in
                ViewModelAction(
                    name: method.name,
                    parameterTypes: method.parameterTypes,
                    firstParameterLabel: method.firstParameterLabel,
                    parameters: method.parameters,
                    isAsync: method.isAsync,
                    isThrows: method.isThrows,
                    mutatesStateDirectly: directlyMutates(method)
                )
            }
            .sorted { $0.name < $1.name }
    }
}

// MARK: - Per-type accumulator

/// Mutable per-type info gathered across the class declaration + all its
/// extensions. `observability` / `declLocation` are set only from the
/// class decl; methods + stored fields merge from every source.
struct RawTypeInfo {
    var observability: ViewModelObservability?
    var declLocation: String?
    var rawFields: [RawStoredField] = []
    var methods: [RawMethod] = []
    /// Parameters of each declared initializer — drives the zero-arg
    /// constructibility gate (a parameterized init suppresses the
    /// synthesized `init()`) and dependency-faking construction.
    var declaredInits: [[ViewModelInitParameter]] = []
    /// `<file>:<line>` of the type's `class` declaration, set for *every*
    /// class (not gated on observability). Non-`nil` iff the type is a class —
    /// the recognition signal `ConventionRoleDiscoverer` uses (presenters /
    /// interactors are reference types).
    var classLocation: String?
    /// Inherited-type names from the class declaration + any extensions —
    /// the conformance signal for convention recognition (VIPER
    /// `FooInteractor: FooInteractorInput`). Not used by MVVM assembly.
    var inheritedTypeNames: [String] = []

    mutating func merge(_ other: Self) {
        observability = observability ?? other.observability
        declLocation = declLocation ?? other.declLocation
        classLocation = classLocation ?? other.classLocation
        rawFields.append(contentsOf: other.rawFields)
        methods.append(contentsOf: other.methods)
        declaredInits.append(contentsOf: other.declaredInits)
        inheritedTypeNames.append(contentsOf: other.inheritedTypeNames)
    }
}

/// A stored property gathered during the scan, before State-vs-dependency
/// classification (`ViewModelDiscoverer.classifyExclusion`).
struct RawStoredField: Equatable {
    let name: String
    let typeText: String
    let isMutable: Bool
    let isObservationIgnored: Bool
    /// `true` when the binding has an initializer (`var x = 0` / `var x: T = …`).
    let hasDefault: Bool
    var isOptional: Bool { typeText.hasSuffix("?") }
}

/// One instance method gathered during the scan, with its precomputed
/// body mutation signals.
struct RawMethod: Equatable {
    let name: String
    let parameterTypes: [String]
    let firstParameterLabel: String?
    /// Full label+type per parameter — the source of truth for synthetic
    /// Action-enum case + dispatch-call emission.
    let parameters: [ViewModelActionParameter]
    let isAsync: Bool
    let isThrows: Bool
    let signals: ViewModelMethodSignals
}
