import Foundation

/// V1.143 — one known counterexample in the durable replay corpus
/// (`.swiftinfer/verify-corpus.json`). The corpus is a Hypothesis-style
/// "example database": once `verify` finds a counterexample, it is recorded
/// here and **kept** — even after the property is fixed — so it can be
/// re-checked on every run as a permanent regression guard.
///
/// Distinct from `VerifyEvidence` (one upsert-latest record per suggestion =
/// the *current verdict*): the corpus **accumulates** distinct counterexamples
/// and never drops them.
public struct VerifyCorpusEntry: Sendable, Equatable, Codable {

    /// Suggestion-identity hash in the normalized persisted form (16-char
    /// uppercase hex, no `0x`), matching `VerifyEvidence.identityHash`.
    public let identityHash: String

    /// Template that produced the suggestion (`"round-trip"`, `"idempotence"`,
    /// …). Stored for readability + so a replayer can route without an index
    /// lookup.
    public let template: String

    /// The first failing input the verify run found (`VERIFY_DEFAULT_INPUT`),
    /// as a Swift-source expression — the durable example to re-check.
    public let counterexample: String

    /// The minimal still-failing input after shrinking, or `nil` when the
    /// carrier wasn't shrinkable.
    public let shrunkCounterexample: String?

    /// The replayable Xoshiro seed (deterministic from the identity hash),
    /// serialized as colon-joined hex — reproduces the failing trial.
    public let seed: String

    /// When this counterexample was first recorded. ISO8601 in JSON.
    public let capturedAt: Date

    /// swift-infer version that recorded it (staleness signal on replay).
    public let swiftInferVersion: String

    public init(
        identityHash: String,
        template: String,
        counterexample: String,
        shrunkCounterexample: String?,
        seed: String,
        capturedAt: Date,
        swiftInferVersion: String
    ) {
        self.identityHash = identityHash
        self.template = template
        self.counterexample = counterexample
        self.shrunkCounterexample = shrunkCounterexample
        self.seed = seed
        self.capturedAt = capturedAt
        self.swiftInferVersion = swiftInferVersion
    }

    /// Identity for dedup: a counterexample is "the same" when it's the same
    /// failing input for the same suggestion. Re-running verify (deterministic
    /// seed → same first failure) must not duplicate the entry.
    public var dedupKey: String { "\(identityHash)\u{1F}\(counterexample)" }
}

/// Top-level `.swiftinfer/verify-corpus.json` shape. Wraps the entry list with
/// a schema version, mirroring `VerifyEvidenceLog` / `Decisions`.
public struct VerifyCorpus: Sendable, Equatable, Codable {

    /// Bumped on incompatible on-disk schema change. Ships at `1` (v1.143).
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let entries: [VerifyCorpusEntry]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        entries: [VerifyCorpusEntry] = []
    ) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }

    /// The empty corpus — `VerifyCorpusStore.load` returns this when absent.
    public static let empty = Self()

    /// **Accumulate** a counterexample. Unlike `VerifyEvidenceLog.upserting`
    /// (which replaces the prior record), the corpus *keeps* every distinct
    /// counterexample: if `dedupKey` already exists the corpus is unchanged
    /// (first-seen wins, preserving `capturedAt`); otherwise the entry is
    /// appended. This is what makes it a permanent regression guard.
    public func adding(_ entry: VerifyCorpusEntry) -> Self {
        guard entries.contains(where: { $0.dedupKey == entry.dedupKey }) == false else {
            return self
        }
        return Self(schemaVersion: schemaVersion, entries: entries + [entry])
    }

    /// All recorded counterexamples for a suggestion identity — the set a
    /// replay run re-checks.
    public func entries(for identityHash: String) -> [VerifyCorpusEntry] {
        entries.filter { $0.identityHash == identityHash }
    }
}
