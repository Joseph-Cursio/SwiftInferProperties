import Foundation
import PropertyLawCore

/// V1.47.A — JSON-encodable mirror of `PropertyLawCore.TypeShape`,
/// persisted alongside `SemanticIndexEntry` so the verify pipeline
/// can call `DerivationStrategist.strategy(for:)` at verify time
/// without re-parsing the user's source.
///
/// **Why a mirror, not a `Codable` extension on the kit's type.**
/// Swift's `Codable` synthesis doesn't cross module boundaries, so
/// adding `Codable` to the kit's `TypeShape` via extension would
/// require hand-written `init(from:)` + `encode(to:)` plus
/// hand-written conformances on `TypeShape.Kind` and `StoredMember`
/// plus `@retroactive` suppressions on each — strictly more code
/// than this mirror. As a bonus, this mirror also insulates the
/// persisted index format from kit-version evolution (a future kit
/// `TypeShape` field change would update the converter only, not
/// the JSON schema seen by older `swift-infer` releases).
///
/// **Field-for-field parity.** Every public field of the kit's
/// `TypeShape` has a same-named property here. The converter
/// (`init(from kitShape:)` and `toKitShape()`) is a deterministic
/// element-wise map.
public struct IndexedTypeShape: Codable, Sendable, Equatable {

    // Nominal type kinds only. `TypeDecl.Kind` mirrors the same upstream shape and adds
    // `.extension`; an extension is not a type, so it has no place in an indexed *type* shape.
    // swiftprojectlint:disable:next parallel-list-drift
    /// Kind discriminator mirroring `TypeShape.Kind`. `String`-backed so
    /// the JSON encoding stays human-readable.
    public enum Kind: String, Codable, Sendable, Equatable {
        case `struct`
        case `class`
        case `enum`
        case `actor`
    }

    /// Stored property mirror — name + source-declared type spelling.
    public struct StoredMember: Codable, Sendable, Equatable {
        public let name: String
        public let typeName: String

        public init(name: String, typeName: String) {
            self.name = name
            self.typeName = typeName
        }
    }

    /// Mirror of `PropertyLawCore.InitializerParameter` — call-site label
    /// (nil for an unlabeled `_` param) + source-declared type spelling.
    public struct InitializerParameter: Codable, Sendable, Equatable {
        public let label: String?
        public let typeName: String

        public init(label: String?, typeName: String) {
            self.label = label
            self.typeName = typeName
        }
    }

    /// Mirror of `PropertyLawCore.InitializerSignature` — a user-declared
    /// initializer consumed by the Tier 6 `initializerBased` strategy at
    /// verify time. Persisted so `toKitShape()` can round-trip it; without
    /// this the strategist saw `hasUserInit == true` with no captured inits
    /// and fell through to `.todo`.
    public struct InitializerSignature: Codable, Sendable, Equatable {
        public let parameters: [InitializerParameter]
        public let isFailable: Bool
        public let isThrowing: Bool

        public init(parameters: [InitializerParameter], isFailable: Bool = false, isThrowing: Bool = false) {
            self.parameters = parameters
            self.isFailable = isFailable
            self.isThrowing = isThrowing
        }
    }

