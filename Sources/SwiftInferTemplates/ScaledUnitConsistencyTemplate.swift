import Foundation
import SwiftInferCore

/// **Scaled-unit consistency** — two constructors from one unit family must agree.
///
///     Duration.seconds(n) == Duration.milliseconds(n * 1_000)
///
/// Rows 8–11 of the swift.org `loops` answer key. See `ScaledUnitPairing` for why the
/// law relates two constructors rather than reproducing the witness's decomposition
/// form, and for why byte units are excluded.
public enum ScaledUnitConsistencyTemplate {

    public static func suggest(
        for shape: ScaledUnitPairing.ScaledUnitShape
    ) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: shape)
    }

    public static func makeConstraint() -> Constraint<ScaledUnitPairing.ScaledUnitShape> {
        Constraint<ScaledUnitPairing.ScaledUnitShape>(
            templateName: "scaled-unit-consistency",
            appliesTo: { _ in true },
            signals: Self.signals(for:),
            evidence: { [$0.larger.inferenceEvidence, $0.smaller.inferenceEvidence] },
            identity: Self.makeIdentity(for:),
            carrier: { $0.typeName },
            carrierType: { $0.typeName },
            caveats: Self.makeCaveats(for:),
            additionalWhySuggested: Self.makeWhySuggested(for:),
            generators: Self.makeGenerators(for:)
        )
    }

    /// 70 (Likely), or 80 (Strong) once the carrier exposes three or more units.
    ///
    /// Two curated unit names on one carrier could be a coincidence — a type with
    /// `seconds` and `minutes` might be a schedule rather than a duration. Three or more
    /// in one SI ladder is a unit family announcing itself.
    static func signals(for shape: ScaledUnitPairing.ScaledUnitShape) -> [Signal] {
        var signals = [
            Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Curated time-unit names: '\(shape.larger.name)' and "
                    + "'\(shape.smaller.name)'. SI time prefixes are definitional — one "
                    + "\(shape.larger.name.dropLast()) is \(shape.ratio) "
                    + "\(shape.smaller.name), and no type may reinterpret that"
            ),
            Signal(
                kind: .typeSymmetrySignature,
                weight: 30,
                detail: "Both are static constructors returning \(shape.typeName), so they "
                    + "are two spellings of one value and must agree"
            )
        ]
        if shape.familySize >= 3 {
            signals.append(Signal(
                kind: .algebraicStructureCluster,
                weight: 10,
                detail: "\(shape.familySize) curated units co-occur on \(shape.typeName) — a "
                    + "unit family by construction, not a coincidence of two names"
            ))
        }
        return signals
    }

    static func makeWhySuggested(for shape: ScaledUnitPairing.ScaledUnitShape) -> [String] {
        [
            "Stated between constructors rather than against a decomposition: the ratio is "
                + "all this needs, so it says nothing about how \(shape.typeName) stores the "
                + "value and reaches the same defect — a wrong conversion constant"
        ]
    }

    static func makeCaveats(for shape: ScaledUnitPairing.ScaledUnitShape) -> [String] {
        [
            "THE LAW IS `\(shape.lawText)` — the two constructors are two spellings of one "
                + "value. Confirm `\(shape.typeName)` means the SI unit by these names; a "
                + "type modelling calendar time rather than elapsed time may define a unit "
                + "differently, and the law is then false by intent rather than by defect.",
            "OVERFLOW BOUNDS THE DOMAIN, AND IT IS NOT A DEFECT. The right-hand side "
                + "multiplies by \(shape.ratio), so a generator drawing near the parameter "
                + "type's maximum will overflow or trap on that side while the left-hand "
                + "side is fine. That is the law leaving its domain, not the code being "
                + "wrong. Bound the generator so `n * \(shape.ratio)` is representable — and "
                + "if the carrier is expected to saturate rather than trap, THAT is a "
                + "separate property worth stating on its own.",
            "ONLY ADJACENT UNITS ARE PROPOSED, deliberately. Every pair in a six-unit family "
                + "would be fifteen rows saying much the same thing, and the distant ratios "
                + "are large enough (hours to nanoseconds is 3.6e12) that the law would "
                + "report a domain limit on almost every input rather than a defect.",
            "BYTE UNITS ARE EXCLUDED and this is why: `kilobytes` means 1000 in some types "
                + "and 1024 in others, and both are defensible. Time prefixes are "
                + "definitional; byte prefixes are a convention the type chooses. If you are "
                + "reading this on a byte-sized carrier, the template has misfired — please "
                + "report it."
        ]
    }

    static func makeGenerators(
        for shape: ScaledUnitPairing.ScaledUnitShape
    ) -> [GeneratorRecipe] {
        let parameterType = shape.larger.parameters.first?.typeText ?? "Int64"
        return [
            GeneratorRecipe(
                subject: "n",
                typeName: parameterType,
                expression: "Gen<\(parameterType)>.bounded(soThat: n * \(shape.ratio) fits)",
                rationale: "BOUND IT SO THE PRODUCT IS REPRESENTABLE. The law multiplies by "
                    + "\(shape.ratio) on one side only, so an unbounded draw fails on "
                    + "overflow rather than on a conversion bug and every counterexample "
                    + "will be a false one. Do keep the boundary of the *bounded* range — "
                    + "the largest `n` whose product still fits is exactly where an "
                    + "off-by-one in the conversion shows up."
            )
        ]
    }

    static func makeIdentity(for shape: ScaledUnitPairing.ScaledUnitShape) -> SuggestionIdentity {
        SuggestionIdentity(
            canonicalInput: "scaled-unit-consistency|\(shape.typeName)|"
                + "\(shape.larger.name)|\(shape.smaller.name)"
        )
    }
}
