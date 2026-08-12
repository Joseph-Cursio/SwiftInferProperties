import CryptoKit
import Foundation
import SwiftInferCore

/// TestLifter M8.0 — regression-stub arms for `swift-infer
/// convert-counterexample`. Each arm parallels the corresponding
/// non-regression sibling on `LiftedTestEmitter` but emits a
/// **deterministic single-trial** test stub: no `forAll`, no
/// generator, no seed, no sample. The user supplies a counterexample
/// expression as `inputSource`; the regression test embeds it as a
/// `let` binding and asserts the property directly via `#expect(...)`.
///
/// **Why parallel arms instead of widening the existing arms.** The
/// existing M3.3 / M5.5 arms emit `forAll`-style tests that exercise
/// the generator over N trials. Regression tests are a different
/// shape — single trial, fixed input, no machinery. Trying to
/// parameterize the existing arms would either bifurcate every body
/// with `if regression` checks or accumulate dead seed/sample params
/// for the regression case. The parallel-arms split keeps each
/// shape minimal.
///
/// **Hash-based filename suffix.** `regressionFileHash(for:)` computes
/// the first 8 hex chars of `SHA256(inputSource.utf8)` so multiple
/// regressions on the same property don't collide. PRD §16 #6
/// reproducibility — same input → same hash → same file path on
/// every machine.
public extension LiftedTestEmitter {

    /// First 8 hex chars of `SHA256(inputSource.utf8)`. Used by the
    /// M8.1 CLI subcommand to build the regression filename
    /// `<callee>_regression_<hash>.swift`. Per OD #2 default — 8
    /// chars (32 bits) is well-collision-safe for per-(template,
    /// callee) regression sets, which rarely exceed 100 entries.
    static func regressionFileHash(for inputSource: String) -> String {
        let digest = SHA256.hash(data: Data(inputSource.utf8))
        let hex = digest.map { String(format: "%02X", $0) }.joined()
        return String(hex.prefix(8))
    }

    /// Regression-stub for idempotence. Body asserts
    /// `f(f(value)) == f(value)` for the user-supplied counterexample
    /// `inputSource` interpreted at type `typeName`.
    static func idempotentRegression(
        funcName: String,
        typeName: String,
        inputSource: String
    ) -> String {
        let testFunctionName = "\(funcName)_isIdempotent_regression_"
            + regressionFileHash(for: inputSource)
        return makeRegressionTestStub(
            testFunctionName: testFunctionName,
            inputBinding: "value",
            inputType: typeName,
            inputSource: inputSource,
            propertyExpression: "\(funcName)(\(funcName)(value)) == \(funcName)(value)"
        )
    }

    /// Regression-stub for round-trip. Body asserts
    /// `inverse(forward(value)) == value`.
    static func roundTripRegression(
        forwardName: String,
        inverseName: String,
        typeName: String,
        inputSource: String
    ) -> String {
        let testFunctionName = "\(forwardName)_\(inverseName)_roundTrip_regression_"
            + regressionFileHash(for: inputSource)
        return makeRegressionTestStub(
            testFunctionName: testFunctionName,
            inputBinding: "value",
            inputType: typeName,
            inputSource: inputSource,
            propertyExpression: "\(inverseName)(\(forwardName)(value)) == value"
        )
    }

    /// Regression-stub for monotonicity. The user supplies a sorted
    /// pair `(small, large)` as `inputSource`; body asserts
    /// `f(pair.0) <= f(pair.1)`. `inputType` is the tuple type the
    /// CLI builds from `--type` (e.g. `(Int, Int)`).
    static func monotonicRegression(
        funcName: String,
        tupleType: String,
        inputSource: String
    ) -> String {
        let testFunctionName = "\(funcName)_isMonotonic_regression_"
            + regressionFileHash(for: inputSource)
        return makeRegressionTestStub(
            testFunctionName: testFunctionName,
            inputBinding: "pair",
            inputType: tupleType,
            inputSource: inputSource,
            propertyExpression: "\(funcName)(pair.0) <= \(funcName)(pair.1)"
        )
    }

    /// Regression-stub for commutativity. The user supplies a pair
    /// `(a, b)`; body asserts `f(pair.0, pair.1) == f(pair.1, pair.0)`.
    static func commutativeRegression(
        funcName: String,
        tupleType: String,
        inputSource: String
    ) -> String {
        let testFunctionName = "\(funcName)_isCommutative_regression_"
            + regressionFileHash(for: inputSource)
        return makeRegressionTestStub(
            testFunctionName: testFunctionName,
            inputBinding: "pair",
            inputType: tupleType,
            inputSource: inputSource,
            propertyExpression:
                "\(funcName)(pair.0, pair.1) == \(funcName)(pair.1, pair.0)"
        )
    }

