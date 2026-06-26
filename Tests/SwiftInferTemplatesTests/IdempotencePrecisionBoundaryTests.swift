import PropertyLawKit
@testable import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Precision-boundary characterization for `IdempotenceTemplate` — pinned
/// against executable ground truth.
///
/// The template is a **static name/signature heuristic**: it scores a function
/// from its name and `T -> T` shape, never its semantics. It therefore *cannot*
/// be sound on its own, and the system does not ask it to be — the emitted
/// property test (validated separately in `EmittedIdempotenceLawSoundnessTests`)
/// is the actual verifier; the suggestion is a reviewer-facing candidate.
///
/// This suite makes that boundary explicit and regression-guarded. For a corpus
/// where we control *both* the name (what the template sees) and the
/// implementation (executable, so we know ground truth via `f(f(x)) == f(x)`),
/// it asserts the template's confidence class alongside the law's verdict —
/// including a **documented false positive**: a curated-verb function the
/// template confidently surfaces yet which the executable law fails.
///
/// If a future scoring change shifts this boundary — e.g. starts vetoing the
/// false-positive shape, or stops surfacing a true positive — these expectations
/// trip and force a conscious update.
@Suite
struct IdempotencePrecisionBoundaryTests {

    private static let seed = Seed(
        stateA: 0x0123_4567_89AB_CDEF,
        stateB: 0xFEDC_BA98_7654_3210,
        stateC: 0x1111_1111_1111_1111,
        stateD: 0x2222_2222_2222_2222
    )

    /// "Confident" = the template surfaces this as a real candidate a reviewer
    /// would act on. Defined explicitly rather than via `Tier`'s `Comparable`
    /// ordering to keep the intent unambiguous.
    private static func isConfident(_ tier: Tier?) -> Bool {
        tier == .strong || tier == .likely
    }

    /// The static side: the tier `IdempotenceTemplate` assigns to a
    /// `name : String -> String` function. The implementation is invisible here
    /// — that is the whole point.
    private static func tier(forName name: String) -> Tier? {
        let summary = makeIdempotenceSummary(name: name, paramType: "String", returnType: "String")
        return IdempotenceTemplate.suggest(for: summary)?.score.tier
    }

    /// The executable side: runs the emitted idempotence law `f(f(x)) == f(x)`
    /// over generated strings and reports whether it holds.
    private static func lawHolds(for transform: @escaping @Sendable (String) -> String) async -> Bool {
        let result = await SwiftPropertyBasedBackend().check(
            trials: 200,
            seed: seed,
            sample: { rng in
                let alphabet = Array("abcXYZ  ")
                let length = Int.random(in: 0 ... 10, using: &rng)
                return String((0 ..< length).map { _ in
                    alphabet[Int.random(in: 0 ..< alphabet.count, using: &rng)]
                })
            },
            property: { value in transform(transform(value)) == transform(value) }
        )
        if case .passed = result { return true }
        return false
    }

    private struct Case: Sendable {
        let label: String
        let name: String
        let transform: @Sendable (String) -> String
        let expectedConfident: Bool
        let expectedLawHolds: Bool
    }

    private static let corpus: [Case] = [
        // True positive: curated verb, genuinely idempotent → confident & holds.
        Case(
            label: "canonicalize=lowercased",
            name: "canonicalize",
            transform: { $0.lowercased() },
            expectedConfident: true,
            expectedLawHolds: true
        ),
        // True positive: curated verb, genuinely idempotent → confident & holds.
        Case(
            label: "normalize=prefix3",
            name: "normalize",
            transform: { String($0.prefix(3)) },
            expectedConfident: true,
            expectedLawHolds: true
        ),
        // DOCUMENTED FALSE POSITIVE: same curated verb as the first case, so the
        // template gives the same confident tier — but this implementation is
        // non-idempotent and the executable law fails. The heuristic confidently
        // mislabels it; only the emitted test catches the lie.
        Case(
            label: "canonicalize=append!",
            name: "canonicalize",
            transform: { $0 + "!" },
            expectedConfident: true,
            expectedLawHolds: false
        ),
        // Under-claim: an unrecognized name stays below confident even though the
        // implementation IS idempotent — the heuristic is high-precision,
        // low-recall by design.
        Case(
            label: "frobnicate=lowercased",
            name: "frobnicate",
            transform: { $0.lowercased() },
            expectedConfident: false,
            expectedLawHolds: true
        )
    ]

    @Test
    func characterizeBoundary_staticTierVsExecutableTruth() async {
        for entry in Self.corpus {
            let confident = Self.isConfident(Self.tier(forName: entry.name))
            #expect(
                confident == entry.expectedConfident,
                "[\(entry.label)] template confidence: expected \(entry.expectedConfident), got \(confident)"
            )

            let holds = await Self.lawHolds(for: entry.transform)
            #expect(
                holds == entry.expectedLawHolds,
                "[\(entry.label)] executable law: expected holds=\(entry.expectedLawHolds), got \(holds)"
            )
        }
    }

    /// The crux: two functions with the **same name** (`canonicalize`) get the
    /// **same confident tier** from the template — yet one satisfies the
    /// idempotence law and the other does not. Identical static signal, opposite
    /// ground truth: proof the heuristic cannot be sound on its own, which is
    /// exactly why the emitted property test exists.
    @Test
    func sameName_sameConfidence_oppositeTruth() async {
        let idempotent: @Sendable (String) -> String = { $0.lowercased() }
        let notIdempotent: @Sendable (String) -> String = { $0 + "!" }

        // The template sees only the name, so both are scored identically.
        let tierA = Self.tier(forName: "canonicalize")
        let tierB = Self.tier(forName: "canonicalize")
        #expect(Self.isConfident(tierA))
        #expect(Self.isConfident(tierB))
        #expect(tierA == tierB)

        // The executable law tells them apart.
        let holdsA = await Self.lawHolds(for: idempotent)
        let holdsB = await Self.lawHolds(for: notIdempotent)
        #expect(holdsA)
        #expect(holdsB == false)
    }
}
