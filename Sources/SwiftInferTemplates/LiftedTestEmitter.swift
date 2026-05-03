import ProtoLawCore
import SwiftInferCore

/// Pure-function emit of a Swift Testing `@Test func` source string
/// for a SwiftInfer-discovered property. Consumed by
/// `SwiftInferMacroImpl.CheckPropertyMacro` (M5.2 + M5.3) and
/// `SwiftInferCLI.InteractiveTriage` (M6.4) — see the M5/M6 plan rows.
///
/// The emitter is agnostic about seed derivation: callers supply a
/// `SamplingSeed.Value` from whichever identity path is appropriate
/// (macro-time canonical string vs. accept-flow `Suggestion.identity`).
/// Both paths are deterministic per PRD §16 #6.
///
/// Output is column-0 (no leading indent) and includes one leading
/// newline so the emitted decl reads as a standalone block when
/// concatenated with file-level imports.
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

    /// Emit a commutativity test stub for `f: (T, T) -> T` where
    /// `T: Equatable`. The body draws a pair `(T, T)` from `generator`,
    /// then asserts `f(lhs, rhs) == f(rhs, lhs)`. Counter-examples
    /// surface via Swift Testing's `Issue.record`. M8.2 — retires the
    /// "no stub writeout available for template 'commutativity' in v1"
    /// diagnostic from M6.4's `liftedTestStub(for:)` default branch.
    public static func commutative(
        funcName: String,
        typeName: String,
        seed: SamplingSeed.Value,
        generator: String
    ) -> String {
        _ = typeName
        let testFunctionName = "\(funcName)_isCommutative"
        // Same multi-line sample shape as `monotonic`'s pair draw —
        // mirrors the column convention so the existing tests/goldens
        // share the same indentation envelope. Two values, no sort.
        let sample = [
            "{ rng in",
            "                    let lhs = (\(generator)).run(&rng)",
            "                    let rhs = (\(generator)).run(&rng)",
            "                    return (lhs, rhs)",
            "                }"
        ].joined(separator: "\n")
        let property = "{ pair in \(funcName)(pair.0, pair.1) == \(funcName)(pair.1, pair.0) }"
        let failureLabel = "\(funcName)(_:_:) failed commutativity"
        return makeTestStubExpression(
            testFunctionName: testFunctionName,
            seed: seed,
            sampleExpression: sample,
            propertyExpression: property,
            failureLabel: failureLabel
        )
    }

    /// Emit an associativity test stub for `f: (T, T) -> T` where
    /// `T: Equatable`. The body draws a triple `(T, T, T)` from
    /// `generator`, then asserts
    /// `f(f(one, two), three) == f(one, f(two, three))`. M8.2 —
    /// retires the "no stub writeout available for template
    /// 'associativity' in v1" diagnostic.
    public static func associative(
        funcName: String,
        typeName: String,
        seed: SamplingSeed.Value,
        generator: String
    ) -> String {
        _ = typeName
        let testFunctionName = "\(funcName)_isAssociative"
        // Three-value tuple sample — same multi-line style as monotonic /
        // commutative for visual consistency across the binary-op arms.
        let sample = [
            "{ rng in",
            "                    let one = (\(generator)).run(&rng)",
            "                    let two = (\(generator)).run(&rng)",
            "                    let three = (\(generator)).run(&rng)",
            "                    return (one, two, three)",
            "                }"
        ].joined(separator: "\n")
        // Multi-line property — the nested call shape would push a
        // one-liner past 120 chars. Indents match the test-stub
        // template's 8-space strip.
        let property = [
            "{ triple in",
            "            \(funcName)(\(funcName)(triple.0, triple.1), triple.2)",
            "                == \(funcName)(triple.0, \(funcName)(triple.1, triple.2))",
            "        }"
        ].joined(separator: "\n")
        let failureLabel = "\(funcName)(_:_:) failed associativity"
        return makeTestStubExpression(
            testFunctionName: testFunctionName,
            seed: seed,
            sampleExpression: sample,
            propertyExpression: property,
            failureLabel: failureLabel
        )
    }

    /// Emit an identity-element test stub for `f: (T, T) -> T` paired
    /// with a static identity element `T.\(identityName)`. The body
    /// draws a single `T` value and asserts both
    /// `f(value, T.identity) == value` and `f(T.identity, value) == value`.
    /// `identityName` is the bare member name on `typeName` (e.g.
    /// `"empty"`, `"zero"`, `"identity"`), extracted from the
    /// suggestion's evidence[1] displayName (`"\(typeName).\(identityName)"`)
    /// at dispatch time. M8.2 — retires the "no stub writeout available
    /// for template 'identity-element' in v1" diagnostic.
    public static func identityElement(
        funcName: String,
        typeName: String,
        identityName: String,
        seed: SamplingSeed.Value,
        generator: String
    ) -> String {
        let testFunctionName = "\(funcName)_hasIdentity_\(identityName)"
        // Single-value sample — the identity is constant in the body
        // (referenced via `\(typeName).\(identityName)`), so the
        // canonical `{ rng in (generator).run(&rng) }` shape applies.
        let property = "\(funcName)(value, \(typeName).\(identityName)) == value"
            + " && \(funcName)(\(typeName).\(identityName), value) == value"
        let failureLabel = "\(funcName)(_:_:) failed identity-element \(typeName).\(identityName)"
        return makeTestStub(
            testFunctionName: testFunctionName,
            seed: seed,
            generator: generator,
            propertyExpression: property,
            failureLabel: failureLabel
        )
    }

    /// Emit an inverse-pair test stub for `forward: T -> U` paired
    /// with `inverse: U -> T`. Body shape matches `roundTrip` —
    /// `inverse(forward(value)) == value` over a `T` generator —
    /// because the structural assertion is identical. The non-Equatable
    /// caveat that distinguishes M8.1's inverse-pair from M1.4's
    /// round-trip lives in the §4.5 explainability block surfaced at
    /// CLI render time, *before* the user accepts: if `T` doesn't
    /// conform to `Equatable`, the user supplies a custom equality
    /// witness or the emitted test fails to compile (the explicit
    /// signal pointing them at the gap). Distinct test-function name
    /// + failure label so the two arms remain disambiguable in test
    /// runner output.
    public static func inversePair(
        forwardName: String,
        inverseName: String,
        typeName: String,
        seed: SamplingSeed.Value,
        generator: String
    ) -> String {
        _ = typeName
        let testFunctionName = "\(forwardName)_\(inverseName)_inversePair"
        let property = "\(inverseName)(\(forwardName)(value)) == value"
        let failureLabel = "\(forwardName)/\(inverseName) inverse-pair failed"
        return makeTestStub(
            testFunctionName: testFunctionName,
            seed: seed,
            generator: generator,
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

    // MARK: - Shared stub shape

    /// Convenience overload for the unary-property arms (idempotent,
    /// round-trip, invariant-preservation, identity-element, inverse-pair)
    /// where the sample expression is the canonical
    /// `{ rng in (generator).run(&rng) }` shape and the property closure
    /// binds a single `value` parameter. Forwards to
    /// `makeTestStubExpression` after composing the wrappers.
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
    /// monotonic, invariant-preserving, commutative, associative,
    /// identity-element, and inverse-pair share the backend-
    /// construction + check-call + failure-recording scaffold; they
    /// only differ in the sample/property closure shape and the
    /// failure-label string. Keeping a single template makes the
    /// "match the existing Swift Testing convention" requirement easy
    /// to enforce: any future change to the surrounding scaffold
    /// (e.g. switching to a different backend or a richer
    /// `Issue.record` shape) lands in one place.
    ///
    /// **Module-private (not file-private)** so the M5.5 lifted-only
    /// arms in `LiftedTestEmitter+M5.swift` can share the same scaffold
    /// without duplicating it.
    static func makeTestStubExpression(
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

    static func hex(_ word: UInt64) -> String {
        let raw = String(word, radix: 16, uppercase: true)
        return String(repeating: "0", count: 16 - raw.count) + raw
    }
}
