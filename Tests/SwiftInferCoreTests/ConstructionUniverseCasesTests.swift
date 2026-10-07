import Foundation
import Testing

@testable import SwiftInferCore

/// **The construction universe's manifest reader and order, held to the cases file both consumers
/// share.**
///
/// `docs/construction-universe-cases.json` is a byte-identical copy of SwiftProjectLint's
/// `Docs/construction-universe-cases.json` (`SEICrossRepoPinTests` asserts the two files are equal
/// when the sibling checkout is present) — the shared spec's amendment E. The `.tsv` beside it pins
/// the predicate; this pins the other parts of the rule a disagreement would hide in: which
/// nested packages a manifest reaches (`localPackageDependencies(manifest:)` and, since amendment R,
/// `localTargetPaths(manifest:)`) and the order the facts are built in (`buildOrder(_:)`).
@Suite("Construction universe — the shared cases file")
struct ConstructionUniverseCasesTests {

    static let casesPath = URL(fileURLWithPath: #filePath, isDirectory: false)
        .deletingLastPathComponent()   // SwiftInferCoreTests/
        .deletingLastPathComponent()   // Tests/
        .deletingLastPathComponent()   // SwiftInferProperties/
        .appendingPathComponent("docs/construction-universe-cases.json")

    struct ManifestCase: Decodable, CustomStringConvertible {
        let manifest: String
        /// `nil` is the doubt rule: a computed `path:`.
        let expected: [String]?
        var description: String { manifest }
    }

    struct ManifestTextCase: Decodable, CustomStringConvertible {
        let text: String
        let expected: Bool
        var description: String { "\(text.debugDescription) → \(expected)" }
    }

    struct Cases: Decodable {
        let localPackageDependencies: [ManifestCase]
        let localTargetPaths: [ManifestCase]
        let buildOrder: [String]
        let isManifest: [ManifestTextCase]
    }

    static func cases() throws -> Cases {
        try JSONDecoder().decode(Cases.self, from: Data(contentsOf: casesPath))
    }

    @Test("localPackageDependencies answers every shared case")
    func manifestCasesHold() throws {
        let cases = try Self.cases().localPackageDependencies
        #expect(cases.count >= 8, "\(cases.count) cases — the shared answer key lost rows")
        #expect(cases.contains { $0.expected == nil }, "the doubt rule has no case")
        #expect(cases.contains { $0.expected?.isEmpty == true }, "the no-dependency answer has no case")
        // Amendment H: the reader returns the value the compiler sees, so some case must spell a
        // path differently from its value — an escape and a raw string do.
        #expect(cases.contains { $0.manifest.contains(#"\u{"#) }, "no case escapes a path")
        #expect(cases.contains { $0.manifest.contains(##"#""##) }, "no case is a raw string")
        let wrong = cases.filter { ConstructionUniverse.localPackageDependencies(manifest: $0.manifest) != $0.expected }
        #expect(wrong.isEmpty, """
        The manifest reader disagrees with the cases SwiftProjectLint answers too — the two \
        consumers would bound one root's nested packages differently: \(wrong)
        """)
    }

    /// Amendment R: the target paths a manifest names (amendment P), read as the dependencies are.
    @Test("localTargetPaths answers every shared case")
    func targetPathCasesHold() throws {
        let cases = try Self.cases().localTargetPaths
        #expect(cases.count >= 6, "\(cases.count) cases — the shared answer key lost rows")
        #expect(cases.contains { $0.expected == nil }, "the doubt rule has no case")
        #expect(cases.contains { $0.expected?.isEmpty == true }, "the no-target-path answer has no case")
        let wrong = cases.filter { ConstructionUniverse.localTargetPaths(manifest: $0.manifest) != $0.expected }
        #expect(wrong.isEmpty, """
        The target-path reader disagrees with the cases SwiftProjectLint answers too — the two \
        consumers would reach different nested packages from one root: \(wrong)
        """)
    }

    /// Amendment U: what SwiftPM loads as a manifest (amendment S) — leading blank lines, the label
    /// in any case, the comment after other lines from 6.0 — answered alike by both repos.
    @Test("isManifest answers every shared case")
    func manifestTextCasesHold() throws {
        let cases = try Self.cases().isManifest
        #expect(cases.count >= 28, "\(cases.count) cases — the shared answer key lost rows")
        // Bound first: `#expect` treats a key-path argument as throwing.
        let accepts = cases.contains(where: \.expected)
        let rejects = cases.contains { !$0.expected }
        #expect(accepts && rejects, "both answers need a case")
        let wrong = cases.filter { ConstructionUniverse.isManifest($0.text) != $0.expected }
        #expect(wrong.isEmpty, """
        The manifest test disagrees with the cases SwiftProjectLint answers too — the two consumers \
        would draw different package boundaries in one root: \(wrong)
        """)
    }

    @Test("buildOrder is the shared order, whatever order the paths arrive in")
    func buildOrderIsTheSharedOrder() throws {
        let order = try Self.cases().buildOrder
        #expect(order.count >= 8, "\(order.count) paths — the shared order lost rows")
        #expect(ConstructionUniverse.buildOrder(order) == order)
        #expect(ConstructionUniverse.buildOrder(order.reversed()) == order)
        var generator = SplitMix64(seed: 0x5EED)
        for _ in 0..<32 {
            #expect(ConstructionUniverse.buildOrder(order.shuffled(using: &generator)) == order)
        }
    }

    /// The file is only a guard if it can tell the shared order from its plausible neighbours: a
    /// case-insensitive sort, a numeric one, and a sort by path component — which differs from
    /// `String <` wherever `-` or `.` meets `/` (`Sources/A-B/X.swift` sorts before
    /// `Sources/A/X.swift` under `String <`, after it per component; the shared spec's amendment N
    /// added that pair after a per-component mutant passed both repos). All three disagree with it.
    @Test("the shared order is not a case-insensitive, numeric or per-component order")
    func sharedOrderDiscriminates() throws {
        let order = try Self.cases().buildOrder
        let finder = order.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let caseless = order.sorted { $0.lowercased() < $1.lowercased() }
        let perComponent = order.sorted {
            $0.split(separator: "/").lexicographicallyPrecedes($1.split(separator: "/"))
        }
        #expect(finder != order)
        #expect(caseless != order)
        #expect(perComponent != order)
    }
}

/// A seeded generator, so the shuffles above are the same on every run.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
