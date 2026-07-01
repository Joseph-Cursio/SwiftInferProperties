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

    public init(
        name: String,
        kind: Kind,
        inheritedTypes: [String],
        hasUserGen: Bool,
        storedMembers: [StoredMember] = [],
        hasUserInit: Bool = false,
        initializers: [InitializerSignature] = []
    ) {
        self.name = name
        self.kind = kind
        self.inheritedTypes = inheritedTypes
        self.hasUserGen = hasUserGen
        self.storedMembers = storedMembers
        self.hasUserInit = hasUserInit
        self.initializers = initializers
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
    }
}

// MARK: - Conversion ↔ kit's TypeShape

extension IndexedTypeShape {

    /// Build a mirror from the kit's `TypeShape`. Element-wise map of
    /// kind + stored-member structs.
    public init(from kitShape: TypeShape) {
        self.init(
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
                PropertyLawCore.StoredMember(name: $0.name, typeName: $0.typeName)
            },
            hasUserInit: hasUserInit,
            initializers: initializers.map { sig in
                PropertyLawCore.InitializerSignature(
                    parameters: sig.parameters.map {
                        PropertyLawCore.InitializerParameter(label: $0.label, typeName: $0.typeName)
                    },
                    isFailable: sig.isFailable,
                    isThrowing: sig.isThrowing
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
