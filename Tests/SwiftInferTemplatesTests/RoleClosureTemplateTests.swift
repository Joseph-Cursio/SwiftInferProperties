import SwiftInferCore
import SwiftInferTemplates
import Testing

/// `f(f(x)) == f(x)`, claimed from a role whose postcondition is closed under reapplication.
///
/// The walk's T4 — idempotence of `NSRange.clamped(to:)` — is the row this closes. It was
/// unreachable by `IdempotenceTemplate` because that template reads a unary `(T) -> T` off the
/// signature, and `clamped(to:)` holds a bound fixed.
@Suite("Role closure — reapplying a closed guarantee changes nothing")
struct RoleClosureTemplateTests {

    private static func summary(
        _ name: String,
        parameters: [(String?, String)] = [],
        returns: String?,
        containingType: String? = nil,
        isStatic: Bool = false,
        isMutating: Bool = false,
        isAsync: Bool = false,
        isThrows: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: parameters.enumerated().map { index, pair in
                Parameter(
                    label: pair.0,
                    internalName: "arg\(index)",
                    typeText: pair.1,
                    isInout: false
                )
            },
            returnTypeText: returns,
            isThrows: isThrows,
            isAsync: isAsync,
            isMutating: isMutating,
            isStatic: isStatic,
            location: SourceLocation(file: "F.swift", line: 1, column: 1),
            containingTypeName: containingType,
            bodySignals: .empty,
            docComment: nil
        )
    }

    // MARK: - The measured case

    /// T4 from `roadtest-swiftmarkdownwiki.md`, reduced to its declaration.
    @Test func clampedOnItsOwnTypeIsProposed() throws {
        let suggestion = try #require(RoleClosureTemplate.suggest(
            for: Self.summary("clamped", parameters: [("to", "Int")], returns: "NSRange", containingType: "NSRange")
        ))
        #expect(suggestion.templateName == "role-closure")
    }

    @Test func aNullaryReceiverRoleIsProposed() {
        let suggestion = RoleClosureTemplate.suggest(
            for: Self.summary("lowercased", returns: "String", containingType: "String")
        )
        #expect(suggestion != nil)
    }

    // MARK: - Closure is a second fact, and this is the row that proves it

    /// **The sharpest negative in the suite.** `escaped` satisfies its postcondition on every
    /// pass and changes the value every time — `\` to `\\` to `\\\\`. A template deriving
    /// closure from the postcondition would state a false law about correct code here, which is
    /// this project's worst failure mode.
    @Test func escapedIsNotClosedAndIsRefused() {
        #expect(RoleClosureTemplate.suggest(
            for: Self.summary("escaped", returns: "String", containingType: "String")
        ) == nil)
        #expect(RolePostcondition.escaped.isClosedUnderReapplication == false)
        #expect(RolePostcondition.unescaped.isClosedUnderReapplication == false)
    }

    /// Reversing twice is the identity, not a fixpoint — a different law, and `InvolutionTemplate`
    /// states it. A shuffle is not deterministic at all.
    @Test func involutionsAndNondeterminismAreNotClosure() {
        #expect(RolePostcondition.reversed.isClosedUnderReapplication == false)
        #expect(RolePostcondition.shuffled.isClosedUnderReapplication == false)
        #expect(RoleClosureTemplate.suggest(
            for: Self.summary("reversed", returns: "[Int]", containingType: "[Int]")
        ) == nil)
    }

    /// Pins the judgement per role rather than by count, so adding a role forces a decision
    /// about it instead of inheriting one.
    @Test("each role's closure is a stated judgement", arguments: [
        (RolePostcondition.sorted, true), (.clamped, true), (.rounded, true),
        (.lowercased, true), (.uppercased, true), (.deduplicated, true),
        (.escaped, false), (.unescaped, false), (.reversed, false), (.shuffled, false)
    ])
    func closureIsStatedPerRole(role: RolePostcondition, closed: Bool) {
        #expect(role.isClosedUnderReapplication == closed)
    }

    // MARK: - Not a duplicate of idempotence

    /// Where `IdempotenceTemplate` already fires, a second suggestion is one law twice. Measured
    /// at 1 site of 25 across 20 corpora, so the veto is cheap — but without it that one site
    /// produces a duplicate indistinguishable from coverage.
    @Test func aSiteIdempotenceAlreadyReachesIsLeftToIt() {
        #expect(RoleClosureTemplate.suggest(
            for: Self.summary("sorted", parameters: [(nil, "[Int]")], returns: "[Int]")
        ) == nil)
    }

    /// The same name one parameter wider is *not* reached by idempotence, so it is this
    /// template's to state. The contrast with the test above is the whole boundary.
    @Test func theSameRoleWithAHeldArgumentIsProposed() {
        #expect(RoleClosureTemplate.suggest(
            for: Self.summary(
                "sorted",
                parameters: [("by", "(Int, Int) -> Bool")],
                returns: "[Int]",
                containingType: "[Int]"
            )
        ) != nil)
    }

    // MARK: - Shape gates

    /// `f(f(x))` must type-check. A `sorted` returning something else is another operation
    /// wearing the name.
    @Test func aResultThatDoesNotComposeIsRefused() {
        #expect(RoleClosureTemplate.suggest(
            for: Self.summary("sorted", parameters: [(nil, "[Int]")], returns: "Report")
        ) == nil)
    }

    @Test("effects and in-place mutation are excluded", arguments: [
        ("async", true, false, false), ("throws", false, true, false), ("mutating", false, false, true)
    ])
    func effectfulDeclarationsAreRefused(label: String, isAsync: Bool, isThrows: Bool, isMutating: Bool) {
        #expect(RoleClosureTemplate.suggest(
            for: Self.summary(
                "clamped", parameters: [("to", "Int")], returns: "NSRange",
                containingType: "NSRange", isMutating: isMutating, isAsync: isAsync, isThrows: isThrows
            )
        ) == nil, "\(label) should not carry this law")
    }

    /// A parameterised match is not the role — `trimmed(matching:)` trims trivia a caller picks.
    /// Inherited from `RolePostcondition.matches`, pinned here because this template's whole
    /// premise is that the name means what it usually means.
    @Test func anUnpermittedLabelIsNotTheRole() {
        #expect(RoleClosureTemplate.suggest(
            for: Self.summary(
                "clamped",
                parameters: [("matching", "Filter")],
                returns: "NSRange",
                containingType: "NSRange"
            )
        ) == nil)
    }

    // MARK: - What the reader is told

    @Test func theHeldArgumentIsCalledOut() throws {
        let suggestion = try #require(RoleClosureTemplate.suggest(
            for: Self.summary("clamped", parameters: [("to", "Int")], returns: "NSRange", containingType: "NSRange")
        ))
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: " ")
        #expect(caveats.contains("SAME IN BOTH CALLS"))
    }

    /// The claim is stronger than signature-shaped idempotence and it is still not entailment.
    /// A caveat that overstated it would be worse than none.
    @Test func theClaimIsNotPresentedAsEntailment() throws {
        let suggestion = try #require(RoleClosureTemplate.suggest(
            for: Self.summary("lowercased", returns: "String", containingType: "String")
        ))
        let caveats = suggestion.explainability.whyMightBeWrong.joined(separator: " ")
        #expect(caveats.contains("NOT entailment"))
        #expect(Refutability.isRoleEntailed(suggestion) == false)
    }
}
