import PropertyLawCore
import SwiftInferCore

/// The second law of the `CaseIterable`-mapping family: **`caseiterable-case-coverage`**
/// — a classifier out of one enum into another owes that **no case lands in the
/// sink**.
///
/// The shape: `RuleIdentifier -> PatternCategory`, where `PatternCategory` has a
/// case called `other`. Every case must be mentioned somewhere — the compiler
/// already forces that much, because an exhaustive `switch` with no `default:`
/// arm will not build without it. What the compiler cannot force is *where* the
/// new case gets mentioned, and the path of least resistance when adding one is
/// the arm that already exists: the sink.
///
/// A case that lands in `.other` is not reported wrong. It is **never checked**
/// — it drops out of every category-filtered run without announcing itself. That
/// is the "spell-checker missing a word" failure this project keeps meeting from
/// different directions: the silence looks exactly like a clean bill of health.
///
/// ## Why the sink has to be found, not assumed
///
/// The law is only checkable once you can name the sink, and the sink is a
/// domain fact. Rather than guess, this template reads the **codomain's own case
/// list** and fires only when it actually contains a curated sink name. An enum
/// with no such case gets no suggestion — there is nothing to be false against,
/// and inventing a law here would be exactly the manufacturing this project
/// declines to do.
///
/// Like its sibling, this is name-conjectured and Possible-tier: routing some
/// cases to `other` can be entirely correct (this codebase's own `.unknown` and
/// `.fileParsingError` sentinels do). The law's value is that it forces the
/// exception list to be **written down** rather than accumulated silently.
extension CaseIterableMappingTemplate {

    /// Case names that read as "we did not classify this". Matched
    /// case-insensitively against the codomain enum's case identifiers.
    public static let curatedSinkCaseNames: Set<String> = [
        "other", "unknown", "unspecified", "unrecognized", "unclassified",
        "none", "undefined", "misc", "miscellaneous"
    ]

    public static func coverageSuggestion(
        for summary: FunctionSummary,
        shapesByName: [String: TypeShape]
    ) -> Suggestion? {
        ConstraintRunner.suggest(
            constraint: makeCoverageConstraint(shapesByName: shapesByName),
            subject: summary
        )
    }

    public static func makeCoverageConstraint(
        shapesByName: [String: TypeShape]
    ) -> Constraint<FunctionSummary> {
        Constraint<FunctionSummary>(
            templateName: "caseiterable-case-coverage",
            appliesTo: { isClassifier($0, shapesByName: shapesByName) },
            signals: { coverageSignals(for: $0, shapesByName: shapesByName) },
            evidence: { [$0.inferenceEvidence] },
            identity: { summary in
                SuggestionIdentity(
                    canonicalInput: "caseiterable-case-coverage|"
                        + IdempotenceTemplate.canonicalSignature(of: summary)
                )
            },
            carrier: { $0.containingTypeName },
            carrierType: { $0.containingTypeName },
            caveats: { summary in coverageCaveats(for: summary, shapesByName: shapesByName) }
        )
    }

    // MARK: - Shape gate

    /// A classifier: a case mapping out of a `CaseIterable` enum whose return
    /// type is *another* corpus enum carrying a sink case.
    ///
    /// Self-mappings are excluded — `Foo -> Foo` is an endomorphism, which the
    /// idempotence / involution templates already speak for.
    static func isClassifier(
        _ summary: FunctionSummary,
        shapesByName: [String: TypeShape]
    ) -> Bool {
        sinkCase(for: summary, shapesByName: shapesByName) != nil
    }

    /// The codomain's sink case name, when every gate passes.
    static func sinkCase(
        for summary: FunctionSummary,
        shapesByName: [String: TypeShape]
    ) -> String? {
        guard let domain = enclosingCaseIterableEnum(of: summary, shapesByName: shapesByName),
              isCaseMapping(summary),
              let returnType = summary.returnTypeText?.trimmingCharacters(in: .whitespaces),
              returnType != domain.name,
              let codomain = shapesByName[returnType],
              codomain.kind == .enum,
              codomain.enumCases.count >= 2 else {
            return nil
        }
        return codomain.enumCases
            .map(\.name)
            .first { curatedSinkCaseNames.contains($0.lowercased()) }
    }

    // MARK: - Scoring

    static func coverageSignals(
        for summary: FunctionSummary,
        shapesByName: [String: TypeShape]
    ) -> [Signal] {
        guard let sink = sinkCase(for: summary, shapesByName: shapesByName),
              let domain = enclosingCaseIterableEnum(of: summary, shapesByName: shapesByName),
              let returnType = summary.returnTypeText?.trimmingCharacters(in: .whitespaces) else {
            return []
        }
        return [
            Signal(
                kind: .orderedCodomainSignature,
                weight: 20,
                detail: "CaseIterable classifier: \(domain.name) (\(domain.enumCases.count) cases) "
                    + "-> \(returnType), so every case's classification is enumerable"
            ),
            Signal(
                kind: .exactNameMatch,
                weight: 15,
                detail: "\(returnType) carries the sink case `.\(sink)` — a case routed there is "
                    + "never reported wrong, it is simply never checked"
            )
        ]
    }

    static func coverageCaveats(
        for summary: FunctionSummary,
        shapesByName: [String: TypeShape]
    ) -> [String] {
        let sink = sinkCase(for: summary, shapesByName: shapesByName) ?? "other"
        let caseCount = enclosingCaseIterableEnum(
            of: summary, shapesByName: shapesByName
        )?.enumCases.count ?? 0
        return [
            "THE LAW IS `allCases.filter { $0.\(summary.name) == .\(sink) } == <your written-down "
                + "exceptions>` — not "
                + "\"nothing maps to the sink\", which is usually false and would be deleted on "
                + "day one. State the exceptions as a literal set; the law is that the ACTUAL sink "
                + "members equal the declared ones.",
            "WHAT IT CATCHES is the next case, not this one. Today's mapping is presumably right. "
                + "The failure is six months out, when a case is added and the arm that already "
                + "exists is the cheapest place to put it — the law fires on that commit, which is "
                + "the only moment anyone can still cheaply fix it.",
            "CHECK IT EXHAUSTIVELY, NOT BY SAMPLING. The domain is \(caseCount) cases and fully "
                + "enumerable, so iterate `allCases`. A sampled run over this domain can miss the "
                + "one newly-added case and report success.",
            "AN EXHAUSTIVE `switch` IS NOT THIS LAW. The compiler forces every case to be "
                + "MENTIONED; it cannot force it to be mentioned somewhere other than the sink "
                + "arm. If the mapping uses a `default:` arm, the compiler is not even doing that "
                + "much, and this law is the only check there is.",
            "SINK ROUTING IS NAME-CONJECTURED. `.\(sink)` is read as a sink because of its NAME; "
                + "it may be a perfectly ordinary member of the codomain. If it is, this law does "
                + "not apply — say so and move on."
        ]
    }
}
