import Foundation
import SwiftInferCore
import Testing

/// §13-style budgets for the construction universe itself — a regression the final review of the
/// shared spec's amendment 3 measured, priced so it cannot come back silently.
///
/// - **The walk enters `Tests/`** for the nested packages it holds, as SwiftProjectLint's does,
///   and it once read every entry's attributes there: a package with 50,000 snapshot PNGs under
///   `Tests/AppTests/__Snapshots__` took 2.4 s per universe (0.5 ms before the walk entered it).
///
/// Budgets carry several times their measured headroom, and run alone (`make perf`).
@Suite("Performance — construction universe walk and coverage budgets")
struct ConstructionUniversePerformanceTests {

    /// A package with one target and `snapshots` empty files under `Tests/AppTests/__Snapshots__`.
    static func snapshotPackage(snapshots: Int) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PerfUniverse-\(UUID().uuidString)")
        let snapshotsDirectory = root.appendingPathComponent("Tests/AppTests/__Snapshots__/AppTests")
        try FileManager.default.createDirectory(at: snapshotsDirectory, withIntermediateDirectories: true)
        try Data("// swift-tools-version:5.9\n".utf8).write(to: root.appendingPathComponent("Package.swift"))
        let app = root.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data("public func make() -> Int { 1 }\n".utf8).write(to: app.appendingPathComponent("App.swift"))
        for index in 0..<snapshots {
            let file = snapshotsDirectory.appendingPathComponent("test_\(index).1.png").path
            guard FileManager.default.createFile(atPath: file, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        return root
    }

    static func measureWall(_ block: () throws -> Void) rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        try block()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
    }

    @Test("A universe beside 20,000 snapshot files under Tests/ is walked within a 0.5-second budget")
    func universeBesideManySnapshotFiles() throws {
        let root = try Self.snapshotPackage(snapshots: 20_000)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Sources/App")
        var members = 0
        let elapsed = Self.measureWall { members = ConstructionUniverse.universe(forScanOf: app).members.count }
        print("[universe walk] 20,000 snapshot files: \(String(format: "%.3f", elapsed))s")
        #expect(members == 1)
        #expect(elapsed < 0.5, "the universe walk took \(elapsed)s over 20,000 files it only needs the names of")
    }
}
