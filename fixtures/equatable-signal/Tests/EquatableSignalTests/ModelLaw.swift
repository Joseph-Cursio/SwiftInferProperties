/// The model law — `left == right` ⟺ `model(left) == model(right)` — and a
/// deterministic driver for it.
///
/// This exists because the Equatable law suite turns out to be *structurally*
/// unable to catch the projection-class bugs in `CollectionSubjects.swift`: a
/// projection of the stored fields is still an equivalence relation, so
/// reflexivity / symmetry / transitivity / negation-consistency all hold no
/// matter how wrong the projection is. The law that *can* fail compares `==`
/// against an independent reference definition of the value — the type's
/// canonical sequence view.
///
/// Hand-rolled rather than run through `propertyCheck`, for one reason: several
/// arms here *expect* a violation, and `propertyCheck` reports one by recording
/// a Swift Testing issue, which would fail the very test asserting the mutant
/// gets caught. This driver returns the outcome as a value instead.

// MARK: - Deterministic sampling

/// A seeded LCG. Deliberately not `SystemRandomNumberGenerator` and not
/// `Date`-derived: a counterexample here must be replayable from the seed
/// alone, and the repo's generator guidance treats unseeded sampling in a
/// measurement harness as a defect rather than a convenience.
struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func nextRaw() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 16
    }

    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(nextRaw() % span)
    }

    mutating func nextBool() -> Bool {
        nextRaw() & 1 == 0
    }

    /// True with probability `1 / oneIn`.
    mutating func chance(oneIn: Int) -> Bool {
        nextInt(in: 1 ... oneIn) == 1
    }
}

// MARK: - Outcome

struct ModelLawOutcome {
    var trialsRun: Int
    var counterexample: String?

    var passed: Bool { counterexample == nil }
}

// MARK: - Driver

/// Runs `left == right ⟺ model(left) == model(right)` over `trials` sampled
/// pairs, stopping at the first divergence.
///
/// `samplePair` rather than a single-value sampler on purpose. Every law here
/// needs the two values to *collide* in some way — be permutations of each
/// other, share logical contents while differing in representation — and a
/// pair of independently drawn values collides far too rarely to measure. This
/// is the collision-dependence caveat from the repo's guidance made explicit:
/// each sampler below narrows deliberately and says so.
func checkModelLaw<Subject, Model: Equatable>(
    trials: Int = 5_000,
    seed: UInt64 = 0x5EED_1234,
    samplePair: (inout SeededGenerator) -> (Subject, Subject),
    areEqual: (Subject, Subject) -> Bool,
    model: (Subject) -> Model,
    describe: (Subject) -> String
) -> ModelLawOutcome {
    var generator = SeededGenerator(seed: seed)
    for trial in 1 ... trials {
        let (left, right) = samplePair(&generator)
        let byOperator = areEqual(left, right)
        let byModel = model(left) == model(right)
        if byOperator != byModel {
            return ModelLawOutcome(
                trialsRun: trial,
                counterexample: """
                    left = \(describe(left)), right = \(describe(right)); \
                    left == right → \(byOperator), models equal → \(byModel)
                    """
            )
        }
    }
    return ModelLawOutcome(trialsRun: trials, counterexample: nil)
}

/// Reports a model-law outcome on the same one-line format the Equatable arms
/// print, so a run reads as one table.
func reportModelLaw(_ label: String, _ outcome: ModelLawOutcome) {
    if let counterexample = outcome.counterexample {
        print("  [\(label)] MODEL-LAW VIOLATION @ trial \(outcome.trialsRun): \(counterexample)")
    } else {
        print("  [\(label)] model law passed over \(outcome.trialsRun) trials — no counterexample")
    }
}
