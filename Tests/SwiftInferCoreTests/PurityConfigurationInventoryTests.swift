import Foundation
import SwiftInferCore
import Testing

/// **Every purity oracle in `Sources/` holds its project's construction facts — read off the
/// source, not trusted.**
///
/// SEI's warning on `PurityInferrer.constructionFacts` is that one inferrer left at `.empty`
/// silently disagrees with the configured ones. Nothing at runtime can notice that: an
/// unconfigured inferrer answers, plausibly, for the wrong package. So the places an oracle can be
/// built are inventoried here, as text, and a new one anywhere else fails this suite until someone
/// decides on purpose which table it holds.
@Suite("Purity configuration — where an oracle can be built")
struct PurityConfigurationInventoryTests {

    struct SourceFile {
        let name: String
        /// The file with `//` comments removed, so documentation naming a constructor is not a
        /// call site.
        let code: String
    }

    static let sources: [SourceFile] = {
        let root = CensusPurity.packageRoot.appendingPathComponent("Sources")
        return SwiftSourceFiles.sorted(in: root).compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let lines = text.components(separatedBy: "\n").map(withoutComment)
            return SourceFile(name: url.lastPathComponent, code: lines.joined(separator: "\n"))
        }
    }()

    static func withoutComment(_ line: String) -> String {
        line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? line
    }

    static func files(containing needle: String) -> Set<String> {
        Set(sources.filter { $0.code.contains(needle) }.map(\.name))
    }

    @Test("the inventory read the sources it claims to")
    func inventoryIsNotEmpty() {
        #expect(Self.sources.count > 500, "read \(Self.sources.count) files — the walk lost Sources/")
    }

    @Test("a PurityInferrer is built in SoundPurity alone")
    func inferrerIsBuiltInOnePlace() {
        #expect(Self.files(containing: "PurityInferrer(") == ["SoundPurity.swift"])
    }

    @Test("a SoundPurity is configured only where a table is built")
    func soundPurityIsConfiguredWhereTheTableIs() {
        let configuring = Self.files(containing: "SoundPurity(constructionFacts:")
        #expect(configuring.contains("PackagePurity.swift"), "PackagePurity no longer configures the oracle")
        #expect(configuring.isSubset(of: ["SoundPurity.swift", "PackagePurity.swift"]), "\(configuring.sorted())")
        #expect(
            Self.files(containing: ".build(from:") == ["PackagePurity.swift"],
            "a construction table is built somewhere other than PackagePurity"
        )
    }

    /// The one production opt-out, and why it is one: `FunctionScanner.scanTypeDecls(directory:)`
    /// reads declarations only, and no verdict its walk computes leaves the function. Every other
    /// file naming the unconfigured oracle is a scan that would judge without its table.
    static let declarationsOnlyScan = "FunctionScanner+Declarations.swift"

    @Test("the unconfigured oracle is named nowhere in production but the declarations-only scan")
    func unconfiguredIsNeverReferenced() {
        let offenders = Self.files(containing: ".unconfigured")
            .subtracting(["SoundPurity.swift", "PackagePurity.swift", Self.declarationsOnlyScan])
        #expect(offenders.isEmpty, "production code opts out of the construction table: \(offenders.sorted())")
        let declarationsOnly = Self.sources.first { $0.name == Self.declarationsOnlyScan }
        #expect(declarationsOnly?.code.contains("-> [TypeDecl]") == true, "the allow-listed file stopped declaring")
        #expect(declarationsOnly?.code.contains("ScannedCorpus {") == false, "the allow-listed file returns verdicts")
    }

    /// `PackagePurity.forJudging(directory:)` returns no purity when the directory holds no Swift
    /// file; the unguarded `forScan(of:)` parses the whole universe regardless. Measured on
    /// `discover-reducers` over an empty folder in a swift-syntax copy: 0.03 s / 12 MB guarded,
    /// 1.30 s / 379 MB not. So production builds a purity through the guard and nowhere else.
    @Test("a purity is built in production only through the judged-set guard")
    func purityIsBuiltOnlyThroughTheGuard() {
        #expect(
            Self.files(containing: "forScan(of:") == ["PackagePurity.swift"],
            "an unguarded purity build: \(Self.files(containing: "forScan(of:").sorted())"
        )
        #expect(Self.files(containing: "forJudging(directory:").isSuperset(of: [
            "FunctionScanner+Package.swift", "TypeShapeCarriers.swift",
            "ValueSemanticVerifier.swift", "CensusCommand.swift"
        ]))
    }

    /// The callers that read only `typeDecls` scan declarations only. Through
    /// `scanCorpus(directory:)` each paid for a construction universe and its table and read none
    /// of it: `index --scan-dependencies` went from ~75 MB to ~410 MB peak RSS with identical output.
    @Test("the declarations-only callers build no construction table")
    func declarationsOnlyCallersBuildNoTable() {
        let callers: Set = ["DependencyTypeShapes.swift", "VerifyInteractionPipeline+RefintGate.swift"]
        #expect(Self.files(containing: "scanTypeDecls(directory:").isSuperset(of: callers))
        let full = Self.files(containing: "scanCorpus(directory:").intersection(callers)
        #expect(full.isEmpty, "a declarations-only caller runs the full scan: \(full.sorted())")
    }

    @Test("every scanner visitor is handed an oracle, in the scanner's own files")
    func everyVisitorIsHandedAnOracle() {
        let constructing = Self.sources.filter { $0.code.contains("FunctionScannerVisitor(") }
        #expect(Set(constructing.map(\.name)) == ["FunctionScanner.swift"])
        for file in constructing {
            let calls = file.code.components(separatedBy: "FunctionScannerVisitor(").dropFirst()
            for call in calls {
                let arguments = call.prefix { $0 != ")" }
                #expect(arguments.contains("purity:"), "\(file.name) builds a visitor with no oracle")
            }
        }
    }
}
