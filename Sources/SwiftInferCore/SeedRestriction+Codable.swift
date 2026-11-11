extension SeedRestriction: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "declaration":
            self = .declaration

        case "enclosing-type":
            self = .enclosingType

        default:
            self = .unrecognised(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
