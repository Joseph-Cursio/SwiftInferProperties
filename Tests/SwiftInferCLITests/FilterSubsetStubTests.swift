import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// `filter-subset` suggestions are written, and the law they write can fail (#476, #468).
///
/// The corpus funnel census declined 13 of these with *"no stub writeout available"*, and #476
/// blocked the writer on a classification question — the stub's header says ENTAILED or CONJECTURE
/// depending on the answer, so the file could not be written until the answer was settled. It is:
/// the law is entailed, and `SubsetNameContractTests` holds the gate that keeps that true.
///
/// **The end-to-end evidence is not in this file**, because a unit test cannot compile what it
/// emits. Measured in a scratch package against the pinned kit: both stubs compile, both pass on
/// correct implementations, and both go red on a planted mutant — a filter returning a fallback row
/// when nothing survives, and one appending a sentinel. See
/// `docs/measurements/filter-subset-stub-writer.md`.
@Suite("Filter-subset — the accept path writes the subset law")
struct FilterSubsetStubTests {

    private static func summary(
        name: String = "filterViolations",
        parameters: [Parameter] = [
            Parameter(label: nil, internalName: "violations", typeText: "[Violation]", isInout: false),
            Parameter(label: "allowed", internalName: "allowed", typeText: "[Int]", isInout: false)
        ],
        returns: String = "[Violation]",
        owner: String? = "Analyzer",
        isStatic: Bool = true,
        globalActor: String? = nil
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returns,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: isStatic,
            location: SourceLocation(file: "Analyzer.swift", line: 8, column: 5),
            containingTypeName: owner,
            bodySignals: .empty,
            globalActor: globalActor
        )
    }

    private static func suggestion(_ summary: FunctionSummary) throws -> Suggestion {
        try #require(FilterSubsetTemplate.suggest(for: summary))
    }

    /// Resolves the project element type only — the array spelling answers `nil`, which is the
    /// whole reason the arm resolves at the element and wraps.
    private static func resolver(_ typeName: String) -> String? {
        typeName == "Violation" ? "Gen<Int>.int().map { Violation(line: $0) }" : nil
    }

    // MARK: - Written

    /// The census's own shape: a static filter over a project element, with a second collection
    /// argument that is not the haystack.
    @Test func aMultiArgumentFilterWritesTheSubsetLaw() throws {
        let suggestion = try Self.suggestion(Self.summary())
        let stub = try #require(
            InteractiveTriage.entailedTemplateStub(for: suggestion, customGenerator: Self.resolver(_:))
        )
        #expect(stub.contains("func filterViolations_returnsOnlyElementsItWasGiven()"))
        // The call is qualified and labelled, and the haystack is argument 0 — not argument 1,
        // which is also a collection.
        #expect(stub.contains("Analyzer.filterViolations(args.0, allowed: args.1)"))
        #expect(stub.contains("selected.allSatisfy { args.0.contains($0) }"))
        // Both collection arguments draw arrays, each resolved at its element.
        #expect(stub.contains("(Gen<Int>.int().map { Violation(line: $0) }).array(of: 0 ... 8)"))
        #expect(stub.contains("(Gen<Int>.int()).array(of: 0 ... 8)"))
    }

    /// **The law is spelled with `contains`, not `Set`.** `Set(result).isSubset(of:)` states the
    /// same thing and needs `Hashable`; this needs only `Equatable`, which strictly more element
    /// types have. The two cannot disagree, so the weaker constraint is the right one.
    @Test func theCheckNeedsEquatableRatherThanHashable() throws {
        let stub = try #require(
            InteractiveTriage.entailedTemplateStub(
                for: Self.suggestion(Self.summary()), customGenerator: Self.resolver(_:)
            )
        )
        #expect(stub.contains("Set(") == false, "a Hashable-only spelling would cost reach for nothing")
        #expect(stub.contains("allSatisfy"))
    }

    /// A single-argument free filter binds `value` rather than a tuple — the same shape the
    /// totality arm emits, so no stub grows a tuple it does not need.
    @Test func aSingleArgumentFreeFilterBindsOneValue() throws {
        let suggestion = try Self.suggestion(
            Self.summary(
                name: "keep",
                parameters: [Parameter(label: nil, internalName: "values", typeText: "[Int]", isInout: false)],
                returns: "[Int]",
                owner: nil,
                isStatic: false
            )
        )
        let stub = try #require(InteractiveTriage.entailedTemplateStub(for: suggestion, customGenerator: nil))
        #expect(stub.contains("let selected = keep(value)"))
        #expect(stub.contains("selected.allSatisfy { value.contains($0) }"))
    }

    /// **The empty draw is the point of `0 ...`.** A filter that substitutes a default when nothing
    /// survives is the most likely way this law fails, and it only shows up on an input that
    /// selects nothing — which a draw starting at 1 can still reach, but a draw over empty reaches
    /// directly.
    @Test func theDrawCanProduceAnEmptyCollection() throws {
        let stub = try #require(
            InteractiveTriage.entailedTemplateStub(
                for: Self.suggestion(Self.summary()), customGenerator: Self.resolver(_:)
            )
        )
        #expect(stub.contains(".array(of: 0 ... 8)"))
        #expect(stub.contains(".array(of: 1 ... 8)") == false)
    }

    /// An isolated filter — `filterTemplates` in the corpus is a method on a SwiftUI `View` — hops
    /// onto its actor. The hop takes a synchronous closure, which this body is.
    @Test func anIsolatedFilterHopsOntoItsActor() throws {
        let suggestion = try Self.suggestion(Self.summary(globalActor: "MainActor"))
        let stub = try #require(
            InteractiveTriage.entailedTemplateStub(for: suggestion, customGenerator: Self.resolver(_:))
        )
        #expect(stub.contains("await MainActor.run { let selected ="))
    }

    /// The header the whole of #476 was about. A reader who sees this go red has found something.
    @Test func theStubHeaderSaysEntailed() throws {
        let suggestion = try Self.suggestion(Self.summary())
        #expect(Refutability.isRoleEntailed(suggestion))
        #expect(InteractiveTriage.lawClassLine(for: suggestion).contains("ENTAILED"))
    }

    /// An unproven conformance is **said**, not assumed away. A project type reads `.unknown` here,
    /// because the accept context carries `TypeShape`s and `EquatableResolver`'s corpus arm has
    /// nothing to read — so the file names what to check if it will not build.
    @Test func anUnverifiedConformanceIsDeclaredInTheFile() throws {
        let stub = try #require(
            InteractiveTriage.entailedTemplateStub(
                for: Self.suggestion(Self.summary()), customGenerator: Self.resolver(_:)
            )
        )
        #expect(stub.contains("`Equatable` conformance is NOT verified"))
    }

    /// A curated-Equatable element says nothing, because there is nothing to warn about.
    @Test func aKnownEquatableElementCarriesNoWarning() throws {
        let suggestion = try Self.suggestion(
            Self.summary(
                name: "keep",
                parameters: [Parameter(label: nil, internalName: "values", typeText: "[String]", isInout: false)],
                returns: "[String]",
                owner: nil,
                isStatic: false
            )
        )
        let stub = try #require(InteractiveTriage.entailedTemplateStub(for: suggestion, customGenerator: nil))
        #expect(stub.contains("`Equatable` conformance is NOT verified") == false)
    }

    // MARK: - Declined, with a reason

    /// **Clear evidence only.** An existential element cannot host value equality, so `contains`
    /// cannot be spelled over it and the file would not compile for a reason the reader would have
    /// to work out. This is `EquatableResolver`'s curated-shape veto, which needs no corpus.
    @Test func anExistentialElementDeclinesWithAReason() {
        let reason = InteractiveTriage.filterSubsetDeclineReason(haystackType: "[any Rule]")
        #expect(reason?.contains("cannot host value equality") == true)
    }

    /// A project element is `.unknown`, not `.notEquatable` — the caveat-don't-drop posture
    /// `EquatableResolver`'s own header records. Declining here would cost every reachable row.
    @Test func aProjectElementIsNotDeclined() {
        #expect(InteractiveTriage.filterSubsetDeclineReason(haystackType: "[Violation]") == nil)
    }

    /// The haystack is found by the carrier the template recorded, and its index shifts past the
    /// receiver for an instance method. Picking the wrong argument would emit a law about the wrong
    /// collection — and it would pass, which is why a miss declines rather than guesses.
    @Test func theHaystackIndexShiftsPastAReceiver() {
        let types = ["Analyzer", "[URL]", "[Violation]"]
        #expect(
            InteractiveTriage.haystackArgumentIndex(
                of: "[Violation]", among: types, isInstanceMethod: true
            ) == 2
        )
        #expect(
            InteractiveTriage.haystackArgumentIndex(
                of: "[Missing]", among: types, isInstanceMethod: true
            ) == nil
        )
    }

    /// A receiver whose type happens to match the carrier is not the haystack: the haystack is a
    /// parameter, and the search starts past the receiver so it cannot be mistaken for one.
    @Test func theReceiverIsNeverMistakenForTheHaystack() {
        #expect(
            InteractiveTriage.haystackArgumentIndex(
                of: "[Violation]", among: ["[Violation]"], isInstanceMethod: true
            ) == nil
        )
    }
}
