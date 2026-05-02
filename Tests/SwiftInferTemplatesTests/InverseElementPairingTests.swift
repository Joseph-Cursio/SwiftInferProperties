import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("InverseElementPairing — type + curated-name pre-filter (M8.3)")
struct InverseElementPairingTests {

    // MARK: - Curated name + type filter

    @Test("Binary op + curated unary inverse on same type pairs")
    func binaryOpPlusCuratedInversePairs() {
        let merge = makeBinaryOp(name: "merge", typeText: "AdditiveInt")
        let negate = makeUnary(name: "negate", typeText: "AdditiveInt")
        let pairs = InverseElementPairing.candidates(in: [merge, negate])
        #expect(pairs.count == 1)
        #expect(pairs.first?.operation.name == "merge")
        #expect(pairs.first?.inverse.name == "negate")
    }

    @Test("Unary with non-inverse name is filtered out")
    func nonInverseNameFiltered() {
        let merge = makeBinaryOp(name: "merge", typeText: "AdditiveInt")
        let transform = makeUnary(name: "transform", typeText: "AdditiveInt")
        let pairs = InverseElementPairing.candidates(in: [merge, transform])
        #expect(pairs.isEmpty)
    }

    @Test("Type mismatch — unary inverse on a different type doesn't pair")
    func typeMismatchFilters() {
        let merge = makeBinaryOp(name: "merge", typeText: "AdditiveInt")
        let negateOther = makeUnary(name: "negate", typeText: "MultiplicativeFloat")
        let pairs = InverseElementPairing.candidates(in: [merge, negateOther])
        #expect(pairs.isEmpty)
    }

    @Test("Binary op alone (no inverse candidate) yields no pair")
    func binaryOpAloneYieldsNoPair() {
        let merge = makeBinaryOp(name: "merge", typeText: "AdditiveInt")
        let pairs = InverseElementPairing.candidates(in: [merge])
        #expect(pairs.isEmpty)
    }

    @Test("Unary inverse alone (no binary op) yields no pair")
    func unaryInverseAloneYieldsNoPair() {
        let negate = makeUnary(name: "negate", typeText: "AdditiveInt")
        let pairs = InverseElementPairing.candidates(in: [negate])
        #expect(pairs.isEmpty)
    }

    // MARK: - Each curated verb pairs

    @Test("Every curated verb name pairs successfully")
    func everyCuratedVerbPairs() {
        let merge = makeBinaryOp(name: "merge", typeText: "T")
        for verb in InverseElementPairing.curatedInverseVerbs {
            let inverse = makeUnary(name: verb, typeText: "T")
            let pairs = InverseElementPairing.candidates(in: [merge, inverse])
            #expect(pairs.count == 1, "Expected pair for curated verb '\(verb)'")
        }
    }

    // MARK: - Project-vocabulary extension

