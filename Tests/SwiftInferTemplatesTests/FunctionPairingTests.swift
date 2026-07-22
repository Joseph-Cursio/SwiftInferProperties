import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("FunctionPairing — module-scope type filter for cross-function templates")
struct FunctionPairingTests {

    @Test("Empty corpus produces no pairs")
    func emptyCorpus() {
        #expect(FunctionPairing.candidates(in: []).isEmpty)
    }

    @Test("Single function cannot pair with itself")
    func singleFunctionNoPair() {
        let summary = makeSummary(name: "encode", paramType: "MyType", returnType: "Data")
        #expect(FunctionPairing.candidates(in: [summary]).isEmpty)
    }

    @Test("Inverse type-shape pair is discovered")
    func inverseShapeMatched() throws {
        let encode = makeSummary(name: "encode", paramType: "MyType", returnType: "Data", line: 3)
        let decode = makeSummary(name: "decode", paramType: "Data", returnType: "MyType", line: 7)
        let pairs = FunctionPairing.candidates(in: [encode, decode])
        #expect(pairs.count == 1)
        let pair = try #require(pairs.first)
        #expect(pair.forward.name == "encode")
        #expect(pair.reverse.name == "decode")
    }

    @Test("Pair orientation is canonical by (file, line) regardless of input order")
    func canonicalOrientation() throws {
        let encode = makeSummary(name: "encode", paramType: "MyType", returnType: "Data", line: 3)
        let decode = makeSummary(name: "decode", paramType: "Data", returnType: "MyType", line: 7)
        let forwardFirst = FunctionPairing.candidates(in: [encode, decode])
        let reverseFirst = FunctionPairing.candidates(in: [decode, encode])
        #expect(forwardFirst == reverseFirst)
        #expect(try #require(forwardFirst.first).forward.name == "encode")
    }

    @Test("Mismatched type shapes do not pair")
    func mismatchedShapesNoPair() {
        let encode = makeSummary(name: "encode", paramType: "MyType", returnType: "Data")
        let unrelated = makeSummary(name: "decode", paramType: "Data", returnType: "Int")
        #expect(FunctionPairing.candidates(in: [encode, unrelated]).isEmpty)
    }

    @Test("inout parameter disqualifies a function from pairing")
    func inoutDisqualifies() {
        let encode = makeSummary(
            name: "encode",
            parameters: [Parameter(label: nil, internalName: "v", typeText: "MyType", isInout: true)],
            returnType: "Data"
        )
        let decode = makeSummary(name: "decode", paramType: "Data", returnType: "MyType")
        #expect(FunctionPairing.candidates(in: [encode, decode]).isEmpty)
    }

    @Test("mutating disqualifies a function from pairing")
    func mutatingDisqualifies() {
        let encode = makeSummary(
            name: "encode",
            paramType: "MyType",
            returnType: "Data",
            isMutating: true
        )
        let decode = makeSummary(name: "decode", paramType: "Data", returnType: "MyType")
        #expect(FunctionPairing.candidates(in: [encode, decode]).isEmpty)
    }

    @Test("Multi-parameter functions are excluded")
    func multiParameterExcluded() {
        let encode = makeSummary(
            name: "encode",
            parameters: [
                Parameter(label: nil, internalName: "v", typeText: "MyType", isInout: false),
                Parameter(label: "with", internalName: "options", typeText: "Options", isInout: false)
            ],
            returnType: "Data"
        )
        let decode = makeSummary(name: "decode", paramType: "Data", returnType: "MyType")
        #expect(FunctionPairing.candidates(in: [encode, decode]).isEmpty)
    }

    @Test("Same-type T -> T pair (auto-inverse) is captured exactly once")
    func sameTypePairCapturedOnce() {
        // Two T -> T functions can both invert each other; the pairing
        // engine emits the unordered pair once, oriented by source
        // location.
        let early = makeSummary(name: "f", paramType: "Int", returnType: "Int", line: 1)
        let late = makeSummary(name: "g", paramType: "Int", returnType: "Int", line: 2)
        let pairs = FunctionPairing.candidates(in: [early, late])
        #expect(pairs.count == 1)
        #expect(pairs.first?.forward.name == "f")
        #expect(pairs.first?.reverse.name == "g")
    }

