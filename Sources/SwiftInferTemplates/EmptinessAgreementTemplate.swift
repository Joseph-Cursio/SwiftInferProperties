import SwiftInferCore

/// A `Bool` member and a count on one type, named for the same thing — `hasIssues` and
/// `totalIssueCount`, `isEmpty` and `count` — and the law that ties them: the predicate holds
/// exactly when the count is positive (or, for an emptiness predicate, exactly when it is zero).
///
/// ## Why this template exists
///
/// Measured on SwiftLintRuleStudioCore's `CompatibilityReport`, whose two computed properties are
///
/// ```swift
/// var hasIssues: Bool {
///     !deprecatedRules.isEmpty || !removedRules.isEmpty || !renamedRules.isEmpty
/// }
/// var totalIssueCount: Int {
///     deprecatedRules.count + removedRules.count + renamedRules.count
/// }
/// ```
///
/// Both were seeded. `discover` proposed `measure-non-negativity` for the count and nothing for
/// the predicate, and a mutation run left both `||` → `&&` mutants in `hasIssues` unreached by any
/// test. Neither law alone can see them: totality holds of any `Bool`, and a count is non-negative
/// whatever the predicate says. **Together they state what the two members owe each other**, and
/// either mutant breaks it on the first report with exactly one kind of issue.
///
/// ## A conjecture, read from names
///
/// The pairing is a naming convention, not an entailment, so the law is a conjecture: a `hasX`
/// that means "has a *pending* X" while the count counts all of them is correct code that fails
/// it. It is scored Likely all the same, because what keeps precision up is the pairing rule —
/// the count must name the predicate's subject
/// (`hasIssues` pairs with `totalIssueCount`, not with `retryCount`) — and that both members
/// belong to one type and take no arguments, so the law is a statement about one value.
public enum EmptinessAgreementTemplate {

    public static let templateName = "emptiness-agreement"

    public static func suggest(for pair: EmptinessAgreementPair) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: pair)
    }

    public static func makeConstraint() -> Constraint<EmptinessAgreementPair> {
        Constraint<EmptinessAgreementPair>(
            templateName: "emptiness-agreement",
            appliesTo: { _ in true },   // the pairing layer already gated
            signals: Self.signals(for:),
            evidence: { [$0.predicate.inferenceEvidence, $0.measure.inferenceEvidence] },
            identity: Self.makeIdentity(for:),
            carrier: { $0.predicate.containingTypeName },
            carrierType: { $0.predicate.containingTypeName },
            caveats: { Self.makeCaveats(for: $0) }
        )
    }

    /// Likely-tier by construction (30 + 15 = 45), as `dual-style-consistency` is and for its
    /// reason: the pairing requires both members on one type, named by one convention, so a false
    /// pair needs a developer to use the convention for something else. Possible would hide it from
    /// every default run — and the seed focus promotes only role-entailed laws, which this is not —
    /// so on SwiftLintRuleStudioCore it reached no reader at all without `--include-possible`.
    static func signals(for pair: EmptinessAgreementPair) -> [Signal] {
        let type = pair.predicate.containingTypeName ?? "?"
        return [
            Signal(
                kind: .typeSymmetrySignature,
                weight: 30,
                detail: "Predicate and count on one type: \(type).\(pair.predicate.name) -> Bool, "
                    + "\(type).\(pair.measure.name) -> \(pair.measure.returnTypeText ?? "Int")"
            ),
            Signal(
                kind: .exactNameMatch,
                weight: 15,
                detail: "Named for the same thing: '\(pair.predicate.name)' / '\(pair.measure.name)' — "
                    + "so `\(lawText(for: pair))`"
            )
        ]
    }

    /// The law as a reader would write it.
    public static func lawText(for pair: EmptinessAgreementPair) -> String {
        "\(pair.predicate.name) == (\(pair.measure.name) \(pair.holdsWhenPositive ? "> 0" : "== 0"))"
    }

    static func makeCaveats(for pair: EmptinessAgreementPair) -> [String] {
        [
            "THE LAW IS `\(lawText(for: pair))` — the predicate and the count describe one fact. It "
                + "is refutable exactly where the two are computed separately: a `||` written as "
                + "`&&`, a section the count includes and the predicate forgets, an off-by-one in "
                + "the comparison.",
            "A CONJECTURE read from the names. A predicate that means something narrower than its "
                + "count — `hasUnreadIssues` beside a count of all issues — is correct code that "
                + "fails this; confirm the two are meant to agree before encoding it."
        ]
    }

    private static func makeIdentity(for pair: EmptinessAgreementPair) -> SuggestionIdentity {
        let halves = [
            IdempotenceTemplate.canonicalSignature(of: pair.predicate),
            IdempotenceTemplate.canonicalSignature(of: pair.measure)
        ]
        return SuggestionIdentity(canonicalInput: "\(templateName)|" + halves.joined(separator: "|"))
    }
}

