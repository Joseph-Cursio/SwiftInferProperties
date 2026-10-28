// #669's uniquifier law, prototyped by hand for SwiftInferProperties' kill arm
// (`docs/plans/uniquifier-law-census-scope.md` §5.2). It is copied into an export of SwiftUMLStudio's
// `SwiftUMLBridgeFrameworkTests` target by `scripts/uniquifier_kill_arm.py`, never into SwiftUMLStudio itself.
//
// The law: one receiver, n calls, n distinct results, apart from the guard's sentinel. A memoizing uniquifier
// owes the other form: equal keys give equal ids, and distinct keys give distinct ids.
//
// The names are drawn so a drawn name can equal another drawn name plus the suffix the subject appends:
// `uniqName` appends its diagram-wide counter's digits (`a0`, `a10`), and `DiagramIdentifiers` appends
// `_2`, `_3`, …. A generator drawing realistic names never collides, and so never fails.
import Testing
@testable import SwiftUMLBridgeFramework

/// SplitMix64, so every run draws the same sequences on one toolchain.
struct UniquifierLawRandom: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

/// The draws both suites share.
enum UniquifierLawDraws {
    static let trials = 1_000
    static let kinds: [ElementKind] = [.class, .struct, .enum, .protocol, .extension, .macro]
    static let suffixes = ["0", "1", "2", "10", "11", "_2"]

    /// A base of `a` or `b`, bare half the time and otherwise followed by a suffix `uniqName` or a reader could
    /// write: digits from the counter's range, two-digit ones included, and `_2`.
    static func name(_ rng: inout UniquifierLawRandom) -> String {
        let base = Bool.random(using: &rng) ? "a" : "b"
        return Bool.random(using: &rng) ? base : base + suffixes[Int.random(in: 0..<suffixes.count, using: &rng)]
    }

    /// Half the trials draw 1–16 items over every name `name(_:)` spells. The other half are dense: 11–24 items
    /// over `a`, `a1`, `b` and `b1` only, so a repeated `a1` takes `a10` early and the counter reaches `10` on a
    /// repeated `a` within one sequence. Kinds and names are drawn independently.
    static func items(_ rng: inout UniquifierLawRandom) -> [SyntaxStructure] {
        let dense = Bool.random(using: &rng)
        let count = dense ? Int.random(in: 11...24, using: &rng) : Int.random(in: 1...16, using: &rng)
        let denseNames = ["a", "a1", "b", "b1"]
        return (0..<count).map { _ in
            SyntaxStructure(
                kind: kinds[Int.random(in: 0..<kinds.count, using: &rng)],
                name: dense ? denseNames[Int.random(in: 0..<denseNames.count, using: &rng)] : name(&rng)
            )
        }
    }

    /// The relationship each emitter names an element with (`ElementKind.classNode`, and `"macro"`).
    static func relationship(of item: SyntaxStructure) -> String {
        switch item.kind {
        case .extension: "ext"
        case .macro: "macro"
        case .protocol: "conforms to"
        case .enum: ""
        default: "inherits"
        }
    }

    /// Whether `format` declares `item` under its alias: Mermaid and Nomnoml write a macro only as a comment.
    static func declaresIdentifier(_ item: SyntaxStructure, in format: DiagramFormat) -> Bool {
        item.kind != .macro || format == .plantuml
    }

