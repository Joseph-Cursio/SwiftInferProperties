import Foundation
import Testing

@testable import SwiftInferCore

/// The `gen()` signature this tool tells users to write must be the one that compiles.
///
/// It said `static func gen() -> Gen<T>` until 2026-08-14. `Gen` is
/// `public enum Gen<Value> {}` — an uninhabitable namespace of static factories — so nobody
/// following that advice could build. The real type is
/// `Generator<T, some SendableSequenceType>`, which the kit has always documented.
///
/// **This is issue #256's class, and #256's guard cannot catch it.**
/// `RefusalFlagVocabularyTests` asserts every `--flag` named in a refusal actually parses;
/// this is a type name, not a flag. The defect was found by *following the advice literally*
/// while road-testing GRDB — the one check neither repo performs.
///
/// **Scale is why it matters**: `unsupportedCarrier` is the most-shown remedy on unfamiliar
/// code (138 rows on GRDB, 18 on swift-format, 5 here). It is invisible from inside the
/// project, because nobody working here needs telling how to write a generator.
@Suite("gen() advice — the signature we prescribe is the one that compiles")
struct GenAdviceCompilesTests {

    private var carrierRemedy: String { UnverifiableCause.unsupportedCarrier.remedy }

    @Test("the carrier remedy does not prescribe a return type that cannot exist")
    func remedyDoesNotReturnTheNamespace() {
        // `Gen` has no cases. A function returning `Gen<T>` cannot be written, let alone
        // called. Asserted on RETURN-TYPE position only: `Gen<Int>.int(in:)` in expression
        // position is correct and is what every emitted recipe uses, so a blanket ban on the
        // substring would fail for the wrong reason.
        #expect(!carrierRemedy.contains("-> Gen<"))
        #expect(!carrierRemedy.contains("→ Gen<"))
    }

    @Test("the carrier remedy prescribes the kit's own signature")
    func remedyMatchesTheKit() {
        #expect(carrierRemedy.contains("Generator<"))
        #expect(carrierRemedy.contains("some SendableSequenceType"))
    }

    @Test("the carrier remedy states the dependency it requires")
    func remedyStatesItsCost() {
        // Following it makes swift-property-based a dependency of the PRODUCTION target under
        // test. The old wording said "in your target" and left that to be discovered.
        #expect(carrierRemedy.contains("PropertyBased"))
    }

    /// Read the signature out of the kit rather than restating it — a guard that restates
    /// what it guards only checks that two copies agree.
    ///
    /// A missing sibling checkout reports UNAVAILABLE rather than passing, the
    /// `DeferralFalsifierTests` posture: no clone is not a clean bill of health.
    @Test("the kit still prescribes the signature this advice mirrors")
    func kitStillSaysGenerator() {
        var repoRoot = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 { repoRoot = repoRoot.deletingLastPathComponent() }
        let todoReason = repoRoot
            .appendingPathComponent("SwiftPropertyLaws/Sources/PropertyLawCore/TodoReason.swift")
        guard let kitText = try? String(contentsOf: todoReason, encoding: .utf8) else {
            let unavailable = "SwiftPropertyLaws checkout not found at \(todoReason.path) — the "
                + "prescribed signature could not be checked against the kit. UNAVAILABLE, "
                + "not agreement."
            Issue.record(Comment(rawValue: unavailable))
            return
        }
        // The kit emits `static func gen() -> Generator<<name>, some SendableSequenceType>`.
        // If the kit ever changes shape, this fails here rather than in a user's build.
        #expect(kitText.contains("static func gen() -> Generator<"))
        #expect(kitText.contains("SendableSequenceType"))
    }

    @Test("every cause still yields a non-empty remedy")
    func everyCauseHasARemedy() {
        // Parameterised over the enum so a new cause cannot ship with empty guidance — the
        // `everyFamilyMarksItsCheck` pattern.
        for cause in UnverifiableCause.allCases {
            #expect(!cause.remedy.isEmpty, Comment(rawValue: "\(cause) has no remedy"))
        }
    }
}
