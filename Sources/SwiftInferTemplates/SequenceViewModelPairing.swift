import Foundation
import SwiftInferCore

/// Recognises the **sequence-view model law**: a carrier whose `==` is hand-written, whose
/// iteration order is part of its value, and whose value is determined by its elements —
/// so `==` owes agreement with the sequence view.
///
///     (a == b) == a.elementsEqual(b)
///
/// ## Why a hand-written `==` is the whole point
///
/// `fixtures/equatable-signal/README.md` set out to test whether an `Equatable` conformance
/// alone justifies a property test and measured the answer as **no** — conformance does not
/// predict refutability. What predicts it is the **shape of the `==` body**, and specifically
/// whether it is a *projection* of the stored fields. A projection is still an equivalence
/// relation however wrong it is, so all four Equatable laws pass and the kit's
/// `checkEquatablePropertyLaws` cannot see the bug.
///
/// A **synthesized** `==` cannot be a projection: the compiler compares every stored member.
/// So the carrier must declare its own, and that declaration is the signal.
///
/// ## Why this is not a kit double-report
///
/// `checkEquatablePropertyLaws` asserts reflexivity, symmetry, transitivity and
/// negation-consistency. Measured on three real projection bodies reproduced with the bug each
/// depends on not having — an order-insensitive `OrderedSet`, a `BitArray` with padding
/// unmasked (which is the *shipped* body, correct only while an invariant `==` does not itself
/// enforce keeps holding), and a `Deque` that forgets to rotate by `head` — **3 of 3 pass 4/4
/// Equatable laws and 3 of 3 die against the model law at trial ≤3.**
///
/// The kit asks "is this an equivalence relation". The answer is yes for every one of them.
/// This asks "is it the *right* equivalence relation", which needs an independent reference
/// definition of the value — and the sequence view is one the type already publishes.
public enum SequenceViewModelPairing {

    /// One statable sequence-view law.
    public struct SequenceViewModelShape: Sendable, Equatable {

        /// The carrier, generic parameters stripped — `OrderedSet`.
        public let typeName: String

        /// The hand-written `==` this law holds to account.
        public let equals: FunctionSummary

        /// The conformance that established order is value-determined, for explainability.
        public let orderSignal: String

        /// Whether the carrier also hand-writes `hash(into:)`. Hashable's own contract ties
        /// hashing to `==`, so an author writing both is defining value identity deliberately
        /// rather than inheriting it — and a projection bug in `==` is normally mirrored there.
        public let declaresCustomHash: Bool

        public init(
            typeName: String,
            equals: FunctionSummary,
            orderSignal: String,
            declaresCustomHash: Bool
        ) {
            self.typeName = typeName
            self.equals = equals
            self.orderSignal = orderSignal
            self.declaresCustomHash = declaresCustomHash
        }
    }

    /// Every sequence-view law statable from `summaries`, ordered deterministically.
    ///
    /// `inheritedTypesByName` is the corpus-wide conformance index — the same one the
    /// protocol-coverage vetoes read — so the discriminator sees conformances added by an
    /// extension in another file, which is how `Deque: RandomAccessCollection` is declared.
    public static func candidates(
        in summaries: [FunctionSummary],
        inheritedTypesByName: [String: Set<String>]
    ) -> [SequenceViewModelShape] {
        var byCarrier: [String: [FunctionSummary]] = [:]
        for summary in summaries {
            guard let carrier = summary.containingTypeName, !carrier.isEmpty else { continue }
            byCarrier[stripGenerics(carrier), default: []].append(summary)
        }

        var result: [SequenceViewModelShape] = []
        for (carrier, members) in byCarrier.sorted(by: { $0.key < $1.key }) {
            guard let equals = equalityOperator(in: members, carrier: carrier) else { continue }
            let conformances = inheritedTypesByName[carrier] ?? []
            guard case .elementDetermined(let signal) =
                OrderedCarrierDiscriminator.verdict(forConformances: conformances) else {
                continue
            }
            result.append(SequenceViewModelShape(
                typeName: carrier,
                equals: equals,
                orderSignal: signal,
                declaresCustomHash: members.contains { $0.name == "hash" }
            ))
        }
        return result
    }

    /// A hand-written `static func == (lhs: T, rhs: T) -> Bool` on this carrier.
    ///
    /// Both operands must be the carrier. A heterogeneous `==` (`Substring == String`) states a
    /// different claim, and the law's `elementsEqual` right-hand side would be comparing two
    /// different element types.
    static func equalityOperator(
        in members: [FunctionSummary], carrier: String
    ) -> FunctionSummary? {
        members
            .filter { summary in
                summary.name == "=="
                    && summary.returnTypeText == "Bool"
                    && summary.parameters.count == 2
                    && summary.parameters.allSatisfy {
                        matchesCarrier($0.typeText, carrier: carrier) && !$0.isInout
                    }
                    && !summary.isThrows && !summary.isAsync
            }
            // Deterministic pick when a type declares several `==` overloads.
            .min { $0.location.line < $1.location.line }
    }

    /// `OrderedSet<Element>`, `OrderedSet` and `Self` all name the carrier.
    static func matchesCarrier(_ typeText: String, carrier: String) -> Bool {
        let trimmed = typeText.trimmingCharacters(in: .whitespaces)
        return trimmed == "Self" || stripGenerics(trimmed) == carrier
    }

    /// `OrderedSet<Element>` → `OrderedSet`.
    static func stripGenerics(_ typeText: String) -> String {
        let trimmed = typeText.trimmingCharacters(in: .whitespaces)
        guard let angle = trimmed.firstIndex(of: "<") else { return trimmed }
        return String(trimmed[trimmed.startIndex..<angle])
    }
}
