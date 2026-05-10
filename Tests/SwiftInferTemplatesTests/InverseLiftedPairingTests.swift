import PropertyLawCore
import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("InverseLiftedPairing — V1.19.D mutating add/remove pairing")
struct InverseLiftedPairingTests {

    // MARK: - Helpers

    private func valueSemanticResolver(carrier: String = "Bag") -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: carrier,
                kind: .struct,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "items", typeName: "[Int]")]
            )
        ])
    }

    private func mutator(
        _ name: String,
        paramType: String = "Int",
        carrier: String = "Bag",
        line: Int = 1,
        bodySignals: BodySignals = .empty
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(label: nil, internalName: "x", typeText: paramType, isInout: false)
            ],
            returnTypeText: "Void",
            isThrows: false,
            isAsync: false,
            isMutating: true,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: line, column: 1),
            containingTypeName: carrier,
            bodySignals: bodySignals
        )
    }

    private func lifted(
        _ name: String,
        paramType: String = "Int",
        carrier: String = "Bag",
        line: Int = 1,
        bodySignals: BodySignals = .empty
    ) -> LiftedTransformation {
        LiftedTransformation.lift(
            mutator(name, paramType: paramType, carrier: carrier, line: line, bodySignals: bodySignals),
            carrierKindResolver: valueSemanticResolver(carrier: carrier)
        )!
    }

    // MARK: - Curated pairs

    @Test("add/remove on the same carrier pairs (canonical example)")
    func addRemovePair() {
        let pairs = InverseLiftedPairing.candidates(in: [
            lifted("add"),
            lifted("remove")
        ])
        #expect(pairs.count == 1)
        #expect(pairs.first?.forward.originalSummary.name == "add")
        #expect(pairs.first?.reverse.originalSummary.name == "remove")
    }

    @Test("Pair is canonical-orientation-stable (lex-smaller name is forward)")
    func canonicalOrientation() {
        // Input order shouldn't matter — orientation is always lex-smaller-first.
        let pairsA = InverseLiftedPairing.candidates(in: [
            lifted("add"),
            lifted("remove")
        ])
        let pairsB = InverseLiftedPairing.candidates(in: [
            lifted("remove"),
            lifted("add")
        ])
        #expect(pairsA.first?.forward.originalSummary.name == "add")
        #expect(pairsB.first?.forward.originalSummary.name == "add")
    }

    @Test("All curated pair names produce a pair when both halves exist")
    func allCuratedPairs() {
        for namePair in InverseLiftedPairing.curatedPairs {
            let pairs = InverseLiftedPairing.candidates(in: [
                lifted(namePair.lhs),
                lifted(namePair.rhs)
            ])
            #expect(pairs.count == 1, "expected pair for \(namePair.lhs)/\(namePair.rhs)")
        }
    }

    @Test("Project-vocabulary inverse pair admits via Vocabulary.inversePairs")
    func projectVocabularyPair() {
        let vocab = Vocabulary(inversePairs: [InversePair(forward: "ingest", reverse: "expel")])
        let pairs = InverseLiftedPairing.candidates(
            in: [lifted("ingest"), lifted("expel")],
            vocabulary: vocab
        )
        #expect(pairs.count == 1)
    }

    // MARK: - Filters

    @Test("Different carriers don't pair (Set.insert + Array.remove)")
    func differentCarriersDoNotPair() {
        let pairs = InverseLiftedPairing.candidates(in: [
            lifted("insert", carrier: "Set"),
            lifted("remove", carrier: "Array")
        ])
        #expect(pairs.isEmpty)
    }

    @Test("Mismatched parameter types don't pair")
    func mismatchedParamTypes() {
        let pairs = InverseLiftedPairing.candidates(in: [
            lifted("add", paramType: "Int"),
            lifted("remove", paramType: "String")
        ])
        #expect(pairs.isEmpty)
    }

    @Test("Non-inverse name pair doesn't pair (`add` + `merge`)")
    func nonInverseNamesDoNotPair() {
        let pairs = InverseLiftedPairing.candidates(in: [
            lifted("add"),
            lifted("merge")
        ])
        #expect(pairs.isEmpty)
    }

    @Test("No-param mutators don't pair (no `x` to add or remove)")
    func noParamDoNotPair() {
        let resolver = valueSemanticResolver()
        let summaryAdd = FunctionSummary(
            name: "add", parameters: [], returnTypeText: "Void",
            isThrows: false, isAsync: false, isMutating: true, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: "Bag", bodySignals: .empty
        )
        let summaryRemove = FunctionSummary(
            name: "remove", parameters: [], returnTypeText: "Void",
            isThrows: false, isAsync: false, isMutating: true, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 2, column: 1),
            containingTypeName: "Bag", bodySignals: .empty
        )
        let liftAdd = LiftedTransformation.lift(summaryAdd, carrierKindResolver: resolver)!
        let liftRemove = LiftedTransformation.lift(summaryRemove, carrierKindResolver: resolver)!
        #expect(InverseLiftedPairing.candidates(in: [liftAdd, liftRemove]).isEmpty)
    }

    @Test("Pairs sort by forward location for byte-stable output")
    func pairsSortDeterministically() {
        let pairs = InverseLiftedPairing.candidates(in: [
            lifted("add", carrier: "B", line: 50),
            lifted("remove", carrier: "B", line: 60),
            lifted("add", carrier: "A", line: 100),
            lifted("remove", carrier: "A", line: 110)
        ])
        #expect(pairs.count == 2)
        // Sorted by forward.location.line — A's forward is at line 100,
        // B's forward is at line 50. So B's pair sorts first.
        #expect(pairs[0].forward.carrier == "B")
        #expect(pairs[1].forward.carrier == "A")
    }

    @Test("Same carrier with multiple add+remove pairs produces one pair per match")
    func multipleHomogeneousPairs() {
        // Two `add`s + two `remove`s on Bag — cross-product is 4 pairs.
        let pairs = InverseLiftedPairing.candidates(in: [
            lifted("add", line: 10),
            lifted("add", line: 20),
            lifted("remove", line: 30),
            lifted("remove", line: 40)
        ])
        #expect(pairs.count == 4)
    }
}

