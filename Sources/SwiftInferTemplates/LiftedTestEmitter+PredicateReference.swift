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
///
/// This file keeps the free-function entry point and the pieces the scaffold shares: the
/// result note, the numeric edge bias and the parameter clause. The scaffold itself —
/// a member's reference declared in `extension <Owner>`, and the comparison written through the
/// determinism law's own `agreementProperty` — is `LiftedTestEmitter+ReferenceOracle.swift`.
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

    /// Emit the reference-oracle stub + property for a documented FREE function
    /// `funcName: (T...) -> R` of any arity whose return `R` is `Equatable` — or, for a tuple
    /// `R`, has `==` through its elements: a tuple never conforms to `Equatable`, and Swift
    /// defines `==` on tuples of two to six `Equatable` elements instead (`TupleResultShape`).
    ///
    /// The free-function form of `referenceOracle(subject:draws:equalityKind:docComment:seed:)`,
    /// kept for callers that hold only a name and its parameters. It spells the call bare, which
    /// is right only for a function at file scope; `discover` builds the subject from the
    /// function's own evidence row instead, so a member is qualified or drawn a receiver.
    ///
    /// - Parameters:
    ///   - funcName: the function's base name (e.g. `isValidQuantity`).
    ///   - arguments: its parameters + per-parameter generators, in order (non-empty).
    ///   - returnTypeText: the return type `R` (`"Bool"` for predicate/comparator).
    ///   - docComment: the reflowed docstring — shown verbatim as the definition.
    ///   - seed: sampling seed (derive from the suggestion identity for stability).
    ///   - equalityKind: how two results compare; strict unless the caller asks otherwise.
    public static func referenceOracle(
        funcName: String,
        arguments: [ReferenceOracleArgument],
        returnTypeText: String,
        docComment: String,
        seed: SamplingSeed.Value,
        equalityKind: EqualityKind = .strict
    ) -> String {
        guard !arguments.isEmpty else { return "" }
        let parameters = arguments.map(\.parameter)
        let subject = ReferenceOracleSubject(
            callee: CalleeReference(bareName: funcName, argumentLabels: parameters.map(\.label)),
            owner: nil,
            parameters: parameters,
            returnTypeText: returnTypeText,
            isAsync: false,
            isThrows: false
        )
        let draws = ReferenceOracleDraws(
            generators: arguments.map(\.generator),
            argumentTypes: parameters.map(\.typeText)
        )
        return referenceOracle(
            subject: subject, draws: draws, equalityKind: equalityKind, docComment: docComment, seed: seed
        )
    }

    /// What `R` needs for `f(x) == f_reference(x)` to compile, as a comment above the stub.
    ///
    /// "The return type must be Equatable" is right for every nominal `R` and wrong for a tuple,
    /// which never is — so a tuple gets the element-wise sentence, and a tuple shape with no `==`
    /// at all says that instead. Every non-tuple `R` keeps its note byte for byte.
    static func equatableNote(forReturnType returnTypeText: String) -> String {
        let shape = TupleResultShape(typeText: returnTypeText)
        if let obstacle = shape.equalityObstacle {
            return "// (this cannot compile as written: the function returns \(obstacle))\n"
        }
        guard shape.involvesTuple else {
            return "// (the return type \(returnTypeText) must be Equatable for this to compile)\n"
        }
        return "// (every element of the returned tuple must be Equatable for this to compile — "
            + "\(TupleResultShape.elementwiseEqualityClause))\n"
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
    static func edgeBiasedGenerator(forTypeText typeText: String, fallback: String) -> String {
        let edges: String
        let uniform: String
        switch typeText {
        case "Double", "Float", "CGFloat", "Float16", "Float32", "Float64", "Float80":
            edges = "0.0, -1.0, 1.0"
            uniform = fallback

        // Signed and unsigned stay separate arms: the edge values differ (`-1` is
        // only representable on the signed half), which is exactly why
        // `FixedWidthIntegerNames` exposes the two halves rather than only the union.
        case let name where FixedWidthIntegerNames.signed.contains(name):
            edges = "0, -1, 1"
            uniform = "Gen<\(typeText)>.boundedForArithmetic()"

        case let name where FixedWidthIntegerNames.unsigned.contains(name):
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
    static func parameterClause(
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
