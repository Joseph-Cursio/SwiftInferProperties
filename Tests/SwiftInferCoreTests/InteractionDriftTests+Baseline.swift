import Foundation
@testable import SwiftInferCore
import Testing

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
