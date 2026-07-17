import SwiftInferCore

/// B25 (issue #1) — the runnable form of the predicate reference definition.
///
/// A `predicate` law is `unsupported-template: predicate` at verify time: it has
/// no oracle to run against without a reference definition "only you can state."
/// The docstring states it (B23), but as prose. This emitter closes the gap by
/// generating the *runnable* scaffold: a `<name>_reference` stub carrying the
/// docstring as its guide, plus the property that runs the predicate against it.
///
/// The division of labor is the one walk 10 exposed: the reader supplies the one
/// boolean the docstring already dictates (the part only they can state), and the
/// generator finds the input where the code disagrees with its own documentation
/// (the part the reader skipped by hand — five of six walk-10 readers named the
/// contract and never ran it). Point, don't synthesize — pushed one stage on, so
/// the pointed-at sentence becomes executable.
extension LiftedTestEmitter {

    /// One parameter of a reference oracle paired with the `Gen<T>` it draws from.
    public struct ReferenceOracleArgument: Sendable, Equatable {
        public let parameter: Parameter
        public let generator: String

        public init(parameter: Parameter, generator: String) {
            self.parameter = parameter
            self.generator = generator
        }
    }

    /// Emit the reference-oracle stub + property for a documented function
    /// `funcName: (T...) -> R` of any arity whose return `R` is `Equatable`.
    ///
    /// This is the runnable form of a reference definition — a `<name>_reference`
    /// the reader writes from the docstring, checked against the code by
    /// `f(x) == f_reference(x)`. It serves three callers: a `predicate` and a
    /// `comparator` (`R == Bool`, the docstring is the boolean law / the ordering
    /// key), and the determinism-fallback contract (`R` is the value type, the
    /// docstring is the computation the templates could not name — the reference
    /// is a from-the-spec re-implementation, differential testing).
    ///
    /// A single parameter draws one `value`; two or more draw a `tuple` the
    /// property indexes (`tuple.0`, `tuple.1`, …) — the commutativity arm's pair
    /// shape. Argument labels are preserved in both calls, so a `canReach(from:to:)`
    /// compares against a `canReach_reference(from:to:)` of the same signature.
    ///
    /// - Parameters:
    ///   - funcName: the function's base name (e.g. `isValidQuantity`).
    ///   - arguments: its parameters + per-parameter generators, in order (non-empty).
    ///   - returnTypeText: the return type `R` (`"Bool"` for predicate/comparator).
    ///   - docComment: the reflowed docstring — shown verbatim as the definition.
    ///   - seed: sampling seed (derive from the suggestion identity for stability).
    public static func referenceOracle(
        funcName: String,
        arguments: [ReferenceOracleArgument],
        returnTypeText: String,
        docComment: String,
        seed: SamplingSeed.Value
    ) -> String {
        guard !arguments.isEmpty else { return "" }
        let parameters = arguments.map(\.parameter)
        let referenceName = "\(funcName)_reference"
        let paramClause = parameters
            .map { parameterClause(label: $0.label, name: $0.internalName, typeText: $0.typeText) }
            .joined(separator: ", ")
        let equatableNote = returnTypeText == "Bool" ? "" :
            "// (the return type \(returnTypeText) must be Equatable for this to compile)\n"

        let stub = """
        // Fill in the reference definition below — your docstring already states it:
        //   "\(docComment)"
        // Then run the test: the generator finds the input where the code disagrees
        // with its own documentation.
        \(equatableNote)func \(referenceName)(\(paramClause)) -> \(returnTypeText) {
            fatalError("state the reference definition from the docstring, then replace this line")
        }
        """

        let biased = arguments.map { edgeBiasedGenerator(forTypeText: $0.parameter.typeText, fallback: $0.generator) }
        let (closureParam, sample) = sampleClause(generators: biased)
        let callArgs = callArguments(parameters: parameters, boundTo: closureParam)
        let property = "{ \(closureParam) in "
            + "\(funcName)(\(callArgs)) == \(referenceName)(\(callArgs)) }"

        let test = makeTestStubExpression(
            testFunctionName: "\(funcName)_matchesReferenceDefinition",
            seed: seed,
            sampleExpression: sample,
            propertyExpression: property,
            failureLabel: "\(funcName)\(labelSelector(parameters)) "
                + "disagrees with its documented reference definition"
        )
        return stub + "\n" + test
    }

