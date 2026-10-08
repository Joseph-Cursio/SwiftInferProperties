import SwiftInferCore

extension LiftedTestEmitter {

    /// `value.predicate == (value.measure > 0)` — or `== 0` for an emptiness predicate — over one
    /// value drawn from `carrier.generator`, of type `carrier.typeName`. See
    /// `EmptinessAgreementTemplate`.
    ///
    /// Both members are read off the same drawn value inside the property closure, hopped onto the
    /// subject's actor when it has one, so a MainActor-default carrier's members are reachable.
    public static func emptinessAgreement(
        predicate: CalleeReference,
        measure: CalleeReference,
        holdsWhenPositive: Bool,
        carrier: (typeName: String, generator: String),
        seed: SamplingSeed.Value
    ) -> String {
        let comparison = holdsWhenPositive ? "> 0" : "== 0"
        let body = "\(predicate.call(["value"])) == (\(measure.call(["value"])) \(comparison))"
        return makeTestStub(
            testFunctionName: "\(predicate.identifierName)_agreesWith_\(measure.identifierName)",
            seed: seed,
            generator: carrier.generator,
            propertyExpression: predicate.isolated(body),
            failureLabel: "\(predicate.displaySignature) disagrees with "
                + "\(measure.displaySignature) \(comparison)",
            carrierType: carrier.typeName
        )
    }
}
