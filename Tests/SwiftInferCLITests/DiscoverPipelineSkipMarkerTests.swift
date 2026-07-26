import Foundation
@testable import SwiftInferCLI
import Testing

/// `// swiftinfer: skip <hash>` suppression, end-to-end through the discover pipeline.
///
/// Split out of `DiscoverPipelineTests` on the file-length cap. They belong together anyway:
/// every test here asserts on the SAME fixture shapes as the discovery tests next door and
/// differs only by the marker comment, so keeping them adjacent to the unmarked cases they
/// mirror was making both suites harder to read, not easier.
@Suite("Discover pipeline — skip markers")
struct DiscoverPipelineSkipMarkerTests {

    @Test("Skip marker in source suppresses the matching suggestion")
    func skipMarkerSuppressesSuggestion() throws {
        // Identity for: idempotence|Sanitizer.normalize(_:)|(String)->String
        let directory = try writeDPFixture(name: "SkipMarker", contents: """
        // swiftinfer: skip 0xA1C9DEC1AEA2791C
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            output: recording
        )
        #expect(recording.text == "0 suggestions.")
    }

    @Test("Skip marker for an unrelated hash leaves the suggestion in place")
    func skipMarkerUnrelatedHashIgnored() throws {
        let directory = try writeDPFixture(name: "SkipUnrelated", contents: """
        // swiftinfer: skip 0xDEADBEEF12345678
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            output: recording
        )
        #expect(recording.text.contains("Template: idempotence"))
        // 30 type + 40 curated + 20 self-comp + 5 value-semantic = 95.
        #expect(recording.text.contains("Score:    95 (Strong)"))
    }

    @Test("Round-trip skip marker suppresses the pair regardless of orientation")
    func skipMarkerRoundTrip() throws {
        // Identity for: round-trip|Codec.decode(_:)|(Data)->MyType|Codec.encode(_:)|(MyType)->Data
        let directory = try writeDPFixture(name: "SkipRoundTrip", contents: """
        // swiftinfer: skip 0x4C3618BEBBE59391
        struct MyType {}
        struct Codec {
            func encode(_ value: MyType) -> Data {
                return Data()
            }
            func decode(_ data: Data) -> MyType {
                return MyType()
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            output: recording
        )
        #expect(!recording.text.contains("Template: round-trip"))
    }
}
