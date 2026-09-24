@testable import SwiftInferCLI
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// `codable-round-trip`, `binary-idempotence` and `dual-style-consistency` get accept-path writers,
/// each stating the law its `verify` composer checks.
@Suite("Conformance law writers — codable round trip, binary idempotence, dual style")
struct ConformanceLawStubTests {

    private static let tags = """
        public struct Tags: Equatable {
            public var items: Set<Int>
            public init(items: Set<Int>) { self.items = items }
            public func union(_ other: Tags) -> Tags { Tags(items: items.union(other.items)) }
            public mutating func formUnion(_ other: Tags) { items.formUnion(other.items) }
        }
        """

    private static func suggestions(_ source: String, template: String) -> [Suggestion] {
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Tags.swift")
        return TemplateRegistry.discover(in: corpus.summaries, typeDecls: corpus.typeDecls)
            .filter { $0.templateName == template }
    }

    @Test("a formUnion / union pair checks the mutating half against the non-mutating one")
    func dualStyleOperandPair() throws {
        let suggestion = try #require(Self.suggestions(Self.tags, template: "dual-style-consistency").first)
        let text = try #require(InteractiveTriage.templateStub(for: suggestion))
        #expect(text.contains("var copy = args.0; copy.formUnion(args.1); return args.0.union(args.1) == copy"),
                "got:\n\(text)")
    }
    @Test("a union checks that combining a value with itself changes nothing")
    func binaryIdempotence() throws {
        let suggestion = try #require(Self.suggestions(Self.tags, template: "binary-idempotence").first)
        let text = try #require(InteractiveTriage.templateStub(for: suggestion))
        #expect(text.contains("value.union(value) == value"), "got:\n\(text)")
    }

    private static let queue = """
        public struct Queue: Equatable {
            public var items: [Int]
            public init(items: [Int]) { self.items = items }
            public func sorted() -> Queue { Queue(items: items.sorted()) }
            public mutating func sort() { items.sort() }
        }
        """

    @Test("a sorted / sort pair draws one value and compares against a sorted copy")
    func dualStyleNoOperand() throws {
        let suggestion = try #require(Self.suggestions(Self.queue, template: "dual-style-consistency").first)
        let text = try #require(InteractiveTriage.templateStub(for: suggestion))
        #expect(text.contains("var copy = value; copy.sort(); return value.sorted() == copy"), "got:\n\(text)")
    }

    private static let money = """
        public struct Money: Codable, Equatable {
            public var cents: Int
            public init(cents: Int) { self.cents = cents }
            enum CodingKeys: String, CodingKey { case cents }
            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                cents = try container.decode(Int.self, forKey: .cents)
            }
            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(cents, forKey: .cents)
            }
        }
        """

    @Test("a hand-written codec checks decode(encode(x)) == x, and a throwing codec fails it")
    func codableRoundTrip() throws {
        let suggestion = try #require(Self.suggestions(Self.money, template: "codable-round-trip").first)
        let text = try #require(InteractiveTriage.templateStub(for: suggestion))
        #expect(text.contains("try JSONDecoder().decode(Money.self, from: try JSONEncoder().encode(value))"),
                "got:\n\(text)")
        #expect(text.contains("Money_roundTripsThroughJSON"))
    }
}
