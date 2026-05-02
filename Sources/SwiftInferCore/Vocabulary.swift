/// Project-extensible naming vocabulary loaded from `.swiftinfer/vocabulary.json`
/// per PRD v0.3 §4.5. Templates consult vocabulary entries alongside their
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
///   "inverseElementVerbs": ["mirror", "antipodal"]
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

    public init(
        inversePairs: [InversePair] = [],
        idempotenceVerbs: [String] = [],
        commutativityVerbs: [String] = [],
        antiCommutativityVerbs: [String] = [],
        monotonicityVerbs: [String] = [],
        inverseElementVerbs: [String] = []
    ) {
        self.inversePairs = inversePairs
        self.idempotenceVerbs = idempotenceVerbs
        self.commutativityVerbs = commutativityVerbs
        self.antiCommutativityVerbs = antiCommutativityVerbs
        self.monotonicityVerbs = monotonicityVerbs
        self.inverseElementVerbs = inverseElementVerbs
    }

    /// The default vocabulary — every list empty. Templates fall back to
    /// their curated lists alone when no project vocabulary is supplied.
    public static let empty = Vocabulary()
}

extension Vocabulary: Codable {

    private enum CodingKeys: String, CodingKey {
        case inversePairs
        case idempotenceVerbs
        case commutativityVerbs
        case antiCommutativityVerbs
        case monotonicityVerbs
        case inverseElementVerbs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            inversePairs: try container.decodeIfPresent([InversePair].self, forKey: .inversePairs) ?? [],
            idempotenceVerbs: try container.decodeIfPresent([String].self, forKey: .idempotenceVerbs) ?? [],
            commutativityVerbs: try container.decodeIfPresent([String].self, forKey: .commutativityVerbs) ?? [],
            antiCommutativityVerbs: try container.decodeIfPresent([String].self, forKey: .antiCommutativityVerbs) ?? [],
            monotonicityVerbs: try container.decodeIfPresent([String].self, forKey: .monotonicityVerbs) ?? [],
            inverseElementVerbs: try container.decodeIfPresent([String].self, forKey: .inverseElementVerbs) ?? []
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
