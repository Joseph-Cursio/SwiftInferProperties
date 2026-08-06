import Foundation
import SwiftEffectInference

/// The effect-lattice position a linter resolved for a seeded symbol.
///
/// The consumer half of SwiftProjectLint's `PBTSeedEffect`. It answers the
/// question this package raised from the other side and could not answer for
/// itself: `IdempotenceTemplate+DeclaredEffect` reads the author's annotation
/// off the declaration in front of it, and noted that the linter *"computes
/// strictly more from the same vocabulary — an `EffectSymbolTable` resolving
/// cross-file, multi-hop upward inference through the call graph, and a
/// heuristic inferrer for unannotated callees — and none of that crosses into
/// `.pbt/seeds.json`."* Now some of it does.
///
/// **Some, not all, and the gap is the interesting part** — see `Provenance`.
public struct SeedEffect: Codable, Sendable, Equatable {

    /// A lattice position, spelled as the annotation grammar spells it.
    ///
    /// A separate enum from `SwiftEffectInference.Effect` rather than a
    /// `Codable` conformance on it. `Effect` is a shared vocabulary type three
    /// packages depend on; making it decode a wire format would let a producer's
    /// schema change break an in-memory algebra that has nothing to do with
    /// JSON. `asEffect` is the deliberate crossing.
    public enum Tier: String, Codable, Sendable {
        case pure
        case idempotent
        case observational
        case externallyIdempotent = "externally_idempotent"
        case nonIdempotent = "non_idempotent"

        /// The in-memory lattice position. `externallyIdempotent` arrives
        /// without its key parameter — the manifest carries the tier, and the
        /// `(by:)` binding is a producer-side detail no consumer here reads.
        public var asEffect: Effect {
            switch self {
            case .pure: return .pure
            case .idempotent: return .idempotent
            case .observational: return .observational
            case .externallyIdempotent: return .externallyIdempotent(keyParameter: nil)
            case .nonIdempotent: return .nonIdempotent
            }
        }
    }

    /// How the linter came to know `resolved`, and therefore whether this
    /// package may act on it.
    public enum Provenance: String, Codable, Sendable {
        /// A human annotated the callee. The only provenance this package acts
        /// on — see `carriesEnoughEvidenceToDemote`.
        case declared

        /// Resolved by walking bodies up the call graph to a fixed point.
        case inferredUpward = "inferred-upward"

        /// Matched by the linter's name/framework heuristic.
        case inferredDownward = "inferred-downward"
    }

    /// What the seeded symbol claims on its own declaration.
    public let declared: Tier

    /// What the linter found its body actually reaches.
    public let resolved: Tier

    /// How `resolved` was arrived at.
    public let provenance: Provenance

    /// Hops back to an anchor, when `provenance == .inferredUpward`.
    public let depth: Int?

    /// What an upward chain bottoms out on. `nil` for the other provenances,
    /// where the question does not arise.
    ///
    /// This is the field that turns `inferred-upward` from *reported* into
    /// *usable* — see `carriesEnoughEvidenceToDemote`.
    public let anchor: Anchor?

    /// Mirrors SwiftProjectLint's `PBTSeedEffect.Anchor`, and through it
    /// `SwiftEffectInference.BodyInference.Anchor`. Translated at each boundary
    /// rather than shared, so a rename in one repository cannot silently move a
    /// wire format two repositories away.
    public enum Anchor: String, Codable, Sendable {
        /// Every step justifying the tier was a human annotation.
        case declaration
        /// At least one step was a name or framework guess.
        case heuristic
    }

    /// The phrase a heuristic matched, when `provenance == .inferredDownward`.
    public let reason: String?

    /// Whether this package may turn the effect into a scoring signal.
    ///
    /// **Only `declared` qualifies, and the exclusion is a decision this
    /// repository already made in `EffectResolver`.** That resolver runs its own
    /// upward inference with the heuristic classifier explicitly disabled,
    /// because it *"guesses effects for unannotated callees from their NAMES —
    /// the shape of inference this repo has repeatedly measured as a precision
    /// cost — and a veto built on a name guess would suppress a true law because
    /// a callee was called `save`."* Accepting `inferred-downward` from the
    /// manifest would re-import that exact failure through a JSON file.
    ///
    /// **`inferredUpward` is excluded for a subtler reason, and it is the one
    /// worth knowing.** The linter's upward inference is *not* the same
    /// declaration-anchored walk `EffectResolver` performs: it calls
    /// `applyBodyInference` with `HeuristicEffectInferrer` supplied as the
    /// anchor resolver, so a chain can bottom out on a name guess and still
    /// surface as `inferred-upward`. The manifest's `provenance` describes the
    /// **final hop** — how the immediate callee's effect was known — not whether
    /// everything beneath it was declared. So an upward tier cannot be
    /// distinguished here from a name-anchored one, and a demotion built on it
    /// would be the `save` failure again, one hop further away and harder to see.
    ///
    /// The fix is on the producer: track anchor purity through
    /// `BodyEffectInferrer` and emit it, at which point a declaration-anchored
    /// multi-hop chain becomes exactly the signal this package cannot compute
    /// for itself and most wants. Until then the honest reading of an upward
    /// tier is a caveat, not a score.
    public var carriesEnoughEvidenceToDemote: Bool {
        switch provenance {
        case .declared:
            return true

        case .inferredUpward:
            // Acted on **only** when the chain is annotation-anchored. The
            // producer now distinguishes the two, so the blanket refusal this
            // used to be is no longer the honest answer — it withheld a real
            // signal to avoid an unrelated one.
            //
            // This is the case worth having: the producer resolves to a fixed
            // point across every file, while `EffectResolver` here runs one hop
            // against a budget it must fit inside §13's. A `@NonIdempotent`
            // three calls down is structurally out of local reach and arrives
            // here already resolved.
            return anchor == .declaration

        case .inferredDownward:
            // Never. A name match is a guess by construction, and
            // `EffectResolver` disables its own heuristic classifier for
            // exactly this reason: "a veto built on a name guess would suppress
            // a true law because a callee was called `save`". Accepting it
            // through a JSON file would be the same mistake in a different hat.
            return false
        }
    }

    public init(
        declared: Tier,
        resolved: Tier,
        provenance: Provenance,
        depth: Int? = nil,
        anchor: Anchor? = nil,
        reason: String? = nil
    ) {
        self.declared = declared
        self.resolved = resolved
        self.provenance = provenance
        self.depth = depth
        self.anchor = anchor
        self.reason = reason
    }

    /// `depth` and `reason` decode leniently; the three that would have to be
    /// guessed do not. The same rule `SeedManifest.Seed` applies to `kind`
    /// versus `role`: absence with an honest reading may be optional, absence
    /// that would be filled by a guess may not.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.declared = try container.decode(Tier.self, forKey: .declared)
        self.resolved = try container.decode(Tier.self, forKey: .resolved)
        self.provenance = try container.decode(Provenance.self, forKey: .provenance)
        self.depth = try container.decodeIfPresent(Int.self, forKey: .depth)
        // Absent means "no chain to describe", which is the honest reading for
        // the two non-upward provenances — and, for an upward one, means a
        // producer that predates the field. `carriesEnoughEvidenceToDemote`
        // then reads nil as not-declaration and withholds, which is the same
        // answer this tool gave before the field existed.
        self.anchor = try container.decodeIfPresent(Anchor.self, forKey: .anchor)
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason)
    }
}