    @Test("Project-vocabulary inverseElementVerbs entry pairs")
    func projectVocabularyExtension() {
        let merge = makeBinaryOp(name: "merge", typeText: "Polygon")
        let mirror = makeUnary(name: "mirror", typeText: "Polygon")
        // `mirror` isn't in the curated list — only the project vocab.
        #expect(
            InverseElementPairing.curatedInverseVerbs.contains("mirror") == false
        )
        let pairsWithoutVocab = InverseElementPairing.candidates(in: [merge, mirror])
        #expect(pairsWithoutVocab.isEmpty)
        let vocab = Vocabulary(inverseElementVerbs: ["mirror"])
        let pairsWithVocab = InverseElementPairing.candidates(
            in: [merge, mirror],
            vocabulary: vocab
        )
        #expect(pairsWithVocab.count == 1)
        #expect(pairsWithVocab.first?.inverse.name == "mirror")
    }

    // MARK: - Multi-arity

    @Test("Multiple binary ops on same type produce one pair per op")
    func multipleOpsYieldMultiplePairs() {
        let plus = makeBinaryOp(name: "plus", typeText: "AdditiveInt")
        let merge = makeBinaryOp(name: "merge", typeText: "AdditiveInt")
        let negate = makeUnary(name: "negate", typeText: "AdditiveInt")
        let pairs = InverseElementPairing.candidates(in: [plus, merge, negate])
        #expect(pairs.count == 2)
        let opNames = Set(pairs.map(\.operation.name))
        #expect(opNames == ["plus", "merge"])
    }

    @Test("Multiple inverse candidates produce one pair per inverse")
    func multipleInversesYieldMultiplePairs() {
        let merge = makeBinaryOp(name: "merge", typeText: "AdditiveInt")
        let negate = makeUnary(name: "negate", typeText: "AdditiveInt")
        let inverse = makeUnary(name: "inverse", typeText: "AdditiveInt")
        let pairs = InverseElementPairing.candidates(in: [merge, negate, inverse])
        #expect(pairs.count == 2)
        let inverseNames = Set(pairs.map(\.inverse.name))
        #expect(inverseNames == ["negate", "inverse"])
    }

    // MARK: - Shape rejection

    @Test("Mutating inverse is rejected")
    func mutatingInverseRejected() {
        let merge = makeBinaryOp(name: "merge", typeText: "AdditiveInt")
        let negate = makeUnary(
            name: "negate",
            typeText: "AdditiveInt",
            isMutating: true
        )
        let pairs = InverseElementPairing.candidates(in: [merge, negate])
        #expect(pairs.isEmpty)
    }

    @Test("Inout inverse parameter is rejected")
    func inoutInverseRejected() {
        let merge = makeBinaryOp(name: "merge", typeText: "AdditiveInt")
        let negate = FunctionSummary(
            name: "negate",
            parameters: [
                Parameter(label: nil, internalName: "x", typeText: "AdditiveInt", isInout: true)
            ],
            returnTypeText: "AdditiveInt",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "X.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let pairs = InverseElementPairing.candidates(in: [merge, negate])
        #expect(pairs.isEmpty)
    }

    @Test("Two-arg inverse-named function rejected (must be unary)")
    func twoArgInverseNameRejected() {
        let merge = makeBinaryOp(name: "merge", typeText: "AdditiveInt")
        let negate = makeBinaryOp(name: "negate", typeText: "AdditiveInt")
        let pairs = InverseElementPairing.candidates(in: [merge, negate])
        // Even though the binary-op `negate` has the right name, it doesn't
        // match the unary T → T shape; the merge-merge pair would never
        // surface because every binary op is its own inverse-mate.
        #expect(pairs.isEmpty)
    }

    // MARK: - Determinism

    @Test("Pairs are sorted by (op file, op line, inverse file, inverse line)")
    func pairsAreDeterministicallySorted() {
        let firstOp = makeBinaryOp(name: "alpha", typeText: "T", line: 30)
        let secondOp = makeBinaryOp(name: "beta", typeText: "T", line: 10)
        let firstInv = makeUnary(name: "negate", typeText: "T", line: 40)
        let secondInv = makeUnary(name: "inverse", typeText: "T", line: 20)
        let pairs = InverseElementPairing.candidates(in: [firstOp, secondOp, firstInv, secondInv])
        #expect(pairs.count == 4)
        // Op order: secondOp (line 10) before firstOp (line 30).
        // Within each op: secondInv (line 20) before firstInv (line 40).
        #expect(pairs.map(\.operation.name) == ["beta", "beta", "alpha", "alpha"])
        #expect(pairs.map(\.inverse.name) == ["inverse", "negate", "inverse", "negate"])
    }

    // MARK: - Fixtures

    private func makeBinaryOp(
        name: String,
        typeText: String,
        line: Int = 1
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(label: nil, internalName: "lhs", typeText: typeText, isInout: false),
                Parameter(label: nil, internalName: "rhs", typeText: typeText, isInout: false)
            ],
            returnTypeText: typeText,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "X.swift", line: line, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }

    private func makeUnary(
        name: String,
        typeText: String,
        line: Int = 5,
        isMutating: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(label: nil, internalName: "value", typeText: typeText, isInout: false)
            ],
            returnTypeText: typeText,
            isThrows: false,
            isAsync: false,
            isMutating: isMutating,
            isStatic: false,
            location: SourceLocation(file: "X.swift", line: line, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }
}
