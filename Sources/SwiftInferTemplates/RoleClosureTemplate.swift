import SwiftInferCore

/// The **role closure** law: an operation whose name carries a postcondition that is closed
/// under reapplication is the identity the second time. `f(f(x)) == f(x)`.
///
/// ## Why this is not `idempotence` with a longer verb list
///
/// `IdempotenceTemplate` reads the law off the *signature* — a unary `(T) -> T` whose name is in
/// a curated list — and its suggestions carry the catalog's standard warning that a correct
/// implementation can fail it. Nothing backs the claim but the verb.
///
/// Here the claim is backed by a postcondition the catalogue already states. `clamped(to:)` owes
/// *"the result lies within the given bounds"*; a value already within them is returned
/// unchanged; so clamping twice equals clamping once. The law is still only as good as the
/// assumption that the name means what it usually means — **it is not entailment, and
/// `role-postcondition` is deliberately absent from `Refutability.roleEntailedTemplates` for
/// exactly this reason** — but it rests on a stated guarantee rather than on a signature shape.
///
/// ## Closure is a second fact about the role, and assuming it would be the worst kind of wrong
///
/// A postcondition does not imply closure. `escaped` satisfies *"contains no unescaped
/// occurrence"* on every pass while changing the value every time — `\` to `\\` to `\\\\`. A
/// template that derived closure from the postcondition would state a false law about correct
/// code on the very first role a reader would try it on. ``RolePostcondition/isClosedUnderReapplication``
/// is therefore its own judgement, per role.
///
/// ## Measured before it was built
///
/// `S3ShapeCensusMeasuredTests`, 32 369 functions across 20 corpora:
///
/// | shape | raw | through its gate |
/// |---|---:|---:|
/// | parameterised idempotence `(T, P…) -> T` | 1 602 | **6** |
/// | removal verb over `String` | 16 | 16 |
/// | **closed role** | — | **25** |
/// | *of which `idempotence` already reaches* | — | **1** |
///
/// The obvious build was the 1 602, and through the gate that would actually fire it is six —
/// the population is large precisely because it is ungated, and consists of query builders whose
/// idempotence is probably false (`matching(x).matching(x)` plausibly ANDs twice). **24 of the
/// 25 closed-role sites are unreachable by `idempotence` today**, which is what makes this a gap
/// rather than a competitor.
///
/// ## What it does not do
///
/// It states the law; it does not emit a stub. An accepted suggestion takes the existing "no
/// stub writeout available for this template" path. The roles that hold an argument fixed —
/// `clamped(to:)`, `sorted(by:)` — need an emitter that can bind that argument across a nested
/// call, which `StubApplicationArity` newly makes expressible and which is its own slice. Same
/// posture as `guard-domain` (#443).
public enum RoleClosureTemplate {

    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "role-closure",
            appliesTo: { Self.role(of: $0) != nil },
            signals: Self.signals(for:),
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "role-closure|"
                        + IdempotenceTemplate.canonicalSignature(of: summary)
                )
            },
            carrier: { $0.containingTypeName },
            carrierType: { Self.transformedType(of: $0) },
            caveats: { Self.caveats(for: $0) }
        )
    }

    /// The type the law quantifies over: the first argument for a free or static function, else
    /// the receiver. The same choice `role-postcondition` makes, for the same reason.
    static func transformedType(of summary: FunctionSummary) -> String? {
        if summary.isStatic || summary.containingTypeName == nil {
            return summary.parameters.first?.typeText
        }
        return summary.containingTypeName
    }

    /// The closed role this declaration carries, or `nil`.
    ///
    /// Three gates beyond the role itself:
    ///
    /// - **The result must compose with the input.** `f(f(x))` has to type-check, so the return
    ///   type must be the transformed type. A `sorted` returning a *different* type is some
    ///   other operation wearing the name.
    /// - **`idempotence` must not already reach it.** Where both fire the reader gets one law
    ///   twice. Measured at exactly 1 site of 25, so this costs almost nothing and keeps the
    ///   catalog's output free of a duplicate that would be indistinguishable from coverage.
    /// - **No `async`, no `throws`, no `mutating`** — the law is about a returned value, on the
    ///   same grounds every algebraic template excludes them.
    public static func role(of summary: FunctionSummary) -> RolePostcondition? {
        guard let returnType = summary.returnTypeText,
              returnType != "Void", returnType != "()",
              !summary.isAsync, !summary.isThrows, !summary.isMutating,
              let role = RolePostcondition.matches(
                  name: summary.name,
                  parameterLabels: summary.parameters.map(\.label)
              ),
              role.isClosedUnderReapplication,
              Self.composes(summary, returning: returnType),
              !Self.alreadyReachedByIdempotence(summary, returning: returnType)
        else { return nil }
        return role
    }

    /// Whether `f(f(x))` type-checks: the return type is the type being transformed.
    static func composes(_ summary: FunctionSummary, returning returnType: String) -> Bool {
        let returned = Self.bare(returnType)
        if returned == "Self" { return !summary.isStatic }
        guard let transformed = Self.transformedType(of: summary) else { return false }
        return returned == Self.bare(transformed)
    }

    /// `IdempotenceTemplate` fires on a unary `(T) -> T` carrying a curated verb.
    static func alreadyReachedByIdempotence(_ summary: FunctionSummary, returning returnType: String) -> Bool {
        guard summary.parameters.count == 1,
              Self.bare(summary.parameters[0].typeText) == Self.bare(returnType)
        else { return false }
        return IdempotenceTemplate.curatedVerbs.contains(summary.name)
    }

    static func bare(_ text: String) -> String {
        var out = text.trimmingCharacters(in: .whitespaces)
        while out.hasSuffix("?") || out.hasSuffix("!") { out.removeLast() }
        return out
    }

    static func signals(for summary: FunctionSummary) -> [Signal] {
        guard let role = Self.role(of: summary) else { return [] }
        return [
            Signal(
                kind: .exactNameMatch,
                weight: 30,
                detail: "Curated role verb: '\(summary.name)' owes \(role.law) — and that "
                    + "guarantee is closed, so applying it again changes nothing"
            ),
            Signal(
                kind: .typeSymmetrySignature,
                weight: 20,
                detail: "Closure shape: \(summary.name)(\(summary.name)(x)) == \(summary.name)(x), "
                    + "backed by the catalogue's postcondition rather than by the signature alone"
            )
        ]
    }

    static func caveats(for summary: FunctionSummary) -> [String] {
        guard let role = Self.role(of: summary) else { return [] }
        var caveats = [
            "THE LAW RESTS ON THE ROLE, NOT THE CODE: '\(summary.name)' is taken to owe "
                + "\(role.law), and that guarantee is taken to be closed under reapplication. "
                + "Both come from the name. This is stronger than a signature-shaped idempotence "
                + "claim and it is NOT entailment — a function borrowing the verb for something "
                + "else owes neither.",
            "IT IS THE CHECKABLE HALF OF A WIDER LAW. The full statement is that the operation "
                + "is the identity on any input already satisfying its postcondition; this "
                + "checks it only where the input is itself a result, because those are the "
                + "values a generator can reach without being taught the predicate."
        ]
        if summary.parameters.isEmpty == false {
            caveats.append(
                "THE HELD ARGUMENT MUST BE THE SAME IN BOTH CALLS. '\(summary.name)' takes a "
                    + "parameter, and the law is about reapplying the SAME operation — "
                    + "`clamped(to: a).clamped(to: b)` claims nothing. A caller-supplied "
                    + "comparator or bound must also be deterministic."
            )
        }
        return caveats
    }
}
