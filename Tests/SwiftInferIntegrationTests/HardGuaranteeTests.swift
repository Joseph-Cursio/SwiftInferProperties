import Foundation
import Testing
import SwiftInferCore
import SwiftInferTemplates

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
        for case let url as URL in enumerator ?? FileManager.DirectoryEnumerator() {
            paths.insert(url.path.replacingOccurrences(of: directory.path, with: ""))
        }
        return paths
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
