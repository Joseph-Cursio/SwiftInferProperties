import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// V1.5.2 — protocol-coverage veto tests for the three pair-shaped
// algebraic templates (identity-element / inverse-pair / round-trip).
// Single-summary templates (idempotence / commutativity / associativity)
// + shared fixtures live in `AssumedKitCoverageTests.swift`;
// discover() end-to-end integration in
// `ProtocolCoverageDiscoverIntegrationTests.swift`.
//
// The identity-element suite is the cycle-2 headline — V1.5.2 closes
// the cycle-1 "operator-aware identity-element pairing" gap that
// produced 16.7%-acceptance noise in the v1.4 calibration data.

// MARK: - Identity-element (cycle-2 headline tuning)

@Suite("AssumedKitCoverage — identity-element op-class-aware (V1.5.2)")
struct IdentityElementAssumedKitCoverageTests {

    @Test("(.zero, \"+\") on : AdditiveArithmetic vetoes (cycle-1 noise closure)")
    func zeroPlusOnAdditiveArithmeticVetoes() {
        let pair = makeIdentityElementPair(
            opName: "+",
            paramTypes: ("Money", "Money"),
            returnType: "Money",
            identityName: "zero",
            identityType: "Money"
        )
        let result = IdentityElementTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("Money", conformances: ["AdditiveArithmetic"])
        )
        #expect(result == nil)
    }

    @Test("(.one, \"*\") on : Numeric vetoes")
    func oneTimesOnNumericVetoes() {
        let pair = makeIdentityElementPair(
            opName: "*",
            paramTypes: ("BigInt", "BigInt"),
            returnType: "BigInt",
            identityName: "one",
            identityType: "BigInt"
        )
        let result = IdentityElementTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("BigInt", conformances: ["Numeric"])
        )
        #expect(result == nil)
    }

    @Test("(.empty, \"union\") on : SetAlgebra vetoes")
    func emptyUnionOnSetAlgebraVetoes() {
        let pair = makeIdentityElementPair(
            opName: "union",
            paramTypes: ("BitSet", "BitSet"),
            returnType: "BitSet",
            identityName: "empty",
            identityType: "BitSet"
        )
        let result = IdentityElementTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("BitSet", conformances: ["SetAlgebra"])
        )
        #expect(result == nil)
    }

    @Test("(.identity, \"combine\") on : Monoid vetoes (kit Monoid coverage)")
    func identityOnKitMonoidVetoes() {
        let pair = makeIdentityElementPair(
            opName: "combine",
            paramTypes: ("Element", "Element"),
            returnType: "Element",
            identityName: "identity",
            identityType: "Element"
        )
        let result = IdentityElementTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("Element", conformances: ["Monoid"])
        )
        #expect(result == nil)
    }

    @Test("V1.29.B — (.zero, \"*\") on : Numeric is now suppressed via algebraic-family veto")
    func zeroTimesOnNumericNowSuppressed() {
        // V1.5.2: protocol-coverage veto narrowing didn't fire on this
        // cross-product pair because the (zero, *) tuple doesn't bind
        // to a kit-published law — the suggestion surfaced as Possible.
        // V1.29.B (cycle-25 finding 2): the (zero, *) pair is now
        // suppressed at signal-construction time because zero is the
        // additive identity and * is multiplicative — algebraic-family
        // mismatch fires Signal.vetoWeight. The V1.5.2 protocol-coverage
        // narrowing is preserved at the implementation level (op-class-
        // aware), but the suggestion no longer surfaces because the
        // earlier algebraic-family veto wins.
        let pair = makeIdentityElementPair(
            opName: "*",
            paramTypes: ("BigInt", "BigInt"),
            returnType: "BigInt",
            identityName: "zero",
            identityType: "BigInt"
        )
        #expect(IdentityElementTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("BigInt", conformances: ["Numeric"])
        ) == nil)
    }

    @Test("V1.29.B — (.one, \"+\") on : Numeric is now suppressed via algebraic-family veto")
    func onePlusOnNumericNowSuppressed() {
        // Symmetric to zeroTimesOnNumericNowSuppressed: V1.29.B's
        // algebraic-family-mismatch veto fires because one is the
        // multiplicative identity but + is additive.
        let pair = makeIdentityElementPair(
            opName: "+",
            paramTypes: ("BigInt", "BigInt"),
            returnType: "BigInt",
            identityName: "one",
            identityType: "BigInt"
        )
        #expect(IdentityElementTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("BigInt", conformances: ["Numeric"])
        ) == nil)
    }

    @Test("(.none, \"+\") on : Numeric does NOT veto — .none is not curated")
    func noneIdentityDoesNotVeto() throws {
        let pair = makeIdentityElementPair(
            opName: "+",
            paramTypes: ("BigInt", "BigInt"),
            returnType: "BigInt",
            identityName: "none",
            identityType: "BigInt"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("BigInt", conformances: ["Numeric"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }

    @Test("(.zero, \"+\") on plain Equatable type does NOT veto (no AdditiveArithmetic)")
    func zeroPlusOnPlainTypeDoesNotVeto() throws {
        let pair = makeIdentityElementPair(
            opName: "+",
            paramTypes: ("Vec", "Vec"),
            returnType: "Vec",
            identityName: "zero",
            identityType: "Vec"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("Vec", conformances: ["Equatable"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }

    @Test("(constant, op) → KnownProperty mapping table — exhaustive cases")
    func identityCoverageCandidateMapping() {
        // Positives
        #expect(IdentityElementTemplate.identityCoverageCandidate(
            identityName: "zero", opName: "+"
        ) == .additiveIdentityZero)
        #expect(IdentityElementTemplate.identityCoverageCandidate(
            identityName: "one", opName: "*"
        ) == .multiplicativeIdentityOne)
        #expect(IdentityElementTemplate.identityCoverageCandidate(
            identityName: "empty", opName: "union"
        ) == .setUnionEmptyIdentity)
        #expect(IdentityElementTemplate.identityCoverageCandidate(
            identityName: "empty", opName: "formUnion"
        ) == .setUnionEmptyIdentity)
        #expect(IdentityElementTemplate.identityCoverageCandidate(
            identityName: "empty", opName: "+"
        ) == .setUnionEmptyIdentity)
        #expect(IdentityElementTemplate.identityCoverageCandidate(
            identityName: "identity", opName: "combine"
        ) == .monoidIdentity)
        // Cross-product noise — no veto candidate
        #expect(IdentityElementTemplate.identityCoverageCandidate(
            identityName: "zero", opName: "*"
        ) == nil)
        #expect(IdentityElementTemplate.identityCoverageCandidate(
            identityName: "one", opName: "+"
        ) == nil)
        // Non-curated identity names
        #expect(IdentityElementTemplate.identityCoverageCandidate(
            identityName: "none", opName: "+"
        ) == nil)
        #expect(IdentityElementTemplate.identityCoverageCandidate(
            identityName: "default", opName: "+"
        ) == nil)
    }
}
