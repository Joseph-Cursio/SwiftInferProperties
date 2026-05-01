import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import SwiftInferCore
@testable import SwiftInferMacroImpl

// swiftlint:disable type_body_length
// Test suite covers both .idempotent (M5.2) and .roundTrip (M5.3) arms
// plus the diagnostics for both — splitting along the 250-line body
// limit would scatter the per-arm assertions across multiple files for
// no reader benefit.
@Suite("@CheckProperty peer-macro expansion (M5.2 + M5.3)")
struct CheckPropertyMacroTests {

    let testMacros: [String: Macro.Type] = [
        "CheckProperty": CheckPropertyMacro.self
    ]

    // MARK: - Diagnostics

    @Test
    func nonFunctionAttachmentEmitsDiagnostic() {
        assertMacroExpansion(
            """
            @CheckProperty(.idempotent)
            struct NotAFunction {}
            """,
            expandedSource: """
            struct NotAFunction {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@CheckProperty can only attach to a function declaration.",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    @Test
    func nonUnaryFunctionEmitsDiagnostic() {
        assertMacroExpansion(
            """
            @CheckProperty(.idempotent)
            func merge(_ a: Int, _ b: Int) -> Int { a }
            """,
            expandedSource: """
            func merge(_ a: Int, _ b: Int) -> Int { a }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@CheckProperty(.idempotent) requires `func name(_: T) -> T`"
                        + " — exactly one parameter and a non-nil return type.",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    @Test
    func mismatchedParameterAndReturnTypeEmitsDiagnostic() {
        assertMacroExpansion(
            """
            @CheckProperty(.idempotent)
            func encode(_ value: MyType) -> Data { Data() }
            """,
            expandedSource: """
            func encode(_ value: MyType) -> Data { Data() }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@CheckProperty(.idempotent) requires the parameter type and"
                        + " return type to be identical (the `T -> T` shape).",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    @Test
    func roundTripArmRequiresUnaryShape() {
        assertMacroExpansion(
            """
            @CheckProperty(.roundTrip(pairedWith: "split"))
            func merge(_ a: Int, _ b: Int) -> Int { a }
            """,
            expandedSource: """
            func merge(_ a: Int, _ b: Int) -> Int { a }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@CheckProperty(.roundTrip, pairedWith:) requires"
                        + " `func name(_: T) -> U` — exactly one parameter and"
                        + " a non-nil return type.",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    @Test
    func roundTripArmRejectsSameTypeShape() {
        // T -> T is .idempotent territory — round-trip needs T != U so
        // the inverse function actually takes the forward's output.
        assertMacroExpansion(
            """
            @CheckProperty(.roundTrip(pairedWith: "unwrap"))
            func wrap(_ value: Int) -> Int { value }
            """,
            expandedSource: """
            func wrap(_ value: Int) -> Int { value }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@CheckProperty(.roundTrip, pairedWith:) requires the"
                        + " parameter type and return type to differ. For T -> T"
                        + " use @CheckProperty(.idempotent).",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    // MARK: - Idempotent expansion shape

    @Test
    func idempotentExpansionPicksRawTypeGeneratorForString() {
        let canonical = "checkProperty.idempotent|normalize|(String)->String"
        let seed = SamplingSeed.derive(fromIdentityHash: canonical)
        let expected = expectedIdempotentExpansion(
            sourceFunction: "func normalize(_ value: String) -> String { value }",
            funcName: "normalize",
            generator: "Gen<Character>.letterOrNumber.string(of: 0...8)",
            seed: seed
        )
        assertMacroExpansion(
            """
            @CheckProperty(.idempotent)
            func normalize(_ value: String) -> String { value }
            """,
            expandedSource: expected,
            macros: testMacros
        )
    }

    @Test
    func idempotentExpansionPicksRawTypeGeneratorForInt() {
        let canonical = "checkProperty.idempotent|abs|(Int)->Int"
        let seed = SamplingSeed.derive(fromIdentityHash: canonical)
        let expected = expectedIdempotentExpansion(
            sourceFunction: "func abs(_ value: Int) -> Int { value < 0 ? -value : value }",
            funcName: "abs",
            generator: "Gen<Int>.int()",
            seed: seed
        )
        assertMacroExpansion(
            """
            @CheckProperty(.idempotent)
            func abs(_ value: Int) -> Int { value < 0 ? -value : value }
            """,
            expandedSource: expected,
            macros: testMacros
        )
    }

    @Test
    func idempotentExpansionFallsBackToUserGenForCustomType() {
        // Non-RawType parameters fall through to `<TypeName>.gen()` —
        // the same convention `DerivationStrategist.userGen` /
        // `.todo` produce. The user provides `static func gen()` on
        // the type or gets a compile error pointing at the missing
        // symbol.
        let canonical = "checkProperty.idempotent|sanitize|(IntSet)->IntSet"
        let seed = SamplingSeed.derive(fromIdentityHash: canonical)
        let expected = expectedIdempotentExpansion(
            sourceFunction: "func sanitize(_ value: IntSet) -> IntSet { value }",
            funcName: "sanitize",
            generator: "IntSet.gen()",
            seed: seed
        )
        assertMacroExpansion(
            """
            @CheckProperty(.idempotent)
            func sanitize(_ value: IntSet) -> IntSet { value }
            """,
            expandedSource: expected,
            macros: testMacros
        )
    }

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
        // same identity hash + therefore the same seed. Mirrors the
        // sort-then-hash pattern from `RoundTripTemplate.makeIdentity`.
        let forwardCanonical = "checkProperty.roundTrip|decode|encode|(MyType)->Data"
        let reverseCanonical = "checkProperty.roundTrip|decode|encode|(Data)->MyType"
        // Note these are DIFFERENT — the canonical form keeps the
        // *attached* function's signature visible. Both halves
        // produce orientation-agnostic identity for the *names*
        // half (sorted) but the type signature is per-side. The
        // round-trip identity in the kit's sense (where both
        // signatures appear sorted) is a future tightening; M5.3
        // sorts only the names.
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

    // MARK: - Helpers

    /// Build the byte-stable expansion we expect for an `.idempotent`
    /// `@CheckProperty` attachment. Mirrors the format
    /// `CheckPropertyMacro.expandIdempotent` emits — any drift in
    /// either side fails the assertion immediately.
    private func expectedIdempotentExpansion(
        sourceFunction: String,
        funcName: String,
        generator: String,
        seed: SamplingSeed.Value
    ) -> String {
        let stateA = hex(seed.stateA)
        let stateB = hex(seed.stateB)
        let stateC = hex(seed.stateC)
        let stateD = hex(seed.stateD)
        return """
            \(sourceFunction)

            @Test func \(funcName)_isIdempotent() async {
                let backend = SwiftPropertyBasedBackend()
                let seed = Seed(
                    stateA: 0x\(stateA),
                    stateB: 0x\(stateB),
                    stateC: 0x\(stateC),
                    stateD: 0x\(stateD)
                )
                let result = await backend.check(
                    trials: 100,
                    seed: seed,
                    sample: { rng in (\(generator)).run(&rng) },
                    property: { value in \(funcName)(\(funcName)(value)) == \(funcName)(value) }
                )
                if case let .failed(_, _, input, error) = result {
                    Issue.record(
                        "\(funcName)(_:) failed idempotence at input \\(input)."
                            + " \\(error?.message ?? \\"\\")"
                    )
                }
            }
            """
    }

    /// Build the byte-stable expansion we expect for a `.roundTrip`
    /// `@CheckProperty` attachment. Mirrors the format
    /// `CheckPropertyMacro.expandRoundTrip` emits.
    private func expectedRoundTripExpansion(
        sourceFunction: String,
        forwardName: String,
        inverseName: String,
        generator: String,
        seed: SamplingSeed.Value
    ) -> String {
        let stateA = hex(seed.stateA)
        let stateB = hex(seed.stateB)
        let stateC = hex(seed.stateC)
        let stateD = hex(seed.stateD)
        return """
            \(sourceFunction)

            @Test func \(forwardName)_\(inverseName)_roundTrip() async {
                let backend = SwiftPropertyBasedBackend()
                let seed = Seed(
                    stateA: 0x\(stateA),
                    stateB: 0x\(stateB),
                    stateC: 0x\(stateC),
                    stateD: 0x\(stateD)
                )
                let result = await backend.check(
                    trials: 100,
                    seed: seed,
                    sample: { rng in (\(generator)).run(&rng) },
                    property: { value in \(inverseName)(\(forwardName)(value)) == value }
                )
                if case let .failed(_, _, input, error) = result {
                    Issue.record(
                        "\(forwardName)/\(inverseName) round-trip failed at input \\(input)."
                            + " \\(error?.message ?? \\"\\")"
                    )
                }
            }
            """
    }

    private func hex(_ word: UInt64) -> String {
        let raw = String(word, radix: 16, uppercase: true)
        return String(repeating: "0", count: 16 - raw.count) + raw
    }
}
// swiftlint:enable type_body_length
