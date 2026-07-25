import PropertyLawCore
import SwiftInferCore

/// Laws over a **mapping out of a `CaseIterable` enum** — a zero-argument member
/// (`var suppressionKey: String`, `func category() -> PatternCategory`) whose
/// domain is the whole case list.
///
/// The gap this closes, from the SwiftProjectLint road test
/// (`docs/roadtest-swiftprojectlint.md`): two of the ten hand-keyed candidates
/// were mappings of exactly this shape, and **nothing in the catalog named
/// them**. Their laws are not about a function's *inputs* — the function has
/// none — they are about the mapping *across all cases*, which no
/// signature-pattern template can see. The pipeline offered `f(x) == f(x)`.
///
/// ## Why the domain matters more than the signature
///
/// A `CaseIterable` carrier is the one place where the domain is **finite,
/// enumerable, and known at compile time**. That changes what a property test
/// should even be: the honest check is an **exhaustive loop over `allCases`**,
/// not `propertyCheck` with 100 sampled trials. Over a 197-case enum, sampling
/// has to be lucky to draw the single colliding pair it exists to find, and it
/// reports success when it misses. Both caveat sets say so, because the emitted
/// advice is the whole product here.
///
/// ## Two laws, both name-conjectured
///
/// Neither law is entailed by the shape, and the reason is worth stating: a
/// mapping out of an enum is *usually* not injective. `RuleIdentifier.category`
/// maps 197 rules onto 11 categories deliberately — that is what a classifier
/// is. Proposing injectivity there would be a false positive on correct code.
///
/// So the two laws split on what the mapping is *for*, read off its name and its
/// codomain:
///
/// - **`caseiterable-key-injectivity`** — a *key*-shaped mapping
///   (`suppressionKey`, `identifier`, `slug`) into a scalar owes distinctness.
/// - **`caseiterable-case-coverage`** — a *classifier* into another enum that
///   has a sink case (`other`, `unknown`) owes that no case lands in the sink.
///
/// This is the same posture as `filter-subset`: refutable, name-conjectured,
/// Possible-tier, left for the seed focus to narrow. See
/// `CaseIterableMappingTemplate+Coverage.swift` for the second law.
public enum CaseIterableMappingTemplate {

    /// Curated key nouns, matched case-insensitively against the member name. A
    /// name ending in one asserts the value *identifies* the case rather than
    /// describing it — which is what makes distinctness owed.
    ///
    /// Suffix-matched rather than prefix-matched: these read as the head noun of
    /// a compound (`suppressionKey`, `ruleIdentifier`, `errorCode`), where the
    /// filter/selection verbs of `FilterSubsetTemplate` lead.
    ///
    /// **Deliberately strict, and `name` is deliberately absent.** This list is
    /// what admits the template to `Refutability.roleEntailedTemplates`, so every
    /// entry has to clear the bar that a *correctly* named implementation cannot
    /// fail the law. `displayName` does not clear it — two cases legitimately
    /// sharing a human-readable label is ordinary code, not a bug — and neither
    /// do `tag` / `abbreviation`. An identifier that collides is either a bug or
    /// a lie about what the name promises; a label that collides is neither.
    public static let curatedKeyNouns: [String] = [
        "key", "identifier", "id", "slug", "token", "code", "symbol"
    ]

    /// Scalar codomains a key can plausibly live in. A key mapping into a struct
    /// or another enum is a classification, not an identifier.
    static let keyCodomains: Set<String> = [
        "String", "Int", "UInt", "Int32", "Int64", "Character", "StaticString"
    ]

    public static func suggest(
        for summary: FunctionSummary,
        shapesByName: [String: TypeShape]
    ) -> Suggestion? {
        ConstraintRunner.suggest(
            constraint: makeConstraint(shapesByName: shapesByName),
            subject: summary
        )
    }

