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

    /// One template covers both arms — idempotent and round-trip
    /// share the backend-construction + check-call + failure-recording
    /// scaffold; they only differ in the property closure body and
    /// the failure-label string. Keeping a single template makes the
    /// "match the existing Swift Testing convention" requirement easy
    /// to enforce: any future change to the surrounding scaffold
    /// (e.g. switching to a different backend or a richer
    /// `Issue.record` shape) lands in one place.
    private static func makeTestStub(
        testFunctionName: String,
        seed: SamplingSeed.Value,
        generator: String,
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
                sample: { rng in (\(generator)).run(&rng) },
                property: { value in \(propertyExpression) }
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

    private static func hex(_ word: UInt64) -> String {
        let raw = String(word, radix: 16, uppercase: true)
        return String(repeating: "0", count: 16 - raw.count) + raw
    }
}
