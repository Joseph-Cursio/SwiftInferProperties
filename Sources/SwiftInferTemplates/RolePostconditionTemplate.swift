import SwiftInferCore

/// The **role postcondition** law: a function whose name names an operation with a known
/// guarantee owes that guarantee **of its output**.
///
/// `sorted()` owes a sorted result. `clamped(to:)` owes a result inside the bounds.
/// `lowercased()` owes a result with no uppercase. The predicate is not found in the
/// subject's code — ``RolePostcondition`` supplies it, which is why this template exists
/// where two discovery-based routes were declined.
///
/// ## Why this earns a template where the discovery routes did not
///
/// `docs/measurements/postcondition-law-declined.md`:
///
/// | route | how the predicate is obtained | population | precision |
/// |---|---|---:|---:|
/// | pair a same-type `(T) -> Bool` by name | discovered | ~5 of 349 | — |
/// | read it from a body guard | discovered | ~13 of 25 | 52%, 9 of 13 in one file |
/// | **role → catalogue** | **supplied** | **~33** | **~97%** |
///
/// The law itself is the strong one: **4 of 4 real normaliser bugs killed, against
/// idempotence's 1 of 4** (`fixtures/branch-reaching-generator/` §4).
///
/// ## The gates, and what each cost to learn
///
/// **Exact name only.** A prefix match is a different operation whose suffix narrows the
/// law: `trimmingLeadingWhitespace` does not guarantee the trailing half. 14 of 16
/// trim-family sites were prefix matches.
///
/// **Parameter labels must leave the role intact.** `trimmed(matching filter:)` is an
/// exact name match that trims trivia a caller selects — supplying "no leading or trailing
/// whitespace" would be a **false law refuting correct code**. It was the only false
/// positive in a hand-check of all 38 declarations.
///
/// **The result must be returned, not applied in place.** A `mutating` function that
/// returns `Void` has no output to assert about.
public enum RolePostconditionTemplate {

    public static func suggest(for summary: FunctionSummary) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: summary)
    }

    public static func makeConstraint() -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "role-postcondition",
            appliesTo: { Self.role(of: $0) != nil },
            signals: Self.signals(for:),
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "role-postcondition|"
                        + IdempotenceTemplate.canonicalSignature(of: summary)
                )
            },
            carrier: { $0.containingTypeName },
            // The law quantifies over the value transformed: the argument for a
            // free/static function, else the receiver.
            carrierType: { $0.parameters.first?.typeText ?? $0.containingTypeName },
            caveats: { Self.caveats(for: $0) }
        )
    }

    /// The role this declaration carries, or `nil`.
    public static func role(of summary: FunctionSummary) -> RolePostcondition? {
        // No output, no postcondition. `async` and `throws` are excluded on the same
        // grounds every other algebraic template excludes them: the law is about a
        // returned value, and a suspension or an error path is a different claim.
        guard let returnType = summary.returnTypeText,
              returnType != "Void", returnType != "()",
              !summary.isAsync, !summary.isThrows
        else { return nil }
        return RolePostcondition.matches(
            name: summary.name,
            parameterLabels: summary.parameters.map(\.label)
        )
    }

    static func signals(for summary: FunctionSummary) -> [Signal] {
        guard let role = Self.role(of: summary) else { return [] }
        // A strong role sits at Likely (30 + 20); the two weak ones — `reversed` and
        // `shuffled`, which pin size and membership but not content — sit below it, so
        // they surface only with `--include-possible`. Measured strength, not a guess:
        // the postcondition kills 4 of 4 on a normaliser where idempotence kills 1 of 4.
        let shapeWeight = role.isStrong ? 30 : 15
        return [
            Signal(
                kind: .exactNameMatch,
                weight: shapeWeight,
                detail: "Curated role verb: '\(summary.name)' names an operation whose "
                    + "guarantee is known, so it owes it of its output — \(role.law)"
            ),
            Signal(
                kind: .typeSymmetrySignature,
                weight: 20,
                detail: "Postcondition shape: the law is asserted of the RESULT, and the "
                    + "predicate is supplied by the catalogue rather than read from the subject"
            )
        ]
    }

    static func caveats(for summary: FunctionSummary) -> [String] {
        guard let role = Self.role(of: summary) else { return [] }
        var caveats = [
            "THE LAW IS A POSTCONDITION: \(role.law). It is supplied by this template from "
                + "the name '\(summary.name)', not read from the code — so it is exactly as good "
                + "as the assumption that the name means what it usually means.",
            "IT IS WRONG IF THE NAME IS IDIOSYNCRATIC. A `sorted` over an order the caller "
                + "supplies, or an `escaped` using a private escaping scheme, still owes its "
                + "guarantee — but a function borrowing the verb for something else does not. "
                + "This is the one failure mode measured on real corpora: `trimmed(matching:)` "
                + "trims trivia a caller selects, and is excluded by parameter shape for that reason."
        ]
        if !role.isStrong {
            caveats.append(
                "THIS ROLE'S LAW IS WEAK. '\(summary.name)' pins the result's SIZE or membership "
                    + "and not its content, so a wrong result of the right shape satisfies it. "
                    + "Surfaced below the strong roles for that reason."
            )
        }
        return caveats
    }
}
