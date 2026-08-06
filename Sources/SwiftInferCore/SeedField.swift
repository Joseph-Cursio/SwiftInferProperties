import Foundation

/// Every key a seed carries — the coding keys for `SeedManifest.Seed`, and the **one** place this
/// build's read-field set is written down.
///
/// Declared at top level rather than nested as `Seed.CodingKeys` for two reasons, one incidental
/// and one not. The incidental: nesting it would sit two levels deep inside `SeedManifest.Seed` and
/// trip the `nesting` rule. The real one: `SeedFieldParity` needs to enumerate it, a synthesised
/// `CodingKeys` is `private` and not `CaseIterable`, and hand-listing the fields beside the decoder
/// would make the parity guard a copy that agrees with itself — the exact failure
/// `KitCoverageDriftTests` demonstrated by passing green through thirteen false claims.
///
/// Because the keys are explicit, `Seed` provides **both** `init(from:)` and `encode(to:)`. Leaving
/// the encoder synthesised would give it a second, private, invisible set of keys, so the two
/// halves of the round trip could disagree without anything saying so.
public enum SeedField: String, CodingKey, CaseIterable {
    case file
    case line
    case symbol
    case rule
    case kind
    case role
    case restriction
    case effect
}

extension SeedManifest.Seed {

    /// Written out rather than synthesised — see `SeedField`. Optionals use `encodeIfPresent`, so a
    /// seed with no role is byte-identical to one written before that field existed, which is the
    /// property the producer maintains on its side and the reason no version bump accompanied
    /// `role`, `restriction` or `effect`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SeedField.self)
        try container.encode(file, forKey: .file)
        try container.encode(line, forKey: .line)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(rule, forKey: .rule)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encodeIfPresent(restriction, forKey: .restriction)
        try container.encodeIfPresent(effect, forKey: .effect)
    }
}

/// Which manifest fields this build reads — the consumer half of the schema contract.
///
/// It exists because `Codable` ignores unknown keys, which makes a producer-side addition
/// **silent** on this side. `restriction` shipped upstream on 2026-08-03 and was dropped on the
/// floor here for three days, while this repo was independently getting the question it answers
/// wrong. Nothing failed; nothing could have.
///
/// Derived from `SeedField` rather than hand-listed, and compared by `SeedFieldParityTests` against
/// what a *real* producer emits: a committed manifest sample, plus the producer's own `PBTSeed`
/// declaration when a sibling checkout is present.
public enum SeedFieldParity {

    /// Every key `SeedManifest.Seed` decodes, at the top level of a seed.
    public static var knownFields: Set<String> {
        Set(SeedField.allCases.map(\.stringValue))
    }

    /// Every key this build decodes inside a **nested** object, keyed by the field that holds it.
    ///
    /// **The first version of this guard had no such notion, and the omission cost a field within
    /// hours.** `SeedFieldParity` enumerated `Seed`'s keys; `effect` was one of them, and its
    /// sub-object was never opened. SwiftProjectLint added `anchor` to `PBTSeedEffect` on
    /// 2026-08-06 — the same day the top-level guard shipped, for the same reason `restriction` had
    /// been silent three days earlier — and nothing here could have reported it.
    ///
    /// Keyed by holder rather than flattened into one set, because a flat set would let a field
    /// added to the *wrong* object pass: `reason` is legitimate inside `effect` and would be a
    /// silent drop at the top level.
    public static var knownNestedFields: [String: Set<String>] {
        [SeedField.effect.stringValue: Set(SeedEffectField.allCases.map(\.stringValue))]
    }

    /// Fields emitted under `holder` that this build does not decode.
    ///
    /// An **unknown holder is not a violation** — that case is already the top-level guard's job,
    /// and reporting it twice would make one added field fail two tests with different messages.
    public static func unreadFields(under holder: String, emitted: Set<String>) -> Set<String> {
        guard let known = knownNestedFields[holder] else { return [] }
        return emitted.subtracting(known)
    }
}
