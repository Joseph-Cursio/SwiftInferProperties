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

    /// Emit the reference-oracle stub + property for a documented predicate
    /// `funcName: (T...) -> Bool` of any arity.
    ///
    /// A single parameter draws one `value`; two or more draw a `tuple` and the
    /// property indexes it (`tuple.0`, `tuple.1`, …) — the same shape the
    /// commutativity arm uses for its pair. Argument labels are preserved in both
    /// calls, so a `canReach(from:to:)` predicate compares against a
    /// `canReach_reference(from:to:)` the reader writes with the same signature.
    ///
    /// - Parameters:
    ///   - funcName: the predicate's base name (e.g. `isValidQuantity`).
    ///   - parameters: the predicate's parameters, in order (non-empty).
    ///   - docComment: the predicate's reflowed docstring — shown verbatim as the
    ///     reference definition the reader is encoding.
    ///   - seed: sampling seed (derive from the suggestion identity for stability).
    ///   - generators: the fallback `Gen<T>` expression per parameter, in order —
    ///     parallel to `parameters`. Each is edge-biased internally.
    public static func predicateReferenceOracle(
        funcName: String,
        parameters: [Parameter],
        docComment: String,
        seed: SamplingSeed.Value,
        generators: [String]
    ) -> String {
        guard !parameters.isEmpty, parameters.count == generators.count else {
            return ""
        }
        let referenceName = "\(funcName)_reference"
        let paramClause = parameters
            .map { parameterClause(label: $0.label, name: $0.internalName, typeText: $0.typeText) }
            .joined(separator: ", ")

        let stub = """
        // Fill in the reference definition below — your docstring already states it:
        //   "\(docComment)"
        // Then run the test: the generator finds the input where the code disagrees
        // with its own documentation.
        func \(referenceName)(\(paramClause)) -> Bool {
            fatalError("state the reference definition from the docstring, then replace this line")
        }
        """

        let biased = zip(parameters, generators).map { parameter, generator in
            edgeBiasedGenerator(forTypeText: parameter.typeText, fallback: generator)
        }
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

    /// Wrap a numeric generator to mix its uniform baseline (weight 3) with the
    /// curated boundary values (weight 2) where predicate contract bugs live —
    /// above all **zero**, the point a `> 0` / `>= 0` slip hides at. A uniform
    /// range generator samples the boundary with measure zero and false-passes;
    /// this is the numeric analog of the kit's String edge-biasing. Non-numeric
    /// types return the fallback unchanged (their own generator handles edges).
    private static func edgeBiasedGenerator(forTypeText typeText: String, fallback: String) -> String {
        let edges: String
        switch typeText {
        case "Double", "Float", "CGFloat", "Float16", "Float32", "Float64", "Float80":
            edges = "0.0, -1.0, 1.0"

        case "Int", "Int8", "Int16", "Int32", "Int64":
            edges = "0, -1, 1"

        case "UInt", "UInt8", "UInt16", "UInt32", "UInt64":
            edges = "0, 1"

        default:
            return fallback
        }
        return "Gen.frequency("
            + "(3.0, \(fallback)), "
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
