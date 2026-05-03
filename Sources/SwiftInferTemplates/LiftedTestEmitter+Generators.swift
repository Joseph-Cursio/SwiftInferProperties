import ProtoLawCore
import SwiftInferCore

/// `LiftedTestEmitter` generator-expression helpers — split out of
/// `LiftedTestEmitter.swift` to keep the main file under SwiftLint's
/// file-length limit (M4.4 split). The `defaultGenerator(for:)` and
/// `mockInferredGenerator(_:)` functions are the two paths
/// `InteractiveTriage+Accept`'s `chooseGenerator(for:typeName:)`
/// dispatches between based on `Suggestion.generator.source` +
/// `mockGenerator` presence.
public extension LiftedTestEmitter {

    /// Pick the canonical generator expression for `typeName`. If it
    /// matches a `ProtoLawCore.RawType` (stdlib `Int`, `String`,
    /// `Bool`, etc.), emit the kit's `RawType.generatorExpression` so
    /// the M4.2 generator-selection convention holds. Otherwise emit
    /// `\(typeName).gen()` — same fallback the
    /// `DerivationStrategist` produces for non-derivable types,
    /// requiring the user to provide `static func gen() -> Gen<T>`
    /// or take the missing-symbol compile error.
    static func defaultGenerator(for typeName: String) -> String {
        if let rawType = RawType(typeName: typeName) {
            return rawType.generatorExpression
        }
        return "\(typeName).gen()"
    }

    /// TestLifter M4.4 — emit a `Gen<T>` expression for a mock-inferred
    /// generator synthesized from observed test construction sites.
    /// Mirrors `MemberwiseEmitter`'s `zip(...).map { Type(...) }` shape
    /// for parameterized constructors and falls back to
    /// `Gen<Type> { _ in Type() }` for the empty-constructor case
    /// (where `MemberwiseEmitter`'s ≥1-member precondition would trip).
    /// Each argument's `swiftTypeName` is resolved against the kit's
    /// `RawType.generatorExpression` table — through M4 the four
    /// supported types (`Int` / `String` / `Bool` / `Double`) all
    /// resolve, so non-`RawType` arguments don't reach this path.
    /// (`MockGeneratorSynthesizer.swiftTypeName(for:)` produces only
    /// these four names; if the M5+ literal classifier widens the
    /// shape, this path needs the corresponding update.)
    static func mockInferredGenerator(_ mock: MockGenerator) -> String {
        let typeName = mock.typeName
        guard !mock.argumentSpec.isEmpty else {
            // Empty-constructor mock — the test corpus consistently
            // built `\(typeName)()` with no args. Emit a Gen that
            // always produces the default value.
            return "Gen<\(typeName)> { _ in \(typeName)() }"
        }
        let generators = mock.argumentSpec.map { argument in
            generatorExpression(forSwiftTypeName: argument.swiftTypeName)
        }
        if mock.argumentSpec.count == 1 {
            let argument = mock.argumentSpec[0]
            let labelPrefix = argument.label.map { "\($0): " } ?? ""
            return "\(generators[0])\n            .map { \(typeName)(\(labelPrefix)$0) }"
        }
        let zipArgs = generators.joined(separator: ", ")
        let constructionArgs = mock.argumentSpec.enumerated()
            .map { index, argument -> String in
                let labelPrefix = argument.label.map { "\($0): " } ?? ""
                return "\(labelPrefix)$0.\(index)"
            }
            .joined(separator: ", ")
        return "zip(\(zipArgs))\n            .map { \(typeName)(\(constructionArgs)) }"
    }

    /// Resolve `swiftTypeName` ("Int" / "String" / "Bool" / "Double")
    /// to the kit's RawType generator expression. Non-RawType names
    /// shouldn't reach this path through M4 (synthesizer guarantees
    /// the four supported types); guard with a `\(typeName).gen()`
    /// fallback so a future widening doesn't crash the renderer.
    private static func generatorExpression(forSwiftTypeName typeName: String) -> String {
        if let rawType = RawType(typeName: typeName) {
            return rawType.generatorExpression
        }
        return "\(typeName).gen()"
    }
}
