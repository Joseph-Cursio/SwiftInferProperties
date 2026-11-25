import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `verify --suggestion … --no-persist-evidence` must write nothing, as `--all-from-index` does.
///
/// The flag was parsed in both modes and read only by the survey arm: `runPipeline` persisted the
/// evidence record and the replay corpus unconditionally, so re-checking one suggestion against a
/// frozen `.swiftinfer/verify-evidence.json` rewrote the file first — the false "0 drift" #129
/// fixed for surveys. These arms drive the single-run writer `runPipeline` now calls; the
/// command-level arm, through a real build, is `NamespaceRoundTripVerifyMeasuredTests`.
@Suite("verify --suggestion — --no-persist-evidence writes nothing")
struct SuggestionPersistOptOutTests {

    private static let entry = SemanticIndexEntry(
        identityHash: "0x3184A52016D53F64",
        templateName: "round-trip",
        score: 95,
        tier: "Strong",
        primaryFunctionName: "encode(_:)",
        location: "/Toy/Sources/Toy/Codec.swift:6",
        firstSeenAt: "2026-11-24T00:00:00Z",
        lastSeenAt: "2026-11-24T00:00:00Z",
        typeName: "Slug",
        secondaryFunctionName: "decode(_:)",
        parameterTypeNames: ["String"]
    )

    /// A counterexample, so the default run writes BOTH files — the evidence record and the
    /// replay corpus entry. A passing outcome writes no corpus entry, and could not tell an
    /// opted-out corpus write from one that never happens.
    private static let counterexample = VerifyOutcome.defaultFails(
        DefaultFailDetail(trial: 0, input: "\"- - \"", forwardResult: "\"-%20-%20\"", inverseResult: "\"-%20-%20\"")
    )

    private static func paths(_ root: URL) -> (evidence: URL, corpus: URL) {
        let dir = root.appendingPathComponent(".swiftinfer")
        return (dir.appendingPathComponent("verify-evidence.json"), dir.appendingPathComponent("verify-corpus.json"))
    }

    private static func withTempRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("suggestion-persist-optout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private static func persist(in root: URL, persistEvidence: Bool) {
        SwiftInferCommand.Verify.persistSingleRun(
            parsed: counterexample,
            evidenceEntry: entry,
            corpusEntry: entry,
            packageRoot: root,
            regressionPath: nil,
            persistEvidence: persistEvidence,
            now: Date(timeIntervalSince1970: 1_000_000)
        )
    }

    @Test("--no-persist-evidence writes neither the evidence log nor the replay corpus")
    func optOutWritesNothing() throws {
        try Self.withTempRoot { root in
            Self.persist(in: root, persistEvidence: false)
            #expect(!FileManager.default.fileExists(atPath: Self.paths(root).evidence.path))
            #expect(!FileManager.default.fileExists(atPath: Self.paths(root).corpus.path))
        }
    }

    /// **The control.** An absence-only assertion cannot tell "opted out" from "never worked".
    @Test("the default still writes both")
    func defaultStillPersistsBoth() throws {
        try Self.withTempRoot { root in
            Self.persist(in: root, persistEvidence: true)
            #expect(FileManager.default.fileExists(atPath: Self.paths(root).evidence.path))
            #expect(FileManager.default.fileExists(atPath: Self.paths(root).corpus.path))
        }
    }
}
