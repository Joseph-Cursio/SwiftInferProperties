import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// **The construction table reaches what `discover` prints**, not only the scanner's summaries.
///
/// `discover --effect-annotations` advises `/// @lint.effect pure` for every summary whose
/// `isInferredPure` holds. Before construction facts were wired in, `make` below was advised pure
/// while the `Item` it returns mints a `UUID` in another target — the motivating case
/// (SwiftLintRuleStudio's `generateRecommendations`, `analyze`). This drives the CLI's own pipeline
/// entry, `collectVisibleSuggestions`, over a `--target`-shaped directory, so a table built and
/// dropped anywhere on the way is caught here.
@Suite("Construction facts — through discover's pipeline")
struct ConstructionFactsPipelineTests {

    private struct SilentDiagnostics: DiagnosticOutput {
        func writeDiagnostic(_: String) { /* no-op */ }
    }

    /// A package: `files` by root-relative path, with a bare root manifest unless `files` gives one.
    private static func makePackage(_ files: [String: String]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("construction-pipeline-\(UUID().uuidString)")
        let manifest = ["Package.swift": "// swift-tools-version:5.9\n"]
        for (path, text) in files.merging(manifest, uniquingKeysWith: { given, _ in given }) {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    private static let item = "public struct Item { public let id = UUID(); public let title: String }"
    private static let logic = """
    public func make(_ title: String) -> Item { Item(title: title) }
    public func double(_ value: Int) -> Int { value * 2 }
    """

    @Test("a sibling target's identity-minting type withdraws the pure advice from its constructor")
    func siblingConstructionWithdrawsTheAdvice() throws {
        let root = try Self.makePackage([
            "Sources/Model/Item.swift": Self.item,
            "Sources/Logic/Logic.swift": Self.logic
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let pipeline = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: root.appendingPathComponent("Sources/Logic"),
            includePossible: true,
            diagnostics: SilentDiagnostics()
        )
        let make = try #require(pipeline.summaries.first { $0.name == "make" })
        #expect(make.purityVerdict == .refuted)

        let advised = Set(EffectAnnotationAdvice.adviceList(from: pipeline.summaries).map(\.displayName))
        #expect(advised.contains { $0.hasPrefix("double") }, "control: the advisory still runs")
        #expect(!advised.contains { $0.hasPrefix("make") }, """
        `make` is advised `/// @lint.effect pure` while the `Item` it constructs mints a UUID — \
        the table did not reach the pipeline. Advised: \(advised.sorted())
        """)
    }

    private static let modelManifest = "// swift-tools-version:5.9\nimport PackageDescription\n"

    private static func touch(_ path: String, in root: URL) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(3_600)],
            ofItemAtPath: root.appendingPathComponent(path).path
        )
    }

    private static func makeIndex(in root: URL) throws -> URL {
        let index = root.appendingPathComponent("index.json")
        try Data("{}".utf8).write(to: index)
        return index
    }

    /// A verdict now depends on files outside `Sources/`, so the index's staleness probe must
    /// watch them: here, a nested local package the root compiles — its manifest names it by path —
    /// whose type refutes a constructor in `Sources/`.
    @Test("an edit to a universe file outside Sources/ makes the index stale")
    func universeEditOutsideSourcesIsStale() throws {
        let root = try Self.makePackage([
            "Package.swift": """
            // swift-tools-version:5.9
            import PackageDescription
            let package = Package(name: "Root", dependencies: [.package(path: "Packages/Model")])
            """,
            "Packages/Model/Package.swift": Self.modelManifest,
            "Packages/Model/Sources/Model/Item.swift": Self.item,
            "Sources/Logic/Logic.swift": Self.logic
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let corpus = try FunctionScanner.scanCorpus(directory: root.appendingPathComponent("Sources/Logic"))
        #expect(
            corpus.summaries.first { $0.name == "make" }?.purityVerdict == .refuted,
            "the root compiles the nested package, so its `Item` is in the universe and decides `make`"
        )

        let index = try Self.makeIndex(in: root)
        #expect(VerifyHarness.isStale(indexPath: index, packageRoot: root) == false, "control: fresh")
        try Self.touch("Packages/Model/Sources/Model/Item.swift", in: root)
        #expect(VerifyHarness.isStale(indexPath: index, packageRoot: root), """
        A universe file outside Sources/ changed and the index still reads fresh — verify would \
        run on a verdict the construction facts no longer support.
        """)
    }

    /// The converse, and the critic's scenario: a nested package the root never names is not
    /// compiled by it, so its namesake neither refutes nor is watched.
    @Test("a nested package the root does not compile neither refutes nor makes the index stale")
    func unreferencedNestedPackageIsNotWatched() throws {
        let root = try Self.makePackage([
            "Demo/Package.swift": Self.modelManifest,
            "Demo/Sources/Demo/Item.swift": Self.item,
            "Sources/Logic/Logic.swift": Self.logic
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let corpus = try FunctionScanner.scanCorpus(directory: root.appendingPathComponent("Sources/Logic"))
        #expect(
            corpus.summaries.first { $0.name == "make" }?.purityVerdict == .pure,
            "a package the root never compiles refuted `make` through a namesake"
        )

        let index = try Self.makeIndex(in: root)
        try Self.touch("Demo/Sources/Demo/Item.swift", in: root)
        #expect(
            VerifyHarness.isStale(indexPath: index, packageRoot: root) == false,
            "an edit outside the universe made the index stale"
        )
        // But the manifest that would bring it in is watched: naming `Demo` by path moves the bound.
        try Self.touch("Package.swift", in: root)
        #expect(VerifyHarness.isStale(indexPath: index, packageRoot: root), "a root manifest edit read fresh")
    }
}
