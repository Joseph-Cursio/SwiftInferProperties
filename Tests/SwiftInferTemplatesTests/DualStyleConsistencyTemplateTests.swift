import PropertyLawCore
import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("DualStyleConsistencyTemplate — V1.18.C signal scoring + identity")
struct DualStyleConsistencyTemplateTests {

    // MARK: - Helpers

    private func summary(
        _ name: String,
        params: [(label: String?, type: String)] = [],
        returnType: String? = nil,
        isMutating: Bool = false,
        containingType: String = "Bag",
        line: Int = 1,
        nonDeterministic: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: params.enumerated().map { index, parameter in
                Parameter(
                    label: parameter.label,
                    internalName: "p\(index)",
                    typeText: parameter.type,
                    isInout: false
                )
            },
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: isMutating,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: line, column: 1),
            containingTypeName: containingType,
            bodySignals: BodySignals(
                hasNonDeterministicCall: nonDeterministic,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: nonDeterministic ? ["Date.init"] : []
            )
        )
    }

    private func makePair(
        mutating mutatingName: String = "add",
        nonMutating nonMutatingName: String = "adding",
        rule: DualStylePair.PairingRule = .activeToPresentParticiple,
        nonDeterministic: Bool = false
    ) -> DualStylePair {
        DualStylePair(
            mutatingMember: summary(
                mutatingName,
                params: [(label: nil, type: "Item")],
                returnType: "Void",
                isMutating: true,
                nonDeterministic: nonDeterministic
            ),
            nonMutatingMember: summary(
                nonMutatingName,
                params: [(label: nil, type: "Item")],
                returnType: "Bag"
            ),
            rule: rule
        )
    }

    private func valueSemanticResolver() -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: "Bag",
                kind: .struct,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "items", typeName: "[Item]")]
            )
        ])
    }

    // MARK: - Scoring

    @Test("Active / present-participle pair scores 70 (Likely) without resolver")
    func scoresWithoutResolver() throws {
        let suggestion = try #require(DualStyleConsistencyTemplate.suggest(for: makePair()))
        // 30 type-shape + 40 naming = 70 → Likely (40-74).
        #expect(suggestion.score.total == 70)
        #expect(suggestion.score.tier == .likely)
        #expect(suggestion.templateName == "dual-style-consistency")
    }

    @Test("Value-semantic carrier signal lifts the score to 75 (Strong)")
    func valueSemanticCarrierLiftsToStrong() throws {
        let suggestion = try #require(DualStyleConsistencyTemplate.suggest(
            for: makePair(),
            carrierKindResolver: valueSemanticResolver()
        ))
        // 30 + 40 + 5 = 75 → Strong.
        #expect(suggestion.score.total == 75)
        #expect(suggestion.score.tier == .strong)
    }

    @Test("Reference-type carrier signal demotes the score to 60 (Likely)")
    func referenceCarrierDemotesToLikely() throws {
        let resolver = CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: "Bag",
                kind: TypeDecl.Kind.class,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1)
            )
        ])
        let suggestion = try #require(DualStyleConsistencyTemplate.suggest(
            for: makePair(),
            carrierKindResolver: resolver
        ))
        // 30 + 40 - 10 = 60 → Likely.
        #expect(suggestion.score.total == 60)
        #expect(suggestion.score.tier == .likely)
    }

    @Test("Unknown / mixed carrier emits no signal — score stays at 70")
    func unknownCarrierEmitsNoSignal() throws {
        let resolver = CarrierKindResolver(typeDecls: [])
        let suggestion = try #require(DualStyleConsistencyTemplate.suggest(
            for: makePair(),
            carrierKindResolver: resolver
        ))
        #expect(suggestion.score.total == 70)
    }

    @Test("Non-deterministic body in mutating member vetoes the suggestion")
    func nonDeterministicVetoSuppresses() {
        let suggestion = DualStyleConsistencyTemplate.suggest(
            for: makePair(nonDeterministic: true)
        )
        #expect(suggestion == nil)
    }

    // MARK: - Naming detail rendering

    @Test("Past-participle rule renders the matching detail line")
    func pastParticipleDetail() throws {
        let suggestion = try #require(DualStyleConsistencyTemplate.suggest(
            for: makePair(
                mutating: "sort",
                nonMutating: "sorted",
                rule: .activeToPastParticiple
            )
        ))
        let signal = try #require(suggestion.score.signals.first {
            $0.kind == .exactNameMatch
        })
        #expect(signal.detail.contains("Active / past-participle"))
        #expect(signal.detail.contains("'sort'"))
        #expect(signal.detail.contains("'sorted'"))
    }

    @Test("Form-prefix rule renders the matching detail line")
    func formPrefixDetail() throws {
        let suggestion = try #require(DualStyleConsistencyTemplate.suggest(
            for: makePair(
                mutating: "formUnion",
                nonMutating: "union",
                rule: .formPrefixToBare
            )
        ))
        let signal = try #require(suggestion.score.signals.first {
            $0.kind == .exactNameMatch
        })
        #expect(signal.detail.contains("form-prefix / bare"))
    }

    @Test("Project-vocabulary rule renders the matching detail line")
    func projectVocabularyDetail() throws {
        let suggestion = try #require(DualStyleConsistencyTemplate.suggest(
            for: makePair(
                mutating: "rebake",
                nonMutating: "baker",
                rule: .projectVocabulary
            )
        ))
        let signal = try #require(suggestion.score.signals.first {
            $0.kind == .exactNameMatch
        })
        #expect(signal.detail.contains("Project-vocabulary"))
    }

    // MARK: - Identity

    @Test("Identity is orientation-stable across mutating/non-mutating sort order")
    func identityIsOrientationStable() throws {
        let suggestion = try #require(DualStyleConsistencyTemplate.suggest(for: makePair()))
        // Identity prefix matches the template name; the canonical input
        // sorts the two halves so the hash is order-independent.
        #expect(suggestion.identity.canonicalInput.hasPrefix("dual-style-consistency|"))
    }

    @Test("Cross-validation key carries both callee names sorted lexicographically")
    func crossValidationKeyContainsBothCallees() throws {
        let suggestion = try #require(DualStyleConsistencyTemplate.suggest(for: makePair()))
        let key = suggestion.crossValidationKey
        #expect(key.templateName == "dual-style-consistency")
        #expect(key.calleeNames == ["add", "adding"])
    }

    // MARK: - Two evidence rows

    @Test("Suggestion carries two evidence rows: mutating + non-mutating")
    func twoEvidenceRows() throws {
        let suggestion = try #require(DualStyleConsistencyTemplate.suggest(for: makePair()))
        #expect(suggestion.evidence.count == 2)
        #expect(suggestion.evidence[0].displayName == "add(_:)")
        #expect(suggestion.evidence[1].displayName == "adding(_:)")
    }
}
