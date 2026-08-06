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

    /// **What an upward chain bottoms out on** — the field that makes
    /// `inferredUpward` usable rather than merely reported.
    ///
    /// `provenance` names the *final hop*: how the immediate callee's effect was
    /// known, and nothing about the chain beneath it. This says whether every
    /// step was a human annotation or whether at least one was a guess. `nil`
    /// for the other two provenances, where the question does not arise — a
    /// declaration *is* the anchor, and a heuristic match is a guess by
    /// construction.
    public let anchor: Anchor?

    /// What an upward chain rests on.
    ///
    /// Mirrors the producer's enum, and mirrored rather than shared for the same
    /// reason `Tier` is: the manifest is a versioned wire format and must not
    /// move because a dependency renamed a case.
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
    /// **`inferredUpward` used to be excluded for a subtler reason, and the
    /// producer has now removed it.** The linter's upward inference is *not* the
    /// same declaration-anchored walk `EffectResolver` performs: it calls
    /// `applyBodyInference` with `HeuristicEffectInferrer` supplied as the
    /// anchor resolver, so a chain can bottom out on a name guess and still
    /// surface as `inferred-upward`. `provenance` describes the **final hop** —
    /// how the immediate callee's effect was known — not whether everything
    /// beneath it was declared. So an upward tier could not be distinguished
    /// here from a name-anchored one, and a demotion built on it would have been
    /// the `save` failure again, one hop further away and harder to see.
    ///
    /// This doc then said: *"The fix is on the producer: track anchor purity
    /// through `BodyEffectInferrer` and emit it, at which point a
    /// declaration-anchored multi-hop chain becomes exactly the signal this
    /// package cannot compute for itself and most wants."* **That shipped
    /// (SwiftProjectLint `a5795819`, 2026-08-06), and `anchor` is it.** An
    /// upward chain anchored on `.declaration` is a multi-hop, cross-file walk
    /// in which every justifying step was a human annotation — strictly more
    /// evidence than the single declared callee this already acts on, and
    /// unreachable from here, because `EffectResolver`'s local pass runs one hop
    /// against §13's 2-second `discover` ceiling.
    ///
    /// **`.heuristic` stays excluded, and so does a `nil` anchor on an upward
    /// tier.** The first is the `save` failure by the producer's own admission.
    /// The second is a producer that does not compute anchors — an older linter,
    /// or a newer one that declined to answer — and the safe reading of "did not
    /// say" is not "said declaration". Absent-means-guess is the one default
    /// that turns a missing field into a score.
    public var carriesEnoughEvidenceToDemote: Bool {
        switch provenance {
        case .declared:
            return true

        case .inferredUpward:
            return anchor == .declaration

        case .inferredDownward:
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

    /// `depth`, `anchor` and `reason` decode leniently; the three that would
    /// have to be guessed do not. The same rule `SeedManifest.Seed` applies to
    /// `kind` versus `role`: absence with an honest reading may be optional,
    /// absence that would be filled by a guess may not.
    ///
    /// `anchor` is optional and **safe** to be optional, because the guess it
    /// would otherwise invite is made in the losing direction: a missing anchor
    /// on an upward tier withholds the demotion rather than granting it. See
    /// `carriesEnoughEvidenceToDemote`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SeedEffectField.self)
        self.declared = try container.decode(Tier.self, forKey: .declared)
        self.resolved = try container.decode(Tier.self, forKey: .resolved)
        self.provenance = try container.decode(Provenance.self, forKey: .provenance)
        self.depth = try container.decodeIfPresent(Int.self, forKey: .depth)
        self.anchor = try container.decodeIfPresent(Anchor.self, forKey: .anchor)
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason)
    }

    /// Written out rather than synthesised, for the same reason `SeedField` is —
    /// see there. Optionals use `encodeIfPresent`, so a seed effect from a
    /// producer that computes no anchor stays byte-identical to one written
    /// before the field existed.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SeedEffectField.self)
        try container.encode(declared, forKey: .declared)
        try container.encode(resolved, forKey: .resolved)
        try container.encode(provenance, forKey: .provenance)
        try container.encodeIfPresent(depth, forKey: .depth)
        try container.encodeIfPresent(anchor, forKey: .anchor)
        try container.encodeIfPresent(reason, forKey: .reason)
    }
}

/// Every key a seed's `effect` object carries.
///
/// Top-level and `CaseIterable` for the same reason `SeedField` is: `SeedFieldParity` has to
/// enumerate it. **The nested object needed its own entry because the guard did not reach it** —
/// `SeedFieldParity` walked `Seed`'s keys, `effect` was one key, and its sub-object was never
/// opened. `anchor` arrived upstream on 2026-08-06 and was silent here for exactly the same reason
/// `restriction` had been silent at the top level three days earlier: the same defect class, one
/// level down, hours after the guard meant to end it. A guard that stops at the first level of a
/// nested document only guards the first level.
public enum SeedEffectField: String, CodingKey, CaseIterable {
    case declared
    case resolved
    case provenance
    case depth
    case anchor
    case reason
}
