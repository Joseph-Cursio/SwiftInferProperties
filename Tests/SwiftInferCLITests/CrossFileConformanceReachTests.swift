import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `scaffold-kit-suites` fed the wrong conformance index, and on idiomatic third-party
/// code that cost it the entire public API.
///
/// `TypeShapeBuilder` merges the primary declaration with **same-file** extensions only
/// (`TypeShapeBuilder.swift:172`). The scaffold command passed
/// `shapes.mapValues { Set($0.inheritedTypes) }`, so a type that declares its conformances
/// in a sibling file — `Money.swift` + `Money+Equatable.swift`, the dominant convention in
/// swift-collections and in Swift generally — read as conforming to nothing, and the audit
/// emitted no suites for it.
///
/// **Measured on swift-collections `899809d3` (2026-08-02):** `public struct BitSet {}`
/// carries a bare inheritance clause and declares all eleven conformances in separate
/// `BitSet+X.swift` files. Across five targets, **zero of the eight public collection
/// types** were reached — not `Deque`, `OrderedSet`, `TreeSet`, `BitSet`, `Heap`, or their
/// kin. What the emitter produced instead was internal HAMT scaffolding pulled in through
/// `@testable`: `_Bitmap`, `_HashSlot`, `_DequeSlot`, `_HeapNode`. After the fix, 6 of 8
/// are reached and `Deque` becomes the first public type to emit a live suite.
///
/// `ProtocolCoverageMap.inheritedTypesIndex(from:)` already merged cross-file extension
/// records; nothing was routing it here.
struct CrossFileConformanceReachTests {

    private struct SilentDiagnostics: DiagnosticOutput {
        func writeDiagnostic(_: String) { /* no-op */ }
    }

    private func makeFixtureDir(_ files: [String: String]) throws -> String {
        let dir = NSTemporaryDirectory() + "cross-file-conformance-" + UUID().uuidString
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        for (name, body) in files {
            try body.write(toFile: dir + "/" + name, atomically: true, encoding: .utf8)
        }
        return dir
    }

    private func pipeline(_ files: [String: String]) throws -> (
        SwiftInferCommand.Discover.PipelineResult, String
    ) {
        let dir = try makeFixtureDir(files)
        let url = URL(fileURLWithPath: dir)
        let diagnostics = SilentDiagnostics()
        let result = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: url,
            includePossible: true,
            evidence: SwiftInferCommand.Discover.loadEvidence(
                directory: url, diagnostics: diagnostics
            ),
            diagnostics: diagnostics
        )
        return (result, dir)
    }

    /// The regression this exists for: a conformance in a sibling file must reach the
    /// index the kit-suite audit reads.
    @Test("a conformance declared in ANOTHER file is reachable")
    func crossFileConformanceIsMerged() throws {
        let (result, dir) = try pipeline([
            "Money.swift": "public struct Money {\n    public let cents: Int\n}",
            "Money+Equatable.swift": "extension Money: Equatable {}",
            "Money+Hashable.swift": "extension Money: Hashable {}"
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let merged = result.inheritedTypesByName["Money"] ?? []
        #expect(merged.contains("Equatable"))
        #expect(merged.contains("Hashable"))
    }

    /// Pins the DIFFERENCE, not just the fix. `typeShapesByName` is same-file-only by
    /// design — it is not broken and must not be "fixed" to merge cross-file records,
    /// because other consumers rely on a shape describing one file's view of a type.
    /// The bug was reading the wrong one. If this expectation ever flips, the two indexes
    /// have converged and the scaffold command's input no longer matters.
    @Test("typeShapesByName stays same-file-only — the two indexes are different on purpose")
    func shapeIndexRemainsSameFileOnly() throws {
        let (result, dir) = try pipeline([
            "Money.swift": "public struct Money {\n    public let cents: Int\n}",
            "Money+Equatable.swift": "extension Money: Equatable {}"
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let shapeView = Set(result.typeShapesByName["Money"]?.inheritedTypes ?? [])
        #expect(!shapeView.contains("Equatable"))
        #expect(result.inheritedTypesByName["Money"]?.contains("Equatable") == true)
    }

    /// **The defect itself**, stated as the A/B the fix turns on: feed
    /// `ProtocolCoverageAudit` the shape-derived map and a cross-file conformer is audited
    /// to nothing; feed it the merged index and the type is found. The three tests above
    /// pin the index; this one pins that *which index the scaffold command passes* is the
    /// thing that mattered. `ScaffoldKitSuitesCommand` passes the second.
    @Test("the audit finds a cross-file conformer only with the merged index")
    func auditReachesCrossFileConformerOnlyWithMergedIndex() throws {
        let (result, dir) = try pipeline([
            "Money.swift": "public struct Money {\n    public let cents: Int\n}",
            "Money+Hashable.swift": "extension Money: Hashable {}"
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let shapeDerived = result.typeShapesByName.mapValues { Set($0.inheritedTypes) }
        let withShapes = ProtocolCoverageAudit.audit(
            inheritedTypesByName: shapeDerived, kitEvidence: KitEvidenceLog()
        )
        let withMerged = ProtocolCoverageAudit.audit(
            inheritedTypesByName: result.inheritedTypesByName, kitEvidence: KitEvidenceLog()
        )

        #expect(!withShapes.contains { $0.typeName == "Money" })
        #expect(withMerged.contains { $0.typeName == "Money" })
    }

    /// The control: a same-file conformance was always reachable, so a green run above
    /// is not just "the index has entries".
    @Test("a same-file conformance was never the problem")
    func sameFileConformanceStillWorks() throws {
        let (result, dir) = try pipeline([
            "Point.swift": "public struct Point: Equatable {\n    public let x: Int\n}"
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        #expect(result.inheritedTypesByName["Point"]?.contains("Equatable") == true)
        #expect(result.typeShapesByName["Point"]?.inheritedTypes.contains("Equatable") == true)
    }
}
