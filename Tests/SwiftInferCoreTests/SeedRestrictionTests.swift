import Foundation
import Testing

@testable import SwiftInferCore

/// The manifest's `restriction`, and what this build is allowed to do with it.
///
/// The field says **what would have to move** for a test to reach a seeded symbol. Its whole value
/// is that the two remedies are not interchangeable: widening a declaration whose enclosing type is
/// the real blocker compiles, changes nothing, and leaves the law still unrunnable — with the
/// reader having done what the tool asked.
@Suite("SeedRestriction — the producer's access answer")
struct SeedRestrictionTests {

    // MARK: - Decoding

    @Test("the two producer spellings decode")
    func decodesProducerSpellings() throws {
        #expect(try decode("\"declaration\"") == .declaration)
        #expect(try decode("\"enclosing-type\"") == .enclosingType)
    }

    /// An unknown spelling is carried, not guessed at and not rejected.
    ///
    /// Rejecting would fail a whole manifest over one seed from a newer linter. Guessing
    /// `.declaration` would be worse than either — it is the one value that licenses the widening
    /// patch this type exists to prevent.
    @Test("an unknown spelling is carried as unrecognised")
    func carriesUnknownSpelling() throws {
        #expect(try decode("\"module-boundary\"") == .unrecognised("module-boundary"))
    }

    @Test("round-trips through encoding")
    func roundTrips() throws {
        for restriction in [SeedRestriction.declaration, .enclosingType, .unrecognised("x")] {
            let data = try JSONEncoder().encode(restriction)
            #expect(try JSONDecoder().decode(SeedRestriction.self, from: data) == restriction)
        }
    }

    private func decode(_ json: String) throws -> SeedRestriction {
        try JSONDecoder().decode(SeedRestriction.self, from: Data(json.utf8))
    }

    // MARK: - Reconciliation

    /// The case the field is carried for.
    ///
    /// This scan's enclosing-type stack is same-declaration only, so a member of an unmarked
    /// `extension` of a `private` type reads locally as blocked by its own modifier. The manifest
    /// resolved the type; believing it here turns a no-op patch into the remedy that works.
    @Test("the manifest wins when it names an enclosing type this scan could not see")
    func manifestWinsOnEnclosingType() {
        #expect(
            AccessRestriction.notVisibleToTests.reconciled(with: .enclosingType)
                == .enclosingTypeNotVisibleToTests
        )
    }

    /// Everything else is left alone. Preferring the manifest wholesale would let a stale seed
    /// overrule a syntactic reading of the declaration in front of us, and the failure would be
    /// invisible because both answers are plausible sentences about access.
    @Test("this scan wins everywhere else")
    func localWinsOtherwise() {
        #expect(AccessRestriction.notVisibleToTests.reconciled(with: .declaration) == .notVisibleToTests)
        #expect(AccessRestriction.notVisibleToTests.reconciled(with: nil) == .notVisibleToTests)
        #expect(AccessRestriction.nestedLocal.reconciled(with: .enclosingType) == .nestedLocal)
        #expect(AccessRestriction.internalOrSPI.reconciled(with: .enclosingType) == .internalOrSPI)
        #expect(
            AccessRestriction.enclosingTypeNotVisibleToTests.reconciled(with: .declaration)
                == .enclosingTypeNotVisibleToTests
        )
    }

    /// An unrecognised spelling must never trigger the upgrade — this build cannot say what it
    /// means, and the upgrade is the one that changes the advice.
    @Test("an unrecognised restriction changes nothing")
    func unrecognisedChangesNothing() {
        #expect(
            AccessRestriction.notVisibleToTests.reconciled(with: .unrecognised("enclosing_type"))
                == .notVisibleToTests
        )
    }

    /// Reconciliation must be idempotent, since the reconciled value is what gets rendered and
    /// could be reconciled again by a later caller.
    @Test("reconciling twice is reconciling once")
    func reconciliationIsIdempotent() {
        let locals: [AccessRestriction] = [
            .notVisibleToTests, .internalOrSPI, .nestedLocal, .enclosingTypeNotVisibleToTests
        ]
        let seeds: [SeedRestriction?] = [nil, .declaration, .enclosingType, .unrecognised("z")]
        for local in locals {
            for seed in seeds {
                let once = local.reconciled(with: seed)
                #expect(once.reconciled(with: seed) == once)
            }
        }
    }

    // MARK: - Disagreement

    /// Reported, never silently resolved. Two tools disagreeing without saying so is how
    /// `restricted-function` went wrong the first time — 316 of 468 supposedly analysable seeds
    /// named a function no test could call, unnoticed until both sides stated their beliefs in a
    /// comparable vocabulary.
    @Test("a genuine conflict is reported")
    func reportsGenuineConflict() {
        // We found an enclosing type; the manifest says the declaration is the only blocker.
        #expect(AccessRestriction.enclosingTypeNotVisibleToTests.disagrees(with: .declaration))
        // The manifest says an enclosing type blocks it; we found something unrelated to access
        // nesting entirely.
        #expect(AccessRestriction.nestedLocal.disagrees(with: .enclosingType))
        #expect(AccessRestriction.internalOrSPI.disagrees(with: .enclosingType))
    }

    /// Silence is not a conflict, and neither is a word this build does not know.
    ///
    /// The producer classifies only `restricted-function` seeds, so absence is "not asked" — the
    /// same reading `role` and `effect` get. Treating it as a conflict would make every
    /// `pure-function` seed report one.
    @Test("absence, agreement and version skew are not conflicts")
    func doesNotInventConflicts() {
        #expect(!AccessRestriction.notVisibleToTests.disagrees(with: nil))
        #expect(!AccessRestriction.notVisibleToTests.disagrees(with: .declaration))
        #expect(!AccessRestriction.enclosingTypeNotVisibleToTests.disagrees(with: .enclosingType))
        #expect(!AccessRestriction.nestedLocal.disagrees(with: .unrecognised("what")))

        // The reconciled case in particular: this pair is the one we *fix*, so calling it a
        // disagreement would print a note about something already handled.
        #expect(!AccessRestriction.notVisibleToTests.disagrees(with: .enclosingType))
    }
}