    @Test("Three-way mutually-pairable corpus emits all three pairs once")
    func threeWayCombinatorics() {
        let alpha = makeSummary(name: "alpha", paramType: "Int", returnType: "Int", line: 1)
        let bravo = makeSummary(name: "bravo", paramType: "Int", returnType: "Int", line: 2)
        let charlie = makeSummary(name: "charlie", paramType: "Int", returnType: "Int", line: 3)
        let pairs = FunctionPairing.candidates(in: [alpha, bravo, charlie])
        #expect(pairs.count == 3)
        let forwards = pairs.map(\.forward.name)
        let reverses = pairs.map(\.reverse.name)
        #expect(forwards == ["alpha", "alpha", "bravo"])
        #expect(reverses == ["bravo", "charlie", "charlie"])
    }

    @Test("Pair list is sorted by forward (file, line) for byte-stable output")
    func sortedOutput() {
        let encodeA = makeSummary(name: "encode", paramType: "X", returnType: "Y", file: "A.swift", line: 10)
        let decodeA = makeSummary(name: "decode", paramType: "Y", returnType: "X", file: "A.swift", line: 20)
        let encodeB = makeSummary(name: "encode", paramType: "P", returnType: "Q", file: "B.swift", line: 5)
        let decodeB = makeSummary(name: "decode", paramType: "Q", returnType: "P", file: "B.swift", line: 15)
        let pairs = FunctionPairing.candidates(in: [encodeB, decodeB, encodeA, decodeA])
        #expect(pairs.count == 2)
        #expect(pairs[0].forward.location.file == "A.swift")
        #expect(pairs[1].forward.location.file == "B.swift")
    }

    // MARK: - Instance-method codec (0-param encode, domain = receiver)

    @Test("A 0-param instance-method encode pairs with a free/static decode (the codec recall gap)")
    func instanceMethodEncodePairs() throws {
        // `func base64EncodedString() -> String` on Blob reads as `Blob -> String`
        // (domain = the receiver), so it pairs with `decode(String) -> Blob`.
        // Previously invisible: the pairing keyed on `parameters.first`.
        let encode = makeSummary(
            name: "base64EncodedString",
            returnType: "String",
            containingType: "Blob",
            line: 3
        )
        let decode = makeSummary(name: "decode", paramType: "String", returnType: "Blob", line: 7)
        let pairs = FunctionPairing.candidates(in: [encode, decode])
        #expect(pairs.count == 1)
        let pair = try #require(pairs.first)
        #expect(pair.forward.name == "base64EncodedString")
        #expect(pair.reverse.name == "decode")
    }

    @Test("transformationDomain: receiver for a 0-param instance method, param otherwise, nil for static/free")
    func transformationDomainByShape() {
        let instance = makeSummary(name: "encode", returnType: "String", containingType: "Blob")
        #expect(FunctionPairing.transformationDomain(instance) == "Blob")

        let oneParam = makeSummary(name: "decode", paramType: "String", returnType: "Blob")
        #expect(FunctionPairing.transformationDomain(oneParam) == "String")

        // A 0-param *static* method has no receiver to stand in as the domain.
        let staticNullary = makeSummary(
            name: "make", returnType: "Blob", isStatic: true, containingType: "Blob"
        )
        #expect(FunctionPairing.transformationDomain(staticNullary) == nil)

        // A 0-param *free* function likewise has no domain.
        let freeNullary = makeSummary(name: "now", returnType: "Date")
        #expect(FunctionPairing.transformationDomain(freeNullary) == nil)
    }

    @Test("A 0-param static factory does NOT pair as an encode (no receiver domain)")
    func staticNullaryDoesNotPair() {
        let make = makeSummary(
            name: "make", returnType: "String", isStatic: true, containingType: "Blob"
        )
        let decode = makeSummary(name: "decode", paramType: "String", returnType: "Blob")
        #expect(FunctionPairing.candidates(in: [make, decode]).isEmpty)
    }

    // MARK: - Synthetic init-decode admission gate (road-test #10)

    @Test("A synthetic init-decode pairs with an encode whose name embeds its label stem")
    func initDecodePairsWhenLabelStems() throws {
        // `func base64EncodedString() -> String` on Blob (domain = receiver) +
        // a synthesized `init(base64Encoded:)` decode: "base64EncodedString"
        // embeds "base64Encoded", so the codec pair is admitted.
        let encode = makeSummary(
            name: "base64EncodedString", returnType: "String", containingType: "Blob", line: 5
        )
        let decode = makeSummary(
            name: "base64Encoded", paramType: "String", returnType: "Blob",
            isInitializer: true, containingType: "Blob", line: 1
        )
        let pairs = FunctionPairing.candidates(in: [encode, decode])
        #expect(pairs.count == 1)
        #expect(try #require(pairs.first).reverse.name == "base64EncodedString")
    }

