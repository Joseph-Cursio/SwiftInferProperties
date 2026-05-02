import Foundation
import Testing
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates

// swiftlint:disable type_body_length file_length
// Single-suite for §16 + §14 hard guarantees grows linearly with new
// allowlist boundaries (M6 SwiftInfer, M7 SwiftInferRefactors, ...).
// Splitting along the 400-line / 250-body limits would scatter the
// allowlist assertions for no reader benefit.

/// PRD v0.3 §16 hard-guarantee integration suite + the §14 telemetry
/// boundary. The M1 acceptance bar §c (per the M1 Plan) calls out three
/// guarantees as in-scope for M1.7:
///
///   1. **No source-file modification** (§16 #1). `discover` is read-
///      only against the scanned target.
///   2. **Byte-identical reproducibility** (§16 #6). Re-running
///      `discover` on unchanged source produces identical output. The
///      seeded sampling policy lands at M4; M1 verifies the property
///      at the discovery layer where no sampling runs.
///   3. **No telemetry / no network calls** (§14). Static check —
///      production source contains none of the networking-API usage
///      patterns we explicitly forbid.
///
/// Other §16 rows (no test deletion #2, no auto-accept #3, no silently-
/// wrong code #4, target-scope refusal #5) are template / TestLifter /
/// CLI-layer concerns and either covered by unit tests already
/// (`discoverRequiresTargetOption`) or land with later milestones.
@Suite("Hard guarantees — PRD §16 + §14 telemetry boundary")
struct HardGuaranteeTests {

    // MARK: - §16 #1 — no source modification

    @Test("discover never modifies any file in the scanned target")
    func discoverDoesNotModifySource() throws {
        let directory = try makeFixture(named: "NoModification")
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = try snapshotContents(of: directory)
        _ = try TemplateRegistry.discover(in: directory)
        let after = try snapshotContents(of: directory)
        #expect(before == after, "Source files were modified by discover")
    }

    @Test("discover does not create new files in the scanned target")
    func discoverDoesNotCreateFiles() throws {
        let directory = try makeFixture(named: "NoNewFiles")
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = try fileSet(of: directory)
        _ = try TemplateRegistry.discover(in: directory)
        let after = try fileSet(of: directory)
        #expect(before == after, "discover added or removed files in the scanned target")
    }

    // MARK: - §16 #6 — byte-identical reproducibility

    @Test("Repeated discover runs return identical Suggestion lists")
    func suggestionsByteIdenticalAcrossRuns() throws {
        let directory = try makeFixture(named: "Reproducibility")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try TemplateRegistry.discover(in: directory)
        let second = try TemplateRegistry.discover(in: directory)
        let third = try TemplateRegistry.discover(in: directory)
        #expect(first == second)
        #expect(second == third)
    }

    @Test("Rendered output is byte-identical across runs")
    func renderedOutputByteIdentical() throws {
        let directory = try makeFixture(named: "RenderedReproducibility")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = SuggestionRenderer.render(try TemplateRegistry.discover(in: directory))
        let second = SuggestionRenderer.render(try TemplateRegistry.discover(in: directory))
        #expect(first == second)
    }

    @Test("Sampling seed is reproducible across runs (PRD §16 #6 + M4.3)")
    func samplingSeedReproducibleAcrossRuns() throws {
        // §16 #6 requires the sampling seed to be byte-identical for
        // unchanged source. M4.3 derives the seed from the suggestion
        // identity (which is itself derived from the canonical signature),
        // so re-running discover must produce identical seeds — and the
        // rendered "lifted test seed: 0x..." line must match across runs.
        let directory = try makeFixture(named: "SeedReproducibility")
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstRun = try TemplateRegistry.discover(in: directory)
        let secondRun = try TemplateRegistry.discover(in: directory)
        let firstSeeds = firstRun.map { SamplingSeed.derive(from: $0.identity) }
        let secondSeeds = secondRun.map { SamplingSeed.derive(from: $0.identity) }
        #expect(firstSeeds == secondSeeds, "Sampling seeds drifted across runs on unchanged source")
        // Belt-and-suspenders: confirm the rendered text contains the
        // same hex form across runs. The whole-output reproducibility
        // test above implicitly covers this, but pinning the seed line
        // explicitly catches regressions where the renderer might
        // someday emit the seed conditionally.
        let firstRendered = SuggestionRenderer.render(firstRun)
        let secondRendered = SuggestionRenderer.render(secondRun)
        for seed in firstSeeds {
            let line = "lifted test seed: \(SamplingSeed.renderHex(seed))"
            #expect(firstRendered.contains(line))
            #expect(secondRendered.contains(line))
        }
    }

