import Foundation
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The `+20` cross-validation signal names **which** test corroborates the law.
///
/// It was designed to mean *this codebase independently states this law*. Once the slicer
/// could read property tests, it could equally mean *this codebase took our advice* — the four
/// `merge(_:)` commutativity rows are corroborated by `MergeAlgebraPropertyTests`, whose own
/// header says the laws were ones `discover` **proposed**
/// (`docs/measurements/roadtest-self-dogfood-2026-08-08.md` §7.6). Those are different claims
/// and they rendered identically.
///
/// The resolution is not to suppress the signal but to **name its source**, the same medicine
/// §7.4 applied to lifted rows. This does not settle whether such corroboration *should*
/// count — it makes the question answerable by the person reading the row.
@Suite("Cross-validation names its corroborating test")
struct CrossValidationOriginTests {

    private static func origin(
        method: String = "commutativityHolds",
        file: String = "/repo/Tests/CLITests/MergeAlgebraPropertyTests.swift",
        line: Int = 91
    ) -> LiftedOrigin {
        LiftedOrigin(
            testMethodName: method,
            sourceLocation: SourceLocation(file: file, line: line, column: 9)
        )
    }

    // MARK: - Rendering

    @Test("with an origin, the detail names the file, line and test method")
    func detailNamesTheCorroborator() {
        let detail = TemplateRegistry.crossValidationDetail(for: Self.origin())
        #expect(detail.contains("MergeAlgebraPropertyTests.swift:91"))
        #expect(detail.contains("commutativityHolds"))
        #expect(detail.hasPrefix("Cross-validated by TestLifter"))
    }

    /// The degraded form must still be the old sentence — a suggestion corroborated by a
    /// corpus-level finding has no single test to name, and inventing one would be worse than
    /// saying less.
    @Test("with no origin, the detail is the unqualified sentence")
    func detailDegradesCleanly() {
        #expect(
            TemplateRegistry.crossValidationDetail(for: nil)
                == TemplateRegistry.crossValidationDetail
        )
    }

    /// An unresolvable origin is treated as no origin. `<test-body>:0` and `<corpus>:0` name
    /// nothing a reader can open, and printing them would restate the §7.4 defect inside its
    /// own fix.
    @Test("an unresolvable origin degrades rather than printing a placeholder")
    func unresolvableOriginDegrades() {
        let placeholder = LiftedOrigin(
            testMethodName: "corpus", sourceLocation: .testBodyPlaceholder
        )
        let detail = TemplateRegistry.crossValidationDetail(for: placeholder)
        #expect(detail == TemplateRegistry.crossValidationDetail)
        #expect(!detail.contains("<test-body>"))
    }

    // MARK: - The invariant that matters

    /// **Origins are advisory: they must never change WHETHER the signal fires.**
    ///
    /// The key set stays authoritative. If supplying origins could add or remove a `+20`, the
    /// two collections would have to agree, and a presentational map would have become a
    /// scoring input — the drift this design exists to avoid.
    @Test("supplying origins does not change which suggestions are cross-validated")
    func originsDoNotChangeWhoFires() {
        let suggestions = [Self.suggestion()]
        let keys: Set<CrossValidationKey> = [suggestions[0].crossValidationKey]

        let without = TemplateRegistry.applyCrossValidation(to: suggestions, matching: keys)
        let with = TemplateRegistry.applyCrossValidation(
            to: suggestions, matching: keys, origins: [suggestions[0].crossValidationKey: Self.origin()]
        )
        #expect(without[0].score.total == with[0].score.total, "the +20 must be identical")
        #expect(
            without[0].score.signals.count == with[0].score.signals.count,
            "the same signals must fire; only their text may differ"
        )
    }

    /// An origin for a key that is NOT in the authoritative set must not conjure a signal.
    @Test("an origin without a matching key fires nothing")
    func orphanOriginFiresNothing() {
        let suggestions = [Self.suggestion()]
        let result = TemplateRegistry.applyCrossValidation(
            to: suggestions,
            matching: [],
            origins: [suggestions[0].crossValidationKey: Self.origin()]
        )
        #expect(result[0].score.total == suggestions[0].score.total)
    }

    /// The named origin reaches the rendered explainability, not just the signal — the
    /// `whySuggested` block is what a reader actually sees.
    @Test("the corroborator's name reaches the whySuggested block")
    func nameReachesExplainability() {
        let subject = Self.suggestion()
        let result = TemplateRegistry.applyCrossValidation(
            to: [subject],
            matching: [subject.crossValidationKey],
            origins: [subject.crossValidationKey: Self.origin()]
        )
        let why = result[0].explainability.whySuggested.joined(separator: " ")
        #expect(why.contains("commutativityHolds"))
    }

    // MARK: - Fixture
    //
    // Built through a real template rather than by hand: `Suggestion` carries fields whose
    // loss is a recorded bug in this very file's subject (`rebuildWithCrossValidation`'s
    // "mutate a copy; never rebuild field-by-field"), so a hand-rolled literal would drift
    // from the shape production actually produces.

    private static func suggestion() -> Suggestion {
        let summary = FunctionSummary(
            name: "normalize",
            parameters: [
                Parameter(label: nil, internalName: "x", typeText: "String", isInout: false)
            ],
            returnTypeText: "String",
            isThrows: false, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "T.swift", line: 1, column: 1),
            containingTypeName: "Engine",
            bodySignals: .empty
        )
        guard let suggestion = IdempotenceTemplate.suggest(for: summary) else {
            fatalError("IdempotenceTemplate must produce a suggestion for String -> String")
        }
        return suggestion
    }
}