    /// The sample closure and the name its produced value binds to. One
    /// parameter yields a scalar bound to `value`; several yield a tuple bound
    /// to `tuple`, drawn component-wise.
    private static func sampleClause(generators: [String]) -> (closureParam: String, sample: String) {
        if generators.count == 1 {
            return ("value", "{ rng in (\(generators[0])).run(using: &rng) }")
        }
        let draws = generators.map { "(\($0)).run(using: &rng)" }.joined(separator: ", ")
        return ("tuple", "{ rng in (\(draws)) }")
    }

    /// The argument list for a call to the predicate / its reference, binding
    /// each parameter to `value` (single) or `tuple.<i>` (multi), with labels.
    private static func callArguments(parameters: [Parameter], boundTo closureParam: String) -> String {
        let arguments = parameters.enumerated().map { index, parameter -> String in
            let valueExpression = parameters.count == 1 ? closureParam : "\(closureParam).\(index)"
            if let label = parameter.label {
                return "\(label): \(valueExpression)"
            }
            return valueExpression
        }
        return arguments.joined(separator: ", ")
    }

    /// `(_:)`, `(from:to:)` — the labelled selector for the failure message.
    private static func labelSelector(_ parameters: [Parameter]) -> String {
        "(" + parameters.map { "\($0.label ?? "_"):" }.joined() + ")"
    }

    /// Wrap a numeric generator to mix a uniform baseline (weight 3) with the
    /// curated boundary values (weight 2) where contract bugs live — above all
    /// **zero**, the point a `> 0` / `>= 0` slip hides at. A uniform range
    /// generator samples the boundary with measure zero and false-passes; this is
    /// the numeric analog of the kit's String edge-biasing.
    ///
    /// For integer types the baseline is the kit's `boundedForArithmetic()`, NOT
    /// the unbounded `Gen<Int>.int()` fallback: an unbounded draw produces
    /// billion-scale values, and a function with an O(n) loop on that parameter
    /// (`roundToPlaces`'s `0..<abs(places)`) then runs effectively forever. The
    /// bound (`2^(bitWidth/4)`, ~65k for `Int`) keeps loops fast while still
    /// reaching the boundary via the edge arm. Floats keep the fallback (already
    /// bounded to ±1e6). Non-numeric types return the fallback unchanged.
    private static func edgeBiasedGenerator(forTypeText typeText: String, fallback: String) -> String {
        let edges: String
        let uniform: String
        switch typeText {
        case "Double", "Float", "CGFloat", "Float16", "Float32", "Float64", "Float80":
            edges = "0.0, -1.0, 1.0"
            uniform = fallback

        case "Int", "Int8", "Int16", "Int32", "Int64":
            edges = "0, -1, 1"
            uniform = "Gen<\(typeText)>.boundedForArithmetic()"

        case "UInt", "UInt8", "UInt16", "UInt32", "UInt64":
            edges = "0, 1"
            uniform = "Gen<\(typeText)>.boundedForArithmetic()"

        default:
            return fallback
        }
        return "Gen.frequency("
            + "(3.0, \(uniform)), "
            + "(2.0, Gen<\(typeText)?>.element(of: [\(edges)] as [\(typeText)]).map { $0! })"
            + ")"
    }

    /// Reconstruct a Swift parameter clause from its label / name / type.
    /// `_ quantity: Double`, `name value: T`, or `value: T` when label == name.
    private static func parameterClause(
        label: String?,
        name: String,
        typeText: String
    ) -> String {
        guard let label else {
            return "_ \(name): \(typeText)"
        }
        return label == name ? "\(name): \(typeText)" : "\(label) \(name): \(typeText)"
    }
}
