import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("InvariantPreservationTemplate — annotation-only firing, Strong tier")
struct InvariantPreservationTemplateTests {

    // MARK: - Annotation gating

    @Test("Annotation present scores 80 (Strong)")
    func annotationPresentScoresStrong() {
        let summary = makeSummary(
            name: "adjust",
            paramType: "Widget",
            returnType: "Widget",
            invariantKeypath: "\\.isValid"
        )
        let suggestion = InvariantPreservationTemplate.suggest(for: summary)
        #expect(suggestion?.score.total == 80)
        #expect(suggestion?.score.tier == .strong)
    }

    @Test("Annotation absent yields no suggestion even with preservation-suggesting name")
    func nameAloneDoesNotMatch() {
        // `mutate`, `apply`, `updateInPlace` all read like preservation
        // candidates — but per the §5.2 caveat the annotation is
        // structurally required. Any of these without the attribute → nil.
        for verb in ["mutate", "apply", "updateInPlace", "transform", "adjust"] {
            let summary = makeSummary(
                name: verb,
                paramType: "Widget",
                returnType: "Widget"
            )
            #expect(
                InvariantPreservationTemplate.suggest(for: summary) == nil,
                "verb '\(verb)' should not match without annotation"
            )
        }
    }

    @Test("Empty invariantKeypath string is treated as absent")
    func emptyKeypathIsTreatedAsPresent() {
        // Explicit guard: if the scanner ever surfaces an empty string
        // (it shouldn't, but the type permits it), the template should
        // still emit. Documents the absent / present semantics: the
        // gate is non-nil-ness, not text content.
        let summary = makeSummary(
            name: "adjust",
            paramType: "Widget",
            returnType: "Widget",
            invariantKeypath: ""
        )
        #expect(InvariantPreservationTemplate.suggest(for: summary)?.score.tier == .strong)
    }

    // MARK: - Veto

    @Test("Non-deterministic body suppresses an annotated function")
    func nonDeterministicBodyVetoes() {
        let summary = makeSummary(
            name: "adjust",
            paramType: "Widget",
            returnType: "Widget",
            invariantKeypath: "\\.isValid",
            bodySignals: BodySignals(
                hasNonDeterministicCall: true,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: ["UUID()"]
            )
        )
        #expect(InvariantPreservationTemplate.suggest(for: summary) == nil)
    }

    // MARK: - Type-pattern flexibility

    @Test("Multi-parameter annotated function still emits — annotation overrides shape constraints")
    func multiParameterAnnotatedFires() {
        // Unlike idempotence/monotonicity which guard on parameter count,
        // invariant-preservation's gate is the annotation. A function
        // with multiple params still emits.
        let summary = makeSummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "lhs", typeText: "Widget", isInout: false),
                Parameter(label: nil, internalName: "rhs", typeText: "Widget", isInout: false)
            ],
            returnType: "Widget",
            invariantKeypath: "\\.isValid"
        )
        #expect(InvariantPreservationTemplate.suggest(for: summary)?.score.tier == .strong)
    }

    @Test("Annotated function with non-matching return type still emits")
    func returnTypeNeedNotMatch() {
        // `T -> U` is fine — the keypath is on `T` (input) and `U`
        // (output) is checked against the same predicate or its
        // analogue. The template doesn't enforce equality of the param
        // and return types.
        let summary = makeSummary(
            name: "summarize",
            paramType: "Document",
            returnType: "Summary",
            invariantKeypath: "\\.wordCount"
        )
        #expect(InvariantPreservationTemplate.suggest(for: summary)?.score.tier == .strong)
    }

    // MARK: - Identity

    @Test("Same function with two different keypaths produces distinct identities")
    func keypathPartOfIdentity() {
        let baseSummary = makeSummary(
            name: "adjust",
            paramType: "Widget",
            returnType: "Widget"
        )
        let summary1 = baseSummary.withInvariantKeypath("\\.isValid")
        let summary2 = baseSummary.withInvariantKeypath("\\.isNonNegative")
        let suggestion1 = InvariantPreservationTemplate.suggest(for: summary1)
        let suggestion2 = InvariantPreservationTemplate.suggest(for: summary2)
        #expect(suggestion1?.identity != suggestion2?.identity)
    }

    @Test("Suggestion identity carries the invariant-preservation template prefix")
    func identityCarriesTemplatePrefix() {
        let summary = makeSummary(
            name: "adjust",
            paramType: "Widget",
            returnType: "Widget",
            invariantKeypath: "\\.isValid"
        )
        let suggestion = InvariantPreservationTemplate.suggest(for: summary)
        #expect(suggestion?.identity.canonicalInput.hasPrefix("invariant-preservation|") == true)
        #expect(suggestion?.identity.canonicalInput.hasSuffix("|\\.isValid") == true)
    }

    // MARK: - Evidence + signature rendering

    @Test("Evidence signature line includes the keypath via `preserving` clause")
    func evidenceSignatureRendersKeypath() {
        let summary = makeSummary(
            name: "adjust",
            paramType: "Widget",
            returnType: "Widget",
            invariantKeypath: "\\.isValid"
        )
        let suggestion = InvariantPreservationTemplate.suggest(for: summary)
        let evidence = try? #require(suggestion?.evidence.first)
        #expect(evidence?.signature.contains("preserving \\.isValid") == true)
    }

    @Test("Template name is invariant-preservation")
    func templateNameMatches() {
        let summary = makeSummary(
            name: "adjust",
            paramType: "Widget",
            returnType: "Widget",
            invariantKeypath: "\\.isValid"
        )
        let suggestion = InvariantPreservationTemplate.suggest(for: summary)
        #expect(suggestion?.templateName == "invariant-preservation")
    }

    // MARK: - Helpers

    private func makeSummary(
        name: String,
        paramType: String? = nil,
        parameters explicitParameters: [Parameter]? = nil,
        returnType: String?,
        invariantKeypath: String? = nil,
        bodySignals: BodySignals = .empty
    ) -> FunctionSummary {
        let parameters: [Parameter]
        if let explicitParameters {
            parameters = explicitParameters
        } else if let paramType {
            parameters = [Parameter(label: nil, internalName: "value", typeText: paramType, isInout: false)]
        } else {
            parameters = []
        }
        return FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: bodySignals,
            discoverableGroup: nil,
            invariantKeypath: invariantKeypath
        )
    }
}

// MARK: - Test helpers

extension FunctionSummary {
    fileprivate func withInvariantKeypath(_ keyPath: String?) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returnTypeText,
            isThrows: isThrows,
            isAsync: isAsync,
            isMutating: isMutating,
            isStatic: isStatic,
            location: location,
            containingTypeName: containingTypeName,
            bodySignals: bodySignals,
            discoverableGroup: discoverableGroup,
            invariantKeypath: keyPath
        )
    }
}
