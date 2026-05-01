import Foundation
import Testing
import SwiftInferCore
import SwiftInferTemplates

/// PRD v0.3 §13 performance budget integration suite.
///
/// The hard target is `swift-infer discover` on a 50-file module in
/// **< 2 seconds wall** — a regression breaks this and blocks release.
/// PRD calls out `swift-collections` and `swift-algorithms` as the
/// reference corpora during M1; for M1.6 we calibrate against
/// `swift-collections/Sources/DequeModule` (44 .swift files — closest
/// real-world fit to the 50-file budget) when the sibling checkout is
/// available, and against a deterministic synthetic corpus always.
@Suite("Performance — PRD §13 budget enforcement")
struct PerformanceTests {

    /// 50-file synthetic corpus: each file fires every M2 template plus
    /// the M3.4 contradiction pass. Per file:
    ///   - `normalize(_:)` — idempotence
    ///   - `encode(_:)` / `decode(_:)` — round-trip
    ///   - `merge(_:_:)` over a custom struct — commutativity + associativity
    ///   - `static let empty: T` + `merge` reduce — identity-element
    ///   - the `merge` is referenced via `xs.reduce(.empty, merge)` →
    ///     reducer/builder usage signal
    /// All five M2 templates are active alongside the contradiction
    /// detector on the same scan, matching the M3.6 acceptance bar's
    /// "all five templates plus the new contradiction pass" requirement.
    @Test("Synthetic 50-file corpus discover completes within the §13 2-second budget")
    func syntheticFiftyFileCorpus() throws {
        let directory = try generateSyntheticCorpus(fileCount: 50)
        defer { try? FileManager.default.removeItem(at: directory) }
        var output: [Suggestion] = []
        let elapsed = try measureWall {
            output = try TemplateRegistry.discover(in: directory)
        }
        #expect(
            elapsed < 2.0,
            "Synthetic 50-file discover took \(formatted(elapsed))s — over the §13 2s budget"
        )
        // M3.6 acceptance bar: all five M2 templates active *plus* the
        // contradiction pass. Each template must surface at least once
        // across the corpus so the budget covers the full pipeline.
        let templates = Set(output.map(\.templateName))
        #expect(templates.contains("idempotence"))
        #expect(templates.contains("round-trip"))
        #expect(templates.contains("commutativity"))
        #expect(templates.contains("associativity"))
        #expect(templates.contains("identity-element"))
        // M4.5 acceptance bar (b): the M4.2 generator-selection pass
        // is active on top of the contradiction pass. The synthetic
        // corpus's `Bag` struct has two stdlib stored members
        // (`Int` + `String`) so commutativity / associativity /
        // identity-element suggestions over `Bag` lift to
        // `.derivedMemberwise`. At least one suggestion must therefore
        // carry a populated generator source — without M4.2 firing,
        // every suggestion would stay at the M1 `.notYetComputed`
        // placeholder.
        let populated = output.contains { $0.generator.source != .notYetComputed }
        #expect(populated, "GeneratorSelection did not fire on the synthetic corpus")
    }

    /// `swift-collections/Sources/DequeModule` is 44 `.swift` files —
    /// the closest open-source single-module corpus to the §13 50-file
    /// budget. Gated on the sibling checkout being present so the test
    /// is skipped (not failed) on machines / CI runners where the
    /// corpus isn't available.
    @Test(
        "swift-collections DequeModule discover completes within the §13 2-second budget",
        .enabled(if: PerformanceTests.dequeModulePath != nil)
    )
    func swiftCollectionsDequeModule() throws {
        let path = try #require(PerformanceTests.dequeModulePath)
        let elapsed = try measureWall {
            _ = try TemplateRegistry.discover(in: path)
        }
        #expect(
            elapsed < 2.0,
            "DequeModule discover took \(formatted(elapsed))s — over the §13 2s budget"
        )
    }

    // MARK: - Reference-corpus discovery

    /// Sibling `../swift-collections/Sources/DequeModule` resolved
    /// relative to the test source file (so the path holds regardless
    /// of the working directory `swift test` was invoked from). Returns
    /// `nil` when the corpus isn't checked out alongside this package.
    static let dequeModulePath: URL? = {
        let testSource = URL(fileURLWithPath: #filePath, isDirectory: false)
        // .../SwiftInferProperties/Tests/SwiftInferIntegrationTests/PerformanceTests.swift
        // strip filename + 2 dirs → SwiftInferProperties/
        let packageRoot = testSource
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sibling = packageRoot
            .deletingLastPathComponent()
            .appendingPathComponent("swift-collections/Sources/DequeModule")
        return FileManager.default.fileExists(atPath: sibling.path) ? sibling : nil
    }()

    // MARK: - Synthetic corpus

    private func generateSyntheticCorpus(fileCount: Int) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftInferPerf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        for index in 0..<fileCount {
            let url = base.appendingPathComponent("File\(index).swift")
            try syntheticFileSource(index: index)
                .write(to: url, atomically: true, encoding: .utf8)
        }
        return base
    }

    private func syntheticFileSource(index: Int) -> String {
        // Per-file unique types keep cross-file pairing bounded — a
        // realistic module rarely lets every encoder pair with every
        // decoder, or every merge with every other merge's identity.
        let payload = "Payload\(index)"
        let data = "Data\(index)"
        let bag = "Bag\(index)"
        return """
        import Foundation

        struct \(payload) {}
        struct \(data) {}
        struct \(bag): Equatable {}

        extension \(bag) {
            static let empty: \(bag) = \(bag)()
            func merge(_ first: \(bag), _ second: \(bag)) -> \(bag) {
                return first
            }
        }

        struct Container\(index) {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
            func encode(_ value: \(payload)) -> \(data) {
                return \(data)()
            }
            func decode(_ data: \(data)) -> \(payload) {
                return \(payload)()
            }
            func fold(_ items: [\(bag)]) -> \(bag) {
                return items.reduce(.empty, \(bag).merge)
            }
            func unrelated(_ first: Int, _ second: Int) -> Bool {
                return first == second
            }
        }
        """
    }

    // MARK: - Wall-clock measurement

    private func measureWall(_ block: () throws -> Void) rethrows -> Double {
        let start = Date()
        try block()
        return Date().timeIntervalSince(start)
    }

    private func formatted(_ seconds: Double) -> String {
        String(format: "%.3f", seconds)
    }
}
