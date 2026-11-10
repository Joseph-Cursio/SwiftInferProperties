extension SeedKind: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "pure-function":
            self = .pureFunction

        case "idempotency":
            self = .idempotency

        case "extractable-kernel":
            self = .extractableKernel

        case "restricted-function":
            self = .restrictedFunction

        case "carrier":
            self = .carrier

        case "pure-mutator":
            self = .pureMutator

        default:
            self = .unrecognised(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
