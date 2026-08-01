import Foundation
import SwiftInferCore

/// The **sequence-view model law** — the second of the two model-law families.
///
///     (a == b) == a.elementsEqual(b)
///
/// `ModelLawTemplate` closed the *membership* line (`RangeSet`, five swift.org witnesses);
/// `fixtures/equatable-signal/README.md` recorded the sequence-view line as still open, and
/// said why it was not built with it: its model is "the type's canonical `Sequence` /
/// `Collection` view", and `Set` is a `Sequence` whose order is unspecified, so the law fails
/// spuriously there. *"Resolving that needs an ordered-carrier discriminator, which is its own
/// measurement."* `OrderedCarrierDiscriminator` is that measurement; this is the template it
/// unblocks.
///
/// ## The bugs it rejects
///
/// The three the Equatable laws are structurally blind to, each a real shipped or
/// near-shipped body rather than a strawman:
///
/// - an `OrderedSet` whose `==` compares as a `Set` — order silently stops mattering;
/// - a `BitArray` whose `==` compares raw storage words with the padding bits unmasked;
/// - a `Deque` whose `==` forgets to rotate by `head`, so two logically equal deques with
///   different head positions compare unequal.
///
/// All three pass 4/4 Equatable laws. All three die here at trial ≤3.
///
/// ## The direction that matters, and why the law is a biconditional
///
/// Both halves earn their place, and each catches a different bug above. `a == b ⟹
/// a.elementsEqual(b)` catches the order-insensitive `OrderedSet` — `==` says equal while the
/// elements differ. `a.elementsEqual(b) ⟹ a == b` catches the unrotated `Deque` and the
/// unmasked `BitArray` — the elements agree while `==` says otherwise. Stating only one
/// direction would drop two of the three witnesses, so the template states both.
///
/// That is also exactly why `Range` had to be excluded by the discriminator rather than merely
/// scored down: `5..<5` and `7..<7` are both empty, so the second direction is false for it.
public enum SequenceViewModelLawTemplate {

