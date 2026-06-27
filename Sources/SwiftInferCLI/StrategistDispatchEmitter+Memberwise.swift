import Foundation
import PropertyLawCore

/// V1.89 lint pass — memberwise-recipe helpers extracted from
/// `StrategistDispatchEmitter.swift` so the main enum body stays
/// under SwiftLint's 250-line cap. These functions render the
/// `.memberwiseArbitrary` strategy into a `GeneratorRecipe`; they
/// were `private static` and are now internal-static so the sibling
/// extension file can call them.
extension StrategistDispatchEmitter {

    /// 1-member memberwise emit. Uses `.map` directly (no zip needed).
    static func memberwiseRecipeSingle(
        member: MemberSpec,
        carrier: String
    ) -> GeneratorRecipe {
        let expression = "\(member.generatorExpression).map { "
            + "\(carrier)(\(member.name): $0) }"
        return GeneratorRecipe(
            expression: expression,
            carrierTypeName: carrier,
            imports: ["Foundation", "PropertyBased"]
        )
    }

    /// 2–10 member memberwise emit. Uses `zip(...)` from
    /// swift-property-based + a tuple-destructuring `.map`.
    static func memberwiseRecipeMulti(
        members: [MemberSpec],
        carrier: String
    ) -> GeneratorRecipe {
        let generators = members
            .map(\.generatorExpression)
            .joined(separator: ", ")
        let bindings = (0 ..< members.count)
            .map { "m\($0)" }
            .joined(separator: ", ")
        let constructorArgs = members
            .enumerated()
            .map { offset, spec in "\(spec.name): m\(offset)" }
            .joined(separator: ", ")
        let expression = "zip(\(generators)).map { (\(bindings)) in "
            + "\(carrier)(\(constructorArgs)) }"
        return GeneratorRecipe(
            expression: expression,
            carrierTypeName: carrier,
            imports: ["Foundation", "PropertyBased"]
        )
    }

    /// Memberwise-recipe entry point. Dispatches single-member vs
    /// multi-member emit; guards against the empty-member and over-
    /// arity cases the strategist's `memberwiseStrategy(for:)` should
    /// have already filtered to `.todo` (defensive — v1.49.B).
    static func memberwiseRecipe(
        members: [MemberSpec],
        carrier: String
    ) throws -> GeneratorRecipe {
        guard !members.isEmpty else {
            throw VerifyError.unsupportedCarrier(
                carrier: carrier,
                expected: [
                    ".memberwiseArbitrary with empty members "
                        + "(strategist's memberwiseStrategy should never return this; "
                        + "v1.49.B defensive guard)"
                ]
            )
        }
        guard members.count <= DerivationStrategist.memberwiseArityLimit else {
            throw VerifyError.unsupportedCarrier(
                carrier: carrier,
                expected: [
                    ".memberwiseArbitrary arity \(members.count) > "
                        + "memberwiseArityLimit \(DerivationStrategist.memberwiseArityLimit) "
                        + "(strategist should have filtered to .todo; "
                        + "v1.49.B defensive guard)"
                ]
            )
        }
        if members.count == 1 {
            return memberwiseRecipeSingle(member: members[0], carrier: carrier)
        }
        return memberwiseRecipeMulti(members: members, carrier: carrier)
    }
}