    @Test("A synthetic init-decode does NOT pair with a same-typed getter whose name is unrelated")
    func initDecodeDoesNotPairWithUnrelatedGetter() {
        // The SwiftLintRuleStudio road-test noise: `CustomRuleConflict(ruleIdentifier:)`
        // type-matches every `CustomRuleConflict -> String` getter. Neither `id()`
        // nor `message()` embeds "ruleIdentifier", so no spurious codec pair forms.
        let initDecode = makeSummary(
            name: "ruleIdentifier", paramType: "String", returnType: "CustomRuleConflict",
            isInitializer: true, containingType: "CustomRuleConflict", line: 1
        )
        let identifier = makeSummary(
            name: "id", returnType: "String", containingType: "CustomRuleConflict", line: 5
        )
        let message = makeSummary(
            name: "message", returnType: "String", containingType: "CustomRuleConflict", line: 9
        )
        #expect(FunctionPairing.candidates(in: [initDecode, identifier, message]).isEmpty)
    }

    @Test("An unlabelled synthetic init (bare name \"init\") never pairs — no stem to match")
    func unlabelledInitNeverPairs() {
        let initDecode = makeSummary(
            name: "init", paramType: "String", returnType: "Blob",
            isInitializer: true, containingType: "Blob", line: 1
        )
        let encode = makeSummary(
            name: "serialize", returnType: "String", containingType: "Blob", line: 5
        )
        #expect(FunctionPairing.candidates(in: [initDecode, encode]).isEmpty)
    }

    @Test("The gate does not touch ordinary (non-initializer) pairs")
    func ordinaryPairsUnaffectedByGate() {
        // Two non-init functions with inverse type shape and unrelated names
        // still pair — naming stays a signal, not a pre-filter, for real pairs.
        let encode = makeSummary(name: "alpha", paramType: "MyType", returnType: "Data", line: 3)
        let decode = makeSummary(name: "omega", paramType: "Data", returnType: "MyType", line: 7)
        #expect(FunctionPairing.candidates(in: [encode, decode]).count == 1)
    }

    // MARK: - sharedDiscoverableGroup (M5.1)

    @Test("sharedDiscoverableGroup is nil when neither half is annotated")
    func sharedGroupNilForUnannotatedPair() {
        let pair = makePair(forwardGroup: nil, reverseGroup: nil)
        #expect(pair.sharedDiscoverableGroup == nil)
    }

    @Test("sharedDiscoverableGroup is nil when only one half is annotated")
    func sharedGroupNilForOneSidedAnnotation() {
        let onlyForward = makePair(forwardGroup: "codec", reverseGroup: nil)
        let onlyReverse = makePair(forwardGroup: nil, reverseGroup: "codec")
        #expect(onlyForward.sharedDiscoverableGroup == nil)
        #expect(onlyReverse.sharedDiscoverableGroup == nil)
    }

    @Test("sharedDiscoverableGroup is nil when groups disagree")
    func sharedGroupNilForMismatchedGroups() {
        let pair = makePair(forwardGroup: "codec", reverseGroup: "queue")
        #expect(pair.sharedDiscoverableGroup == nil)
    }

    @Test("sharedDiscoverableGroup returns the common group when both halves match")
    func sharedGroupMatchesForCommonGroup() {
        let pair = makePair(forwardGroup: "codec", reverseGroup: "codec")
        #expect(pair.sharedDiscoverableGroup == "codec")
    }
}

// Helpers live in an extension so the primary suite body stays under
// SwiftLint's `type_body_length` cap (extension bodies are exempt).
extension FunctionPairingTests {

    private func makePair(
        forwardGroup: String?,
        reverseGroup: String?
    ) -> FunctionPair {
        let forward = makeSummary(
            name: "encode",
            paramType: "MyType",
            returnType: "Data",
            line: 3,
            discoverableGroup: forwardGroup
        )
        let reverse = makeSummary(
            name: "decode",
            paramType: "Data",
            returnType: "MyType",
            line: 7,
            discoverableGroup: reverseGroup
        )
        return FunctionPair(forward: forward, reverse: reverse)
    }

    private func makeSummary(
        name: String,
        paramType: String? = nil,
        parameters explicitParameters: [Parameter]? = nil,
        returnType: String?,
        isMutating: Bool = false,
        isStatic: Bool = false,
        isInitializer: Bool = false,
        containingType: String? = nil,
        file: String = "Test.swift",
        line: Int = 1,
        discoverableGroup: String? = nil
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
            isMutating: isMutating,
            isStatic: isStatic,
            location: SourceLocation(file: file, line: line, column: 1),
            containingTypeName: containingType,
            bodySignals: .empty,
            discoverableGroup: discoverableGroup,
            isInitializer: isInitializer
        )
    }
}
