import Foundation
import SwiftInferTestLifter
import Testing

/// PRD v0.4 §16 #1 hard-guarantee extension for TestLifter — the
/// "discover never writes to source files" guarantee TemplateEngine
/// already passes is widened in M1.6 to cover the new TestLifter scan
/// path. Snapshots the source-file tree before and after
/// `TestLifter.discover(in:)` and asserts byte-identical equality.
///
/// R1.1.d extends the suite with an explicit §16 #2 "never deletes
/// tests" assertion: TestLifter reads existing tests; it never
/// overwrites them with lifted properties. The existing
/// "no new files" test already covers the file-set delta direction;
/// R1.1.d adds the per-test-method survival assertion that pins the
/// "no in-place rewrite" half of the contract.
@Suite("TestLifter — PRD §16 #1 + #2 source-tree-immutable (M1.6 + R1.1.d)")
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

    /// PRD §16 #2 — "TestLifter reads existing tests; it never
    /// overwrites them. Lifted properties are emitted as new files,
    /// never replacements." This test exercises the lifted-suggestion
    /// path (the round-trip pattern in the fixture is exactly what
    /// `AssertAfterTransformDetector` lifts) and asserts that all
    /// pre-existing test files survive AND each originally-declared
    /// test method is still textually present after discover. The
    /// per-method survival check pins the "no in-place rewrite" half
    /// of the contract — a hypothetical regression where TestLifter
    /// rewrites the file to add a lifted property would dissolve the
    /// XCTest+Swift Testing methods even if the file count holds.
    @Test("TestLifter.discover never deletes existing tests (PRD §16 #2)")
    func existingTestsSurviveDiscover() throws {
        let directory = try makeFixtureWithRoundTripTest()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalFiles = try fileSet(in: directory)
        let originalCount = originalFiles.count

        // Drive the lifted-suggestion path — the fixture's
        // testRoundTrip + swiftTestingRoundTrip both match
        // AssertAfterTransformDetector, so this discover call exercises
        // the lift (not just the no-op scan). A regression that wrote
        // lifted output back into the source files would modify or
        // delete them — both directions are caught below.
        let artifacts = try TestLifter.discover(in: directory)
        #expect(
            !artifacts.liftedSuggestions.isEmpty,
            "Fixture should produce at least one lifted suggestion to exercise §16 #2"
        )

        let surviving = try fileSet(in: directory)
        #expect(
            surviving.count == originalCount,
            """
            TestLifter.discover deleted or replaced a source test file \
            (before=\(originalCount), after=\(surviving.count))
            """
        )
        #expect(
            Set(surviving.map(\.lastPathComponent)) == Set(originalFiles.map(\.lastPathComponent)),
            "TestLifter.discover changed the set of source test file names"
        )

        // Per-method survival: each originally-declared test method
        // must still be textually present in its file. Catches the
        // "TestLifter rewrites the file to splice in a lifted property
        // alongside the original test" failure mode. M2.4 widens the
        // per-method survival pin to all three pattern files (round-trip,
        // idempotence, commutativity) — a regression in any M2 detector
        // path that wrote back to source would surface here.
        try assertMethodSurvived(
            directory: directory,
            file: "CodecTests.swift",
            decl: "func testRoundTrip()"
        )
        try assertMethodSurvived(
            directory: directory,
            file: "OtherTests.swift",
            decl: "func swiftTestingRoundTrip()"
        )
        try assertMethodSurvived(
            directory: directory,
            file: "NormalizerTests.swift",
            decl: "func testIdempotent()"
        )
        try assertMethodSurvived(
            directory: directory,
            file: "MergerTests.swift",
            decl: "func testCommutative()"
        )
    }

    private func assertMethodSurvived(
        directory: URL,
        file: String,
        decl: String
    ) throws {
        let body = try String(
            contentsOf: directory.appendingPathComponent(file),
            encoding: .utf8
        )
        #expect(
            body.contains(decl),
            "TestLifter.discover removed or rewrote the \(decl) declaration in \(file)"
        )
    }

    // MARK: - Fixture + snapshotting

    private func makeFixtureWithRoundTripTest() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftInferTestLifterHG-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try writeRoundTripFixtureFiles(in: base)
        // M2.4: extend the fixture with idempotence + commutativity test
        // methods so the §16 #1 + #2 guarantees re-validate against the
        // M2 detector paths, not just M1's round-trip path.
        try writeM2DetectorFixtureFiles(in: base)
        return base
    }

    private func writeRoundTripFixtureFiles(in base: URL) throws {
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
    }

    private func writeM2DetectorFixtureFiles(in base: URL) throws {
        try """
        import XCTest

        final class NormalizerTests: XCTestCase {
            func testIdempotent() {
                let s = "hello"
                let once = normalize(s)
                let twice = normalize(once)
                XCTAssertEqual(once, twice)
            }
        }
        """.write(
            to: base.appendingPathComponent("NormalizerTests.swift"),
            atomically: true,
            encoding: .utf8
        )
        try """
        import XCTest

        final class MergerTests: XCTestCase {
            func testCommutative() {
                let a = [1, 2]
                let b = [3, 4]
                XCTAssertEqual(merge(a, b), merge(b, a))
            }
        }
        """.write(
            to: base.appendingPathComponent("MergerTests.swift"),
            atomically: true,
            encoding: .utf8
        )
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
