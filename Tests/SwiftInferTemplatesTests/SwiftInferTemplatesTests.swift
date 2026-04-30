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

    @Test("Idempotence suggestions are sorted by (file, line) for byte-stable output")
    func sortedByLocation() {
        let early = makeIdempotentSummary(file: "B.swift", line: 1)
        let middle = makeIdempotentSummary(file: "A.swift", line: 100)
        let late = makeIdempotentSummary(file: "B.swift", line: 50)
        let suggestions = TemplateRegistry.discover(in: [early, middle, late])
        // Three String -> String functions also cross-pair via round-trip;
        // filter to idempotence so the sort assertion stays focused.
        let locations = suggestions
            .filter { $0.templateName == "idempotence" }
            .compactMap { $0.evidence.first?.location }
        #expect(locations.map(\.file) == ["A.swift", "B.swift", "B.swift"])
        #expect(locations.map(\.line) == [100, 1, 50])
    }

    @Test("Functions that don't match any template are dropped from output")
    func nonMatchingDropped() {
        let matching = makeIdempotentSummary(file: "A.swift", line: 1)
        // Mismatched parameter and return types — no idempotence (1 param
        // needed), no commutativity (params would need to match each
        // other and the return type), and there's no second function to
        // pair with for round-trip.
        let nonMatching = FunctionSummary(
            name: "tickle",
            parameters: [
                Parameter(label: "from", internalName: "src", typeText: "Int", isInout: false),
                Parameter(label: "to", internalName: "dst", typeText: "String", isInout: false)
            ],
            returnTypeText: "Bool",
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

    @Test("Both idempotence and round-trip fire over a mixed corpus")
    func bothTemplatesFire() {
        let normalize = makeIdempotentSummary(file: "A.swift", line: 1)
        let encode = FunctionSummary(
            name: "encode",
            parameters: [Parameter(label: nil, internalName: "v", typeText: "MyType", isInout: false)],
            returnTypeText: "Data",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "B.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let decode = FunctionSummary(
            name: "decode",
            parameters: [Parameter(label: nil, internalName: "d", typeText: "Data", isInout: false)],
            returnTypeText: "MyType",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "B.swift", line: 5, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let suggestions = TemplateRegistry.discover(in: [normalize, encode, decode])
        let templates = suggestions.map(\.templateName)
        #expect(templates.contains("idempotence"))
        #expect(templates.contains("round-trip"))
        #expect(suggestions.count == 2)
    }

    @Test("Associativity reducer-fold signal aggregates corpus-wide via TemplateRegistry.discover")
    func associativityReducerOpsAggregateAcrossSummaries() throws {
        // `combine` is in the curated commutativity list (shared with
        // associativity per v0.2 §5.2 naming), and its name appears as
        // the closure-position arg of `.reduce(0, combine)` in `driver`'s
        // body. The registry must union reducer-op references across
        // summaries before invoking the associativity template — the
        // signal then fires even though `combine` itself never calls
        // reduce in its own body.
        let combine = FunctionSummary(
            name: "combine",
            parameters: [
                Parameter(label: nil, internalName: "lhs", typeText: "Int", isInout: false),
                Parameter(label: nil, internalName: "rhs", typeText: "Int", isInout: false)
            ],
            returnTypeText: "Int",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "A.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let driver = FunctionSummary(
            name: "driver",
            parameters: [Parameter(label: nil, internalName: "xs", typeText: "[Int]", isInout: false)],
            returnTypeText: "Int",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "A.swift", line: 10, column: 1),
            containingTypeName: nil,
            bodySignals: BodySignals(
                hasNonDeterministicCall: false,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: [],
                reducerOpsReferenced: ["combine"]
            )
        )
        let suggestions = TemplateRegistry.discover(in: [combine, driver])
        let associativity = try #require(suggestions.first { $0.templateName == "associativity" })
        // 30 type + 40 curated `combine` + 20 reducer = 90 → Strong.
        #expect(associativity.score.total == 90)
        #expect(associativity.score.tier == .strong)
    }

    @Test("Identity-element fires on (T, T) -> T op + same-typed static identity via discover(in:directory:)")
    func identityElementFromDirectoryScan() throws {
        // End-to-end: a single .swift file with a binary-op merge plus an
        // identity-shaped `empty` constant on the same type, plus a driver
        // that uses `merge` as a reducer with `.empty` as the seed. The
        // registry should compose the identity-element suggestion at
        // Strong (30 + 40 + 20 = 90) without any explicit identities
        // parameter — directory scan threads through `scanCorpus`.
        let directory = try writeFixture(named: "IdentityElementCorpus", contents: """
        struct IntSet {
            static let empty: IntSet = IntSet()
            func merge(_ lhs: IntSet, _ rhs: IntSet) -> IntSet { return lhs }
        }
        struct Driver {
            func fold(_ xs: [IntSet]) -> IntSet {
                return xs.reduce(.empty, IntSet.merge)
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = try TemplateRegistry.discover(in: directory)
        let identityElement = try #require(
            suggestions.first { $0.templateName == "identity-element" }
        )
        #expect(identityElement.score.total == 90)
        #expect(identityElement.score.tier == .strong)
    }

    @Test("Idempotence and round-trip suggestions interleave by (file, line)")
    func interleavedSorting() {
        let earlyNormalize = makeIdempotentSummary(file: "A.swift", line: 50)
        let encode = FunctionSummary(
            name: "encode",
            parameters: [Parameter(label: nil, internalName: "v", typeText: "MyType", isInout: false)],
            returnTypeText: "Data",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "A.swift", line: 10, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let decode = FunctionSummary(
            name: "decode",
            parameters: [Parameter(label: nil, internalName: "d", typeText: "Data", isInout: false)],
            returnTypeText: "MyType",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "A.swift", line: 20, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let suggestions = TemplateRegistry.discover(in: [earlyNormalize, encode, decode])
        // round-trip is anchored at encode (line 10), idempotence at line 50.
        #expect(suggestions.map(\.templateName) == ["round-trip", "idempotence"])
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
