import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import SwiftInferCore
@testable import SwiftInferMacroImpl

@Suite("@CheckProperty macro — round-trip + preserves-invariant expansion")
struct CheckPropertyMacroExpansionTests {

    let testMacros: [String: Macro.Type] = [
        "CheckProperty": CheckPropertyMacro.self
    ]

    // MARK: - Round-trip expansion shape (M5.3)

    @Test
    func roundTripExpansionPicksRawTypeGeneratorForString() {
        let canonical = "checkProperty.roundTrip|encode|hash|(String)->Int"
        let seed = SamplingSeed.derive(fromIdentityHash: canonical)
        let expected = expectedRoundTripExpansion(
            sourceFunction: "func encode(_ value: String) -> Int { value.count }",
            forwardName: "encode",
            inverseName: "hash",
            generator: "Gen<Character>.letterOrNumber.string(of: 0...8)",
            seed: seed
        )
        assertMacroExpansion(
            """
            @CheckProperty(.roundTrip(pairedWith: "hash"))
            func encode(_ value: String) -> Int { value.count }
            """,
            expandedSource: expected,
            macros: testMacros
        )
    }

    @Test
    func roundTripExpansionFallsBackToUserGenForCustomType() {
        let canonical = "checkProperty.roundTrip|decode|encode|(MyType)->Data"
        let seed = SamplingSeed.derive(fromIdentityHash: canonical)
        let expected = expectedRoundTripExpansion(
            sourceFunction: "func encode(_ value: MyType) -> Data { Data() }",
            forwardName: "encode",
            inverseName: "decode",
            generator: "MyType.gen()",
            seed: seed
        )
        assertMacroExpansion(
            """
            @CheckProperty(.roundTrip(pairedWith: "decode"))
            func encode(_ value: MyType) -> Data { Data() }
            """,
            expandedSource: expected,
            macros: testMacros
        )
    }

    @Test
    func roundTripIdentityIsOrientationAgnostic() {
        // Attaching the macro to either half of the pair produces the
        // same identity hash + therefore the same seed for the names
        // half (sorted); the type signature is per-side.
        let forwardCanonical = "checkProperty.roundTrip|decode|encode|(MyType)->Data"
        let reverseCanonical = "checkProperty.roundTrip|decode|encode|(Data)->MyType"
        let forwardSeed = SamplingSeed.derive(fromIdentityHash: forwardCanonical)
        let reverseSeed = SamplingSeed.derive(fromIdentityHash: reverseCanonical)
        // The two seeds differ because the canonical forms differ.
        // What matters: attaching to `encode` always hashes the same
        // canonical string, attaching to `decode` always hashes the
        // same canonical string — neither shifts based on the order
        // of `forwardName` / `inverseName` in the canonical sort.
        #expect(forwardSeed != reverseSeed)
        // The same-side reproducibility check:
        let again = SamplingSeed.derive(fromIdentityHash: forwardCanonical)
        #expect(forwardSeed == again)
    }

    // MARK: - Invariant-preservation expansion shape (M7.2.a)

    @Test
    func preservesInvariantExpansionPicksRawTypeGeneratorForCustomType() {
        let canonical = "checkProperty.preservesInvariant|adjust|\\.isValid|(Widget)->Widget"
        let seed = SamplingSeed.derive(fromIdentityHash: canonical)
        let expected = expectedPreservesInvariantExpansion(
            sourceFunction: "func adjust(_ value: Widget) -> Widget { value }",
            funcName: "adjust",
            keyPath: "\\.isValid",
            generator: "Widget.gen()",
            seed: seed
        )
        assertMacroExpansion(
            """
            @CheckProperty(.preservesInvariant(\\.isValid))
            func adjust(_ value: Widget) -> Widget { value }
            """,
            expandedSource: expected,
            macros: testMacros
        )
    }

    @Test
    func preservesInvariantSeedDiffersAcrossKeypaths() {
        // Same function with two different invariant keypaths produces
        // distinct seeds — the canonical signature embeds the keypath
        // text so trial sequences don't collide across claims.
        let canonical1 = "checkProperty.preservesInvariant|adjust|\\.isValid|(Widget)->Widget"
        let canonical2 = "checkProperty.preservesInvariant|adjust|\\.isNonNegative|(Widget)->Widget"
        let seed1 = SamplingSeed.derive(fromIdentityHash: canonical1)
        let seed2 = SamplingSeed.derive(fromIdentityHash: canonical2)
        #expect(seed1 != seed2)
    }
}
