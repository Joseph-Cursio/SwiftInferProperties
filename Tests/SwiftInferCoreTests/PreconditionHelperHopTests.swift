import Foundation
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

    /// Scans `sources` as one package, each in its own file, the way `discover` scans a target — the hop
    /// is applied where the scan assembles its records, so every `TypeShapeBuilder` caller sees it.
    private func shapes(_ sources: [String]) throws -> [TypeShape] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreconditionHelperHopTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (index, source) in sources.enumerated() {
            try source.write(to: root.appendingPathComponent("File\(index).swift"), atomically: true, encoding: .utf8)
        }
        return TypeShapeBuilder.shapes(from: try FunctionScanner.scanCorpus(directory: root).typeDecls)
    }

    @Test("a check routed through another type's trapping helper, in another file, is a precondition")
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
        let with = try #require(try shapes([Self.helper, matrix]).first { $0.name == "Matrix3x3" })
        let without = try #require(try shapes([matrix]).first { $0.name == "Matrix3x3" })
        #expect(with.initializers.first?.assertsPrecondition == true)
        #expect(without.initializers.first?.assertsPrecondition == false)
        if case .initializerBased = DerivationStrategist.strategy(for: with) {
            Issue.record("derived through an initializer whose helper traps")
        }
        guard case .initializerBased = DerivationStrategist.strategy(for: without) else {
            Issue.record("control: with no trapping helper in scope the initializer should still derive")
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
        let shape = try #require(try shapes([source]).first { $0.name == "SystemString" })
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
        let shape = try #require(try shapes([Self.helper, source]).first { $0.name == "Tag" })
        #expect(shape.initializers.first?.assertsPrecondition == false)
    }
}