@Suite("InversePairTemplate — V1.19.D lift admission scoring")
struct InversePairTemplateLiftedTests {

    private func valueSemanticResolver(carrier: String = "Bag") -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: [
            TypeDecl(
                name: carrier,
                kind: .struct,
                inheritedTypes: [],
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                storedMembers: [StoredMember(name: "items", typeName: "[Int]")]
            )
        ])
    }

    private func makePair(
        forwardName: String = "add",
        reverseName: String = "remove",
        bodySignalsForward: BodySignals = .empty,
        bodySignalsReverse: BodySignals = .empty
    ) -> LiftedInversePair {
        let resolver = valueSemanticResolver()
        let forward = LiftedTransformation.lift(
            FunctionSummary(
                name: forwardName,
                parameters: [
                    Parameter(label: nil, internalName: "x", typeText: "Int", isInout: false)
                ],
                returnTypeText: "Void",
                isThrows: false, isAsync: false, isMutating: true, isStatic: false,
                location: SourceLocation(file: "Test.swift", line: 1, column: 1),
                containingTypeName: "Bag",
                bodySignals: bodySignalsForward
            ),
            carrierKindResolver: resolver
        )!
        let reverse = LiftedTransformation.lift(
            FunctionSummary(
                name: reverseName,
                parameters: [
                    Parameter(label: nil, internalName: "x", typeText: "Int", isInout: false)
                ],
                returnTypeText: "Void",
                isThrows: false, isAsync: false, isMutating: true, isStatic: false,
                location: SourceLocation(file: "Test.swift", line: 2, column: 1),
                containingTypeName: "Bag",
                bodySignals: bodySignalsReverse
            ),
            carrierKindResolver: resolver
        )!
        return LiftedInversePair(
            forward: forward,
            reverse: reverse,
            pairName: LiftedInversePair.NamePair(lhs: forwardName, rhs: reverseName)
        )
    }

    // MARK: - Score baseline

    @Test("Canonical add/remove pair scores 25+10+5+10=50 → Likely")
    func canonicalScoresLikely() throws {
        let suggestion = try #require(InversePairTemplate.suggest(
            forLifted: makePair(),
            carrierKindResolver: valueSemanticResolver()
        ))
        #expect(suggestion.score.total == 50)
        #expect(suggestion.score.tier == .likely)
        #expect(suggestion.templateName == "inverse-pair")
    }

    @Test("liftedFromMutation +10 signal fires with both halves named")
    func liftedSignalNamesBothHalves() throws {
        let suggestion = try #require(InversePairTemplate.suggest(
            forLifted: makePair(),
            carrierKindResolver: valueSemanticResolver()
        ))
        let signal = try #require(suggestion.score.signals.first {
            $0.kind == .liftedFromMutation
        })
        #expect(signal.weight == 10)
        #expect(signal.detail.contains("Bag.add"))
        #expect(signal.detail.contains("Bag.remove"))
    }

    @Test("Type-shape signal fires at +25 (parallel to non-lifted InversePair baseline)")
    func typeShapeFiresAt25() throws {
        let suggestion = try #require(InversePairTemplate.suggest(
            forLifted: makePair(),
            carrierKindResolver: valueSemanticResolver()
        ))
        let signal = try #require(suggestion.score.signals.first {
            $0.kind == .typeSymmetrySignature
        })
        #expect(signal.weight == 25)
    }

    @Test("Naming signal renders the matched curated pair name")
    func namingSignalDetail() throws {
        let suggestion = try #require(InversePairTemplate.suggest(
            forLifted: makePair(),
            carrierKindResolver: valueSemanticResolver()
        ))
        let signal = try #require(suggestion.score.signals.first {
            $0.kind == .exactNameMatch
        })
        #expect(signal.detail.contains("add/remove"))
    }

    // MARK: - Vetoes

    @Test("Non-deterministic body in EITHER half vetoes")
    func nonDeterministicVetoesEitherHalf() {
        let pair = makePair(bodySignalsForward: BodySignals(
            hasNonDeterministicCall: true,
            hasSelfComposition: false,
            nonDeterministicAPIsDetected: ["Date.init"]
        ))
        #expect(InversePairTemplate.suggest(
            forLifted: pair,
            carrierKindResolver: valueSemanticResolver()
        ) == nil)
    }

    @Test("Non-deterministic body in REVERSE half vetoes too")
    func nonDeterministicVetoesReverseHalf() {
        let pair = makePair(bodySignalsReverse: BodySignals(
            hasNonDeterministicCall: true,
            hasSelfComposition: false,
            nonDeterministicAPIsDetected: ["Date.init"]
        ))
        #expect(InversePairTemplate.suggest(
            forLifted: pair,
            carrierKindResolver: valueSemanticResolver()
        ) == nil)
    }

    // MARK: - Identity + evidence

    @Test("Identity uses `inverse-pair-lifted|` prefix and is orientation-insensitive")
    func identityPrefix() throws {
        let suggestion = try #require(InversePairTemplate.suggest(
            forLifted: makePair(),
            carrierKindResolver: valueSemanticResolver()
        ))
        #expect(suggestion.identity.canonicalInput.hasPrefix("inverse-pair-lifted|"))
    }

    @Test("Two evidence rows: forward (add) + reverse (remove)")
    func twoEvidenceRows() throws {
        let suggestion = try #require(InversePairTemplate.suggest(
            forLifted: makePair(),
            carrierKindResolver: valueSemanticResolver()
        ))
        #expect(suggestion.evidence.count == 2)
        #expect(suggestion.evidence[0].displayName == "Bag.add(_:)")
        #expect(suggestion.evidence[1].displayName == "Bag.remove(_:)")
    }
}
