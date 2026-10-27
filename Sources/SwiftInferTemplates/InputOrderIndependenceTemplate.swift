import Foundation
import SwiftInferCore

/// The **input-order-independence** law: a function that maps a `Dictionary` to an array and sorts
/// it returns the same order whatever order its input array arrives in (SwiftInferProperties#647,
/// law 2).
///
/// ```swift
/// func ruleHotspots(_ repos: [FleetRepo]) -> [RuleHotspot] {
///     var totals: [String: (violations: Int, repos: Int)] = [:]
///     … // fold every repo's violations into `totals`
///     return totals
///         .map { RuleHotspot(rule: $0.key, violations: $0.value.violations, repoCount: $0.value.repos) }
///         .sorted { $0.violations > $1.violations }
/// }
/// ```
///
/// is proposed as `ruleHotspots(repos).map(\.rule) == ruleHotspots(repos.reversed()).map(\.rule)`.
///
/// ## Why it can fail today, unlike `sorted-output`
///
/// `sorted-output` restates the comparator, so the code satisfies it by construction. This law is
/// about what the comparator does NOT decide. A dictionary iterates in hash order, Swift seeds that
/// order per table, and `sorted(by:)` keeps elements it calls tied in the order it met them — so
/// two rules with equal `violations` come out in an order no input decides. A comparator that ends
/// on the dictionary's own key (`ImpactReport.from`'s `ruleID`) closes that, and this law then
/// catches the edit that drops it.
///
/// ## Why it compares the key, not the elements
///
/// The keys are distinct, so their sequence IS the order, and a key is `Hashable` — the stub needs
/// no `Equatable` on the element, which the motivating defect's element (`RuleHotspot`) lacks.
///
/// ## Measured detection, and why a reversal rather than a second call
///
/// On a standalone copy of the leaking shape (2026-10-22): calling `f(xs)` twice disagreed on 1 of
/// 100 inputs — the freed table's address is reused, so the second table gets the same seed —
/// while `f(xs.reversed())` disagreed on 29–76 of 100 whenever the input drew five or more keys,
/// and the fixed comparator disagreed on 0. Inserting in another order is what moves the ties.
public enum InputOrderIndependenceTemplate {

    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "input-order-independence",
            appliesTo: Self.isPermutable,
            signals: Self.signals(for:),
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "input-order-independence|"
                        + IdempotenceTemplate.canonicalSignature(of: summary)
                )
            },
            carrier: { $0.containingTypeName },
            carrierType: { summary in
                permutedParameter(of: summary).map { summary.parameters[$0].typeText }
                    ?? summary.containingTypeName
            },
            caveats: { summary in Self.makeCaveats(for: summary) },
            // The same `SortedOutput` `sorted-output` carries; the writer reads its dictionary key.
            match: { $0.bodySignals.sortedOutput.map(TemplateMatch.sortedOutput) }
        )
    }

    /// A sorted result mapped from a dictionary whose key an element holds, and an array parameter
    /// to permute. `throws`, `async` and `mutating` are excluded as `sorted-output` excludes them.
    static func isPermutable(_ summary: FunctionSummary) -> Bool {
        summary.bodySignals.sortedOutput?.dictionaryKeyMember != nil
            && permutedParameter(of: summary) != nil
            && !summary.isMutating
            && !summary.isAsync
            && !summary.isThrows
    }

    /// The first parameter whose type is an array, which the law reverses.
    public static func permutedParameter(of summary: FunctionSummary) -> Int? {
        summary.parameters.firstIndex { !$0.isInout && isArrayType($0.typeText) }
    }

    /// `[T]` or `Array<T>`, not `[K: V]`.
    public static func isArrayType(_ text: String) -> Bool {
        let type = text.trimmingCharacters(in: .whitespaces)
        if type.hasPrefix("Array<") { return type.hasSuffix(">") }
        guard type.hasPrefix("["), type.hasSuffix("]") else { return false }
        var depth = 0
        for character in type.dropFirst().dropLast() {
            switch character {
            case "[", "(", "<": depth += 1
            case "]", ")", ">": depth -= 1
            case ":" where depth == 0: return false
            default: break
            }
        }
        return true
    }

    static func signals(for summary: FunctionSummary) -> [Signal] {
        guard let ordering = summary.bodySignals.sortedOutput,
              let key = ordering.dictionaryKeyMember else {
            return []
        }
        let subject = ordering.member.map { "\(summary.name)(…).\($0)" } ?? "\(summary.name)(…)"
        let reach = ordering.comparatorReachesDictionaryKey
            ? "the comparator reaches the key, so this catches an edit that drops it"
            : "the comparator never reaches `\(key)`, so elements tied on "
                + "\(SortedOutputTemplate.describe(ordering.keys)) keep the dictionary's hash order"
        return [
            Signal(
                kind: .typeSymmetrySignature,
                weight: 40,
                detail: "the body sorts a dictionary's entries: \(subject) holds its key in `\(key)`; \(reach)"
            )
        ]
    }

    static func makeCaveats(for summary: FunctionSummary) -> [String] {
        var caveats = [
            "IT COMPARES THE ORDER OF THE DICTIONARY'S KEYS, NOT THE ELEMENTS. The keys are distinct, "
                + "so their sequence is the whole order; a member that depends on input order — a "
                + "group kept in arrival order — is not checked.",
            "IT CAN FAIL ON CORRECT CODE IN ONE WAY: a sort key computed from the ORDER of the input, "
                + "such as the first or last occurrence in a group. Reversing the input then changes "
                + "the key, and the order with it, as intended.",
            "A FAILURE NEEDS TWO ELEMENTS THE COMPARATOR CALLS TIED, so a generator that rarely "
                + "draws equal sort keys rarely fails. Narrow the alphabet of whatever the sort keys "
                + "are counted or summed from."
        ]
        if summary.bodySignals.sortedOutput?.comparatorReachesDictionaryKey == true {
            caveats.insert(
                "THE COMPARATOR ALREADY REACHES THE KEY, so this holds of today's code and catches "
                    + "an EDIT that drops it — the same edit `sorted-output` catches only when the "
                    + "trials draw a tie.",
                at: 0
            )
        }
        return caveats
    }
}

extension TemplateRegistry {

    /// `InputOrderIndependenceTemplate`, reached from `collectValueLawSuggestions`.
    static func collectInputOrderIndependenceSuggestions(
        summaries: [FunctionSummary],
        into collector: inout SuggestionCollector
    ) {
        for summary in summaries {
            if let suggestion = InputOrderIndependenceTemplate.suggest(for: summary) {
                collector.record(
                    suggestion,
                    generatorType: InputOrderIndependenceTemplate.permutedParameter(of: summary)
                        .map { summary.parameters[$0].typeText } ?? summary.containingTypeName
                )
            }
        }
    }
}
