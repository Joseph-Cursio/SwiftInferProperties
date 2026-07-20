import SwiftInferCore

/// The **equivalence-relation** law — the `==` analog of the comparator's strict
/// weak ordering.
///
/// A method named like an equality over two operands of the same type owes three
/// laws by virtue of *being* an equality, none of which an example test can make:
///
///     func isEqual(to other: Self) -> Bool          // instance: self ~ other
///     static func areEqual(_ a: T, _ b: T) -> Bool  // binary
///
///   - **reflexivity**: `a ~ a` for every `a`.
///   - **symmetry**: `a ~ b` iff `b ~ a`.
///   - **transitivity**: `a ~ b` and `b ~ c` imply `a ~ c`.
///
/// Reflexivity is a claim over every value, symmetry over every *pair*, and
/// transitivity over every *triple* — exactly the shapes a hand-written example
/// misses and a generator catches (the same argument the comparator template
/// makes for the incomparability clause).
///
/// **Name-gated.** Every `(T, T) -> Bool` is an equivalence by shape, so gating
/// on the shape alone would fire on every binary predicate — the Daikon flood.
/// The equality verb (`equals` / `isEqual` / `isEquivalent` / `isEqualSet` / …)
/// is the load-bearing signal, so only a method that *claims* to be an equality
/// is asked to prove it. Operators are excluded: `==` is `Equatable`'s law and
/// the kit already runs it — re-reporting it here would teach the reader the
/// tools disagree.
///
/// **Operands must share a type.** `a ~ b` is only symmetric when `a` and `b`
/// are interchangeable, so `BitSet.isEqualSet(to: Range<Int>)` — a cross-type
/// "does this set equal this range" — is correctly NOT an equivalence (you
/// cannot swap the operands). That is the honest boundary the swift-syntax
/// `isEqualSet(to:)` cross-type overload sits outside of.
public enum EquivalenceRelationTemplate {

