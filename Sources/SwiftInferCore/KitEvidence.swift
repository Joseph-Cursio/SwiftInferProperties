import Foundation

/// **PropertyLawKit results, fed back into inference.**
///
/// Until this existed the toolchain was one-way: `discover` proposed laws, a human wrote
/// tests, the kit ran them, and nothing came back. The kit's verdicts — the only *executed*
/// evidence anywhere in the pipeline — influenced no later inference at all.
///
/// That is the same architectural quarantine as two others found on 2026-08-01: the curated
/// catalog contributes zero to scoring, and `ProtocolCoverageMap` vetoes a template on the
/// *assumption* the kit covers the law without ever checking whether the kit ran.
///
/// ## The inference this exists for
///
/// **A refuted equality invalidates every law stated with it.** Almost every property
/// `discover` proposes is an `==` between two expressions — `f(f(x)) == f(x)`,
/// `a • b == b • a`, `decode(encode(x)) == x`. All of them use the carrier's `==` as the
/// oracle. If the kit has *measured* that `==` to be broken, those laws are not wrong so
/// much as **unusable**: they will be checked with a comparison that does not work, and a
/// green run means nothing.
///
/// That is not a hypothetical shape. `fixtures/toolchain-coverage` plants a projecting `==`
/// beside a synthesized `hash(into:)` and the kit rejects it at `Strict` tier in 17 trials,
/// while all four Equatable laws pass — because a projection *is* an equivalence relation.
/// A tool that kept proposing `==`-shaped laws for that type after the kit said so would be
/// ignoring the best evidence it has.
///
/// ## Why this demotes rather than vetoes
///
/// The law itself may be perfectly true and worth stating. What is broken is the ability to
/// *check* it. So the correct output is a diagnosis with a prerequisite — fix `==`, then
/// these become checkable — not silence. Suppressing outright would hide the one finding
/// that matters, and `ProtocolCoverageMap`'s full veto is not the right precedent because
/// it fires on coverage rather than on refutation.
public struct KitLawOutcome: Sendable, Equatable, Codable {

    public enum Outcome: String, Sendable, Equatable, Codable {
        case passed
        case failed
        /// The kit's `.expectedViolation` — a real failure the author documented as
        /// intentional. **Not** treated as a refutation: the author has said they mean it.
        case expectedViolation
        case suppressed
    }

    /// The kit's `StrictnessTier`, as a string so Core takes no kit dependency.
    public enum Tier: String, Sendable, Equatable, Codable {
        case strict
        case conventional
        case heuristic
    }

    /// The carrier the suite ran against — `"ProjectedPlayerScore"`, generics stripped.
    public let typeName: String

    /// The kit's `LawIdentifier.qualifiedName` — `"Hashable.equalityConsistency"`.
    public let law: String

    public let outcome: Outcome
    public let tier: Tier

    /// The kit's counterexample, when it reported one.
    public let counterexample: String?

    public init(
        typeName: String,
        law: String,
        outcome: Outcome,
        tier: Tier,
        counterexample: String? = nil
    ) {
        self.typeName = typeName
        self.law = law
        self.outcome = outcome
        self.tier = tier
        self.counterexample = counterexample
    }
}

/// Everything the kit reported, indexed for the questions inference asks.
public struct KitEvidenceLog: Sendable, Equatable, Codable {

    public let outcomes: [KitLawOutcome]

    public init(outcomes: [KitLawOutcome] = []) {
        self.outcomes = outcomes
    }

    /// Laws whose refutation makes the carrier's `==` untrustworthy as an oracle.
    ///
    /// Deliberately a **short, named list** rather than "anything mentioning equality".
    /// `Equatable.reflexivity` failing means `x != x`, which breaks every comparison;
    /// `Hashable.equalityConsistency` failing means `==` and `hash` disagree, which breaks
    /// `Set` / `Dictionary` and signals that `==` is a projection of something the type
    /// treats as identity.
    ///
    /// `Comparable.totalOrder` is **not** here. A broken `<` invalidates ordering laws, not
    /// equality-shaped ones, and conflating the two would suppress far more than the
    /// evidence supports.
    public static let equalityOracleLaws: Set<String> = [
        "Equatable.reflexivity",
        "Equatable.symmetry",
        "Equatable.transitivity",
        "Equatable.negationConsistency",
        "Hashable.equalityConsistency"
    ]

    /// The kit's measured verdict that this type's `==` cannot be trusted as an oracle.
    ///
    /// Only `Strict`-tier `failed` counts. `Heuristic` failures are advisory by the kit's own
    /// `EnforcementMode.default` and routinely reflect the generator rather than the type —
    /// `fixtures/toolchain-coverage` measured a *correct* type failing `Hashable.distribution`
    /// purely because the generator had been narrowed to hunt a collision bug. Demoting real
    /// suggestions on that basis would punish a reader for aiming their generator well.
    ///
    /// `.expectedViolation` is excluded on purpose: the author used the kit's own
    /// `.intentionalViolation` suppression to say the failure is the documented design.
    public func refutedEqualityOracle(for typeName: String) -> KitLawOutcome? {
        outcomes.first { outcome in
            outcome.typeName == typeName
                && outcome.outcome == .failed
                && outcome.tier == .strict
                && Self.equalityOracleLaws.contains(outcome.law)
        }
    }

    /// The kit executed this carrier's equality laws and they all held.
    ///
    /// Consumed as **provenance, not as a boost** — see the licensing note on
    /// `KitEvidenceScoring`. Inference already assumes `==` is sound, because that is what
    /// the Equatable laws are for; this only records that the assumption was checked.
    public func confirmedEqualityOracle(for typeName: String) -> Bool {
        let relevant = outcomes.filter {
            $0.typeName == typeName && Self.equalityOracleLaws.contains($0.law)
        }
        return !relevant.isEmpty && relevant.allSatisfy { $0.outcome == .passed }
    }

    /// Whether the kit was actually run against this type at all.
    ///
    /// The distinction `ProtocolCoverageMap` currently cannot make: its veto assumes the kit
    /// covers a law, and this is the first thing in the codebase able to say whether that
    /// assumption held.
    public func wasExercised(_ typeName: String) -> Bool {
        outcomes.contains { $0.typeName == typeName }
    }
}