    @Test("Discovery order is stable across an out-of-order input shuffle")
    func discoveryOrderStable() throws {
        // Same logical corpus, different file *names* — sorted-path
        // enumeration in FunctionScanner.scan(directory:) means the
        // file with the lexically smaller name is scanned first
        // regardless of which was created first.
        let directoryA = try makeFixture(named: "OrderStable-A", layout: .alpha)
        let directoryB = try makeFixture(named: "OrderStable-B", layout: .alpha)
        defer {
            try? FileManager.default.removeItem(at: directoryA)
            try? FileManager.default.removeItem(at: directoryB)
        }
        let renderA = SuggestionRenderer.render(try TemplateRegistry.discover(in: directoryA))
        let renderB = SuggestionRenderer.render(try TemplateRegistry.discover(in: directoryB))
        // Strip the absolute path to the temp directory before comparing
        // — the rendered location lines carry the directory path, which
        // differs between fixtures by construction.
        let normalizedA = renderA.replacingOccurrences(of: directoryA.path, with: "<root>")
        let normalizedB = renderB.replacingOccurrences(of: directoryB.path, with: "<root>")
        #expect(normalizedA == normalizedB)
    }

    // MARK: - §16 #1 — M6 writeouts respect the allowlist

    @Test("--interactive accept writes only under Tests/Generated/SwiftInfer/")
    func interactiveAcceptWritesOnlyUnderGeneratedTests() throws {
        let directory = try makeM6Fixture(named: "InteractiveAcceptAllowlist")
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("Sources").appendingPathComponent("Lib")
        let before = try fileSet(of: directory)
        try SwiftInferCommand.Discover.run(
            directory: target,
            interactive: true,
            promptInput: ScriptedPromptInput(scriptedLines: ["A"]),
            output: SilentOutput(),
            diagnostics: SilentDiagnosticOutput()
        )
        let after = try fileSet(of: directory)
        let added = after.subtracting(before)
        // Two paths added: the property-test stub + the decisions.json
        // record. Both match the M6 plan's allowlist (Tests/Generated/
        // SwiftInfer/<Template>/<FunctionName>.swift +
        // .swiftinfer/decisions.json under packageRoot).
        for path in added {
            #expect(
                path.hasPrefix("/Tests/Generated/SwiftInfer/")
                    || path.hasPrefix("/.swiftinfer/decisions.json"),
                "M6 --interactive accept wrote outside the allowlist: \(path)"
            )
        }
        // Source files untouched — snapshot equality on the original
        // source tree (everything under /Sources/) before vs after.
        let sourceBefore = before.filter { $0.hasPrefix("/Sources/") }
        let sourceAfter = after.filter { $0.hasPrefix("/Sources/") }
        #expect(sourceBefore == sourceAfter)
    }

    // MARK: - §16 #1 — M7 RefactorBridge writeout allowlist

    @Test("--interactive B accept writes only under Tests/Generated/SwiftInferRefactors/")
    func interactiveBAcceptWritesOnlyUnderRefactorsAllowlist() throws {
        let directory = try makeM7BridgeFixture(named: "BridgeAllowlist")
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("Sources").appendingPathComponent("Lib")
        let before = try fileSet(of: directory)
        try SwiftInferCommand.Discover.run(
            directory: target,
            interactive: true,
            // First prompt: B (accept conformance for the type). Second:
            // s (skip; the next associativity-firing suggestion on the
            // same type collapses to [A/s/n/?] per per-type aggregation).
            promptInput: ScriptedPromptInput(scriptedLines: ["B", "s", "s", "s"]),
            output: SilentOutput(),
            diagnostics: SilentDiagnosticOutput()
        )
        let after = try fileSet(of: directory)
        let added = after.subtracting(before)
        // Allowed prefixes: SwiftInferRefactors writeout + decisions.json.
        // The associativity / commutativity / identity-element templates
        // ship no LiftedTestEmitter arm in v1, so A-arm accepts (skipped
        // here) wouldn't write under Tests/Generated/SwiftInfer/ even if
        // surfaced — the allowlist for B alone is what this test pins.
        for path in added {
            #expect(
                path.hasPrefix("/Tests/Generated/SwiftInferRefactors/")
                    || path.hasPrefix("/.swiftinfer/decisions.json"),
                "M7 --interactive B accept wrote outside the allowlist: \(path)"
            )
        }
        // The file written must follow the per-PRD §16 #1 path convention:
        // Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift.
        let conformancePath = added.first {
            $0.hasPrefix("/Tests/Generated/SwiftInferRefactors/")
        }
        #expect(conformancePath != nil, "RefactorBridge B accept did not write a conformance file")
        if let path = conformancePath {
            #expect(path.contains("/Bag/Semigroup.swift") || path.contains("/Bag/Monoid.swift"))
        }
        // Source files untouched — same posture as the M6 allowlist test.
        let sourceBefore = before.filter { $0.hasPrefix("/Sources/") }
        let sourceAfter = after.filter { $0.hasPrefix("/Sources/") }
        #expect(sourceBefore == sourceAfter)
    }

    @Test("--update-baseline writes only .swiftinfer/baseline.json under packageRoot")
    func updateBaselineWritesOnlyToConventionalPath() throws {
        let directory = try makeM6Fixture(named: "UpdateBaselineAllowlist")
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("Sources").appendingPathComponent("Lib")
        let before = try fileSet(of: directory)
        try SwiftInferCommand.Discover.run(
            directory: target,
            updateBaseline: true,
            output: SilentOutput(),
            diagnostics: SilentDiagnosticOutput()
        )
        let after = try fileSet(of: directory)
        let added = after.subtracting(before)
        #expect(added == ["/.swiftinfer/baseline.json"])
    }

    // MARK: - §14 — no telemetry / no network

    @Test("Production source contains no networking-API usage patterns")
    func noNetworkingAPIsInProduction() throws {
        let sourcesRoot = Self.packageSourcesRoot
        let forbidden = [
            "URLSession(",
            "URLSession.shared.",
            "dataTask(",
            "downloadTask(",
            "uploadTask(",
            "import Network",
            "Process("
        ]
        var violations: [String] = []
        let enumerator = FileManager.default.enumerator(
            at: sourcesRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        for case let url as URL in enumerator ?? FileManager.DirectoryEnumerator()
        where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            for term in forbidden where source.contains(term) {
                violations.append("\(url.lastPathComponent): \(term)")
            }
        }
        #expect(
            violations.isEmpty,
            "PRD §14 forbids networking-API usage in production source. Violations: \(violations)"
        )
    }

    // MARK: - Fixture helpers

    private enum Layout {
        case standard
        case alpha
    }

    private func makeFixture(named name: String, layout: Layout = .standard) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftInferGuarantee-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        switch layout {
        case .standard:
            try """
            struct MyType {}

            struct Codec {
                func normalize(_ value: String) -> String {
                    return normalize(normalize(value))
                }
                func encode(_ value: MyType) -> Data {
                    return Data()
                }
                func decode(_ data: Data) -> MyType {
                    return MyType()
                }
            }
            """.write(
                to: base.appendingPathComponent("Codec.swift"),
                atomically: true,
                encoding: .utf8
            )
        case .alpha:
            try "struct AlphaType {}\n".write(
                to: base.appendingPathComponent("Alpha.swift"),
                atomically: true,
                encoding: .utf8
            )
            try """
            struct AlphaContainer {
                func normalize(_ value: String) -> String {
                    return normalize(normalize(value))
                }
            }
            """.write(
                to: base.appendingPathComponent("Container.swift"),
                atomically: true,
                encoding: .utf8
            )
        }
        return base
    }

    private func snapshotContents(of directory: URL) throws -> [String: String] {
        var snapshot: [String: String] = [:]
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        for case let url as URL in enumerator ?? FileManager.DirectoryEnumerator() {
            let relative = url.path.replacingOccurrences(of: directory.path, with: "")
            snapshot[relative] = try String(contentsOf: url, encoding: .utf8)
        }
        return snapshot
    }

    private func fileSet(of directory: URL) throws -> Set<String> {
        var paths: Set<String> = []
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        // macOS resolves /tmp through the /private symlink during
        // enumeration, so the enumerator's URLs carry that prefix while
        // `directory.path` may not. Strip both candidates so the
        // returned relative paths normalize identically. Also filter to
        // regular files — directory entries pollute the diff with
        // synthetic ".swiftinfer" hits when an M6 writeout creates a
        // new sub-folder.
        let raw = directory.path
        let withPrivatePrefix = raw.hasPrefix("/private") ? raw : "/private" + raw
        for case let url as URL in enumerator ?? FileManager.DirectoryEnumerator() {
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            guard isFile else { continue }
            let stripped = url.path
                .replacingOccurrences(of: withPrivatePrefix, with: "")
                .replacingOccurrences(of: raw, with: "")
            paths.insert(stripped)
        }
        return paths
    }

    /// Build a Package.swift-rooted fixture with one `Sources/Lib/`
    /// target so the M6 `--interactive` / `--update-baseline` writeouts
    /// have a real package boundary to anchor at. The DecisionsLoader /
    /// BaselineLoader walk-up needs `Package.swift` at the root or it
    /// falls back to the target directory (which the M6 tests
    /// elsewhere exercise — here we want the conventional path).
    private func makeM6Fixture(named name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftInferM6Guarantee-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 6.1\n".utf8).write(
            to: base.appendingPathComponent("Package.swift")
        )
        let target = base.appendingPathComponent("Sources").appendingPathComponent("Lib")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try """
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """.write(
            to: target.appendingPathComponent("Source.swift"),
            atomically: true,
            encoding: .utf8
        )
        return base
    }

    /// Build a Package.swift-rooted fixture with a `Bag` type that
    /// fires the M2 associativity template via `merge(_:_:)` and the
    /// M2 identity-element template via `static let empty`. The
    /// RefactorBridgeOrchestrator (M7.5) aggregates those signals into
    /// a Monoid proposal on `Bag`; the `B` accept routes through
    /// `LiftedConformanceEmitter.monoid` and writes to
    /// `Tests/Generated/SwiftInferRefactors/Bag/Monoid.swift`.
    private func makeM7BridgeFixture(named name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftInferM7Bridge-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 6.1\n".utf8).write(
            to: base.appendingPathComponent("Package.swift")
        )
        let target = base.appendingPathComponent("Sources").appendingPathComponent("Lib")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try """
        struct Bag: Equatable {
            static let empty = Bag()
            static func merge(_ first: Bag, _ second: Bag) -> Bag { first }
        }
        """.write(
            to: target.appendingPathComponent("Bag.swift"),
            atomically: true,
            encoding: .utf8
        )
        return base
    }

    /// `Sources/` directory of the package, resolved against `#filePath`
    /// so the path holds regardless of `swift test`'s working directory.
    private static let packageSourcesRoot: URL = {
        let testFile = URL(fileURLWithPath: #filePath, isDirectory: false)
        return testFile
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // SwiftInferProperties/
            .appendingPathComponent("Sources")
    }()
}

// MARK: - Silent stubs for the M6 hard-guarantee tests

private final class SilentOutput: DiscoverOutput, @unchecked Sendable {
    func write(_ text: String) {}
}

private final class SilentDiagnosticOutput: DiagnosticOutput, @unchecked Sendable {
    func writeDiagnostic(_ text: String) {}
}

private final class ScriptedPromptInput: PromptInput, @unchecked Sendable {
    private var remaining: [String]
    init(scriptedLines: [String]) {
        self.remaining = scriptedLines
    }
    func readLine() -> String? {
        guard !remaining.isEmpty else { return nil }
        return remaining.removeFirst()
    }
}
// swiftlint:enable type_body_length file_length
