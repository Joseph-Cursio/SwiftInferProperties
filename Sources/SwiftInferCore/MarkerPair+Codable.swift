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