    /// Regression-stub for associativity. The user supplies a triple
    /// `(a, b, c)`; body asserts
    /// `f(f(triple.0, triple.1), triple.2) == f(triple.0, f(triple.1, triple.2))`.
    static func associativeRegression(
        funcName: String,
        tripleType: String,
        inputSource: String
    ) -> String {
        let testFunctionName = "\(funcName)_isAssociative_regression_"
            + regressionFileHash(for: inputSource)
        return makeRegressionTestStub(
            testFunctionName: testFunctionName,
            inputBinding: "triple",
            inputType: tripleType,
            inputSource: inputSource,
            propertyExpression:
                "\(funcName)(\(funcName)(triple.0, triple.1), triple.2) == "
                + "\(funcName)(triple.0, \(funcName)(triple.1, triple.2))"
        )
    }

    /// Regression-stub for identity-element. The user supplies a
    /// single value `T`; body asserts both
    /// `f(value, T.identity) == value` and `f(T.identity, value) == value`.
    static func identityElementRegression(
        funcName: String,
        typeName: String,
        identityName: String,
        inputSource: String
    ) -> String {
        let testFunctionName = "\(funcName)_hasIdentity_\(identityName)_regression_"
            + regressionFileHash(for: inputSource)
        return makeRegressionTestStub(
            testFunctionName: testFunctionName,
            inputBinding: "value",
            inputType: typeName,
            inputSource: inputSource,
            propertyExpression:
                "\(funcName)(value, \(typeName).\(identityName)) == value"
                + " && \(funcName)(\(typeName).\(identityName), value) == value"
        )
    }

    /// Regression-stub for inverse-pair. Same shape as round-trip.
    static func inversePairRegression(
        forwardName: String,
        inverseName: String,
        typeName: String,
        inputSource: String
    ) -> String {
        let testFunctionName = "\(forwardName)_\(inverseName)_inversePair_regression_"
            + regressionFileHash(for: inputSource)
        return makeRegressionTestStub(
            testFunctionName: testFunctionName,
            inputBinding: "value",
            inputType: typeName,
            inputSource: inputSource,
            propertyExpression: "\(inverseName)(\(forwardName)(value)) == value"
        )
    }

    /// Regression-stub for invariant-preservation. The user supplies
    /// a value `T`; body asserts the implication
    /// `value[\.kp] -> f(value)[\.kp]` (i.e.
    /// `!value[\.kp] || f(value)[\.kp]`).
    static func invariantPreservingRegression(
        funcName: String,
        typeName: String,
        invariantName: String,
        inputSource: String
    ) -> String {
        let suffix = sanitizeKeyPathForRegressionIdentifier(invariantName)
        let testFunctionName = "\(funcName)_preservesInvariant_\(suffix)_regression_"
            + regressionFileHash(for: inputSource)
        return makeRegressionTestStub(
            testFunctionName: testFunctionName,
            inputBinding: "value",
            inputType: typeName,
            inputSource: inputSource,
            propertyExpression:
                "!value[keyPath: \(invariantName)] || "
                + "\(funcName)(value)[keyPath: \(invariantName)]"
        )
    }

    /// Regression-stub for the M5.5 lifted count-invariance arm. The
    /// user supplies a `[T]` collection; body asserts
    /// `f(xs).count == xs.count`.
    static func liftedCountInvarianceRegression(
        funcName: String,
        elementTypeName: String,
        inputSource: String
    ) -> String {
        let testFunctionName = "\(funcName)_preservesCount_regression_"
            + regressionFileHash(for: inputSource)
        return makeRegressionTestStub(
            testFunctionName: testFunctionName,
            inputBinding: "xs",
            inputType: "[\(elementTypeName)]",
            inputSource: inputSource,
            propertyExpression: "\(funcName)(xs).count == xs.count"
        )
    }

    /// Regression-stub for the M5.5 lifted reduce-equivalence arm.
    /// The user supplies a `[T]` collection; body asserts
    /// `xs.reduce(seed, op) == xs.reversed().reduce(seed, op)`.
    static func liftedReduceEquivalenceRegression(
        opName: String,
        elementTypeName: String,
        seedSource: String,
        inputSource: String
    ) -> String {
        let testFunctionName = "\(sanitizeOperatorForRegressionIdentifier(opName))"
            + "_reduceIsReversalInvariant_regression_"
            + regressionFileHash(for: inputSource)
        return makeRegressionTestStub(
            testFunctionName: testFunctionName,
            inputBinding: "xs",
            inputType: "[\(elementTypeName)]",
            inputSource: inputSource,
            propertyExpression:
                "xs.reduce(\(seedSource), \(opName))"
                + " == xs.reversed().reduce(\(seedSource), \(opName))"
        )
    }

    // MARK: - Shared regression-stub shape

    /// One template covers every regression arm — they all share the
    /// same `let <binding>: <type> = <source>; #expect(<property>)`
    /// scaffold. Distinct from `makeTestStubExpression` (the M3.3
    /// `forAll`-style scaffold) because regression tests don't
    /// invoke a backend, sample a generator, or thread a seed.
    private static func makeRegressionTestStub(
        testFunctionName: String,
        inputBinding: String,
        inputType: String,
        inputSource: String,
        propertyExpression: String
    ) -> String {
        let typeAnnotation = inputType.isEmpty ? "" : ": \(inputType)"
        return """

        @Test func \(identifierSafe(testFunctionName))() {
            let \(inputBinding)\(typeAnnotation) = \(literal(inputSource, ofType: inputType))
            #expect(\(propertyExpression))
        }
        """
    }

