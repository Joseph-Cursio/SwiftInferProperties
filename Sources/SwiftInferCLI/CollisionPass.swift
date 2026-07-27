import Foundation

/// The **collision pass** — a second sweep of a binary law under deliberately
/// narrowed entropy, so that independently-drawn operands share field values.
///
/// ## The problem it exists for
///
/// A derived generator is tuned for coverage of the *type*: realistic domains,
/// wide ranges, values that look like production data. That is silently the
/// wrong tuning for coverage of the *law*. Any property whose failure requires
/// two generated values to **collide** — a merge tie-break, a cache-key clash,
/// dedup, key injectivity — is unreachable, because a realistic key space makes
/// collisions astronomically unlikely.
///
/// This is not hypothetical. `Decisions.merge` commutativity is **false** — on a
/// timestamp tie the fold keeps the receiver's record — and `verify` reported
/// `measured-bothPass` at 100 trials, because the strategist draws
/// `identityHash` from an eight-character alphanumeric space and `capturedAt`
/// from `Gen<Date>.date`. Two records essentially never share both. Measured
/// directly: the same generated stub, with only the identity and timestamp
/// alphabets narrowed by hand, fails at trial 5.
///
/// A confident green is the mirror of the confident zero this project was built
/// to warn about, and it is worse: `measured-bothPass` promotes a pick to
/// `Verified` and publishes it through `docc`, whose whole premise is that
/// documented properties are provable.
///
/// ## Why narrow the RNG rather than the generator
///
/// The obvious fix — rewrite the recipe so key-like leaves draw from a small
/// pool — needs structural surgery on an expression this layer only has as a
/// *string*, plus a heuristic for which leaves are "key-like". Both are
/// guesswork.
///
/// Every leaf generator instead draws from the same `RandomNumberGenerator`. So
/// narrowing **the RNG** narrows every field at once, whatever the recipe looks
/// like: string lengths, character choices, dates, enum case indices, array
/// counts. No recipe parsing, no heuristics, and it works for a carrier shape
/// nobody has seen yet.
///
/// ## Why this cannot produce a false positive
///
/// The narrowed values still come out of the *same generators*, so every
/// operand is a legitimate value of the carrier type. A counterexample found
/// here is a genuine refutation — the law really is false for values the type
/// admits. The pass therefore adds recall and can never add a false alarm,
/// which is what makes it safe to run by default under a project whose stated
/// posture is high precision (PRD §3.5).
///
/// It is emphatically **not** a completeness claim. It raises the probability of
/// reaching a collision-dependent branch from ~zero to high; it does not
/// guarantee it. A law that passes both sweeps is still only "no counterexample
/// in the generated domain."
enum CollisionPass {

    /// Pool sizes cycled across trials — how many *distinct* values the RNG may
    /// return before the generators reduce them.
    ///
    /// **Small domain, not small numbers.** The first version of this masked the
    /// RNG's output (`next() & 0x3`), which is not the same thing at all: every
    /// value the generators derive from it collapses toward zero, so
    /// `.array(of: 0...8)` yielded a count of 0 on every draw and both operands
    /// came out *empty*. Commutativity on two empty logs is trivially true, and
    /// the sweep reported a clean pass while reaching nothing. Measured by
    /// probing the generated stub — the counts were 0 for every trial.
    ///
    /// Drawing from a pool of well-spread constants keeps the values varied
    /// (non-degenerate lengths, real characters, spread dates) while keeping the
    /// *number of possibilities* tiny, which is what actually makes two
    /// independent draws share a field. Rotating the size sweeps "almost always
    /// identical" through "occasionally equal", so a law needing two *distinct*
    /// records that agree on one column — the `merge` tie — is reached somewhere.
    static let poolSizes = "[2, 3, 4, 6, 8]"

