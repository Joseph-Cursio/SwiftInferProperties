import Foundation
import Testing
import SwiftInferCore
import SwiftInferTemplates

/// PRD v0.4 §4.1 + §5.7 / M5.6 acceptance-bar (a) integration suite
/// for `@Discoverable(group:)` recognition. Closes the bar by
/// exercising the recognize-only attribute detection (no runtime dep
/// on `ProtoLawMacro`) over real on-disk fixture corpora — scanner →
/// `FunctionPair.sharedDiscoverableGroup` → +35 signal end-to-end.
///
/// The unit-level path is covered by `DiscoverableAnnotationScannerTests`
/// (M5.1) + `RoundTripTemplateTests` (M5.1); this suite proves the
/// full discover pipeline picks up the annotation across multiple
/// files and lifts the round-trip suggestion's score correctly.
@Suite("@Discoverable(group:) — fixture-corpus integration (M5.6)")
struct DiscoverableGroupIntegrationTests {

    @Test("Same-group annotations lift a curated round-trip pair to Strong")
    func sameGroupLiftsCuratedPairToStrong() throws {
        let directory = try writeFixture(named: "DiscovSameGroup", file: "Source.swift", contents: """
        struct MyType {}
        struct Codec {
            @Discoverable(group: "codec")
            func encode(_ value: MyType) -> Data {
                return Data()
            }
            @Discoverable(group: "codec")
            func decode(_ data: Data) -> MyType {
                return MyType()
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = try TemplateRegistry.discover(in: directory)
        let roundTrip = try #require(suggestions.first { $0.templateName == "round-trip" })
        // 30 type + 40 curated encode/decode + 35 discoverable = 105 → Strong.
        #expect(roundTrip.score.total == 105)
        #expect(roundTrip.score.tier == .strong)
        let signal = try #require(
            roundTrip.score.signals.first { $0.kind == .discoverableAnnotation }
        )
        #expect(signal.weight == 35)
        #expect(signal.detail.contains("codec"))
    }

    @Test("Cross-file pair with matching group still fires the +35 signal")
    func crossFilePairWithMatchingGroupFiresSignal() throws {
        // Each half lives in its own file. Scanner walks files in
        // sorted-path order; the pair-finder unions across the corpus.
        let directory = try writeFixture(named: "DiscovCrossFile", files: [
            "Encoder.swift": """
            struct MyType {}
            struct Encoder {
                @Discoverable(group: "codec")
                func encode(_ value: MyType) -> Data {
                    return Data()
                }
            }
            """,
            "Decoder.swift": """
            struct Decoder {
                @Discoverable(group: "codec")
                func decode(_ data: Data) -> MyType {
                    return MyType()
                }
            }
            """
        ])
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = try TemplateRegistry.discover(in: directory)
        let roundTrip = try #require(suggestions.first { $0.templateName == "round-trip" })
        #expect(roundTrip.score.total == 105)
        let signal = try #require(
            roundTrip.score.signals.first { $0.kind == .discoverableAnnotation }
        )
        #expect(signal.detail.contains("codec"))
    }

    @Test("Mismatched groups skip the +35 signal (conservative-precision posture)")
    func mismatchedGroupsSkipSignal() throws {
        let directory = try writeFixture(named: "DiscovMismatch", file: "Source.swift", contents: """
        struct MyType {}
        struct Codec {
            @Discoverable(group: "codec")
            func encode(_ value: MyType) -> Data {
                return Data()
            }
            @Discoverable(group: "queue")
            func decode(_ data: Data) -> MyType {
                return MyType()
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = try TemplateRegistry.discover(in: directory)
        let roundTrip = try #require(suggestions.first { $0.templateName == "round-trip" })
        #expect(!roundTrip.score.signals.contains { $0.kind == .discoverableAnnotation })
        #expect(roundTrip.score.total == 70) // 30 type + 40 curated, no discoverable
    }

    @Test("One-sided annotation skips the +35 signal")
    func oneSidedAnnotationSkipsSignal() throws {
        let directory = try writeFixture(named: "DiscovOneSided", file: "Source.swift", contents: """
        struct MyType {}
        struct Codec {
            @Discoverable(group: "codec")
            func encode(_ value: MyType) -> Data {
                return Data()
            }
            func decode(_ data: Data) -> MyType {
                return MyType()
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = try TemplateRegistry.discover(in: directory)
        let roundTrip = try #require(suggestions.first { $0.templateName == "round-trip" })
        #expect(!roundTrip.score.signals.contains { $0.kind == .discoverableAnnotation })
    }

    @Test("Both-untagged pair stays at the M1-default 70 (no annotation needed)")
    func bothUntaggedStaysAtBaseline() throws {
        let directory = try writeFixture(named: "DiscovUntagged", file: "Source.swift", contents: """
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
        let suggestions = try TemplateRegistry.discover(in: directory)
        let roundTrip = try #require(suggestions.first { $0.templateName == "round-trip" })
        #expect(!roundTrip.score.signals.contains { $0.kind == .discoverableAnnotation })
        // 30 type + 40 curated encode/decode = 70 → Likely.
        #expect(roundTrip.score.total == 70)
    }

    @Test("Annotation lifts non-curated naming pair from Possible to Likely")
    func annotationLiftsNonCuratedPairAcrossTierBoundary() throws {
        // `transform/untransform` isn't in the curated inverse list, so
        // the pair scores 30 (type-symmetry only) — Possible. The +35
        // discoverable signal lifts it to 65 → Likely.
        let directory = try writeFixture(named: "DiscovTierLift", file: "Source.swift", contents: """
        struct MyType {}
        struct Pipeline {
            @Discoverable(group: "pipeline")
            func transform(_ value: MyType) -> Data {
                return Data()
            }
            @Discoverable(group: "pipeline")
            func untransform(_ data: Data) -> MyType {
                return MyType()
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = try TemplateRegistry.discover(in: directory)
        let roundTrip = try #require(suggestions.first { $0.templateName == "round-trip" })
        #expect(roundTrip.score.total == 65)
        #expect(roundTrip.score.tier == .likely)
    }

    // MARK: - Helpers

    private func writeFixture(named name: String, file: String, contents: String) throws -> URL {
        try writeFixture(named: name, files: [file: contents])
    }

    private func writeFixture(named name: String, files: [String: String]) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftInferDiscovIT-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        for (filename, contents) in files {
            try contents.write(
                to: base.appendingPathComponent(filename),
                atomically: true,
                encoding: .utf8
            )
        }
        return base
    }
}
