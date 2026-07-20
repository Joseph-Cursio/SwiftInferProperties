import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// The **live-index** measured proof of codable-round-trip — the productionized
/// path (`verify --all-from-index --corpus-module`), where value generation comes
/// from `DerivationStrategist` (not a hand-written expression). Packages the
/// `codable-roundtrip-live-corpus` module, reindexes it, and surveys every pick:
///
///   - `Meters` (faithful custom codec) → measured-bothPass
///   - `OffByOne` (encode stores value+1 — an asymmetric codec) → measured-defaultFails
///
/// Both are Int-field structs with a public memberwise init (strategist-
/// generatable, NaN-free) and a hand-written `Codable` conformance. Spawns real
/// `swift build`s resolving the algebraic deps + the corpus path-dep; tagged
/// `.subprocess`.
@Suite("Codable-round-trip live survey — measured (verify --all-from-index)", .tags(.subprocess))
struct CodableRoundTripLiveSurveyMeasuredTests {

    @Test("the live --all-from-index survey verifies the codable-round-trip picks")
    func measuredLiveSurvey() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("codable-roundtrip-live-corpus")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "CodableRoundTripLiveCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        try await SwiftInferCommand.Verify.runAllFromIndex(
            indexPathOverride: nil,
            budgetString: "small",
            workingDirectory: root,
            maxParallel: 4,
            templateFilter: "codable-round-trip",
            corpusModuleName: "CodableRoundTripLiveCorpus"
        )

        let records = VerifyEvidenceStore.load(startingFrom: root).log.records
            .filter { $0.template == "codable-round-trip" }

        // Exactly two picks (the corpus's two custom-Codable types), split by the
        // measured verdict — the faithful `Meters` bothPasses, the asymmetric
        // `OffByOne` defaultFails. Only execution through the strategist-generated
        // values tells them apart.
        let bothPass = records.filter { $0.outcome == .measuredBothPass }
        let defaultFails = records.filter { $0.outcome == .measuredDefaultFails }
        #expect(records.count == 2)
        #expect(bothPass.count == 1)
        #expect(defaultFails.count == 1)
    }

    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("codable-roundtrip-live-corpus")
    }()
}
