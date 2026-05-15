import Foundation
import Testing
@testable import SwiftInferCore

// V2.0 M10 — InteractionDriftDetector + InteractionDriftWarning +
// InteractionBaseline. Pure: no I/O. All inputs are synthetic
// `InteractionInvariantSuggestion`s because production families ship
// at default-`.possible` until calibration promotes them.

@Suite("InteractionDrift — V2.0 M10 drift detection")
struct InteractionDriftTests {

    private let now = ISO8601DateFormatter().date(from: "2026-05-15T12:00:00Z")!

    private func suggestion(
        family: InteractionInvariantFamily = .cardinality,
        reducerQualifiedName: String = "Inbox.body",
        predicate: String = "p1",
        tier: Tier = .strong
    ) -> InteractionInvariantSuggestion {
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: family,
            reducerQualifiedName: reducerQualifiedName,
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: family,
            reducerQualifiedName: reducerQualifiedName,
            reducerLocation: "Sources/MyApp/Inbox.swift:42",
            stateTypeName: "Inbox.State",
            actionTypeName: "Inbox.Action",
            predicate: predicate,
            score: 80,
            tier: tier,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: now
        )
    }

    private func baselineEntry(
        from suggestion: InteractionInvariantSuggestion
    ) -> InteractionBaselineEntry {
        InteractionBaselineEntry(
            identityHash: suggestion.identity.normalized,
            family: suggestion.family,
            scoreAtSnapshot: suggestion.score,
            tier: suggestion.tier,
            reducerQualifiedName: suggestion.reducerQualifiedName
        )
    }

    // MARK: - Tier filtering

    @Test("Strong-tier suggestions not in baseline warn")
    func strongNotInBaselineWarns() {
        let target = suggestion()
        let warnings = InteractionDriftDetector.warnings(
            currentSuggestions: [target],
            baseline: .empty
        )
        #expect(warnings.count == 1)
        #expect(warnings[0].identityHash == target.identity.normalized)
    }

    @Test("Likely-tier and Possible-tier additions stay silent")
    func subStrongStaysSilent() {
        let likely = suggestion(predicate: "p-likely", tier: .likely)
        let possible = suggestion(predicate: "p-possible", tier: .possible)
        let warnings = InteractionDriftDetector.warnings(
            currentSuggestions: [likely, possible],
            baseline: .empty
        )
        #expect(warnings.isEmpty)
    }

    @Test("Suppressed suggestions never warn")
    func suppressedNeverWarns() {
        let target = suggestion(tier: .suppressed)
        let warnings = InteractionDriftDetector.warnings(
            currentSuggestions: [target],
            baseline: .empty
        )
        #expect(warnings.isEmpty)
    }

    @Test("Verified tier (Strong+) also warns when new")
    func verifiedAlsoWarns() {
        let target = suggestion(tier: .verified)
        let warnings = InteractionDriftDetector.warnings(
            currentSuggestions: [target],
            baseline: .empty
        )
        #expect(warnings.count == 1)
    }

    // MARK: - Baseline membership

    @Test("Strong-tier suggestion present in baseline stays silent")
    func baselineMembershipSuppresses() {
        let target = suggestion()
        let baseline = InteractionBaseline(entries: [baselineEntry(from: target)])
        let warnings = InteractionDriftDetector.warnings(
            currentSuggestions: [target],
            baseline: baseline
        )
        #expect(warnings.isEmpty)
    }

    @Test("mixed input: only new Strong-tier members warn")
    func mixedInputProducesPartialWarnings() {
        let known = suggestion(predicate: "p-known")
        let novel = suggestion(predicate: "p-novel")
        let baseline = InteractionBaseline(entries: [baselineEntry(from: known)])
        let warnings = InteractionDriftDetector.warnings(
            currentSuggestions: [known, novel],
            baseline: baseline
        )
        #expect(warnings.count == 1)
        #expect(warnings[0].predicate == "p-novel")
    }

    // MARK: - Order preservation

    @Test("warnings preserve input order — byte-stable stream against unchanged corpus")
    func warningsPreserveOrder() {
        let suggestions = [
            suggestion(family: .conservation, predicate: "p-cons"),
            suggestion(family: .cardinality, predicate: "p-card"),
            suggestion(family: .biconditional, predicate: "p-bi")
        ]
        let warnings = InteractionDriftDetector.warnings(
            currentSuggestions: suggestions,
            baseline: .empty
        )
        let inputFamilies = suggestions.map(\.family)
        let outputFamilies = warnings.map(\.family)
        #expect(outputFamilies == inputFamilies)
    }

    // MARK: - Rendered-line shape

    @Test("renderedLine carries family, identity, reducer, location, and predicate")
    func renderedLineShape() {
        let target = suggestion(
            family: .biconditional,
            predicate: "state.isLoading == (state.activeTask != nil)"
        )
        let warning = InteractionDriftWarning(suggestion: target)
        let line = warning.renderedLine()
        #expect(line.hasPrefix("warning: drift:"))
        #expect(line.contains("Strong biconditional invariant"))
        #expect(line.contains("0x\(target.identity.normalized)"))
        #expect(line.contains("Inbox.body"))
        #expect(line.contains("Sources/MyApp/Inbox.swift:42"))
        #expect(line.contains("state.isLoading == (state.activeTask != nil)"))
    }
}

// V2.0 M10 — baseline data-model coverage. Extension-grouped to
// keep the main suite under SwiftLint's type_body_length cap.
extension InteractionDriftTests {

    @Test("empty baseline has no entries")
    func emptyBaselineHasNoEntries() {
        #expect(InteractionBaseline.empty.entries.isEmpty)
    }

    @Test("contains(identityHash:) checks entry membership")
    func containsChecksMembership() {
        let target = suggestion()
        let baseline = InteractionBaseline(entries: [baselineEntry(from: target)])
        #expect(baseline.contains(identityHash: target.identity.normalized))
        #expect(!baseline.contains(identityHash: "0000000000000000"))
    }

    @Test("entry(for:) looks up by identity hash")
    func entryLookupByHash() {
        let target = suggestion()
        let entry = baselineEntry(from: target)
        let baseline = InteractionBaseline(entries: [entry])
        #expect(baseline.entry(for: target.identity.normalized) == entry)
        #expect(baseline.entry(for: "deadbeefdeadbeef") == nil)
    }

    @Test("InteractionBaseline round-trips through JSON")
    func baselineRoundTripJSON() throws {
        let target = suggestion()
        let original = InteractionBaseline(entries: [baselineEntry(from: target)])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InteractionBaseline.self, from: data)
        #expect(decoded == original)
    }

    @Test("schema version is bumped to 1 by default")
    func defaultSchemaVersion() {
        #expect(InteractionBaseline.empty.schemaVersion == 1)
        #expect(InteractionBaseline.currentSchemaVersion == 1)
    }
}
