@testable import SwiftInferCLI
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// An instance method on a separate object is written with its receiver held fixed — the 103
/// suggestions the accept path declined as needing one argument more than the law applies.
@Suite("Held receiver — a law over a method on a configuration object")
struct HeldReceiverTests {

    private static let source = """
        public struct Codec {
            public var pretty: Bool
            public init(pretty: Bool) { self.pretty = pretty }
            public func encode(_ value: Point) -> [Int] { [value.x] }
            public func decode(_ fields: [Int]) -> Point { Point(x: fields.first ?? 0) }
            public func normalize(_ text: String) -> String { text.lowercased() }
        }
        public struct Point: Equatable { public var x: Int }
        public struct Bag: Equatable {
            public var items: [Int]
            public init(items: [Int]) { self.items = items }
            public func appending(_ other: Bag) -> Bag { Bag(items: items + other.items) }
        }
        """

    private static func suggestions(template: String) -> [Suggestion] {
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Codec.swift")
        return TemplateRegistry.discover(in: corpus.summaries, typeDecls: corpus.typeDecls)
            .filter { $0.templateName == template }
    }

    private static func held(_ suggestion: Suggestion) -> Suggestion? {
        HeldReceiver.rewrite(suggestion) { $0 == "Codec" ? "Codec(pretty: false)" : nil }
    }

    @Test("idempotence over a method on a configuration object calls it on the held receiver")
    func idempotenceIsHeld() throws {
        let suggestion = try #require(Self.suggestions(template: "idempotence")
            .first { $0.evidence.first?.displayName == "normalize(_:)" })
        #expect(StubApplicationArity.declineReason(for: suggestion) != nil, "declined as discovered")
        let held = try #require(Self.held(suggestion))
        #expect(StubApplicationArity.declineReason(for: held) == nil)
        let text = try #require(InteractiveTriage.liftedTestStub(for: held))
        #expect(text.contains("Codec(pretty: false).normalize(Codec(pretty: false).normalize(value))"),
                "got:\n\(text)")
    }

    @Test("a round-trip pair is held on one receiver for both halves")
    func roundTripIsHeld() throws {
        let suggestion = try #require(Self.suggestions(template: "round-trip").first)
        let held = try #require(Self.held(suggestion))
        let text = try #require(InteractiveTriage.liftedTestStub(for: held))
        #expect(text.contains("Codec(pretty: false).decode(Codec(pretty: false).encode("), "got:\n\(text)")
    }

    @Test("a receiver of the parameter's own type is an operand and is not held")
    func operandReceiverIsNotHeld() throws {
        let appending = try #require(Self.suggestions(template: "idempotence")
            .first { $0.evidence.first?.displayName == "appending(_:)" })
        #expect(HeldReceiver.rewrite(appending) { _ in "Bag(items: [])" } == nil)
    }

    @Test("a receiver nothing can spell is not held")
    func unspellableReceiverIsNotHeld() throws {
        let suggestion = try #require(Self.suggestions(template: "round-trip").first)
        #expect(HeldReceiver.rewrite(suggestion) { _ in nil } == nil)
    }

    @Test("a derived generator is drawn once, on a seed fixed by the suggestion")
    func generatorSpellingIsSeeded() throws {
        let suggestion = try #require(Self.suggestions(template: "round-trip").first)
        let spell = HeldReceiver.spelling(for: suggestion, receiverExpression: nil) { _ in "Codec.gen()" }
        let text = try #require(spell("Codec"))
        #expect(text.hasPrefix("({ () -> Codec in var receiverRNG = Xoshiro(seed: (0x"))
        #expect(text.hasSuffix("return (Codec.gen()).run(using: &receiverRNG) })()"))
        #expect(spell("Codec") == text, "deterministic")
        let todo = HeldReceiver.spelling(for: suggestion, receiverExpression: nil) { _ in "Codec.gen() /* .todo */" }
        #expect(todo("Codec") == nil)
        let marked = HeldReceiver.spelling(for: suggestion, receiverExpression: nil) { _ in
            "Codec.gen() /* TODO: no generator derived — supply `static func gen()`; this will not compile */"
        }
        #expect(marked("Codec") == nil)
    }

    @Test("a single-value generator is spelled as its value")
    func alwaysIsSpelledDirectly() throws {
        let suggestion = try #require(Self.suggestions(template: "round-trip").first)
        let spell = HeldReceiver.spelling(for: suggestion, receiverExpression: nil) { _ in "Gen.always(Codec())" }
        #expect(spell("Codec") == "Codec()")
        #expect(HeldReceiver.singleValue(of: "Gen.always(Codec()).map(f)") == nil)
    }

    @Test("an async or throwing subject is not held")
    func effectfulSubjectIsNotHeld() {
        #expect(HeldReceiver.hasEffects("(String) async -> Int"))
        #expect(HeldReceiver.hasEffects("(String) throws -> Int"))
        #expect(!HeldReceiver.hasEffects("([Int]) rethrows -> Int"))
        #expect(!HeldReceiver.hasEffects("(ThrowsPolicy) -> Int"))
    }
}
