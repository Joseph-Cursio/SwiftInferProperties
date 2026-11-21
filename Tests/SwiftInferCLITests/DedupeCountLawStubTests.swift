@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// The accepted idempotence stub of a gated dedupe also writes #671's count laws, C1 and C2, over
/// the same generator and seed (SwiftInferProperties#711). Whether the written laws kill the kill
/// arm's mutants is measured by compiling and running them: `docs/measurements/dedupe-count-laws.md`.
@Suite("Accept — a gated dedupe's idempotence stub also writes C1 and C2")
struct DedupeCountLawStubTests {

    static func stub(for source: String) throws -> String {
        let summary = try #require(FunctionScanner.scan(source: source, file: "Subject.swift").first)
        let suggestion = try #require(IdempotenceTemplate.suggest(for: summary))
        return try #require(InteractiveTriage.idempotentStub(for: suggestion))
    }

    static func setRoute(body: String = "if seen.insert(x).inserted { result.append(x) }") -> String {
        """
        enum Extractor {
            static func dedupe(relationships: [Int]) -> [Int] {
                var seen = Set<Int>()
                var result: [Int] = []
                for x in relationships { \(body) }
                return result
            }
        }
        """
    }

    @Test("a keep-first dedupe gets idempotence, C1, and C2 as equality — one seed for all three")
    func keepFirst() throws {
        let stub = try Self.stub(for: Self.setRoute())
        #expect(stub.contains("func dedupe_isIdempotent()"))
        #expect(stub.contains("func dedupe_keepsASingleton()"))
        #expect(stub.contains("func dedupe_ignoresADuplicateOfEverything()"))
        #expect(stub.contains(
            "value.allSatisfy { element in Extractor.dedupe(relationships: [element]).count == 1 }"
        ))
        #expect(stub.contains(
            "Extractor.dedupe(relationships: value + value) == Extractor.dedupe(relationships: value)"
        ))
        let seeds = stub.split(separator: "\n").filter { $0.contains("stateA:") }
        #expect(seeds.count == 3 && Set(seeds).count == 1, "one seed across the three laws")
    }

    @Test("a dictionary-route dedupe's C2 compares counts: its result is in hash order")
    func dictionaryRouteComparesCounts() throws {
        let stub = try Self.stub(for: """
        enum Universe {
            static func deduplicated(_ members: [Int]) -> [Int] {
                var byKey: [Int: Int] = [:]
                for member in members {
                    byKey[member % 7] = member
                }
                return Array(byKey.values)
            }
        }
        """)
        #expect(stub.contains(
            "Universe.deduplicated(value + value).count == Universe.deduplicated(value).count"
        ))
        #expect(!stub.contains("Universe.deduplicated(value + value) == "))
    }

    @Test("a dedupe the gate refuses gets today's stub: idempotence alone")
    func refusedGetsIdempotenceAlone() throws {
        let stub = try Self.stub(for: Self.setRoute(
            body: "guard x > 0 else { continue }; if seen.insert(x).inserted { result.append(x) }"
        ))
        #expect(stub.contains("func dedupe_isIdempotent()"))
        #expect(!stub.contains("keepsASingleton"))
        #expect(!stub.contains("ignoresADuplicateOfEverything"))
    }
}
