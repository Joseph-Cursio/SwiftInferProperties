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

    /// Emit the reference-oracle stub + property for a single-parameter
    /// documented predicate `funcName: (T) -> Bool`.
    ///
    /// - Parameters:
    ///   - funcName: the predicate's base name (e.g. `isValidQuantity`).
    ///   - parameter: the predicate's single parameter (label / name / type).
    ///   - docComment: the predicate's reflowed docstring — shown verbatim as the
    ///     reference definition the reader is encoding.
    ///   - seed: sampling seed (derive from the suggestion identity for stability).
    ///   - generator: the `Gen<T>` expression the sample draws from.
    public static func predicateReferenceOracle(
        funcName: String,
        parameter: Parameter,
        docComment: String,
        seed: SamplingSeed.Value,
        generator: String
    ) -> String {
        let referenceName = "\(funcName)_reference"
        let paramTypeText = parameter.typeText
        let paramClause = parameterClause(
            label: parameter.label,
            name: parameter.internalName,
            typeText: paramTypeText
        )

        let stub = """
        // Fill in the reference definition below — your docstring already states it:
        //   "\(docComment)"
        // Then run the test: the generator finds the input where the code disagrees
        // with its own documentation.
        func \(referenceName)(\(paramClause)) -> Bool {
            fatalError("state the reference definition from the docstring, then replace this line")
        }
        """

        let property = "{ value in \(funcName)(value) == \(referenceName)(value) }"
        let biased = edgeBiasedGenerator(forTypeText: paramTypeText, fallback: generator)
        let sample = "{ rng in (\(biased)).run(using: &rng) }"
        let test = makeTestStubExpression(
            testFunctionName: "\(funcName)_matchesReferenceDefinition",
            seed: seed,
            sampleExpression: sample,
            propertyExpression: property,
            failureLabel: "\(funcName)(_:) disagrees with its documented reference definition"
        )
        return stub + "\n" + test
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
