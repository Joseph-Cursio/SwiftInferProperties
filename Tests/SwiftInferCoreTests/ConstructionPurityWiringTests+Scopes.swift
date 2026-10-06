import Foundation
import PropertyLawCore
import Testing

@testable import SwiftInferCore

/// The wiring beyond the function verdict: the getter path, the scans that must NOT build a
/// table, and the guard that keeps an empty scan from parsing a package.
extension ConstructionPurityWiringTests {

    // MARK: - The getter path

    /// A computed property is a nullary `self -> T` map to the templates, and it is judged by
    /// `SoundPurity.verdict(forGetter:)`, not `verdict(for:)`. Every other wiring fixture's subject
    /// is a function, so a getter path that kept the unconfigured inferrer survived the whole suite
    /// — while swift-foundation's 21 moved rows include 12 getters.
    @Test("a computed property constructing a sibling target's refuted type is refuted")
    func getterConstructingASiblingTypeIsRefuted() throws {
        let root = try Self.makePackage([
            "Sources/Model/Item.swift": Self.item,
            "Sources/Lib/Shelf.swift": """
            public struct Shelf {
                public let name: String
                public var sample: Item { Item(title: name) }
            }
            """
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appendingPathComponent("Sources/Lib")
        let summaries = try FunctionScanner.scanCorpus(directory: lib).summaries
        let sample = try #require(summaries.first { $0.name == "sample" })
        #expect(sample.isComputedProperty)
        #expect(sample.purityVerdict == .refuted, "the getter path judged without the package's table")
        #expect(!sample.isInferredPure)
        // The control: the file alone cannot see `Item`, so the getter reads pure.
        let alone = try FunctionScanner.scanCorpus(file: lib.appendingPathComponent("Shelf.swift"))
        #expect(Self.verdict("sample", in: alone) == .pure)
    }

    // MARK: - Scans that build no table

    /// `scanTypeDecls(directory:)` is for callers that read declarations only. Its output must be
    /// exactly the full scan's — the cross-file `PreconditionHelperHop` included, which is the part
    /// a per-file loop would lose — with no universe parsed for it.
    @Test("the declarations-only scan returns the full scan's typeDecls, the cross-file hop included")
    func declarationsOnlyScanMatchesTheFullScan() throws {
        let root = try Self.makePackage([
            "Sources/Lib/Failure.swift": """
            public enum Failure {
                public static func failed(_ message: String) { fatalError(message) }
            }
            """,
            "Sources/Lib/Matrix.swift": """
            public struct Matrix: Equatable {
                public var values: [Float]
                public init(values: [Float]) {
                    if values.count != 9 { Failure.failed("nine values") }
                    self.values = values
                }
            }
            """,
            "Sources/Lib/Item.swift": Self.item,
            "Sources/Model/Other.swift": "public struct Other: Equatable { public let n: Int }"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appendingPathComponent("Sources/Lib")
        let declarations = try FunctionScanner.scanTypeDecls(directory: lib)
        #expect(declarations == (try FunctionScanner.scanCorpus(directory: lib)).typeDecls)
        let matrix = try #require(TypeShapeBuilder.shapes(from: declarations).first { $0.name == "Matrix" })
        #expect(matrix.initializers.first?.assertsPrecondition == true, "the hop across files was not applied")
        #expect(!declarations.contains { $0.name == "Other" }, "a sibling target's type was scanned")
        #expect(try FunctionScanner.scanTypeDecls(directory: root.appendingPathComponent("Empty")).isEmpty)
    }

    @Test("a purity is built for judging only when something is judged")
    func purityIsBuiltOnlyForAJudgedSet() throws {
        let root = try Self.makePackage([
            "Sources/Lib/Item.swift": Self.item,
            "Sources/Lib/Make.swift": Self.make,
            "Sources/Empty/README.md": "no Swift here"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(PackagePurity.forJudging(directory: root.appendingPathComponent("Sources/Empty")) == nil)
        #expect(PackagePurity.forJudging(directory: root.appendingPathComponent("Missing")) == nil)
        let lib = root.appendingPathComponent("Sources/Lib")
        let purity = try #require(PackagePurity.forJudging(directory: lib))
        #expect(purity.covers(lib))
        #expect(purity.universe == ["Sources/Lib/Item.swift", "Sources/Lib/Make.swift"])
    }
}
