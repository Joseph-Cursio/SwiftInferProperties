import Foundation

/// What happened to a law that only exists because a refactor was applied to a
/// **copy** of the reader's code.
///
/// ## Why this is not `VerifyEvidenceOutcome`
///
/// The design named reusing `measured-defaultFails` as a dishonesty, and the
/// reason survives review: that name means *"the property is false of your
/// program"*. A speculative law is not about the reader's program. It is about a
/// program that does not exist yet — the one they would have after applying the
/// patch.
///
/// For **access widening** specifically those two are closer than for any later
/// tier, because a visibility change cannot alter behaviour, so a refuted
/// speculative law really is a statement about their logic. But the vocabulary has
/// to survive tiers 2 and 3, where a refutation indicts *either the code or the
/// extraction* and nothing distinguishes them without differential testing. Naming
/// it separately now costs one enum; renaming it later, after consumers have keyed
/// on the wrong word, costs a migration and a wrong claim in between.
public enum SpeculativeVerdict: String, Sendable, Equatable, Codable {

    /// The law ran against the patched copy and found no counterexample. **This is
    /// the only outcome that should surface a refactor** — the design's whole
    /// inversion is that a patch is proposed *because* a law ran, not in the hope
    /// that one might.
    case lawHeldOnPatchedCopy = "speculative-law-held"

    /// The law ran and was refuted. Worth reporting and worth NOT calling a bug:
    /// measured 2026-08-04, both refutations were `idempotence` firing on a
    /// `T -> T` shape that is not idempotent — a false law about correct code. The
    /// refactor is not recommended, and the reason is the law, not the patch.
    case lawRefutedOnPatchedCopy = "speculative-law-refuted"

    /// The patch applied and the law was proposed, but verify could not execute it
    /// — no generator for the carrier, no composer, a build failure. **Not
    /// evidence about the refactor either way.** Measured: 3 of 6 proposed laws
    /// landed here, so this is the common outcome, not an edge case.
    case lawNotRunnable = "speculative-law-not-runnable"

    /// The widening produced no new law at all. Two of five all-primitive rows in
    /// the 2026-08-04 sample landed here: the **template gate**, not the carrier,
    /// decides whether a law is proposed, so parameter types cannot predict this.
    case noLawGained = "speculative-no-law-gained"

    /// Whether this verdict justifies putting a patch in front of a reader.
    public var recommendsRefactor: Bool { self == .lawHeldOnPatchedCopy }
}

/// A speculative refactor proposal: the patch, the law it unlocks, and what
/// happened when that law was run.
///
/// ## The source hash is not decoration
///
/// The copy is a [border claim](../../docs/glossary.md): the verdict is measured
/// against a snapshot and reported about the original. If the file moved
/// underneath the run, the verdict silently becomes a claim about code that no
/// longer exists — the same failure `run.json` records tool SHAs to prevent.
/// Recording the hash of the file as it was read is what makes the claim
/// checkable rather than merely asserted.
public struct SpeculativeProposal: Sendable, Equatable {

    /// Package-relative path of the file the patch applies to.
    public let path: String

    /// Unified diff of the one changed line.
    public let diff: String

    /// SHA-ish digest of the ORIGINAL file contents at read time. A reader whose
    /// file has changed since can tell that this verdict is stale.
    public let sourceDigest: String

    /// The law that became visible because of the patch.
    public let lawDescription: String

    public let verdict: SpeculativeVerdict

    /// Trials run, counterexample, or the reason it could not run.
    public let detail: String?

    public init(
        path: String,
        diff: String,
        sourceDigest: String,
        lawDescription: String,
        verdict: SpeculativeVerdict,
        detail: String? = nil
    ) {
        self.path = path
        self.diff = diff
        self.sourceDigest = sourceDigest
        self.lawDescription = lawDescription
        self.verdict = verdict
        self.detail = detail
    }
}
