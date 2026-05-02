import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("InversePairTemplate — non-Equatable inverse, Possible-tier (M8.1)")
struct InversePairTemplateTests {

    // MARK: - Type-pattern + EquatableResolver gating

    @Test("Pair with Equatable T returns nil — RoundTripTemplate handles it")
    func equatableTDefersToRoundTrip() {
        let pair = makePair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "Int",
            forwardReturn: "Data"
        )
        // `Int` is in `EquatableResolver.curatedEquatableStdlib`.
        let resolver = EquatableResolver(typeDecls: [])
        let suggestion = InversePairTemplate.suggest(
            for: pair,
            equatableResolver: resolver
        )
        #expect(suggestion == nil)
    }

    @Test("Pair with .notEquatable T fires (curated non-Equatable shape)")
    func notEquatableTFires() {
        // Function-type parameter — `(Int) -> Int` is in the curated
        // non-Equatable shape list (textual `->` detector). T can't host
        // value equality, so RoundTripTemplate's `==` veto holds.
        let pair = makePair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "(Int) -> Int",
            forwardReturn: "Data"
        )
        let resolver = EquatableResolver(typeDecls: [])
        let suggestion = InversePairTemplate.suggest(
            for: pair,
            equatableResolver: resolver
        )
        #expect(suggestion != nil)
        #expect(suggestion?.templateName == "inverse-pair")
    }

    @Test("Pair with .unknown T fires (corpus type without Equatable evidence)")
    func unknownTFires() {
        // `MyType` isn't in the curated stdlib list and isn't declared
        // in the corpus typeDecls — resolver returns `.unknown`.
        let pair = makePair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let resolver = EquatableResolver(typeDecls: [])
        let suggestion = InversePairTemplate.suggest(
            for: pair,
            equatableResolver: resolver
        )
        #expect(suggestion != nil)
        #expect(suggestion?.templateName == "inverse-pair")
    }

    @Test("nil resolver fires (test/programmatic fallback)")
    func nilResolverFires() {
        let pair = makePair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion != nil)
        #expect(suggestion?.templateName == "inverse-pair")
    }

    @Test("Corpus-declared Equatable type defers to RoundTripTemplate")
    func corpusEquatableDefers() {
        let pair = makePair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "Money",
            forwardReturn: "Data"
        )
        let resolver = EquatableResolver(typeDecls: [
            TypeDecl(
                name: "Money",
                kind: .struct,
                inheritedTypes: ["Equatable"],
                location: SourceLocation(file: "Money.swift", line: 1, column: 1)
            )
        ])
        let suggestion = InversePairTemplate.suggest(
            for: pair,
            equatableResolver: resolver
        )
        #expect(suggestion == nil)
    }

    // MARK: - Scoring: Possible tier per PRD §5.8 M8 row

    @Test("Type pattern alone scores 25 (Possible)")
    func typeShapeAlone() {
        let pair = makePair(
            forwardName: "transform",
            reverseName: "untransform",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion?.score.total == 25)
        #expect(suggestion?.score.tier == .possible)
    }

    @Test("Curated inverse name pair scores 35 (still Possible)")
    func curatedInverseNamePair() {
        let pair = makePair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion?.score.total == 35)
        #expect(suggestion?.score.tier == .possible)
    }

    @Test("Curated match works regardless of pair orientation")
    func curatedMatchOrientationInsensitive() {
        let direct = makePair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let swapped = makePair(
            forwardName: "decode",
            reverseName: "encode",
            forwardParam: "Data",
            forwardReturn: "MyType"
        )
        // The .swapped case has T = Data which IS Equatable — defers
        // to RoundTrip when a resolver is supplied. With no resolver,
        // both fire (default-fire fallback per the suggest signature).
        #expect(InversePairTemplate.suggest(for: direct)?.score.total == 35)
        #expect(InversePairTemplate.suggest(for: swapped)?.score.total == 35)
    }

    @Test("Project-vocabulary inverse pair contributes the +10 name signal")
    func projectVocabularyMatch() {
        let pair = makePair(
            forwardName: "enqueue",
            reverseName: "dequeue",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let vocab = Vocabulary(
            inversePairs: [InversePair(forward: "enqueue", reverse: "dequeue")]
        )
        let suggestion = InversePairTemplate.suggest(for: pair, vocabulary: vocab)
        #expect(suggestion?.score.total == 35)
        let why = suggestion?.explainability.whySuggested.joined(separator: "\n") ?? ""
        #expect(why.contains("Project-vocabulary inverse pair match: enqueue/dequeue"))
    }

    // MARK: - Vetoes

    @Test("Non-deterministic API in either body suppresses the suggestion")
    func nonDeterministicVeto() {
        let pair = makePair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data",
            forwardBodySignals: BodySignals(
                hasNonDeterministicCall: true,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: ["Date()"]
            )
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        #expect(suggestion == nil)
    }

    // MARK: - Identity

    @Test("Identity hash is template-prefixed and orientation-agnostic")
    func identityHashIsOrientationAgnostic() {
        let direct = makePair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let swapped = makePair(
            forwardName: "decode",
            reverseName: "encode",
            forwardParam: "Data",
            forwardReturn: "MyType"
        )
        let directIdentity = InversePairTemplate.suggest(for: direct)?.identity
        let swappedIdentity = InversePairTemplate.suggest(for: swapped)?.identity
        #expect(directIdentity == swappedIdentity)
    }

    @Test("Identity hash differs from RoundTripTemplate's for the same pair")
    func identityHashDistinctFromRoundTrip() {
        // Same pair shape; both templates would normally fire (T unknown).
        // Their identity hashes must differ so the decisions / baseline
        // files can carry independent records per template.
        let pair = makePair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let inverseIdentity = InversePairTemplate.suggest(for: pair)?.identity
        let roundTripIdentity = RoundTripTemplate.suggest(for: pair)?.identity
        #expect(inverseIdentity != roundTripIdentity)
    }

    // MARK: - Explainability

    @Test("Explainability block carries the four M8.1 caveats")
    func explainabilityCaveats() {
        let pair = makePair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        let caveats = suggestion?.explainability.whyMightBeWrong.joined(separator: "\n") ?? ""
        #expect(caveats.contains("Non-Equatable T means SwiftInfer cannot sample-verify"))
        #expect(caveats.contains("TestLifter corroboration not yet wired"))
        #expect(caveats.contains("Possible-tier by default"))
        #expect(caveats.contains("RoundTripTemplate (M1.4) handles this case"))
    }

    @Test("Type-symmetry signal detail mentions the non-Equatable T qualifier")
    func typeSymmetryDetailMentionsNonEquatable() {
        let pair = makePair(
            forwardName: "transform",
            reverseName: "untransform",
            forwardParam: "MyType",
            forwardReturn: "Data"
        )
        let suggestion = InversePairTemplate.suggest(for: pair)
        let why = suggestion?.explainability.whySuggested.joined(separator: "\n") ?? ""
        #expect(why.contains("(non-Equatable T)"))
    }

    // MARK: - Fixtures

    private func makePair(
        forwardName: String,
        reverseName: String,
        forwardParam: String,
        forwardReturn: String,
        forwardBodySignals: BodySignals = .empty,
        reverseBodySignals: BodySignals = .empty
    ) -> FunctionPair {
        let forward = FunctionSummary(
            name: forwardName,
            parameters: [Parameter(label: nil, internalName: "x", typeText: forwardParam, isInout: false)],
            returnTypeText: forwardReturn,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: forwardBodySignals
        )
        let reverse = FunctionSummary(
            name: reverseName,
            parameters: [Parameter(label: nil, internalName: "x", typeText: forwardReturn, isInout: false)],
            returnTypeText: forwardParam,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 5, column: 1),
            containingTypeName: nil,
            bodySignals: reverseBodySignals
        )
        return FunctionPair(forward: forward, reverse: reverse)
    }
}
