/// Project-extensible naming vocabulary loaded from `.swiftinfer/vocabulary.json`
/// per PRD §4.5. Templates consult vocabulary entries alongside their
/// curated lists; project-vocabulary matches contribute the same +40 / +25 /
/// -30 weights as the built-in lists.
///
/// Schema mirrors the PRD §4.5 JSON example:
///
/// ```json
/// {
///   "inversePairs": [["enqueue", "dequeue"], ["activate", "deactivate"]],
///   "idempotenceVerbs": ["sanitizeXML", "rewritePath"],
///   "commutativityVerbs": ["unionGraphs"],
///   "antiCommutativityVerbs": ["concatenateOrdered"],
///   "monotonicityVerbs": ["depth"],
///   "inverseElementVerbs": ["mirror", "antipodal"],
///   "registeredGenerators": { "Node": { "expression": "Node.gen()", "imports": ["Yams"] } }
/// }
/// ```
///
/// Decoding is missing-key-tolerant — every key defaults to an empty array
/// when absent. Unknown top-level keys are silently ignored at the Codable
/// layer; the CLI `VocabularyLoader` (M2.1.5) inspects raw JSON separately
/// if it wants to surface unknowns as warnings.
///
/// Pure value type; no I/O. Loading from disk lives in `VocabularyLoader`.
public struct Vocabulary: Sendable, Equatable {

    /// Project-supplied inverse-name pairs that extend the round-trip
    /// template's curated list (PRD §5.2). Match orientation-insensitive.
    public let inversePairs: [InversePair]

    /// Project-supplied verbs that extend the idempotence template's
    /// curated `normalize` / `canonicalize` / etc. list (PRD §5.2).
    public let idempotenceVerbs: [String]

    /// Project-supplied verbs for the commutativity template (M2.3).
    /// Carried in the M2.1 schema so M2.3 can consume it without
    /// re-touching this type.
    public let commutativityVerbs: [String]

    /// Project-supplied counter-signal verbs for commutativity-class claims
    /// (PRD §4.1's -30 anti-commutativity row, M2.3). Same forward-look as
    /// `commutativityVerbs` — carried in the M2.1 schema.
    public let antiCommutativityVerbs: [String]

    /// Project-supplied verbs for the monotonicity template (M7.1). Extends
    /// the curated `length` / `count` / `size` / `priority` / `score` /
    /// `depth` / `height` / `weight` list. Kept opt-in alongside the curated
    /// set the template ships with.
    public let monotonicityVerbs: [String]

    /// Project-supplied verbs for the inverse-element pairing pass (M8.3 +
    /// M8.4 Group arm). Extends the curated `negate` / `negated` /
    /// `inverse` / `inverted` / `reciprocal` / `complement` / `invert`
    /// list. The pairing pass uses these as a *pre-filter* — only unary
    /// `T -> T` functions whose name matches the curated or project list
    /// surface as inverse-element witnesses. PRD §5.4's Group claim
    /// requires a Monoid + inverse signal pair on the same type; this is
    /// the "inverse" half of that signal.
    public let inverseElementVerbs: [String]

    /// Project-supplied two-class equivalence-class marker pairs (TestLifter
    /// M13.0). Extends `MarkerTable.curatedPairs` (`Valid`/`Invalid`,
    /// `Success`/`Failure`, `Accept`/`Reject`, `Pass`/`Fail`,
    /// `Allowed`/`Forbidden`); the M13.1 extractor consumes the
    /// concatenation, so an empty project list still inherits the curated
    /// defaults — no project-level config required.
    public let markerPairs: [MarkerPair]

    /// Project-supplied N-class equivalence-class marker sets (TestLifter
    /// M13.0). No curated defaults per M13 plan OD #2 — N-class partitions
    /// are domain-specific. The M13.2 detector reads the project list
    /// directly.
    public let markerSets: [MarkerSet]

