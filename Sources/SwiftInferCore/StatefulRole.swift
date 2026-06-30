import SwiftEffectInference

/// The unified shape every state architecture (TCA, MVVM, Redux/Elm, VIPER,
/// MVP, MVC) reduces to: a thing that owns **state** and exposes **mutation
/// entry points** (an action alphabet), plus how to **construct** an instance
/// to drive and which **collaborators** to fake.
///
/// Phase 0 of the `StatefulRoleDiscoverer` design
/// (`docs/stateful-role-discoverer-design.md`). This generalizes — and is
/// adapter-compatible with — the two existing candidate types:
///
/// - `ReducerCandidate` (TCA / Elm / ReSwift / Mobius / Workflow), and
/// - `ViewModelCandidate` (MVVM), already documented as a "reducer-in-disguise".
///
/// Phase 0 introduces this type *alongside* those, with adapters
/// (`asStatefulRole`) proving the lift; it changes no existing behavior. The
/// existing discoverers and their `Codable` wire shapes are untouched.
public struct StatefulRole: Sendable, Equatable {

    /// `<path>:<line>` of the declaration — same click-target UX as
    /// `ReducerCandidate.location` / `ViewModelCandidate.location`.
    public let location: String

    /// The role's type name (or, for a free-function reducer, its function
    /// name).
    public let typeName: String

    /// Which architecture this role belongs to.
    public let paradigm: Paradigm

    /// How the role was structurally recognized — surfaced for the same
    /// transparency reason `ViewModelExcludedField` carries its exclusion
    /// reason: a human can see *why* a declaration was treated as this role.
    public let recognizedBy: RecognitionKind

    /// The state surface the invariants reason about — a named `State` type
    /// (reducer) or the stored properties (viewmodel-style).
    public let state: StateSurface

    /// The action alphabet — the mutation entry points. Unifies a reducer's
    /// `Action` cases and a viewmodel's state-mutating methods.
    public let actions: [RoleAction]

    /// How the verify harness obtains something to drive — a free function it
    /// calls directly, or an instance it must build (injecting fakes).
    public let construction: Construction

    /// Protocols the role calls *out* to, recognized so they can be faked. A
    /// `.dependency` is a no-op fake; an `.output` is a recording fake the
    /// property asserts against (the capability MVP/VIPER need; empty for the
    /// Phase 0 adapters).
    public let collaborators: [Collaborator]

    /// The role's effect on the SwiftEffectInference lattice, when known. A
    /// `.pure` reducer can be fuzzed as a free function with no harness; an
    /// effectful role needs the instance + mock path. `nil` when not yet
    /// classified (the adapters map only the *sound* signals — see
    /// `asStatefulRole`).
    public let effect: Effect?

    public init(
        location: String,
        typeName: String,
        paradigm: Paradigm,
        recognizedBy: RecognitionKind,
        state: StateSurface,
        actions: [RoleAction],
        construction: Construction,
        collaborators: [Collaborator] = [],
        effect: Effect? = nil
    ) {
        self.location = location
        self.typeName = typeName
        self.paradigm = paradigm
        self.recognizedBy = recognizedBy
        self.state = state
        self.actions = actions
        self.construction = construction
        self.collaborators = collaborators
        self.effect = effect
    }
}

/// The state architectures the discoverer can recognize. The reducer families
/// (Elm / ReSwift / Mobius / Workflow) fold into `.redux` at this granularity;
/// `ReducerCandidate.carrierKind` retains the finer distinction.
public enum Paradigm: String, Sendable, Equatable, Codable, CaseIterable {
    case tca
    case mvvm
    case redux
    case viper
    case mvp
    case mvc
}

/// How a role was structurally recognized.
public enum RecognitionKind: String, Sendable, Equatable, Codable {
    /// Matched a reducer function signature shape (`(S, A) -> S`, …).
    case signatureShape = "signature-shape"
    /// Conforms to a marker protocol (`Reducer`, `ObservableObject`, …).
    case conformance
    /// Carries a marker macro (`@Reducer`, `@Observable`).
    case macro
    /// Matched a project-declared naming/protocol convention (VIPER/MVP/MVC).
    case convention
}

