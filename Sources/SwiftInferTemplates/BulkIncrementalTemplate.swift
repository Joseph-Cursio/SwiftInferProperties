import Foundation
import SwiftInferCore

/// The **bulk-vs-incremental** law — one call must agree with one element at a time.
///
///     T(elements) == elements.reduce(into: T()) { $0.insert($1) }
///
/// Row 1 of the swift.org `loops` answer key, the last of the seven gap families to be
/// assessed. See `BulkIncrementalPairing` for the witness, the element-type
/// discriminator, and why the population is thin for a reason that is a scanner
/// limitation rather than a fact about the shape.
public enum BulkIncrementalTemplate {

    public static func suggest(
        for shape: BulkIncrementalPairing.BulkIncrementalShape
    ) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: shape)
    }

    public static func makeConstraint()
        -> Constraint<BulkIncrementalPairing.BulkIncrementalShape> {
        Constraint<BulkIncrementalPairing.BulkIncrementalShape>(
            templateName: "bulk-incremental-agreement",
            appliesTo: { _ in true },
            signals: Self.signals(for:),
            evidence: { [$0.inserter.inferenceEvidence] },
            identity: Self.makeIdentity(for:),
            carrier: { $0.typeName },
            carrierType: { $0.typeName },
            caveats: Self.makeCaveats(for:),
            additionalWhySuggested: Self.makeWhySuggested(for:),
            generators: Self.makeGenerators(for:)
        )
    }

    /// 70 (Likely). No cluster bonus: unlike the set-operation families there is no
    /// second co-occurring name that corroborates the reading, because the two halves of
    /// this law are the *only* two things it needs and both are already required for the
    /// shape to be recognised at all. A bonus that always fires is not a signal.
    static func signals(
        for shape: BulkIncrementalPairing.BulkIncrementalShape
    ) -> [Signal] {
        [
            Signal(
                kind: .typeSymmetrySignature,
                weight: 40,
                detail: "Two ways to build one value: `\(shape.typeName)"
                    + "(\(shape.bulkParameterTypeText))` in bulk, and "
                    + "`\(shape.inserter.name)` one \(shape.elementTypeText) at a time from "
                    + "`\(shape.typeName)()`. They must agree"
            ),
            Signal(
                kind: .exactNameMatch,
                weight: 30,
                detail: "Curated accumulator name: '\(shape.inserter.name)' — adding one "
                    + "element is definitional for it, so the fold is the incremental "
                    + "construction rather than a guess at one"
            )
        ]
    }

    static func makeWhySuggested(
        for shape: BulkIncrementalPairing.BulkIncrementalShape
    ) -> [String] {
        [
            "Element match: the bulk parameter is `\(shape.bulkParameterTypeText)` and "
                + "`\(shape.inserter.name)` takes `\(shape.elementTypeText)`, so the fold "
                + "consumes exactly what the bulk call consumes. A carrier with several "
                + "accumulators is paired on this, not on the name"
        ]
    }

    static func makeCaveats(
        for shape: BulkIncrementalPairing.BulkIncrementalShape
    ) -> [String] {
        [
            "THE LAW IS `\(shape.lawText)` — building in one call agrees with building one "
                + "element at a time. Confirm the bulk entry point is meant to be a "
                + "*shortcut* and not a different operation: a bulk initializer that "
                + "deliberately sorts, de-duplicates or clamps where the incremental path "
                + "does not is a design choice, and this law is then false by intent rather "
                + "than by defect.",
            "THE GENERATOR MUST PRODUCE DUPLICATES AND ADJACENCY, or the law is close to "
                + "vacuous. Bulk and incremental paths agree trivially on distinct, "
                + "well-separated elements — they diverge exactly where a batch step can "
                + "take a shortcut the loop cannot: repeated elements, adjacent or "
                + "overlapping ranges, and the empty sequence. Draw elements from a narrow "
                + "alphabet so collisions are common, and include the empty case "
                + "explicitly.",
            "ORDER IS PART OF THE CLAIM. The fold applies `\(shape.inserter.name)` in "
                + "sequence order, so this states that the bulk path behaves as if it did "
                + "the same. For a carrier whose result depends on insertion order — an "
                + "ordered set resolving duplicates by first-wins or last-wins — the law is "
                + "the thing that pins which policy the bulk path implements, and a failure "
                + "means the two paths disagree about it.",
            "This is not covered by `checkRangeReplaceableCollectionPropertyLaws`, whose "
                + "four laws are `emptyInitIsEmpty`, `removeAllMakesEmpty`, "
                + "`removeAtInsertRoundTrip` and `replaceSubrangeAppliesEdit` — none relates "
                + "a bulk construction to a fold."
        ]
    }

    static func makeGenerators(
        for shape: BulkIncrementalPairing.BulkIncrementalShape
    ) -> [GeneratorRecipe] {
        [
            GeneratorRecipe(
                subject: "elements",
                typeName: shape.bulkParameterTypeText,
                expression: "Gen.collidingSequence(of: \(shape.elementTypeText).self)",
                rationale: "DELIBERATELY COLLISION-HEAVY, and include the empty sequence. "
                    + "The two construction paths agree trivially on distinct, "
                    + "well-separated elements; they diverge where a batch step can shortcut "
                    + "what the loop must do element by element — duplicates, adjacency, "
                    + "overlap. Draw from a narrow alphabet or the suite goes green having "
                    + "exercised only the easy half of the domain."
            )
        ]
    }

    static func makeIdentity(
        for shape: BulkIncrementalPairing.BulkIncrementalShape
    ) -> SuggestionIdentity {
        SuggestionIdentity(
            canonicalInput: "bulk-incremental-agreement|\(shape.typeName)|"
                + "\(shape.elementTypeText)|"
                + IdempotenceTemplate.canonicalSignature(of: shape.inserter)
        )
    }
}
