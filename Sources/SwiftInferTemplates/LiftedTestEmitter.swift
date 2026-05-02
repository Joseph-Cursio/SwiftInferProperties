import ProtoLawCore
import SwiftInferCore

/// Pure-function emit of a Swift Testing `@Test func` source string
/// for a SwiftInfer-discovered property. Single source of truth for
/// the lifted-test text shape consumed by:
///
/// - `SwiftInferMacroImpl.CheckPropertyMacro` (M5.2 + M5.3) — wraps
///   the returned string as a `DeclSyntax` peer at user compile time.
/// - `SwiftInferCLI.InteractiveTriage` (M6.4) — wraps with file
///   imports + provenance header and writes to
///   `Tests/Generated/SwiftInfer/<TemplateName>/<FunctionName>.swift`.
///
/// The emitter is *agnostic* about how the seed is derived. Callers
/// supply a `SamplingSeed.Value` from whichever identity path is
/// appropriate: the macro uses a `checkProperty.idempotent|…`-shaped
/// canonical string (no Suggestion in scope at macro-expansion time);
/// the M6.4 accept flow uses `SamplingSeed.derive(from: suggestion.identity)`
/// directly (the suggestion identity is already the M1.5 canonical
/// hash). Both paths are deterministic; the seeds intentionally
/// differ because the identity-formation paths differ — re-running
/// either path on unchanged source produces an identical seed and
/// therefore an identical trial sequence per PRD §16 #6.
///
/// Output is column-0 (no leading indent) and includes one leading
/// newline so the emitted decl reads as a standalone block when
/// concatenated with file-level imports. Callers needing a different
/// indentation tier (e.g. nested inside a type body for the macro's
/// peer-decl context) can re-indent with their preferred whitespace
/// strategy.
public enum LiftedTestEmitter {

    /// Emit an idempotence test stub for `f: T -> T`. The body asserts
    /// `f(f(x)) == f(x)` over the supplied generator, surfacing
    /// counterexamples via Swift Testing's `Issue.record`.
    public static func idempotent(
        funcName: String,
        typeName: String,
        seed: SamplingSeed.Value,
        generator: String
    ) -> String {
        let testFunctionName = "\(funcName)_isIdempotent"
        let property = "\(funcName)(\(funcName)(value)) == \(funcName)(value)"
        let failureLabel = "\(funcName)(_:) failed idempotence"
        return makeTestStub(
            testFunctionName: testFunctionName,
            seed: seed,
            generator: generator,
            propertyExpression: property,
            failureLabel: failureLabel
        )
    }

    /// Emit a round-trip test stub for the pair (`forward: T -> U`,
    /// `inverse: U -> T`). The body asserts
    /// `inverse(forward(value)) == value` over the supplied generator
    /// (which produces values of the *forward* parameter type).
    /// `forwardName` is the wrapper-then-unwrapper applied first;
    /// `inverseName` is the unwrapper applied to its output.
    public static func roundTrip(
        forwardName: String,
        inverseName: String,
        seed: SamplingSeed.Value,
        generator: String
    ) -> String {
        let testFunctionName = "\(forwardName)_\(inverseName)_roundTrip"
        let property = "\(inverseName)(\(forwardName)(value)) == value"
        let failureLabel = "\(forwardName)/\(inverseName) round-trip failed"
        return makeTestStub(
            testFunctionName: testFunctionName,
            seed: seed,
            generator: generator,
            propertyExpression: property,
            failureLabel: failureLabel
        )
    }

    /// Emit a monotonicity test stub for `f: T -> U` where `U: Comparable`.
    /// The body draws a pair `(T, T)` from `generator`, sorts the pair
    /// via Swift's `<` (T must conform to Comparable for the test to
    /// compile), then asserts `f(small) <= f(large)`. Counter-examples
    /// surface via Swift Testing's `Issue.record`.
    ///
    /// `returnType` is part of the M7.3 plan-row signature; it is
    /// reserved for future surface (e.g. emitting a `Comparable` hint in
    /// the failure message). The current body doesn't reference it
    /// because Swift's `<=` infers the operand type from the function's
    /// declared return type at the call site.
    public static func monotonic(
        funcName: String,
        typeName: String,
        returnType: String,
        seed: SamplingSeed.Value,
        generator: String
    ) -> String {
        _ = (typeName, returnType)
        let testFunctionName = "\(funcName)_isMonotonic"
        // T must conform to Comparable for this sample to typecheck —
        // mirrors the per-template caveat surfaced by the explainability
        // block. Sample emitted as a multi-line block so the generated
        // test file reads naturally; indent levels match the surrounding
        // backend.check(...) body (line continuations at column 20 in
        // the output, closing brace at column 16, matching the
        // `property:` line above).
        let sample = [
            "{ rng in",
            "                    let lhs = (\(generator)).run(&rng)",
            "                    let rhs = (\(generator)).run(&rng)",
            "                    return lhs < rhs ? (lhs, rhs) : (rhs, lhs)",
            "                }"
        ].joined(separator: "\n")
        let property = "{ pair in \(funcName)(pair.0) <= \(funcName)(pair.1) }"
        let failureLabel = "\(funcName)(_:) failed monotonicity"
        return makeTestStubExpression(
            testFunctionName: testFunctionName,
            seed: seed,
            sampleExpression: sample,
            propertyExpression: property,
            failureLabel: failureLabel
        )
    }