    /// Case-insensitive equality verbs. The bare method name (`equals`,
    /// `isEqual`) is matched, not the argument label (`to:`), because an
    /// equality's operands are interchangeable regardless of how the second is
    /// labelled — the very property that separates it from a role-bearing
    /// predicate.
    public static let equalityVerbs: Set<String> = [
        "equals",
        "isequal",
        "isequalto",
        "isequivalent",
        "isequivalentto",
        "issame",
        "issameas",
        "issamevalue",
        "isequalset",
        "isidentical",
        "isidenticalto",
        // Binary (`(T, T) -> Bool`) naming — a static/free equality reads
        // `areEqual(_:_:)` rather than `isEqual(to:)`.
        "areequal",
        "areequivalent",
        "aresame"
    ]

    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "equivalence-relation",
            appliesTo: Self.isEquivalenceRelation,
            signals: { summary in
                [
                    Signal(
                        kind: .equivalenceRelationSignature,
                        weight: 40,
                        detail: "`\(summary.name)` is a named equality over two operands of the "
                            + "same type — it owes reflexivity, symmetry, and transitivity"
                    )
                ]
            },
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "equivalence-relation|\(summary.containingTypeName ?? "")|"
                        + summary.name
                )
            },
            carrier: { $0.containingTypeName },
            carrierType: { operandType(of: $0) },
            caveats: { _ in Self.makeCaveats() },
            generators: Self.makeGenerators(for:)
        )
    }

    /// A named equality over two same-type operands: either an instance
    /// `func equals(to other: Self) -> Bool` (receiver + one same-type arg) or a
    /// free/static `func areEqual(_ a: T, _ b: T) -> Bool` (two same-type args).
    /// Not an operator, not async/throwing.
    static func isEquivalenceRelation(_ summary: FunctionSummary) -> Bool {
        guard summary.returnTypeText == "Bool",
              !summary.isAsync,
              !summary.isThrows,
              !isOperator(summary.name),
              equalityVerbs.contains(summary.name.lowercased()) else {
            return false
        }
        return isInstanceForm(summary) || isBinaryForm(summary)
    }

    /// Instance `(self, T) -> Bool` where the single argument's type is the
    /// carrier (`Self` or the containing type) — so the receiver and the
    /// argument are interchangeable operands.
    private static func isInstanceForm(_ summary: FunctionSummary) -> Bool {
        guard !summary.isStatic,
              let carrier = summary.containingTypeName,
              summary.parameters.count == 1,
              let parameter = summary.parameters.first,
              !parameter.isInout else {
            return false
        }
        let argumentType = parameter.typeText
        return argumentType == carrier || argumentType == "Self"
    }

    /// Free / static `(T, T) -> Bool` with both operands the same type.
    private static func isBinaryForm(_ summary: FunctionSummary) -> Bool {
        guard summary.parameters.count == 2 else { return false }
        let operands = summary.parameters
        return operands[0].typeText == operands[1].typeText
            && !operands[0].isInout && !operands[1].isInout
    }

    /// The operand type — the argument for the instance form, the first
    /// parameter for the binary form. Used for the generator recipe.
    static func operandType(of summary: FunctionSummary) -> String? {
        summary.parameters.first?.typeText
    }

    private static func isOperator(_ name: String) -> Bool {
        name.allSatisfy { !$0.isLetter && !$0.isNumber && $0 != "_" }
    }

    /// Only `String` operands get a recipe — equality bugs hide in COLLISIONS
    /// (a comparison that case-folds one side agrees with the reference notion
    /// everywhere the two coincide and diverges on the first pair equal under
    /// one and distinct under the other), exactly the predicate/comparator
    /// argument. A struct operand needs a generator this template cannot
    /// synthesize and should not pretend to.
    static func makeGenerators(for summary: FunctionSummary) -> [GeneratorRecipe] {
        summary.parameters
            .filter { $0.typeText.trimmingCharacters(in: .whitespaces) == "String" }
            .map { CollisionBias.collidingString(subject: $0.internalName) }
    }

    static func makeCaveats() -> [String] {
        [
            "REFLEXIVITY, SYMMETRY, TRANSITIVITY are the three laws, and none is catchable by an "
                + "example: reflexivity quantifies over every value (`a ~ a`), symmetry over every "
                + "pair (`a ~ b` iff `b ~ a`), transitivity over every triple (`a ~ b` and `b ~ c` "
                + "imply `a ~ c`). Generate pairs and triples — an equality that is subtly "
                + "asymmetric or non-transitive passes every hand-written case and fails the first "
                + "generated one.",
            "TRANSITIVITY is the clause that breaks in practice, and the one tests never check. A "
                + "\"fuzzy\" or tolerance-based equality (`abs(a - b) < epsilon`, "
                + "case-and-whitespace-folded string compare) is reflexive and symmetric but NOT "
                + "transitive: `a ~ b` and `b ~ c` can hold while `a ~ c` fails by accumulated "
                + "slack. If your notion has a tolerance, this law is probably false — that is a "
                + "finding, not a nuisance.",
            "WHAT counts as equal is DOMAIN knowledge the tool cannot invent — state the reference "
                + "notion in one English sentence (\"two addresses name the same mailbox\") and "
                + "encode THAT. Bias the generator toward COLLISIONS: a small alphabet, values equal "
                + "under one notion and distinct under another. An equality that has quietly "
                + "confused two notions agrees with the right answer everywhere they coincide, so a "
                + "wide-alphabet generator almost never catches it.",
            "If the type is also `Equatable` / `Hashable`, this relation must AGREE with `==` and be "
                + "CONSISTENT with `hashValue`: two values this method calls equal must have the same "
                + "hash, or a `Set` / `Dictionary` built on them will silently lose elements. A "
                + "hand-rolled equality that disagrees with the synthesized `==` is a latent bug."
        ]
    }
}
