import Foundation
import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// **Codegen for the laws the kit covers and nothing wrote.**
///
/// Measured end to end on `SwiftInferCore` (2026-08-02): 84 carriers / 304 laws emitted live,
/// 74 carriers / 258 commented out pending a hand-written `gen()`. The emitted file compiled
/// with **zero errors** and its 126 tests ran **126/126 green** — after two defects that only
/// running it could reveal, both pinned below.
@Suite("Kit-suite emitter")
struct KitSuiteEmitterTests {

    private func finding(
        _ typeName: String,
        conformances: [String],
        laws: Set<KnownProperty> = [.equatableReflexive]
    ) -> ProtocolCoverageAudit.Finding {
        ProtocolCoverageAudit.Finding(
            typeName: typeName,
            coveringConformance: conformances.min() ?? "",
            standing: .assumed,
            coveredLaws: laws,
            declaredCoveringConformances: conformances.sorted()
        )
    }

    private func shape(
        _ name: String,
        kind: TypeShape.Kind = .enum,
        inherited: [String] = ["CaseIterable"]
    ) -> TypeShape {
        TypeShape(
            name: name, kind: kind, inheritedTypes: inherited,
            hasUserGen: false, storedMembers: []
        )
    }

    // MARK: - Subsumption

    /// **`Hashable`'s law set already contains `Equatable`'s.** `ProtocolCoverageMap` bakes
    /// transitive coverage in, so emitting both would run reflexivity / symmetry /
    /// transitivity twice and read as two findings where there is one.
    @Test("a conformance subsumed by another is not emitted")
    func subsumedConformanceDropped() {
        let suites = KitSuiteEmitter.suiteConformances(
            for: finding("Money", conformances: ["Equatable", "Hashable"])
        )
        #expect(suites == ["Hashable"])
    }

    /// …but two conformances that merely overlap both survive. `Comparable` and `Hashable`
    /// each add a law the other lacks, so neither is a subset.
    @Test("overlapping-but-incomparable conformances both emit")
    func incomparableConformancesBothEmit() {
        let suites = KitSuiteEmitter.suiteConformances(
            for: finding("Tier", conformances: ["Comparable", "Hashable"])
        )
        #expect(suites == ["Comparable", "Hashable"])
    }

