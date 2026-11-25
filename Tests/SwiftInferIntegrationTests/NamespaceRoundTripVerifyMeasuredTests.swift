import ArgumentParser
import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// The toy namespace codec, verified for real in both modes — the three `verify` fixes of
/// 2026-11-24 through one fixture (`Tests/Fixtures/namespace-round-trip-corpus/`, `Slug.encode` /
/// `Slug.decode` over `String`, with a planted bug: `%20` is never decoded).
///
/// - **Survey mode finds the planted bug.** It used to file the pair as `not-a-candidate:
///   carrier Slug is a caseless enum` while `--suggestion` measured it; a `(T) -> T` round trip on
///   a namespace is now indexed over `T` (`StructuralBlocker.endomorphicNamespaceRoundTripDomain`).
/// - **`--fail-on-refutation` exits non-zero in both modes**, and without it the same run exits
///   zero — the command is driven end to end through `execute(workingDirectory:)`.
/// - **`--suggestion … --no-persist-evidence` writes neither the evidence log nor the replay
///   corpus**, as `--all-from-index` already did; the default run, the control, writes both.
///
/// Spawns real `swift build`s of the verifier package; tagged `.subprocess` and run in `make
/// batch7`. Each test packages its own copy of the fixture, so they share no state.
@Suite("Namespace round trip — survey finds the planted bug; both modes gate and opt out", .tags(.subprocess))
struct NamespaceRoundTripVerifyMeasuredTests {

    private typealias Verify = SwiftInferCommand.Verify

    private static let moduleName = "NamespaceRoundTripCorpus"

    private static let fixtureDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // SwiftInferIntegrationTests/
        .deletingLastPathComponent()  // Tests/
        .appendingPathComponent("Fixtures")
        .appendingPathComponent("namespace-round-trip-corpus")

    private static func withPackagedCorpus(_ body: (URL) throws -> Void) throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("namespace-round-trip-corpus")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = try CorpusPackager.package(
            moduleName: moduleName, fromSourcesDirectory: fixtureDirectory, into: parent
        )
        try body(root)
    }

    private static func swiftInferFile(_ name: String, in root: URL) -> URL {
        root.appendingPathComponent(".swiftinfer").appendingPathComponent(name)
    }

    @Test("survey mode measures Slug's round trip, finds the planted bug, and gates on it")
    func surveyFindsThePlantedBug() throws {
        try Self.withPackagedCorpus { root in
            let records = try Verify.runAllFromIndex(
                indexPathOverride: nil,
                budgetString: "standard",
                workingDirectory: root,
                maxParallel: 1,
                templateFilter: "round-trip",
                persistEvidence: false,
                corpusModuleName: Self.moduleName,
                quiet: true
            )
            let record = try #require(records.first { $0.primaryFunctionName == "encode(_:)" })
            #expect(
                record.outcome == .measuredDefaultFails,
                "expected the planted bug; got \(record.outcome.rawValue): \(record.outcomeDetail ?? "")"
            )
            #expect(!(record.outcomeDetail ?? "").contains("not-a-candidate"))

            let survey = [
                "--all-from-index", "--template", "round-trip", "--corpus-module", Self.moduleName,
                "--no-persist-evidence",
            ]
            #expect(throws: ExitCode.self) {
                try Verify.parse(survey + ["--fail-on-refutation"]).execute(workingDirectory: root)
            }
            // Without the flag the same refuted survey exits zero, as it always did.
            try Verify.parse(survey).execute(workingDirectory: root)
            #expect(!FileManager.default.fileExists(atPath: Self.swiftInferFile("verify-evidence.json", in: root).path))
        }
    }

    @Test("--suggestion honours --no-persist-evidence and --fail-on-refutation")
    func suggestionOptsOutAndGates() throws {
        try Self.withPackagedCorpus { root in
            let index = try Verify.loadIndex(indexPathOverride: nil, packageRoot: root, scanDependencies: false)
            let entry = try #require(index.entries.first {
                $0.templateName == "round-trip" && $0.typeName == "Slug"
            })
            let suggestion = ["--suggestion", entry.identityHash, "--no-emit-regression"]
            let evidence = Self.swiftInferFile("verify-evidence.json", in: root)
            let corpus = Self.swiftInferFile("verify-corpus.json", in: root)

            #expect(throws: ExitCode.self) {
                try Verify.parse(suggestion + ["--no-persist-evidence", "--fail-on-refutation"])
                    .execute(workingDirectory: root)
            }
            #expect(!FileManager.default.fileExists(atPath: evidence.path))
            #expect(!FileManager.default.fileExists(atPath: corpus.path))

            // The control: no flags, so the counterexample exits zero and both files are written.
            try Verify.parse(suggestion).execute(workingDirectory: root)
            let log = VerifyEvidenceStore.load(startingFrom: root).log
            #expect(log.records.contains { $0.template == "round-trip" && $0.outcome == .measuredDefaultFails })
            #expect(FileManager.default.fileExists(atPath: corpus.path))
        }
    }
}
