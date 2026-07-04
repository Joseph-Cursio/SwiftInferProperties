import Foundation
import SwiftInferCLI
import SwiftInferCore
import Testing

/// V1.143 — replay-corpus value-type + store tests. The corpus accumulates
/// distinct counterexamples (never drops them) and persists to
/// `.swiftinfer/verify-corpus.json`.
@Suite("Verify corpus — V1.143")
struct VerifyCorpusTests {

    private static func entry(
        identity: String = "ABCDEF0123456789",
        counterexample: String,
        shrunk: String? = nil
    ) -> VerifyCorpusEntry {
        VerifyCorpusEntry(
            identityHash: identity,
            template: "idempotence",
            counterexample: counterexample,
            shrunkCounterexample: shrunk,
            seed: "a:b:c:d",
            capturedAt: Date(timeIntervalSinceReferenceDate: 0),
            swiftInferVersion: "test"
        )
    }

    // MARK: - Accumulate semantics

    @Test("adding the same (identity, counterexample) is a no-op (first-seen wins)")
    func addingDedups() {
        let first = Self.entry(counterexample: "999", shrunk: "0")
        let dup = Self.entry(counterexample: "999", shrunk: "0")
        let corpus = VerifyCorpus.empty.adding(first).adding(dup)
        #expect(corpus.entries.count == 1)
    }

    @Test("adding a different counterexample for the same identity keeps both")
    func addingAccumulatesDistinct() {
        let corpus = VerifyCorpus.empty
            .adding(Self.entry(counterexample: "999"))
            .adding(Self.entry(counterexample: "42"))
        #expect(corpus.entries.count == 2)
        #expect(corpus.entries(for: "ABCDEF0123456789").count == 2)
    }

    @Test("entries(for:) filters by identity")
    func entriesForIdentity() {
        let corpus = VerifyCorpus.empty
            .adding(Self.entry(identity: "AAAA", counterexample: "1"))
            .adding(Self.entry(identity: "BBBB", counterexample: "2"))
        #expect(corpus.entries(for: "AAAA").count == 1)
        #expect(corpus.entries(for: "AAAA").first?.counterexample == "1")
        #expect(corpus.entries(for: "CCCC").isEmpty)
    }

    @Test("Codable round-trips entries incl. optional shrunk field")
    func codableRoundTrip() throws {
        let corpus = VerifyCorpus.empty
            .adding(Self.entry(counterexample: "999", shrunk: "0"))
            .adding(Self.entry(counterexample: "42", shrunk: nil))
        let data = try JSONEncoder().encode(corpus)
        let decoded = try JSONDecoder().decode(VerifyCorpus.self, from: data)
        #expect(decoded == corpus)
        #expect(decoded.entries.first?.shrunkCounterexample == "0")
        #expect(decoded.entries.last?.shrunkCounterexample == nil)
    }

    // MARK: - Store

    private func tempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("verify-corpus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("store: missing file loads empty; record then reload round-trips")
    func storeRecordRoundTrip() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        // Missing → empty, silent.
        #expect(VerifyCorpusStore.load(packageRoot: root).corpus.entries.isEmpty)
        #expect(VerifyCorpusStore.load(packageRoot: root).warnings.isEmpty)

        let warnings = VerifyCorpusStore.record(Self.entry(counterexample: "999"), packageRoot: root)
        #expect(warnings.isEmpty)
        let reloaded = VerifyCorpusStore.load(packageRoot: root).corpus
        #expect(reloaded.entries.count == 1)
        #expect(reloaded.entries.first?.counterexample == "999")
        // Written at the conventional path.
        let path = VerifyCorpusStore.defaultPath(for: root)
        #expect(FileManager.default.fileExists(atPath: path.path))
    }

    @Test("store: recordBatch accumulates distinct entries in one write and dedups")
    func storeRecordBatch() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let warnings = VerifyCorpusStore.recordBatch(
            [
                Self.entry(counterexample: "1"),
                Self.entry(counterexample: "2"),
                Self.entry(counterexample: "1") // dup of the first
            ],
            packageRoot: root
        )
        #expect(warnings.isEmpty)
        let corpus = VerifyCorpusStore.load(packageRoot: root).corpus
        #expect(corpus.entries.count == 2)
        // A second batch merges into the existing file (accumulate, dedup).
        _ = VerifyCorpusStore.recordBatch(
            [Self.entry(counterexample: "2"), Self.entry(counterexample: "3")],
            packageRoot: root
        )
        #expect(VerifyCorpusStore.load(packageRoot: root).corpus.entries.count == 3)
    }

    @Test("store: empty batch is a no-op")
    func storeEmptyBatch() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(VerifyCorpusStore.recordBatch([], packageRoot: root).isEmpty)
        #expect(FileManager.default.fileExists(atPath: VerifyCorpusStore.defaultPath(for: root).path) == false)
    }

    @Test("store: re-recording the same counterexample doesn't duplicate; a new one accumulates")
    func storeAccumulates() throws {
        let root = try tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = VerifyCorpusStore.record(Self.entry(counterexample: "999"), packageRoot: root)
        _ = VerifyCorpusStore.record(Self.entry(counterexample: "999"), packageRoot: root) // dup
        _ = VerifyCorpusStore.record(Self.entry(counterexample: "42"), packageRoot: root)  // new
        let corpus = VerifyCorpusStore.load(packageRoot: root).corpus
        #expect(corpus.entries.count == 2)
    }
}
