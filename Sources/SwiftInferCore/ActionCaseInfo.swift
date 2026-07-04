import Foundation

// Cycle 125 + item 2 slices 3/4 — the per-Action-case discovery record and its
// composition-payload resolution enrichments, lifted out of
// `ReducerCandidate.swift` so that file stays under SwiftLint's `file_length`
// cap (the slice-3/4 fields pushed it over). Pure relocation — no behavior
// change.

/// Item 2 slice 4 — one stored `var` field of an `@ObservableState` reducer
/// State (name + resolved type), captured at discovery time. Used by
/// `BindingActionResolver` to construct a `BindingAction.set(\.field, value)`
/// value for a `case binding(BindingAction<State>)` action. Only stored,
/// non-attributed `var`s of a resolvable type are recorded (the bindable
/// surface); `let` / `static` / computed / `@Presents` / `@Shared` fields are
/// excluded.
public struct StateFieldInfo: Sendable, Equatable, Codable {
    public let name: String
    public let typeName: String

    public init(name: String, typeName: String) {
        self.name = name
        self.typeName = typeName
    }
}

/// Cycle 125 (Phase B) — one Action enum case captured at discovery time:
/// its name plus its associated-value payload types in declaration order
/// (`[]` = payload-free). The emitter classifies constructibility from
/// `payloadTypes` (empty → free; single recognized raw type → raw-payload;
/// anything else → non-derivable, excluded from partial exploration).
public struct ActionCaseInfo: Sendable, Equatable, Codable {
    public let name: String
    public let payloadTypes: [String]

    /// Item 2 slice 3 — resolved facts for an `IdentifiedActionOf<Child>`
    /// payload, filled by `IdentifiedActionResolver` (CLI) when the child
    /// reducer resolves to a cheaply-defaultable id + a payload-free child
    /// action. `nil` for every other case (payload-free, raw, other
    /// composition wrappers) and pre-resolution. When present, the emitter
    /// constructs a canonical `.element(id:action:)` value from these facts
    /// — no child-candidate map threaded downstream. The `Optional` type is
    /// backward-compatible with the synthesized `Codable` (missing key →
    /// `nil`).
    public let resolvedElement: ResolvedIdentifiedElement?

    /// Item 2 slice 4 — resolved bindable fields for a
    /// `case binding(BindingAction<State>)` payload, filled by
    /// `BindingActionResolver` (CLI) from the reducer's own `@ObservableState`
    /// State fields whose type is cheaply defaultable. `nil` for every other
    /// case and pre-resolution; non-empty lists the fields the emitter explores
    /// via `.binding(.set(\.field, <value>))`. Backward-compatible optional.
    public let resolvedBinding: [ResolvedBindingField]?

    public init(
        name: String,
        payloadTypes: [String] = [],
        resolvedElement: ResolvedIdentifiedElement? = nil,
        resolvedBinding: [ResolvedBindingField]? = nil
    ) {
        self.name = name
        self.payloadTypes = payloadTypes
        self.resolvedElement = resolvedElement
        self.resolvedBinding = resolvedBinding
    }
}

/// Item 2 slice 4 — the resolved facts for constructing a canonical
/// `BindingAction.set(\.field, value)` value against a
/// `case binding(BindingAction<State>)` payload. Pure data (a field name + its
/// value type) — the emitter formats the keypath + the canned value literal.
public struct ResolvedBindingField: Sendable, Equatable, Codable {
    /// The `@ObservableState` stored `var` name — the `.set` keypath is `\.<fieldName>`.
    public let fieldName: String
    /// The field's value type — one of the cheaply-defaultable set
    /// (`Bool` / `Int` / `String` / `Double` / `UUID`); the emitter maps it
    /// to a canned literal.
    public let valueType: String

    public init(fieldName: String, valueType: String) {
        self.fieldName = fieldName
        self.valueType = valueType
    }
}

/// Item 2 slice 3 — the resolved facts for constructing a canonical
/// `IdentifiedAction.element(id:action:)` value against an
/// `IdentifiedActionOf<Child>` payload. Pure data (type names + a case
/// name) — the emitter formats the id literal + the `Gen.always(...)`
/// expression, keeping the "how to spell a canned UUID" knowledge in the
/// CLI emit layer rather than in Core.
public struct ResolvedIdentifiedElement: Sendable, Equatable, Codable {
    /// The child `State.ID` type — one of the cheaply-defaultable set
    /// (`UUID` / `Int` / `String`); the emitter maps it to a canned literal.
    public let idType: String
    /// The child's Action type, qualified (`"Row.Action"`).
    public let childActionType: String
    /// A payload-free case of the child's Action (`"increment"`), driven
    /// at depth 0 — no recursion into further composition wrappers.
    public let childActionCase: String

    public init(idType: String, childActionType: String, childActionCase: String) {
        self.idType = idType
        self.childActionType = childActionType
        self.childActionCase = childActionCase
    }
}
