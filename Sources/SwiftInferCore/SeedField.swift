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

    /// Every key `SeedManifest.Seed` decodes.
    public static var knownFields: Set<String> {
        Set(SeedField.allCases.map(\.stringValue))
    }
}
