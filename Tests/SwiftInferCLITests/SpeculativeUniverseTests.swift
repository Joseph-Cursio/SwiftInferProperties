import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// **A speculative widening is judged under the baseline's construction universe.**
///
/// `suggest-refactors --speculative` reports `snapshot − baseline`: the laws visible in a patched
/// copy and not in the real tree. The baseline is judged under the table its scan builds — every
/// production file of the package — so a copy of `Sources/` alone is judged under a smaller one: a
/// refuting type outside `Sources/` vetoes laws in the baseline and is absent from the copy, and
/// the widening is credited with them. Each fixture below widens a `private` helper that no law is
/// about, so the only correct answer is `noLawGained`.
@Suite("Speculative refactors — the snapshot keeps the baseline's universe")
struct SpeculativeUniverseTests {

    private struct Quiet: DiagnosticOutput {
        func writeDiagnostic(_: String) { /* no-op */ }
    }

    private static func makePackage(_ files: [String: String]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("speculative-universe-\(UUID().uuidString)")
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    /// Run with the root as the CLI spells it — the working directory's own spelling, which
    /// `getcwd` gives with `/private` — since the runner mirrors each file by its path below the
    /// root it was given, and its file walk yields `/private/var/…` for a root given as `/var/…`.
    private static func proposals(for root: URL) throws -> [SpeculativeProposal] {
        let path = root.path.hasPrefix("/var/") ? "/private" + root.path : root.path
        return try SpeculativeRefactorRunner.run(
            options: .init(packageRoot: URL(fileURLWithPath: path), maxCandidates: 4, budget: "small"),
            diagnostics: Quiet()
        )
    }

    private static let identityItem = """
    import Foundation

    public struct Item: Equatable {
        public let id = UUID()
        public var n: Int

        public init(n: Int) {
            self.n = n
        }
    }
    """

    /// The review's P3: `Core` is a custom-path target, outside `Sources/`, and its `Item` mints a
    /// `UUID`, so the real tree vetoes `normalize`'s and `canonicalize`'s laws.
    @Test("a refuting type in a custom-path target leaves an unrelated widening with no law gained")
    func customPathTargetStaysInTheSnapshot() throws {
        let root = try Self.makePackage([
            "Package.swift": """
            // swift-tools-version: 5.9
            import PackageDescription
            let package = Package(
                name: "P3",
                targets: [.target(name: "Core", path: "Core"), .target(name: "Lib", dependencies: ["Core"])]
            )
            """,
            "Core/Item.swift": Self.identityItem,
            "Sources/Lib/Ops.swift": """
            import Core

            public enum Ops {
                public static func normalize(_ item: Item) -> Item { Item(n: abs(item.n)) }
                public static func canonicalize(_ item: Item) -> Item { Item(n: abs(item.n)) }
                private static func helper(_ x: Int) -> Int { x }
            }
            """
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let proposals = try Self.proposals(for: root)
        #expect(proposals.map(\.path) == ["Sources/Lib/Ops.swift"], "the fixture's one candidate was not examined")
        #expect(proposals.map(\.verdict) == [.noLawGained], """
        the widening of `helper` was credited with laws the real tree vetoes: \
        \(proposals.map(\.lawDescription))
        """)
    }

    /// The `Examples/` namesake package: `Examples/` is production by the shared rule, and its
    /// `Item` refutes `Sources/`'s by name in the baseline.
    private static let namesakePackage = [
        "Package.swift": """
        // swift-tools-version: 5.9
        import PackageDescription
        let package = Package(name: "Spec", targets: [.target(name: "Lib")])
        """,
        "Examples/Gen/Item.swift": """
        import Foundation

        struct Item {
            let id = UUID()
            var n: Int = 0
        }
        """,
        "Sources/Lib/Item.swift": """
        public struct Item: Equatable {
            public var n: Int
            public init(n: Int) { self.n = n }
        }
        public func normalized(_ item: Item) -> Item { Item(n: abs(item.n)) }
        public func canonicalize(_ item: Item) -> Item { Item(n: item.n % 10) }
        public func merge(_ lhs: Item, _ rhs: Item) -> Item { Item(n: max(lhs.n, rhs.n)) }
        private func clamp(_ value: Int) -> Int { min(max(value, 0), 100) }
        public func clamped(_ value: Int) -> Int { clamp(value) }
        """
    ]

    /// The over-refuting namesake: `Examples/` is production by the shared rule, and its `Item`
    /// refutes `Sources/`'s by name in the baseline. The snapshot must see it too.
    @Test("an Examples/ namesake leaves an unrelated widening with no law gained")
    func examplesNamesakeStaysInTheSnapshot() throws {
        let root = try Self.makePackage(Self.namesakePackage)
        defer { try? FileManager.default.removeItem(at: root) }
        let proposals = try Self.proposals(for: root)
        #expect(proposals.map(\.path) == ["Sources/Lib/Item.swift"], "the fixture's one candidate was not examined")
        #expect(proposals.map(\.verdict) == [.noLawGained], """
        the widening of `clamp` was credited with laws the real tree vetoes: \
        \(proposals.map(\.lawDescription))
        """)
    }

    /// What the copy holds: every universe member outside `Sources/`, at its package-relative path,
    /// and nothing the universe leaves out — a test target, an uncompiled nested package.
    @Test("the snapshot copies exactly the universe outside Sources/")
    func snapshotCopiesTheUniverse() throws {
        let root = try Self.makePackage([
            "Package.swift": "// swift-tools-version: 5.9\n",
            "Core/Item.swift": Self.identityItem,
            "Examples/Gen/main.swift": "print(1)",
            "Tests/LibTests/LibTests.swift": "struct LibTests {}",
            "Demo/Package.swift": "// swift-tools-version: 5.9\n",
            "Demo/Sources/Demo/main.swift": "print(2)",
            "Sources/Lib/Lib.swift": "public func f() -> Int { 1 }"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = SpeculativeRefactorRunner.universeOutsideSources(of: root)
        #expect(outside == ["Core/Item.swift", "Examples/Gen/main.swift"])
        let snapshot = try SpeculativeRefactorRunner.snapshotTree(
            of: root,
            replacing: root.appendingPathComponent("Sources/Lib/Lib.swift").path,
            with: "public func f() -> Int { 2 }"
        )
        defer { try? FileManager.default.removeItem(at: snapshot.root) }
        let original = ConstructionUniverse.files(forScanOf: root.appendingPathComponent("Sources")).map(\.relativePath)
        let copied = ConstructionUniverse.files(forScanOf: snapshot.sources).map(\.relativePath)
        #expect(copied == original, "the snapshot's universe differs from the baseline's")
    }

    /// The review's `sip#2` / `robustness#2`: one universe `.swift` outside `Sources/` that cannot
    /// be read — a dangling link, a mode-000 file — threw for every candidate's snapshot, so the run
    /// reported `No widenable candidates.` Neither arm's table has such a file (`PackagePurity`
    /// skips it), so the snapshot skips it too, and the candidate gets its verdict.
    @Test("an unreadable universe file outside Sources/ is skipped, and the candidate still judged")
    func unreadableUniverseFileIsSkipped() throws {
        var files = Self.namesakePackage
        files["Examples/Fine.swift"] = "let fine = 1"
        files["Examples/Locked.swift"] = "let locked = 1"
        let root = try Self.makePackage(files)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("Examples/Gone.swift").path,
            withDestinationPath: "/nonexistent/Gone.swift"
        )
        let locked = root.appendingPathComponent("Examples/Locked.swift").path
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked)
        #expect(FileManager.default.contents(atPath: locked) == nil, "a mode-000 file was readable — running as root?")
        let outside = SpeculativeRefactorRunner.universeOutsideSources(of: root)
        #expect(outside.contains("Examples/Gone.swift") && outside.contains("Examples/Locked.swift"), "\(outside)")

        let proposals = try Self.proposals(for: root)
        #expect(proposals.map(\.path) == ["Sources/Lib/Item.swift"], "the candidate was dropped")
        #expect(proposals.map(\.verdict) == [.noLawGained])
    }

    /// A snapshot that fails part-way is removed, rather than left in the temporary directory — the
    /// copy is made before anything that can throw.
    @Test("a snapshot that fails leaves nothing behind")
    func failedSnapshotIsRemoved() throws {
        let root = try Self.makePackage(Self.namesakePackage)
        defer { try? FileManager.default.removeItem(at: root) }
        let scratch = try Self.makePackage([:])
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        // The patched file's directory exists in neither tree, so its write throws last.
        #expect(throws: (any Error).self) {
            try SpeculativeRefactorRunner.snapshotTree(
                of: root,
                replacing: root.appendingPathComponent("Sources/Missing/X.swift").path,
                with: "let x = 1",
                in: scratch
            )
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.path).isEmpty, "a failed snapshot leaked")
        // The control: a snapshot that succeeds is the caller's to remove.
        let snapshot = try SpeculativeRefactorRunner.snapshotTree(
            of: root,
            replacing: root.appendingPathComponent("Sources/Lib/Item.swift").path,
            with: "public struct Item {}",
            in: scratch
        )
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.path) == [snapshot.root.lastPathComponent])
    }
}
