import Foundation
import SwiftInferCore

/// **Same-end access round-trip** — adding at one end and removing from that end returns
/// what you put in and leaves the container as it was.
///
///     var copy = c; copy.append(x); copy.removeLast() == x && copy == c
///
/// The stack / queue / deque family from `known-properties`' `[reference]` rows. See
/// `EndedAccessPairing` for the two admission gates and the `PriorityQueue` witness that
/// forced the second.
public enum EndedAccessRoundTripTemplate {

    public static func suggest(
        for shape: EndedAccessPairing.EndedAccessShape
    ) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: shape)
    }

    public static func makeConstraint() -> Constraint<EndedAccessPairing.EndedAccessShape> {
        Constraint<EndedAccessPairing.EndedAccessShape>(
            templateName: "ended-access-round-trip",
            appliesTo: { _ in true },
            signals: Self.signals(for:),
            evidence: { [$0.addition.inferenceEvidence, $0.removal.inferenceEvidence] },
            identity: Self.makeIdentity(for:),
            carrier: { $0.typeName },
            carrierType: { $0.typeName },
            caveats: Self.makeCaveats(for:),
            additionalWhySuggested: Self.makeWhySuggested(for:),
            generators: Self.makeGenerators(for:)
        )
    }

    /// 75 (Strong). Both halves are positionally named and their ends agree, which is a
    /// strong joint claim — a carrier does not accidentally expose `append` *and*
    /// `removeLast`. The weight sits above the model-law families deliberately: those
    /// infer a law from one name plus a shape, this one has two names agreeing.
    static func signals(for shape: EndedAccessPairing.EndedAccessShape) -> [Signal] {
        [
            Signal(
                kind: .exactNameMatch,
                weight: 45,
                detail: "Curated same-end pair: '\(shape.addition.name)' and "
                    + "'\(shape.removal.name)' both name the \(shape.end.rawValue) of the "
                    + "container. A bare `pop` would not — swift-nio's `PriorityQueue` "
                    + "returns the extremum from one, so an unnamed end is not assumed"
            ),
            Signal(
                kind: .inverseMutatorPair,
                weight: 30,
                detail: "Mutating add/remove pair on \(shape.typeName): "
                    + "`\(shape.addition.name)(\(shape.elementTypeText))` against "
                    + "`\(shape.removal.name)() -> \(shape.removal.returnTypeText ?? "?")`"
            )
        ]
    }

    static func makeWhySuggested(
        for _: EndedAccessPairing.EndedAccessShape
    ) -> [String] {
        [
            "From the `known-properties` [reference] rows — the stack/queue/deque laws the "
                + "catalog already verifies on stdlib types but that no template could "
                + "transfer to a carrier of your own until now"
        ]
    }

    static func makeCaveats(for shape: EndedAccessPairing.EndedAccessShape) -> [String] {
        var caveats = [
            "THE LAW IS `\(shape.lawText)` — and the second half is the load-bearing one. "
                + "Returning `x` is easy; RESTORING the container is where a ring buffer's "
                + "head pointer, a capacity shrink, or a stale count shows up. A law that "
                + "only checked the returned value would pass on an implementation that "
                + "leaks a slot on every round trip.",
            "IT IS A CLAIM ABOUT ONE END. `\(shape.addition.name)` and "
                + "`\(shape.removal.name)` both act on the \(shape.end.rawValue); pairing "
                + "an add at one end with a removal at the other is a FIFO queue, where "
                + "this law is false for any non-empty container. If this type is a queue, "
                + "the property you want is the ordering law, not this one.",
            "CONFIRM THE REMOVAL IS POSITIONAL, not priority-ordered. The gate is the name: "
                + "`\(shape.removal.name)` says which end. A carrier that reinterprets it — "
                + "returning a minimum, a most-recently-used entry, or a random element — "
                + "does not owe this law, and the failure would be a finding about the name "
                + "rather than about the code."
        ]
        if shape.removalIsOptional {
            caveats.append(
                "`\(shape.removal.name)` returns an Optional, so the law is stated over "
                    + "`.some(x)`. The empty container is a SEPARATE property — that "
                    + "`\(shape.removal.name)` on empty returns `nil` rather than trapping — "
                    + "and this law says nothing about it."
            )
        }
        caveats.append(
            "If this carrier is swift-collections' `Deque`, prefer the kit: "
                + "`checkDequeSymmetryPropertyLaws` already runs `prependPopFirstRoundTrips` "
                + "and `appendPopLastRoundTrips`. The kit states them over the *concrete* "
                + "type — its own doc notes there is no double-ended protocol to abstract "
                + "over — which is exactly why this template exists for everything else."
        )
        return caveats
    }

    static func makeGenerators(
        for shape: EndedAccessPairing.EndedAccessShape
    ) -> [GeneratorRecipe] {
        [
            GeneratorRecipe(
                subject: "c",
                typeName: shape.typeName,
                expression: "Gen<\(shape.typeName)>.includingEmptyAndAtCapacity()",
                rationale: "THE INTERESTING CONTAINERS ARE THE DEGENERATE ONES. A "
                    + "mid-sized container round-trips on almost any implementation; the "
                    + "failures live at the EMPTY container, at exactly one element, and at "
                    + "whatever capacity boundary forces a reallocation or a wrap-around. "
                    + "Draw those deliberately — a uniform size distribution will miss all "
                    + "three and report green."
            )
        ]
    }

    static func makeIdentity(for shape: EndedAccessPairing.EndedAccessShape) -> SuggestionIdentity {
        SuggestionIdentity(
            canonicalInput: "ended-access-round-trip|\(shape.typeName)|\(shape.end.rawValue)|"
                + "\(shape.addition.name)|\(shape.removal.name)"
        )
    }
}
