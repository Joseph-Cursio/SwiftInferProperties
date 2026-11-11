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
