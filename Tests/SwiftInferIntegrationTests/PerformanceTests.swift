import Foundation
import Testing
import SwiftInferCLI
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

    /// 50-file synthetic corpus: each file fires every shipped template
    /// plus the M3.4 contradiction pass. Per file:
    ///   - `normalize(_:)` — idempotence
    ///   - `encode(_:)` / `decode(_:)` — round-trip
    ///   - `merge(_:_:)` over a custom struct — commutativity + associativity
    ///   - `static let empty: T` + `merge` reduce — identity-element
    ///   - the `merge` is referenced via `xs.reduce(.empty, merge)` →
    ///     reducer/builder usage signal
    ///   - `length(_:)` — monotonicity (M7.1; type pattern + curated
    ///     name `length`, fires at Possible tier)
    ///   - `adjust(_:)` annotated with `@CheckProperty(.preservesInvariant(\.isValid))`
    ///     — invariant-preservation (M7.2; annotation-only, Strong tier)
    /// All seven shipped templates are active alongside the contradiction
    /// detector on the same scan, matching the M7.6 acceptance bar (g)
    /// "§13 budget holds *with* M7's two new templates active".
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
        // M7.6 acceptance bar (g): the perf re-check holds with M7's
        // two new templates also active. The corpus's `length(_:)`
        // fires monotonicity; the `@CheckProperty(.preservesInvariant)`
        // annotation fires invariant-preservation.
        #expect(templates.contains("monotonicity"))
        #expect(templates.contains("invariant-preservation"))
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
        // M5.6 acceptance bar (f): the M5.1 @Discoverable scanner
        // extension is active. Each per-file Container's encode /
        // decode pair carries @Discoverable(group: "codec<n>"), so
        // every round-trip suggestion across the corpus must also
        // earn the +35 .discoverableAnnotation signal — without M5.1
        // firing, no suggestion would carry it.
        let discoverableSeen = output.contains { suggestion in
            suggestion.score.signals.contains { $0.kind == .discoverableAnnotation }
        }
        #expect(discoverableSeen, "@Discoverable signal did not fire on the synthetic corpus")
    }

    /// M6.6 acceptance bar (g): the §13 budget must hold *with* the
    /// M6.1 decisions-load path active. The synthetic corpus gains a
    /// sibling `.swiftinfer/decisions.json` (one decided record per
    /// surfaced suggestion), and the test runs `Discover.run`
    /// end-to-end so the decisions read happens inside the budget
    /// alongside the discovery scan. M6.4's `--interactive` is a
    /// developer-driven gesture and is excluded — the budget is for
    /// the unattended discovery path the §13 PRD line targets.
    @Test("Synthetic 50-file corpus discover stays under §13 with M6.1 decisions-load active")
    func syntheticFiftyFileCorpusWithDecisionsLoad() throws {
        let directory = try generateSyntheticCorpus(fileCount: 50)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Wrap the synthetic target into a Package.swift-rooted layout
        // so DecisionsLoader's walk-up resolves the conventional path.
        let packageRoot = directory.deletingLastPathComponent()
            .appendingPathComponent("PerfPkg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: packageRoot) }
        try Data("// swift-tools-version: 6.1\n".utf8).write(
            to: packageRoot.appendingPathComponent("Package.swift")
        )
        let target = packageRoot.appendingPathComponent("Sources").appendingPathComponent("Lib")
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Move (rename) the synthetic corpus into the package's
        // Sources/Lib/ slot so the discover pipeline picks it up.
        try FileManager.default.moveItem(at: directory, to: target)
        // Pre-discover to capture identities, then write a fixture
        // decisions.json with one .skipped record per surfaced
        // suggestion. The skipped state is what M6.4's drift suppression
        // path reads on every subsequent run.
        let pipeline = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: target,
            diagnostics: SilentDiagnosticOutput()
        )
        let decisions = Decisions(records: pipeline.suggestions.map { suggestion in
            DecisionRecord(
                identityHash: suggestion.identity.normalized,
                template: suggestion.templateName,
                scoreAtDecision: suggestion.score.total,
                tier: suggestion.score.tier,
                decision: .skipped,
                timestamp: Date(timeIntervalSince1970: 0)
            )
        })
        try DecisionsLoader.write(
            decisions,
            to: packageRoot.appendingPathComponent(".swiftinfer/decisions.json")
        )
        // Now measure the full Discover.run path with the decisions
        // file present.
        let elapsed = try measureWall {
            try SwiftInferCommand.Discover.run(
                directory: target,
                output: SilentOutput(),
                diagnostics: SilentDiagnosticOutput()
            )
        }
        #expect(
            elapsed < 2.0,
            "Discover.run with decisions.json took \(formatted(elapsed))s — over the §13 2s budget"
        )
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

    // swiftlint:disable:next function_body_length
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
            @Discoverable(group: "codec\(index)")
            func encode(_ value: \(payload)) -> \(data) {
                return \(data)()
            }
            @Discoverable(group: "codec\(index)")
            func decode(_ data: \(data)) -> \(payload) {
                return \(payload)()
            }
            func fold(_ items: [\(bag)]) -> \(bag) {
                return items.reduce(.empty, \(bag).merge)
            }
            // M7.1 — curated `length` verb on `String -> Int` fires
            // monotonicity at Possible tier (type pattern + curated
            // naming match).
            func length(_ value: String) -> Int {
                return value.count
            }
            // M7.2 — annotation-only invariant-preservation. The
            // scanner picks up the `@CheckProperty(.preservesInvariant(\\.isValid))`
            // attribute by name match; the template fires Strong-tier
            // because the annotation IS the signal.
            @CheckProperty(.preservesInvariant(\\.isValid))
            func adjust(_ value: \(payload)) -> \(payload) {
                return value
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

// MARK: - Silent stubs for the M6.6 perf re-check

private final class SilentOutput: DiscoverOutput, @unchecked Sendable {
    func write(_ text: String) {}
}

private final class SilentDiagnosticOutput: DiagnosticOutput, @unchecked Sendable {
    func writeDiagnostic(_ text: String) {}
}
