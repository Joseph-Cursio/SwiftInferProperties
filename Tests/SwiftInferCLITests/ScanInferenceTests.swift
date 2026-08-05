import Foundation
import Testing

@testable import SwiftInferCLI

/// Scope inference for `discover`, and the line it must not cross.
///
/// The friction being removed: SwiftProjectLint takes a repository path and works
/// the layout out, `discover` did not, so the documented lint→infer hop failed on a
/// reader's first attempt. The line being kept: **no confident zero.** Inference
/// fires only where the layout is unambiguous, and the ambiguous case stays an error.
@Suite("Scan inference — discover's half of the hop")
struct ScanInferenceTests {

    private func makeTree(_ modules: [String], sources: Bool = true) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("scan-inference-\(UUID().uuidString)")
        let base = sources ? root.appendingPathComponent("Sources") : root
        for module in modules {
            try FileManager.default.createDirectory(
                at: base.appendingPathComponent(module), withIntermediateDirectories: true
            )
        }
        if modules.isEmpty {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return root
    }

    @Test("one module under Sources/ infers that target")
    func singleModuleInfersTarget() throws {
        let root = try makeTree(["Only"])
        defer { try? FileManager.default.removeItem(at: root) }
        let scan = try TargetDirectory.resolveScanInferring(
            target: nil, sources: nil, workingDirectory: root
        )
        #expect(scan.directory.lastPathComponent == "Only")
        #expect(scan.note?.contains("inferred --target Only") == true)
    }

    /// The load-bearing case. Picking *a* target when several exist would silently
    /// scan a fraction of the package — the confident zero this repo is built
    /// against. Scanning everything cannot be a *narrower* wrong answer.
    @Test("several modules scan the whole tree rather than picking one")
    func severalModulesScanEverything() throws {
        let root = try makeTree(["Alpha", "Beta", "Gamma"])
        defer { try? FileManager.default.removeItem(at: root) }
        let scan = try TargetDirectory.resolveScanInferring(
            target: nil, sources: nil, workingDirectory: root
        )
        #expect(scan.directory.lastPathComponent == "Sources")
        #expect(scan.note?.contains("3 modules") == true)
    }

    /// The one case inference must refuse. An Xcode app has no `Sources/`, and
    /// guessing a directory there is exactly how a run reports 0 suggestions about
    /// a folder nobody meant.
    @Test("no Sources/ is a loud error naming the escape hatch")
    func noSourcesIsAnError() throws {
        let root = try makeTree([], sources: false)
        defer { try? FileManager.default.removeItem(at: root) }
        var threw = false
        do {
            _ = try TargetDirectory.resolveScanInferring(
                target: nil, sources: nil, workingDirectory: root
            )
        } catch {
            threw = true
            #expect("\(error)".contains("--sources"))
        }
        #expect(threw, "inference must refuse rather than guess when there is no layout")
    }

    /// Explicit callers are untouched, and report nothing — the note exists so an
    /// *inferred* scope is visible, not to narrate what the user already typed.
    @Test("an explicit flag is passed through with no note")
    func explicitIsUnchanged() throws {
        let root = try makeTree(["Only"])
        defer { try? FileManager.default.removeItem(at: root) }
        let scan = try TargetDirectory.resolveScanInferring(
            target: nil,
            sources: root.appendingPathComponent("Sources/Only").path,
            workingDirectory: root
        )
        #expect(scan.note == nil)
        #expect(scan.directory.lastPathComponent == "Only")
    }

    /// Module listing is sorted, so a run is reproducible rather than dependent on
    /// filesystem enumeration order.
    @Test("module discovery is ordered")
    func moduleListingIsSorted() throws {
        let root = try makeTree(["Zulu", "Alpha", "Mike"])
        defer { try? FileManager.default.removeItem(at: root) }
        let modules = TargetDirectory.moduleDirectories(
            under: root.appendingPathComponent("Sources")
        )
        #expect(modules == ["Alpha", "Mike", "Zulu"])
    }
}
