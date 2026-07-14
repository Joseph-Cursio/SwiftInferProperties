import SwiftInferCore

/// The **comparator** law: a strict weak ordering, or `sorted(by:)` may crash.
///
/// The shape is `(T, T) -> Bool` with **both operands positional** — the thing you hand to
/// `sorted(by:)`:
///
///     static func precedes(_ lhs: FileSortKey, _ rhs: FileSortKey) -> Bool
///
/// This is the one law in the catalogue whose violation is not a wrong answer but a **trap**. Swift's
/// `sorted(by:)` documents that its predicate must be a strict weak ordering, and a comparator that
/// is not one can take the sort out of bounds. And no example test will tell you which triple broke
/// it — the failure is a property of a *relation over three elements*, which is precisely the kind of
/// claim an example cannot make and a generator can.
public enum ComparatorTemplate {

    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "comparator",
            appliesTo: Self.isComparator,
            signals: { summary in
                [
                    Signal(
                        kind: .comparatorSignature,
                        weight: 40,
                        detail: "`\(summary.name)` is `(T, T) -> Bool` with both operands positional "
                            + "— the shape `sorted(by:)` takes, and it owes a strict weak ordering"
                    )
                ]
            },
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "comparator|\(summary.containingTypeName ?? "")|\(summary.name)"
                )
            },
            carrier: { $0.containingTypeName },
            carrierType: { $0.parameters.first?.typeText },
            caveats: { _ in Self.makeCaveats() }
        )
    }

    /// `(T, T) -> Bool`, same operand type, **both positional**, and not an operator.
    ///
    /// The label test is what tells a comparator apart from a binary predicate of identical shape:
    /// `isImmediateChild(_ path: String, of parentPath: String)` is also `(String, String) -> Bool`,
    /// but its second operand carries a role. A comparator's operands are interchangeable in
    /// position, which is exactly why the ordering laws are stateable over them.
    ///
    /// **Operators are excluded.** `==` is `Equatable`'s, `<` is `Comparable`'s, and both already have
    /// executable law suites in the kit — proposing them here would re-report a law the reader can
    /// already run, and re-reporting another tool's finding teaches people the tools disagree.
    static func isComparator(_ summary: FunctionSummary) -> Bool {
        guard summary.returnTypeText == "Bool",
              summary.parameters.count == 2,
              !summary.isAsync,
              !summary.isThrows,
              !isOperator(summary.name) else {
            return false
        }

        let operands = summary.parameters
        guard operands[0].typeText == operands[1].typeText,
              !operands[0].isInout, !operands[1].isInout,
              operands[0].label == nil, operands[1].label == nil else {
            return false
        }
        return true
    }

    private static func isOperator(_ name: String) -> Bool {
        name.allSatisfy { !$0.isLetter && !$0.isNumber && $0 != "_" }
    }

    static func makeCaveats() -> [String] {
        [
            "STRICT WEAK ORDERING is the law, and it is not a stylistic nicety: `sorted(by:)` "
                + "documents that its predicate must be one, and a comparator that is not can take "
                + "the sort out of bounds. Check all four clauses — irreflexive (`!f(a, a)`), "
                + "asymmetric (`f(a, b)` implies `!f(b, a)`), transitive, and transitivity of "
                + "*incomparability* (if neither `f(a, b)` nor `f(b, a)`, and likewise for `b`/`c`, "
                + "then likewise for `a`/`c`).",
            "It rejects the two comparators people actually write. `{ $0.name <= $1.name }` is "
                + "REFLEXIVE, so it is not a strict ordering at all. `{ $0.a > $1.a || $0.b < $1.b }` "
                + "breaks TRANSITIVITY. Both fit on one line, both look right, and neither can be "
                + "caught by an example test — the failure is a claim about a *triple*.",
            "The last clause is the one hand-written tests never check, and the one a "
                + "folders-first-then-name comparator most often breaks: two items that tie on the "
                + "primary key must tie consistently, or incomparability is not transitive.",
            "Sorting with the comparator should also be IDEMPOTENT — sorting an already-sorted array "
                + "changes nothing — and should PRESERVE the partition key: if it orders folders "
                + "before files, no file may end up before a folder.",
            "A locale-sensitive comparison (`localizedCaseInsensitiveCompare`, `localizedCompare`) is "
                + "not a fixed ordering — it varies by locale, so the property must pin the locale or "
                + "it will pass on your machine and fail on someone else's."
        ]
    }
}
