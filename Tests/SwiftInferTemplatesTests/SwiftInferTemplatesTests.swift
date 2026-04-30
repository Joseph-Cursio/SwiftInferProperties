import Foundation
import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("TemplateRegistry — discovery orchestration over multiple summaries")
struct TemplateRegistryTests {

    @Test("Empty corpus produces no suggestions")
    func emptyCorpus() {
        #expect(TemplateRegistry.discover(in: []).isEmpty)
    }

    @Test("Suggestions are sorted by (file, line) for byte-stable output")
    func sortedByLocation() {
        let early = makeIdempotentSummary(file: "B.swift", line: 1)
        let middle = makeIdempotentSummary(file: "A.swift", line: 100)
        let late = makeIdempotentSummary(file: "B.swift", line: 50)
        let suggestions = TemplateRegistry.discover(in: [early, middle, late])
        let locations = suggestions.compactMap { $0.evidence.first?.location }
        #expect(locations.map(\.file) == ["A.swift", "B.swift", "B.swift"])
        #expect(locations.map(\.line) == [100, 1, 50])
    }

    @Test("Functions that don't match any template are dropped from output")
    func nonMatchingDropped() {
        let matching = makeIdempotentSummary(file: "A.swift", line: 1)
        let nonMatching = FunctionSummary(
            name: "tickle",
            parameters: [
                Parameter(label: "from", internalName: "src", typeText: "Int", isInout: false),
                Parameter(label: "to", internalName: "dst", typeText: "Int", isInout: false)
            ],
            returnTypeText: "Int",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "B.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let suggestions = TemplateRegistry.discover(in: [matching, nonMatching])
        #expect(suggestions.count == 1)
        #expect(suggestions.first?.evidence.first?.location.file == "A.swift")
    }

    @Test("Directory scan integration over a single fixture file")
    func directoryScanIntegration() throws {
        let directory = try writeFixture(named: "RegistryDirScan", contents: """
        struct Sanitizer {
            func normalize(_ s: String) -> String {
                return normalize(normalize(s))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = try TemplateRegistry.discover(in: directory)
        #expect(suggestions.count == 1)
        let suggestion = try #require(suggestions.first)
        #expect(suggestion.templateName == "idempotence")
        #expect(suggestion.score.tier == .strong)
    }

    private func makeIdempotentSummary(file: String, line: Int) -> FunctionSummary {
        FunctionSummary(
            name: "normalize",
            parameters: [Parameter(label: nil, internalName: "v", typeText: "String", isInout: false)],
            returnTypeText: "String",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: file, line: line, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }

    private func writeFixture(named name: String, contents: String) throws -> URL {
        let directoryName = "SwiftInferTests-\(name)-\(UUID().uuidString)"
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(directoryName)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let file = base.appendingPathComponent("Sanitizer.swift")
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return base
    }
}
