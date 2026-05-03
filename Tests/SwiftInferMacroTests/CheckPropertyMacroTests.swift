import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import SwiftInferCore
@testable import SwiftInferMacroImpl

@Suite("@CheckProperty macro — diagnostics (M5.2 + M5.3 + M7.2.a)")
struct CheckPropertyMacroDiagnosticsTests {

    let testMacros: [String: Macro.Type] = [
        "CheckProperty": CheckPropertyMacro.self
    ]

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

    @Test
    func preservesInvariantArmRequiresUnaryShape() {
        assertMacroExpansion(
            """
            @CheckProperty(.preservesInvariant(\\.isValid))
            func merge(_ a: Widget, _ b: Widget) -> Widget { a }
            """,
            expandedSource: """
            func merge(_ a: Widget, _ b: Widget) -> Widget { a }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@CheckProperty(.preservesInvariant(_:)) requires"
                        + " `func name(_: T) -> U` — exactly one parameter and a non-nil"
                        + " return type. The keypath must resolve against T (and against"
                        + " U if it's a bool predicate on the output too).",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }
}

@Suite("@CheckProperty macro — idempotent expansion (M5.2)")
struct CheckPropertyMacroIdempotentTests {

    let testMacros: [String: Macro.Type] = [
        "CheckProperty": CheckPropertyMacro.self
    ]

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
        // `.todo` produce.
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
}

// MARK: - Shared expectation helpers

/// Build the byte-stable expansion we expect for an `.idempotent`
/// `@CheckProperty` attachment.
func expectedIdempotentExpansion(
    sourceFunction: String,
    funcName: String,
    generator: String,
    seed: SamplingSeed.Value
) -> String {
    let stateA = hex16(seed.stateA)
    let stateB = hex16(seed.stateB)
    let stateC = hex16(seed.stateC)
    let stateD = hex16(seed.stateD)
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
/// `@CheckProperty` attachment.
func expectedRoundTripExpansion(
    sourceFunction: String,
    forwardName: String,
    inverseName: String,
    generator: String,
    seed: SamplingSeed.Value
) -> String {
    let stateA = hex16(seed.stateA)
    let stateB = hex16(seed.stateB)
    let stateC = hex16(seed.stateC)
    let stateD = hex16(seed.stateD)
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

/// Build the byte-stable expansion we expect for a
/// `.preservesInvariant` `@CheckProperty` attachment (M7.2.a).
func expectedPreservesInvariantExpansion(
    sourceFunction: String,
    funcName: String,
    keyPath: String,
    generator: String,
    seed: SamplingSeed.Value
) -> String {
    let stateA = hex16(seed.stateA)
    let stateB = hex16(seed.stateB)
    let stateC = hex16(seed.stateC)
    let stateD = hex16(seed.stateD)
    let suffix = keyPath
        .replacingOccurrences(of: "\\.", with: "")
        .replacingOccurrences(of: ".", with: "_")
    return """
        \(sourceFunction)

        @Test func \(funcName)_preservesInvariant_\(suffix)() async {
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
                property: { value in !value[keyPath: \(keyPath)] || \(funcName)(value)[keyPath: \(keyPath)] }
            )
            if case let .failed(_, _, input, error) = result {
                Issue.record(
                    "\(funcName)(_:) failed invariant preservation \(keyPath) at input \\(input)."
                        + " \\(error?.message ?? \\"\\")"
                )
            }
        }
        """
}

func hex16(_ word: UInt64) -> String {
    let raw = String(word, radix: 16, uppercase: true)
    return String(repeating: "0", count: 16 - raw.count) + raw
}
