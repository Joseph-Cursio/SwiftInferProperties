import Foundation
import Testing

@testable import SwiftInferCore

@Suite("Refutability — no filter may take a run to zero refutable laws")
struct RefutabilityTests {

    // MARK: - The classification

    @Test("the synthesized determinism law is the one tautology in the catalogue")
    func determinismIsTautological() {
        #expect(!Refutability.isRefutable(suggestion(template: "determinism")))
    }

    @Test("laws with content are refutable")
    func realTemplatesAreRefutable() {
        for template in ["partition", "comparator", "state-machine", "monotonicity", "round-trip"] {
            #expect(Refutability.isRefutable(suggestion(template: template)), "\(template)")
        }
    }

    // MARK: - The invariant

    @Test("a filter that keeps a refutable law is left alone — narrowing still works")
    func narrowingIsUntouched() {
        let partition = suggestion(template: "partition", canonical: "p")
        let comparator = suggestion(template: "comparator", canonical: "c")

        // The filter dropped `comparator`, but kept a law that can fail. That is a narrowing,
        // and the invariant has no business overriding it.
        let outcome = Refutability.preservingLastRefutable(
            filtered: [partition],
            from: [partition, comparator]
        )

        #expect(outcome.kept == [partition])
        #expect(outcome.rescued.isEmpty)
    }

    @Test("a filter that discards the LAST refutable law has it taken back")
    func lastRefutableLawIsRescued() {
        let partition = suggestion(template: "partition", canonical: "p")
        let tautology = suggestion(template: "determinism", canonical: "d")

        // This is the road-test fixture in miniature: the focus kept only the determinism law
        // and binned the one law in the run that could ever fail.
        let outcome = Refutability.preservingLastRefutable(
            filtered: [tautology],
            from: [tautology, partition]
        )

        #expect(outcome.kept.contains(partition), "the law that can fail must survive")
        #expect(outcome.rescued == [partition])
    }

    @Test("an honest empty stays empty — nothing refutable was found, so nothing is invented")
    func honestEmptyIsPreserved() {
        let tautology = suggestion(template: "determinism", canonical: "d")

        // The filter left only tautologies, but there were never any refutable laws to lose.
        // Rescuing here would mean fabricating a finding, which is the failure this whole
        // exercise exists to prevent.
        let outcome = Refutability.preservingLastRefutable(
            filtered: [tautology],
            from: [tautology]
        )

        #expect(outcome.kept == [tautology])
        #expect(outcome.rescued.isEmpty)
    }

    @Test("a filter that discards everything, refutable and not, still gets the refutable back")
    func totalErasureIsRescued() {
        let partition = suggestion(template: "partition", canonical: "p")
        let tautology = suggestion(template: "determinism", canonical: "d")

        let outcome = Refutability.preservingLastRefutable(
            filtered: [],
            from: [partition, tautology]
        )

        // Only the refutable law comes back. The tautology stays discarded — the invariant is
        // about preserving *meaning*, not about undoing the filter.
        #expect(outcome.kept == [partition])
        #expect(outcome.rescued == [partition])
    }

    @Test("every refutable law comes back, not merely one of them")
    func allRefutableLawsAreRescued() {
        let partition = suggestion(template: "partition", canonical: "p")
        let comparator = suggestion(template: "comparator", canonical: "c")

        let outcome = Refutability.preservingLastRefutable(
            filtered: [],
            from: [partition, comparator]
        )

        #expect(outcome.rescued.count == 2)
    }

    @Test("a rescue never duplicates a law the filter already kept")
    func noDuplication() {
        let partition = suggestion(template: "partition", canonical: "p")

        let outcome = Refutability.preservingLastRefutable(
            filtered: [partition],
            from: [partition]
        )

        #expect(outcome.kept.count == 1)
    }

    // MARK: - A rescue must not surface a law that CORRECT code fails

    /// The two axes are different, and conflating them ships a tool that cries wolf.
    ///
    /// *Refutable* = a wrong implementation can fail it. *Role-entailed* = a right one cannot.
    /// `monotonicity` is refutable and **not** role-entailed: it is a conjecture from a name, and
    /// `func get(_ key: String) -> Int { key.count }` violates it while being perfectly correct
    /// (`"aa" < "b"` yet `count("aa") > count("b")`).
    @Test("a conjecture is refutable but not role-entailed")
    func conjecturesAreNotRoleEntailed() {
        for template in ["monotonicity", "idempotence", "round-trip"] {
            let conjecture = suggestion(template: template)
            #expect(Refutability.isRefutable(conjecture), "\(template) can catch a bug")
            #expect(!Refutability.isRoleEntailed(conjecture), "\(template) may be false of correct code")
            #expect(!Refutability.isWorthSurfacingBelowCut(conjecture), "\(template)")
        }
    }

    @Test("a law owed by the role is safe to surface below the cut")
    func roleEntailedLawsAreSurfaceable() {
        for template in ["predicate", "comparator", "partition", "state-machine"] {
            #expect(Refutability.isWorthSurfacingBelowCut(suggestion(template: template)), "\(template)")
        }
    }

    /// **The rescue must not fire for a conjecture.** A run whose only non-tautology is a guessed
    /// `monotonicity` law keeps its tautologies: they are useless, and a law a correct function fails
    /// is worse than useless. Found by a cold reader, who called the shipped version of this
    /// "a false positive that would waste a developer's afternoon."
    @Test("the last REFUTABLE law is not rescued when it is only a conjecture")
    func conjecturesAreNotRescued() {
        let conjecture = suggestion(template: "monotonicity", canonical: "m")
        let tautology = suggestion(template: "determinism", canonical: "d")

        let outcome = Refutability.preservingLastRefutable(
            filtered: [tautology],
            from: [tautology, conjecture]
        )

        #expect(outcome.rescued.isEmpty, "a guessed law must not be promoted past the confidence cut")
        #expect(outcome.kept == [tautology])
    }

    /// …but a law owed by the role still is. This is the road-test fixture's phase 1: the only law
    /// that can fail is a state-machine inverse pair, and it must survive.
    @Test("the last role-entailed law IS rescued")
    func roleEntailedLawsAreRescued() {
        let owed = suggestion(template: "partition", canonical: "p")
        let tautology = suggestion(template: "determinism", canonical: "d")

        let outcome = Refutability.preservingLastRefutable(
            filtered: [tautology],
            from: [tautology, owed]
        )

        #expect(outcome.rescued == [owed])
    }

    // MARK: -

    private func suggestion(template: String, canonical: String = "x") -> Suggestion {
        let evidence = Evidence(
            displayName: "byteRange(ofChunk:)",
            signature: "(Int) -> Range<Int>",
            location: SourceLocation(file: "ChunkPlan.swift", line: 1, column: 1)
        )
        return Suggestion(
            templateName: template,
            evidence: [evidence],
            score: Score(signals: [Signal(kind: .typeSymmetrySignature, weight: 30, detail: "")]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: canonical)
        )
    }
}
