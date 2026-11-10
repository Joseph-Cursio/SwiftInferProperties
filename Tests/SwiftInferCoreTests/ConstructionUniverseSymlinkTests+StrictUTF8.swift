import Foundation
import SwiftEffectInference
import Testing

@testable import SwiftInferCore

// MARK: - C: strict UTF-8

extension ConstructionUniverseSymlinkTests {

    /// The shared spec's amendment C: a file enters the table only if it decodes as strict UTF-8,
    /// since `swiftc` reads no other. A lenient read would detect this UTF-16 file by its byte-order
    /// mark, decode it, and let a type no target compiles refute `make`.
    @Test("a universe file that is not strict UTF-8 declares nothing to the table")
    func nonUTF8FileIsNotInTheUniverse() throws {
        let root = try Wiring.makePackage(["Sources/Lib/Make.swift": Wiring.make])
        defer { try? FileManager.default.removeItem(at: root) }
        let model = root.appendingPathComponent("Sources/Model/Item.swift")
        let directory = model.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Wiring.item.write(to: model, atomically: true, encoding: .utf16)
        let lib = root.appendingPathComponent("Sources/Lib")
        #expect(ConstructionUniverse.files(forScanOf: lib).map(\.relativePath).contains("Sources/Model/Item.swift"))
        let purity = PackagePurity.forScan(of: lib)
        #expect(purity.universe == ["Sources/Lib/Make.swift"], "a UTF-16 file reached the table")
        #expect(try Self.verdict("make", scanning: lib) == .pure)
    }
}
