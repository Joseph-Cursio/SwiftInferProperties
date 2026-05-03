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
    ///
    /// **M7.1 — non-determinism suppression.** PRD §3.5 + Appendix
    /// B.3: when a constructor's test fixtures pass non-deterministic
    /// API calls (`Date()`, `UUID()`, `Random.next()`, etc.) as
    /// argument values, the mock-inferred generator MUST NOT fire —
    /// emitting `Gen<T> { _ in T(timestamp: Date(), id: UUID()) }`
    /// produces the SAME Date/UUID every trial, defeating the
    /// purpose of property testing. The synthesizer rejects records
    /// with any non-deterministic literal in any position.
    ///
    /// In practice the M4.1 `SetupRegionConstructionScanner` already
    /// skips constructor sites whose args aren't literal kinds —
    /// `Date()` is a `FunctionCallExpr`, not a literal, so the
    /// scanner returns `nil` from `fingerprint(...)` and the entire
    /// site is invisible to synthesis. This explicit check is
    /// belt-and-suspenders against future scanner widening that
    /// admits function-call args (e.g. M9 expanded-outputs).
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
        // M7.1 — explicit non-determinism check.
        if containsNonDeterministicLiteral(in: entry) {
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

    /// Curated list of non-deterministic API call surface texts.
    /// Mirrors `BodySignalVisitor.NonDeterministicAPIs` on the
    /// production-side; kept locally here so the two paths can
    /// evolve independently if the curated set grows. PRD §4.1's
    /// non-deterministic-body counter-signal cites this same list.
    private static let nonDeterministicLiteralPatterns: [String] = [
        "Date()",
        "Date.now",
        "UUID()",
        "URLSession.shared",
        "arc4random()",
        "arc4random_uniform(",
        "drand48()",
        "rand()",
        "random()",
        ".random()",
        ".random(in:"
    ]

    /// `true` if any observed literal in any argument position of
    /// `entry` matches a curated non-deterministic API call surface
    /// (`Date()`, `Date.now`, `UUID()`, `Random.next()`, etc.).
    /// Substring match against the trimmed literal text — handles
    /// both `"Date()"` exact and `"Int.random(in: 0...100)"` partial
    /// matches via the `.random(in:` prefix entry.
    static func containsNonDeterministicLiteral(in entry: ConstructionRecordEntry) -> Bool {
        for row in entry.observedLiterals {
            for literal in row where matchesNonDeterministicPattern(literal) {
                return true
            }
        }
        return false
    }

    private static func matchesNonDeterministicPattern(_ literal: String) -> Bool {
        nonDeterministicLiteralPatterns.contains { pattern in
            literal.contains(pattern)
        }
    }
}
