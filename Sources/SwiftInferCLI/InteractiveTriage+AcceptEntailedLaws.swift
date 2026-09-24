import Foundation
import PropertyLawCore
import SwiftInferCore
import SwiftInferTemplates

/// The accept-path arms for three laws `verify` already composed and nothing wrote to disk:
/// `involution`, `role-postcondition` and `equivalence-relation`.
///
/// Each writes exactly the law its `verify` composer checks (`StrategistDispatchEmitter+AlgebraicLaws`
/// for the first two), and declines exactly where that composer does, so a stub and a verify run
/// never disagree about what the code owes.
extension InteractiveTriage {

    /// A stub for one of the three, or `nil` when the suggestion is not one or cannot be written.
    static func entailedLawStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)? = nil
    ) -> String? {
        switch suggestion.templateName {
        case "involution":
            return involutionStub(for: suggestion, customGenerator: customGenerator)

        case "role-postcondition":
            return rolePostconditionStub(for: suggestion, customGenerator: customGenerator)

        case "equivalence-relation":
            return equivalenceRelationStub(for: suggestion, customGenerator: customGenerator)

        case "codable-round-trip":
            return codableRoundTripStub(for: suggestion, customGenerator: customGenerator)

        case "binary-idempotence":
            return binaryIdempotenceStub(for: suggestion, customGenerator: customGenerator)

        case "dual-style-consistency":
            return dualStyleConsistencyStub(for: suggestion, customGenerator: customGenerator)

        default:
            return nil
        }
    }

    /// `f(f(x)) == x`, over the carrier idempotence would draw — the same call shape, so the same
    /// arity rule and the same equality choice.
    private static func involutionStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)?
    ) -> String? {
        guard let evidence = suggestion.evidence.first,
              let callee = CalleeReference(evidence: evidence),
              let arity = StubApplicationArity.forTemplate(suggestion.templateName),
              callee.accepts(applicationArity: arity),
              let typeName = carrierType(for: evidence) else {
            return nil
        }
        return LiftedTestEmitter.involution(
            callee: callee,
            typeName: typeName,
            seed: SamplingSeed.derive(from: suggestion.identity),
            generator: chooseGenerator(for: suggestion, typeName: typeName, customGenerator: customGenerator),
            equalityKind: equalityKind(forTypeText: typeName)
        )
    }

    /// The role's guarantee of the result, for the roles whose guarantee is a check swift-infer can
    /// spell without proving anything about the types — `RolePostcondition.violationExpression`,
    /// today `lowercased` and `uppercased`. The other roles stay advisory, as they do in `verify`:
    /// `sorted` needs `Comparable`, `clamped` the caller's bounds, and emitting a check the tool
    /// cannot justify is the 89%-fails-to-compile failure `criterion-a-unmet-subject.md` measured.
    private static func rolePostconditionStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)?
    ) -> String? {
        guard let evidence = suggestion.evidence.first,
              let callee = CalleeReference(evidence: evidence),
              callee.applicationArity == 1,
              let role = RolePostcondition(rawValue: callee.bareName),
              let typeName = callee.isInstanceMethod
                ? evidence.qualifiedTypeName
                : parameterTypes(from: evidence.signature).first else {
            return nil
        }
        return LiftedTestEmitter.rolePostcondition(
            callee: callee,
            role: role,
            typeName: typeName,
            seed: SamplingSeed.derive(from: suggestion.identity),
            generator: chooseGenerator(for: suggestion, typeName: typeName, customGenerator: customGenerator)
        )
    }

    /// Reflexivity, symmetry and transitivity, in the three shapes the template admits:
    /// `a.isEqual(to: b)` (the receiver is an operand), `areEqual(a, b)` (static or free), and
    /// `relation.equals(a, b)` (a receiver holding the relation, drawn once per trial).
    ///
    /// An isolated relation is declined, as the comparator writer declines one: the coverage loop
    /// and the kit's closure call it synchronously from a nonisolated context.
    private static func equivalenceRelationStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)?
    ) -> String? {
        guard let evidence = suggestion.evidence.first,
              let callee = CalleeReference(evidence: evidence),
              callee.isolation == nil else {
            return nil
        }
        let operands = parameterTypes(from: evidence.signature)
        let generate = { (type: String) in
            chooseGenerator(for: suggestion, typeName: type, customGenerator: customGenerator)
        }
        // Which receiver, if any, holds the relation: none when the receiver IS an operand
        // (`a.isEqual(to: b)`) or there is no receiver (`areEqual(a, b)`), the declaring type when a
        // strategy object holds it (`relation.equals(a, b)`).
        let receiver: String?
        switch (callee.isInstanceMethod, operands.count) {
        case (true, 1):
            receiver = nil

        case (true, 2) where operands[0] == operands[1]:
            guard let holder = evidence.qualifiedTypeName else { return nil }
            receiver = generate(holder)

        case (false, 2) where operands[0] == operands[1]:
            receiver = nil

        default:
            return nil
        }
        let call = LiftedTestEmitter.EquivalenceCall(
            callee: callee,
            operandGenerator: LiftedTestEmitter.tieDense(generate(operands[0])),
            receiverGenerator: receiver
        )
        return LiftedTestEmitter.equivalenceRelation(call, seed: SamplingSeed.derive(from: suggestion.identity))
    }
}
