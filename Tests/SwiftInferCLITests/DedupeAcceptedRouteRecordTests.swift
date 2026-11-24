import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// #711 — the decision record keeps the route the accepted row carried, so `accept-check` can
/// re-check the accepted count laws after an edit the gate refuses.
@Suite("Decisions — the accepted dedupe route")
struct DedupeAcceptedRouteRecordTests {

    @Test("an accepted gated dedupe records its route; a record without one decodes as before")
    func recordsRoute() throws {
        let source = """
        enum E {
            static func dedupe(_ xs: [Int]) -> [Int] {
                var seen = Set<Int>()
                return xs.filter { seen.insert($0).inserted }
            }
        }
        """
        let summary = try #require(FunctionScanner.scan(source: source, file: "E.swift").first)
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary))
        let record = InteractiveTriage.makeRecord(
            for: suggestion, decision: .accepted, timestamp: Date(timeIntervalSince1970: 0)
        )
        #expect(record.dedupeBody == DedupeBody(route: .set))
        let data = try JSONEncoder().encode(record)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "dedupeBody")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let old = try JSONDecoder().decode(DecisionRecord.self, from: stripped)
        #expect(old.dedupeBody == nil)
    }
}
