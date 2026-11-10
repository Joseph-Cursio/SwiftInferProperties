import Foundation
import PropertyLawCore

// MARK: - Conversion ↔ kit's TypeShape

public extension IndexedTypeShape {

    /// Build a mirror from the kit's `TypeShape`. Element-wise map of
    /// kind + stored-member structs.
    init(from kitShape: TypeShape) {
        self.init(
            everyColumn: .required,
            name: kitShape.name,
            kind: Kind(kitKind: kitShape.kind),
            inheritedTypes: kitShape.inheritedTypes,
            hasUserGen: kitShape.hasUserGen,
            storedMembers: kitShape.storedMembers.map {
                StoredMember(name: $0.name, typeName: $0.typeName, accessLevel: $0.accessLevel.rawValue)
            },
            hasUserInit: kitShape.hasUserInit,
            initializers: kitShape.initializers.map { sig in
                InitializerSignature(
                    parameters: sig.parameters.map {
                        InitializerParameter(label: $0.label, typeName: $0.typeName)
                    },
                    isFailable: sig.isFailable,
                    isThrowing: sig.isThrowing,
                    assertsPrecondition: sig.assertsPrecondition,
                    delegatesToSelf: sig.delegatesToSelf
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
    func toKitShape() -> TypeShape {
        TypeShape(
            name: name,
            kind: kind.kitKind,
            inheritedTypes: inheritedTypes,
            hasUserGen: hasUserGen,
            storedMembers: storedMembers.map {
                PropertyLawCore.StoredMember(
                    name: $0.name,
                    typeName: $0.typeName,
                    accessLevel: $0.accessLevel.flatMap(AccessLevel.init(rawValue:)) ?? .implicit
                )
            },
            hasUserInit: hasUserInit,
            initializers: initializers.map { sig in
                PropertyLawCore.InitializerSignature(
                    parameters: sig.parameters.map {
                        PropertyLawCore.InitializerParameter(label: $0.label, typeName: $0.typeName)
                    },
                    isFailable: sig.isFailable,
                    isThrowing: sig.isThrowing,
                    assertsPrecondition: sig.assertsPrecondition,
                    delegatesToSelf: sig.delegatesToSelf
                )
            },
            enumCases: enumCases.map { enumCase in
                PropertyLawCore.EnumCase(
                    name: enumCase.name,
                    associatedValues: enumCase.associatedValues.map {
                        PropertyLawCore.InitializerParameter(label: $0.label, typeName: $0.typeName)
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
