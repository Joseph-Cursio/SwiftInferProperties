import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// `guard-domain` suggestions are written, and what cannot be written says which NAME defeated it
/// (#468, unblocked by #477).
///
/// **62 declined suggestions across 14 repositories, the largest writerless population of the
/// nine** — and the reason it stayed unwritten is that this law is source text the tool did not
/// write. The condition and the returned expression are spelled in the declaration's own scope;
/// a stub has different names for the same values. `GuardDomainRebinding` owns the rewrite.
///
/// **The end-to-end evidence is not in this file**, because a unit test cannot compile what it
/// emits. Measured in a scratch package on the pinned kit: four stubs compile; the guard's own
/// answer changing goes RED with the law stated; a sub-domain no draw reaches reports NOT APPLIED
/// rather than passing; and a redundant guard being dropped correctly does NOT fire. See
/// `docs/measurements/guard-domain-stub-writer.md`.
@Suite("Guard-domain — the accept path writes the characterisation law")
struct GuardDomainStubTests {

    private static func summary(
        _ name: String,
        parameters: [Parameter],
        returns: String?,
        owner: String? = "Parser",
        isStatic: Bool = true,
        domain: GuardDomain
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returns,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: isStatic,
            location: SourceLocation(file: "Parser.swift", line: 8, column: 5),
            containingTypeName: owner,
            bodySignals: BodySignals(
                guardDomain: domain,
                hasNonDeterministicCall: false,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: []
            )
        )
    }

    private static func param(_ label: String?, _ type: String, _ internalName: String) -> Parameter {
        Parameter(label: label, internalName: internalName, typeText: type, isInout: false)
    }

    private static func suggestion(_ summary: FunctionSummary) throws -> Suggestion {
        try #require(GuardDomainTemplate.suggest(for: summary))
    }

    /// The template's own documented example.
    private static func parseSuggestion() throws -> Suggestion {
        try suggestion(
            summary(
                "parse",
                parameters: [Self.param("from", "String", "source")],
                returns: "(FrontMatter, String)",
                domain: GuardDomain(
                    condition: "source.hasPrefix(\"---\")",
                    returnedExpression: "(FrontMatter(), source)",
                    parameterName: "source",
                    firesWhenConditionHolds: false
                )
            )
        )
    }

    // MARK: - Written

    /// **A `guard` fires its early return when the condition FAILS.** Getting that backwards states
    /// the law over the complement of the sub-domain it was read from — a different law, which
    /// would also pass, which is why it is asserted rather than eyeballed.
    @Test func aGuardStatesTheNegatedSubDomain() throws {
        let stub = try #require(
            InteractiveTriage.entailedTemplateStub(for: Self.parseSuggestion(), customGenerator: nil)
        )
        #expect(stub.contains("guard !(arg0.hasPrefix(\"---\")) else { return true }"))
        #expect(stub.contains("return Parser.parse(from: arg0) == (FrontMatter(), arg0)"))
    }

    /// An `if cond { return r }` fires when the condition HOLDS, so its predicate is not negated.
    @Test func anIfStatesTheConditionUnnegated() throws {
        let suggestion = try Self.suggestion(
            Self.summary(
                "clamped",
                parameters: [Self.param(nil, "Int", "value")],
                returns: "Int",
                domain: GuardDomain(
                    condition: "value < 0",
                    returnedExpression: "0",
                    parameterName: "value",
                    firesWhenConditionHolds: true
                )
            )
        )
        let stub = try #require(
            InteractiveTriage.entailedTemplateStub(for: suggestion, customGenerator: nil)
        )
        #expect(stub.contains("guard (arg0 < 0) else { return true }"))
        #expect(stub.contains("!(arg0 < 0)") == false, "an `if` must NOT be negated")
    }

    /// **The type a test must name comes from the subject's own signature.** `parse` returns
    /// `(FrontMatter(), source)` — the concrete type, not `Self` — and that is the template's
    /// documented example, so declining it would decline the case the template was built for.
    @Test func aTypeNamedInTheSignatureBindsToItself() throws {
        let stub = try #require(
            InteractiveTriage.entailedTemplateStub(for: Self.parseSuggestion(), customGenerator: nil)
        )
        #expect(stub.contains("FrontMatter()"))
        let reason = InteractiveTriage.guardDomainDeclineReason(for: try Self.parseSuggestion())
        #expect(reason == nil)
    }

    /// 57 of 156 measured sites mention `self`. It is the receiver, which for an instance method
    /// is the first argument the stub draws.
    @Test func selfBindsToTheDrawnReceiver() throws {
        let suggestion = try Self.suggestion(
            Self.summary(
                "merged",
                parameters: [Self.param("with", "Bag", "other")],
                returns: "Bag",
                owner: "Bag",
                isStatic: false,
                domain: GuardDomain(
                    condition: "self.items.isEmpty",
                    returnedExpression: "other",
                    parameterName: "other",
                    firesWhenConditionHolds: true
                )
            )
        )
        let stub = try #require(
            InteractiveTriage.entailedTemplateStub(for: suggestion, customGenerator: nil)
        )
        #expect(stub.contains("guard (arg0.items.isEmpty) else { return true }"))
        #expect(stub.contains("return arg0.merged(with: arg1) == arg1"))
    }

    // MARK: - The coverage guard

    /// **The law is CONDITIONAL, so it can pass while checking nothing.** One measured condition is
    /// `self === other`, which independent draws reach approximately never. The kit treats this as
    /// a first-class failure for the strict-weak-ordering suite; this arm does the same.
    @Test func theStubCountsWhetherTheSubDomainWasEverEntered() throws {
        let stub = try #require(
            InteractiveTriage.entailedTemplateStub(for: Self.parseSuggestion(), customGenerator: nil)
        )
        #expect(stub.contains("var entered = 0"))
        #expect(stub.contains("if entered == 0 {"))
        #expect(stub.contains("NOT APPLIED"))
        // Over the SAME seed words the check uses, so it counts the draws that will actually be made.
        #expect(stub.contains("Xoshiro(seed: ("))
    }

    /// The header the reader keeps. A pass here says nothing about today's behaviour, and a reader
    /// who took it for a correctness result would have been misled by the tool.
    @Test func theStubHeaderSaysCharacterisation() throws {
        let suggestion = try Self.parseSuggestion()
        #expect(Refutability.isCharacterisation(suggestion))
        #expect(Refutability.isRoleEntailed(suggestion), "characterisation is a SUBSET of entailed")
        let header = InteractiveTriage.lawClassLine(for: suggestion)
        #expect(header.contains("CHARACTERISATION"))
        #expect(header.contains("ENTAILED") == false, "the weaker, more precise line wins")
    }

    // MARK: - Declined, naming the name

    /// **The reader's own gate has a hole this closes.** `GuardDomainReader.mentionsOnly` counts a
    /// free identifier only when it starts with a LETTER, so `_fastPath(…)`, `_root` and `_count`
    /// pass through it as if they were not identifiers — which is why 27 of 156 measured sites
    /// carry a name no test can bind. The writer declines them rather than emitting a file that
    /// does not compile.
    @Test func anUnbindableNameDeclinesAndIsNamed() throws {
        let suggestion = try Self.suggestion(
            Self.summary(
                "fastCount",
                parameters: [Self.param(nil, "Int", "value")],
                returns: "Int",
                domain: GuardDomain(
                    condition: "_fastPath(value > 0)",
                    returnedExpression: "0",
                    parameterName: "value",
                    firesWhenConditionHolds: false
                )
            )
        )
        #expect(InteractiveTriage.entailedTemplateStub(for: suggestion, customGenerator: nil) == nil)
        let reason = try #require(InteractiveTriage.guardDomainDeclineReason(for: suggestion))
        #expect(reason.contains("`_fastPath`"), "a decline the reader cannot act on is no better than silence")
    }

    /// The decline reaches the sentence the CLI prints, rather than falling through to the generic
    /// "no stub writeout available for template …", which told 62 readers nothing about their code.
    @Test func theDeclineReachesTheDiagnostic() throws {
        let suggestion = try Self.suggestion(
            Self.summary(
                "rooted",
                parameters: [Self.param(nil, "Int", "value")],
                returns: "Int",
                domain: GuardDomain(
                    condition: "_root == value",
                    returnedExpression: "0",
                    parameterName: "value",
                    firesWhenConditionHolds: false
                )
            )
        )
        let reason = try #require(StubApplicationArity.declineReason(for: suggestion))
        #expect(reason.contains("`_root`"))
    }
}
