import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// A method on an actor instance is reached with `await` — 11 stubs across four repositories
/// failed in census 13 on an actor-isolated call made without it.
@Suite("Actor receivers — reached with await, not a hop")
struct ActorReceiverTests {

    private static let source = """
        public actor Store {
            public init() {}
            public func normalized(_ text: String) -> String { text.lowercased() }
            public nonisolated func label(_ text: String) -> String { text }
            public static func shared(_ text: String) -> String { text }
        }
        """

    private static let corpus = FunctionScanner.scanCorpus(source: source, file: "Store.swift")

    private static var actorNames: Set<String> {
        let shapes = TypeShapeBuilder.shapes(from: corpus.typeDecls)
        return ActorReceiver.actorTypeNames(in: Dictionary(uniqueKeysWithValues: shapes.map { ($0.name, $0) }))
    }

    private static func idempotence(_ name: String) throws -> Suggestion {
        try #require(TemplateRegistry.discover(in: corpus.summaries, typeDecls: corpus.typeDecls)
            .first { $0.templateName == "idempotence" && $0.evidence.first?.displayName == name })
    }

    @Test("an actor's instance method is marked and awaited")
    func instanceMethodIsAwaited() throws {
        #expect(Self.actorNames == ["Store"])
        let marked = ActorReceiver.marking(try Self.idempotence("normalized(_:)"), actorTypeNames: Self.actorNames)
        let callee = try #require(marked.evidence.first.flatMap(CalleeReference.init(evidence:)))
        #expect(callee.isolated("x.normalized(y)") == "await x.normalized(y)")
        let held = try #require(HeldReceiver.rewrite(marked) { _ in "Store()" })
        let text = try #require(InteractiveTriage.liftedTestStub(for: held))
        #expect(text.contains("await Store().normalized(Store().normalized(value))"), "got:\n\(text)")
    }

    @Test("a nonisolated member is not marked")
    func nonisolatedIsNotMarked() throws {
        let suggestion = try Self.idempotence("label(_:)")
        let marked = ActorReceiver.marking(suggestion, actorTypeNames: Self.actorNames)
        #expect(marked.evidence.first?.globalActor == nil)
    }

    @Test("a global actor still hops")
    func globalActorStillHops() {
        let callee = CalleeReference(bareName: "f", isolation: "MainActor")
        #expect(callee.isolated("f(x)") == "await MainActor.run { f(x) }")
    }
}
