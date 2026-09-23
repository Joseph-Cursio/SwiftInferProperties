import SwiftSyntax

extension FunctionScannerVisitor {

    /// A computed property's body signals: only the replacement-chain veto input, and only for a
    /// property of its own receiver's type — `var xmlEscaped: String` on `String` — which is the
    /// self-form `idempotence` proposes `x.p.p == x.p` for.
    static func computedPropertySignals(
        _ block: AccessorBlockSyntax,
        type: TypeSyntax,
        in containingTypeName: String
    ) -> BodySignals {
        guard type.trimmedDescription == containingTypeName,
              case let .getter(statements) = block.accessors,
              let shape = IdempotenceReturnShapeClassifier.replacementChainShape(getter: statements) else {
            return .empty
        }
        return BodySignals(
            hasNonDeterministicCall: false,
            hasSelfComposition: false,
            nonDeterministicAPIsDetected: [],
            reducerOpsReferenced: [],
            reducerOpsWithIdentitySeed: [],
            idempotenceReturnShape: shape
        )
    }
}