    /// Reduce an arbitrary caller-supplied name to something that can follow `@Test func`.
    ///
    /// The arms above compose this from callee names, and a callee reaching them is a rendered
    /// CALL EXPRESSION rather than an identifier — `SwiftFormatConfig.parse`, or after #242 the
    /// receiver-closure form `{ $0.serialized() }`. Interpolated raw, that produced
    ///
    ///     @Test func SwiftFormatConfig.parse_{ $0.serialized() }_roundTrip_regression_6C179F21()
    ///
    /// which is not a Swift identifier — dots, braces, spaces and a `$` (issue #249).
    ///
    /// Each `_`-separated segment collapses to its LAST identifier run, which is the method name
    /// in every shape observed: `Type.method` → `method`, `{ $0.method() }` → `method`. Anything
    /// with no identifier run at all is dropped rather than mangled, and a name that reduces to
    /// nothing falls back to `regression` so the stub is still parseable and still obviously
    /// unfinished.
    ///
    /// Defensive rather than the whole fix: the callers should pass bare function names, which the
    /// index already carries. This is the floor, so a future caller passing an expression gets an
    /// ugly name instead of a syntax error.
    static func identifierSafe(_ name: String) -> String {
        let segments = name.split(separator: "_", omittingEmptySubsequences: true).map { segment -> String in
            var runs: [String] = []
            var current = ""
            for character in segment {
                if character.isLetter || character.isNumber || character == "_" {
                    current.append(character)
                } else if !current.isEmpty {
                    runs.append(current)
                    current = ""
                }
            }
            if !current.isEmpty { runs.append(current) }
            // Drop all-DIGIT runs only: `$0` reduces to `0`, which is a positional placeholder and
            // not a name. A run may otherwise begin with a digit — the trailing segment of every
            // arm's name is a hex hash, and `6C179F21` is as valid a segment as `AB12CD34`.
            //
            // Requiring a leading letter here silently deleted the hash from every name whose hash
            // began with a digit, which is 10 of the 16 possible first characters. The arm's
            // byte-stable tests caught it; the control in `RegressionStubWellFormednessTests` did
            // not, because it happened to use a hash starting with `A`.
            return runs.last { !$0.allSatisfy(\.isNumber) } ?? ""
        }
        let joined = segments.filter { !$0.isEmpty }.joined(separator: "_")
        guard let first = joined.first else { return "regression" }
        // Only the WHOLE identifier is forbidden from starting with a digit.
        return first.isNumber ? "regression_\(joined)" : joined
    }

    /// Render `source` as an expression of `type`, quoting when the type needs it.
    ///
    /// `inputSource` arrives as the RAW counterexample value — `verify` reports the value, not a
    /// Swift literal for it. Interpolated directly after `=`, a `String` counterexample is a syntax
    /// error, and a whitespace-only one leaves the binding with no right-hand side at all:
    ///
    ///     let value: SwiftFormatConfig =
    ///
    /// which is what issue #249 was filed on. Only `String` is quoted here, because that is the
    /// case observed and the one where a raw value is never valid; every other type's
    /// counterexample already arrives as an expression. A wider rule wants the type-aware
    /// rendering `verify` uses for replay, and should be measured rather than guessed.
    static func literal(_ source: String, ofType type: String) -> String {
        guard type == "String" || type == "String?" else { return source }
        if source.hasPrefix("\""), source.hasSuffix("\""), source.count >= 2 { return source }
        let escaped = source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    /// Strip the leading `\.` from a key-path source-text and rewrite
    /// `.` separators as `_` so the resulting fragment is a valid
    /// Swift identifier — same shape as the non-regression arm's
    /// `sanitizeKeyPathForIdentifier`.
    private static func sanitizeKeyPathForRegressionIdentifier(_ keyPath: String) -> String {
        var sanitized = keyPath
        if sanitized.hasPrefix("\\.") {
            sanitized = String(sanitized.dropFirst(2))
        }
        return sanitized.replacingOccurrences(of: ".", with: "_")
    }

    /// Operator-name → identifier-safe fragment, mirroring
    /// `LiftedTestEmitter+M5.swift`'s sanitizer for the same purpose.
    /// Curated set covers `+`, `-`, `*`, `/`, `%`, `&&`, `||`; bare
    /// identifiers pass through; anything else falls back to `op`.
    private static func sanitizeOperatorForRegressionIdentifier(
        _ opName: String
    ) -> String {
        if opName.unicodeScalars.allSatisfy({ scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }) {
            return opName.isEmpty ? "op" : opName
        }
        switch opName {
        case "+": return "op_plus"
        case "-": return "op_minus"
        case "*": return "op_times"
        case "/": return "op_divide"
        case "%": return "op_modulo"
        case "&&": return "op_and"
        case "||": return "op_or"
        default: return "op"
        }
    }
}
