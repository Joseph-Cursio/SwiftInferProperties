@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// The refactor-pending listing ranks and annotates by the seed's **role**.
///
/// A kernel seed can never be analysed — its symbol names the impure method the logic is trapped
/// inside, so there is nothing to call and no inputs to generate. This listing is therefore the
/// *only* channel through which a kernel finding reaches a reader, and everything the manifest
/// knows about it has to arrive here or nowhere.
///
/// Extraction is real work, so the one useful thing to say is **which of it pays**. A role that
/// entails a law — comparator, predicate, partition — guarantees a payoff: `ComparatorTemplate`,
/// `PredicateTemplate` and `PartitionTemplate` all exist, and "entailed" is exactly the claim that
/// a correct implementation cannot fail the law they propose. A `transform` may yield nothing but a
/// shape. Saying so for a conjectured role would sell a maybe as a guarantee.
@Suite("Refactor-pending advisory — role ranking and payoff")
struct RefactorPendingRoleRankingTests {

    private func seed(_ symbol: String, role: SeedRole?) -> SeedManifest.Seed {
        SeedManifest.Seed(
            file: "A.swift", line: 1, symbol: symbol,
            rule: "Pure Closure Property-Test Candidate", kind: .extractableKernel, role: role
        )
    }

    // MARK: - Ranking

    @Test("entailed roles are listed before conjectured ones")
    func entailedRolesComeFirst() {
        let ranked = SwiftInferCommand.Discover.prioritised([
            seed("mapper", role: .transform),
            seed("sorter", role: .comparator),
            seed("folder", role: .reducer),
            seed("tester", role: .predicate)
        ])
        #expect(ranked.prefix(2).map(\.symbol) == ["sorter", "tester"])
        #expect(ranked.suffix(2).map(\.symbol) == ["mapper", "folder"])
    }

    @Test("a seed with no role sorts with the conjectured ones, not ahead of them")
    func rolelessSeedsDoNotJumpTheQueue() {
        let ranked = SwiftInferCommand.Discover.prioritised([
            seed("unclassified", role: nil),
            seed("sorter", role: .comparator)
        ])
        #expect(ranked.map(\.symbol) == ["sorter", "unclassified"])
    }

    /// The scoping tests compare whole blocks, so the order has to be a function of the input and
    /// nothing else.
    @Test("ranking is stable within each group")
    func rankingIsStable() {
        let input = [
            seed("p1", role: .predicate), seed("t1", role: .transform),
            seed("p2", role: .predicate), seed("t2", role: .transform)
        ]
        // The explicit expected order IS the stability assertion: `p1` before `p2` and `t1` before
        // `t2` can only hold if each group preserves input order. Re-running the same pure function
        // on the same input and comparing would assert nothing — there is no randomness to catch.
        #expect(SwiftInferCommand.Discover.prioritised(input).map(\.symbol) == ["p1", "p2", "t1", "t2"])
    }

    @Test("ranking never loses or duplicates a seed")
    func rankingIsAPermutation() {
        let input = [
            seed("a", role: .comparator), seed("b", role: nil),
            seed("c", role: .partition), seed("d", role: .normalizer)
        ]
        let ranked = SwiftInferCommand.Discover.prioritised(input)
        #expect(ranked.count == input.count)
        #expect(Set(ranked.map(\.symbol)) == Set(input.map(\.symbol)))
    }

    // MARK: - The payoff clause

    @Test("an entailed role names the template that will fire")
    func entailedRoleNamesItsTemplate() {
        let line = SwiftInferCommand.Discover.listing(seed("sorter", role: .comparator))
        #expect(line.contains("It is a comparator"))
        #expect(line.contains("Extracting it PAYS"))
        #expect(line.contains("`comparator` law"))
        #expect(line.contains("cannot fail"))
    }

    @Test("a conjectured role describes the law but promises no payoff")
    func conjecturedRoleMakesNoPromise() {
        // `transform` and `reducer` and `normalizer` name real shapes whose laws are guesses. The
        // listing still says what they are — that is worth knowing — but claiming a guaranteed
        // payoff would be the overclaim `Refutability` exists to prevent.
        for role in [SeedRole.transform, .reducer, .normalizer] {
            let line = SwiftInferCommand.Discover.listing(seed("f", role: role))
            #expect(line.contains("It is a"), "\(role.rawValue) should still describe itself")
            #expect(line.contains("PAYS") == false, "\(role.rawValue) is conjectured, not entailed")
        }
    }

    @Test("a seed with no role still gets the location and the instruction")
    func rolelessSeedStillReadable() {
        let line = SwiftInferCommand.Discover.listing(seed("mystery", role: nil))
        #expect(line.contains("inside `mystery`"))
        #expect(line.contains("extract it into a named value type"))
        #expect(line.contains("It is a") == false)
        #expect(line.contains("PAYS") == false)
    }

    @Test("an unrecognised role adds nothing it cannot justify")
    func unrecognisedRoleIsSilent() {
        // Same asymmetry as `SeedKind.unrecognised`: a role from a newer linter must not be
        // described or promised on, because this build cannot interpret it.
        let line = SwiftInferCommand.Discover.listing(seed("f", role: .unrecognised("bifunctor")))
        #expect(line.contains("inside `f`"))
        #expect(line.contains("It is a") == false)
        #expect(line.contains("PAYS") == false)
    }
}
