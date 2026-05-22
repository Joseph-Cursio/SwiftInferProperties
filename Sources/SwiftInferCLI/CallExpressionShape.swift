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
    ) -> Self {
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
    ///
    /// **V1.59.A.fix**: defends against the indexer producing
    /// already-qualified `primaryFunctionName` values. Cycle-56 OS
    /// picks (e.g. `OrderedSet.sort()`) carry a type-qualifier prefix
    /// in the indexed name; without this stripping the renderer would
    /// produce `OrderedSet.OrderedSet.sort`. Other carriers' picks
    /// (e.g. Complex's `exp(_:)`) come through as bare names, so the
    /// strip is a no-op for them.
    public static func render(
        typeQualifier: String,
        bareFunctionName: String
    ) -> String {
        let prefix = "\(typeQualifier)."
        let trueBareName: String
        if bareFunctionName.hasPrefix(prefix) {
            trueBareName = String(bareFunctionName.dropFirst(prefix.count))
        } else {
            trueBareName = bareFunctionName
        }
        return classify(
            typeQualifier: typeQualifier,
            bareFunctionName: trueBareName
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

    /// Carriers + their free-function-surface function names.
    /// **V1.54.A — empty after cycle-50 evidence**. v1.52.A's
    /// hypothesis was that swift-numerics's `_Numerics`-global
    /// `exp<T: ElementaryFunctions>(_:)` overloads would resolve from
    /// the verifier workdir's imports. Cycle-50 measurement (`docs/
    /// calibration-cycle-50-findings.md`) showed bare `exp(value)`
    /// doesn't compile from a workdir that imports only
    /// `ComplexModule` + `RealModule` — the `_Numerics`-globals live
    /// behind an `import _Numerics` that the workdir doesn't issue.
    /// Reverting to the v1.51 `.staticMethod` shape: `Complex.exp(_:)`
    /// is canonical Swift syntax for the static `exp` declared by
    /// `ElementaryFunctions`, compiles cleanly, and (via V1.53.A's
    /// DYLD fix) reaches the property check.
    ///
    /// The map stays as an extension point — v1.55+ may revive a
    /// free-function classification by adding `import _Numerics` to
    /// the V1.49.A preamble, at which point the EF surface entries
    /// can be restored here.
    static let freeFunctionMap: [String: Set<String>] = [:]
}
