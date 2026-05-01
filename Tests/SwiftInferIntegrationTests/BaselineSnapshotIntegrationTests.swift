import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// PRD v0.4 §5.8 M6 / M6 plan §M6.2 acceptance — the canonical
/// "discover → snapshot to baseline.json → reload" round-trip.
/// Proves the M6.5 `discover --update-baseline` pipeline (which
/// will compose these three steps inside `Discover.run`) gets a
/// stable on-disk snapshot back from BaselineLoader's writer + reader.
@Suite("Baseline — discover → snapshot → reload integration (M6.2)")
struct BaselineSnapshotIntegrationTests {

    @Test
    func discoverOutputSnapshotsCleanlyAsBaseline() throws {
        let directory = try makeFixtureDirectory(name: "DiscoverSnapshot")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePackageManifest(in: directory)
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
            to: directory.appendingPathComponent("Codec.swift"),
            atomically: true,
            encoding: .utf8
        )

        let suggestions = try TemplateRegistry.discover(in: directory)
        #expect(!suggestions.isEmpty, "Fixture must produce ≥1 suggestion")
        let entries = suggestions.map { suggestion in
            BaselineEntry(
                identityHash: suggestion.identity.normalized,
                template: suggestion.templateName,
                scoreAtSnapshot: suggestion.score.total,
                tier: suggestion.score.tier
            )
        }
        let snapshot = Baseline(entries: entries)
        let baselinePath = directory
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("baseline.json")
        try BaselineLoader.write(snapshot, to: baselinePath)

        let reloaded = BaselineLoader.load(startingFrom: directory)
        #expect(reloaded.baseline == snapshot)
        // Every discovered identity is contained — the canonical
        // "is this identity in the baseline?" predicate works for
        // the next M6.5 drift-diff run.
        for suggestion in suggestions {
            #expect(reloaded.baseline.contains(identityHash: suggestion.identity.normalized))
        }
    }

    @Test
    func reSnapshotOfTheSameCorpusProducesByteIdenticalBaseline() throws {
        // Discover is byte-stable across runs (PRD §16 #6); snapshot
        // building is a pure transform of the suggestion list; so
        // re-running the snapshot pipeline against unchanged source
        // must produce a byte-identical baseline.json. Proof against
        // the M6.5 baseline-update operation introducing nondeterminism.
        let directory = try makeFixtureDirectory(name: "DiscoverReSnapshot")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writePackageManifest(in: directory)
        try """
        struct Codec {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """.write(
            to: directory.appendingPathComponent("Codec.swift"),
            atomically: true,
            encoding: .utf8
        )
        let baselinePath = directory
            .appendingPathComponent(".swiftinfer")
            .appendingPathComponent("baseline.json")

        try snapshot(into: baselinePath, in: directory)
        let firstBytes = try Data(contentsOf: baselinePath)
        try snapshot(into: baselinePath, in: directory)
        let secondBytes = try Data(contentsOf: baselinePath)
        #expect(firstBytes == secondBytes)
    }

    // MARK: - Helpers

    private func snapshot(into path: URL, in directory: URL) throws {
        let suggestions = try TemplateRegistry.discover(in: directory)
        let entries = suggestions.map { suggestion in
            BaselineEntry(
                identityHash: suggestion.identity.normalized,
                template: suggestion.templateName,
                scoreAtSnapshot: suggestion.score.total,
                tier: suggestion.score.tier
            )
        }
        try BaselineLoader.write(Baseline(entries: entries), to: path)
    }

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("BaselineSnapshotIT-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writePackageManifest(in directory: URL) throws {
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: directory.appendingPathComponent("Package.swift"))
    }
}
