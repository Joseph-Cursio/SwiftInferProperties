import Foundation
import SwiftEffectInference
import SwiftParser
import Testing

@testable import SwiftInferCore

// MARK: - The order, pinned exactly

extension ConstructionUniverseSymlinkTests {

    /// **`String <`, and nothing near it.** The review's mutant sorted with
    /// `localizedStandardCompare` — case-insensitive and numeric — and every suite stayed green:
    /// their paths sorted the same under either. Here they do not (`B` < `F10` < `F2` < `Lib` < `a`
    /// under `String <`; `a`, `B`, `F2`, `F10`, `Lib` under Finder's order), and two pairs of
    /// same-named types carry different witnesses, so the order decides which witness SEI reports
    /// first for each: the clock (`B`'s `Stamp`, `F10`'s `Mark`), not the identifier.
    @Test("the universe is ordered by String <, and the order decides each witness")
    func universeOrderIsStringLessThan() throws {
        let files = [
            "Sources/B/Stamp.swift": "struct Stamp { let at = Date() }",
            "Sources/a/Stamp.swift": "struct Stamp { let id = UUID() }",
            "Sources/F10/Mark.swift": "struct Mark { let at = Date() }",
            "Sources/F2/Mark.swift": "struct Mark { let id = UUID() }",
            "Sources/Lib/Make.swift": "func makeStamp() -> Stamp { Stamp() }\nfunc makeMark() -> Mark { Mark() }",
        ]
        let root = try Wiring.makePackage(files)
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appendingPathComponent("Sources/Lib")
        let purity = PackagePurity.forScan(of: lib)
        let expected = [
            "Sources/B/Stamp.swift", "Sources/F10/Mark.swift", "Sources/F2/Mark.swift",
            "Sources/Lib/Make.swift", "Sources/a/Stamp.swift",
        ]
        #expect(purity.universe == expected)

        // The fixture can fail: Finder's order builds a different digest.
        let digest = { (order: [String]) -> [String] in
            let facts = ConstructionFacts.build(from: order.map { Parser.parse(source: files[$0] ?? "") })
            return facts.refutedTypeNames.map { "\($0): \(facts.refutation(constructing: $0)?.description ?? "?")" }
        }
        let finder = expected.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        #expect(digest(finder) != digest(expected), "the fixture must be order-sensitive, or this test cannot fail")
        #expect(purity.refutedTypes == digest(expected))

        let tree = try #require(purity.tree(for: lib.appendingPathComponent("Make.swift")))
        for (name, type) in [("makeStamp", "Stamp"), ("makeMark", "Mark")] {
            let function = try #require(Wiring.function(named: name, in: tree))
            #expect(purity.oracle.verdict(for: function) == .refuted)
            let witness = purity.oracle.inferrerRefutation(for: function)
            guard case .refutingConstruction(type: type, via: .storedProperty("at"), cause: _) = witness else {
                let got = String(describing: witness)
                Issue.record("\(name): expected the clock witness of the first `\(type)` in String < order, got \(got)")
                continue
            }
        }
    }
}
