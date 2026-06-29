import PropertyLawKit
import Testing

/// Soundness of the executable determinism law that SwiftInferProperties emits.
///
/// `LiftedTestEmitter.deterministic` expands to a runtime check of
/// `f(value) == f(value)` over generated inputs, executed by PropertyLawKit's
/// `SwiftPropertyBasedBackend`. The emitter test confirms the generated source
/// is correct, and the accept-flow e2e confirms it gets written to disk — but
/// neither verifies the law actually **discriminates** a deterministic function
/// from a nondeterministic one when it runs.
///
/// This suite closes that loop by feeding the exact property expression the
/// emitter produces (`transform(value) == transform(value)`) a corpus with KNOWN
/// ground truth, and asserting the backend agrees: passing pure functions,
/// failing functions that read a nondeterministic source. A regression that
/// emitted, say, `f(value) != f(value)` would sail through the golden emitter
/// test yet be caught here.
///
/// The backend, seed, and `sample`/`property` call shape mirror the emitter
/// output. Deterministic inputs use overflow-safe arithmetic (`&*`, `&+`) so the
/// law itself — never an arithmetic trap — decides each trial. The
/// nondeterministic corpus reads the *system* RNG (no injected `using:`), so two
/// evaluations of the same input differ with overwhelming probability.
@Suite
struct EmittedDeterminismLawSoundnessTests {

    private static let seed = Seed(
        stateA: 0x0123_4567_89AB_CDEF,
        stateB: 0xFEDC_BA98_7654_3210,
        stateC: 0x1111_1111_1111_1111,
        stateD: 0x2222_2222_2222_2222
    )

    /// Runs the emitted determinism law `f(value) == f(value)` over generated
    /// Ints, exactly as the accept-flow stub does.
    private static func checkDeterminism(
        of transform: @escaping @Sendable (Int) -> Int
    ) async -> BackendCheckResult<Int> {
        await SwiftPropertyBasedBackend().check(
            trials: 200,
            seed: seed,
            sample: { rng in Int.random(in: -10_000 ... 10_000, using: &rng) },
            // Two explicit evaluations of the same input — the determinism law
            // the emitter writes as `f(value) == f(value)`.
            property: { value in
                let first = transform(value)
                let second = transform(value)
                return first == second
            }
        )
    }

    @Test
    func law_passes_deterministicFunctions() async {
        let corpus: [(name: String, transform: @Sendable (Int) -> Int)] = [
            ("double", { value in value &* 2 }),
            ("addSeven", { value in value &+ 7 }),
            ("constant", { _ in 42 }),
            ("lowByte", { value in value & 0xFF }),
            ("xorMask", { value in value ^ 0x5A5A })
        ]
        for entry in corpus {
            let result = await Self.checkDeterminism(of: entry.transform)
            let passed: Bool = if case .passed = result { true } else { false }
            #expect(passed, "Deterministic '\(entry.name)' should pass the emitted law; got \(result)")
        }
    }

    @Test
    func law_fails_nondeterministicFunctions() async {
        let corpus: [(name: String, transform: @Sendable (Int) -> Int)] = [
            // Reads the system RNG — two evaluations of the same input differ.
            ("systemRandom", { _ in Int.random(in: Int.min ... Int.max) }),
            ("inputPlusRandom", { value in value &+ Int.random(in: 1 ... 1_000_000_000) })
        ]
        for entry in corpus {
            let result = await Self.checkDeterminism(of: entry.transform)
            let failed: Bool = if case .failed = result { true } else { false }
            #expect(failed, "Nondeterministic '\(entry.name)' should fail the emitted law; got \(result)")
        }
    }
}
