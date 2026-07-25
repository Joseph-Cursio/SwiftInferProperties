import SwiftInferCore

/// The **override-precedence** law: a function given an explicit value returns
/// *that* value, unchanged.
///
///     resolveRules(cliCategories:cliRuleIdentifiers:) ([PatternCategory]?, [RuleIdentifier]?) -> [RuleIdentifier]?
///     ⟹  cliRuleIdentifiers != nil  implies  result == cliRuleIdentifiers
///
/// ## The gap this closes
///
/// From the SwiftProjectLint road test. `resolveRules` reached `discover` and was
/// handed `f(x) == f(x)` — the tautology — because no template matched its shape.
/// Its docstring names the law in passing ("given optional CLI **overrides**"),
/// and the docstring surface duly surfaced it; but a contract this structurally
/// legible should not need prose to be found.
///
/// **The signal is the type match, not the name.** A parameter whose type is
/// *exactly* the return type is unusual and load-bearing: the function can hand
/// that parameter straight back, and an override is the overwhelmingly common
/// reason to write that signature. The name then confirms the reading.
///
/// ## Why this is refutable, and what it catches
///
/// The precedence lives in an early return, and early returns migrate. Move it
/// below the rest of the computation — an entirely natural-looking tidy-up when
/// the surrounding code grows — and the explicit value stops winning: it gets
/// merged, filtered by a category argument, or subtracted from. Nothing fails to
/// compile, every fixed-input test that passes an override *and* expects it back
/// still passes, and the escape hatch a user reaches for when a config file is
/// fighting them quietly stops working.
///
/// ## Why it is not role-entailed
///
/// Kept below the confidence cut on purpose. A function can legitimately take an
/// optional value of its own return type and **merge** rather than replace —
/// defaults-with-fallback, or an accumulate-into shape. Both are correct code
/// that this law rejects, so it is a name-conjecture in the sense
/// `Refutability` means: refutable, but a right implementation can fail it.
public enum OverridePrecedenceTemplate {

    /// Curated override nouns, matched case-insensitively against the parameter's
    /// label *and* its internal name. A parameter named for one of these asserts
    /// that the caller is *supplying the answer*, not contributing to it.
    ///
    /// Deliberately narrow. Broad nouns (`value`, `input`, `other`) name
    /// parameters that are combined far more often than they are obeyed, and a
    /// law that fires on those would cry wolf on ordinary merge functions.
    public static let curatedOverrideNouns: [String] = [
        "override", "overrides", "explicit", "forced", "cli",
        "requested", "preferred", "pinned"
    ]

    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "override-precedence",
            appliesTo: { overrideParameter(of: $0) != nil },
            signals: Self.signals(for:),
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "override-precedence|"
                        + IdempotenceTemplate.canonicalSignature(of: summary)
                )
            },
            carrier: { $0.containingTypeName },
            // The law quantifies over the override parameter's own type — that is
            // what a reader must generate to check it.
            carrierType: { overrideParameter(of: $0)?.typeText ?? $0.returnTypeText },
            caveats: { summary in makeCaveats(for: summary) }
        )
    }

    // MARK: - Shape gate

    /// The parameter this function is expected to hand straight back.
    ///
    /// Requires an **exact** type match with the return type, both optional. A
    /// looser match (`T` parameter, `T?` return) admits ordinary
    /// wrap-and-transform functions, where returning the argument unchanged is
    /// not owed at all.
    static func overrideParameter(of summary: FunctionSummary) -> Parameter? {
        guard !summary.isMutating,
              !summary.isAsync,
              !summary.isThrows,
              let returnType = summary.returnTypeText?.trimmingCharacters(in: .whitespaces),
              isOptional(returnType) else {
            return nil
        }
        return summary.parameters.first { parameter in
            !parameter.isInout
                && parameter.typeText.trimmingCharacters(in: .whitespaces) == returnType
                && hasOverrideNoun(parameter)
        }
    }

    static func isOptional(_ type: String) -> Bool {
        type.hasSuffix("?") && type.count > 1
    }

    static func hasOverrideNoun(_ parameter: Parameter) -> Bool {
        var names = [parameter.internalName]
        if let label = parameter.label { names.append(label) }
        return names.contains { name in
            let lowered = name.lowercased()
            return curatedOverrideNouns.contains { lowered.contains($0) }
        }
    }

    // MARK: - Scoring

    static func signals(for summary: FunctionSummary) -> [Signal] {
        guard let parameter = overrideParameter(of: summary),
              let returnType = summary.returnTypeText else {
            return []
        }
        let name = parameter.label ?? parameter.internalName
        return [
            Signal(
                kind: .typeSymmetrySignature,
                weight: 20,
                detail: "Override shape: `\(name)` has the return type exactly "
                    + "(\(returnType)), so the function can hand it straight back"
            ),
            Signal(
                kind: .exactNameMatch,
                weight: 15,
                detail: "Curated override noun in `\(name)` — the caller is SUPPLYING the "
                    + "answer, so a non-nil value owes being returned unchanged"
            )
        ]
    }

    static func makeCaveats(for summary: FunctionSummary) -> [String] {
        let name = overrideParameter(of: summary).map { $0.label ?? $0.internalName } ?? "the override"
        return [
            "THE LAW IS `\(name) != nil` implies `result == \(name)` — an explicit value is "
                + "returned unchanged, not merged, filtered or subtracted from. It is refutable "
                + "exactly where it matters: the precedence lives in an early return, and early "
                + "returns migrate.",
            "WHAT IT CATCHES is a tidy-up, not a typo. Move that early return below the rest of "
                + "the computation — natural enough as the surrounding code grows — and the "
                + "explicit value silently stops winning. Nothing fails to compile, and a fixed "
                + "test that passes an override and expects it back still passes if the other "
                + "arguments happen to be empty.",
            "GENERATE THE OTHER ARGUMENTS NON-EMPTY. This law passes vacuously when everything "
                + "else is nil or empty, because then merging and overriding agree. The "
                + "counterexample needs a populated configuration AND an override that "
                + "contradicts it — draw both from a small pool so they genuinely conflict.",
            "PRECEDENCE IS NAME-CONJECTURED, not shape-entailed. A function may legitimately "
                + "take an optional value of its own return type and MERGE it — "
                + "defaults-with-fallback, or an accumulate-into shape — which is correct code "
                + "that fails this law. Confirm the parameter is obeyed rather than combined.",
            "If two parameters could each override, the law is owed for each INDEPENDENTLY and "
                + "their relative precedence is a separate claim the signature does not state."
        ]
    }
}
