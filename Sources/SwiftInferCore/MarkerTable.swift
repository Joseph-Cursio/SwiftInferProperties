/// Equivalence-class marker table data model — TestLifter M13.0.
///
/// Used by `EquivalenceClassMarkerExtractor` (M11.1 + M13.1) to recognize
/// `(positive, negative)` two-class partitions and (M13.2+) N-class
/// partitions over a single predicate's output type.
///
/// Layering: pure value types live in `SwiftInferCore` so both the
/// TestLifter detectors and the CLI's `Vocabulary` schema can name the
/// same shapes without circular deps. `MarkerPair` was previously declared
/// in `SwiftInferTestLifter` (M11.1); M13.0 lifts it to Core unchanged
/// at the call-site level (synonym fields are additive with `[]`
/// defaults), then adds `MarkerSet` and the combined `MarkerTable` value
/// type.
///
/// Loading from project vocabulary lives in `Vocabulary.markerPairs` /
/// `Vocabulary.markerSets` (M13.0 schema extension), which
/// `VocabularyLoader` round-trips through `.swiftinfer/vocabulary.json`.
public struct MarkerPair: Sendable, Equatable, Hashable {

    /// The positive-bucket marker token (e.g. `"Valid"`). Matched against
    /// camelCase + snake_case identifier sub-tokens of the test method
    /// name per `EquivalenceClassMarkerExtractor.tokenize` (M11 plan OD #7).
    public let positive: String

    /// The negative-bucket marker token (e.g. `"Invalid"`). Same matching
    /// rules as `positive`.
    public let negative: String

    /// Optional positive-side synonyms supplied via project vocabulary
    /// (M13 plan §"What M13 ships" axis 1). Empty by default; the curated
    /// `MarkerTable.curatedPairs` ship with no synonyms. Consumed by
    /// future M13.1+ extractor work — adding the field at M13.0 keeps the
    /// data shape forward-compatible without forcing an API churn later.
    public let positiveSynonyms: [String]

    /// Optional negative-side synonyms; same posture as `positiveSynonyms`.
    public let negativeSynonyms: [String]

    public init(
        positive: String,
        negative: String,
        positiveSynonyms: [String] = [],
        negativeSynonyms: [String] = []
    ) {
        self.positive = positive
        self.negative = negative
        self.positiveSynonyms = positiveSynonyms
        self.negativeSynonyms = negativeSynonyms
    }

    /// The M11 narrow default — `Valid`/`Invalid` only. Preserved at M13.0
    /// so M11's extractor + tests continue to compile against a single
    /// constant; M13.1's extractor refactor switches the discover loop to
    /// consume the broader `MarkerTable.curatedPairs` surface (see M13
    /// plan sub-milestone M13.1).
    public static let defaultTable: [Self] = [
        Self(positive: "Valid", negative: "Invalid")
    ]
}

extension MarkerPair: Codable {

    private enum CodingKeys: String, CodingKey {
        case positive
        case negative
        case positiveSynonyms
        case negativeSynonyms
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            positive: try container.decode(String.self, forKey: .positive),
            negative: try container.decode(String.self, forKey: .negative),
            positiveSynonyms: try container.decodeIfPresent(
                [String].self, forKey: .positiveSynonyms
            ) ?? [],
            negativeSynonyms: try container.decodeIfPresent(
                [String].self, forKey: .negativeSynonyms
            ) ?? []
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(positive, forKey: .positive)
        try container.encode(negative, forKey: .negative)
        try container.encode(positiveSynonyms, forKey: .positiveSynonyms)
        try container.encode(negativeSynonyms, forKey: .negativeSynonyms)
    }
}

/// One N-class marker set —
/// `MarkerSet(name: "Sizes", markers: ["small", "medium", "large"])`.
/// Surfaced by `NClassEquivalenceClassDetector` (M13.2). The `name` field
/// is the disambiguator used in N-class accept-flow filenames per M13
/// plan OD #6 (`EquivalenceClasses_<predicate>_<markerSetName>.swift`).
public struct MarkerSet: Sendable, Equatable, Hashable, Codable {

    public let name: String

    public let markers: [String]

    public init(name: String, markers: [String]) {
        self.name = name
        self.markers = markers
    }
}

/// Combined marker-table data model — pairs (two-class M11/M13) plus
/// sets (N-class M13.2). Static `curatedPairs` and `curatedSets` constants
/// expose the v1.x curated default surface; consumers concatenate these
/// with `Vocabulary.markerPairs` / `Vocabulary.markerSets` to build the
/// effective marker table for a discover run (concatenation lands in
/// M13.1's extractor refactor).
public struct MarkerTable: Sendable, Equatable, Codable {

    public let pairs: [MarkerPair]

    public let sets: [MarkerSet]

    public init(pairs: [MarkerPair] = [], sets: [MarkerSet] = []) {
        self.pairs = pairs
        self.sets = sets
    }

    /// The five curated marker pairs the M13 plan ships (OD #1):
    /// `Valid`/`Invalid` (M11 inheritance) + `Success`/`Failure` +
    /// `Accept`/`Reject` + `Pass`/`Fail` + `Allowed`/`Forbidden`.
    /// Consumers concatenate this with `Vocabulary.markerPairs` to build
    /// the effective per-discover table; user-supplied vocab is additive
    /// (it does not replace curated defaults).
    public static let curatedPairs: [MarkerPair] = [
        MarkerPair(positive: "Valid", negative: "Invalid"),
        MarkerPair(positive: "Success", negative: "Failure"),
        MarkerPair(positive: "Accept", negative: "Reject"),
        MarkerPair(positive: "Pass", negative: "Fail"),
        MarkerPair(positive: "Allowed", negative: "Forbidden")
    ]

    /// Curated N-class marker sets — empty per M13 plan OD #2. N-class
    /// partitions are domain-specific (`Small`/`Medium`/`Large`,
    /// `Red`/`Green`/`Blue`, …); opinionated curated defaults would be
    /// either too narrow or too broad. User-supplied via
    /// `Vocabulary.markerSets`.
    public static let curatedSets: [MarkerSet] = []
}
