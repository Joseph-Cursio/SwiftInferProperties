import Foundation
import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// The reference oracle `discover` prints — through the real plan, gates, project-type resolver
/// and `Sendable` shims — compiles, once its `fatalError(…)` line is filled in.
///
/// `ReferenceOracleScaffoldWitness` compiles the emitter's shapes with hand-written draws. This one
/// takes nothing by hand: the subjects are scanned out of `ReferenceOracleDiscoverWitness.swift`
/// the way discover scans a target, the scaffold is built by `referenceOracleOutcome`, and that
/// file must hold the result byte for byte. The test target building is the proof that what
/// discover prints for a nested-type array, a drawn struct receiver, a non-`Sendable` class
/// receiver, a type nested beside the owner rather than in it, a typealias nested in the receiver's
/// type, and a member of `extension [Element]` compiles; the witness's `@Test`s passing is the
/// proof the law holds.
@Suite("Reference oracle — what discover prints compiles, and the witness holds it verbatim")
struct ReferenceOracleDiscoverWitnessTests {

    private struct SilentDiagnostics: DiagnosticOutput {
        func writeDiagnostic(_: String) { /* no-op */ }
    }

    static let witnessFile = "ReferenceOracleDiscoverWitness.swift"
    static let fatalLine = #"fatalError("state the reference definition from the docstring, then replace this line")"#

    /// One case: the subject's owner and name, and the body that replaces `fatalError`.
    struct WitnessCase: Sendable {
        let owner: String
        let name: String
        let body: String
    }

    static let cases = [
        WitnessCase(owner: "OracleDiscoverInbox", name: "largest", body: "messages.map(\\.size).max()"),
        WitnessCase(owner: "OracleDiscoverRuler", name: "scaled", body: "Swift.max(unit &* length, 0)"),
        WitnessCase(owner: "OracleDiscoverTally", name: "adding", body: "amount &+ total"),
        WitnessCase(owner: "Shelf", name: "thickened", body: "OracleDiscoverLibrary.Book(pages: book.pages &* 2)"),
        WitnessCase(owner: "OracleDiscoverAccount", name: "isOwned", body: "id == owner"),
        WitnessCase(owner: "[OracleDiscoverBead]", name: "totalWeight", body: "map(\\.weight).reduce(bonus, &+)")
    ]

    /// The scanned functions, and the context discover builds from the same scan.
    struct Scan {
        let summaries: [FunctionSummary]
        let context: SwiftInferCommand.Discover.ReferenceOracleContext
    }

    static func witnessText() throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(witnessFile)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The witness's subjects — everything above the generated region — scanned as discover scans a
    /// target, and the reference-oracle context `discover` would build from that scan.
    static func scan() throws -> Scan {
        let text = try witnessText()
        let subjects = String(text[..<(text.range(of: "// WITNESS-BEGIN")?.lowerBound ?? text.endIndex)])
        let corpus = FunctionScanner.scanCorpus(source: subjects, file: witnessFile)
        let shapes = TypeShapeBuilder.shapes(from: corpus.typeDecls)
        let pipeline = SwiftInferCommand.Discover.PipelineResult(
            suggestions: [],
            packageRoot: nil,
            typeShapesByName: Dictionary(uniqueKeysWithValues: shapes.map { ($0.name, $0) }),
            inheritedTypesByName: ProtocolCoverageMap.inheritedTypesIndex(from: corpus.typeDecls),
            testVisibleTypeNames: SendableShim.testVisibleTypeNames(from: corpus.typeDecls),
            typeAliases: corpus.typeAliases,
            protocolNames: Set(corpus.typeDecls.filter { $0.kind == .protocol }.map(\.qualifiedName)),
            summaries: corpus.summaries,
            docstringAdvice: true
        )
        return Scan(summaries: corpus.summaries, context: .init(pipeline: pipeline))
    }

    /// What discover prints for `owner.name` as its fallback contract, `fatalError` filled in.
    static func printed(owner: String, name: String, body: String) throws -> String {
        let scan = try scan()
        let summary = try #require(scan.summaries.first { $0.name == name && $0.containingTypeName == owner })
        let manifest = SeedManifest(seeds: [.init(file: witnessFile, line: summary.location.line, symbol: name)])
        let laws = SwiftInferCommand.Discover.synthesizeGenericLaws(
            for: manifest, summaries: [summary], covered: [], diagnostics: SilentDiagnostics()
        )
        let doc = try #require(summary.docComment)
        let outcome = SwiftInferCommand.Discover.referenceOracleOutcome(
            for: summary,
            advisory: .fallbackContract(.init(docComment: doc, redHerrings: [])),
            suggestions: laws,
            context: scan.context
        )
        let scaffold = try #require(outcome?.scaffold, "declined: \(outcome?.decline ?? "no outcome")")
        return scaffold.replacingOccurrences(of: fatalLine, with: body)
    }

    @Test("the witness holds what discover prints", arguments: cases)
    func theWitnessHoldsWhatDiscoverPrints(witness: WitnessCase) throws {
        let printed = try Self.printed(owner: witness.owner, name: witness.name, body: witness.body)
        #expect(try Self.witnessText().contains(printed), "regenerate the witness; discover now prints:\n\(printed)")
    }

    /// What the three cases exercise, read off the printed text.
    @Test func theWitnessedCasesDrawThroughTheResolverAndShim() throws {
        let inbox = try Self.printed(owner: "OracleDiscoverInbox", name: "largest", body: "")
        #expect(inbox.contains("extension OracleDiscoverInbox.Message: @unchecked Sendable {}"))
        #expect(inbox.contains(".map { OracleDiscoverInbox.Message(size: $0) }.array(of: 0...8)"))
        let ruler = try Self.printed(owner: "OracleDiscoverRuler", name: "scaled", body: "")
        #expect(ruler.contains("{ (args: (OracleDiscoverRuler, Int)) in args.0.scaled(args.1) =="))
        let tally = try Self.printed(owner: "OracleDiscoverTally", name: "adding", body: "")
        #expect(tally.contains("extension OracleDiscoverTally: @unchecked Sendable {}"))
        #expect(LiftedTestEmitter.isUnresolvedGenerator(inbox + ruler + tally) == false)
    }

    /// The three spellings a file-scope extension or test cannot resolve as declared, read off the
    /// printed text. Each, printed as declared, is a compile error in the witness file:
    /// `extension OracleDiscoverLibrary.Shelf` cannot see `Book` (*cannot find type 'Book' in
    /// scope*), the `@Test`'s binding cannot see `OwnerID`, and `[OracleDiscoverBead]_totalWeight_…`
    /// is not a function name.
    @Test func theWitnessedSpellingsResolveAtFileScope() throws {
        let shelf = try Self.printed(owner: "Shelf", name: "thickened", body: "")
        #expect(shelf.contains(
            "    static func thickened_reference(_ book: OracleDiscoverLibrary.Book) -> OracleDiscoverLibrary.Book {"
        ))
        let account = try Self.printed(owner: "OracleDiscoverAccount", name: "isOwned", body: "")
        #expect(account.contains("{ (args: (OracleDiscoverAccount, OracleDiscoverAccount.OwnerID)) in "))
        let beads = try Self.printed(owner: "[OracleDiscoverBead]", name: "totalWeight", body: "")
        #expect(beads.contains("@Test func OracleDiscoverBead_totalWeight_matchesReferenceDefinition() async {"))
    }
}
