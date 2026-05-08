import Testing
@testable import SwiftInferCore

@Suite("ProtocolCoverageMap — V1.5.1 curated protocol → property coverage")
struct ProtocolCoverageMapTests {

    // MARK: - Table coverage (one assertion per documented protocol key)

    @Test("Equatable covers reflexive / symmetric / transitive")
    func equatableCoverage() {
        #expect(ProtocolCoverageMap.covers("Equatable", .equatableReflexive))
        #expect(ProtocolCoverageMap.covers("Equatable", .equatableSymmetric))
        #expect(ProtocolCoverageMap.covers("Equatable", .equatableTransitive))
        #expect(!ProtocolCoverageMap.covers("Equatable", .comparableTotalOrder))
        #expect(!ProtocolCoverageMap.covers("Equatable", .hashableConsistency))
    }

    @Test("Comparable transitively covers Equatable plus comparableTotalOrder")
    func comparableCoverage() {
        #expect(ProtocolCoverageMap.covers("Comparable", .comparableTotalOrder))
        #expect(ProtocolCoverageMap.covers("Comparable", .equatableReflexive))
        #expect(ProtocolCoverageMap.covers("Comparable", .equatableSymmetric))
        #expect(ProtocolCoverageMap.covers("Comparable", .equatableTransitive))
        #expect(!ProtocolCoverageMap.covers("Comparable", .hashableConsistency))
    }

    @Test("Hashable transitively covers Equatable plus hashableConsistency")
    func hashableCoverage() {
        #expect(ProtocolCoverageMap.covers("Hashable", .hashableConsistency))
        #expect(ProtocolCoverageMap.covers("Hashable", .equatableReflexive))
        #expect(ProtocolCoverageMap.covers("Hashable", .equatableSymmetric))
        #expect(ProtocolCoverageMap.covers("Hashable", .equatableTransitive))
        #expect(!ProtocolCoverageMap.covers("Hashable", .comparableTotalOrder))
    }

    @Test("AdditiveArithmetic transitively covers Equatable plus additive triple")
    func additiveArithmeticCoverage() {
        #expect(ProtocolCoverageMap.covers("AdditiveArithmetic", .additiveAssociative))
        #expect(ProtocolCoverageMap.covers("AdditiveArithmetic", .additiveCommutative))
        #expect(ProtocolCoverageMap.covers("AdditiveArithmetic", .additiveIdentityZero))
        #expect(ProtocolCoverageMap.covers("AdditiveArithmetic", .equatableReflexive))
        #expect(!ProtocolCoverageMap.covers("AdditiveArithmetic", .multiplicativeAssociative))
        #expect(!ProtocolCoverageMap.covers("AdditiveArithmetic", .additiveInverse))
        #expect(!ProtocolCoverageMap.covers("AdditiveArithmetic", .distributivity))
    }

    @Test("Numeric transitively covers AdditiveArithmetic plus multiplicative + distributivity")
    func numericCoverage() {
        // Inherited from AdditiveArithmetic (the load-bearing transitive case)
        #expect(ProtocolCoverageMap.covers("Numeric", .additiveAssociative))
        #expect(ProtocolCoverageMap.covers("Numeric", .additiveCommutative))
        #expect(ProtocolCoverageMap.covers("Numeric", .additiveIdentityZero))
        #expect(ProtocolCoverageMap.covers("Numeric", .equatableReflexive))
        // Numeric-specific
        #expect(ProtocolCoverageMap.covers("Numeric", .multiplicativeAssociative))
        #expect(ProtocolCoverageMap.covers("Numeric", .multiplicativeCommutative))
        #expect(ProtocolCoverageMap.covers("Numeric", .multiplicativeIdentityOne))
        #expect(ProtocolCoverageMap.covers("Numeric", .distributivity))
        // Out of scope for Numeric
        #expect(!ProtocolCoverageMap.covers("Numeric", .additiveInverse))
        #expect(!ProtocolCoverageMap.covers("Numeric", .multiplicativeInverse))
    }

    @Test("SignedNumeric transitively covers Numeric plus additiveInverse")
    func signedNumericCoverage() {
        // Inherited transitively (Numeric → AdditiveArithmetic → Equatable)
        #expect(ProtocolCoverageMap.covers("SignedNumeric", .multiplicativeIdentityOne))
        #expect(ProtocolCoverageMap.covers("SignedNumeric", .additiveIdentityZero))
        #expect(ProtocolCoverageMap.covers("SignedNumeric", .equatableReflexive))
        // SignedNumeric-specific
        #expect(ProtocolCoverageMap.covers("SignedNumeric", .additiveInverse))
        // Still out of scope (multiplicative inverse needs Field-shaped arm)
        #expect(!ProtocolCoverageMap.covers("SignedNumeric", .multiplicativeInverse))
    }

