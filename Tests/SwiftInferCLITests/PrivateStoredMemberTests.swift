import PropertyLawCore
import Testing

@testable import SwiftInferCLI
@testable import SwiftInferCore

/// A `private` stored property makes a struct's synthesized memberwise initializer inaccessible to
/// a test file, and the kit already refuses memberwise derivation for it
/// (`firstBlockingMemberwiseDerivation`). But the scanner dropped each member's access level and
/// `TypeShapeBuilder` rebuilt members without one, so the kit saw every member as callable and
/// emitted `CorrectSession(received: $0)` — which does not compile. Seven stubs in the seventh
/// corpus census were blocked on exactly that (pbt-workbook-corpus's upload sessions).
@Suite("Private stored members — the kit sees their access level")
struct PrivateStoredMemberTests {

    private func resolver(for source: String) -> GeneratorResolver {
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Session.swift")
        return GeneratorResolver(types: TypeShapeBuilder.shapes(from: corpus.typeDecls))
    }

    @Test("a struct with a private stored property gets no memberwise call it cannot make")
    func privateMemberBlocksMemberwise() {
        let expression = resolver(for: """
            struct Session {
                private var received: Set<Int> = []
                var receivedCount: Int { received.count }
            }
            """).customTypeGenerator(forTypeName: "Session")?.expression
        #expect(expression?.contains("Session(received:") != true, "got \(expression ?? "nil")")
    }

    @Test("the same struct with an internal member still derives memberwise")
    func internalMemberStillDerives() {
        let expression = resolver(for: """
            struct Session {
                var received: Set<Int> = []
            }
            """).customTypeGenerator(forTypeName: "Session")?.expression
        #expect(expression?.contains("Session(received:") == true, "got \(expression ?? "nil")")
    }
}
