import Foundation
import SwiftInferCore

/// **Functor identity** — mapping the identity function changes nothing.
///
///     c.map { $0 } == c
///
/// From the `known-properties` `[reference]` rows. See `FunctorIdentityPairing` for the
/// return-type discriminator, which is doing double duty as both the correctness gate
/// and the kit-overlap gate.
public enum FunctorIdentityTemplate {

    public static func suggest(
        for shape: FunctorIdentityPairing.FunctorShape
    ) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: shape)
    }

    public static func makeConstraint() -> Constraint<FunctorIdentityPairing.FunctorShape> {
        Constraint<FunctorIdentityPairing.FunctorShape>(
            templateName: "functor-identity",
            appliesTo: { _ in true },
            signals: Self.signals(for:),
            evidence: { [$0.mapper.inferenceEvidence] },
            identity: Self.makeIdentity(for:),
            carrier: { $0.typeName },
            carrierType: { $0.typeName },
            caveats: Self.makeCaveats(for:),
            additionalWhySuggested: Self.makeWhySuggested(for:),
            generators: Self.makeGenerators(for:)
        )
    }

    /// 70 (Likely). One name plus one shape, with no second declaration corroborating it
    /// — deliberately below `ended-access-round-trip`'s 75, where two independently named
    /// members have to agree about an end.
    static func signals(for shape: FunctorIdentityPairing.FunctorShape) -> [Signal] {
        [
            Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Curated map-family name: '\(shape.mapper.name)'. Mapping is "
                    + "definitionally structure-preserving — a `\(shape.mapper.name)` that "
                    + "reorders, drops or merges is not one"
            ),
            Signal(
                kind: .typeSymmetrySignature,
                weight: 30,
                detail: "Carrier-preserving: `\(shape.mapper.name)` returns "
                    + "`\(shape.returnTypeText)`, which is \(shape.typeName) again. "
                    + "A map returning `[T]` — `Set.map`, `Dictionary.map` — changes the "
                    + "container and cannot carry this law"
            )
        ]
    }

    static func makeWhySuggested(
        for _: FunctorIdentityPairing.FunctorShape
    ) -> [String] {
        [
            "From the `known-properties` [reference] rows — laws the catalog already "
                + "verifies on `Optional` and `Dictionary` but that no template could "
                + "transfer to a carrier of your own"
        ]
    }

    static func makeCaveats(for shape: FunctorIdentityPairing.FunctorShape) -> [String] {
        [
            "THE LAW IS `\(shape.lawText)` — mapping the identity function is a no-op. "
                + "It is refuted by a `\(shape.mapper.name)` that does anything beyond "
                + "transforming in place: re-sorting, dropping elements the transform "
                + "left unchanged, merging collided keys, or normalising on the way out. "
                + "Confirm the method is meant to be structure-preserving before treating "
                + "a failure as a defect.",
            "IDENTITY IS THE WEAKER HALF. The stronger law is COMPOSITION — "
                + "`c.\(shape.mapper.name)(f).\(shape.mapper.name)(g) == "
                + "c.\(shape.mapper.name) { g(f($0)) }` — which catches a map that is "
                + "correct on the identity function and wrong on everything else. It is "
                + "not proposed here because it needs two generated functions rather than "
                + "a value, and that is a generator capability rather than a template "
                + "shape. If you write one law by hand, write that one.",
            "IF THE ELEMENT TYPE CHANGES, EQUALITY MAY NOT SURVIVE. This law is stated at "
                + "the identity function precisely so the result type matches the input "
                + "type and `==` is available. A composition law over two type-changing "
                + "functions needs the final type to be Equatable, which is not implied by "
                + "the carrier being so.",
            "The kit's `checkTransformationPropertyLaws` runs `Transformation.mapFusion` "
                + "over ANY `Sequence`, so a bare `map` on a sequence carrier is its job, "
                + "not this template's — that case is declined at pairing. `mapValues` is "
                + "not `Sequence.map`, which is why a dictionary carrier is still reached."
        ]
    }

    static func makeGenerators(
        for shape: FunctorIdentityPairing.FunctorShape
    ) -> [GeneratorRecipe] {
        [
            GeneratorRecipe(
                subject: "c",
                typeName: shape.typeName,
                expression: "Gen<\(shape.typeName)>.includingEmptyAndDegenerate()",
                rationale: "INCLUDE THE EMPTY AND SINGLE-ELEMENT CASES, and any state the "
                    + "carrier treats specially — a `Result`'s failure branch, an "
                    + "`Optional`'s `nil`, a future that has already completed. The "
                    + "identity law is trivially true on a typical populated value; where "
                    + "it breaks is a short-circuit path that forgets to carry the payload "
                    + "through, and those paths are exactly the degenerate states."
            )
        ]
    }

    static func makeIdentity(for shape: FunctorIdentityPairing.FunctorShape) -> SuggestionIdentity {
        SuggestionIdentity(
            canonicalInput: "functor-identity|\(shape.typeName)|\(shape.mapper.name)"
        )
    }
}
