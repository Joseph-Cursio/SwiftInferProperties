import Foundation
import SwiftInferTestLifter
import Testing

/// PRD v0.4 §16 #1 hard-guarantee extension for TestLifter — the
/// "discover never writes to source files" guarantee TemplateEngine
/// already passes is widened in M1.6 to cover the new TestLifter scan
/// path. Snapshots the source-file tree before and after
/// `TestLifter.discover(in:)` and asserts byte-identical equality.
@Suite("TestLifter — PRD §16 #1 source-tree-immutable (M1.6)")
struct TestLifterHardGuaranteeTests {

    @Test("TestLifter.discover does not modify source files")
    func sourceTreeStableAfterDiscover() throws {
        let directory = try makeFixtureWithRoundTripTest()
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = try snapshot(directory: directory)
        _ = try TestLifter.discover(in: directory)
        let after = try snapshot(directory: directory)
        #expect(before == after, "TestLifter.discover modified the source tree")
    }

    @Test("TestLifter.discover does not create new files")
    func noNewFilesAfterDiscover() throws {
        let directory = try makeFixtureWithRoundTripTest()
        defer { try? FileManager.default.removeItem(at: directory) }
        let before = try fileSet(in: directory)
        _ = try TestLifter.discover(in: directory)
        let after = try fileSet(in: directory)
        #expect(before == after, "TestLifter.discover created or removed files")
    }

    // MARK: - Fixture + snapshotting

    private func makeFixtureWithRoundTripTest() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftInferTestLifterHG-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try """
        import XCTest

        final class CodecTests: XCTestCase {
            func testRoundTrip() {
                let original = 42
                let encoded = encode(original)
                let decoded = decode(encoded)
                XCTAssertEqual(original, decoded)
            }
        }
        """.write(
            to: base.appendingPathComponent("CodecTests.swift"),
            atomically: true,
            encoding: .utf8
        )
        try """
        import XCTest

        @Test func swiftTestingRoundTrip() {
            let original = 42
            #expect(decode(encode(original)) == original)
        }
        """.write(
            to: base.appendingPathComponent("OtherTests.swift"),
            atomically: true,
            encoding: .utf8
        )
        return base
    }

    private func snapshot(directory: URL) throws -> [String: Data] {
        var snap: [String: Data] = [:]
        for url in try fileSet(in: directory) {
            let relative = String(url.path.dropFirst(directory.path.count))
            snap[relative] = try Data(contentsOf: url)
        }
        return snap
    }

    private func fileSet(in directory: URL) throws -> [URL] {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }
}
