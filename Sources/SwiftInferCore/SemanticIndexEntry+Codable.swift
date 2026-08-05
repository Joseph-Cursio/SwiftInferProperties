import Foundation

/// `SemanticIndexEntry`'s `Codable` conformance, split out when the file hit
/// SwiftLint's 400-line cap.
///
/// The seam is meaningful rather than arbitrary: back-compatibility lives
/// entirely on the DECODER side (`decodeIfPresent` for every field added after
/// v1.33), while the encoder writes every stored property unconditionally. That
/// asymmetry is a rule the file states in a comment and that
/// `FieldCoverageReflectionTests` enforces, so keeping both halves together and
/// away from the value's shape reads better than interleaving them.
extension SemanticIndexEntry {

    /// Custom decoder uses `decodeIfPresent` for `typeShape` so
    /// pre-v1.47 entries (without the field) decode cleanly. All
    /// other fields stay required — they've been part of the schema
    /// since v1.33.
    private enum CodingKeys: String, CodingKey {
        case identityHash
        case templateName
        case typeName
        case score
        case tier
        case primaryFunctionName
        case location
        case decision
        case decisionAt
        case firstSeenAt
        case lastSeenAt
        case typeShape
        case secondaryFunctionName
        case carrierTypeName
        case isInstanceMethod
        case isMutatingMethod
        case isNullary
        case returnsSelfType
        case isComputedProperty
        case parameterTypeNames
        case qualifiedTypeName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.identityHash = try container.decode(String.self, forKey: .identityHash)
        self.templateName = try container.decode(String.self, forKey: .templateName)
        self.typeName = try container.decodeIfPresent(String.self, forKey: .typeName)
        self.score = try container.decode(Int.self, forKey: .score)
        self.tier = try container.decode(String.self, forKey: .tier)
        self.primaryFunctionName = try container.decode(String.self, forKey: .primaryFunctionName)
        self.location = try container.decode(String.self, forKey: .location)
        self.decision = try container.decodeIfPresent(String.self, forKey: .decision)
        self.decisionAt = try container.decodeIfPresent(String.self, forKey: .decisionAt)
        self.firstSeenAt = try container.decode(String.self, forKey: .firstSeenAt)
        self.lastSeenAt = try container.decode(String.self, forKey: .lastSeenAt)
        self.typeShape = try container.decodeIfPresent(IndexedTypeShape.self, forKey: .typeShape)
        self.secondaryFunctionName = try container.decodeIfPresent(
            String.self, forKey: .secondaryFunctionName
        )
        self.carrierTypeName = try container.decodeIfPresent(String.self, forKey: .carrierTypeName)
        self.isInstanceMethod =
            try container.decodeIfPresent(Bool.self, forKey: .isInstanceMethod) ?? false
        self.isMutatingMethod =
            try container.decodeIfPresent(Bool.self, forKey: .isMutatingMethod) ?? false
        self.isNullary =
            try container.decodeIfPresent(Bool.self, forKey: .isNullary) ?? false
        self.returnsSelfType =
            try container.decodeIfPresent(Bool.self, forKey: .returnsSelfType) ?? false
        self.isComputedProperty =
            try container.decodeIfPresent(Bool.self, forKey: .isComputedProperty) ?? false
        // Absent on any index written before 2026-08-03 → empty, which verify reads as
        // "not recorded" and falls back to the single-carrier composition.
        self.parameterTypeNames =
            try container.decodeIfPresent([String].self, forKey: .parameterTypeNames) ?? []
        self.qualifiedTypeName =
            try container.decodeIfPresent(String.self, forKey: .qualifiedTypeName)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identityHash, forKey: .identityHash)
        try container.encode(templateName, forKey: .templateName)
        try container.encodeIfPresent(typeName, forKey: .typeName)
        try container.encode(score, forKey: .score)
        try container.encode(tier, forKey: .tier)
        try container.encode(primaryFunctionName, forKey: .primaryFunctionName)
        try container.encode(location, forKey: .location)
        try container.encodeIfPresent(decision, forKey: .decision)
        try container.encodeIfPresent(decisionAt, forKey: .decisionAt)
        try container.encode(firstSeenAt, forKey: .firstSeenAt)
        try container.encode(lastSeenAt, forKey: .lastSeenAt)
        try container.encodeIfPresent(typeShape, forKey: .typeShape)
        try container.encodeIfPresent(secondaryFunctionName, forKey: .secondaryFunctionName)
        try container.encodeIfPresent(carrierTypeName, forKey: .carrierTypeName)
        try container.encode(isInstanceMethod, forKey: .isInstanceMethod)
        try container.encode(isMutatingMethod, forKey: .isMutatingMethod)
        try container.encode(isNullary, forKey: .isNullary)
        try container.encode(returnsSelfType, forKey: .returnsSelfType)
        try container.encode(isComputedProperty, forKey: .isComputedProperty)
        // Encoded unconditionally, including when empty. It was briefly omitted-when-empty to
        // keep an index of unary laws byte-identical to one written before the field existed —
        // and `FieldCoverageReflectionTests` rejected that within the hour. It is right to: a
        // stored property that silently never reaches the encoded form is the defect that guard
        // exists for, and a tidier diff is not worth reopening it. Old indexes still load,
        // because the DECODER is where back-compat belongs (`decodeIfPresent`).
        try container.encode(parameterTypeNames, forKey: .parameterTypeNames)
        // Encoded unconditionally (null when absent), for the same reason
        // `parameterTypeNames` is: back-compat belongs on the DECODER
        // (`decodeIfPresent`), and a stored property that never reaches the encoded
        // form is exactly what `FieldCoverageReflectionTests` exists to catch. It
        // caught this one — the first version used `encodeIfPresent`.
        try container.encode(qualifiedTypeName, forKey: .qualifiedTypeName)
    }
}
