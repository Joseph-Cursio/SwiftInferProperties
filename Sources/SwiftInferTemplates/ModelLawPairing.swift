import Foundation
import SwiftInferCore

/// Recognises the **membership model law**: a type whose operations are named after set
/// operations, and which exposes a membership predicate to state them against.
///
/// ## Why the abstraction function is `contains`, not a conversion
///
/// The obvious way to state a model law is to convert: `Set(a.union(b)) == Set(a).union(Set(b))`.
/// That needs a conversion `T -> Model`, and the motivating type does not have one. `RangeSet`
/// (`stdlib/public/core/RangeSet.swift:30`) conforms to `Equatable, Hashable, Sendable,
/// CustomStringConvertible` — **not** `SetAlgebra`, and **not** `Sequence`. There is no free
/// abstraction function to be had from a conformance, and the swift.org tests supply one by
/// hand (`unionViaSet`) inside the test file, where no source-only analysis can see it.
///
/// What `RangeSet` *does* have is `contains(_:) -> Bool`. That is the abstraction function,
/// pointwise: a set **is** its characteristic function, so
///
///     (a.union(b)).contains(x) == (a.contains(x) || b.contains(x))
///
/// states the model law using nothing but the type's own API. No conversion, no conformance,
/// no annotation — which is why this template can reach code that `invariant-preservation`
/// (annotation-only) cannot.
///
/// ## Why this is not a double-report
///
/// PropertyLawKit ships `checkSetAlgebraPropertyLaws` with **15 laws** — union/intersection
/// commutativity and idempotence, distributivity, De Morgan, absorption, the
/// symmetric-difference identities. Every one of them relates the operations *to each other*,
/// and the suite mentions `contains` **zero** times. It proves the lattice algebra and never
/// ties it to membership.
///
/// That gap is the point. The membership law *entails* those 15 (modulo extensionality —
/// `||` is commutative, so pointwise agreement forces `a ∪ b == b ∪ a` whenever `contains`
/// determines equality), so it is the strictly stronger claim, and it fails on bugs the
/// algebra survives. A range-backed union that forgets to merge the seam `[1,3) ∪ [3,5)` into
/// `[1,5)` can still be commutative, idempotent and absorptive — and still wrong at `x == 3`.
public enum ModelLawPairing {

    /// The set operations this template knows how to state pointwise, with the Boolean
    /// combinator each one owes.
    ///
    /// Deliberately closed and small. Every entry is an operation whose membership semantics
    /// are *definitional* rather than conventional — there is no reasonable type for which
    /// `union` means something other than "in either". Names outside this list, however
    /// set-adjacent, are not guessed at.
    public enum SetOperation: String, Sendable, Equatable, CaseIterable {
        case union
        case intersection
        case symmetricDifference
        case subtracting

        /// The right-hand side of the law, as Swift, given operand names.
        public func membershipExpression(_ lhs: String, _ rhs: String, element: String) -> String {
            switch self {
            case .union:
                return "\(lhs).contains(\(element)) || \(rhs).contains(\(element))"

            case .intersection:
                return "\(lhs).contains(\(element)) && \(rhs).contains(\(element))"

            case .symmetricDifference:
                return "\(lhs).contains(\(element)) != \(rhs).contains(\(element))"

            case .subtracting:
                return "\(lhs).contains(\(element)) && !\(rhs).contains(\(element))"
            }
        }

        /// Prose for the caveat, so the reader can check the combinator against intent.
        public var membershipProse: String {
            switch self {
            case .union: return "in either operand"
            case .intersection: return "in both operands"
            case .symmetricDifference: return "in exactly one operand"
            case .subtracting: return "in the first and not the second"
            }
        }
    }

    /// One statable membership law: an operation, and the predicate that gives it meaning.
    public struct MembershipModelShape: Sendable, Equatable {

        /// The carrier, generic parameters stripped — `RangeSet`.
        public let typeName: String

        /// The set-shaped operation, `(T) -> T`.
        public let operation: FunctionSummary

        /// The membership predicate on the same carrier, `(Element) -> Bool`.
        public let membership: FunctionSummary

        /// Which law to state.
        public let form: SetOperation

        /// The element domain the law quantifies over — the `contains` parameter type.
        public let elementTypeText: String

        /// How many curated set operations the carrier exposes in total. A type with all four
        /// is unmistakably set-like; one with a lone `union` might be a merge.
        public let siblingOperationCount: Int

        public init(
            typeName: String,
            operation: FunctionSummary,
            membership: FunctionSummary,
            form: SetOperation,
            elementTypeText: String,
            siblingOperationCount: Int
        ) {
            self.typeName = typeName
            self.operation = operation
            self.membership = membership
            self.form = form
            self.elementTypeText = elementTypeText
            self.siblingOperationCount = siblingOperationCount
        }
    }

