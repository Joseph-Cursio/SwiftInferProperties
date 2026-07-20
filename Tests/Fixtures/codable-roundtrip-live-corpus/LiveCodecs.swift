import Foundation

// Live-index verify corpus for codable-round-trip (verify --all-from-index).
// Int fields (NaN-free, cleanly strategist-generatable) + a public memberwise
// init (custom init(from:) suppresses the synthesized one) + keyed containers
// (no top-level JSON fragment). Two hand-written custom Codable conformances:
// one faithful (bothPass), one buggy (defaultFails).

/// Faithful custom codec — `decode(encode(x)) == x` → bothPass.
public struct Meters: Codable, Equatable {
    public var value: Int
    public init(value: Int) { self.value = value }

    private enum CodingKeys: String, CodingKey { case value }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.value = try container.decode(Int.self, forKey: .value)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
    }
}

/// Buggy custom codec — encode stores `value + 1`, decode reads it back as-is,
/// so `decode(encode(x)) == x + 1 != x` for every value → defaultFails. The
/// swift-asn1 class of asymmetric codec, in its simplest off-by-one form.
public struct OffByOne: Codable, Equatable {
    public var value: Int
    public init(value: Int) { self.value = value }

    private enum CodingKeys: String, CodingKey { case stored }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.value = try container.decode(Int.self, forKey: .stored)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value + 1, forKey: .stored)   // BUG
    }
}