    /// Checks one format's aliases, records the first colliding pair, and prints a summary line the kill arm
    /// compares across runs (RC6).
    static func checkAliases(_ property: String, format: DiagramFormat, seed: UInt64, reserving: Bool) {
        var rng = UniquifierLawRandom(state: seed)
        var failures = 0
        var firstFailure: String?
        for trial in 0..<trials {
            let items = items(&rng)
            let context = DiagramContext(configuration: Configuration(format: format))
            if reserving {
                context.reserveIdentifiers(drawing: items)
            }
            let aliases = items.map { context.uniqName(item: $0, relationship: relationship(of: $0)) }
            var issued: [String: Int] = [:]
            for (position, item) in items.enumerated() where declaresIdentifier(item, in: format) {
                if let earlier = issued[aliases[position]] {
                    failures += 1
                    if firstFailure == nil {
                        let describe = { (index: Int) in "\(items[index].kind.map { "\($0)" } ?? "nil") \(items[index].name ?? "nil")" }
                        firstFailure = "trial \(trial): `\(describe(earlier))` (call \(earlier + 1)) and "
                            + "`\(describe(position))` (call \(position + 1)) both got `\(aliases[position])`; sequence "
                            + items.map { "\($0.kind.map { "\($0)" } ?? "nil") \($0.name ?? "nil")" }.joined(separator: ", ")
                    }
                    break
                }
                issued[aliases[position]] = position
            }
        }
        print("UNIQUIFIER-LAW \(property) format=\(format) trials=\(trials) failures=\(failures)")
        if let firstFailure {
            Issue.record("\(property) (\(format)): \(failures) sequences issue one alias twice; first: \(firstFailure)")
        }
    }
}

@Suite("#669 uniquifier law (hand prototype)")
struct UniquifierLawTests {
    @Test("U1: after reserveIdentifiers, uniqName issues no alias twice", arguments: DiagramFormat.allCases)
    func aliasesAreDistinct(format: DiagramFormat) {
        let seed = 669_100 + UInt64(DiagramFormat.allCases.firstIndex(of: format) ?? 0)
        UniquifierLawDraws.checkAliases("U1", format: format, seed: seed, reserving: true)
    }

    /// Keys drawn from a pool of three to six strings over characters `mermaidId` rewrites to `_`, plus `2`, so
    /// distinct keys collide when sanitized and a sanitized key can spell another's `_2`; 1–16 lookups, so keys
    /// repeat.
    @Test("M1: DiagramIdentifiers gives equal keys equal ids and distinct keys distinct ids")
    func identifiersAreMemoizedAndDistinct() {
        let characters = ["a", "_", ".", "-", "2"]
        var rng = UniquifierLawRandom(state: 669_200)
        var failures = 0
        var firstFailure: String?
        for trial in 0..<UniquifierLawDraws.trials {
            let pool = (0..<Int.random(in: 3...6, using: &rng)).map { _ in
                (0..<Int.random(in: 1...3, using: &rng)).map { _ in characters[Int.random(in: 0..<5, using: &rng)] }
                    .joined()
            }
            let keys = (0..<Int.random(in: 1...16, using: &rng)).map { _ in pool[Int.random(in: 0..<pool.count, using: &rng)] }
            var table = DiagramIdentifiers(sanitize: DepsScript.mermaidId)
            let ids = keys.map { table.id(for: $0) }
            search: for first in keys.indices {
                for second in keys.indices where second > first && (keys[first] == keys[second]) != (ids[first] == ids[second]) {
                    failures += 1
                    if firstFailure == nil {
                        firstFailure = "trial \(trial): keys `\(keys[first])` (call \(first + 1)) and `\(keys[second])` "
                            + "(call \(second + 1)) got `\(ids[first])` and `\(ids[second])`; keys \(keys)"
                    }
                    break search
                }
            }
        }
        print("UNIQUIFIER-LAW M1 trials=\(UniquifierLawDraws.trials) failures=\(failures)")
        if let firstFailure {
            Issue.record("M1: \(failures) sequences break the memoizing law; first: \(firstFailure)")
        }
    }
}

/// #669's law exactly as the issue states it: a fresh receiver and n calls, with nothing called first. U1's draw
/// generator, on seeds of its own. Run once on the unmutated export as a measurement (S0), never in the kill loop:
/// `uniqName`'s contract asks for `reserveIdentifiers` first.
@Suite("#669 uniquifier law without the contract's setup (control)")
struct UniquifierLawSetupFreeTests {
    @Test("U0: a fresh DiagramContext's uniqName issues no alias twice", arguments: DiagramFormat.allCases)
    func aliasesAreDistinctWithoutSetup(format: DiagramFormat) {
        let seed = 669_000 + UInt64(DiagramFormat.allCases.firstIndex(of: format) ?? 0)
        UniquifierLawDraws.checkAliases("U0", format: format, seed: seed, reserving: false)
    }
}
