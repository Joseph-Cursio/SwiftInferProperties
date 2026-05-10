import PropertyLawCore
import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("IdentityElementTemplate — V1.19.C lift admission (op'(s, e) == s)")
struct IdentityElementTemplateLiftedTests {

    // MARK: - Helpers

    private func valueSemanticResolver(carrier: String = "Counter") -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: carrier,
                kind: .struct,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "value", typeName: "Int")]
            )
        ])
    }

    private func mutatorBy(
        _ name: String = "increment",
        paramType: String = "Int",
        carrier: String = "Counter"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(label: "by", internalName: "amount", typeText: paramType, isInout: false)
            ],
            returnTypeText: "Void",
            isThrows: false,
            isAsync: false,
            isMutating: true,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    private func lifted(
        _ name: String = "increment",
        paramType: String = "Int",
        carrier: String = "Counter"
    ) -> LiftedTransformation {
        LiftedTransformation.lift(
            mutatorBy(name, paramType: paramType, carrier: carrier),
            carrierKindResolver: valueSemanticResolver(carrier: carrier)
        )!
    }

    private func zeroIdentity(
        name: String = "zero",
        typeText: String = "Int",
        containingType: String? = nil
    ) -> IdentityCandidate {
        IdentityCandidate(
            name: name,
            typeText: typeText,
            containingTypeName: containingType,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1)
        )
    }

    // MARK: - Pairing

    @Test("(Counter.increment(by: Int), zero: Int) pair is found")
    func canonicalPairFound() {
        let pairs = LiftedIdentityElementPairing.candidates(
            in: [lifted()],
            identities: [zeroIdentity()]
        )
        #expect(pairs.count == 1)
        #expect(pairs.first?.operation.originalSummary.name == "increment")
        #expect(pairs.first?.identity.name == "zero")
    }

    @Test("Identity with mismatched type does NOT pair")
    func mismatchedIdentityTypeDoesntPair() {
        let pairs = LiftedIdentityElementPairing.candidates(
            in: [lifted()],
            identities: [zeroIdentity(typeText: "String")]
        )
        #expect(pairs.isEmpty)
    }

    @Test("Identity with non-curated name does NOT pair (e.g. 'origin')")
    func nonCuratedIdentityNameDoesntPair() {
        let pairs = LiftedIdentityElementPairing.candidates(
            in: [lifted()],
            identities: [zeroIdentity(name: "origin")]
        )
        #expect(pairs.isEmpty)
    }

    @Test("Param-matches-carrier shape is filtered out (handled by IdempotenceTemplate)")
    func paramMatchesCarrierFilteredOut() {
        // mutating func formUnion(_:Counter) — flows through IdempotenceTemplate.
        let pairs = LiftedIdentityElementPairing.candidates(
            in: [lifted("formUnion", paramType: "Counter")],
            identities: [zeroIdentity()]
        )
        #expect(pairs.isEmpty)
    }

    @Test("Generic-specialization-stripped types pair")
    func genericSpecializationStripsForMatching() {
        let pairs = LiftedIdentityElementPairing.candidates(
            in: [lifted(paramType: "Int<NotReal>")],
            identities: [zeroIdentity(typeText: "Int")]
        )
        #expect(pairs.count == 1)
    }

    @Test("Multiple identities of same type produce multiple pairs (cross-product)")
    func multipleIdentitiesProduceCrossProduct() {
        let pairs = LiftedIdentityElementPairing.candidates(
            in: [lifted()],
            identities: [
                zeroIdentity(name: "zero"),
                zeroIdentity(name: "empty")
            ]
        )
        #expect(pairs.count == 2)
    }

    @Test("Pairs sort by (operation file/line, identity file/line) for byte-stable output")
    func pairsSortDeterministically() {
        let resolverA = valueSemanticResolver(carrier: "A")
        let resolverB = valueSemanticResolver(carrier: "B")
        let mutatorEarly = LiftedTransformation.lift(
            FunctionSummary(
                name: "increment",
                parameters: [Parameter(label: "by", internalName: "x", typeText: "Int", isInout: false)],
                returnTypeText: "Void",
                isThrows: false, isAsync: false, isMutating: true, isStatic: false,
                location: SourceLocation(file: "A.swift", line: 10, column: 1),
                containingTypeName: "A", bodySignals: .empty
            ),
            carrierKindResolver: resolverA
        )!
        let mutatorLate = LiftedTransformation.lift(
            FunctionSummary(
                name: "increment",
                parameters: [Parameter(label: "by", internalName: "x", typeText: "Int", isInout: false)],
                returnTypeText: "Void",
                isThrows: false, isAsync: false, isMutating: true, isStatic: false,
                location: SourceLocation(file: "Z.swift", line: 5, column: 1),
                containingTypeName: "B", bodySignals: .empty
            ),
            carrierKindResolver: resolverB
        )!
        let pairs = LiftedIdentityElementPairing.candidates(
            in: [mutatorLate, mutatorEarly],
            identities: [zeroIdentity()]
        )
        #expect(pairs[0].operation.originalSummary.location.file == "A.swift")
        #expect(pairs[1].operation.originalSummary.location.file == "Z.swift")
    }

    // MARK: - Template scoring

    @Test("Suggestion scores 30+40+5+10=85 → Strong on canonical pair")
    func suggestionScoresStrong() throws {
        let pair = LiftedIdentityElementPair(
            operation: lifted(),
            identity: zeroIdentity()
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(
            forLifted: pair,
            carrierKindResolver: valueSemanticResolver()
        ))
        #expect(suggestion.score.total == 85)
        #expect(suggestion.score.tier == .strong)
        #expect(suggestion.templateName == "identity-element")
    }

    @Test("liftedFromMutation +10 signal fires")
    func liftedSignalFires() throws {
        let pair = LiftedIdentityElementPair(
            operation: lifted(),
            identity: zeroIdentity()
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(
            forLifted: pair,
            carrierKindResolver: valueSemanticResolver()
        ))
        let signal = try #require(suggestion.score.signals.first {
            $0.kind == .liftedFromMutation
        })
        #expect(signal.weight == 10)
        #expect(signal.detail.contains("Counter.increment"))
    }

    @Test("Identity uses `identity-element-lifted|` prefix")
    func identityPrefix() throws {
        let pair = LiftedIdentityElementPair(
            operation: lifted(),
            identity: zeroIdentity()
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(
            forLifted: pair,
            carrierKindResolver: valueSemanticResolver()
        ))
        #expect(suggestion.identity.canonicalInput.hasPrefix("identity-element-lifted|"))
    }

    @Test("Two evidence rows: operation + identity constant")
    func twoEvidenceRows() throws {
        let pair = LiftedIdentityElementPair(
            operation: lifted(),
            identity: zeroIdentity()
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(
            forLifted: pair,
            carrierKindResolver: valueSemanticResolver()
        ))
        #expect(suggestion.evidence.count == 2)
        #expect(suggestion.evidence[0].displayName == "Counter.increment(by:)")
        #expect(suggestion.evidence[1].displayName == "zero")
    }

    @Test("Non-deterministic body in operation vetoes")
    func nonDeterministicVetoes() {
        let resolver = valueSemanticResolver()
        let summaryWithVeto = FunctionSummary(
            name: "increment",
            parameters: [
                Parameter(label: "by", internalName: "amount", typeText: "Int", isInout: false)
            ],
            returnTypeText: "Void",
            isThrows: false, isAsync: false, isMutating: true, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: "Counter",
            bodySignals: BodySignals(
                hasNonDeterministicCall: true,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: ["Date.init"]
            )
        )
        let lift = LiftedTransformation.lift(summaryWithVeto, carrierKindResolver: resolver)!
        let pair = LiftedIdentityElementPair(operation: lift, identity: zeroIdentity())
        #expect(IdentityElementTemplate.suggest(
            forLifted: pair,
            carrierKindResolver: resolver
        ) == nil)
    }
}
