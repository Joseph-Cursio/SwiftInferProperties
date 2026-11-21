@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// #711, verify side: a dedupe's route reaches the index, and verify states idempotence the way the
/// accepted stub does. On the dictionary route that means without order, because a correct body
/// returns `Array(d.values)` in hash order and strict `==` refutes it.
@Suite("Verify — a dedupe's route and its idempotence oracle")
struct DedupeVerifyOracleTests {

    static let source = """
    public enum Dedupe {
        public static func deduplicated(_ xs: [Int]) -> [Int] {
            var byKey: [Int: Int] = [:]
            for x in xs {
                byKey[x % 7] = x
            }
            return Array(byKey.values)
        }

        public static func dedupe(_ xs: [Int]) -> [Int] {
            var seen = Set<Int>()
            return xs.filter { seen.insert($0).inserted }
        }

        public static func normalized(_ xs: [Int]) -> [Int] { xs.sorted() }
    }
    """

    static func entry(_ name: String) throws -> SemanticIndexEntry {
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Dedupe.swift")
        let summary = try #require(corpus.summaries.first { $0.name == name })
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary))
        return SwiftInferCommand.Index.buildEntry(
            from: suggestion, decisionsByHash: [:], now: "2026-11-21T00:00:00Z"
        )
    }

    static let strictOracle = "if onceResult != twiceResult {"
    static let orderFreeOracle = "if twiceResult.count != onceResult.count "
        + "|| !twiceResult.allSatisfy { element in onceResult.contains(element) } {"
    static let orderFreeCollision = "if collisionTwice.count != collisionOnce.count"

    @Test("the projection persists the route, and only on a gated dedupe")
    func projection() throws {
        #expect(try Self.entry("deduplicated").dedupeBody == DedupeBody(route: .dictionary))
        #expect(try Self.entry("dedupe").dedupeBody == DedupeBody(route: .set))
        #expect(try Self.entry("normalized").dedupeBody == nil)
    }

    @Test("a dictionary-route dedupe is verified without order, in the main loop and the collision sweep")
    func dictionaryRouteIsOrderFree() throws {
        let entry = try Self.entry("deduplicated")
        let stub = try SwiftInferCommand.Verify.buildStubBundle(entry: entry, budget: .small).source
        #expect(stub.contains(Self.orderFreeOracle))
        #expect(stub.contains(Self.orderFreeCollision))
        #expect(!stub.contains(Self.strictOracle))
    }

    @Test("a keep-first dedupe and a plain idempotence row keep the strict oracle")
    func otherRowsStayStrict() throws {
        for name in ["dedupe", "normalized"] {
            let stub = try SwiftInferCommand.Verify.buildStubBundle(entry: Self.entry(name), budget: .small).source
            #expect(stub.contains(Self.strictOracle), "\(name)")
            #expect(!stub.contains("twiceResult.allSatisfy"), "\(name)")
        }
    }
}
