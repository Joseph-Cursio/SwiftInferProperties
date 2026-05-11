import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

/// V1.29.B — algebraic-family-mismatch veto on IdentityElementTemplate.
/// Closes cycle-25 finding 2: `rescaledDivide(_:_:) × Complex.zero` was
/// a 6-cycle stable reject (cycles 17 + 20 + 23 + 25) because the `+40`
/// curated-identity-constant signal fires unconditionally on type-shape
/// match without checking algebraic-family compatibility.
@Suite("IdentityElementTemplate — V1.29.B algebraic-family mismatch veto")
struct IdentityElementAlgebraicFamilyTests {

    @Test("V1.29.B — `rescaledDivide × Complex.zero` fires full veto (cycle-25 #30 case)")
    func rescaledDivideZeroFiresVeto() {
        let pair = makeIdentityElementPair(
            opName: "rescaledDivide",
            paramTypes: ("Complex", "Complex"),
            returnType: "Complex",
            identityName: "zero",
            identityType: "Complex"
        )
        #expect(IdentityElementTemplate.suggest(for: pair) == nil)
    }

    @Test("V1.29.B — `/ × Complex.zero` fires full veto")
    func divisionZeroFiresVeto() {
        let pair = makeIdentityElementPair(
            opName: "/",
            paramTypes: ("Complex", "Complex"),
            returnType: "Complex",
            identityName: "zero",
            identityType: "Complex"
        )
        #expect(IdentityElementTemplate.suggest(for: pair) == nil)
    }

    @Test("V1.29.B — `pow × T.zero` fires full veto")
    func powZeroFiresVeto() {
        let pair = makeIdentityElementPair(
            opName: "pow",
            paramTypes: ("Complex", "Complex"),
            returnType: "Complex",
            identityName: "zero",
            identityType: "Complex"
        )
        #expect(IdentityElementTemplate.suggest(for: pair) == nil)
    }

    @Test("V1.29.B — `_relaxedMul × T.zero` fires full veto")
    func relaxedMulZeroFiresVeto() {
        let pair = makeIdentityElementPair(
            opName: "_relaxedMul",
            paramTypes: ("Self", "Self"),
            returnType: "Self",
            identityName: "zero",
            identityType: "Self"
        )
        #expect(IdentityElementTemplate.suggest(for: pair) == nil)
    }

    @Test("V1.29.B — `+ × T.zero` still surfaces (additive compatibility preserved)")
    func plusZeroStillSurfaces() throws {
        let pair = makeIdentityElementPair(
            opName: "+",
            paramTypes: ("MyInt", "MyInt"),
            returnType: "MyInt",
            identityName: "zero",
            identityType: "MyInt"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(for: pair))
        #expect(suggestion.score.tier == .likely)
    }

    @Test("V1.29.B — `_relaxedAdd × T.zero` still surfaces")
    func relaxedAddZeroStillSurfaces() throws {
        let pair = makeIdentityElementPair(
            opName: "_relaxedAdd",
            paramTypes: ("Self", "Self"),
            returnType: "Self",
            identityName: "zero",
            identityType: "Self"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(for: pair))
        #expect(suggestion.score.tier == .likely)
    }

    @Test("V1.29.B — `* × T.one` still surfaces (multiplicative compatibility preserved)")
    func multiplyOneStillSurfaces() throws {
        let pair = makeIdentityElementPair(
            opName: "*",
            paramTypes: ("MyInt", "MyInt"),
            returnType: "MyInt",
            identityName: "one",
            identityType: "MyInt"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(for: pair))
        #expect(suggestion.score.tier == .likely)
    }

    @Test("V1.29.B — `+ × T.one` fires full veto (one is not the additive identity)")
    func plusOneFiresVeto() {
        let pair = makeIdentityElementPair(
            opName: "+",
            paramTypes: ("MyInt", "MyInt"),
            returnType: "MyInt",
            identityName: "one",
            identityType: "MyInt"
        )
        #expect(IdentityElementTemplate.suggest(for: pair) == nil)
    }

    @Test("V1.29.B — `merge × T.empty` unaffected (empty handled by V1.5.2 coverage path)")
    func mergeEmptyUnaffected() throws {
        let pair = makeIdentityElementPair(
            opName: "merge",
            paramTypes: ("IntSet", "IntSet"),
            returnType: "IntSet",
            identityName: "empty",
            identityType: "IntSet"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(for: pair))
        #expect(suggestion.score.tier == .likely)
    }

    @Test("V1.29.B — `arbitraryOp × T.identity` unaffected (kit-monoid path)")
    func arbitraryOpIdentityUnaffected() throws {
        let pair = makeIdentityElementPair(
            opName: "arbitraryOp",
            paramTypes: ("MyType", "MyType"),
            returnType: "MyType",
            identityName: "identity",
            identityType: "MyType"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(for: pair))
        #expect(suggestion.score.tier == .likely)
    }
}

@Suite("IdentityOperatorAlgebra — curated set membership")
struct IdentityOperatorAlgebraTests {

    @Test("Additive set contains +, add, plus, addingProduct, _relaxedAdd")
    func additiveSetMembers() {
        #expect(IdentityOperatorAlgebra.additiveOperatorNames.contains("+"))
        #expect(IdentityOperatorAlgebra.additiveOperatorNames.contains("add"))
        #expect(IdentityOperatorAlgebra.additiveOperatorNames.contains("plus"))
        #expect(IdentityOperatorAlgebra.additiveOperatorNames.contains("addingProduct"))
        #expect(IdentityOperatorAlgebra.additiveOperatorNames.contains("_relaxedAdd"))
    }

    @Test("Additive set excludes - (only right-identity, not two-sided)")
    func additiveSetExcludesMinus() {
        #expect(!IdentityOperatorAlgebra.additiveOperatorNames.contains("-"))
    }

    @Test("Multiplicative set excludes / (only right-identity, not two-sided)")
    func multiplicativeSetExcludesDivide() {
        #expect(!IdentityOperatorAlgebra.multiplicativeOperatorNames.contains("/"))
    }

    @Test("isIncompatibleFamily: (zero, rescaledDivide) is incompatible")
    func zeroRescaledDivideIncompatible() {
        #expect(IdentityOperatorAlgebra.isIncompatibleFamily(
            identityName: "zero", opName: "rescaledDivide"
        ))
    }

    @Test("isIncompatibleFamily: (zero, +) is compatible")
    func zeroPlusCompatible() {
        #expect(!IdentityOperatorAlgebra.isIncompatibleFamily(
            identityName: "zero", opName: "+"
        ))
    }

    @Test("isIncompatibleFamily: (empty, anything) returns false (not in gate scope)")
    func emptyAlwaysCompatible() {
        #expect(!IdentityOperatorAlgebra.isIncompatibleFamily(
            identityName: "empty", opName: "rescaledDivide"
        ))
    }
}