    /// V1.18.C — project-supplied dual-style member-name pairs that
    /// extend `DualStylePairing`'s curated rules (`X`/`Xing`,
    /// `formX`/`X`, `X`/`Xed`). Literal `(mutating, nonMutating)` pairs
    /// only per the v1.18 plan open decision #6 lean — regex-pattern
    /// extension is a v1.21+ candidate.
    public let dualStyleNamePairs: [DualStyleNamePair]

    /// V1.19.C — project-supplied additive-action verbs that extend
    /// `CompositionTemplate`'s curated list (`increment`, `add`,
    /// `accumulate`, `accrue`, `advance`, `step`, ...). Names matched
    /// here earn the same +40 canonical-naming signal the curated list
    /// produces. The template's numeric-only param-type gate (curated
    /// additive-monoid set) still applies — adding a verb here doesn't
    /// override the type-shape filter.
    public let compositionVerbs: [String]

    /// Project-supplied generators for types the strategist can't derive —
    /// keyed by the bare type spelling as it appears in a carrier's member /
    /// init-parameter list (e.g. `"Node"` for Yams). Generator derivation
    /// dead-ends at `.todo` for a struct with a member of an external type it
    /// can't reach (the SwiftLintRuleStudio road-test's `YAMLConfig` gated by
    /// its Yams `Node` field); registering an expression here lets the
    /// resolver compose the *rest* of the struct instead of gating the whole
    /// carrier. The expression is spliced in verbatim as the member's leaf
    /// generator, so it must be a valid `Gen<Type>` (the idiomatic
    /// `Type.gen()` convention, or any expression the user supplies); the
    /// registration is honoured for nested members and top-level composite
    /// carriers alike. Missing-key-tolerant — defaults to `[:]`.
    public let registeredGenerators: [String: RegisteredGenerator]

    public init(
        inversePairs: [InversePair] = [],
        idempotenceVerbs: [String] = [],
        commutativityVerbs: [String] = [],
        antiCommutativityVerbs: [String] = [],
        monotonicityVerbs: [String] = [],
        inverseElementVerbs: [String] = [],
        markerPairs: [MarkerPair] = [],
        markerSets: [MarkerSet] = [],
        dualStyleNamePairs: [DualStyleNamePair] = [],
        compositionVerbs: [String] = [],
        registeredGenerators: [String: RegisteredGenerator] = [:]
    ) {
        self.inversePairs = inversePairs
        self.idempotenceVerbs = idempotenceVerbs
        self.commutativityVerbs = commutativityVerbs
        self.antiCommutativityVerbs = antiCommutativityVerbs
        self.monotonicityVerbs = monotonicityVerbs
        self.inverseElementVerbs = inverseElementVerbs
        self.markerPairs = markerPairs
        self.markerSets = markerSets
        self.dualStyleNamePairs = dualStyleNamePairs
        self.compositionVerbs = compositionVerbs
        self.registeredGenerators = registeredGenerators
    }

    /// The default vocabulary — every list empty. Templates fall back to
    /// their curated lists alone when no project vocabulary is supplied.
    public static let empty = Self()
}

extension Vocabulary: Codable {

