import Foundation
import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("TemplateRegistry — contradiction detection (PRD §5.6)")
struct TemplateRegistryContradictionTests {

    @Test("Contradiction pass drops commutativity over non-Equatable return + emits stderr diagnostic")
    func contradictionDropsCommutativityForNonEquatableReturn() {
        let merge = FunctionSummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "Any", isInout: false),
                Parameter(label: nil, internalName: "b", typeText: "Any", isInout: false)
            ],
            returnTypeText: "Any",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Mixer.swift", line: 3, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        var diagnostics: [String] = []
        let suggestions = TemplateRegistry.discover(
            in: [merge],
            diagnostic: { diagnostics.append($0) }
        )
        #expect(suggestions.allSatisfy { $0.templateName != "commutativity" })
        #expect(diagnostics.count == 1)
        let line = diagnostics.first ?? ""
        #expect(line.hasPrefix("contradiction: "))
        #expect(line.contains("commutativity"))
        #expect(line.contains("merge"))
        #expect(line.contains("Mixer.swift:3"))
        #expect(line.contains("PRD §5.6 #2"))
    }

    @Test("Contradiction pass drops round-trip pair when domain is non-Equatable function type")
    func contradictionDropsRoundTripForNonEquatableDomain() {
        let wrap = FunctionSummary(
            name: "wrap",
            parameters: [Parameter(label: nil, internalName: "f", typeText: "(Int) -> Int", isInout: false)],
            returnTypeText: "Data",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Wrap.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let unwrap = FunctionSummary(
            name: "unwrap",
            parameters: [Parameter(label: nil, internalName: "d", typeText: "Data", isInout: false)],
            returnTypeText: "(Int) -> Int",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Wrap.swift", line: 5, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        var diagnostics: [String] = []
        let suggestions = TemplateRegistry.discover(
            in: [wrap, unwrap],
            diagnostic: { diagnostics.append($0) }
        )
        #expect(suggestions.allSatisfy { $0.templateName != "round-trip" })
        #expect(diagnostics.count == 1)
        let line = diagnostics.first ?? ""
        #expect(line.contains("round-trip"))
        #expect(line.contains("PRD §5.6 #3"))
    }

    @Test("Directory scan threads typeDecls through discover and emits contradiction diagnostics")
    func directoryScanFiresContradictionDiagnostic() throws {
        let directory = try writeRegistryFixture(named: "ContradictionDirScan", contents: """
        struct Composer {
            func compose(_ a: (Int) -> Int, _ b: (Int) -> Int) -> (Int) -> Int { return a }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        var diagnostics: [String] = []
        let suggestions = try TemplateRegistry.discover(
            in: directory,
            diagnostic: { diagnostics.append($0) }
        )
        #expect(suggestions.allSatisfy { $0.templateName != "commutativity" })
        #expect(diagnostics.contains { line in
            line.hasPrefix("contradiction: ")
                && line.contains("commutativity")
                && line.contains("compose")
        })
    }
}

@Suite("TemplateRegistry — @Discoverable signal end-to-end (M5.1)")
struct TemplateRegistryDiscoverableTests {

    @Test("@Discoverable(group:) on both halves of a round-trip pair fires the +35 signal end-to-end")
    func discoverableGroupSignalFiresEndToEnd() throws {
        let directory = try writeRegistryFixture(named: "DiscoverableE2E", contents: """
        struct MyType {}
        struct Codec {
            @Discoverable(group: "codec")
            func encode(_ value: MyType) -> Data {
                return Data()
            }
            @Discoverable(group: "codec")
            func decode(_ data: Data) -> MyType {
                return MyType()
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = try TemplateRegistry.discover(in: directory)
        let roundTrip = try #require(suggestions.first { $0.templateName == "round-trip" })
        let discoverable = try #require(
            roundTrip.score.signals.first { $0.kind == .discoverableAnnotation }
        )
        #expect(discoverable.weight == 35)
        #expect(discoverable.detail.contains("codec"))
        // 30 type + 40 curated encode/decode + 35 discoverable = 105 → Strong.
        #expect(roundTrip.score.total == 105)
    }

    @Test("Mismatched @Discoverable groups across the pair leave the +35 signal off")
    func discoverableGroupMismatchSkipsTheSignal() throws {
        let directory = try writeRegistryFixture(named: "DiscoverableMismatch", contents: """
        struct MyType {}
        struct Codec {
            @Discoverable(group: "codec")
            func encode(_ value: MyType) -> Data {
                return Data()
            }
            @Discoverable(group: "queue")
            func decode(_ data: Data) -> MyType {
                return MyType()
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suggestions = try TemplateRegistry.discover(in: directory)
        let roundTrip = try #require(suggestions.first { $0.templateName == "round-trip" })
        #expect(!roundTrip.score.signals.contains { $0.kind == .discoverableAnnotation })
        #expect(roundTrip.score.total == 70)
    }
}
