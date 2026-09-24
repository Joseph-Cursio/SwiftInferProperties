import Foundation
import PropertyLawCore
import SwiftInferCore
import SwiftInferTemplates

/// The accept-path arms for `codable-round-trip`, `binary-idempotence` and
/// `dual-style-consistency`: laws `verify` composed and nothing wrote to disk
/// (`StubWriterCoverageTests`). Each writes its composer's law.
extension InteractiveTriage {

    /// `decode(encode(x)) == x` over the type that conforms. The template requires `Codable` and
    /// `Equatable` on one type, so the stub needs nothing it cannot assume.
    static func codableRoundTripStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)?
    ) -> String? {
        guard let evidence = suggestion.evidence.first,
              let typeName = evidence.qualifiedTypeName ?? suggestion.carrier else {
            return nil
        }
        return LiftedTestEmitter.codableRoundTrip(
            typeName: typeName,
            seed: SamplingSeed.derive(from: suggestion.identity),
            generator: chooseGenerator(for: suggestion, typeName: typeName, customGenerator: customGenerator)
        )
    }

    /// `op(x, x) == x`, at the two call shapes an arity-2 law takes: `a.union(a)` and `max(a, a)`.
    static func binaryIdempotenceStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)?
    ) -> String? {
        guard let evidence = suggestion.evidence.first,
              let callee = CalleeReference(evidence: evidence),
              callee.accepts(applicationArity: 2),
              let typeName = carrierType(for: evidence) else {
            return nil
        }
        return LiftedTestEmitter.binaryIdempotence(
            callee: callee,
            typeName: typeName,
            seed: SamplingSeed.derive(from: suggestion.identity),
            generator: chooseGenerator(for: suggestion, typeName: typeName, customGenerator: customGenerator),
            equalityKind: equalityKind(forTypeText: typeName)
        )
    }

    /// The non-mutating half against the mutating half on a copy. The pair's two evidence rows
    /// say which is which (`isMutatingMethod`); both must be instance methods on one type, taking
    /// no operand (`sorted`/`sort`) or one of the receiver's type (`union`/`formUnion`).
    static func dualStyleConsistencyStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)?
    ) -> String? {
        guard suggestion.evidence.count == 2,
              let mutatingRow = suggestion.evidence.first(where: \.isMutatingMethod),
              let pureRow = suggestion.evidence.first(where: { !$0.isMutatingMethod }),
              let mutating = CalleeReference.mutatingStatement(evidence: mutatingRow),
              let nonMutating = CalleeReference(evidence: pureRow),
              mutating.isInstanceMethod, nonMutating.isInstanceMethod,
              mutating.argumentLabels.count == nonMutating.argumentLabels.count,
              mutating.argumentLabels.count <= 1,
              let typeName = pureRow.qualifiedTypeName ?? suggestion.carrier else {
            return nil
        }
        let takesOperand = mutating.argumentLabels.count == 1
        if takesOperand, parameterTypes(from: pureRow.signature).first != typeName { return nil }
        return LiftedTestEmitter.dualStyleConsistency(
            .init(nonMutating: nonMutating, mutating: mutating, takesOperand: takesOperand),
            typeName: typeName,
            seed: SamplingSeed.derive(from: suggestion.identity),
            generator: chooseGenerator(for: suggestion, typeName: typeName, customGenerator: customGenerator)
        )
    }
}
