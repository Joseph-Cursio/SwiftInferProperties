/// V1.24.C — curated set of canonical Swift mutating-method names whose
/// bodies are non-deterministic by structural convention (RNG-driven).
/// Direct cycle-20 finding closure (V1.20.C #40 unknown verdict on
/// `OrderedDictionary.shuffle()` lifted-idempotence; the suggestion
/// surfaced despite shuffling being non-deterministic — the existing
/// `nonDeterministicVeto` body-signal detector didn't catch the OC
/// stdlib RNG call pattern).
///
/// **Why a name-fallback (V1.24.C plan §"Open decisions" #2 lean):**
/// the canonical Swift naming convention `mutating func shuffle()` is
/// by-design non-deterministic regardless of the carrier or the
/// specific RNG implementation. Extending `bodySignals.hasNonDeterministicCall`
/// to catch additional RNG call patterns is a v1.25+ candidate; the
/// name-fallback is the conservative-precision posture for v1.24.
///
/// Mechanism class: extension of class 7's carrier-protocol-conformance
/// veto sub-class (V1.21.A / V1.24.B lineage) — name-based veto on
/// value-semantic carriers, no protocol-conformance requirement.
///
/// Distinct from `MutatorBlockedFromIdempotence.curated`: that set
/// targets state-advancing mutators (reverse/removeFirst/removeLast)
/// which fail idempotence because of structural state advance; this
/// set targets non-deterministic mutators which fail idempotence (and
/// every other algebraic property) because the body itself is non-
/// deterministic.
public enum NonDeterministicMutatorNames {

    /// Canonical Swift non-deterministic mutator names. Single-entry at
    /// v1.24; future-cycle extension via the existing
    /// `Vocabulary.idempotenceVerbs` slot or a new project-vocabulary
    /// slot if more names accumulate.
    ///
    /// `shuffle` is the cycle-20-finding case. Other candidates for
    /// future cycles: `randomize`, `permute` (less standard naming).
    public static let curated: Set<String> = [
        "shuffle"
    ]
}
