@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// A nested type in the PARAMETER position must be qualified in the emitted type
/// annotation, not only in the values the strategist composes.
///
/// `e5731a9` qualified the generator CARRIER and stopped there. The gap stayed hidden
/// because the two coincide for a unary law — it took a four-argument predicate whose
/// third parameter is `RefutedExpectation.Coverage` to separate them, and the stub then
/// read `Generator<Coverage, …>` beside `Gen.always(RefutedExpectation.Coverage.…)`:
/// values right, annotation wrong, on adjacent lines.
@Suite("Nested carrier qualification reaches parameter types, not just the carrier")
struct NestedParameterQualificationTests {

    private func shapes(_ names: [String]) -> [String: IndexedTypeShape] {
        Dictionary(uniqueKeysWithValues: names.map { name in
            (name, IndexedTypeShape(name: name, kind: .struct, inheritedTypes: [], hasUserGen: false))
        })
    }

    @Test("a nested parameter type resolves to its qualified path")
    func nestedParameterIsQualified() {
        let all = shapes(["RefutedExpectation.Coverage", "RefutedExpectation"])
        #expect(
            SwiftInferCommand.Verify.qualifyingNestedCarrier("Coverage", in: all)
                == "RefutedExpectation.Coverage"
        )
    }

    /// The regression that shipped: the map is keyed by qualified name, so the bare key
    /// misses and the strategist derives with no shape at all.
    @Test("the qualified key is the one present in allShapes; the bare key is absent")
    func lookupKeyIsQualified() {
        let all = shapes(["RefutedExpectation.Coverage"])
        #expect(all["Coverage"] == nil, "a bare lookup misses every nested type")
        #expect(all["RefutedExpectation.Coverage"] != nil)
    }

    /// Ambiguity must keep the status quo rather than guess — the same rule the carrier
    /// path follows, and the reason `Visitor` (7 declaration sites) stays declined.
    @Test("an ambiguous parameter name is left bare")
    func ambiguousParameterIsLeftAlone() {
        let all = shapes(["A.Visitor", "B.Visitor", "C.Visitor"])
        #expect(SwiftInferCommand.Verify.qualifyingNestedCarrier("Visitor", in: all) == "Visitor")
    }

    /// A top-level parameter type is already a key and must pass through untouched, or
    /// every ordinary law would acquire a spurious prefix.
    @Test("a top-level parameter type is untouched")
    func topLevelParameterIsUntouched() {
        let all = shapes(["Suggestion", "Wrapper.Suggestion"])
        #expect(SwiftInferCommand.Verify.qualifyingNestedCarrier("Suggestion", in: all) == "Suggestion")
    }

    /// Composed spellings are shapes the strategist builds, not names to look up.
    @Test(
        "composed parameter spellings are not rewritten",
        arguments: ["[Coverage]", "Coverage?", "Box<Coverage>"]
    )
    func composedParameterSpellingsAreUntouched(spelling: String) {
        let all = shapes(["RefutedExpectation.Coverage"])
        #expect(SwiftInferCommand.Verify.qualifyingNestedCarrier(spelling, in: all) == spelling)
    }
}
