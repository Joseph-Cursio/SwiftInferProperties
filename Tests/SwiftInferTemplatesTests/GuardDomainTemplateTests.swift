import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The first body-derived template: the law is read from the function's own early return.
///
/// Classifying the 21 laws this walk predicted and the catalog missed, **15 are facts about
/// bodies and 2 about signatures** — and a signature is all any other template reads
/// (`docs/measurements/s3-characterisation.md`).
@Suite("GuardDomainTemplate")
struct GuardDomainTemplateTests {

    private func summary(
        name: String = "parse",
        parameter: String = "source",
        parameterType: String = "String",
        returnType: String? = "String",
        domain: GuardDomain? = GuardDomain(
            condition: #"source.hasPrefix("---")"#,
            returnedExpression: "(Self(), source)",
            parameterName: "source",
            firesWhenConditionHolds: false
        ),
        isThrows: Bool = false,
        isAsync: Bool = false,
        isMutating: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [.init(label: "from", internalName: parameter, typeText: parameterType, isInout: false)],
            returnTypeText: returnType,
            isThrows: isThrows,
            isAsync: isAsync,
            isMutating: isMutating,
            isStatic: true,
            location: SourceLocation(file: "F.swift", line: 1, column: 1),
            containingTypeName: "FrontMatter",
            bodySignals: BodySignals(
                guardDomain: domain,
                hasNonDeterministicCall: false,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: []
            )
        )
    }

    /// The walk's motivating case. This exact sentence was written by hand as a predicted law
    /// **before any tool ran**, and was not proposed.
    @Test func theMotivatingCaseIsProposed() throws {
        let suggestion = try #require(GuardDomainTemplate.suggest(for: summary()))
        #expect(suggestion.templateName == "guard-domain")
        let detail = suggestion.score.signals.map(\.detail).joined(separator: " ")
        #expect(detail.contains(#"!(source.hasPrefix("---"))"#))
        #expect(detail.contains("== (Self(), source)"))
    }

    /// `guard` and `if` state opposite sub-domains, and the rendered law has to say which.
    @Test func anIfDomainIsNotNegated() throws {
        let domain = GuardDomain(
            condition: "value.isEmpty", returnedExpression: "true",
            parameterName: "value", firesWhenConditionHolds: true
        )
        let suggestion = try #require(GuardDomainTemplate.suggest(
            for: summary(name: "f", parameter: "value", returnType: "Bool", domain: domain)
        ))
        let detail = suggestion.score.signals.map(\.detail).joined(separator: " ")
        #expect(detail.contains("(value.isEmpty) ⟹"))
        #expect(detail.contains("!(value.isEmpty)") == false)
    }

    @Test func noGuardMeansNoSuggestion() {
        #expect(GuardDomainTemplate.suggest(for: summary(domain: nil)) == nil)
    }

    /// **`throws` is excluded rather than tolerated.** The law compares `f(x)` to an expression,
    /// and a throwing call needs a `try` whose failure is a third outcome the law does not name.
    @Test("effects and mutation are excluded", arguments: [
        ("throws", true, false, false), ("async", false, true, false), ("mutating", false, false, true)
    ])
    func effectsAreExcluded(label _: String, isThrows: Bool, isAsync: Bool, isMutating: Bool) {
        #expect(GuardDomainTemplate.suggest(
            for: summary(isThrows: isThrows, isAsync: isAsync, isMutating: isMutating)
        ) == nil)
    }

    /// A `Void` return has nothing to compare.
    @Test func aVoidReturnIsExcluded() {
        #expect(GuardDomainTemplate.suggest(for: summary(returnType: "Void")) == nil)
    }

    /// **Role-entailed, and for a different reason from every other member of that set.** The
    /// others are owed by virtue of a role; this one because the code is the law's source. That
    /// is what lets it sit above the cut where `idempotence` — a conjecture read off a name —
    /// cannot.
    @Test func itIsRoleEntailedAndSoSurvivesTheCut() throws {
        let suggestion = try #require(GuardDomainTemplate.suggest(for: summary()))
        #expect(Refutability.isRoleEntailed(suggestion))
        #expect(Refutability.isWorthSurfacingBelowCut(suggestion))
    }

    /// The caveat says the thing a reader most needs and would otherwise assume the opposite of.
    @Test func theCaveatSaysItCannotFailToday() throws {
        let suggestion = try #require(GuardDomainTemplate.suggest(for: summary()))
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: " ")
        #expect(caveats.contains("CANNOT FAIL AGAINST THE CODE IT WAS READ FROM"))
        #expect(caveats.contains("catches an EDIT"))
    }
}
