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

    @Test("the unconfigured oracle is named nowhere in production")
    func unconfiguredIsNeverReferenced() {
        let offenders = Self.files(containing: ".unconfigured")
            .subtracting(["SoundPurity.swift", "PackagePurity.swift"])
        #expect(offenders.isEmpty, "production code opts out of the construction table: \(offenders.sorted())")
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
