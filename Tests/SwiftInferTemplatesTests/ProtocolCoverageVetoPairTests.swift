import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

// V1.5.2 — protocol-coverage veto tests for the three pair-shaped
// algebraic templates (identity-element / inverse-pair / round-trip).
// Single-summary templates (idempotence / commutativity / associativity)
// + shared fixtures live in `ProtocolCoverageVetoTests.swift`;
// discover() end-to-end integration in
// `ProtocolCoverageVetoIntegrationTests.swift`.
//
// The identity-element suite is the cycle-2 headline — V1.5.2 closes
// the cycle-1 "operator-aware identity-element pairing" gap that
// produced 16.7%-acceptance noise in the v1.4 calibration data.

// MARK: - Identity-element (cycle-2 headline tuning)

@Suite("ProtocolCoverageVeto — identity-element op-class-aware (V1.5.2)")
struct IdentityElementProtocolCoverageVetoTests {

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

    @Test("(.zero, \"*\") on : Numeric does NOT veto — cycle-1 cross-product noise was here")
    func zeroTimesOnNumericDoesNotVeto() throws {
        // The cycle-2 priority #1 fix: previously the cross-product of
        // curated identity constants × ops produced false-positive
        // suggestions. (.zero, "*") doesn't bind to a kit-published
        // law, so no veto fires. The suggestion still surfaces — v1.5
        // narrows the veto, doesn't blanket-suppress the surface.
        let pair = makeIdentityElementPair(
            opName: "*",
            paramTypes: ("BigInt", "BigInt"),
            returnType: "BigInt",
            identityName: "zero",
            identityType: "BigInt"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("BigInt", conformances: ["Numeric"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }

    @Test("(.one, \"+\") on : Numeric does NOT veto — same cross-product narrowing")
    func onePlusOnNumericDoesNotVeto() throws {
        let pair = makeIdentityElementPair(
            opName: "+",
            paramTypes: ("BigInt", "BigInt"),
            returnType: "BigInt",
            identityName: "one",
            identityType: "BigInt"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("BigInt", conformances: ["Numeric"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
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

// MARK: - Inverse-pair

@Suite("ProtocolCoverageVeto — inverse-pair (V1.5.2)")
struct InversePairProtocolCoverageVetoTests {

    @Test("Inverse-pair on : SignedNumeric vetoes (additiveInverse covered)")
    func signedNumericVetoesInversePair() {
        let pair = makeRoundTripPair(
            forwardName: "negate",
            reverseName: "negate",
            forwardParam: "BigInt",
            forwardReturn: "BigInt"
        )
        let result = InversePairTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("BigInt", conformances: ["SignedNumeric"])
        )
        #expect(result == nil)
    }

    @Test("Inverse-pair on : Group vetoes (groupInverse covered)")
    func groupVetoesInversePair() {
        let pair = makeRoundTripPair(
            forwardName: "compose",
            reverseName: "invert",
            forwardParam: "Permutation",
            forwardReturn: "Permutation"
        )
        let result = InversePairTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("Permutation", conformances: ["Group"])
        )
        #expect(result == nil)
    }

    @Test("Inverse-pair on : Numeric does NOT veto (Numeric lacks additiveInverse)")
    func numericDoesNotVetoInversePair() {
        // Numeric covers `+` / `*` but NOT additive-inverse; that's a
        // SignedNumeric-only law. Inverse-pair on a Numeric (not
        // SignedNumeric) carrier stays surfaced.
        let pair = makeRoundTripPair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "BigInt",
            forwardReturn: "Data"
        )
        let result = InversePairTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("BigInt", conformances: ["Numeric"])
        )
        if let result {
            #expect(!result.score.signals.contains { $0.kind == .protocolCoveredProperty })
        }
    }

    @Test("Inverse-pair on plain user type does NOT veto")
    func plainTypeDoesNotVetoInversePair() throws {
        let pair = makeRoundTripPair(
            forwardName: "parse",
            reverseName: "format",
            forwardParam: "Doc",
            forwardReturn: "String"
        )
        let suggestion = try #require(InversePairTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("Doc", conformances: ["Hashable"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }
}

// MARK: - Round-trip

@Suite("ProtocolCoverageVeto — round-trip (V1.5.2)")
struct RoundTripProtocolCoverageVetoTests {

    @Test("Round-trip on : Codable forward type vetoes")
    func codableVetoesRoundTrip() {
        let pair = makeRoundTripPair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "User",
            forwardReturn: "Data"
        )
        let result = RoundTripTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("User", conformances: ["Codable"])
        )
        #expect(result == nil, "Codable conformance should suppress round-trip")
    }

    @Test("Round-trip on plain forward type does NOT veto")
    func plainForwardTypeDoesNotVetoRoundTrip() throws {
        let pair = makeRoundTripPair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "Doc",
            forwardReturn: "String"
        )
        let suggestion = try #require(RoundTripTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("Doc", conformances: ["Equatable", "Sendable"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }

    @Test("Round-trip on : Encodable-only type does NOT veto (Codable-only key in table)")
    func encodableOnlyDoesNotVetoRoundTrip() throws {
        // V1.5.1 documented limitation: Encodable / Decodable as separate
        // conformances aren't covered (neither alone covers
        // codableRoundTrip). User code that writes them separately
        // doesn't get suppression.
        let pair = makeRoundTripPair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "Tag",
            forwardReturn: "Data"
        )
        let suggestion = try #require(RoundTripTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("Tag", conformances: ["Encodable", "Decodable"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }
}
