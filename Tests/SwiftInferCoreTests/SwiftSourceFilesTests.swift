import Foundation
@testable import SwiftInferCore
import Testing

/// Regression guards for `SwiftSourceFiles.sorted(in:)` — the shared
/// directory enumeration every discoverer routes through. The Mastermind
/// dogfood found that the original symlink fix (commit 5b0c4c9) was applied
/// only to `FunctionScanner`, so `discover` descended a symlinked
/// `Sources/<target>` while `discover-reducers` (ViewModelDiscoverer /
/// ReducerDiscoverer / RuleVisitorDiscoverer) still reported zero carriers.
/// Centralizing here means the symlinked-root behavior is tested once and
/// every discoverer inherits it.
@Suite("SwiftSourceFiles — shared directory enumeration")
struct SwiftSourceFilesTests {

    private struct Tree {
        let base: URL
        let real: URL
        let link: URL
    }

    private func write(_ body: String, to url: URL) throws {
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Builds `base/real/` with `A.swift` + `Nested/B.swift` + a `README.md`
    /// that must be ignored, plus a `base/link` symlink to `real`.
    private func makeTree() throws -> Tree {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("swiftsourcefiles-\(UUID().uuidString)")
        let real = base.appendingPathComponent("real")
        let nested = real.appendingPathComponent("Nested")
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try write("func a() {}\n", to: real.appendingPathComponent("A.swift"))
        try write("func b() {}\n", to: nested.appendingPathComponent("B.swift"))
        try write("ignore\n", to: real.appendingPathComponent("README.md"))
        let link = base.appendingPathComponent("link")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: real)
        return Tree(base: base, real: real, link: link)
    }

    @Test("Recurses a real directory, .swift only, sorted by path")
    func enumeratesRealDirectory() throws {
        let tree = try makeTree()
        defer { try? FileManager.default.removeItem(at: tree.base) }

        let names = SwiftSourceFiles.sorted(in: tree.real).map(\.lastPathComponent)
        #expect(names == ["A.swift", "B.swift"])
    }

    @Test("Descends a symlinked root (regression — was [])")
    func descendsSymlinkedRoot() throws {
        let tree = try makeTree()
        defer { try? FileManager.default.removeItem(at: tree.base) }

        let viaReal = SwiftSourceFiles.sorted(in: tree.real).map(\.lastPathComponent)
        let viaLink = SwiftSourceFiles.sorted(in: tree.link).map(\.lastPathComponent)
        #expect(viaReal == ["A.swift", "B.swift"])
        #expect(viaLink == ["A.swift", "B.swift"])
    }

    @Test("Missing directory yields an empty list (no throw)")
    func missingDirectoryIsEmpty() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        #expect(SwiftSourceFiles.sorted(in: missing).isEmpty)
    }

    /// The exact user-facing path the Mastermind dogfood exercised:
    /// `discover-reducers` must descend a symlinked `Sources/<target>` and
    /// recognize an `@Observable` carrier living in a nested subdirectory.
    @Test("ViewModelDiscoverer descends a symlinked root")
    func viewModelDiscovererDescendsSymlink() throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("vm-symlink-\(UUID().uuidString)")
        let real = base.appendingPathComponent("real").appendingPathComponent("Domain")
        try fileManager.createDirectory(at: real, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }
        try write(
            """
            import Observation
            @Observable final class Game {
                var secret = 0
                func makeNewSecret() { secret += 1 }
            }
            """,
            to: real.appendingPathComponent("Game.swift")
        )
        let link = base.appendingPathComponent("link")
        try fileManager.createSymbolicLink(
            at: link,
            withDestinationURL: base.appendingPathComponent("real")
        )

        let viaLink = try ViewModelDiscoverer.discover(directory: link)
        #expect(viaLink.map(\.typeName) == ["Game"])
    }
}