    /// The RNG wrapper, emitted into the stub. Conforms to
    /// `SeededRandomNumberGenerator` because `Generator.run(using:)` is generic
    /// over it; the inner Xoshiro is carried so the caller can write the
    /// advanced state back and keep the whole run deterministic from one seed.
    static let rngDeclaration = """
        /// Narrows an inner Xoshiro's output so independently-drawn values collide
        /// on individual fields. See `CollisionPass` in SwiftInferCLI for why the
        /// entropy is narrowed at the RNG rather than at the generator.
        struct NarrowedRNG: SeededRandomNumberGenerator {
            /// Well-spread constants (golden-ratio and PCG-style increments) so a
            /// generator reducing them into a range lands on varied results rather
            /// than clustering at zero.
            static let entropyPool: [UInt64] = [
                0x9E37_79B9_7F4A_7C15, 0x5851_F42D_4C95_7F2D,
                0x1405_7B7E_F767_814F, 0x2545_F491_4F6C_DD1D,
                0xD1B5_4A32_D192_ED03, 0xABCD_1234_5678_9EF0,
                0x0123_4567_89AB_CDEF, 0xFEDC_BA98_7654_3210
            ]

            typealias Seed = String
            var inner: Xoshiro
            var poolSize: Int

            init(inner: Xoshiro, poolSize: Int) {
                self.inner = inner
                self.poolSize = max(1, min(poolSize, Self.entropyPool.count))
            }

            init?(seed: String) {
                guard let inner = Xoshiro(seed: seed) else { return nil }
                self.inner = inner
                self.poolSize = 4
            }

            // Required by the protocol. Never used by the sweep, which always
            // constructs with an explicit inner state so the whole run stays
            // reproducible from the stub's single seed.
            init() {
                self.inner = Xoshiro()
                self.poolSize = 4
            }

            var currentSeed: String { inner.currentSeed }

            mutating func next() -> UInt64 {
                Self.entropyPool[Int(inner.next() % UInt64(poolSize))]
            }

            static func == (lhs: Self, rhs: Self) -> Bool {
                lhs.currentSeed == rhs.currentSeed && lhs.poolSize == rhs.poolSize
            }

            func hash(into hasher: inout Hasher) {
                hasher.combine(currentSeed)
                hasher.combine(poolSize)
            }
        }
        """

    /// Emit the collision sweep for a **binary** law (`f(a, b)` vs `f(b, a)`).
    ///
    /// Runs before the stub prints `VERIFY_DEFAULT_RESULT: PASS`, and reports a
    /// failure through the *same* `VERIFY_DEFAULT_*` markers — because it is the
    /// same verdict. The values are ordinary values of the type, so the law is
    /// simply false; nothing about the parser or the promotion path needs to
    /// know which sweep found it. `VERIFY_DEFAULT_PASS_KIND: collision` rides
    /// along so the detail can say where it came from.
    static func binarySweep(functionCall: String, carrier: String) -> String {
        """
        // --- Pass 1b: collision sweep (narrowed entropy) ---
        //
        // The derived generator is tuned for coverage of the TYPE, which makes
        // any law that fails only on colliding operands unreachable. Narrowing
        // the RNG narrows every field at once, so two independent draws share
        // keys and timestamps often. Values remain legitimate values of
        // \(carrier), so a failure here is a genuine refutation.
        let collisionPoolSizes: [Int] = \(poolSizes)
        for trial in 0 ..< trials {
            var narrowed = NarrowedRNG(
                inner: collisionBase,
                poolSize: collisionPoolSizes[trial % collisionPoolSizes.count]
            )
            let lhs = defaultGenerator.run(using: &narrowed)
            let rhs = defaultGenerator.run(using: &narrowed)
            collisionBase = narrowed.inner
            let lhsResult = \(functionCall)(lhs, rhs)
            let rhsResult = \(functionCall)(rhs, lhs)
            if lhsResult != rhsResult {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_PASS_KIND: collision")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: (\\(lhs), \\(rhs))")
                print("VERIFY_DEFAULT_FORWARD: \\(lhsResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(rhsResult)")
                exit(1)
            }
        }
        """
    }

    /// The ternary form (`f(f(a, b), c)` vs `f(a, f(b, c))`) — associativity.
    static func ternarySweep(functionCall: String, carrier _: String) -> String {
        """
        // --- Pass 1b: collision sweep (narrowed entropy) — see the binary form.
        let collisionPoolSizes: [Int] = \(poolSizes)
        for trial in 0 ..< trials {
            var narrowed = NarrowedRNG(
                inner: collisionBase,
                poolSize: collisionPoolSizes[trial % collisionPoolSizes.count]
            )
            let aValue = defaultGenerator.run(using: &narrowed)
            let bValue = defaultGenerator.run(using: &narrowed)
            let cValue = defaultGenerator.run(using: &narrowed)
            collisionBase = narrowed.inner
            let leftResult = \(functionCall)(\(functionCall)(aValue, bValue), cValue)
            let rightResult = \(functionCall)(aValue, \(functionCall)(bValue, cValue))
            if leftResult != rightResult {
                print("VERIFY_DEFAULT_RESULT: FAIL")
                print("VERIFY_DEFAULT_PASS_KIND: collision")
                print("VERIFY_DEFAULT_TRIAL: \\(trial)")
                print("VERIFY_DEFAULT_INPUT: (\\(aValue), \\(bValue), \\(cValue))")
                print("VERIFY_DEFAULT_FORWARD: \\(leftResult)")
                print("VERIFY_DEFAULT_INVERSE: \\(rightResult)")
                exit(1)
            }
        }
        """
    }

    /// The mutable Xoshiro the sweep threads through its trials, declared
    /// alongside the stub's main `rng` so the collision draws continue the same
    /// deterministic stream rather than restarting it.
    static let baseDeclaration = "var collisionBase = Xoshiro(seed: seedTuple)"
}