    /// Every membership law statable from `summaries`, ordered deterministically.
    public static func candidates(in summaries: [FunctionSummary]) -> [MembershipModelShape] {
        var byCarrier: [String: [FunctionSummary]] = [:]
        for summary in summaries {
            guard let carrier = summary.containingTypeName, !carrier.isEmpty else { continue }
            byCarrier[stripGenerics(carrier), default: []].append(summary)
        }
        var result: [MembershipModelShape] = []
        for (carrier, members) in byCarrier.sorted(by: { $0.key < $1.key }) {
            guard let membership = membershipPredicate(in: members, carrier: carrier),
                  let elementType = membership.parameters.first?.typeText else { continue }
            let operations = members.compactMap { summary in
                setOperation(of: summary, carrier: carrier).map { (summary, $0) }
            }
            .sorted { $0.1.rawValue < $1.1.rawValue }
            for (summary, form) in operations {
                result.append(MembershipModelShape(
                    typeName: carrier,
                    operation: summary,
                    membership: membership,
                    form: form,
                    elementTypeText: elementType,
                    siblingOperationCount: operations.count
                ))
            }
        }
        return result
    }

    /// `contains(_:) -> Bool`, positional, effect-free, and **over an element rather than the
    /// carrier**, on this carrier.
    ///
    /// Positional on purpose. A labelled `contains(where:)` takes a *closure*, and a
    /// `contains(subrange:)` asks a different question; neither is the characteristic function
    /// the law needs.
    ///
    /// **The element check is the one that was missing, and it produced three false positives
    /// at Strong tier on the first measured run.** `OptionSet.contains(_ member: Self) -> Bool`
    /// (`OptionSet.swift:216`) is a **subset test**, not membership — and read as membership the
    /// law is not merely unproven but false: `x ⊆ (a ∪ b) ⟺ x ⊆ a ∨ x ⊆ b` fails for
    /// `x = {1,2}`, `a = {1}`, `b = {2}`. A characteristic function maps *elements* to `Bool`;
    /// a `(Self) -> Bool` is a relation between two sets and states nothing pointwise.
    ///
    /// The cost is a set-of-sets carrier (`Set<Set<Int>>`), whose element genuinely is the
    /// carrier's own base name and which is therefore skipped. That is the conservative
    /// direction and the trade is deliberate: a missed law over a false one at Strong.
    static func membershipPredicate(
        in members: [FunctionSummary], carrier: String
    ) -> FunctionSummary? {
        members
            .filter { summary in
                summary.name == "contains"
                    && summary.returnTypeText == "Bool"
                    && summary.parameters.count == 1
                    && summary.parameters.first?.label == nil
                    && summary.parameters.first?.isInout == false
                    && !matchesCarrier(summary.parameters.first?.typeText ?? "", carrier: carrier)
                    && !summary.isMutating && !summary.isThrows
                    && !summary.isAsync && !summary.isStatic
            }
            // Deterministic pick when a type overloads `contains` positionally.
            .min { $0.location.line < $1.location.line }
    }

    /// A curated set operation of shape `(T) -> T` on carrier `T`.
    ///
    /// The non-mutating half only: `formUnion` returns `Void`, so there is no value to ask
    /// `contains` of. `dual-style-consistency` already relates the two halves, and relating a
    /// mutation to its returning twin is that template's job, not this one's.
    static func setOperation(of summary: FunctionSummary, carrier: String) -> SetOperation? {
        guard let form = SetOperation(rawValue: summary.name),
              !summary.isMutating, !summary.isThrows, !summary.isAsync, !summary.isStatic,
              summary.parameters.count == 1,
              let parameter = summary.parameters.first,
              parameter.label == nil, !parameter.isInout,
              let returnType = summary.returnTypeText,
              matchesCarrier(parameter.typeText, carrier: carrier),
              matchesCarrier(returnType, carrier: carrier) else {
            return nil
        }
        return form
    }

    /// `RangeSet<Bound>`, `RangeSet` and `Self` all name the carrier.
    static func matchesCarrier(_ typeText: String, carrier: String) -> Bool {
        let trimmed = typeText.trimmingCharacters(in: .whitespaces)
        return trimmed == "Self" || stripGenerics(trimmed) == carrier
    }

    /// `RangeSet<Bound>` → `RangeSet`. Nested generics are irrelevant here: the carrier is
    /// always the outermost name.
    static func stripGenerics(_ typeText: String) -> String {
        let trimmed = typeText.trimmingCharacters(in: .whitespaces)
        guard let angle = trimmed.firstIndex(of: "<") else { return trimmed }
        return String(trimmed[trimmed.startIndex..<angle])
    }
}
