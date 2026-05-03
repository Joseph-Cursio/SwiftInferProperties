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
            // M9.2 — prepend an `// Inferred precondition:` comment line
            // above the generator expression when the synthesizer
            // surfaced a hint for position 0. Two-space indent matches
            // the surrounding stub indentation pattern.
            let hintComment = preconditionCommentLine(for: 0, in: mock).map { "  \($0)\n            " } ?? ""
            return "\(hintComment)\(generators[0])\n            .map { \(typeName)(\(labelPrefix)$0) }"
        }
        // Multi-arg case — switch from single-line `zip(g1, g2)` to a
        // multi-line shape so per-position `// Inferred precondition:`
        // comments can sit above each generator expression. Without
        // hints the multi-line shape still renders correctly; the
        // hint-line emission is the only conditional bit.
        let argumentLines = generators.enumerated().map { index, generatorExpr -> String in
            let hintLine = preconditionCommentLine(for: index, in: mock)
                .map { "                \($0)\n" } ?? ""
            return "\(hintLine)                \(generatorExpr)"
        }.joined(separator: ",\n")
        let constructionArgs = mock.argumentSpec.enumerated()
            .map { index, argument -> String in
                let labelPrefix = argument.label.map { "\($0): " } ?? ""
                return "\(labelPrefix)$0.\(index)"
            }
            .joined(separator: ", ")
        return "zip(\n\(argumentLines)\n            )\n            "
            + ".map { \(typeName)(\(constructionArgs)) }"
    }

    /// Render a single `// Inferred precondition:` comment line for the
    /// hint at `position` in `mock.preconditionHints`, or `nil` if no
    /// hint was synthesized for that position. The line text is
    /// self-explanatory: identifies the argument by label (or
    /// `positional[N]` for nil-label), summarizes the detected pattern,
    /// cites the site count, and surfaces the inferrer's pre-computed
    /// `suggestedGenerator` expression. PRD §3.5 conservative posture:
    /// the user-visible default generator is unchanged; the hint is
    /// advisory.
    private static func preconditionCommentLine(
        for position: Int,
        in mock: MockGenerator
    ) -> String? {
        guard let hint = mock.preconditionHints.first(where: { $0.position == position }) else {
            return nil
        }
        let label = hint.argumentLabel ?? "positional[\(hint.position)]"
        let description = describePattern(hint.pattern)
        let sitesPlural = hint.siteCount == 1 ? "site" : "sites"
        return "// Inferred precondition: \(label) — \(description) across "
            + "\(hint.siteCount) \(sitesPlural) — consider \(hint.suggestedGenerator)"
    }

    private static func describePattern(_ pattern: PreconditionPattern) -> String {
        switch pattern {
        case .positiveInt:
            return "all observed values are positive Int"
        case .nonNegativeInt:
            return "all observed values are non-negative Int"
        case .negativeInt:
            return "all observed values are negative Int"
        case .intRange(let low, let high):
            return "all observed values are in [\(low), \(high)]"
        case .nonEmptyString:
            return "all observed strings are non-empty"
        case .stringLength(let low, let high):
            return "all observed strings have length in [\(low), \(high)]"
        case .constantBool(let value):
            return "all observed values are \(value)"
        }
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

    /// TestLifter M5.4 — emit the Codable round-trip generator scaffold
    /// for `typeName`. Dispatched from `chooseGenerator(for:typeName:)`
    /// when `Suggestion.generator.source == .derivedCodableRoundTrip`
    /// (set by `GeneratorSelection.applyCodableRoundTripFallback(...)`).
    /// The body uses `Foundation.JSONEncoder` / `JSONDecoder`; the
    /// writeout wrapper widens its imports list to include
    /// `Foundation` for this source so the rendered stub compiles.
    static func codableRoundTripGenerator(for typeName: String) -> String {
        CodableRoundTripGeneratorRenderer.renderGenerator(for: typeName)
    }
}
