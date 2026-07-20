import Foundation

// Verify-ready corpus for the codable-round-trip template. Two hand-written
// custom `Codable` conformances: a faithful codec (bothPass) and a buggy one
// reproducing the swift-asn1 scale-bug class (defaultFails). Both keyed
// containers (avoid top-level JSON fragment edge cases) and `Equatable`.

/// Faithful custom codec — `decode(encode(x)) == x` for every value → bothPass.
public struct Temperature: Codable, Equatable {
    public var celsius: Double
    public init(celsius: Double) { self.celsius = celsius }

    private enum CodingKeys: String, CodingKey { case celsius }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.celsius = try container.decode(Double.self, forKey: .celsius)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(celsius, forKey: .celsius)
    }
}

/// Buggy custom codec — the swift-asn1 class of bug. `encode` scales by 100,
/// `init(from:)` unscales by 1000, so `decode(encode(x)) != x` for x != 0
/// → defaultFails.
public struct ScaledRatio: Codable, Equatable {
    public var value: Double
    public init(value: Double) { self.value = value }

    private enum CodingKeys: String, CodingKey { case scaled }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let scaled = try container.decode(Int.self, forKey: .scaled)
        self.value = Double(scaled) / 1000.0   // BUG: encode used 100
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Int(value * 100), forKey: .scaled)
    }
}
