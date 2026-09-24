import PropertyLawCore
import Testing

@testable import SwiftInferCLI
@testable import SwiftInferCore

/// A `Sendable` class derives a generator through its initializer (SwiftPropertyLaws 4.9.0) — but
/// only if the scanner hands the kit that initializer. It captured initializers for structs and
/// extensions alone, so a class reached the strategist with none and could never derive, whatever
/// the kit allowed. These go through the real scan → shape → resolver path, which is what a stub
/// actually asks.
@Suite("Sendable class generators — scanned initializers reach the strategist")
struct SendableClassGeneratorTests {

    private func resolver(for source: String) -> GeneratorResolver {
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Models.swift")
        return GeneratorResolver(types: TypeShapeBuilder.shapes(from: corpus.typeDecls))
    }

    @Test("an @unchecked Sendable final class derives through its initializer")
    func uncheckedSendableClassDerives() {
        let resolver = resolver(for: """
            final class User: @unchecked Sendable {
                var email: String
                var isActive: Bool
                init(email: String, isActive: Bool) {
                    self.email = email
                    self.isActive = isActive
                }
            }
            """)
        let expression = resolver.customTypeGenerator(forTypeName: "User")?.expression
        #expect(expression?.contains("User(email: ") == true, "got \(expression ?? "nil")")
    }

    @Test("a class that is not Sendable still has no generator")
    func nonSendableClassDoesNot() {
        let resolver = resolver(for: """
            final class Visitor {
                var seen: Int
                init(seen: Int) { self.seen = seen }
            }
            """)
        #expect(resolver.customTypeGenerator(forTypeName: "Visitor") == nil)
    }
}
