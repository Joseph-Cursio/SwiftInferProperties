@testable import SwiftInferCore
@testable import SwiftInferMacroImpl
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing

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
