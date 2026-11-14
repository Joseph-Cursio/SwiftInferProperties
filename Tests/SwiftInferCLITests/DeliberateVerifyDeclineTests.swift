import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

/// The laws `accept` writes and `verify` declines on purpose get their reason on every channel a
/// reader sees (#701), instead of `unsupported-template`'s *"a gap in swift-infer"*.
///
/// Three channels, one sentence: the verify error, the survey row's detail (classified by
/// `report` as `UnverifiableCause.declinedByDesign`), and `accept-check`'s detail. Every arm here
/// drives the real gate (`buildStubBundle`) or the real mapper — a decline that only the switch
/// knew about would reach no reader.
///
/// **The deferral rides its own channel** (`VerifyError.deferredComposer`, cause
/// `UnverifiableCause.deferredComposer`): on the decline channel it printed *"deferred, not
/// declined"* inside *"by design … not a missing composer"*, and every reader downstream filed a
/// planned composer as a permanent refusal.
@Suite("Verify declines by design, and says why")
struct DeliberateVerifyDeclineTests {

    /// The two #701 templates verify refuses to measure, by decision.
    private static let declined = ["sorted-output", "marker-dispatch"]

    /// The #701 template verify does not measure YET: a composer is planned.
    private static let deferred = ["input-order-independence"]

    /// Every recorded decision, decline or deferral.
    private static let recorded = declined + deferred

    /// #701's other three: they get composers, so a decline here would pre-empt them.
    private static let composerBound = ["empty-range", "emptiness-agreement", "documented-range"]

