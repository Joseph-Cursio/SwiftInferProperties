import Foundation

/// What a seeded symbol still needs before a law over it compiles — the `requires` field the
/// producer writes.
///
/// SwiftProjectLint's *Missing Equatable on Pure Function Result* rule seeds a pure function (or a
/// `pure-mutator`) that is refused as a candidate **only** because the value a law compares is not
/// `Equatable` — and only when a bare `: Equatable` on project types would be synthesized. The
/// producer names those types here, the compared type's own first, so a law can say what to declare
/// before it compiles instead of failing to.
///
/// SwiftLintRuleStudio's `MigrationAssistant.detectMigrations` is the case that motivated the field:
/// pure, total, returning a `MigrationPlan` of strings and `MigrationStep`s nobody had declared
/// `Equatable`, and absent from every manifest until the producer learned to say so.
///
/// Optional and presence-keyed, like `role`, `restriction` and `effect`: absent is "nothing
/// required", which is every seed but the near misses.
public struct SeedRequirement: Codable, Sendable, Equatable {

    /// The project types to declare `Equatable`. Never empty when the field is present.
    public let equatable: [String]

    public init(equatable: [String]) {
        self.equatable = equatable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SeedRequirementField.self)
        self.equatable = try container.decodeIfPresent([String].self, forKey: .equatable) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SeedRequirementField.self)
        try container.encode(equatable, forKey: .equatable)
    }

    /// The caveat a law over this seed carries: what to declare before it compiles.
    public var caveat: String {
        let quoted = equatable.map { "`\($0)`" }
        let list = quoted.count > 1
            ? quoted.dropLast().joined(separator: ", ") + " and " + (quoted.last ?? "")
            : (quoted.first ?? "")
        return "Declare `Equatable` on \(list) first — the law compares a value of "
            + "\(equatable.count == 1 ? "that type" : "those types"), and the linter found the "
            + "conformance would be synthesized (every member is already `Equatable`)."
    }
}

/// The keys inside a seed's `requires` object — enumerated for `SeedFieldParity`, as
/// `SeedEffectField` is for `effect`.
public enum SeedRequirementField: String, CodingKey, CaseIterable {
    case equatable
}