/// A `Bool` member and a count on one type that the naming convention says agree.
public struct EmptinessAgreementPair: Sendable, Equatable {
    public let predicate: FunctionSummary
    public let measure: FunctionSummary
    /// `true` for `predicate == (measure > 0)`, `false` for `predicate == (measure == 0)`.
    public let holdsWhenPositive: Bool

    public init(predicate: FunctionSummary, measure: FunctionSummary, holdsWhenPositive: Bool) {
        self.predicate = predicate
        self.measure = measure
        self.holdsWhenPositive = holdsWhenPositive
    }
}

/// Finds `EmptinessAgreementPair`s among a scan's summaries.
public enum EmptinessAgreementPairing {

    /// Every pair on one type: an argument-free `Bool` member and an argument-free signed-integer
    /// measure (`MeasureTemplate.isMeasure`) whose names agree — `has<Thing>` with a count naming
    /// the thing, `isEmpty` / `isNotEmpty` with `count`.
    public static func candidates(in summaries: [FunctionSummary]) -> [EmptinessAgreementPair] {
        let members = summaries.filter(isArgumentFreeMember)
        let byType = Dictionary(grouping: members) { $0.containingTypeName ?? "" }
        var pairs: [EmptinessAgreementPair] = []
        for (type, typeMembers) in byType.sorted(by: { $0.key < $1.key }) where !type.isEmpty {
            let predicates = typeMembers.filter { $0.returnTypeText == "Bool" }
            let measures = typeMembers.filter(MeasureTemplate.isMeasure)
            for predicate in predicates {
                for measure in measures {
                    if let positive = polarity(predicate: predicate.name, measure: measure.name) {
                        pairs.append(EmptinessAgreementPair(
                            predicate: predicate, measure: measure, holdsWhenPositive: positive
                        ))
                    }
                }
            }
        }
        return pairs
    }

    /// `true` when the predicate holds for a positive count, `false` when it holds for zero, `nil`
    /// when the names do not pair.
    public static func polarity(predicate: String, measure: String) -> Bool? {
        switch predicate {
        case "isEmpty":
            return measure == "count" ? false : nil

        case "isNotEmpty":
            return measure == "count" ? true : nil

        default:
            guard let subject = hasSubject(predicate) else { return nil }
            return measure.lowercased().contains(subject.lowercased()) ? true : nil
        }
    }

    /// The thing a `has<Thing>` predicate is about, singular: `hasIssues` → `Issue`. `nil` for any
    /// other name, and for a bare `has`.
    static func hasSubject(_ name: String) -> String? {
        guard name.hasPrefix("has"), name.count > 3 else { return nil }
        let subject = name.dropFirst(3)
        guard let first = subject.first, first.isUppercase else { return nil }
        return singular(String(subject))
    }

    /// English singular for the plural shapes member names use: `Retries` → `Retry`,
    /// `Matches` → `Match`, `Issues` → `Issue`. A word that is already singular is unchanged.
    static func singular(_ word: String) -> String {
        if word.hasSuffix("ies"), word.count > 3 { return String(word.dropLast(3)) + "y" }
        if ["sses", "xes", "ches", "shes"].contains(where: word.hasSuffix) { return String(word.dropLast(2)) }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), word.count > 1 { return String(word.dropLast()) }
        return word
    }

    private static func isArgumentFreeMember(_ summary: FunctionSummary) -> Bool {
        summary.containingTypeName != nil && !summary.isStatic && summary.parameters.isEmpty
            && !summary.isMutating && !summary.isAsync && !summary.isThrows
    }
}

extension TemplateRegistry {

    /// A predicate and a count on one type that the names say agree — `EmptinessAgreementTemplate`.
    /// Lives here rather than in `TemplateRegistry+Collection`, which is at its length cap.
    static func collectEmptinessAgreementSuggestions(
        summaries: [FunctionSummary],
        into collector: inout SuggestionCollector
    ) {
        for pair in EmptinessAgreementPairing.candidates(in: summaries) {
            if let suggestion = EmptinessAgreementTemplate.suggest(for: pair) {
                collector.record(suggestion, generatorType: pair.predicate.containingTypeName)
            }
        }
    }
}