    /// Mirror of `PropertyLawCore.EnumCase` — a case name plus its associated
    /// values, which reuse `InitializerParameter` (label + type spelling) on
    /// both sides.
    ///
    /// **Why this field was missing, and what it cost.** `IndexedTypeShape`
    /// claims field-for-field parity with the kit's `TypeShape`, and every other
    /// field has held that. `enumCases` did not: it exists on `TypeDecl`, is
    /// carried by `TypeShape`, and was dropped on the way into
    /// `.swiftinfer/index.json`. So at verify time the strategist saw an enum
    /// with no cases, `enumCasesStrategy` returned `nil`, and derivation fell
    /// through to `.rawRepresentable` — which emits a *filter* over random raw
    /// values (`.compactMap { T(rawValue: $0) }`) that for a `String`-raw enum
    /// essentially never produces a value and does not terminate.
    ///
    /// That is how a missing JSON field became a hung verifier: two binaries
    /// spinning at 99.9% CPU for the better part of an hour, with the survey
    /// reporting nothing at all. SwiftPropertyLaws v3.19.0 fixed the precedence
    /// kit-side, and the fix could not fire here because there was nothing to
    /// enumerate. See `docs/measurements/roadtest-self-dogfood.md` §11.3 — the third time a
    /// correct kit-side fix was disabled by a lossy projection on this side.
    public struct EnumCase: Codable, Sendable, Equatable {
        public let name: String
        public let associatedValues: [InitializerParameter]

        public init(name: String, associatedValues: [InitializerParameter] = []) {
            self.name = name
            self.associatedValues = associatedValues
        }
    }

    public let name: String
    public let kind: Kind
    public let inheritedTypes: [String]
    public let hasUserGen: Bool
    public let storedMembers: [StoredMember]
    public let hasUserInit: Bool
    /// User-declared initializers from the type's primary body (WS-2). Mirrors
    /// `TypeShape.initializers`; enables the Tier 6 `initializerBased` strategy
    /// at verify time for structs whose user `init` suppresses the memberwise one.
    public let initializers: [InitializerSignature]
    /// Enum cases from the type's primary body. Mirrors `TypeShape.enumCases`;
    /// enables the Tier 4 `enumCases` strategy at verify time. See `EnumCase`.
    public let enumCases: [EnumCase]

    public init(
        name: String,
        kind: Kind,
        inheritedTypes: [String],
        hasUserGen: Bool,
        storedMembers: [StoredMember] = [],
        hasUserInit: Bool = false,
        initializers: [InitializerSignature] = [],
        enumCases: [EnumCase] = []
    ) {
        // Delegates to the exhaustive initializer, which is the designated
        // one — see `EveryColumn`. That direction is load-bearing: because the
        // exhaustive init is what assigns the stored properties, adding a
        // property forces a parameter onto it, which in turn breaks every
        // converter that calls it.
        self.init(
            everyColumn: .required,
            name: name,
            kind: kind,
            inheritedTypes: inheritedTypes,
            hasUserGen: hasUserGen,
            storedMembers: storedMembers,
            hasUserInit: hasUserInit,
            initializers: initializers,
            enumCases: enumCases
        )
    }

    /// Exhaustive initializer — **every parameter is required, deliberately.**
    ///
    /// `init(from kitShape:)` uses this, so a column added to the mirror and
    /// forgotten in the converter is a compile error. That is the guard the
    /// `enumCases` omission needed and did not have: the field was absent for
    /// the type's whole life, nothing failed, and it surfaced three layers
    /// downstream as a hung verifier. See `EveryColumn`.
    public init(
        everyColumn _: EveryColumn,
        name: String,
        kind: Kind,
        inheritedTypes: [String],
        hasUserGen: Bool,
        storedMembers: [StoredMember],
        hasUserInit: Bool,
        initializers: [InitializerSignature],
        enumCases: [EnumCase]
    ) {
        self.name = name
        self.kind = kind
        self.inheritedTypes = inheritedTypes
        self.hasUserGen = hasUserGen
        self.storedMembers = storedMembers
        self.hasUserInit = hasUserInit
        self.initializers = initializers
        self.enumCases = enumCases
    }

    // MARK: - Codable

