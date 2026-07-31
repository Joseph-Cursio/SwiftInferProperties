import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// `Self` resolution in the pairing type filter.
///
/// `Self` is the one type spelling whose meaning depends on where it was
/// written, so comparing it as text makes every `Self -> Self` method the
/// inverse of every other one, across entirely unrelated types. Split from
/// `FunctionPairingTests` on the file-length cap.
@Suite("FunctionPairing — `Self` resolution")
struct FunctionPairingSelfResolutionTests {

    /// The measured defect: `Decisions.merge` and `InteractionDecisions.merge`
    /// are both spelled `(Self) -> Self`, so a textual comparison makes each the
    /// inverse of the other. On this repo's own corpus that built the complete
    /// graph over six unrelated types — 14 surfaced suggestions, 0 same-type.
    /// A merge has no inverse at all.
    @Test("two `Self -> Self` methods on DIFFERENT types do not pair")
    func selfSpellingDoesNotPairAcrossTypes() {
        let decisions = makeSummary(
            name: "merge", paramType: "Self", returnType: "Self", containingType: "Decisions", line: 3
        )
        let interaction = makeSummary(
            name: "merge", paramType: "Self", returnType: "Self",
            containingType: "InteractionDecisions", line: 7
        )
        #expect(FunctionPairing.candidates(in: [decisions, interaction]).isEmpty)
    }

    /// The clique is the whole point: N such types must produce zero pairs, not
    /// C(N,2). Guards against a fix that only separates two types.
    @Test("six `Self -> Self` types produce no pairs at all, not C(6,2)")
    func selfSpellingCliqueDoesNotForm() {
        let owners = [
            "Decisions", "InteractionDecisions", "PostAcceptanceOutcomeLog",
            "InteractionIndexEntry", "SemanticIndexEntry", "VerifyEvidenceLog"
        ]
        let summaries = owners.enumerated().map { index, owner in
            makeSummary(
                name: "merge", paramType: "Self", returnType: "Self",
                containingType: owner, file: "\(owner).swift", line: index + 1
            )
        }
        #expect(FunctionPairing.candidates(in: summaries).isEmpty)
    }

    /// The resolution must not over-reach: a genuine same-type inverse pair
    /// written with `Self` still pairs, because both sides resolve to the same
    /// owner. Without this the fix would trade false positives for false
    /// negatives.
    @Test("a genuine `Self`-spelled pair on ONE type still pairs")
    func selfSpellingStillPairsWithinOneType() throws {
        let boxed = makeSummary(
            name: "boxed", paramType: "Self", returnType: "Wrapper", containingType: "Wrapper", line: 3
        )
        let unboxed = makeSummary(
            name: "unboxed", paramType: "Wrapper", returnType: "Self", containingType: "Wrapper", line: 7
        )
        let pairs = FunctionPairing.candidates(in: [boxed, unboxed])
        #expect(pairs.count == 1)
        #expect(try #require(pairs.first).forward.name == "boxed")
    }

    /// Nested spellings carry the same ambiguity — `[Self]` on two types is two
    /// different array types — so resolution is whole-word, not exact-match.
    @Test("nested `Self` spellings resolve too")
    func nestedSelfSpellingsResolve() {
        let lhs = makeSummary(
            name: "explode", paramType: "Self", returnType: "[Self]", containingType: "Alpha", line: 3
        )
        let rhs = makeSummary(
            name: "collapse", paramType: "[Self]", returnType: "Self", containingType: "Beta", line: 7
        )
        #expect(FunctionPairing.candidates(in: [lhs, rhs]).isEmpty)
    }

    /// Whole-word: a type whose name merely CONTAINS "Self" is not a `Self`
    /// spelling and must be left alone.
    @Test("resolution is whole-word — `SelfDescribing` is untouched")
    func resolutionIsWholeWord() {
        let summary = makeSummary(
            name: "wrap", paramType: "SelfDescribing", returnType: "MySelf", containingType: "Owner"
        )
        #expect(FunctionPairing.resolvingSelf("SelfDescribing", declaredIn: summary) == "SelfDescribing")
        #expect(FunctionPairing.resolvingSelf("MySelf", declaredIn: summary) == "MySelf")
        #expect(FunctionPairing.resolvingSelf("Self", declaredIn: summary) == "Owner")
        #expect(FunctionPairing.resolvingSelf("[Self]", declaredIn: summary) == "[Owner]")
        #expect(FunctionPairing.resolvingSelf("Self?", declaredIn: summary) == "Owner?")
        #expect(FunctionPairing.resolvingSelf("Set<Self>", declaredIn: summary) == "Set<Owner>")
    }

    /// A free function has no declaring type, so there is nothing to resolve
    /// against and the text must pass through unchanged rather than crash or
    /// silently blank out.
    @Test("a free function's type text passes through unchanged")
    func freeFunctionPassesThrough() {
        let free = makeSummary(name: "normalize", paramType: "Self", returnType: "Self")
        #expect(FunctionPairing.resolvingSelf("Self", declaredIn: free) == "Self")
    }

    private func makeSummary(
        name: String,
        paramType: String? = nil,
        returnType: String?,
        containingType: String? = nil,
        file: String = "Test.swift",
        line: Int = 1
    ) -> FunctionSummary {
        let parameters = paramType.map {
            [Parameter(label: nil, internalName: "value", typeText: $0, isInout: false)]
        } ?? []
        return FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: file, line: line, column: 1),
            containingTypeName: containingType,
            bodySignals: .empty,
            discoverableGroup: nil,
            isInitializer: false
        )
    }
}
