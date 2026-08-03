import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
import Testing

/// **Every `TemplateName.verifiable` entry must survive both dispatch gates.**
///
/// The template vocabulary is enumerated in three places, and only the first is a list:
///
/// | gate | where | shape |
/// |---|---|---|
/// | 1. is it verifiable? | `TemplateName.verifiable` | an array |
/// | 2. how are its calls resolved? | `resolveFunctionCalls` | a `switch` |
/// | 3. how is its law composed? | `defaultPassSection` + `algebraicLawPass` + `totalityLawPass` | a `switch` |
///
/// `TemplateName` exists so curated subsets cannot drift apart — and gates 2 and 3 are not subsets
/// it can see. Adding `predicate` to the array and to gate 3 shipped a composer that **verify never
/// reached**: gate 2's `default:` threw the very `unsupportedTemplate` the composer existed to
/// prevent. All 49 indexed `predicate` entries declined, and the 11 unit tests stayed green because
/// they call the composer *directly*, past both gates.
///
/// ## Why this is behavioural rather than a contents comparison
///
/// Two of the three are `switch` statements; there is no list to compare against. A guard that
/// checked what it *could* reach — the array against itself — would pass green through exactly the
/// defect that motivated it, which is the failure mode this repo has already paid for twice
/// (`KitCoverageDriftTests` at suite granularity, `CuratedEntryRole` on the wrong join). So the
/// check calls the gates and asserts on what comes back.
///
/// ## What it asserts, precisely
///
/// **Not** that every template verifies — most of these synthetic entries cannot, and should not.
/// A pair template with no partner throws `unsupportedPair`; a carrier with no generator throws
/// `unsupportedCarrier`. Those are honest refusals about *this* entry.
///
/// The assertion is narrower and is the whole point: **no gate may refuse a verifiable template on
/// the grounds that it is not verifiable.** `unsupportedTemplate` from a member of
/// `TemplateName.verifiable` is a contradiction in terms, and it is precisely what drift looks like.
@Suite("Verifiable templates reach both dispatch gates")
struct VerifiableTemplateReachTests {

    private func entry(for template: TemplateName) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0xDRIFTGUARD",
            templateName: template.rawValue,
            typeName: "Int",
            score: 60,
            tier: "Strong",
            primaryFunctionName: "subject(_:)",
            location: "/Module.swift:1",
            firstSeenAt: "2026-08-03T00:00:00Z",
            lastSeenAt: "2026-08-03T00:00:00Z"
        )
    }

    /// Gate 2. The one that was missed.
    @Test func everyVerifiableTemplateResolvesItsCalls() {
        for template in TemplateName.verifiable {
            do {
                _ = try SwiftInferCommand.Verify.resolveFunctionCalls(for: entry(for: template))
            } catch let VerifyError.unsupportedTemplate(name, _) {
                Issue.record(
                    """
                    `\(name)` is in TemplateName.verifiable but `resolveFunctionCalls` has no case \
                    for it, so verify declines it as unsupported before any composer runs. Add the \
                    case, or remove the template from `verifiable` — the two must agree.
                    """
                )
            } catch {
                // Any OTHER refusal is about this synthetic entry, not about the vocabulary.
                // `unsupportedPair`, `unsupportedCarrier`, a missing secondary name — all fine.
                continue
            }
        }
    }

    /// Gate 3. Green today, and here so the pair of gates is checked as a pair — a future template
    /// added to `verifiable` and to call resolution but not to composition fails exactly the same
    /// way, one layer later.
    @Test func everyVerifiableTemplateComposesItsLaw() {
        let recipe = StrategistDispatchEmitter.GeneratorRecipe(
            expression: "Gen<Int>.int(in: 0 ... 10)",
            carrierTypeName: "Int",
            imports: []
        )
        for template in TemplateName.verifiable {
            let inputs = StrategistDispatchEmitter.Inputs(
                carrier: "Int",
                typeShape: nil,
                template: template.rawValue,
                functionCalls: ["subject", "inverse"],
                extraImports: [],
                seedHex: .init(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
                trialBudget: .small,
                allShapes: [:],
                isInstanceMethod: false,
                isMutatingMethod: false,
                isNullary: false,
                returnsSelfType: false,
                isComputedProperty: false,
                parameterCount: 1
            )
            do {
                _ = try StrategistDispatchEmitter.defaultPassSection(inputs: inputs, recipe: recipe)
            } catch let VerifyError.unsupportedTemplate(name, _) {
                Issue.record(
                    """
                    `\(name)` is in TemplateName.verifiable but no composer handles it — \
                    `defaultPassSection`, `algebraicLawPass` and `totalityLawPass` all declined. \
                    Add a composer, or remove it from `verifiable`.
                    """
                )
            } catch {
                continue
            }
        }
    }

    /// The set is not empty and contains the template whose absence motivated all of this — a guard
    /// that silently iterated nothing would pass forever.
    @Test func theGuardIsActuallyIterating() {
        #expect(TemplateName.verifiable.count >= 14)
        #expect(TemplateName.verifiable.contains(.predicate))
    }

    /// `strategistAlgebraicLaws` is derived from `verifiable` by exclusion, so a template added to
    /// the array lands there by default — and `predicate` must not, since `algebraicLawPass` cannot
    /// compose it. Pins the exclusion rather than the derivation.
    @Test func theAlgebraicSubsetExcludesWhatItCannotCompose() {
        for name in TemplateName.strategistAlgebraicLaws {
            #expect(name != .predicate, "predicate is not an algebraic law and must stay excluded")
            #expect(name != .codableRoundTrip)
            #expect(name != .measureNonNegativity)
        }
    }
}
