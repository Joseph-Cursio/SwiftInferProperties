import PropertyLawCore
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

    /// V1.31.B — equality-form for emitted property assertions.
    /// `.strict` (default; current behavior) emits `lhs == rhs`. `.approximate`
    /// emits `lhs.isApproximatelyEqual(to: rhs)` — required for FP types
    /// (`Double`, `Float`, `Complex<Real>`, etc.) where strict `==` fails
    /// under IEEE 754 rounding even on canonical inverse pairs. Detected
    /// via `SwiftInferCore.FloatingPointEquatableTypes.isFloatingPointEquatable(typeText:)`
    /// at dispatch time (V1.31.C wiring in `InteractiveTriage+Accept`).
    ///
    /// First emit-side mechanism (class 16) in the loop's mechanism-class
    /// taxonomy.
    public enum EqualityKind: Sendable {
        case strict
        case approximate
    }

    /// Emit an idempotence test stub for `f: T -> T`. The body asserts
    /// `f(f(x)) == f(x)` over the supplied generator, surfacing
    /// counterexamples via Swift Testing's `Issue.record`. V1.31.B —
    /// when `equalityKind == .approximate`, the assertion becomes
    /// `f(f(value)).isApproximatelyEqual(to: f(value))`.
    public static func idempotent(
        funcName: String,
        typeName _: String,
        seed: SamplingSeed.Value,
        generator: String,
        equalityKind: EqualityKind = .strict
    ) -> String {
        let testFunctionName = "\(funcName)_isIdempotent"
        let property = equalityExpression(
            lhs: "\(funcName)(\(funcName)(value))",
            rhs: "\(funcName)(value)",
            kind: equalityKind
        )
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
    /// `inverseName` is the unwrapper applied to its output. V1.31.B —
    /// when `equalityKind == .approximate`, the assertion becomes
    /// `inverse(forward(value)).isApproximatelyEqual(to: value)` to
    /// support FP type round-trips (`exp/log`, `cos/acos`, etc.).
    public static func roundTrip(
        forwardName: String,
        inverseName: String,
        seed: SamplingSeed.Value,
        generator: String,
        equalityKind: EqualityKind = .strict
    ) -> String {
        let testFunctionName = "\(forwardName)_\(inverseName)_roundTrip"
        let property = equalityExpression(
            lhs: "\(inverseName)(\(forwardName)(value))",
            rhs: "value",
            kind: equalityKind
        )
        let failureLabel = "\(forwardName)/\(inverseName) round-trip failed"
        return makeTestStub(
            testFunctionName: testFunctionName,
            seed: seed,
            generator: generator,
            propertyExpression: property,
            failureLabel: failureLabel
        )
    }

    /// Emit a monotonicity test stub for `f: T -> U` (U: Comparable):
    /// draws a `(T, T)` pair, sorts via `<`, asserts `f(small) <= f(large)`.
    /// `returnType` is reserved for future failure-message hints — Swift's
    /// `<=` already infers from the function's declared return type.
    public static func monotonic(
        funcName: String,
        typeName: String,
        returnType: String,
        seed: SamplingSeed.Value,
        generator: String
    ) -> String {
        _ = (typeName, returnType)
        let testFunctionName = "\(funcName)_isMonotonic"
        // T must conform to Comparable for this sample to typecheck.
        let sample = [
            "{ rng in",
            "                    let lhs = (\(generator)).run(using: &rng)",
            "                    let rhs = (\(generator)).run(using: &rng)",
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
            "                    let lhs = (\(generator)).run(using: &rng)",
            "                    let rhs = (\(generator)).run(using: &rng)",
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
            "                    let one = (\(generator)).run(using: &rng)",
            "                    let two = (\(generator)).run(using: &rng)",
            "                    let three = (\(generator)).run(using: &rng)",
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
        // canonical `{ rng in (generator).run(using: &rng) }` shape applies.
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

    /// Emit an inverse-pair test stub. Body shape matches `roundTrip`
    /// (`inverse(forward(value)) == value`); distinct test-function
    /// name + failure label keep the two arms disambiguable in test
    /// runner output. The non-Equatable caveat lives in the §4.5
    /// explainability block surfaced before accept.
    public static func inversePair(
        forwardName: String,
        inverseName: String,
        typeName: String,
        seed: SamplingSeed.Value,
        generator: String,
        equalityKind: EqualityKind = .strict
    ) -> String {
        _ = typeName
        let testFunctionName = "\(forwardName)_\(inverseName)_inversePair"
        let property = equalityExpression(
            lhs: "\(inverseName)(\(forwardName)(value))",
            rhs: "value",
            kind: equalityKind
        )
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
        let sample = "{ rng in (\(generator)).run(using: &rng) }"
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
}

// V1.43 cleanup — private builders live here so the primary
// enum body stays under SwiftLint's type_body_length cap.
extension LiftedTestEmitter {

    // MARK: - Shared stub shape

    /// Convenience overload for unary-property arms — wraps the canonical
    /// `{ rng in (generator).run(using: &rng) }` sample and a single-value
    /// property closure, then forwards to `makeTestStubExpression`.
    private static func makeTestStub(
        testFunctionName: String,
        seed: SamplingSeed.Value,
        generator: String,
        propertyExpression: String,
        failureLabel: String
    ) -> String {
        let sample = "{ rng in (\(generator)).run(using: &rng) }"
        let property = "{ value in \(propertyExpression) }"
        return makeTestStubExpression(
            testFunctionName: testFunctionName,
            seed: seed,
            sampleExpression: sample,
            propertyExpression: property,
            failureLabel: failureLabel
        )
    }

    /// Shared scaffold for every arm — they differ only in the sample /
    /// property closure shape and failure-label string. Module-private
    /// (not file-private) so the M5.5 lifted-only arms in
    /// `LiftedTestEmitter+M5.swift` can reuse it.
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
                    "\(failureLabel) at input \\(input). \\(error?.message ?? "")"
                )
            }
        }
        """
    }

    /// `\.isValid` → `isValid`; `\.account.balance` → `account_balance`.
    /// Used only for test-function-name suffixes; the keypath itself is
    /// emitted verbatim into the property closure.
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

    /// V1.31.B equality assertion. `.strict` → `lhs == rhs`;
    /// `.approximate` → `lhs.isApproximatelyEqual(to: rhs)` for FP types
    /// where IEEE 754 rounding makes strict `==` impractical. Emitted
    /// test files need `import Numerics` for the approximate form.
    static func equalityExpression(
        lhs: String,
        rhs: String,
        kind: EqualityKind
    ) -> String {
        switch kind {
        case .strict:
            return "\(lhs) == \(rhs)"

        case .approximate:
            return "\(lhs).isApproximatelyEqual(to: \(rhs))"
        }
    }
}
