import Foundation

/// V1.52.A — classifies the Swift call-expression shape for a function
/// indexed under a carrier type.
///
/// **Why this exists.** v1.42–v1.51 built the call expression as
/// `"\(typeQualifier).\(funcName)"`, treating every function as a
/// static method on the carrier. Cycle-48 measurement (`docs/
/// calibration-cycle-48-findings.md`) revealed two cases where that
/// shape doesn't compile:
///
///   - **Operator-named functions** (e.g. `+(z:w:)`, `/(z:w:)`). The
///     resolver produced `Complex./` but Swift needs `(/)` —
///     parenthesized operator-as-function syntax.
///   - **Free functions promoted to type namespaces.** swift-numerics
///     ships global `exp<T: ElementaryFunctions>(_ x: T) -> T`
///     overloads (defined in `_Numerics.swift`). The indexer attaches
///     these to the carrier (`Complex`, `Double`, `Float`) because
///     they appear in the type's surface, but the canonical call form
///     is `exp(value)` not `Complex.exp(value)`. The static-method
///     form *does* compile (Complex conforms to ElementaryFunctions
///     and exposes static `exp(_:)`), but the runtime resolution path
///     differs from the property under test, surfacing as
///     subprocess SIGABRTs in cycle-48.
///
/// **Decision boundary.** Three cases:
///   - `.operatorFunction(name:)` — emit `"(\(name))"` (e.g. `(/)`,
///     `(+)`). Triggered when the bare function name is composed
///     entirely of Swift operator characters.
///   - `.freeFunction(name:)` — emit `"\(name)"` (no qualifier).
///     Triggered when `(carrier, bareFunctionName)` is in the
///     curated `freeFunctionMap`. Initial entries cover the
///     14-method `ElementaryFunctions` protocol surface over the
///     three carriers v1.49 supports (Complex, Double, Float).
///   - `.staticMethod(qualifier:method:)` — emit
///     `"\(qualifier).\(method)"` (the v1.42–v1.51 default). All
///     other cases.
///
/// **Bit-stability.** For all carriers not in `freeFunctionCarriers`
/// (everything except Complex / Double / Float) and all non-operator
/// function names, `classify(...).rendered` produces a string
/// bit-identical to the v1.51 `"\(typeQualifier).\(funcName)"`
/// interpolation. The classifier is a strict refinement; no
/// pre-cycle-48 test fixture changes shape unless it explicitly
/// references an operator-named or ElementaryFunctions-surface call.
public enum CallExpressionShape: Equatable, Sendable {

    case staticMethod(qualifier: String, method: String)
    case operatorFunction(name: String)
    case freeFunction(name: String)

    /// Classify the call-expression shape from a bare type qualifier
    /// (e.g. `"Complex"`, `"Double"`, `"Int"`) and a parameter-label-
    /// stripped function name (e.g. `"exp"`, `"/"`, `"binomial"`).
    ///
    /// The `typeQualifier` should be the post-`RoundTripPairResolver
    /// .bareTypeName` form (generic args stripped). The
    /// `bareFunctionName` should be the post-`RoundTripPairResolver
    /// .stripParameterLabels` form (parameter labels stripped).
    public static func classify(
        typeQualifier: String,
        bareFunctionName: String
    ) -> CallExpressionShape {
        if isOperatorName(bareFunctionName) {
            return .operatorFunction(name: bareFunctionName)
        }
        if let carrierFreeFunctions = freeFunctionMap[typeQualifier],
           carrierFreeFunctions.contains(bareFunctionName) {
            return .freeFunction(name: bareFunctionName)
        }
        return .staticMethod(qualifier: typeQualifier, method: bareFunctionName)
    }

    /// The rendered Swift call-expression prefix. The synthesized
    /// stub then appends `(value)` / `(lhs, rhs)` / etc.
    public var rendered: String {
        switch self {
        case let .staticMethod(qualifier, method):
            return "\(qualifier).\(method)"
        case let .operatorFunction(name):
            return "(\(name))"
        case let .freeFunction(name):
            return name
        }
    }

    /// One-shot helper: classify and render in a single call. Equivalent
    /// to `classify(...).rendered`.
    public static func render(
        typeQualifier: String,
        bareFunctionName: String
    ) -> String {
        classify(
            typeQualifier: typeQualifier,
            bareFunctionName: bareFunctionName
        ).rendered
    }

    // MARK: - Classification rules

    /// Swift's binary/unary operator character set, per the Swift
    /// reference's "Operators" chapter. Restricted to the ASCII subset
    /// — Unicode-operator support is intentionally out of scope for
    /// v1.52 since the cycle-27 corpus has no Unicode operators.
    ///
    /// Excludes `.` to avoid matching the qualifier separator. Custom
    /// operators using only `.` characters are vanishingly rare and
    /// would need a different shape anyway.
    private static let operatorCharacters: Set<Character> = [
        "+", "-", "*", "/", "%",
        "<", ">", "=", "!",
        "&", "|", "^", "~", "?"
    ]

    /// Returns `true` if `name` is non-empty and every character is in
    /// `operatorCharacters`. Examples: `"+"`, `"/"`, `"<<"`, `"=="`
    /// return true; `"exp"`, `"_relaxedMul"`, `"+1"` (digit) return
    /// false.
    static func isOperatorName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return name.allSatisfy { operatorCharacters.contains($0) }
    }

    /// Carriers + their `ElementaryFunctions`-surface function names.
    /// v1.52 ships with the three v1.49-emitter-supported carriers
    /// (Complex, Double, Float) mapped to the 14-method protocol
    /// surface. v1.53+ extends as new carriers gain emitter support.
    ///
    /// **Why this is a static curated table, not indexer-derived.**
    /// `SemanticIndexEntry` doesn't carry conformance information
    /// (schema bump deferred — see plan §V1.52.A.b.ii). The
    /// ElementaryFunctions protocol surface is small (14 entries) and
    /// stable, so a hardcoded table is the lowest-friction option.
    static let freeFunctionMap: [String: Set<String>] = [
        "Complex": elementaryFunctionsNames,
        "Double": elementaryFunctionsNames,
        "Float": elementaryFunctionsNames
    ]

    /// The 14-method `ElementaryFunctions` protocol surface from
    /// swift-numerics. `exp`/`log` + the 6 trig + 6 hyperbolic
    /// inverses; matches the curated round-trip pair list in
    /// `RoundTripPairResolver.curated`.
    ///
    /// **Not included**: `pow(_:_:)` (binary, not in the round-trip
    /// shape); `sqrt(_:)` (not in cycle-27's surface but valid
    /// ElementaryFunctions member — add when first cycle-N surface
    /// references it).
    private static let elementaryFunctionsNames: Set<String> = [
        "exp", "log",
        "sin", "cos", "tan",
        "asin", "acos", "atan",
        "sinh", "cosh", "tanh",
        "asinh", "acosh", "atanh"
    ]
}