    public static func suggest(
        for shape: SequenceViewModelPairing.SequenceViewModelShape
    ) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: shape)
    }

    public static func makeConstraint()
        -> Constraint<SequenceViewModelPairing.SequenceViewModelShape> {
        Constraint<SequenceViewModelPairing.SequenceViewModelShape>(
            templateName: "sequence-view-model-law",
            appliesTo: { _ in true },
            signals: Self.signals(for:),
            evidence: { [$0.equals.inferenceEvidence] },
            identity: Self.makeIdentity(for:),
            carrier: { $0.typeName },
            carrierType: { $0.typeName },
            caveats: Self.makeCaveats(for:),
            additionalWhySuggested: Self.makeWhySuggested(for:),
            generators: Self.makeGenerators(for:)
        )
    }

    /// 70 (Likely) without the hash bonus, 80 (Strong) with it.
    ///
    /// **Measured: all seven firings are Strong**, because a type that hand-writes `==` on an
    /// element-determined ordered carrier essentially always hand-writes `hash(into:)` too —
    /// `Hashable`'s contract ties them together. So the bonus is not the discriminator between
    /// tiers it was drafted as; it is close to a constant on this population. Recorded rather
    /// than tuned away: the weight is right on its own terms, and adjusting the arithmetic to
    /// hit a target tier is the thing this repo forbids.
    ///
    /// The score cannot see the law's real hazard, which is **vacuity**: a carrier whose `==`
    /// is *already implemented as* `elementsEqual` — `Deque`'s shipped body is close to exactly
    /// that — makes the law `f(x) == f(x)`, unfalsifiable against a correct implementation. It
    /// still refutes every mutant, so it is worth stating. Detecting that body shape needs a
    /// scanner signal that does not exist yet; until it does, the caveat carries the warning
    /// and the reader is told to open the `==` body before counting the law as evidence.
    static func signals(
        for shape: SequenceViewModelPairing.SequenceViewModelShape
    ) -> [Signal] {
        var signals = [
            Signal(
                kind: .orderSensitiveCarrier,
                weight: 30,
                detail: "\(shape.typeName) conforms to \(shape.orderSignal) — position is "
                    + "determined by the value, not by the representation, so element ORDER is "
                    + "part of what this type means by equality"
            ),
            Signal(
                kind: .equivalenceRelationSignature,
                weight: 20,
                detail: "\(shape.typeName) conforms to "
                    + "\(OrderedCarrierDiscriminator.elementDeterminedSignal) — the type states "
                    + "that a sequence of elements is enough to construct it, so nothing outside "
                    + "the elements contributes to its identity"
            ),
            Signal(
                kind: .exactNameMatch,
                weight: 20,
                detail: "Hand-written `==` at \(shape.equals.location.file):"
                    + "\(shape.equals.location.line). A SYNTHESIZED `==` compares every stored "
                    + "member and cannot be a projection; a hand-written one can, and a "
                    + "projection is still an equivalence relation however wrong it is"
            )
        ]
        if shape.declaresCustomHash {
            signals.append(Signal(
                kind: .algebraicStructureCluster,
                weight: 10,
                detail: "\(shape.typeName) also hand-writes `hash(into:)` — the author is "
                    + "defining value identity deliberately, and a projection in `==` is "
                    + "normally mirrored in the hash"
            ))
        }
        return signals
    }

    static func makeWhySuggested(
        for shape: SequenceViewModelPairing.SequenceViewModelShape
    ) -> [String] {
        [
            "Abstraction function: \(shape.typeName)'s own sequence view. No conversion and no "
                + "annotation is needed — the type already publishes the reference definition "
                + "of its value, and `==` is being held to it."
        ]
    }

    static func makeCaveats(
        for shape: SequenceViewModelPairing.SequenceViewModelShape
    ) -> [String] {
        [
            "THE LAW IS `(a == b) == a.elementsEqual(b)` — `\(shape.typeName)`'s equality means "
                + "exactly 'same elements in the same order'. Both directions are load-bearing: "
                + "left-to-right catches an `==` that has stopped distinguishing orderings, "
                + "right-to-left catches one that distinguishes values it should not (unmasked "
                + "padding, an unrotated head buffer). Confirm the type does not deliberately "
                + "hold state OUTSIDE its elements that equality is meant to see — if it does, "
                + "the right-to-left direction is false and this law is wrong.",
            "IT CAN BE VACUOUS, AND YOU CANNOT TELL FROM THE SUGGESTION. If "
                + "`\(shape.typeName).==` is itself implemented as `elementsEqual` (or as a "
                + "count check plus one), this law is `f(x) == f(x)` and cannot fail on a "
                + "correct implementation. It still refutes a wrong one, so it is worth "
                + "keeping as a regression guard — but read the `==` body before counting it "
                + "as evidence of anything.",
            "THE GENERATOR MUST DRAW PAIRS, NOT TWO INDEPENDENT VALUES. This law is "
                + "collision-dependent in the sense CLAUDE.md records: two independently drawn "
                + "values almost never share elements, so `==` is false and `elementsEqual` is "
                + "false and every trial passes having checked nothing. Construct half the "
                + "pairs to agree — permutations of each other, or the same logical contents "
                + "built through different representations (different insertion orders, a "
                + "buffer grown then shrunk).",
            "The kit's `checkEquatablePropertyLaws` does NOT subsume this and cannot. Its four "
                + "laws ask whether `==` is an equivalence relation; a projection of the stored "
                + "fields is one however wrong it is. Measured: three real projection bodies "
                + "pass 4/4 and fail this law at trial ≤3 "
                + "(`fixtures/equatable-signal/README.md`)."
        ]
    }

    /// The pair generator, with the collision rationale attached at the point of use.
    static func makeGenerators(
        for shape: SequenceViewModelPairing.SequenceViewModelShape
    ) -> [GeneratorRecipe] {
        [
            GeneratorRecipe(
                subject: "(a, b)",
                typeName: "(\(shape.typeName), \(shape.typeName))",
                expression: "Gen.collidingPair(of: \(shape.typeName).self)",
                rationale: "MUST DRAW PAIRS. Independently drawn values share no elements, so "
                    + "both sides of the law are false and the trial checks nothing. Half the "
                    + "pairs should be built to agree — permutations of one another, or equal "
                    + "contents reached through different representations — because that is the "
                    + "only region where `==` and the sequence view can disagree."
            )
        ]
    }

    static func makeIdentity(
        for shape: SequenceViewModelPairing.SequenceViewModelShape
    ) -> SuggestionIdentity {
        SuggestionIdentity(
            canonicalInput: "sequence-view-model-law|\(shape.typeName)|"
                + IdempotenceTemplate.canonicalSignature(of: shape.equals)
        )
    }
}