    private static func entry(template: String) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0x701A",
            templateName: template,
            score: 40,
            tier: "likely",
            primaryFunctionName: "ranked(_:)",
            location: "/tmp/Subject.swift:1",
            firstSeenAt: "2026-11-13T00:00:00Z",
            lastSeenAt: "2026-11-13T00:00:00Z",
            typeName: "Report",
            carrierTypeName: "Report"
        )
    }

    // MARK: - The switch

    @Test("exactly the three #701 decisions carry a reason, and say which kind they are")
    func reasonsForExactlyTheThree() {
        for template in Self.recorded {
            let reason = DeliberateVerifyDecline.reason(forTemplate: template)
            #expect(reason?.isEmpty == false, "\(template) lost its recorded reason")
        }
        for template in Self.declined {
            #expect(DeliberateVerifyDecline.disposition(forTemplate: template) == .declined)
        }
        for template in Self.deferred {
            #expect(DeliberateVerifyDecline.disposition(forTemplate: template) == .deferred)
        }
        for template in Self.composerBound + ["round-trip", "some-future-template"] {
            #expect(DeliberateVerifyDecline.reason(forTemplate: template) == nil, "\(template)")
            #expect(DeliberateVerifyDecline.disposition(forTemplate: template) == nil)
        }
    }

    /// The load-bearing direction. A decline on a template that HAS a composer would tell a
    /// reader to stop waiting for a verdict verify can give — and the gate consults this only
    /// after `verifiable` refuses, so such a decline would also be dead code nobody notices.
    @Test("no decline shadows a verifiable template, or any TemplateName case")
    func noDeclineShadowsAVerifiableTemplate() {
        for template in TemplateName.verifiable.rawValues {
            #expect(DeliberateVerifyDecline.reason(forTemplate: template) == nil, "\(template)")
            #expect(DeliberateVerifyDecline.disposition(forTemplate: template) == nil)
        }
        // Wider than `verifiable`: a declined template needs no case, so one with a case is a
        // template someone meant to make verifiable.
        for template in TemplateName.allCases.map(\.rawValue) {
            #expect(DeliberateVerifyDecline.reason(forTemplate: template) == nil, "\(template)")
            #expect(DeliberateVerifyDecline.disposition(forTemplate: template) == nil)
        }
    }

    @Test("the two characterisation laws say so; the deferral names its falsifier")
    func reasonsStateTheirClass() throws {
        for template in ["sorted-output", "marker-dispatch"] {
            let reason = try #require(DeliberateVerifyDecline.reason(forTemplate: template))
            #expect(reason.contains("characterisation law"))
            #expect(reason.contains("by construction"))
            #expect(reason.contains("checked-in stub"))
        }
        let deferral = try #require(
            DeliberateVerifyDecline.reason(forTemplate: "input-order-independence")
        )
        #expect(deferral.contains("composeInputOrderIndependencePass"))
        // The wrapper says "deferred"; the reason must not argue with the wrapper it sits in.
        #expect(!deferral.contains("declined"))
        #expect(!deferral.contains("by design"))
        #expect(!deferral.contains("characterisation"), "it is a conjecture, refutable today")
    }

    // MARK: - The gate

    @Test("buildStubBundle throws declinedByDesign, not unsupportedTemplate", arguments: declined)
    func gateThrowsDeclinedByDesign(template: String) {
        do {
            _ = try SwiftInferCommand.Verify.buildStubBundle(
                entry: Self.entry(template: template),
                budget: .small
            )
            Issue.record("\(template) composed a stub; it must decline")
        } catch let VerifyError.declinedByDesign(thrownTemplate, reason) {
            #expect(thrownTemplate == template)
            #expect(reason == DeliberateVerifyDecline.reason(forTemplate: template))
        } catch {
            Issue.record("\(template) threw \(error), expected .declinedByDesign")
        }
    }

    @Test("buildStubBundle throws deferredComposer for the deferral", arguments: deferred)
    func gateThrowsDeferredComposer(template: String) {
        do {
            _ = try SwiftInferCommand.Verify.buildStubBundle(
                entry: Self.entry(template: template),
                budget: .small
            )
            Issue.record("\(template) composed a stub; it must defer")
        } catch let VerifyError.deferredComposer(thrownTemplate, reason) {
            #expect(thrownTemplate == template)
            #expect(reason == DeliberateVerifyDecline.reason(forTemplate: template))
        } catch {
            Issue.record("\(template) threw \(error), expected .deferredComposer")
        }
    }

    /// The control: an undecided template keeps the composer-gap cause, so the named decline has
    /// not become the default.
    @Test("an undecided template still reports unsupported-template")
    func undecidedTemplateKeepsTheGap() {
        #expect(throws: VerifyError.self) {
            _ = try SwiftInferCommand.Verify.buildStubBundle(
                entry: Self.entry(template: "some-future-template"),
                budget: .small
            )
        }
        let detail = Self.surveyDetail(template: "some-future-template")
        #expect(detail?.hasPrefix("unsupported-template: some-future-template") == true)
    }

    // MARK: - The channels

    @Test("the survey detail carries the prefix and the reason, and classifies", arguments: declined)
    func surveyDetailRoundTrips(template: String) throws {
        let detail = try #require(Self.surveyDetail(template: template))
        #expect(detail.hasPrefix("declined-by-design: \(template)"))
        let reason = try #require(DeliberateVerifyDecline.reason(forTemplate: template))
        #expect(detail.contains(reason))
        #expect(UnverifiableCause.classify(detail: detail) == .declinedByDesign)
    }

    @Test("the deferral's survey detail classifies as a deferred composer", arguments: deferred)
    func deferralSurveyDetailRoundTrips(template: String) throws {
        let detail = try #require(Self.surveyDetail(template: template))
        #expect(detail.hasPrefix("deferred-composer: \(template)"))
        let reason = try #require(DeliberateVerifyDecline.reason(forTemplate: template))
        #expect(detail.contains(reason))
        #expect(UnverifiableCause.classify(detail: detail) == .deferredComposer)
    }

    @Test("the verify error names the reason and says it is a decision")
    func errorDescriptionCarriesTheReason() throws {
        let reason = try #require(DeliberateVerifyDecline.reason(forTemplate: "sorted-output"))
        let text = VerifyError.declinedByDesign(template: "sorted-output", reason: reason)
            .description
        #expect(text.contains(reason))
        #expect(text.contains("by design"))
        #expect(text.contains("not a missing composer"))
        #expect(!text.contains("has no verify composer"))
    }

    /// The defect this channel closes: the deferral's description is read in one breath, and it
    /// said "deferred, not declined" inside "by design … not a missing composer".
    @Test("the deferral's verify error says a composer is planned, not that it is refused")
    func deferralDescriptionDoesNotContradictItself() throws {
        let reason = try #require(
            DeliberateVerifyDecline.reason(forTemplate: "input-order-independence")
        )
        let text = VerifyError.deferredComposer(template: "input-order-independence", reason: reason)
            .description
        #expect(text.contains(reason))
        #expect(!text.contains("by design"))
        #expect(!text.contains("not a missing composer"))
        #expect(text.contains("planned"))
        #expect(text.contains("checked-in stub runs the law"))
    }

    @Test("the cause's remedy points at the row's reason and prescribes no generator")
    func causeRemedyIsHonest() {
        let cause = UnverifiableCause.declinedByDesign
        #expect(cause.remedy.contains("reason recorded"))
        #expect(cause.remedy.contains("checked-in stub"))
        #expect(!cause.remedy.contains("gen()"))
        #expect(!cause.remedy.contains("a gap in swift-infer"))
    }

    /// `accept-check` re-verifies every accepted law; a law `accept` wrote must not read as a
    /// tool failure each time. Driven through `checkOne` against an on-disk index — the decline
    /// throws before any workdir is synthesized, so this stays in-process.
    @Test(
        "accept-check reports the reason, not 'unsupported template'",
        arguments: [
            ("marker-dispatch", "not measured by verify, by design: "),
            ("input-order-independence", "verify composer planned, not built yet: "),
        ]
    )
    func acceptCheckShowsTheReason(template: String, expectedPrefix: String) throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeliberateVerifyDeclineTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: base.appendingPathComponent("Package.swift"))
        let indexPath = base.appendingPathComponent("index.json")
        try IndexStore.save(
            IndexStore.Index(
                updatedAt: "2026-11-13T00:00:00Z",
                entries: [Self.entry(template: template)]
            ),
            to: indexPath
        )
        let record = DecisionRecord(
            identityHash: "0x701A",
            template: template,
            scoreAtDecision: 40,
            tier: .likely,
            decision: .accepted,
            timestamp: Date(timeIntervalSince1970: 1_794_528_000)
        )

        let result = SwiftInferCommand.AcceptCheck.checkOne(
            record: record,
            budgetString: "small",
            indexPathOverride: indexPath.path,
            workingDirectory: base
        )

        #expect(result.kind == .error)
        let detail = try #require(result.detail)
        #expect(detail.hasPrefix(expectedPrefix), "got: \(detail)")
        #expect(!detail.contains("unsupported template"))
    }

    // MARK: - Helpers

    private static func surveyDetail(template: String) -> String? {
        do {
            _ = try SwiftInferCommand.Verify.buildStubBundle(
                entry: entry(template: template),
                budget: .small
            )
            return nil
        } catch let error as VerifyError {
            return SwiftInferCommand.Verify.detail(for: error)
        } catch {
            return nil
        }
    }
}
