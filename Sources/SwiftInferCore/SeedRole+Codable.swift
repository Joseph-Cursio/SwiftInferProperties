extension SeedRole: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "comparator": self = .comparator
        case "predicate": self = .predicate
        case "transform": self = .transform
        case "reducer": self = .reducer
        case "partition": self = .partition
        case "normalizer": self = .normalizer
        default: self = .unrecognised(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
