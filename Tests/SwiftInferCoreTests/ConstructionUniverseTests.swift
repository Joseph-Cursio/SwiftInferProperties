import Foundation
import Testing

@testable import SwiftInferCore

/// **The construction universe's predicate, held to the golden table both consumers share.**
///
/// `docs/construction-universe.tsv` is a byte-identical copy of SwiftProjectLint's
/// `Docs/construction-universe.tsv` (`SEICrossRepoPinTests` asserts the two files are equal when
/// the sibling checkout is present). Each repo asserts its own predicate over every row, so the
/// two implementations of one rule are pinned to one answer key — the substitute for hosting the
/// predicate in SEI, which would make agreement a property of the pin.
@Suite("Construction universe — the shared golden table")
struct ConstructionUniverseTests {

    static let tablePath = URL(fileURLWithPath: #filePath, isDirectory: false)
        .deletingLastPathComponent()   // SwiftInferCoreTests/
        .deletingLastPathComponent()   // Tests/
        .deletingLastPathComponent()   // SwiftInferProperties/
        .appendingPathComponent("docs/construction-universe.tsv")

    struct Row: Sendable, CustomStringConvertible {
        let path: String
        let production: Bool
        var description: String { "\(path) → \(production)" }
    }

    struct Table {
        let header: String
        let rows: [Row]
        let malformed: [String]
    }

    /// The table's rows, after its `path<TAB>production` header. Parsed strictly: a row that is
    /// not exactly two fields with a `true` / `false` second field fails the table test rather
    /// than being skipped.
    static func rows() throws -> Table {
        let text = try String(contentsOf: tablePath, encoding: .utf8)
        var lines = text.components(separatedBy: "\n")
        if lines.last?.isEmpty == true { lines.removeLast() }
        let header = lines.first ?? ""
        var rows: [Row] = []
        var malformed: [String] = []
        for line in lines.dropFirst() {
            let fields = line.components(separatedBy: "\t")
            guard fields.count == 2, ["true", "false"].contains(fields[1]) else {
                malformed.append(line)
                continue
            }
            rows.append(Row(path: fields[0], production: fields[1] == "true"))
        }
        return Table(header: header, rows: rows, malformed: malformed)
    }

    @Test("the table is well formed, and covers both answers")
    func tableIsWellFormed() throws {
        let table = try Self.rows()
        #expect(table.header == "path\tproduction")
        #expect(table.malformed.isEmpty, "malformed rows: \(table.malformed)")
        #expect(table.rows.count >= 20, "\(table.rows.count) rows — the shared answer key lost rows")
        // Bound first: `#expect` treats a key-path argument as throwing.
        let keeps = table.rows.contains(where: \.production)
        let drops = table.rows.contains { !$0.production }
        #expect(keeps)
        #expect(drops)
    }

    @Test("isProductionSource answers every row of the shared table")
    func predicateAnswersTheTable() throws {
        let wrong = try Self.rows().rows.filter {
            ConstructionUniverse.isProductionSource(relativePath: $0.path) != $0.production
        }
        #expect(wrong.isEmpty, """
        The predicate disagrees with the table SwiftProjectLint answers too — the two consumers \
        would build different construction tables from one package: \(wrong)
        """)
    }

    @Test("the named parts of the rule are the shared spec's")
    func namedPartsMatchTheSpec() {
        #expect(ConstructionUniverse.prunedDirectoryNames == ["DerivedData", "Pods", "Carthage", "node_modules"])
        #expect(ConstructionUniverse.isTestTargetDirectory("Tests"))
        #expect(ConstructionUniverse.isTestTargetDirectory("AppTests"))
        #expect(!ConstructionUniverse.isTestTargetDirectory("TestSupport"))
        #expect(!ConstructionUniverse.isTestTargetDirectory("Testing"))
    }
}