    public static func makeConstraint(shapesByName: [String: TypeShape]) -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "caseiterable-key-injectivity",
            appliesTo: { isKeyMapping($0, shapesByName: shapesByName) },
            signals: { signals(for: $0, shapesByName: shapesByName) },
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "caseiterable-key-injectivity|"
                        + IdempotenceTemplate.canonicalSignature(of: summary)
                )
            },
            // The carrier is the ENUM, not the value type: the law quantifies over
            // `Enum.allCases`, so that is the type a reader needs in hand.
            carrier: { $0.containingTypeName },
            carrierType: { $0.containingTypeName },
            caveats: { summary in makeCaveats(for: summary, shapesByName: shapesByName) }
        )
    }

    // MARK: - Shape gates

    /// The `CaseIterable` enum this member is declared on, when there is one.
    ///
    /// Shared by both laws in this family. Requires at least two cases: a
    /// single-case enum satisfies every distinctness and coverage claim
    /// vacuously, so proposing one would be noise.
    static func enclosingCaseIterableEnum(
        of summary: FunctionSummary,
        shapesByName: [String: TypeShape]
    ) -> TypeShape? {
        guard let typeName = summary.containingTypeName,
              let shape = shapesByName[typeName],
              shape.kind == .enum,
              shape.inheritedTypes.contains("CaseIterable"),
              shape.enumCases.count >= 2 else {
            return nil
        }
        return shape
    }

    /// A zero-argument, non-mutating, non-throwing, synchronous **instance**
    /// member — the shape whose domain is exactly the case list.
    ///
    /// `isStatic` is excluded deliberately: a static member is not a function of
    /// the case, so `allCases.map` has nothing to map.
    static func isCaseMapping(_ summary: FunctionSummary) -> Bool {
        summary.parameters.isEmpty
            && !summary.isStatic
            && !summary.isMutating
            && !summary.isThrows
            && !summary.isAsync
            && !summary.isInitializer
            && summary.returnTypeText != nil
            && isNonVoid(summary.returnTypeText)
    }

    static func isNonVoid(_ text: String?) -> Bool {
        guard let text else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed != "Void" && trimmed != "()"
    }

    /// A key-shaped mapping: the enum gate, the zero-argument gate, a scalar
    /// codomain, and a curated key noun in the name.
    static func isKeyMapping(
        _ summary: FunctionSummary,
        shapesByName: [String: TypeShape]
    ) -> Bool {
        guard enclosingCaseIterableEnum(of: summary, shapesByName: shapesByName) != nil,
              isCaseMapping(summary),
              let returnType = summary.returnTypeText,
              keyCodomains.contains(returnType.trimmingCharacters(in: .whitespaces)) else {
            return false
        }
        return hasKeyNoun(summary.name)
    }

    static func hasKeyNoun(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return curatedKeyNouns.contains { lowered.hasSuffix($0) }
    }

    // MARK: - Scoring

    static func signals(
        for summary: FunctionSummary,
        shapesByName: [String: TypeShape]
    ) -> [Signal] {
        guard isKeyMapping(summary, shapesByName: shapesByName),
              let shape = enclosingCaseIterableEnum(of: summary, shapesByName: shapesByName),
              let returnType = summary.returnTypeText else {
            return []
        }
        // Possible tier (20 + 15 = 35) — the same posture and arithmetic as
        // `filter-subset`, and for the same reason: a name-conjecture that a
        // legitimate non-injective mapping would fail.
        return [
            Signal(
                kind: .orderedCodomainSignature,
                weight: 20,
                detail: "CaseIterable mapping: \(shape.name) (\(shape.enumCases.count) cases) "
                    + "-> \(returnType), so the domain is finite and fully enumerable"
            ),
            Signal(
                kind: .exactNameMatch,
                weight: 15,
                detail: "Curated key noun in '\(summary.name)' — it IDENTIFIES a case rather than "
                    + "describing it, so distinct cases owe distinct values"
            )
        ]
    }

    static func makeCaveats(
        for summary: FunctionSummary,
        shapesByName: [String: TypeShape]
    ) -> [String] {
        let caseCount = enclosingCaseIterableEnum(
            of: summary, shapesByName: shapesByName
        )?.enumCases.count ?? 0
        return [
            "THE LAW IS `Set(allCases.map(\\.\(summary.name))).count == allCases.count` — distinct "
                + "cases map to distinct keys. It is refutable where it matters: two cases whose "
                + "names differ only by punctuation or spacing collapse to one key, and this law "
                + "rejects exactly that.",
            "CHECK IT EXHAUSTIVELY, NOT BY SAMPLING. The domain is \(caseCount) cases and it is "
                + "fully enumerable, so iterate `allCases` — a `propertyCheck` over this domain has "
                + "to be LUCKY to draw the one colliding pair, and it reports success when it "
                + "misses. This is the rare case where a loop strictly dominates a generator.",
            "ASK WHAT A COLLISION COSTS — it decides the severity, not the law. If the mapping "
                + "backs a lookup built with `Dictionary(uniqueKeysWithValues:)`, a collision is a "
                + "runtime TRAP on first use, from inside a lazy static initialiser, with a stack "
                + "that points at the lookup rather than at the case someone added.",
            "INJECTIVITY IS NAME-CONJECTURED, not shape-entailed. A mapping out of an enum is "
                + "usually MANY-TO-ONE by design — a classifier mapping 197 rules onto 11 "
                + "categories is correct code that fails this law. It is owed here only because "
                + "the NAME says the value identifies the case. Confirm that before applying.",
            "The law lives on the TYPE, not on this member: it is a claim about the whole case "
                + "list, so it belongs in a suite over the enum and should be re-run whenever a "
                + "case is added. That is the commit where it earns its keep."
        ]
    }
}
