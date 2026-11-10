import Foundation
import SwiftInferCore

extension FunctorIdentityPairing {

    /// Type name ascending, mapper name ascending as the tiebreak — one type
    /// commonly offers several map-shaped methods.
    static func byTypeNameThenMapperName(_ lhs: FunctorShape, _ rhs: FunctorShape) -> Bool {
        (lhs.typeName, lhs.mapper.name) < (rhs.typeName, rhs.mapper.name)
    }
}
