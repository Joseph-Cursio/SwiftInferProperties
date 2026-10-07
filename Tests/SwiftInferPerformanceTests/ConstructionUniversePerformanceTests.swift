import Foundation
import SwiftInferCore
import Testing

/// §13-style budgets for the construction universe itself — the two regressions the final review
/// of the shared spec's amendment 3 measured, each priced so it cannot come back silently.
///
/// - **The walk enters `Tests/`** for the nested packages it holds, as SwiftProjectLint's does,
///   and it once read every entry's attributes there: a package with 50,000 snapshot PNGs under
///   `Tests/AppTests/__Snapshots__` took 2.4 s per universe (0.5 ms before the walk entered it).
/// - **`PackagePurity.covers`** once computed a whole universe on every ask, and a directory
///   scan asks it per call — three times in `discover-reducers` — which doubled that command on
///   swift-package-manager's `Basics`.
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

    /// The built-for shortcut is the one `discover-reducers` and `verify-value-semantics` use, so
    /// the row prices the FIRST ask, which the memo cannot answer: the package is heavy enough
    /// (20,000 files under `Tests/`, ~0.1 s a universe in a debug build) that one computed universe
    /// is several budgets over. With the shortcut the three asks are a string comparison each.
    @Test("covers on the directory a purity was built for answers three times within a 0.02-second budget")
    func coversOnItsOwnDirectory() throws {
        let root = try Self.snapshotPackage(snapshots: 20_000)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Sources/App")
        let purity = PackagePurity.forScan(of: app)
        var covered = true
        let elapsed = Self.measureWall {
            for _ in 0..<3 { covered = covered && purity.covers(app) }
        }
        print("[covers] three asks: \(String(format: "%.4f", elapsed))s")
        #expect(covered)
        #expect(elapsed < 0.02, "three covers asks took \(elapsed)s — the first one computed a universe")
    }
}
