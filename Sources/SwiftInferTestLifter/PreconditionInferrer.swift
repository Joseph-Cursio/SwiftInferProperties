import SwiftInferCore

/// TestLifter M9.1 — pure-function precondition inference over an
/// M4.1 `ConstructionRecordEntry`. Examines each argument position's
/// observed-literal column and emits a `PreconditionHint` when the
/// entire column matches one of the curated patterns:
///
/// - **Numerical bounds** (`Int` only per M9 plan OD #1): `positiveInt`
///   / `nonNegativeInt` / `negativeInt` / `intRange(low, high)`.
/// - **String shape**: `nonEmptyString` / `stringLength(low, high)`.
/// - **Boolean monomorphism**: `constantBool(value)`.
///
/// **§3.5 conservative bias.** A pattern emits ONLY if every observed
/// literal in the column matches; one outlier kills it. Under-threshold
/// entries (`siteCount < 3`) emit nothing — same threshold as M4.3's
/// `MockGeneratorSynthesizer`.
///
/// **Pattern priority** (M9 plan OD #4): when multiple patterns match,
/// the most-specific case wins. For ints, `intRange` (≥ 2 distinct
/// values) preempts the sign-bound patterns. For strings, `stringLength`
/// (≥ 2 distinct lengths) preempts `nonEmptyString`.
///
/// **Pure function.** No I/O, no SwiftSyntax, no FunctionSummary lookup.
/// The §13 100-test-file budget passes through unchanged — per-position
/// literal-text classification is sub-millisecond per record.
public enum PreconditionInferrer {

    /// Detection threshold mirrors M4.3's mock-synthesis bar. Per M9
    /// plan §"Important scope clarifications", a precondition observed
    /// on fewer sites is too thin to surface confidently.
    public static let minimumSiteCount: Int = 3

    /// Examine each argument position in `entry` and return one
    /// `PreconditionHint` per position whose observed-literal column
    /// matches a curated pattern. Returns `[]` when the entry is under
    /// the site threshold or no position's column produces a match.
    public static func infer(from entry: ConstructionRecordEntry) -> [PreconditionHint] {
        guard entry.siteCount >= minimumSiteCount else {
            return []
        }
        var hints: [PreconditionHint] = []
        for (position, argument) in entry.shape.arguments.enumerated() {
            let column = entry.observedLiterals.compactMap { row -> String? in
                position < row.count ? row[position] : nil
            }
            // Conservative: if any row is shorter than expected, skip
            // this position entirely. The scanner aligns rows to shape
            // length, so this is defensive cover for malformed inputs.
            guard column.count == entry.observedLiterals.count else {
                continue
            }
            guard let pattern = detectPattern(kind: argument.kind, column: column) else {
                continue
            }
            hints.append(PreconditionHint(
                position: position,
                argumentLabel: argument.label,
                pattern: pattern,
                siteCount: entry.siteCount,
                suggestedGenerator: suggestedGenerator(for: pattern)
            ))
        }
        return hints
    }

    // MARK: - Per-kind dispatch

    private static func detectPattern(
        kind: ParameterizedValue.Kind,
        column: [String]
    ) -> PreconditionPattern? {
        switch kind {
        case .integer: return detectIntegerPattern(column)
        case .string:  return detectStringPattern(column)
        case .boolean: return detectBooleanPattern(column)
        case .float:   return nil  // OD #1: deferred to v1.x — precision-class concerns
        }
    }

    // MARK: - Integer patterns

    private static func detectIntegerPattern(_ column: [String]) -> PreconditionPattern? {
        var values: [Int] = []
        for literal in column {
            guard let value = parseIntLiteral(literal) else {
                return nil
            }
            values.append(value)
        }
        guard let minVal = values.min(), let maxVal = values.max() else {
            return nil
        }
        let distinctCount = Set(values).count
        // Most-specific: range with ≥ 2 distinct values.
        if distinctCount >= 2 {
            return .intRange(low: minVal, high: maxVal)
        }
        // Single-value column → fall through to sign-bound patterns.
        if values.allSatisfy({ $0 > 0 }) {
            return .positiveInt
        }
        if values.allSatisfy({ $0 >= 0 }) {
            return .nonNegativeInt
        }
        if values.allSatisfy({ $0 < 0 }) {
            return .negativeInt
        }
        return nil
    }