    @Test("SetAlgebra covers union/intersection laws plus inherited Equatable")
    func setAlgebraCoverage() {
        #expect(ProtocolCoverageMap.covers("SetAlgebra", .setUnionAssociative))
        #expect(ProtocolCoverageMap.covers("SetAlgebra", .setUnionCommutative))
        #expect(ProtocolCoverageMap.covers("SetAlgebra", .setUnionEmptyIdentity))
        #expect(ProtocolCoverageMap.covers("SetAlgebra", .setIntersectionIdempotent))
        #expect(ProtocolCoverageMap.covers("SetAlgebra", .equatableReflexive))
        // Sanity — SetAlgebra is not in the additive chain
        #expect(!ProtocolCoverageMap.covers("SetAlgebra", .additiveAssociative))
        #expect(!ProtocolCoverageMap.covers("SetAlgebra", .codableRoundTrip))
    }

    @Test("Codable covers codableRoundTrip exclusively")
    func codableCoverage() {
        #expect(ProtocolCoverageMap.covers("Codable", .codableRoundTrip))
        // Codable has no other covered properties in the curated table
        for property in KnownProperty.allCases where property != .codableRoundTrip {
            #expect(!ProtocolCoverageMap.covers("Codable", property),
                    "Codable should not cover \(property)")
        }
    }

    @Test("Kit Semigroup is a placeholder with empty coverage")
    func semigroupCoverage() {
        // Semigroup is in the table but covers no SwiftInfer-emitted property
        for property in KnownProperty.allCases {
            #expect(!ProtocolCoverageMap.covers("Semigroup", property),
                    "Semigroup should not cover \(property) (placeholder)")
        }
        // Confirm the key is actually present (not a typo / fall-through false)
        #expect(ProtocolCoverageMap.protocolCoverage["Semigroup"] != nil)
    }

    @Test("Kit Monoid covers monoidIdentity")
    func monoidCoverage() {
        #expect(ProtocolCoverageMap.covers("Monoid", .monoidIdentity))
        #expect(!ProtocolCoverageMap.covers("Monoid", .groupInverse))
        #expect(!ProtocolCoverageMap.covers("Monoid", .semilatticeIdempotence))
    }

    @Test("Kit CommutativeMonoid behaves like Monoid (no separate combineCommutative property)")
    func commutativeMonoidCoverage() {
        #expect(ProtocolCoverageMap.covers("CommutativeMonoid", .monoidIdentity))
        #expect(!ProtocolCoverageMap.covers("CommutativeMonoid", .groupInverse))
        // Critically: CommutativeMonoid does NOT cover stdlib `+`-shaped
        // additiveCommutative (different op-class — kit `combine` ≠ stdlib `+`).
        #expect(!ProtocolCoverageMap.covers("CommutativeMonoid", .additiveCommutative))
    }

    @Test("Kit Group covers Monoid's identity plus groupInverse")
    func groupCoverage() {
        #expect(ProtocolCoverageMap.covers("Group", .monoidIdentity))
        #expect(ProtocolCoverageMap.covers("Group", .groupInverse))
        #expect(!ProtocolCoverageMap.covers("Group", .semilatticeIdempotence))
        // Stdlib additiveInverse is a different property surface
        #expect(!ProtocolCoverageMap.covers("Group", .additiveInverse))
    }

    @Test("Kit Semilattice covers Monoid's identity plus semilatticeIdempotence")
    func semilatticeCoverage() {
        #expect(ProtocolCoverageMap.covers("Semilattice", .monoidIdentity))
        #expect(ProtocolCoverageMap.covers("Semilattice", .semilatticeIdempotence))
        #expect(!ProtocolCoverageMap.covers("Semilattice", .groupInverse))
    }

    // MARK: - Lookup-helper edge cases

    @Test("Unknown protocol name returns false for every property")
    func unknownProtocolReturnsFalse() {
        for property in KnownProperty.allCases {
            #expect(!ProtocolCoverageMap.covers("MyCustomProtocol", property))
            #expect(!ProtocolCoverageMap.covers("", property))
        }
    }

    @Test("Module-qualified names do not match (v1 textual-only limitation)")
    func moduleQualifiedDoesNotMatch() {
        // Documented limitation per v1.5 plan §"Out of scope". Cycle-3
        // may add a normalization step.
        #expect(!ProtocolCoverageMap.covers("Swift.Numeric", .multiplicativeAssociative))
        #expect(!ProtocolCoverageMap.covers("Swift.Equatable", .equatableReflexive))
    }

    // MARK: - anyCovers / firstCoveringProtocol convenience wrappers

    @Test("anyCovers returns true when one inherited type covers the property")
    func anyCoversPositive() {
        let inherited = ["Sendable", "Hashable", "CustomStringConvertible"]
        #expect(ProtocolCoverageMap.anyCovers(inherited, .hashableConsistency))
        #expect(ProtocolCoverageMap.anyCovers(inherited, .equatableReflexive))
    }

    @Test("anyCovers returns false when no inherited type covers the property")
    func anyCoversNegative() {
        let inherited = ["Sendable", "CustomStringConvertible"]
        #expect(!ProtocolCoverageMap.anyCovers(inherited, .additiveAssociative))
        #expect(!ProtocolCoverageMap.anyCovers(inherited, .codableRoundTrip))
    }

    @Test("anyCovers handles empty inherited list")
    func anyCoversEmpty() {
        let empty: [String] = []
        #expect(!ProtocolCoverageMap.anyCovers(empty, .equatableReflexive))
    }

    @Test("firstCoveringProtocol returns the first matching conformance")
    func firstCoveringProtocolReturnsFirst() {
        // Order matters — the conformance list is walked left-to-right.
        let inherited = ["Sendable", "Numeric", "Hashable"]
        // Both Numeric and Hashable cover equatableReflexive; Numeric
        // is encountered first.
        #expect(ProtocolCoverageMap.firstCoveringProtocol(in: inherited, for: .equatableReflexive) == "Numeric")
    }

    @Test("firstCoveringProtocol returns nil when no conformance matches")
    func firstCoveringProtocolReturnsNil() {
        let inherited = ["Sendable", "CustomStringConvertible"]
        #expect(ProtocolCoverageMap.firstCoveringProtocol(in: inherited, for: .additiveAssociative) == nil)
    }

    // MARK: - Catalog integrity

    @Test("Curated table contains exactly the 13 documented stdlib + kit protocol keys")
    func tableKeyCount() {
        let expected: Set<String> = [
            // stdlib equality / ordering / hashing
            "Equatable", "Comparable", "Hashable",
            // stdlib arithmetic chain
            "AdditiveArithmetic", "Numeric", "SignedNumeric",
            // stdlib set algebra
            "SetAlgebra",
            // stdlib codable
            "Codable",
            // kit algebraic protocols
            "Semigroup", "Monoid", "CommutativeMonoid", "Group", "Semilattice"
        ]
        #expect(Set(ProtocolCoverageMap.protocolCoverage.keys) == expected)
        #expect(ProtocolCoverageMap.protocolCoverage.count == 13)
    }

    @Test("KnownProperty has the documented 22 cases")
    func knownPropertyCount() {
        // Pinning the count guards against silent enum drift; future
        // template arms should add cases consciously and update this
        // assertion + the test suite.
        #expect(KnownProperty.allCases.count == 22)
    }

    @Test("Every covered property name is a valid KnownProperty case")
    func tableValuesAreValidKnownProperties() {
        // Trivially holds at compile time (the table is typed
        // `[String: Set<KnownProperty>]`), but exercising the table
        // ensures none of the entries are accidentally empty when
        // they shouldn't be.
        for (name, properties) in ProtocolCoverageMap.protocolCoverage {
            // Semigroup is the documented empty placeholder; everyone
            // else should carry at least one property.
            if name == "Semigroup" {
                #expect(properties.isEmpty)
            } else {
                #expect(!properties.isEmpty, "\(name) should cover at least one property")
            }
        }
    }
}

@Suite("Signal.Kind.protocolCoveredProperty — V1.5.1 veto signal")
struct ProtocolCoveredPropertySignalTests {

    @Test("New Kind case is reachable via CaseIterable")
    func kindIsCaseIterable() {
        #expect(Signal.Kind.allCases.contains(.protocolCoveredProperty))
    }

    @Test("Veto-shaped Signal collapses score (mirrors nonDeterministicBody / nonEquatableOutput)")
    func vetoCollapsesScore() {
        let detail = "Property already covered by conformance to 'AdditiveArithmetic'"
            + " — checked by PropertyLawKit's checkAdditiveArithmeticPropertyLaws"
        let veto = Signal(
            kind: .protocolCoveredProperty,
            weight: Signal.vetoWeight,
            detail: detail
        )
        #expect(veto.isVeto)
        // formattedLine ends in " (veto)" for veto-shaped signals
        #expect(veto.formattedLine.hasSuffix(" (veto)"))
    }
}
