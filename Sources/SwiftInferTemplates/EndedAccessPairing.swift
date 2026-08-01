import Foundation
import SwiftInferCore

/// Recognises a **same-end add/remove pair** — the shape behind the catalog's stack,
/// queue and deque laws.
///
///     var copy = container
///     copy.append(x)
///     copy.removeLast() == x && copy == container
///
/// ## Provenance: the `[reference]` half of `known-properties`
///
/// `swift-infer known-properties` ships 71 known-true laws, 49 of them tagged
/// `[reference]` — *"true and self-verified under `--verify`, but invisible to `discover`
/// because no template names its shape."* Five of those are this family:
///
/// - `Stack`: "push x then pop ⇒ x, and the stack is restored"  `[LIFO via append/removeLast]`
/// - `Queue`: "the first enqueued is the first dequeued"  `[FIFO via append/removeFirst]`
/// - `Deque`: "prepend(x) then removeFirst() yields x and restores the deque"
///
/// **The laws were already usable; what was missing is transfer.** `--verify` executes
/// them against stdlib types today. What no template could do is look at a *user's*
/// `RingBuffer` and say it owes the same law. That is what this adds — and it is why the
/// measurement that matters is carriers reached outside the catalog, not whether the law
/// is true.
///
/// ## The end must match, and both ends must be NAMED
///
/// Two gates, and the second was found by the population sweep rather than designed.
///
/// **Ends must match.** Back-add with back-remove round-trips; back-add with
/// *front*-remove is a FIFO queue, where the law is false for any non-empty container.
///
/// **Both must name an end.** swift-nio's `PriorityQueue` exposes `push`/`pop`, and
/// `push(x); pop() == x` is **false** there — a priority queue's `pop` returns the
/// extremum, not the last pushed. A bare `pop` names no end and cannot be assumed to
/// take one; `popLast` can. This is the `OptionSet.contains` lesson in a new costume: a
/// verb that looks definitional until a carrier reinterprets it.
///
/// Requiring positional names costs nothing measured — `PriorityQueue` was the only bare
/// `push`/`pop` pair in seven corpora — and buys the one false positive the sweep found.
public enum EndedAccessPairing {

    /// Which end of the container an operation acts on. Every name below *says* its end;
    /// that is the admission requirement, not a convenience.
    public enum End: String, Sendable, Equatable {
        case back
        case front
    }

    /// Positionally-named insertions.
    ///
    /// `append` and `prepend` earn their place because the words mean "at the end" and
    /// "at the start" and no container reinterprets them. `push` alone does not.
    public static let additions: [String: End] = [
        "append": .back,
        "pushLast": .back,
        "appendLast": .back,
        "prepend": .front,
        "pushFirst": .front,
        "insertFirst": .front
    ]

    /// Positionally-named removals. Note the absence of bare `pop` and `dequeue` — see
    /// the type doc for the `PriorityQueue` witness.
    public static let removals: [String: End] = [
        "removeLast": .back,
        "popLast": .back,
        "removeFirst": .front,
        "popFirst": .front
    ]

    /// One statable same-end round-trip.
    public struct EndedAccessShape: Sendable, Equatable {

        /// The carrier, generic parameters stripped.
        public let typeName: String

        /// The insertion — `append`.
        public let addition: FunctionSummary

        /// The removal at the same end — `removeLast`.
        public let removal: FunctionSummary

        /// Which end both act on.
        public let end: End

        /// The element type the law quantifies over.
        public let elementTypeText: String

        /// `true` when the removal returns an `Optional`, so the law needs unwrapping and
        /// the empty-container case answers `nil` rather than trapping.
        public let removalIsOptional: Bool

        public init(
            typeName: String,
            addition: FunctionSummary,
            removal: FunctionSummary,
            end: End,
            elementTypeText: String,
            removalIsOptional: Bool
        ) {
            self.typeName = typeName
            self.addition = addition
            self.removal = removal
            self.end = end
            self.elementTypeText = elementTypeText
            self.removalIsOptional = removalIsOptional
        }

        /// The law, as Swift.
        public var lawText: String {
            let got = removalIsOptional ? "copy.\(removal.name)() == .some(x)" : "copy.\(removal.name)() == x"
            return "var copy = c; copy.\(addition.name)(x); \(got) && copy == c"
        }
    }

    /// Every same-end round-trip statable from `summaries`, ordered deterministically.
    public static func candidates(in summaries: [FunctionSummary]) -> [EndedAccessShape] {
        let additionsByCarrier = index(summaries, admitting: isAdmissibleAddition)
        let removalsByCarrier = index(summaries, admitting: isAdmissibleRemoval)
        var result: [EndedAccessShape] = []
        var seen: Set<String> = []
        for (carrier, additionList) in additionsByCarrier.sorted(by: { $0.key < $1.key }) {
            guard let removalList = removalsByCarrier[carrier] else { continue }
            for addition in additionList.sorted(by: { $0.name < $1.name }) {
                guard let addEnd = additions[addition.name],
                      let element = addition.parameters.first?.typeText else { continue }
                for removal in removalList.sorted(by: { $0.name < $1.name }) {
                    guard removals[removal.name] == addEnd else { continue }
                    // One law per (carrier, end, element) — `append`/`removeLast` and
                    // `append`/`popLast` state the same thing twice otherwise.
                    let key = "\(carrier)|\(addEnd.rawValue)|\(element)"
                    guard seen.insert(key).inserted else { continue }
                    let returnType = removal.returnTypeText ?? ""
                    result.append(EndedAccessShape(
                        typeName: carrier,
                        addition: addition,
                        removal: removal,
                        end: addEnd,
                        elementTypeText: element,
                        removalIsOptional: returnType.hasSuffix("?")
                            || returnType.hasPrefix("Optional<")
                    ))
                }
            }
        }
        return result
    }

    /// Group admissible members by carrier, generics stripped.
    private static func index(
        _ summaries: [FunctionSummary],
        admitting isAdmissible: (FunctionSummary) -> Bool
    ) -> [String: [FunctionSummary]] {
        var result: [String: [FunctionSummary]] = [:]
        for summary in summaries where isAdmissible(summary) {
            guard let carrier = summary.containingTypeName else { continue }
            result[stripGenerics(carrier), default: []].append(summary)
        }
        return result
    }

    /// A one-argument, positionally-named, mutating insertion.
    private static func isAdmissibleAddition(_ summary: FunctionSummary) -> Bool {
        guard isMutatingMember(summary), additions[summary.name] != nil else { return false }
        guard let parameter = summary.parameters.first, summary.parameters.count == 1 else {
            return false
        }
        return !parameter.isInout && parameter.label == nil
    }

    /// A nullary, positionally-named, mutating removal that returns the element.
    ///
    /// A removal taking an argument is `remove(at:)` — an indexed delete, not an end pop.
    private static func isAdmissibleRemoval(_ summary: FunctionSummary) -> Bool {
        guard isMutatingMember(summary), removals[summary.name] != nil else { return false }
        guard summary.parameters.isEmpty, let returnType = summary.returnTypeText else {
            return false
        }
        return returnType != "Void" && returnType != "()"
    }

    private static func isMutatingMember(_ summary: FunctionSummary) -> Bool {
        summary.isMutating && !summary.isStatic && !summary.isThrows && !summary.isAsync
    }

    static func stripGenerics(_ typeText: String) -> String {
        let trimmed = typeText.trimmingCharacters(in: .whitespaces)
        guard let angle = trimmed.firstIndex(of: "<") else { return trimmed }
        return String(trimmed[trimmed.startIndex..<angle])
    }
}
