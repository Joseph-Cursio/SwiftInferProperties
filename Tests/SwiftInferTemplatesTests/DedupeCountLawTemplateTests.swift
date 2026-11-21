import Testing

@testable import SwiftInferCore
@testable import SwiftInferTemplates

/// #671's count laws reach the idempotence row of a recognised dedupe through the real scanner
/// (SwiftInferProperties#711): the body gate's route rides on `Suggestion.match`, "why suggested"
/// names it, and the caveat says what the laws cannot see. The row's score does not move.
@Suite("Idempotence — a gated dedupe carries #671's count laws")
struct DedupeCountLawTemplateTests {

    /// SwiftUMLBridge's `CoreDataModelExtractor.dedupe(relationships:)`, verbatim at `9ad7631`.
    static let swiftUMLBridge = """
    enum CoreDataModelExtractor {
        static func dedupe(relationships: [ERRelationship]) -> [ERRelationship] {
            var seen: Set<String> = []
            var result: [ERRelationship] = []
            for relationship in relationships {
                let endpoints = [relationship.from, relationship.toEntity].sorted()
                let labels = [relationship.label, relationship.inverseLabel ?? ""].sorted()
                let key = "\\(endpoints[0])|\\(endpoints[1])|\\(labels[0])|\\(labels[1])"
                if !seen.contains(key) {
                    seen.insert(key)
                    result.append(relationship)
                }
            }
            return result
        }
    }
    """

    static func idempotence(in source: String) throws -> Suggestion {
        let summary = try #require(FunctionScanner.scan(source: source, file: "Subject.swift").first)
        return try #require(IdempotenceTemplate.suggest(for: summary))
    }

    @Test("a Set-route dedupe carries the route, names it, and owns the wrong-key caveat")
    func setRoute() throws {
        let suggestion = try Self.idempotence(in: Self.swiftUMLBridge)
        #expect(suggestion.match == .dedupeCount(DedupeBody(route: .set)))
        let why = suggestion.explainability.whySuggested.joined(separator: "\n")
        #expect(why.contains("a `Set` local"))
        #expect(why.contains("C1") && why.contains("C2"))
        #expect(why.contains("stated as equality"))
        #expect(suggestion.explainability.whyMightBeWrong.contains(IdempotenceTemplate.dedupeCountCaveat))
    }

    @Test("a dictionary-route dedupe says C2 compares counts only")
    func dictionaryRoute() throws {
        let suggestion = try Self.idempotence(in: """
        enum ConstructionUniverse {
            static func deduplicated(_ members: [Member]) -> [Member] {
                var byKey: [String: Member] = [:]
                for member in members {
                    if let kept = byKey[member.key], kept.relativePath < member.relativePath { continue }
                    byKey[member.key] = member
                }
                return Array(byKey.values)
            }
        }
        """)
        #expect(suggestion.match == .dedupeCount(DedupeBody(route: .dictionary)))
        #expect(suggestion.explainability.whySuggested.contains { $0.contains("compares counts only") })
    }

    @Test("a recognised dedupe whose body the gate refuses keeps today's row: no match, no line, no caveat")
    func refusedBodyKeepsTodaysRow() throws {
        let suggestion = try Self.idempotence(in: """
        enum Extractor {
            static func dedupe(relationships: [Int]) -> [Int] {
                var seen = Set<Int>()
                var result: [Int] = []
                for x in relationships {
                    guard x > 0 else { continue }
                    if seen.insert(x).inserted { result.append(x) }
                }
                return result
            }
        }
        """)
        #expect(suggestion.match == nil)
        #expect(!suggestion.explainability.whySuggested.contains { $0.contains("C1") })
        #expect(!suggestion.explainability.whyMightBeWrong.contains(IdempotenceTemplate.dedupeCountCaveat))
    }

    @Test("the match does not move the score: the tier stays idempotence's")
    func scoreUnmoved() throws {
        let gated = try Self.idempotence(in: Self.swiftUMLBridge)
        let refused = try Self.idempotence(in: Self.swiftUMLBridge.replacingOccurrences(
            of: "return result", with: "result.append(contentsOf: [])\n        return result"
        ))
        #expect(refused.match == nil, "control: the extra statement refuses the body")
        #expect(gated.score.total == refused.score.total)
        #expect(gated.score.tier == refused.score.tier)
    }
}
