// The subjects of the V1 toy (`scripts/predicate_outcome_reach.py validate`). Each one's outcome
// reach at its stub's own seed is known by construction, and `expected.json` records it. The three
// constants marked TUNED were chosen once from the oracle's draws at the stub's seed and frozen
// (README.md); changing one changes what the toy measures.
import Foundation

public enum Rules {
    public static func isEven(_ value: Int) -> Bool { value % 2 == 0 }
    public static func isWithin(_ value: Int, limit: Int) -> Bool { value <= limit }
    public static func consumesPrefix(_ text: inout String) -> Bool {
        guard let first = text.first else { return false }
        text.removeFirst()
        return first == "a"
    }
    public static func hasControlCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }
    public static func isMagic(_ value: Int) -> Bool { value == 123_456_789 }
    public static func isRepresentable(_ value: Int) -> Bool { value <= Int.max }
    /// TUNED: the residue of the stub's 500th draw, the first draw from the 500th on whose residue
    /// no earlier draw has. So the first 100 draws never return `true` and draw 500 does.
    public static let rareResidue = 566
    public static func isRareResidue(_ value: Int) -> Bool { value % 1_000 == rareResidue }
    public static func indexesSmallTable(_ index: Int) -> Bool { [true, false, true][index] }
}

public struct Point: Equatable, Sendable {
    public var xCoord: Int
    public var yCoord: Int
    public init(xCoord: Int, yCoord: Int) {
        self.xCoord = xCoord
        self.yCoord = yCoord
    }
    public func isRightOf(_ other: Point) -> Bool { xCoord > other.xCoord }
}

public final class Matcher {
    public init() {}
    public func matchesPrefix(_ text: String) -> Bool { text.hasPrefix("ab") }
}

@MainActor public enum Layout {
    public static func isWide(_ width: Int) -> Bool { width > 0 }
    public static func trimsLeading(_ text: inout String) -> Bool {
        let before = text.count
        text = String(text.drop { $0 == " " })
        return text.count < before
    }
}

public func isBlankLine(_ line: String) -> Bool { line.allSatisfy { $0 == " " } }

public enum Faults {
    /// TUNED: the value `trapsLate`'s stub draws 150th at its seed, so only the 1,000-trial run reaches it.
    public static let trapValue = -8_300_438_475_956_774_088
    /// TUNED: the value `spinsLate`'s stub draws 150th at its seed, so only the 1,000-trial run reaches it.
    public static let spinValue = 4_518_500_762_316_687_390
    public static func spinsForever(_ value: Int) -> Bool {
        var spins = value
        while spins == spins { spins &+= 1 }
        return spins > 0
    }
    /// Traps by indexing past a one-element array, not by `precondition`: a `precondition` in the
    /// body keeps `discover` from offering the predicate at all (measured at `fef2971d`).
    public static func trapsLate(_ value: Int) -> Bool {
        [value > 0][value == trapValue ? 1 : 0]
    }
    public static func spinsLate(_ value: Int) -> Bool {
        var spins = value
        while value == spinValue, spins == spins { spins &+= 1 }
        return value > 0
    }
}

public enum Sightings {
    nonisolated(unsafe) static var seen = Set<Int>()
    public static func isFirstSighting(_ value: Int) -> Bool { seen.insert(value).inserted }
}

public enum HashOrder {
    public static func firstOfFourIsEven(_ value: Int) -> Bool {
        Set([value, value &+ 1, value &+ 2, value &+ 3]).first.map { $0 % 2 == 0 } ?? false
    }
    public static func firstOfTwoIsA(_ value: Int) -> Bool { Set(["a", "b"]).first == "a" }
}

public actor Registry {
    public init() {}
    public func holds(_ key: Int) -> Bool { key % 3 == 0 }
}
