import PropertyLawCore
@testable import SwiftInferCore
import Testing

/// An initializer that calls a trapping helper states a precondition one hop away. Harbeth's
/// `Matrix3x3.init(values:)` calls `HarbethError.failed(…)`, which is `fatalError` in DEBUG, and the kit
/// derived a generator through it that trapped (`docs/measurements/subject-harbeth.md`).
@Suite("Precondition one hop through a helper")
struct PreconditionHelperHopTests {

    private static let helper = """
        public enum HarbethError {
            public static func failed(_ message: String) {
                #if DEBUG
                fatalError(message)
                #else
                print(message)
                #endif
            }
            public static func note(_ message: String) { print(message) }
        }
        """

    private func shapes(_ sources: [String], hop: Bool) -> [TypeShape] {
        let corpora = sources.enumerated().map { FunctionScanner.scanCorpus(source: $1, file: "f\($0).swift") }
        let decls = corpora.flatMap(\.typeDecls)
        let trapping = hop ? corpora.reduce(into: Set<String>()) { $0.formUnion($1.trappingFunctions) } : []
        return TypeShapeBuilder.shapes(from: decls, trappingFunctions: trapping)
    }

    @Test("a check routed through another type's trapping helper is a precondition, and the kit declines it")
    func harbethShapeIsDeclined() throws {
        let matrix = """
            public struct Matrix3x3: Equatable {
                public var values: [Float]
                public init(values: [Float]) {
                    if values.count != 9 { HarbethError.failed("There must be nine values for 3x3 Matrix.") }
                    self.values = values
                }
            }
            """
        let with = try #require(shapes([Self.helper, matrix], hop: true).first { $0.name == "Matrix3x3" })
        let without = try #require(shapes([Self.helper, matrix], hop: false).first { $0.name == "Matrix3x3" })
        #expect(with.initializers.first?.assertsPrecondition == true)
        #expect(without.initializers.first?.assertsPrecondition == false)
        if case .initializerBased = DerivationStrategist.strategy(for: with) {
            Issue.record("derived through an initializer whose helper traps")
        }
        guard case .initializerBased = DerivationStrategist.strategy(for: without) else {
            Issue.record("control: without the hop the initializer should still derive")
            return
        }
    }

    @Test("a same-type invariant check through self counts too")
    func sameTypeHelperCounts() throws {
        let source = """
            struct SystemString: Equatable {
                var bytes: [UInt8]
                init(bytes: [UInt8]) { self.bytes = bytes; self._invariantCheck() }
                private func _invariantCheck() { precondition(!bytes.contains(0)) }
            }
            """
        let shape = try #require(shapes([source], hop: true).first { $0.name == "SystemString" })
        #expect(shape.initializers.first?.assertsPrecondition == true)
    }

    @Test("a helper that does not trap leaves the initializer derivable")
    func nonTrappingHelperIsIgnored() throws {
        let source = """
            public struct Tag: Equatable {
                public var name: String
                public init(name: String) { HarbethError.note(name); self.name = name }
            }
            """
        let shape = try #require(shapes([Self.helper, source], hop: true).first { $0.name == "Tag" })
        #expect(shape.initializers.first?.assertsPrecondition == false)
    }
}
