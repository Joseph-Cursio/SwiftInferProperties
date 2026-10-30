@testable import SwiftInferCore
@testable import SwiftInferMacroImpl
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

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
                        + " parameter type and return type to differ. For a T -> T"
                        + " idempotency check, use SwiftIdempotency's `@Idempotent`"
                        + " with `@IdempotencyTests`.",
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
            valueType: "String",
            generator: formattedStringGenerator(),
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
            valueType: "Int",
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
        // Non-RawType parameters fall through to `<TypeName>.gen()` with
        // the `.todo` marker comment, the same convention
        // `DerivationStrategist.userGen` / `.todo` produce.
        let canonical = "checkProperty.idempotent|sanitize|(IntSet)->IntSet"
        let seed = SamplingSeed.derive(fromIdentityHash: canonical)
        let expected = expectedIdempotentExpansion(
            sourceFunction: "func sanitize(_ value: IntSet) -> IntSet { value }",
            funcName: "sanitize",
            valueType: "IntSet",
            generator: todoGenerator("IntSet"),
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
    valueType: String,
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
                sample: { rng in
                    (\(generator)).run(using: &rng)
                },
                property: { (value: \(valueType)) in
                    \(funcName)(\(funcName)(value)) == \(funcName)(value)
                }
            )
            if case let .failed(_, _, input, error) = result {
                Issue.record(
                    "\(funcName)(_:) failed idempotence at input \\(input). \\(error?.message ?? "")"
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
                sample: { rng in
                    (\(generator)).run(using: &rng)
                },
                property: { value in
                    \(inverseName)(\(forwardName)(value)) == value
                }
            )
            if case let .failed(_, _, input, error) = result {
                Issue.record(
                    "\(forwardName)/\(inverseName) round-trip failed at input \\(input). \\(error?.message ?? "")"
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
    let escapedKeyPath = keyPath.replacingOccurrences(of: "\\", with: "\\\\")
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
                sample: { rng in
                    (\(generator)).run(using: &rng)
                },
                property: { value in
                    !value[keyPath: \(keyPath)] || \(funcName)(value) [keyPath: \(keyPath)]
                }
            )
            if case let .failed(_, _, input, error) = result {
                Issue.record(
                    "\(funcName)(_:) failed invariant preservation \(escapedKeyPath) \
        at input \\(input). \\(error?.message ?? "")"
                )
            }
        }
        """
}

/// What the macro emits for a type it derives no generator for.
func todoGenerator(_ typeName: String) -> String {
    "\(typeName).gen() /* TODO: no generator derived — supply `static func gen()`; this will not compile */"
}

/// The String generator the macro emits, PropertyLawCore's edge-biased
/// `RawType.string` expression, as swift-syntax formats it inside the
/// `sample:` closure. The formatter breaks it at each closure and indents the
/// pieces from where it sits in the expansion, so it is pinned here as
/// emitted rather than rebuilt from the kit's one-line source.
func formattedStringGenerator() -> String {
    let tokens = ##"Gen<String?>.element(of: ["", " ", "  ", "\n", "\t", "-", "- ", "  -", "- x", "a\n- b", "##
        + ##"":", "#", "# ", "/"] as [String])"##
    func indented(_ depth: Int, _ line: String) -> String {
        String(repeating: " ", count: depth) + line
    }
    return [
        "Gen.frequency((3.0, Gen<Character>.letterOrNumber.string(of: 0 ... 8)), (1.0, \(tokens).map {",
        indented(28, "$0!"),
        indented(24, "}), (3.0, \(tokens).map {"),
        indented(28, "$0!"),
        indented(24, "} .map {"),
        indented(28, "$0 + $0"),
        indented(24, "}), (1.0, zip(\(tokens).map {"),
        indented(32, "$0!"),
        indented(28, "}, Gen<Character>.letterOrNumber.string(of: 0 ... 4)).map {"),
        indented(28, "$0 + $1"),
        indented(24, "}))")
    ].joined(separator: "\n")
}

func hex16(_ word: UInt64) -> String {
    let raw = String(word, radix: 16, uppercase: true)
    return String(repeating: "0", count: 16 - raw.count) + raw
}