    /// Parse the source-text form of an `IntegerLiteralExprSyntax`'s
    /// `trimmedDescription`. Handles underscore separators (`1_000`)
    /// and a leading `-` for defensive cover (today's M4.1 scanner
    /// doesn't fingerprint negative literals because they parse as
    /// `PrefixOperatorExpr`, but a future scanner widening might admit
    /// them). Hex / octal / binary radix prefixes return `nil` —
    /// per the conservative posture, an unparseable literal kills the
    /// entire column's hint.
    private static func parseIntLiteral(_ literal: String) -> Int? {
        let cleaned = literal.replacingOccurrences(of: "_", with: "")
        return Int(cleaned)
    }

    // MARK: - String patterns

    private static func detectStringPattern(_ column: [String]) -> PreconditionPattern? {
        var contents: [String] = []
        for literal in column {
            guard let stripped = stringContent(of: literal) else {
                return nil
            }
            contents.append(stripped)
        }
        let lengths = contents.map(\.count)
        guard let minLen = lengths.min(), let maxLen = lengths.max() else {
            return nil
        }
        let distinctLengths = Set(lengths).count
        // Most-specific: stringLength with ≥ 2 distinct lengths (M9 plan OD #3).
        if distinctLengths >= 2 {
            return .stringLength(low: minLen, high: maxLen)
        }
        // Single-length column → fall through to non-empty pattern.
        if contents.allSatisfy({ !$0.isEmpty }) {
            return .nonEmptyString
        }
        return nil
    }

    /// Extract the inner content of a Swift string literal's source
    /// text. Conservative — handles only simple single-line literals
    /// (`"foo"`); multi-line (`"""..."""`), raw (`#"..."#`), and any
    /// literal containing string interpolation or backslash escapes
    /// returns `nil`. PRD §3.5 conservative posture: rather than
    /// risk mis-counting length on escaped content, kill the column.
    private static func stringContent(of literal: String) -> String? {
        if literal.hasPrefix("\"\"\"") {
            return nil  // multi-line — defer
        }
        if literal.hasPrefix("#") {
            return nil  // raw string — defer
        }
        guard literal.count >= 2 else {
            return nil
        }
        guard literal.hasPrefix("\""), literal.hasSuffix("\"") else {
            return nil
        }
        let inner = String(literal.dropFirst().dropLast())
        // Reject any backslash content — interpolation `\(` or escape
        // sequences like `\n` change the source-vs-string-length
        // relationship. Conservative: skip.
        if inner.contains("\\") {
            return nil
        }
        return inner
    }

    // MARK: - Boolean patterns

    private static func detectBooleanPattern(_ column: [String]) -> PreconditionPattern? {
        if column.allSatisfy({ $0 == "true" }) {
            return .constantBool(value: true)
        }
        if column.allSatisfy({ $0 == "false" }) {
            return .constantBool(value: false)
        }
        return nil
    }

    // MARK: - Suggested generator rendering

    /// Pre-compute the recommended generator expression so M9.2's
    /// renderer doesn't re-derive it per pattern. The strings here are
    /// rendered verbatim into `// Inferred precondition:` comment
    /// lines; they don't have to compile (they're advisory) but they
    /// should read as plausible Swift.
    private static func suggestedGenerator(for pattern: PreconditionPattern) -> String {
        switch pattern {
        case .positiveInt:
            return "Gen.int(in: 1...)"
        case .nonNegativeInt:
            return "Gen.int(in: 0...)"
        case .negativeInt:
            return "Gen.int(in: ...(-1))"
        case .intRange(let low, let high):
            return "Gen.int(in: \(low)...\(high))"
        case .nonEmptyString:
            return "Gen.string()  // verify empty-string case is acceptable"
        case .stringLength(let low, let high):
            return "Gen.string(of: \(low)...\(high))"
        case .constantBool(let value):
            return "Gen.always(\(value))  // observed only \(value) — opposite case may be untested"
        }
    }
}
