import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// **A restriction belongs to one declaration, not to every declaration that shares its name.**
///
/// `withAccessRestrictionCaveats` used to join scanned restrictions to suggestions on
/// `SymbolJoinKey` — `(file basename, bare symbol)` — resolving collisions with *first wins*.
/// That key was designed for the **seed-manifest** join, where a linter and the scanner spell
/// paths and labels differently, and `SymbolJoinKey`'s own doc calls the collision *"a known,
/// currently-empty hazard"*. The emptiness was measured across FILES, on seeds. It says nothing
/// about a collision WITHIN one file, and that is the one that fired.
///
/// **Measured on `MacPaw/OpenAI` @ `a532be8`, 2026-08-24.** `Components.swift` declares 72
/// `func encode(`. Exactly one is genuinely unreachable — it sits inside a `private struct
/// Storage`. All 72 shared the key `Components.swift::encode`, so that single nested `private`
/// type carried `.enclosingTypeNotVisibleToTests` onto **26 of the 28** `codable-round-trip`
/// suggestions in the file. `blocksEveryTest` marked each one `subjectNotVisibleToTests` and
/// `verify` filed them `not-a-candidate`: **laws suppressed by a true statement about a
/// different function.**
///
/// The old comment justified first-wins with *"two remedies for one key differ only in wording"*.
/// That is the premise that failed — the colliding remedies differed in **truth**, and picking
/// either was picking wrong for 71 of the 72.
///
/// **Why the negative case is the load-bearing one.** A join that is merely *narrower* would
/// also pass a test that only checks the restricted row still gets its caveat. What must hold is
/// that an unrestricted namesake gets **no** caveat, which is the assertion that fails on the
/// old code.
@Suite("Access caveats — the restriction join is per-declaration, not per-name")
struct AccessCaveatJoinCollisionTests {

    private static let file = "Components.swift"

    private static func summary(_ name: String, line: Int) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [],
            returnTypeText: "Void",
            isThrows: true,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: file, line: line, column: 1),
            containingTypeName: "Carrier",
            bodySignals: .empty
        )
    }

    private static func suggestion(line: Int, identity: String) -> Suggestion {
        Suggestion(
            templateName: "codable-round-trip",
            evidence: [
                Evidence(
                    displayName: "encode(to:)",
                    signature: "(Encoder) throws -> Void",
                    location: SourceLocation(file: file, line: line, column: 1)
                )
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: identity)
        )
    }

    private static func isSuppressed(_ suggestion: Suggestion) -> Bool {
        suggestion.score.signals.contains { $0.kind == .subjectNotVisibleToTests }
    }

    /// The shape that fired: one restricted `encode` at line 563, a namesake at 13718 that is
    /// fully public. Before the fix BOTH were suppressed.
    @Test("a namesake in the same file does not inherit the restriction")
    func namesakeIsNotSuppressed() {
        let restricted = RestrictedFunction(
            summary: Self.summary("encode", line: 563),
            restriction: .enclosingTypeNotVisibleToTests
        )
        let visible = Self.suggestion(line: 13_718, identity: "public-encode")

        let result = SwiftInferCommand.Discover.withAccessRestrictionCaveats(
            [visible],
            restrictedFunctions: [restricted]
        )

        #expect(result.count == 1)
        #expect(!Self.isSuppressed(result[0]))
        #expect(result[0].explainability.whyMightBeWrong.isEmpty)
    }

    /// The control. Narrowing the join must not stop the genuinely-restricted row from being
    /// caveated — a fix that suppresses nothing at all would also pass the test above.
    @Test("the declaration that IS restricted still gets its caveat")
    func restrictedDeclarationStillCaveated() {
        let restricted = RestrictedFunction(
            summary: Self.summary("encode", line: 563),
            restriction: .enclosingTypeNotVisibleToTests
        )
        let blocked = Self.suggestion(line: 563, identity: "private-encode")

        let result = SwiftInferCommand.Discover.withAccessRestrictionCaveats(
            [blocked],
            restrictedFunctions: [restricted]
        )

        #expect(Self.isSuppressed(result[0]))
        #expect(result[0].explainability.whyMightBeWrong.contains { $0.contains("enclosing type") })
    }

    /// Both at once, which is the corpus shape: 1 restricted, 3 namesakes, one caveat.
    @Test("one restricted declaration caveats one suggestion, not every namesake")
    func onlyTheRestrictedRowIsCaveated() {
        let restricted = RestrictedFunction(
            summary: Self.summary("encode", line: 563),
            restriction: .enclosingTypeNotVisibleToTests
        )
        let produced = [
            Self.suggestion(line: 518, identity: "a"),
            Self.suggestion(line: 563, identity: "b"),
            Self.suggestion(line: 13_718, identity: "c"),
            Self.suggestion(line: 15_051, identity: "d")
        ]

        let result = SwiftInferCommand.Discover.withAccessRestrictionCaveats(
            produced,
            restrictedFunctions: [restricted]
        )

        #expect(result.filter(Self.isSuppressed).count == 1)
        #expect(Self.isSuppressed(result[1]))
    }

    /// A lifted row locates at `<test-body>:0`, which names no coordinate to join on. The lossy
    /// key stays reachable for exactly that case — narrow fallback, not a general one.
    @Test("a row with no resolvable coordinate still joins by name")
    func unresolvableRowFallsBackToTheNameKey() {
        let restricted = RestrictedFunction(
            summary: Self.summary("encode", line: 563),
            restriction: .enclosingTypeNotVisibleToTests
        )
        var lifted = Self.suggestion(line: 0, identity: "lifted")
        lifted = Suggestion(
            templateName: lifted.templateName,
            evidence: [
                Evidence(
                    displayName: "encode(to:)",
                    signature: "(Encoder) throws -> Void",
                    location: SourceLocation(file: Self.file, line: 0, column: 0)
                )
            ],
            score: lifted.score,
            generator: lifted.generator,
            explainability: lifted.explainability,
            identity: lifted.identity
        )

        let result = SwiftInferCommand.Discover.withAccessRestrictionCaveats(
            [lifted],
            restrictedFunctions: [restricted]
        )

        #expect(Self.isSuppressed(result[0]))
    }
}
