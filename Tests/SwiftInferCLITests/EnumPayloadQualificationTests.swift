import PropertyLawCore
import SwiftInferCore
import Testing

/// **An enum payload is qualified against the scanned universe, like a stored member or an
/// initializer parameter.** `TypeShapeBuilder` resolved those two the way Swift does — innermost
/// enclosing scope first — and passed `enumCases` through bare.
///
/// That went unnoticed because the kit guessed: a bare `Payload` fell back to the one scanned type
/// whose last component was `Payload`. SwiftPropertyLaws#63 removed the guess — it built
/// SwiftAssist's `XcodeDocument.Symbol` for SwiftSourceKitClient's `Symbol` — so the kit now reads
/// a bare spelling at module scope, where `Payload` names nothing. Every call site here resolves a
/// shape with `customTypeGenerator`, so the spelling has to arrive qualified.
@Suite("Enum payloads are qualified against the scanned universe")
struct EnumPayloadQualificationTests {

    private static let corpus = FunctionScanner.scanCorpus(source: """
        public enum Event: Equatable {
            public struct Payload: Equatable { public let n: Int }
            case fired(Payload)
            case idle
        }
        public struct Document {
            public struct Symbol: Equatable { public let id: Int }
        }
        public enum Change: Equatable {
            case renamed(Symbol)
        }
        """, file: "Event.swift")

    private static var shapes: [TypeShape] { TypeShapeBuilder.shapes(from: corpus.typeDecls) }

    private static func strategy(for name: String) throws -> DerivationStrategy {
        let shape = try #require(shapes.first { $0.name == name })
        return DerivationStrategist.strategy(for: shape, resolve: GeneratorResolver(types: shapes).customTypeGenerator)
    }

    @Test("a payload naming a nested sibling is recorded qualified")
    func payloadIsQualified() throws {
        let event = try #require(Self.shapes.first { $0.name == "Event" })
        let fired = try #require(event.enumCases.first { $0.name == "fired" })
        #expect(fired.associatedValues.map(\.typeName) == ["Event.Payload"])
    }

    @Test("the enum derives through the resolver the call sites pass")
    func enumDerives() throws {
        if case .todo(let reason) = try Self.strategy(for: "Event") {
            Issue.record("Event should derive through Event.Payload; got .todo: \(reason)")
        }
    }

    /// The control, and #63 seen from this side: `Change` is nested in nothing, so its `Symbol` is
    /// another module's. The walk must not qualify it to the unrelated `Document.Symbol`, and the
    /// kit (4.10.0 on) must not build one for the bare spelling either.
    @Test("a payload from another module stays bare and does not derive")
    func foreignPayloadDoesNotDerive() throws {
        let change = try #require(Self.shapes.first { $0.name == "Change" })
        #expect(change.enumCases.first?.associatedValues.map(\.typeName) == ["Symbol"])
        guard case .todo = try Self.strategy(for: "Change") else {
            Issue.record("Change must not derive from the unrelated Document.Symbol")
            return
        }
    }
}
