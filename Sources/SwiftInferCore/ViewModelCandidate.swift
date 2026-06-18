import Foundation

/// PROTOTYPE (SwiftUI MVVM carrier) — one detected `@Observable` /
/// `ObservableObject` view model, modelled as a reducer-in-disguise:
///
///   | Reducer            | ViewModel                                  |
///   |--------------------|--------------------------------------------|
///   | `State`            | the stored properties (`stateFields`)      |
///   | `Action` alphabet  | the state-mutating methods (`actions`)     |
///   | `reduce(into:_:)`  | each method body mutating `self`           |
///
/// This is the discovery shape the v2.0 interaction-invariant families
/// (idempotence / cardinality / biconditional / referential-integrity /
/// conservation) need to fire on MVVM code — `ReducerDiscoverer` only
/// recognises reducer *signatures* (TCA / Elm / ReSwift / Mobius /
/// Workflow), so an `@Observable` class with `func selectAll()` etc.
/// currently yields zero candidates. The candidate captures enough to
/// (a) render the action alphabet for a human, and (b) feed a future
/// witness strategy that constructs the view model and drives its
/// methods as the action sequence.
public struct ViewModelCandidate: Sendable, Equatable {

    /// `<path>:<line>` of the type declaration — same click-target UX as
    /// `ReducerCandidate.location`.
    public let location: String

    /// The view model type name (`"ViolationInspectorViewModel"`).
    public let typeName: String

    /// How observability was detected — `@Observable` macro vs
    /// `: ObservableObject` conformance.
    public let observability: ViewModelObservability

    /// The stored instance properties that form the observable State —
    /// the surface the interaction invariants reason about. Excludes
    /// `static` props, computed props, `@ObservationIgnored` plumbing, and
    /// injected dependencies (see `excludedFields`).
    public let stateFields: [ViewModelStateField]

    /// Stored properties deliberately excluded from State, with the reason
    /// — `@ObservationIgnored` plumbing / transient control flags, or
    /// injected dependencies (existential / `*Protocol`-typed services,
    /// `AnyCancellable` bags). Surfaced for transparency so a human can
    /// see what was filtered and why.
    public let excludedFields: [ViewModelExcludedField]

    /// The action alphabet — instance methods that mutate State, either
    /// directly (assign a State field / call a mutator on one) or
    /// transitively (call another action). Sorted by name for stable
    /// output.
    public let actions: [ViewModelAction]

    public init(
        location: String,
        typeName: String,
        observability: ViewModelObservability,
        stateFields: [ViewModelStateField],
        excludedFields: [ViewModelExcludedField] = [],
        actions: [ViewModelAction]
    ) {
        self.location = location
        self.typeName = typeName
        self.observability = observability
        self.stateFields = stateFields
        self.excludedFields = excludedFields
        self.actions = actions
    }
}

/// A stored property filtered out of a view model's State, tagged with
/// why. Kept on the candidate for explainability (the recognizer never
/// silently drops a field).
public struct ViewModelExcludedField: Sendable, Equatable, Codable {
    public let name: String
    public let typeText: String
    public let reason: ViewModelFieldExclusion

    public init(name: String, typeText: String, reason: ViewModelFieldExclusion) {
        self.name = name
        self.typeText = typeText
        self.reason = reason
    }
}

/// PROTOTYPE — one candidate interaction invariant statically surfaced
/// over a `ViewModelCandidate` (its action alphabet + State surface),
/// before any measured verification. The five families
/// (`InteractionInvariantFamily`) are the same ones the reducer pipeline
/// runs; this is the MVVM-shaped *discovery* of them. Always `.possible`
/// — unverified; execution (a future witness strategy that constructs the
/// view model) decides.
public struct ViewModelInteractionCandidate: Sendable, Equatable {
    /// Which interaction family this candidate belongs to.
    public let family: InteractionInvariantFamily
    /// The view model type the candidate was surfaced on.
    public let typeName: String
    /// The actions and/or State fields the invariant ranges over (e.g.
    /// `["selectAll()"]` for idempotence, `["selectedViolationId"]` for
    /// referential integrity).
    public let subjects: [String]
    /// One-line human rationale — why this shape suggests the invariant.
    public let rationale: String

    public init(
        family: InteractionInvariantFamily,
        typeName: String,
        subjects: [String],
        rationale: String
    ) {
        self.family = family
        self.typeName = typeName
        self.subjects = subjects
        self.rationale = rationale
    }
}

/// Why a stored property is not part of State.
public enum ViewModelFieldExclusion: String, Sendable, Equatable, Codable {
    /// `@ObservationIgnored` — not observed; plumbing (Combine bags) or
    /// transient control flags (`isUpdatingSelection`, `isInitialized`).
    case observationIgnored = "observation-ignored"
    /// Injected dependency — an existential (`any Foo`) / `*Protocol`-typed
    /// service, or an `AnyCancellable` Combine bag.
    case dependency
}

/// How a view model's observability was recognised.
public enum ViewModelObservability: String, Sendable, Equatable, Codable {
    /// The Observation framework `@Observable` macro.
    case observableMacro = "observable-macro"
    /// Combine-era `: ObservableObject` conformance.
    case observableObject = "observable-object"
}

/// One stored property of a view model — the State surface.
public struct ViewModelStateField: Sendable, Equatable, Codable {
    public let name: String
    public let typeText: String
    /// `let` constants are state-but-immutable; `var`s are the mutable
    /// surface the action alphabet writes to.
    public let isMutable: Bool

    public init(name: String, typeText: String, isMutable: Bool) {
        self.name = name
        self.typeText = typeText
        self.isMutable = isMutable
    }
}

/// One action in a view model's action alphabet — a state-mutating
/// method. `parameterTypes` is the payload a generator would have to
/// produce (empty = a nullary action like `selectAll()` / `deselectAll()`).
public struct ViewModelAction: Sendable, Equatable, Codable {
    public let name: String
    public let parameterTypes: [String]
    public let isAsync: Bool
    public let isThrows: Bool
    /// `true` when the body directly assigns a stored field or calls a
    /// mutator on one; `false` when the method qualifies only because it
    /// calls another action (transitive). Surfaced so a human can see
    /// which actions are leaf mutators.
    public let mutatesStateDirectly: Bool

    public init(
        name: String,
        parameterTypes: [String],
        isAsync: Bool,
        isThrows: Bool,
        mutatesStateDirectly: Bool
    ) {
        self.name = name
        self.parameterTypes = parameterTypes
        self.isAsync = isAsync
        self.isThrows = isThrows
        self.mutatesStateDirectly = mutatesStateDirectly
    }

    /// Rendered `name(Type, Type)` / `name()` action signature for output.
    public var signature: String {
        "\(name)(\(parameterTypes.joined(separator: ", ")))"
    }
}
