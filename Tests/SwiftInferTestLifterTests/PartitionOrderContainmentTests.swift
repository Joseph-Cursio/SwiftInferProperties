import SwiftInferCore
import Testing

@testable import SwiftInferTestLifter

/// **Does `PartitionAggregator`'s hash-seed-ordered intermediate escape?**
///
/// `docs/measurements/blindspot-base-rates.md` found `finalizeTwoClass` returning
/// `winnerByPredicate.values.map(\.candidate)` over a `[String: RankedCandidate]` —
/// hash-seed order, differing run to run — and `SoundPurity.verdict(for:)` answering
/// `.pure`. That census recorded the defect and **deliberately did not claim it was a
/// bug**, because whether the order reaches a user-visible artifact is a different
/// question. This answers it.
///
/// **The answer is no, and the reason is one hop up.** `finalize()` is
/// `(twoClass + nClass).sorted(by: Self.sortCandidates)`, so the nondeterministic
/// order is consumed by a sort before it leaves the aggregator.
///
/// ## Which makes the whole question comparator totality, and Swift's sort is not stable
///
/// `sorted(by:)` over a **partial** order leaves tied elements in input order, and
/// Swift's sort carries no stability guarantee — so a tie plus a hash-ordered input is
/// nondeterministic output even though a sort ran. Containment therefore rests entirely
/// on no two candidates comparing equal.
///
/// They cannot, and the key types are what guarantee it:
///
/// | tier | separates | why a tie is impossible |
/// |---|---|---|
/// | 1 · `predicateName` | everything with distinct names | — |
/// | 2 · two-class before N-class | a two-class from an N-class candidate | — |
/// | 3 · `markerSet?.name` | two N-class candidates | `NClassPartitionKey` **is**
/// |   |   | `(predicateName, markerSetName)`, so two distinct rows cannot share both |
/// | — | two two-class candidates | `winnerByPredicate` is keyed by `predicateName` alone, so there is at most one |
///
/// **Asserted by permutation rather than by that argument.** The reasoning above is
/// exactly the kind that has been wrong three times in this line of work; a property
/// test over shuffled inputs fails the day the comparator loses a tier or a key type
/// gains a field, which no amount of reading catches.
@Suite("Partition ordering — the aggregator's hash-order intermediate does not escape")
struct PartitionOrderContainmentTests {

    private static func twoClass(_ predicate: String) -> PartitionCandidate {
        PartitionCandidate(
            predicateName: predicate,
            markerPair: MarkerPair(positive: "Valid", negative: "Invalid"),
            positiveSites: [PartitionSite(methodName: "test\(predicate)Valid")],
            negativeSites: [PartitionSite(methodName: "test\(predicate)Invalid")],
            outlierSiteCount: 0
        )
    }

    private static func nClass(_ predicate: String, set: String) -> PartitionCandidate {
        PartitionCandidate(
            predicateName: predicate,
            markerSet: MarkerSet(name: set, markers: ["A", "B", "C"]),
            outlierSiteCount: 0
        )
    }

    /// A population exercising every way two candidates can nearly collide: shared
    /// predicate across the class boundary, and shared predicate within N-class
    /// separated only by marker-set name.
    private static var population: [PartitionCandidate] {
        [
            twoClass("alpha"),
            twoClass("beta"),
            nClass("alpha", set: "sizes"),
            nClass("alpha", set: "colours"),
            nClass("beta", set: "sizes"),
            nClass("gamma", set: "shapes")
        ]
    }

    /// **The containment property.** Every permutation of the same candidates must
    /// sort to the same sequence — which is exactly what a hash-ordered input feeding
    /// `finalize()` requires, and is false the moment the comparator admits a tie.
    @Test("every permutation of the same candidates sorts to one sequence")
    func sortIsOrderIndependent() {
        let candidates = Self.population
        let expected = candidates.sorted(by: PartitionAggregator.sortCandidates)
            .map(Self.identity)

        // Deterministic permutations rather than random ones: a seeded shuffle would
        // make a failure depend on the seed, and rotations plus a reversal already
        // cover "the tied pair arrives in the other order", which is the only input
        // property that can break a sort.
        var permutations: [[PartitionCandidate]] = [candidates.reversed()]
        for offset in 1..<candidates.count {
            permutations.append(Array(candidates[offset...] + candidates[..<offset]))
        }

        for (index, permutation) in permutations.enumerated() {
            let actual = permutation.sorted(by: PartitionAggregator.sortCandidates)
                .map(Self.identity)
            #expect(
                actual == expected,
                "permutation \(index) sorted differently — a tie means the hash-ordered input escapes finalize()"
            )
        }
    }

    /// The comparator is a **strict total order** on this population: for every
    /// distinct pair exactly one direction holds.
    ///
    /// A stronger statement than the permutation test and it fails earlier, naming the
    /// pair. Kept alongside rather than instead: the permutation test is the one that
    /// speaks to the actual question, and this one says why it passes.
    @Test("no two distinct candidates compare equal")
    func comparatorIsTotal() {
        let candidates = Self.population
        for outer in candidates.indices {
            for inner in candidates.indices where inner != outer {
                let lhs = candidates[outer]
                let rhs = candidates[inner]
                let forward = PartitionAggregator.sortCandidates(lhs, rhs)
                let backward = PartitionAggregator.sortCandidates(rhs, lhs)
                #expect(
                    forward != backward,
                    "tie: \(Self.identity(lhs)) vs \(Self.identity(rhs)) — unstable sort, so hash-seed order"
                )
            }
        }
    }

    /// The control: a comparator that *drops* the marker-set tier ties the two
    /// `alpha` N-class rows, and the permutation property fails.
    ///
    /// Without it, `sortIsOrderIndependent` passing proves nothing — a population with
    /// no near-collisions would pass against any comparator at all.
    @Test("the containment property FAILS against a comparator missing its last tier")
    func propertyDetectsAPartialOrder() {
        let partial: (PartitionCandidate, PartitionCandidate) -> Bool = { lhs, rhs in
            if lhs.predicateName != rhs.predicateName { return lhs.predicateName < rhs.predicateName }
            return (lhs.markerPair != nil) && (rhs.markerPair == nil)
        }
        let candidates = Self.population
        let forward = candidates.sorted(by: partial).map(Self.identity)
        let reversed = candidates.reversed().sorted(by: partial).map(Self.identity)
        #expect(
            forward != reversed,
            "a tie-admitting comparator sorted both permutations alike — this control no longer detects a partial order"
        )
    }

    private static func identity(_ candidate: PartitionCandidate) -> String {
        "\(candidate.predicateName)|\(candidate.markerPair == nil ? "n" : "2")|\(candidate.markerSet?.name ?? "-")"
    }
}
