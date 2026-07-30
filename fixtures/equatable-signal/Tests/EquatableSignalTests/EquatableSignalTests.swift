import ComplexModule
import PropertyBased
import PropertyLawComplex
import PropertyLawKit
import Testing

/// Does an `Equatable` conformance, *on its own*, justify a property test?
///
/// swift-numerics main has exactly two `Equatable` conformances. This suite
/// runs the kit's four Equatable laws (and the three Hashable laws) against
/// faithful reproductions of both, plus plausible mutants of each, and scores
/// **refutability**: does some plausible-but-wrong implementation get rejected?
///
/// `enforcement: .strict` so every violation escalates into
/// `PropertyLawViolation` and none is silently recorded as a test issue.
@Suite("Equatable-as-a-signal")
struct EquatableSignalTests {
    static let trials = 5_000

    // MARK: - Harness

    static func equatableViolations<Value: Equatable & Sendable, Shrinker: SendableSequenceType>(
        _ label: String,
        _ generator: Generator<Value, Shrinker>
    ) async -> [String] {
        let options = LawCheckOptions(budget: .custom(trials: trials), enforcement: .strict)
        do {
            _ = try await checkEquatablePropertyLaws(using: generator, options: options)
            print("  [\(label)] Equatable: 4/4 laws passed over \(trials) trials — no counterexample")
            return []
        } catch let violation as PropertyLawViolation {
            for result in violation.results {
                print("  [\(label)] VIOLATION \(result.protocolLaw) @ trial \(result.trials): \(result.outcome)")
            }
            return violation.results.map(\.protocolLaw)
        } catch {
            Issue.record("[\(label)] unexpected error: \(error)")
            return ["<error>"]
        }
    }

    static func hashableViolations<Value: Hashable & Sendable, Shrinker: SendableSequenceType>(
        _ label: String,
        _ generator: Generator<Value, Shrinker>
    ) async -> [String] {
        let options = LawCheckOptions(budget: .custom(trials: trials), enforcement: .strict)
        do {
            _ = try await checkHashablePropertyLaws(using: generator, options: options)
            print("  [\(label)] Hashable: all laws passed over \(trials) trials — no counterexample")
            return []
        } catch let violation as PropertyLawViolation {
            for result in violation.results {
                print("  [\(label)] VIOLATION \(result.protocolLaw) @ trial \(result.trials): \(result.outcome)")
            }
            return violation.results.map(\.protocolLaw)
        } catch {
            Issue.record("[\(label)] unexpected error: \(error)")
            return ["<error>"]
        }
    }

    // MARK: - Arm 1 — the shipped Complex, as it exists on swift-numerics main

    @Test("Shipped Complex<Double> satisfies Equatable and Hashable under edge bias")
    func shippedComplexHolds() async {
        let equatable = await Self.equatableViolations(
            "swift-numerics Complex<Double>",
            Gen<Complex<Double>>.edgeCaseBiased()
        )
        let hashable = await Self.hashableViolations(
            "swift-numerics Complex<Double>",
            Gen<Complex<Double>>.edgeCaseBiased()
        )
        #expect(equatable.isEmpty)
        #expect(hashable.isEmpty)
    }

    // MARK: - Arm 2 — control: is the reproduction faithful?

    @Test("Faithful reproduction of Complex's == also holds")
    func faithfulReproductionHolds() async {
        let violations = await Self.equatableViolations(
            "FaithfulComplex (control)",
            edgeBiasedComponents().map { FaithfulComplex(x: $0.0, y: $0.1) }
        )
        #expect(violations.isEmpty)
    }

    // MARK: - Arm 3 — the refutability question for Complex

    @Test("The obvious componentwise == is REFUTED (reflexivity, via NaN)")
    func componentwiseIsRefuted() async {
        let violations = await Self.equatableViolations(
            "ComponentwiseComplex + edge-biased",
            edgeBiasedComponents().map { ComponentwiseComplex(x: $0.0, y: $0.1) }
        )
        #expect(violations.contains("Equatable.reflexivity"))
    }

    // MARK: - Arm 4 — same mutant, realistic generator

    @Test("The same mutant survives a finite-only generator")
    func componentwiseSurvivesFiniteGenerator() async {
        let violations = await Self.equatableViolations(
            "ComponentwiseComplex + finite-only",
            finiteComponents().map { ComponentwiseComplex(x: $0.0, y: $0.1) }
        )
        #expect(violations.isEmpty, "expected the law to be blind here; that is the finding")
    }

    // MARK: - Arm 5 — the hash half of the conformance

    @Test("Dropping Complex's non-finite hash normalisation is REFUTED")
    func naiveHashIsRefuted() async {
        let violations = await Self.hashableViolations(
            "NaiveHashComplex + edge-biased",
            edgeBiasedComponents().map { NaiveHashComplex(x: $0.0, y: $0.1) }
        )
        #expect(violations.contains("Hashable.equalityConsistency"))
    }

    // MARK: - Arm 6-9 — DoubleWidth: memberwise delegation

    @Test("Faithful DoubleWidth-shaped == holds")
    func faithfulWidePairHolds() async {
        let violations = await Self.equatableViolations(
            "FaithfulWidePair (control)",
            widePairComponents().map { FaithfulWidePair(high: $0.0, low: $0.1) }
        )
        #expect(violations.isEmpty)
    }

    @Test("Forgetting the high word entirely SURVIVES all four Equatable laws")
    func lowWordOnlySurvives() async {
        let violations = await Self.equatableViolations(
            "LowWordOnlyPair (semantically broken)",
            widePairComponents().map { LowWordOnlyPair(high: $0.0, low: $0.1) }
        )
        #expect(violations.isEmpty, "a projection is still an equivalence relation — that is the finding")
    }

    @Test("Comparing the wrong fields — refuted or not?")
    func crossedFieldsOutcome() async {
        let violations = await Self.equatableViolations(
            "CrossedFieldsPair",
            widePairComponents().map { CrossedFieldsPair(high: $0.0, low: $0.1) }
        )
        print("  >> CrossedFieldsPair violations: \(violations)")
    }

    @Test("A <= slipping in for == IS refuted")
    func orderedLeakIsRefuted() async {
        let violations = await Self.equatableViolations(
            "OrderedLeakPair",
            widePairComponents().map { OrderedLeakPair(high: $0.0, low: $0.1) }
        )
        print("  >> OrderedLeakPair violations: \(violations)")
        #expect(!violations.isEmpty)
    }
}
