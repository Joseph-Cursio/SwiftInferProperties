import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import SwiftInferCore
@testable import SwiftInferMacroImpl

@Suite("@CheckProperty peer-macro expansion (M5.2)")
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
    func roundTripArmEmitsDeferredDiagnosticInM52() {
        assertMacroExpansion(
            """
            @CheckProperty(.roundTrip(pairedWith: "decode"))
            func encode(_ value: MyType) -> Data { Data() }
            """,
            expandedSource: """
            func encode(_ value: MyType) -> Data { Data() }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@CheckProperty(.roundTrip, pairedWith:) lands in M5.3."
                        + " M5.2 ships only the .idempotent arm.",
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

    private func hex(_ word: UInt64) -> String {
        let raw = String(word, radix: 16, uppercase: true)
        return String(repeating: "0", count: 16 - raw.count) + raw
    }
}
