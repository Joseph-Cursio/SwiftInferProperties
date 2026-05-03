import Foundation
import SwiftInferCore

/// TestLifter M5.5 lifted-only LiftedTestEmitter arms — split out of
/// the main `LiftedTestEmitter.swift` to keep that file under
/// SwiftLint's 400-line file-length limit. The two arms here parallel
/// the M6.3 / M7.3 / M8.2 arms in shape (sample expression + property
/// closure + failure label fed through `makeTestStubExpression`) but
/// carry lifted-only semantics: the assertion is the property the
/// test body actually claimed, not a more general algebraic shape.
public extension LiftedTestEmitter {

    /// TestLifter M5.5 lifted-only arm — emit a count-invariance test
    /// stub for `f: [T] -> [U]` (or any signature whose result has a
    /// `.count` member). The body draws an `[T]` collection from the
    /// supplied element generator (via the kit's `Gen.array(of:)`
    /// combinator over the 0...20 range), then asserts
    /// `f(xs).count == xs.count`. Counter-examples surface via
    /// Swift Testing's `Issue.record`.
    ///
    /// Distinct from `invariantPreserving` because the assertion is
    /// direct equality on `.count` (an `Int`-typed projection), not
    /// the implication-shaped `Bool`-keypath property the
    /// `InvariantPreservationTemplate`-side arm emits. PRD §3.5
    /// posture: emit the property the test body claimed, not a more
    /// general algebraic shape.
    static func liftedCountInvariance(
        funcName: String,
        typeName: String,
        seed: SamplingSeed.Value,
        generator: String
    ) -> String {
        _ = typeName
        let testFunctionName = "\(funcName)_preservesCount"
        let sample = "{ rng in ((\(generator)).array(of: 0...20)).run(&rng) }"
        let property = "{ xs in \(funcName)(xs).count == xs.count }"
        let failureLabel = "\(funcName)(_:) failed count-invariance"
        return makeTestStubExpression(
            testFunctionName: testFunctionName,
            seed: seed,
            sampleExpression: sample,
            propertyExpression: property,
            failureLabel: failureLabel
        )
    }

    /// TestLifter M5.5 lifted-only arm — emit a reduce-equivalence
    /// test stub for `op: (T, T) -> T` paired with the seed expression
    /// `seedSource` (textual; e.g. `"0"`, `".zero"`). The body draws an
    /// `[T]` collection from the supplied element generator (via the
    /// kit's `Gen.array(of:)` combinator over the 0...20 range), then
    /// asserts `xs.reduce(seed, op) == xs.reversed().reduce(seed, op)`.
    /// Counter-examples surface via Swift Testing's `Issue.record`.
    ///
    /// Distinct from `associative` because the assertion is the
    /// reduce-fold-under-reversal equivalence the test body actually
    /// claimed, not the stronger `op(op(a, b), c) == op(a, op(b, c))`
    /// algebraic associativity. The two are related (associativity +
    /// commutativity + identity together imply reduce-equivalence),
    /// but the lifted side surfaces what the body asserted.
    static func liftedReduceEquivalence(
        opName: String,
        elementTypeName: String,
        seedSource: String,
        seed: SamplingSeed.Value,
        generator: String
    ) -> String {
        _ = elementTypeName
        let testFunctionName = "\(sanitizeOperatorForIdentifier(opName))_reduceIsReversalInvariant"
        let sample = "{ rng in ((\(generator)).array(of: 0...20)).run(&rng) }"
        let property = "{ xs in xs.reduce(\(seedSource), \(opName))"
            + " == xs.reversed().reduce(\(seedSource), \(opName)) }"
        let failureLabel = "\(opName) reduce/.reversed().reduce equivalence failed"
        return makeTestStubExpression(
            testFunctionName: testFunctionName,
            seed: seed,
            sampleExpression: sample,
            propertyExpression: property,
            failureLabel: failureLabel
        )
    }

    /// Produce a Swift-identifier-safe fragment for an op callee name
    /// that may be an operator (`+`, `*`, `-`) rather than a bare
    /// identifier (`combine`). Bare identifiers pass through; operators
    /// map to their English-prefixed form (`+` → `op_plus`, `*` →
    /// `op_times`, etc.) so the lifted reduce-equivalence
    /// test-function name remains a valid Swift identifier.
    /// Anything outside the curated operator set + identifier
    /// characters falls back to `op` to keep the resulting test
    /// function name compilable.
    private static func sanitizeOperatorForIdentifier(_ opName: String) -> String {
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