    /// Custom decoder uses `decodeIfPresent` for `storedMembers` and
    /// `hasUserInit` — they default to empty / false when missing
    /// from older persisted entries, matching the kit-side
    /// `TypeShape.init` defaults.
    private enum CodingKeys: String, CodingKey {
        case name
        case kind
        case inheritedTypes
        case hasUserGen
        case storedMembers
        case hasUserInit
        case initializers
        case enumCases
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.kind = try container.decode(Kind.self, forKey: .kind)
        self.inheritedTypes = try container.decode([String].self, forKey: .inheritedTypes)
        self.hasUserGen = try container.decode(Bool.self, forKey: .hasUserGen)
        self.storedMembers = try container
            .decodeIfPresent([StoredMember].self, forKey: .storedMembers) ?? []
        self.hasUserInit = try container
            .decodeIfPresent(Bool.self, forKey: .hasUserInit) ?? false
        self.initializers = try container
            .decodeIfPresent([InitializerSignature].self, forKey: .initializers) ?? []
        // Additive: an index written before this field existed decodes to `[]`,
        // which is exactly the pre-change behaviour. No schema bump needed.
        self.enumCases = try container
            .decodeIfPresent([EnumCase].self, forKey: .enumCases) ?? []
    }
}

// MARK: - Conversion ↔ kit's TypeShape

extension IndexedTypeShape {

    /// Build a mirror from the kit's `TypeShape`. Element-wise map of
    /// kind + stored-member structs.
    public init(from kitShape: TypeShape) {
        self.init(
            everyColumn: .required,
            name: kitShape.name,
            kind: Kind(kitKind: kitShape.kind),
            inheritedTypes: kitShape.inheritedTypes,
            hasUserGen: kitShape.hasUserGen,
            storedMembers: kitShape.storedMembers.map {
                StoredMember(name: $0.name, typeName: $0.typeName)
            },
            hasUserInit: kitShape.hasUserInit,
            initializers: kitShape.initializers.map { sig in
                InitializerSignature(
                    parameters: sig.parameters.map {
                        InitializerParameter(label: $0.label, typeName: $0.typeName)
                    },
                    isFailable: sig.isFailable,
                    isThrowing: sig.isThrowing
                )
            },
            enumCases: kitShape.enumCases.map { enumCase in
                EnumCase(
                    name: enumCase.name,
                    associatedValues: enumCase.associatedValues.map {
                        InitializerParameter(label: $0.label, typeName: $0.typeName)
                    }
                )
            }
        )
    }

    /// Project back to the kit's `TypeShape` for
    /// `DerivationStrategist.strategy(for:)` consumption.
    public func toKitShape() -> TypeShape {
        TypeShape(
            name: name,
            kind: kind.kitKind,
            inheritedTypes: inheritedTypes,
            hasUserGen: hasUserGen,
            storedMembers: storedMembers.map {
                PropertyLawCore.StoredMember(
                    name: $0.name,
                    typeName: StdlibTypeSpelling.canonical($0.typeName)
                )
            },
            hasUserInit: hasUserInit,
            initializers: initializers.map { sig in
                PropertyLawCore.InitializerSignature(
                    parameters: sig.parameters.map {
                        PropertyLawCore.InitializerParameter(
                            label: $0.label,
                            typeName: StdlibTypeSpelling.canonical($0.typeName)
                        )
                    },
                    isFailable: sig.isFailable,
                    isThrowing: sig.isThrowing
                )
            },
            enumCases: enumCases.map { enumCase in
                PropertyLawCore.EnumCase(
                    name: enumCase.name,
                    associatedValues: enumCase.associatedValues.map {
                        PropertyLawCore.InitializerParameter(
                            label: $0.label,
                            typeName: StdlibTypeSpelling.canonical($0.typeName)
                        )
                    }
                )
            }
        )
    }
}

extension IndexedTypeShape.Kind {

    init(kitKind: TypeShape.Kind) {
        switch kitKind {
        case .struct: self = .struct
        case .class: self = .class
        case .enum: self = .enum
        case .actor: self = .actor
        }
    }

    var kitKind: TypeShape.Kind {
        switch self {
        case .struct: return .struct
        case .class: return .class
        case .enum: return .enum
        case .actor: return .actor
        }
    }
}
