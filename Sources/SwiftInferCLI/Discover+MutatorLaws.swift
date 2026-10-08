import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// Seed-driven laws for a **`pure-mutator`** — a pure function that returns nothing and changes
/// one value, an `inout` argument or a `mutating` method's `self`.
///
/// The determinism floor (`synthesizeGenericLaws`) needs a returned value and refuses every
/// mutator, so a seeded one earned nothing. SwiftLintRuleStudio's `applyMigration(_:to:)` is the
/// shape that motivated the kind: it writes a config through `inout`, and the law it owes —
/// applying a migration twice changes nothing the first application did not — is exactly the one
/// a returned-value template cannot state.
///
/// Two laws, over copies of the value the seed's `mutates` names:
///
/// - **`mutator-determinism`** — two copies given the same inputs end equal. Advisory and
///   tautological, the floor, as `determinism` is for a function.
/// - **`mutator-idempotence`** — applying it twice equals applying it once. A **conjecture**, in
///   the Possible band: purity vouches that a second application is deterministic, not that it is a
///   no-op, and `bump()` is a correct mutator that fails it.
extension SwiftInferCommand.Discover {

    static func synthesizeMutatorLaws(
        for manifest: SeedManifest,
        summaries: [FunctionSummary],
        covered: [Suggestion],
        diagnostics: any DiagnosticOutput,
        restrictedFunctions: [RestrictedFunction] = []
    ) -> [Suggestion] {
        let seeds = Dictionary(
            manifest.seeds.filter { $0.kind == .pureMutator }
                .map { (genericLawKey(file: $0.file, symbol: $0.symbol), $0) }
        ) { first, _ in first }
        guard !seeds.isEmpty else { return [] }

        // A focused law already speaking to the mutator — the lifted `mutating` idempotence, say —
        // is not doubled.
        let coveredKeys = Set(covered.flatMap { suggestion in
            suggestion.evidence.map {
                genericLawKey(file: $0.location.file, symbol: functionBaseName($0.displayName))
            }
        })
        let restrictionByCoordinate = Dictionary(
            restrictedFunctions.map { (coordinate(of: $0.summary.location), $0.restriction) }
        ) { first, _ in first }

        var synthesized: [Suggestion] = []
        var seen: Set<String> = []
        for summary in summaries + restrictedFunctions.map(\.summary) {
            let key = genericLawKey(file: summary.location.file, symbol: summary.name)
            guard let seed = seeds[key], !coveredKeys.contains(key), !seen.contains(key),
                  mutatedType(of: summary) != nil else { continue }
            seen.insert(key)
            let law = MutatorLawInput(
                summary: summary,
                restriction: restrictionByCoordinate[coordinate(of: summary.location)],
                requirement: seed.requires
            )
            synthesized.append(mutatorDeterminism(law))
            synthesized.append(mutatorIdempotence(law))
        }

        if !synthesized.isEmpty {
            diagnostics.writeDiagnostic(
                "synthesized \(synthesized.count) mutator law(s) for \(synthesized.count / 2) seeded "
                    + "pure mutator(s) — idempotence is a conjecture; pass --include-possible to see it"
            )
        }
        return synthesized
    }

    /// What one mutator law is written from.
    private struct MutatorLawInput {
        let summary: FunctionSummary
        let restriction: AccessRestriction?
        let requirement: SeedRequirement?
    }

    /// The type of the value `summary` changes — `self`'s for a `mutating` method, the one `inout`
    /// parameter's otherwise — or `nil` when the scan does not see a mutator here: a returned value,
    /// `async`, or more than one value written. The seed is the purity claim; this is the shape a
    /// law can be written over.
    static func mutatedType(of summary: FunctionSummary) -> String? {
        let returned = summary.returnTypeText ?? "Void"
        guard returned == "Void" || returned == "()", !summary.isAsync else { return nil }
        let written = summary.parameters.filter(\.isInout)
        if summary.isMutating {
            guard written.isEmpty, !summary.isStatic else { return nil }
            return summary.containingTypeName
        }
        guard written.count == 1 else { return nil }
        return written.first?.typeText
    }

    private static func mutatorDeterminism(_ input: MutatorLawInput) -> Suggestion {
        let evidence = input.summary.inferenceEvidence
        let signal = Signal(
            kind: .deterministicPurity,
            weight: 30,
            detail: "Lint-seeded pure mutator — two copies given the same inputs end equal: "
                + "var a = x; f(&a); var b = x; f(&b); a == b"
        )
        let why = [
            "Holds only if the mutator is genuinely pure — a hidden global read or nondeterministic "
                + "dependency would falsify it, which is exactly what the test catches."
        ]
        return Suggestion(
            templateName: "mutator-determinism",
            evidence: [evidence],
            score: Score(advisorySignals: [signal] + accessBlockerSignals(for: input.restriction)),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(
                whySuggested: ["\(evidence.displayName) \(evidence.signature)", signal.formattedLine],
                whyMightBeWrong: caveats(why, input)
            ),
            identity: SuggestionIdentity(
                canonicalInput: "mutator-determinism|" + canonicalInput(for: input.summary, evidence: evidence)
            ),
            carrier: input.summary.containingTypeName
        )
    }

    private static func mutatorIdempotence(_ input: MutatorLawInput) -> Suggestion {
        let evidence = input.summary.inferenceEvidence
        let signal = Signal(
            kind: .seededPureMutator,
            weight: 25,
            detail: "Lint-seeded pure mutator — applying it twice should change nothing the first "
                + "application did not: var once = x; f(&once); var twice = once; f(&twice); once == twice"
        )
        let why = [
            "A conjecture: purity says a second application is deterministic, not that it is a no-op. "
                + "An increment or an append is a correct mutator that fails this — accept it only if "
                + "applying it twice is meant to leave what applying it once left."
        ]
        return Suggestion(
            templateName: "mutator-idempotence",
            evidence: [evidence],
            score: Score(signals: [signal] + accessBlockerSignals(for: input.restriction)),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(
                whySuggested: ["\(evidence.displayName) \(evidence.signature)", signal.formattedLine],
                whyMightBeWrong: caveats(why, input)
            ),
            identity: SuggestionIdentity(
                canonicalInput: "mutator-idempotence|" + canonicalInput(for: input.summary, evidence: evidence)
            ),
            carrier: input.summary.containingTypeName
        )
    }

    /// The access remedy first, verbatim as the determinism floor and the template rows open, then
    /// the seed's `requires` when it has one, then the law's own.
    ///
    /// **No "must be Equatable" sentence without `requires`.** The producer seeds a plain
    /// `pure-mutator` only when the mutated value is already comparable, and a near miss arrives
    /// naming the types; a generic sentence beside either would be wrong or redundant.
    private static func caveats(_ why: [String], _ input: MutatorLawInput) -> [String] {
        let access = input.restriction.map { ["NO TEST CAN RUN THIS LAW AS WRITTEN: \($0.remedy)"] } ?? []
        let required = input.requirement.map { [$0.caveat] } ?? []
        return access + required + why
    }
}
