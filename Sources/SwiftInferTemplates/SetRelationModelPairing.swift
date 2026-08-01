import Foundation
import SwiftInferCore

/// Recognises the **boolean-valued** half of the membership model law: a carrier that
/// answers a *relation* between two sets — `isDisjoint(with:)`, `isSubset(of:)` — and
/// exposes the membership predicate needed to hold that answer to account.
///
/// ## Why this is a separate shape from `ModelLawPairing`
///
/// That one states an **equation** at a point:
///
///     (a.union(b)).contains(x) == (a.contains(x) || b.contains(x))
///
/// A relation cannot be stated that way, because its answer is a single `Bool` about the
/// whole pair rather than a set to interrogate. What *is* statable pointwise is an
/// **implication**:
///
///     if a.isDisjoint(with: b) { expect(!(a.contains(x) && b.contains(x))) }
///
/// ## The direction this cannot check, stated plainly
///
/// Only one direction. `isDisjoint` returning `true` is refuted by any `x` in both
/// operands, so a predicate that wrongly claims disjointness dies as soon as the
/// generator lands in the overlap. A predicate that wrongly claims *non*-disjointness
/// cannot be refuted pointwise — that needs an existential ("there is no such `x`"),
/// which no single trial can establish.
///
/// That is a real limitation and it is the honest half of the bargain. It is also the
/// direction that matters: an interval- or bitset-backed `isDisjoint` fails by missing an
/// overlap at a seam, which is a false `true`.
///
/// ## Provenance
///
/// Rows 6 and 7 of `fixtures/swiftorg-study/loops-answer-key.json` — `RangeSet.isDisjoint`
/// and `RangeSet.isSubset`, both `gap-with-witness`, both hand-written against `Set<Int>`
/// as reference semantics.
///
/// `ModelLawTemplate` was built from the same cluster and findings §1.25 recorded that
/// *"the five swift.org `RangeSet` witnesses are now covered"*. Measured 2026-08-01: it
/// covers **three** of them. `union` / `intersection` / `symmetricDifference` fire;
/// `isDisjoint` and `isSubset` are boolean-valued and were never in `SetOperation`.
///
/// ## Not a kit double-report, checked before building
///
/// `checkSetAlgebraPropertyLaws` ships 15 laws — idempotence, commutativity, distributivity,
/// De Morgan, absorption, the symmetric-difference identities. Every one relates the
/// *operations* to each other, and the suite mentions `isSubset`, `isDisjoint` and
/// `isSuperset` **zero** times.
public enum SetRelationModelPairing {

    /// The relations this template knows how to state pointwise.
    ///
    /// **The strict variants are deliberately absent.** `isStrictSubset` differs from
    /// `isSubset` only in requiring the containment to be proper, and properness is an
    /// existential — pointwise, the two produce an identical law. Including them would add
    /// rows that cannot test the thing their name is about, which is what "score
    /// refutability, not suggestion count" forbids.
    public enum SetRelation: String, Sendable, Equatable, CaseIterable {
        case isDisjoint
        case isSubset
        case isSuperset

        /// The pointwise law, as Swift, given operand names.
        public func pointwiseLaw(_ lhs: String, _ rhs: String, element: String) -> String {
            switch self {
            case .isDisjoint:
                return "if \(lhs).isDisjoint(with: \(rhs)) { "
                    + "expect(!(\(lhs).contains(\(element)) && \(rhs).contains(\(element)))) }"

            case .isSubset:
                return "if \(lhs).isSubset(of: \(rhs)), \(lhs).contains(\(element)) { "
                    + "expect(\(rhs).contains(\(element))) }"

            case .isSuperset:
                return "if \(lhs).isSuperset(of: \(rhs)), \(rhs).contains(\(element)) { "
                    + "expect(\(lhs).contains(\(element))) }"
            }
        }

        /// Prose for the caveat, so a reader can check the claim against intent.
        public var prose: String {
            switch self {
            case .isDisjoint:
                return "no element is in both operands"

            case .isSubset:
                return "every element of the first is in the second"

            case .isSuperset:
                return "every element of the second is in the first"
            }
        }

        /// The failure this law catches — a wrong `true`.
        public var refutedBy: String {
            switch self {
            case .isDisjoint:
                return "an overlap the predicate missed, typically at a seam"

            case .isSubset, .isSuperset:
                return "an element of the smaller set the predicate failed to find in the larger"
            }
        }
    }

    /// One statable relation law.
    public struct SetRelationShape: Sendable, Equatable {

        /// The carrier, generic parameters stripped — `RangeSet`.
        public let typeName: String

        /// The relation, `(T) -> Bool` on carrier `T`.
        public let relation: FunctionSummary

        /// The membership predicate on the same carrier, `(Element) -> Bool`.
        public let membership: FunctionSummary

        /// Which law to state.
        public let form: SetRelation

        /// The element domain the law quantifies over — the `contains` parameter type.
        public let elementTypeText: String

        /// How many curated relations the carrier exposes. A type with all three is
        /// unmistakably set-like; a lone `isSubset` might be a prefix or range test.
        public let siblingRelationCount: Int

        public init(
            typeName: String,
            relation: FunctionSummary,
            membership: FunctionSummary,
            form: SetRelation,
            elementTypeText: String,
            siblingRelationCount: Int
        ) {
            self.typeName = typeName
            self.relation = relation
            self.membership = membership
            self.form = form
            self.elementTypeText = elementTypeText
            self.siblingRelationCount = siblingRelationCount
        }
    }

    /// Every relation law statable from `summaries`, ordered deterministically.
    public static func candidates(in summaries: [FunctionSummary]) -> [SetRelationShape] {
        var byCarrier: [String: [FunctionSummary]] = [:]
        for summary in summaries {
            guard let carrier = summary.containingTypeName, !carrier.isEmpty else { continue }
            byCarrier[ModelLawPairing.stripGenerics(carrier), default: []].append(summary)
        }
        var result: [SetRelationShape] = []
        for (carrier, members) in byCarrier.sorted(by: { $0.key < $1.key }) {
            // Reuses the shipped membership gate verbatim, including the element-typed
            // check that stopped three `OptionSet` false positives at Strong on the first
            // measured run of the sibling template.
            guard let membership = ModelLawPairing.membershipPredicate(in: members, carrier: carrier),
                  let elementType = membership.parameters.first?.typeText else { continue }
            let relations = members.compactMap { summary in
                setRelation(of: summary, carrier: carrier).map { (summary, $0) }
            }
            .sorted { $0.1.rawValue < $1.1.rawValue }
            for (summary, form) in relations {
                result.append(SetRelationShape(
                    typeName: carrier,
                    relation: summary,
                    membership: membership,
                    form: form,
                    elementTypeText: elementType,
                    siblingRelationCount: relations.count
                ))
            }
        }
        return result
    }

    /// A curated set relation of shape `(T) -> Bool` on carrier `T`.
    static func setRelation(of summary: FunctionSummary, carrier: String) -> SetRelation? {
        guard let form = SetRelation(rawValue: summary.name),
              !summary.isMutating, !summary.isThrows, !summary.isAsync, !summary.isStatic,
              summary.returnTypeText == "Bool",
              summary.parameters.count == 1,
              let parameter = summary.parameters.first,
              !parameter.isInout,
              ModelLawPairing.matchesCarrier(parameter.typeText, carrier: carrier) else {
            return nil
        }
        return form
    }
}
