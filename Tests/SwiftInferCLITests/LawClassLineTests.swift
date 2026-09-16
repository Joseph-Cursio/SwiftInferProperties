import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// What a **pass** of an emitted test is allowed to mean (#453).
///
/// ## The harm this addresses
///
/// `mimeType_idempotence` was emitted, compiled, ran 100 trials and **passed** — and the law is
/// false. Its counterexamples are the three literals `css`, `js`, `woff2`, which the generator
/// cannot produce. Nothing in the emitted file, and no count the pipeline reports, separated it
/// from the three totality laws that genuinely passed in the same run.
///
/// **Measured across two subjects: entailed laws 3 run, 0 false; conjectures 5 run, 3 false.**
/// The class predicted every outcome. The *tier* predicted none — `parse` is Possible 30 and
/// true while `mimeType` is Possible 20 and false — which is why carrying the tier, the obvious
/// cheap fix, was measured and rejected.
///
/// ⚠ **This does not catch a false pass.** It tells the reader which kind of claim a green tick
/// is. #453's other two directions — seeding from the subject's literals, and declining when the
/// output cannot re-enter the input domain — were measured and declined on population.
@Suite("Emitted stubs say what a pass means")
struct LawClassLineTests {

    private static func suggestion(template: String) -> Suggestion {
        Suggestion(
            templateName: template,
            evidence: [
                Evidence(
                    displayName: "f(_:)",
                    signature: "(String) -> String",
                    location: SourceLocation(file: "F.swift", line: 1, column: 1)
                )
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "F.swift::f")
        )
    }

    /// The template that produced the false pass.
    @Test func aConjectureSaysAPassIsNotAProof() {
        let line = InteractiveTriage.lawClassLine(for: Self.suggestion(template: "idempotence"))
        #expect(line.contains("CONJECTURE"))
        #expect(line.contains("a CORRECT implementation can fail it"))
        #expect(line.contains("NOT that the law holds"))
    }

    /// The one that genuinely passed beside it.
    @Test func anEntailedLawSaysAPassIsAboutTheCode() {
        let line = InteractiveTriage.lawClassLine(for: Self.suggestion(template: "input-totality"))
        #expect(line.contains("ENTAILED"))
        #expect(line.contains("cannot fail this"))
    }

    /// **The load-bearing pair.** Two stubs that differed only in a template name must now differ
    /// in what they claim, or the line is decoration.
    @Test func theTwoClassesAreDistinguishable() {
        let conjecture = InteractiveTriage.lawClassLine(for: Self.suggestion(template: "idempotence"))
        let entailed = InteractiveTriage.lawClassLine(for: Self.suggestion(template: "input-totality"))
        #expect(conjecture != entailed)
        #expect(conjecture.contains("ENTAILED") == false)
        #expect(entailed.contains("CONJECTURE") == false)
    }

    /// `f(x) == f(x)` was labelled a CONJECTURE — "a CORRECT implementation can fail it" — because
    /// this line had two classes and `determinism` is in neither of them (#466). It is the one
    /// member of `Refutability.tautologicalTemplates`, the class furthest from a conjecture.
    @Test func aTautologyIsNotCalledAConjecture() {
        let line = InteractiveTriage.lawClassLine(for: Self.suggestion(template: "determinism"))
        #expect(line.contains("TAUTOLOGY"))
        #expect(line.contains("CONJECTURE") == false)
        #expect(line.contains("ENTAILED") == false)
    }

    /// A tautology's pass says almost nothing, and the line must say so. Its failure is the
    /// informative outcome — but it must not overclaim: a pure function whose result's `==` is not
    /// reflexive (a NaN inside a collection) fails too, and a reader told "impure" would go hunting
    /// for state that is not there.
    @Test func aTautologySaysWhatAPassAndAFailureMean() {
        let line = InteractiveTriage.lawClassLine(for: Self.suggestion(template: "determinism"))
        #expect(line.contains("a pass only means no hidden"))
        #expect(line.contains("not pure"))
        #expect(line.contains("not reflexive"))
    }

    /// The class is read from `Refutability`, not restated here — a guard that hardcodes the
    /// thing it guards only checks that two copies agree.
    ///
    /// **Four-way now, and it was two-way when #466 shipped.** The earlier form asserted "ENTAILED
    /// exactly when `isRoleEntailed`, CONJECTURE otherwise" over a list without `determinism` —
    /// so it encoded the bug it was meant to guard against, and passed.
    ///
    /// The fourth class is CHARACTERISATION (#468), and **the precedence is the load-bearing
    /// part**: it is a strict subset of role-entailed, so the more specific line has to win. A
    /// `guard-domain` stub labelled ENTAILED would tell the reader *a pass is a statement about
    /// the code* — and the code satisfies that law by construction, so the pass says nothing at
    /// all. This test caught exactly that when the class was added.
    @Test("every template classifies as Refutability says", arguments: [
        "idempotence", "input-totality", "predicate", "monotonicity",
        "guard-domain", "commutativity", "role-closure", "filter-subset", "determinism"
    ])
    func theLineAgreesWithRefutability(template: String) {
        let suggestion = Self.suggestion(template: template)
        let line = InteractiveTriage.lawClassLine(for: suggestion)
        let tautology = Refutability.isRefutable(suggestion) == false
        let characterisation = !tautology && Refutability.isCharacterisation(suggestion)
        let entailed = !tautology && !characterisation && Refutability.isRoleEntailed(suggestion)
        let conjecture = !tautology && !characterisation && !entailed
        #expect(line.contains("TAUTOLOGY") == tautology)
        #expect(line.contains("CHARACTERISATION") == characterisation)
        #expect(line.contains("ENTAILED") == entailed)
        #expect(line.contains("CONJECTURE") == conjecture)
    }

    /// **Characterisation is a subset of entailed, and the sets must stay that way.** If a
    /// template were listed as characterisation without being role-entailed, the line would claim
    /// the code owes a law the tool does not believe it owes.
    @Test func everyCharacterisationTemplateIsAlsoRoleEntailed() {
        #expect(Refutability.characterisationTemplates.isSubset(of: Refutability.roleEntailedTemplates))
        #expect(Refutability.characterisationTemplates.isDisjoint(with: Refutability.tautologicalTemplates))
    }

    /// Every emitted stub carries one — a header that is sometimes silent is worse than one that
    /// is always present, because a reader cannot tell absence from "not applicable".
    @Test func theLineIsNeverEmpty() {
        for template in ["idempotence", "input-totality", "round-trip", "determinism", "anything-unknown"] {
            #expect(InteractiveTriage.lawClassLine(for: Self.suggestion(template: template)).isEmpty == false)
        }
    }

    /// It is a comment block, so it cannot affect what the stub compiles to.
    @Test func itIsEntirelyComment() {
        for template in ["idempotence", "input-totality", "determinism"] {
            let line = InteractiveTriage.lawClassLine(for: Self.suggestion(template: template))
            let code = line.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            #expect(code.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        }
    }
}
