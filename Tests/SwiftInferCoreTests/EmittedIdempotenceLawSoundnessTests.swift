import PropertyLawKit
import Testing

/// Soundness of the executable idempotence law that SwiftInferProperties emits.
///
/// `LiftedTestEmitter.idempotent` (and the `@CheckProperty(.idempotent)` macro
/// that wraps it) expand to a runtime check of `f(f(x)) == f(x)` over generated
/// inputs, executed by PropertyLawKit's `SwiftPropertyBasedBackend`. The
/// existing macro tests only confirm the *generated source is syntactically
/// correct* — `CheckPropertyMacroExpansionTests` golden-matches the emitted
/// text, and the template tests assert *scores*. Nothing verifies that the
/// emitted law actually **discriminates** idempotent from non-idempotent
/// functions when it runs.
///
/// This suite closes that loop the way property-based testing should validate a
/// property-emitting tool: feed the exact law the emitter produces a corpus of
/// functions with KNOWN idempotence ground truth, and assert the backend agrees
/// — passing the idempotent ones, failing the non-idempotent ones. A regression
/// that emitted, say, `f(x) == f(x)` (trivially true) or `f(f(x)) != f(x)`
/// would sail through the syntactic golden tests yet be caught here.
///
/// The property expression mirrors `LiftedTestEmitter`'s equality form exactly
/// (`transform(transform(value)) == transform(value)`); the backend, seed, and
/// `sample`/`property` call shape mirror the macro expansion. Inputs use
/// overflow-safe arithmetic (`&*`, `&-`) so the law itself — never an
/// arithmetic trap — decides each trial.
@Suite
struct EmittedIdempotenceLawSoundnessTests {

    /// Fixed seed for reproducibility, matching the deterministic per-function
    /// seed derivation the macro uses.
    private static let seed = Seed(
        stateA: 0x0123_4567_89AB_CDEF,
        stateB: 0xFEDC_BA98_7654_3210,
        stateC: 0x1111_1111_1111_1111,
        stateD: 0x2222_2222_2222_2222
    )

    /// Runs the emitted idempotence law `f(f(x)) == f(x)` over generated Ints,
    /// exactly as the macro expansion does. The `rng` parameter type is inferred
    /// as `Xoshiro` from the backend's `sample` signature.
    private static func checkIdempotence(
        of transform: @escaping @Sendable (Int) -> Int
    ) async -> BackendCheckResult<Int> {
        await SwiftPropertyBasedBackend().check(
            trials: 200,
            seed: seed,
            sample: { rng in Int.random(in: -10_000 ... 10_000, using: &rng) },
            property: { value in transform(transform(value)) == transform(value) }
        )
    }

    @Test
    func law_passes_genuinelyIdempotentFunctions() async {
        let corpus: [(name: String, transform: @Sendable (Int) -> Int)] = [
            ("snapToMultipleOfTen", { value in value / 10 * 10 }),
            ("absoluteValue", { value in abs(value) }),
            ("clampToNonNegative", { value in max(0, value) }),
            ("constantZero", { _ in 0 }),
            ("signum", { value in value == 0 ? 0 : (value > 0 ? 1 : -1) })
        ]
        for entry in corpus {
            let result = await Self.checkIdempotence(of: entry.transform)
            let passed: Bool = if case .passed = result { true } else { false }
            #expect(passed, "Idempotent '\(entry.name)' should pass the emitted law; got \(result)")
        }
    }

    @Test
    func law_fails_genuinelyNonIdempotentFunctions() async {
        let corpus: [(name: String, transform: @Sendable (Int) -> Int)] = [
            ("increment", { value in value &+ 1 }),
            ("double", { value in value &* 2 }),
            ("negate", { value in 0 &- value })
        ]
        for entry in corpus {
            let result = await Self.checkIdempotence(of: entry.transform)
            let failed: Bool = if case .failed = result { true } else { false }
            #expect(failed, "Non-idempotent '\(entry.name)' should fail the emitted law; got \(result)")
        }
    }
}
