import Foundation
import Testing
@testable import SwiftInferCore

@Suite("SkipMarkerScanner — `// swiftinfer: skip <hash>` extraction")
struct SkipMarkerScannerTests {

    @Test("Empty source produces no hashes")
    func emptySource() {
        #expect(SkipMarkerScanner.skipHashes(in: "").isEmpty)
    }

    @Test("Plain swift source with no markers produces no hashes")
    func sourceWithoutMarkers() {
        let source = """
        struct S {
            // a regular comment
            func f() -> Int { 1 }
        }
        """
        #expect(SkipMarkerScanner.skipHashes(in: source).isEmpty)
    }

    @Test("0x-prefixed marker is captured")
    func zeroXPrefixedMarker() {
        let source = """
        // swiftinfer: skip 0xABCD1234
        struct S {}
        """
        #expect(SkipMarkerScanner.skipHashes(in: source) == ["ABCD1234"])
    }

    @Test("Marker without 0x prefix is also captured")
    func markerWithoutPrefix() {
        let source = """
        // swiftinfer: skip abcd1234
        """
        #expect(SkipMarkerScanner.skipHashes(in: source) == ["ABCD1234"])
    }

    @Test("Lowercase hash is normalized to uppercase")
    func lowercaseNormalized() {
        let source = "// swiftinfer: skip 0xdeadbeef"
        #expect(SkipMarkerScanner.skipHashes(in: source) == ["DEADBEEF"])
    }

    @Test("Multiple markers across the source are all captured")
    func multipleMarkers() {
        let source = """
        // swiftinfer: skip 0xAAAA
        struct A {}

        // swiftinfer: skip 0xBBBB
        struct B {}
        """
        let hashes = SkipMarkerScanner.skipHashes(in: source)
        #expect(hashes == ["AAAA", "BBBB"])
    }

    @Test("Indented marker is still captured")
    func indentedMarker() {
        let source = "        // swiftinfer: skip 0xCCCC"
        #expect(SkipMarkerScanner.skipHashes(in: source) == ["CCCC"])
    }

    @Test("Marker with trailing content captures only the hash token")
    func trailingContentIgnored() {
        let source = "// swiftinfer: skip 0xDDDD some explanation"
        #expect(SkipMarkerScanner.skipHashes(in: source) == ["DDDD"])
    }

    @Test("Malformed marker (non-hex) is rejected, not treated as wildcard")
    func malformedRejected() {
        let source = """
        // swiftinfer: skip notahash
        // swiftinfer: skip
        """
        #expect(SkipMarkerScanner.skipHashes(in: source).isEmpty)
    }

    @Test("Doc comments and triple-slash comments are not markers")
    func nonDoubleSlashCommentsIgnored() {
        let source = """
        /// swiftinfer: skip 0xEEEE
        /* swiftinfer: skip 0xFFFF */
        """
        #expect(SkipMarkerScanner.skipHashes(in: source).isEmpty)
    }

    @Test("Directory scan unions markers across files in sorted-path order")
    func directoryScanUnion() throws {
        let directory = try makeFixture(files: [
            ("a.swift", "// swiftinfer: skip 0x1111\nstruct A {}"),
            ("b.swift", "// swiftinfer: skip 0x2222\nstruct B {}")
        ])
        defer { try? FileManager.default.removeItem(at: directory) }
        let hashes = try SkipMarkerScanner.skipHashes(in: directory)
        #expect(hashes == ["1111", "2222"])
    }

    @Test("Directory scan ignores non-Swift files")
    func directoryScanIgnoresNonSwift() throws {
        let directory = try makeFixture(files: [
            ("a.swift", "// swiftinfer: skip 0x3333"),
            ("readme.md", "// swiftinfer: skip 0x9999")
        ])
        defer { try? FileManager.default.removeItem(at: directory) }
        let hashes = try SkipMarkerScanner.skipHashes(in: directory)
        #expect(hashes == ["3333"])
    }

    private func makeFixture(files: [(String, String)]) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkipMarker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        for (name, contents) in files {
            try contents.write(
                to: base.appendingPathComponent(name),
                atomically: true,
                encoding: .utf8
            )
        }
        return base
    }
}