    @Test("a conformance the kit has no laws for is skipped")
    func emptyCoverageSkipped() {
        // `Semigroup` maps to an empty set — a documented placeholder.
        #expect(KitSuiteEmitter.suiteConformances(
            for: finding("Thing", conformances: ["Semigroup"])
        ).isEmpty)
    }

    // MARK: - The two defects that only running the output could find

    /// **Defect 1 — the assertion was stricter than the kit.** The first emitted file used
    /// `#expect(results.allSatisfy { $0.outcome == .passed })`, which fails on advisory
    /// findings the kit deliberately does not escalate: `EnforcementMode.default` throws on
    /// Strict only. Measured — 2 of 126 tests failed on `Hashable.distribution` at Heuristic.
    @Test("the emitted assertion escalates on Strict only")
    func assertionIsTierAware() {
        let emission = KitSuiteEmitter.emit(
            findings: [finding("Money", conformances: ["Equatable"])],
            shapes: ["Money": shape("Money")],
            moduleName: "M"
        )
        #expect(emission.source.contains("$0.tier != .strict || $0.outcome == .passed"))
        #expect(!emission.source.contains("results.allSatisfy { $0.outcome == .passed }"))
    }

    /// **Defect 2 — a CaseIterable domain cannot satisfy `Hashable.distribution`.** 1000
    /// trials over 25 cases produce 25 unique hashes; the law is degenerate by construction
    /// and no generator fixes it. The kit records a swift-testing Issue even at Heuristic, so
    /// a tier-aware assertion alone was not enough.
    @Test("a CaseIterable Hashable carrier skips the distribution law")
    func caseIterableSkipsDistribution() {
        let emission = KitSuiteEmitter.emit(
            findings: [finding("Tier", conformances: ["Hashable"])],
            shapes: ["Tier": shape("Tier", inherited: ["CaseIterable", "Hashable"])],
            moduleName: "M"
        )
        #expect(emission.source.contains(#"lawName: "distribution""#))
    }

    /// **Scoped, not blanket.** On a wide domain a bad `hash(into:)` shows up as clustering,
    /// so suppressing `distribution` everywhere trades real signal for a green run.
    @Test("a non-CaseIterable carrier keeps the distribution law")
    func memberwiseKeepsDistribution() {
        let money = TypeShape(
            name: "Money", kind: .struct, inheritedTypes: ["Hashable"], hasUserGen: false,
            storedMembers: [StoredMember(name: "amount", typeName: "Int")]
        )
        let emission = KitSuiteEmitter.emit(
            findings: [finding("Money", conformances: ["Hashable"])],
            shapes: ["Money": money],
            moduleName: "M"
        )
        #expect(emission.liveCarriers == 1, "memberwise Int derives")
        #expect(!emission.source.contains(#"lawName: "distribution""#))
    }

    // MARK: - Blocked carriers are shown, not dropped

    /// A carrier whose generator cannot be derived is emitted **commented out**, carrying the
    /// kit's own reason. Emitting it live would produce a file that does not compile;
    /// dropping it silently would report half the work as all of it.
    @Test("an underivable carrier is commented out with its reason")
    func blockedCarrierIsShown() {
        let opaque = TypeShape(
            name: "Opaque", kind: .struct, inheritedTypes: ["Equatable"], hasUserGen: false,
            storedMembers: [StoredMember(name: "inner", typeName: "SomeUnknownType")]
        )
        let emission = KitSuiteEmitter.emit(
            findings: [finding("Opaque", conformances: ["Equatable"])],
            shapes: ["Opaque": opaque],
            moduleName: "M"
        )
        #expect(emission.blockedCarriers == 1)
        #expect(emission.liveCarriers == 0)
        // The marker is cause-neutral as of 2026-08-13; the cause is the line below it. This
        // carrier is genuinely a generator gap, so that is asserted on the REASON rather than
        // on the marker — which is the distinction the old wording collapsed.
        #expect(emission.source.contains("BLOCKED."))
        #expect(emission.source.contains("gen()"))
        #expect(emission.source.contains("//     _ = try await checkEquatablePropertyLaws"))
        // The counts must appear in the header, so a reader cannot mistake the live half for
        // the whole — the "no silent caps" rule applied to generated output.
        #expect(emission.source.contains("commented out"))
    }

    // MARK: - Identifiers

    /// Nested types are the common case and a dot is not a legal identifier character.
    @Test("a nested carrier gets a legal function name")
    func nestedTypeNameIsLegal() {
        #expect(
            KitSuiteEmitter.functionName("VerifyHarness.LookupResult", "Equatable")
                == "verifyHarnessLookupResultEquatable"
        )
        #expect(KitSuiteEmitter.functionName("Money", "Hashable") == "moneyHashable")
    }

    /// The emitted file must name the module under test with `@testable`, since carriers are
    /// routinely `internal`.
    @Test("the emitted file testably imports the module under test")
    func testableImportIsEmitted() {
        let emission = KitSuiteEmitter.emit(
            findings: [finding("Money", conformances: ["Equatable"])],
            shapes: ["Money": shape("Money")],
            moduleName: "MyModule"
        )
        #expect(emission.source.contains("@testable import MyModule"))
        #expect(emission.source.contains("import SwiftInferKitEvidence"), "closes the loop")
        #expect(emission.source.contains("KitEvidenceRecorder.record"))
    }

    @Test("no carriers produces a file that still explains itself")
    func emptyInputStillExplains() {
        let emission = KitSuiteEmitter.emit(findings: [], shapes: [:], moduleName: "M")
        #expect(emission.liveCarriers == 0)
        #expect(emission.blockedCarriers == 0)
        #expect(emission.source.contains("REVIEW BEFORE USE"))
    }
}