/// The state surface a role's invariants range over.
public enum StateSurface: Sendable, Equatable {
    /// A named state type (a reducer's `State`).
    case namedType(String)
    /// The stored properties forming the observable state (viewmodel-style).
    case storedFields([RoleStateField])
}

/// One stored property of a role's state surface. Mirrors
/// `ViewModelStateField`.
public struct RoleStateField: Sendable, Equatable, Codable {
    public let name: String
    public let typeText: String
    /// `let` constants are state-but-immutable; `var`s are the mutable surface
    /// the action alphabet writes to.
    public let isMutable: Bool

    public init(name: String, typeText: String, isMutable: Bool) {
        self.name = name
        self.typeText = typeText
        self.isMutable = isMutable
    }
}

/// One action in a role's alphabet. Unifies `ActionCaseInfo` (a reducer's
/// `Action` enum case) and `ViewModelAction` (a state-mutating method).
public struct RoleAction: Sendable, Equatable, Codable {
    public let name: String
    /// The payload a generator must produce (empty = a nullary action).
    public let parameterTypes: [String]
    /// External label of the first parameter, needed to emit the call at
    /// verify time. `nil` for an unlabelled / nullary action or an enum case.
    public let firstParameterLabel: String?
    public let isAsync: Bool
    public let isThrows: Bool
    /// `true` when the entry point directly mutates state (a leaf mutator or a
    /// reducer case); `false` when it qualifies only transitively.
    public let mutatesStateDirectly: Bool

    public init(
        name: String,
        parameterTypes: [String],
        firstParameterLabel: String? = nil,
        isAsync: Bool = false,
        isThrows: Bool = false,
        mutatesStateDirectly: Bool = true
    ) {
        self.name = name
        self.parameterTypes = parameterTypes
        self.firstParameterLabel = firstParameterLabel
        self.isAsync = isAsync
        self.isThrows = isThrows
        self.mutatesStateDirectly = mutatesStateDirectly
    }

    /// Rendered `name(Type, Type)` / `name()` signature for output.
    public var signature: String {
        "\(name)(\(parameterTypes.joined(separator: ", ")))"
    }
}

/// How the verify harness gets a thing to drive.
public enum Construction: Sendable, Equatable {
    /// A free function the harness calls directly (a reducer).
    case freeFunction(name: String)
    /// An instance the harness must build, injecting a fake for each protocol
    /// collaborator (a viewmodel / presenter / interactor).
    case instance(initParameters: [RoleInitParameter], fakedCollaborators: [Collaborator])
}

/// One initializer parameter. Mirrors `ViewModelInitParameter`.
public struct RoleInitParameter: Sendable, Equatable, Codable {
    public let label: String?
    public let typeText: String

    public init(label: String?, typeText: String) {
        self.label = label
        self.typeText = typeText
    }
}

/// A collaborator a role calls out to, recognized as a protocol so it can be
/// faked.
public struct Collaborator: Sendable, Equatable {
    public let propertyName: String
    public let protocolType: String
    public let role: CollaboratorRole

    public init(propertyName: String, protocolType: String, role: CollaboratorRole) {
        self.propertyName = propertyName
        self.protocolType = protocolType
        self.role = role
    }
}

/// Whether a collaborator is a plain dependency (no-op fake) or an assertable
/// output sink (recording fake — the MVP/VIPER capability).
public enum CollaboratorRole: Sendable, Equatable {
    case dependency
    case output(assertable: Bool)
}

/// A paradigm-specific property family a `RolePolicy` declares it can generate,
/// layered on top of the shared interaction-invariant families.
public enum PropertyKind: String, Sendable, Equatable, Codable, CaseIterable {
    case idempotence
    case actionSequence = "action-sequence"
    case interactionInvariants = "interaction-invariants"
    case determinism
    case unknownActionIsNoOp = "unknown-action-is-no-op"
    case outputDeterminism = "output-determinism"
    case viewUpdateDeterminism = "view-update-determinism"
    case noUIKitImport = "no-uikit-import"
}
