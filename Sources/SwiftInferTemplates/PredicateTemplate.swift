import SwiftInferCore

/// The **predicate** role — and the one role in this catalogue that carries **no free law**.
///
/// This is worth stating plainly rather than papering over, because it is the honest boundary of the
/// whole "laws come from role" idea, and a reader who does not know where that boundary lies will
/// over-trust the tool.
///
/// A **comparator** owes you a strict weak ordering. A **partition** owes you that its parts tile the
/// whole. A **codec** owes you a round trip. Those laws are *free*: they follow from the role alone,
/// and a tool can state them without knowing a thing about your domain.
///
/// A bare predicate owes you almost nothing. What universal claim follows from
/// `isValidFolderName(_:) -> Bool` merely by virtue of returning a `Bool`? None. Whether a name is
/// valid is *domain knowledge*, and no amount of signature analysis will recover it. **A tool that
/// invented a law here would be making one up.**
///
/// So this template proposes the one law that *is* free — **totality** — and is explicit that the
/// interesting law is a hole only the author can fill. That is a smaller claim than the other
/// templates make, and saying so is the point: the alternative is a confident-sounding suggestion
/// with nothing behind it, which is the exact failure mode (`f(x) == f(x)`) this catalogue exists to
/// replace. A tool that says "I have found the shape; the law is yours to state" is more useful than
/// one that manufactures a tautology and calls it a property.
public enum PredicateTemplate {

    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "predicate",
            appliesTo: Self.isPredicate,
            // Weight 20 — the lowest in the catalogue, and deliberately below the default tier, so a
            // predicate suggestion is HIDDEN unless the reader asks for `--include-possible`.
            //
            // This is not modesty, it is arithmetic. Every `Bool`-returning function in a codebase is
            // a predicate by shape — `isEnabled()`, `canEdit()`, `hasPermission()` — and the law this
            // template can state over them is the weakest one it has. Surfaced by default, it would
            // bury the partition and comparator findings under a list of everything that returns a
            // `Bool`, and a category that fires on everything is a category people switch off. The
            // Possible tier is exactly the right home: available when you go looking, silent when you
            // are not.
            signals: { summary in
                [
                    Signal(
                        kind: .predicateSignature,
                        weight: 20,
                        detail: "`\(summary.name)` classifies its inputs — it must be TOTAL over "
                            + "them, and it must agree with a reference definition only you can state"
                    )
                ]
            },
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "predicate|\(summary.containingTypeName ?? "")|\(summary.name)"
                )
            },
            carrier: { $0.containingTypeName },
            carrierType: { $0.parameters.first?.typeText },
            caveats: { _ in Self.makeCaveats() }
        )
    }

    /// Returns `Bool`, takes at least one argument, and is **not** a comparator — `ComparatorTemplate`
    /// owns `(T, T) -> Bool` with positional operands, and that role has a far stronger law.
    ///
    /// Operators are excluded: `==` is `Equatable`'s law, and the kit already runs it.
    static func isPredicate(_ summary: FunctionSummary) -> Bool {
        guard summary.returnTypeText == "Bool",
              !summary.parameters.isEmpty,
              !summary.isAsync,
              !summary.isThrows,
              !summary.name.allSatisfy({ !$0.isLetter && !$0.isNumber && $0 != "_" }),
              !ComparatorTemplate.isComparator(summary) else {
            return false
        }
        return true
    }

    static func makeCaveats() -> [String] {
        [
            "TOTALITY is the only law that follows from the shape, and it is a real one: the "
                + "predicate must return `true` or `false` for *every* input its type admits — never "
                + "trap, never crash. Generate the awkward ones: the empty string, a string that is "
                + "all separators, a value at the type's boundary.",
            "THE INTERESTING LAW IS NOT FREE, and no tool can invent it for you. A comparator owes a "
                + "strict weak ordering and a partition owes a tiling *by virtue of being one*; a "
                + "predicate owes only what its DOMAIN says it owes. State that reference definition "
                + "in one English sentence, then encode it — that sentence is the property.",
            "The reference definition is where the bugs are, because the bug is almost always that "
                + "the CODE says something subtly different from the SENTENCE. \"Two addresses name "
                + "the same mailbox\" is a sentence; an implementation that case-folds one side and "
                + "not the other agrees with it on every example anyone thought to write down, and "
                + "disagrees on the first generated pair that differs only in case. Write the "
                + "sentence, encode THAT, and let the generator find where the code drifted from it.",
            "Bias the generator toward inputs where structure COLLIDES — a small alphabet, repeated "
                + "components, values equal under one notion and distinct under another. A predicate "
                + "that has quietly confused two notions agrees with the right answer everywhere the "
                + "two coincide, so a generator drawing from a wide alphabet will almost never catch "
                + "it. The counterexample lives in the collisions, and you have to generate them on "
                + "purpose.",
            "If you cannot state the reference definition in one true English sentence, that is not a "
                + "reason to skip the property — it is a finding about the function."
        ]
    }
}