    private enum CodingKeys: String, CodingKey {
        case inversePairs
        case idempotenceVerbs
        case commutativityVerbs
        case antiCommutativityVerbs
        case monotonicityVerbs
        case inverseElementVerbs
        case markerPairs
        case markerSets
        case dualStyleNamePairs
        case compositionVerbs
        case registeredGenerators
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            inversePairs: try container.decodeIfPresent([InversePair].self, forKey: .inversePairs) ?? [],
            idempotenceVerbs: try container.decodeIfPresent([String].self, forKey: .idempotenceVerbs) ?? [],
            commutativityVerbs: try container.decodeIfPresent([String].self, forKey: .commutativityVerbs) ?? [],
            antiCommutativityVerbs: try container.decodeIfPresent([String].self, forKey: .antiCommutativityVerbs) ?? [],
            monotonicityVerbs: try container.decodeIfPresent([String].self, forKey: .monotonicityVerbs) ?? [],
            inverseElementVerbs: try container.decodeIfPresent([String].self, forKey: .inverseElementVerbs) ?? [],
            markerPairs: try container.decodeIfPresent([MarkerPair].self, forKey: .markerPairs) ?? [],
            markerSets: try container.decodeIfPresent([MarkerSet].self, forKey: .markerSets) ?? [],
            dualStyleNamePairs: try container.decodeIfPresent(
                [DualStyleNamePair].self, forKey: .dualStyleNamePairs
            ) ?? [],
            compositionVerbs: try container.decodeIfPresent(
                [String].self, forKey: .compositionVerbs
            ) ?? [],
            registeredGenerators: try container.decodeIfPresent(
                [String: RegisteredGenerator].self, forKey: .registeredGenerators
            ) ?? [:]
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(inversePairs, forKey: .inversePairs)
        try container.encode(idempotenceVerbs, forKey: .idempotenceVerbs)
        try container.encode(commutativityVerbs, forKey: .commutativityVerbs)
        try container.encode(antiCommutativityVerbs, forKey: .antiCommutativityVerbs)
        try container.encode(monotonicityVerbs, forKey: .monotonicityVerbs)
        try container.encode(inverseElementVerbs, forKey: .inverseElementVerbs)
        try container.encode(markerPairs, forKey: .markerPairs)
        try container.encode(markerSets, forKey: .markerSets)
        try container.encode(dualStyleNamePairs, forKey: .dualStyleNamePairs)
        try container.encode(compositionVerbs, forKey: .compositionVerbs)
        try container.encode(registeredGenerators, forKey: .registeredGenerators)
    }
}

/// A project-supplied generator for a type the strategist can't derive
/// (`Vocabulary.registeredGenerators`). `expression` is spliced in verbatim as
/// the type's leaf generator (a `Gen<Type>` — idiomatically `Type.gen()`);
/// `imports` names any modules the expression needs (`["Yams"]`), propagated
/// up so the composed carrier generator carries them. Encoded as a JSON object
/// `{ "expression": "...", "imports": [...] }`; `imports` defaults to `[]`.
public struct RegisteredGenerator: Sendable, Equatable {

    public let expression: String
    public let imports: [String]

    public init(expression: String, imports: [String] = []) {
        self.expression = expression
        self.imports = imports
    }
}

extension RegisteredGenerator: Codable {

    private enum CodingKeys: String, CodingKey {
        case expression
        case imports
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            expression: try container.decode(String.self, forKey: .expression),
            imports: try container.decodeIfPresent([String].self, forKey: .imports) ?? []
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(expression, forKey: .expression)
        try container.encode(imports, forKey: .imports)
    }
}

/// V1.18.C — project-supplied dual-style member-name pair, encoded as a
/// two-element JSON array `["mutating", "nonMutating"]` to match
/// `InversePair`'s schema posture.
public struct DualStyleNamePair: Sendable, Equatable {

    public let mutating: String
    public let nonMutating: String

    public init(mutating: String, nonMutating: String) {
        self.mutating = mutating
        self.nonMutating = nonMutating
    }
}

extension DualStyleNamePair: Codable {

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let mutatingName = try container.decode(String.self)
        let nonMutatingName = try container.decode(String.self)
        guard container.isAtEnd else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription:
                    "DualStyleNamePair must be a two-element array "
                    + "[mutating, nonMutating]; got more than two strings."
            )
        }
        self.init(mutating: mutatingName, nonMutating: nonMutatingName)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(mutating)
        try container.encode(nonMutating)
    }
}

/// One project-supplied inverse-name pair. Encoded as a two-element JSON
/// array `["forward", "reverse"]` to match the PRD §4.5 schema.
public struct InversePair: Sendable, Equatable {

    public let forward: String
    public let reverse: String

    public init(forward: String, reverse: String) {
        self.forward = forward
        self.reverse = reverse
    }
}

extension InversePair: Codable {

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let forward = try container.decode(String.self)
        let reverse = try container.decode(String.self)
        guard container.isAtEnd else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription:
                    "InversePair must be a two-element array [forward, reverse]; "
                    + "got more than two strings."
            )
        }
        self.init(forward: forward, reverse: reverse)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(forward)
        try container.encode(reverse)
    }
}
