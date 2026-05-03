import SwiftInferCore

/// TestLifter M4.3 — the §7.4 mock-inferred generator rung.
///
/// Queries an M4.1 `ConstructionRecord` for the type's observed
/// constructor sites and applies the §13 calibrated rule: synthesize a
/// `MockGenerator` only when the type has a *single* dominant
/// argument-shape with `siteCount ≥ 3`. Multi-shape types and
/// under-threshold types return `nil` (the conservative posture per
/// PRD §3.5 — when in doubt, fewer suggestions).
///
/// The synthesizer is a pure function — no I/O, no SwiftSyntax — and
/// runs after `GeneratorSelection.apply(...)` (the strategist-driven
/// pass) on `Suggestion`s whose source still says `.notYetComputed`.
/// Strategist-derived generators (`.derivedCaseIterable`,
/// `.derivedRawRepresentable`, `.derivedMemberwise`) are *never*
/// overwritten — corpus-side memberwise derivation always wins when
/// both a `TypeShape` and a construction record are present. M4 plan
/// §"Important scope clarifications" rationale: §7.4's fallback ladder
/// is ordered, and mock synthesis sits below memberwise.
///
/// Argument-shape → `MockGenerator.Argument` translation: the M4.1
/// scanner stores `ParameterizedValue.Kind` (an enum local to
/// `SwiftInferTestLifter`); the Core-side `MockGenerator.Argument`
/// stores `swiftTypeName: String` so the M4.4 renderer can wrap
/// `Gen<\(swiftTypeName)>` directly without enum-to-typename
/// translation. The `swiftTypeName(for:)` helper here is the boundary.
public enum MockGeneratorSynthesizer {

    /// Synthesize a `MockGenerator` for `typeName` if the construction
    /// record carries a single dominant shape with `siteCount ≥ 3`;
    /// otherwise return `nil`. Pure function over the record + type
    /// name.
    public static func synthesize(
        typeName: String,
        record: ConstructionRecord
    ) -> MockGenerator? {
        let entries = record.entries(for: typeName)
        // Multi-shape types are ambiguous — return nil per OD #3 default.
        guard entries.count == 1 else {
            return nil
        }
        let entry = entries[0]
        // §13 threshold per OD #1 default.
        guard entry.siteCount >= 3 else {
            return nil
        }
        let argumentSpec = entry.shape.arguments.enumerated().map { offset, argument in
            MockGenerator.Argument(
                label: argument.label,
                swiftTypeName: swiftTypeName(for: argument.kind),
                observedLiterals: entry.observedLiterals.map { row in
                    offset < row.count ? row[offset] : ""
                }
            )
        }
        return MockGenerator(
            typeName: typeName,
            argumentSpec: argumentSpec,
            siteCount: entry.siteCount
        )
    }

    /// Boundary mapping: TestLifter-side literal kinds → Swift type
    /// names the M4.4 renderer wraps with `Gen<...>`. Through M4 the
    /// four cases below cover the slicer's `ParameterizedValue.Kind`
    /// shape; future literal classifiers (collections / optionals)
    /// extend this without changing the Core surface.
    private static func swiftTypeName(for kind: ParameterizedValue.Kind) -> String {
        switch kind {
        case .integer: return "Int"
        case .string:  return "String"
        case .boolean: return "Bool"
        case .float:   return "Double"
        }
    }
}
