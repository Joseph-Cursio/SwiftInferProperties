import Foundation
import Testing

@testable import SwiftInferCLI

/// Reading a target's layout must not cost a subprocess per index entry.
///
/// ## The measured defect
///
/// `VerifyTargetInference.module(forLocation:packageRoot:)` runs **once per index entry**, and
/// a survey has hundreds. Consulting the manifest from inside it spawned a
/// `swift package dump-package` per row and took `make test-fast` from ~33 seconds past **ten
/// minutes** before it was killed (2026-08-14,
/// `docs/measurements/exploratory-swiftformat-grdb.md` §7.0).
///
/// Memoising the dump did **not** fix it. The cost is invoking SwiftPM *at all* on paths that
/// never needed it, not invoking it repeatedly — so the fix is ordering: the cheap structural
/// rule answers first, and the manifest is consulted only when the convention cannot.
///
/// ## Why a count and not a stopwatch
///
/// The defect is a **shape** — one spawn per row — and a shape is checkable exactly. A
/// duration budget only catches it once it is already catastrophic, varies by machine, and
/// flakes under parallel load; this repo's own §13 note records `MemoryCeilingPerformanceTests`
/// reading 150 MB alone and 4,800 MB under a full run. Counting spawns catches the same defect
/// at the **first** extra call.
///
/// **Corrected 2026-08-14: this used to end "deterministically, everywhere", and it was not.**
/// The count was process-wide while the cache is per-root, so concurrent suites' spawns landed
/// in this suite's deltas and it failed at `delta → 1` and `delta → 2` — a count is only
/// flake-free once it is *attributable*. It now counts per package root (see `spawnDelta`).
/// A shape is still the right thing to assert; the first version just asserted the wrong one.
///
/// The wall-clock ceiling that complements this lives in the Makefile, deliberately loose: it
/// exists to catch an order-of-magnitude regression that this suite somehow misses, not to
/// police seconds.
@Suite("Manifest reads are bounded by package, not by index entry")
struct ManifestSpawnBudgetTests {

    private func makePackage(target: String, path: String?) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spawn-\(UUID().uuidString)")
        let clause = path.map { ", path: \"\($0)\"" } ?? ""
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
        // swift-tools-version: 5.9
        import PackageDescription
        let package = Package(
            name: "Subject",
            targets: [.target(name: "\(target)"\(clause))]
        )
        """.write(
            to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(path ?? "Sources/\(target)"),
            withIntermediateDirectories: true
        )
        return root
    }

    /// Spawns attributable to **this arm's own package root**, as a delta across its calls.
    ///
    /// It used to read the process-wide total, and that was measured wrong on 2026-08-14: at
    /// least six suites dump a manifest, they run concurrently, and their spawns landed in this
    /// arm's delta. It failed with `delta → 1` and `delta → 2` and got steadily more likely as
    /// the suite grew — reporting a defect in a cache that was working perfectly.
    ///
    /// The old comment claimed a concurrent spawn "can only make an arm fail — never pass
    /// wrongly", which is true and is not a defence: a guard that fails for a reason unrelated
    /// to what it guards teaches people to re-run it, and then it guards nothing.
    ///
    /// Keying by root is also closer to the claim. What is being asserted is *this package root
    /// is dumped at most once*, not *nothing in the process dumps anything*.
    private func spawnDelta(forRoot root: URL, during work: () -> Void) -> Int {
        let before = TargetIsolation.manifestSpawnCount(forPackageRoot: root)
        work()
        return TargetIsolation.manifestSpawnCount(forPackageRoot: root) - before
    }

    @Test("a conventional layout never reads the manifest, however many entries")
    func conventionalLayoutNeverSpawns() throws {
        // The arm that would have failed on the ten-minute version. 200 stands in for a
        // survey's hundreds; the assertion is zero, so the exact count does not matter.
        let root = try makePackage(target: "Core", path: nil)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = root.appendingPathComponent("Sources/Core/Thing.swift").path + ":7"

        let delta = spawnDelta(forRoot: root) {
            for _ in 0 ..< 200 {
                _ = VerifyTargetInference.module(forLocation: location, packageRoot: root)
            }
        }

        #expect(delta == 0, "a conventional layout must not shell out to SwiftPM at all")
    }

    @Test("a custom layout reads the manifest once, not once per entry")
    func customLayoutSpawnsOnce() throws {
        // GRDB's shape. Here the manifest is genuinely required, so the guarantee is not
        // "never" but "bounded by package" — the cache doing its job.
        let root = try makePackage(target: "GRDB", path: "GRDB")
        defer { try? FileManager.default.removeItem(at: root) }
        let location = root.appendingPathComponent("GRDB/Core/Row.swift").path + ":42"

        // Warm the cache outside the measurement so the arm asserts the STEADY state; the
        // first call legitimately spawns.
        _ = VerifyTargetInference.module(forLocation: location, packageRoot: root)

        let delta = spawnDelta(forRoot: root) {
            for _ in 0 ..< 200 {
                _ = VerifyTargetInference.module(forLocation: location, packageRoot: root)
            }
        }

        #expect(delta == 0, "the manifest read must be memoised per package root")
    }

    @Test("the custom layout still resolves — the count is not bought with a wrong answer")
    func boundedCostStillResolves() throws {
        // A cache that returned nil forever would satisfy both arms above and break the
        // feature. This is the control that stops the budget being met by doing nothing.
        let root = try makePackage(target: "GRDB", path: "GRDB")
        defer { try? FileManager.default.removeItem(at: root) }
        let location = root.appendingPathComponent("GRDB/Core/Row.swift").path + ":42"
        for _ in 0 ..< 5 {
            #expect(
                VerifyTargetInference.module(forLocation: location, packageRoot: root) == "GRDB"
            )
        }
    }

    @Test("an unreadable manifest is not retried per entry")
    func failureIsCachedToo() throws {
        // A failure that is not cached is the same defect wearing a different answer: every
        // row re-spawns SwiftPM to be told nil again.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spawn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "not a manifest {{{".write(
            to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let location = root.appendingPathComponent("Elsewhere/Thing.swift").path + ":1"

        _ = VerifyTargetInference.module(forLocation: location, packageRoot: root)
        let delta = spawnDelta(forRoot: root) {
            for _ in 0 ..< 50 {
                _ = VerifyTargetInference.module(forLocation: location, packageRoot: root)
            }
        }

        #expect(delta == 0, "a failed manifest read must be cached, not retried per entry")
    }
}