    /// Emit an invariant-preservation test stub for `f: T -> U` where
    /// the user-supplied keypath `invariantName` (e.g. `\.isValid`)
    /// resolves to a `Bool` member on both `T` and `U`. The body
    /// asserts the implication
    /// `value[keyPath: kp] -> f(value)[keyPath: kp]` — if the input
    /// satisfies the invariant, so must the output. Counterexamples
    /// surface via Swift Testing's `Issue.record`.
    ///
    /// Per M7 plan open decision #5(a) the keypath is opaque text — if
    /// it doesn't resolve against `T` (or returns a non-Bool member),
    /// the user's test target produces a compile error. SemanticIndex
    /// (PRD §20.1) lifts that check to scan time in v1.1+.
    public static func invariantPreserving(
        funcName: String,
        typeName: String,
        invariantName: String,
        seed: SamplingSeed.Value,
        generator: String
    ) -> String {
        _ = typeName
        let suffix = sanitizeKeyPathForIdentifier(invariantName)
        let testFunctionName = "\(funcName)_preservesInvariant_\(suffix)"
        let sample = "{ rng in (\(generator)).run(&rng) }"
        let property = "{ value in !value[keyPath: \(invariantName)] || "
            + "\(funcName)(value)[keyPath: \(invariantName)] }"
        let failureLabel = "\(funcName)(_:) failed invariant preservation \(invariantName)"
        return makeTestStubExpression(
            testFunctionName: testFunctionName,
            seed: seed,
            sampleExpression: sample,
            propertyExpression: property,
            failureLabel: failureLabel
        )
    }

    /// Pick the canonical generator expression for `typeName`. If it
    /// matches a `ProtoLawCore.RawType` (stdlib `Int`, `String`,
    /// `Bool`, etc.), emit the kit's `RawType.generatorExpression` so
    /// the M4.2 generator-selection convention holds. Otherwise emit
    /// `\(typeName).gen()` — same fallback the
    /// `DerivationStrategist` produces for non-derivable types,
    /// requiring the user to provide `static func gen() -> Gen<T>`
    /// or take the missing-symbol compile error.
    public static func defaultGenerator(for typeName: String) -> String {
        if let rawType = RawType(typeName: typeName) {
            return rawType.generatorExpression
        }
        return "\(typeName).gen()"
    }

    // MARK: - Shared stub shape

    /// Convenience overload for the unary-property arms (idempotent,
    /// round-trip, invariant-preservation) where the sample expression
    /// is the canonical `{ rng in (generator).run(&rng) }` shape and
    /// the property closure binds a single `value` parameter. Forwards
    /// to `makeTestStubExpression` after composing the wrappers.
    private static func makeTestStub(
        testFunctionName: String,
        seed: SamplingSeed.Value,
        generator: String,
        propertyExpression: String,
        failureLabel: String
    ) -> String {
        let sample = "{ rng in (\(generator)).run(&rng) }"
        let property = "{ value in \(propertyExpression) }"
        return makeTestStubExpression(
            testFunctionName: testFunctionName,
            seed: seed,
            sampleExpression: sample,
            propertyExpression: property,
            failureLabel: failureLabel
        )
    }

    /// One template covers every arm — idempotent, round-trip,
    /// monotonic, and invariant-preserving share the backend-
    /// construction + check-call + failure-recording scaffold; they
    /// only differ in the sample/property closure shape and the
    /// failure-label string. Keeping a single template makes the
    /// "match the existing Swift Testing convention" requirement easy
    /// to enforce: any future change to the surrounding scaffold
    /// (e.g. switching to a different backend or a richer
    /// `Issue.record` shape) lands in one place.
    private static func makeTestStubExpression(
        testFunctionName: String,
        seed: SamplingSeed.Value,
        sampleExpression: String,
        propertyExpression: String,
        failureLabel: String
    ) -> String {
        """

        @Test func \(testFunctionName)() async {
            let backend = SwiftPropertyBasedBackend()
            let seed = Seed(
                stateA: 0x\(hex(seed.stateA)),
                stateB: 0x\(hex(seed.stateB)),
                stateC: 0x\(hex(seed.stateC)),
                stateD: 0x\(hex(seed.stateD))
            )
            let result = await backend.check(
                trials: 100,
                seed: seed,
                sample: \(sampleExpression),
                property: \(propertyExpression)
            )
            if case let .failed(_, _, input, error) = result {
                Issue.record(
                    "\(failureLabel) at input \\(input)."
                        + " \\(error?.message ?? \\"\\")"
                )
            }
        }
        """
    }

    /// Strip the leading `\.` from a key-path source-text and rewrite
    /// `.` separators as `_` so the resulting fragment is a valid Swift
    /// identifier. `\.isValid` → `isValid`; `\.account.balance` →
    /// `account_balance`. Used for the monotonicity / invariant-
    /// preservation test-function names; never for the keypath itself
    /// (which is emitted verbatim into the property closure).
    private static func sanitizeKeyPathForIdentifier(_ keyPath: String) -> String {
        var sanitized = keyPath
        if sanitized.hasPrefix("\\.") {
            sanitized = String(sanitized.dropFirst(2))
        }
        return sanitized.replacingOccurrences(of: ".", with: "_")
    }

    private static func hex(_ word: UInt64) -> String {
        let raw = String(word, radix: 16, uppercase: true)
        return String(repeating: "0", count: 16 - raw.count) + raw
    }
}
