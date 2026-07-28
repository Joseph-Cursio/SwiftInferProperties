import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The formatter veto's type gate — `docs/parsing-catalog-gap.md` §4.
///
/// `shapeDisambiguationVeto` pattern 2 used to fire on the name prefix alone
/// (`_description*` or `format*`), while its own stated rationale was a type
/// argument: *"`format(_:)` returns String for non-String input"*, so
/// `format(format(x))` cannot type-check. That argument only obtains when the
/// parameter and return types differ, and the veto fired regardless — so it
/// also fired at `(String) -> String`, where the argument does not apply and
/// where idempotence is the canonical law a source formatter owes.
///
/// The bundle also mixed in a second, unrelated argument for `_description`
/// (structural wrapping), which is type-independent and had to survive the
/// split intact.
@Suite("IdempotenceTemplate — formatter-veto type gate")
struct FormatterVetoTypeGateTests {

    private func summary(
        _ name: String,
        param: String,
        returns: String,
        label: String? = nil
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(label: label, internalName: "value", typeText: param, isInout: false)
            ],
            returnTypeText: returns,
            isThrows: false, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: "Formatting",
            bodySignals: .empty
        )
    }

    // MARK: - The law the veto was costing

    @Test("a String -> String formatter is no longer vetoed — the §4 case")
    func sameTypeFormatterSurvives() {
        // `format(format(x)) == format(x)` is the one law every source
        // formatter owes. Measured before the fix: `normalize` scored 75
        // Strong and `format` was suppressed at the identical shape, while
        // `curatedVerbs` was crediting `format` +40 on the same name.
        for name in ["format", "formatSource", "formatDocument"] {
            let subject = summary(name, param: "String", returns: "String")
            #expect(
                IdempotenceTemplate.shapeDisambiguationVeto(for: subject) == nil,
                "expected \(name) (String -> String) NOT vetoed"
            )
            #expect(IdempotenceTemplate.suggest(for: subject) != nil)
        }
    }

    @Test("the curated verb and the veto no longer disagree about the same name")
    func curatedVerbNowSurvivesToStrong() throws {
        // `format` is in `IdempotenceTemplate.curatedVerbs` (+40). Before the
        // split the catalog credited it and then vetoed it.
        #expect(IdempotenceTemplate.curatedVerbs.contains("format"))
        let suggestion = try #require(
            IdempotenceTemplate.suggest(for: summary("format", param: "String", returns: "String"))
        )
        #expect(suggestion.score.signals.contains { $0.kind == .exactNameMatch })
        // 30 type-symmetry + 40 curated verb = 70. A real `discover` run adds
        // the +5 value-semantic carrier signal and lands it at 75 / Strong —
        // measured on the CLI; this unit context passes no resolver.
        #expect(suggestion.score.total == 70)
    }

    @Test("non-String same-type formatters survive too — the gate is on types, not on String")
    func sameTypeNonStringFormatterSurvives() {
        for (param, returns) in [("Decimal", "Decimal"), ("Doc", "Doc"), ("Int", "Int")] {
            #expect(
                IdempotenceTemplate.shapeDisambiguationVeto(
                    for: summary("format", param: param, returns: returns)
                ) == nil,
                "expected format (\(param) -> \(returns)) NOT vetoed"
            )
        }
    }

    // MARK: - What must survive the split

    @Test("`_description*` keeps its UNCONDITIONAL veto — structural wrapping is type-independent")
    func descriptionVetoIsNotTypeGated() throws {
        // `_description(type:)` prepends a type wrapper, so applying it twice
        // prepends twice. That is a claim about what the function does to a
        // value; it holds at `(String) -> String` exactly as it holds
        // elsewhere, so it must NOT inherit the type gate.
        let subject = summary("_description", param: "String", returns: "String", label: "type")
        let veto = try #require(
            IdempotenceTemplate.shapeDisambiguationVeto(for: subject),
            "_description must stay vetoed at String -> String"
        )
        #expect(veto.isVeto)
        #expect(veto.detail.contains("structural"))
        #expect(IdempotenceTemplate.suggest(for: subject) == nil)
    }

    @Test("the capacity/scale arm is untouched")
    func capacityArmUnaffected() {
        let subject = summary("_minimumCapacity", param: "Int", returns: "Int", label: "forScale")
        #expect(IdempotenceTemplate.shapeDisambiguationVeto(for: subject)?.isVeto == true)
    }

    // MARK: - The gate's one remaining trigger, and its honest scope

    @Test("format on the optional-narrowing shape is the only thing the gate still stops")
    func optionalNarrowingFormatterStillVetoed() throws {
        // Only two arms of `typeSymmetrySignal` admit a parameter: the
        // exact-equal form and the optional-narrowing form
        // (`func mergedWith(_ x: T?) -> T`). So after the gate, `format*`
        // fires on `(T?) -> T` and nothing else.
        let subject = summary("format", param: "Doc?", returns: "Doc")
        let veto = try #require(IdempotenceTemplate.shapeDisambiguationVeto(for: subject))
        #expect(veto.isVeto)
        // The message must NOT claim a type error. `format(format(x))`
        // type-checks here — `Doc` promotes back to `Doc?`, which is the whole
        // reason the optional-narrowing arm admits the shape at all. The veto
        // states the weaker, true thing: this is a defaulting step.
        #expect(!veto.detail.contains("type-check"))
        #expect(veto.detail.contains("DEFAULTS"))
    }
}
