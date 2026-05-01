import Foundation
import Testing
import SwiftInferCore

/// PRD v0.3 §5.6 / M3.6 acceptance-bar (c) integration suite for
/// `EquatableResolver`. Closes the bar by exercising the three-state
/// `.equatable` / `.notEquatable` / `.unknown` semantics against
/// real on-disk fixture corpora rather than synthesised `TypeDecl`s —
/// the unit-level `EquatableResolverTests` covers the in-memory paths
/// already.
///
/// Each test writes a multi-file Swift fixture to a temp dir, runs
/// `FunctionScanner.scanCorpus(directory:)` to harvest `TypeDecl`s
/// the way the production `discover` pipeline does, builds an
/// `EquatableResolver` from those records, and asserts the
/// classification matches the M3 plan's spec.
@Suite("EquatableResolver — fixture-corpus integration (M3.6)")
struct EquatableResolverIntegrationTests {

    @Test("Curated stdlib types classify .equatable from a real fixture scan")
    func curatedStdlibClassifiesAsEquatable() throws {
        // No corpus typeDecls needed for stdlib classification — the
        // resolver's curated list is consulted before corpus lookup.
        let directory = try writeFixture(named: "StdlibClassify", files: [:])
        defer { try? FileManager.default.removeItem(at: directory) }
        let corpus = try FunctionScanner.scanCorpus(directory: directory)
        let resolver = EquatableResolver(typeDecls: corpus.typeDecls)
        for stdlibType in ["Int", "String", "Bool", "Double", "Float", "UUID", "Date", "URL"] {
            #expect(resolver.classify(typeText: stdlibType) == .equatable, "expected \(stdlibType) → .equatable")
        }
    }

    @Test("Curated non-Equatable shapes classify .notEquatable from a real fixture scan")
    func curatedNonEquatableShapesClassifyAsNotEquatable() throws {
        let directory = try writeFixture(named: "NonEqShapes", files: [:])
        defer { try? FileManager.default.removeItem(at: directory) }
        let corpus = try FunctionScanner.scanCorpus(directory: directory)
        let resolver = EquatableResolver(typeDecls: corpus.typeDecls)
        for shape in ["Any", "AnyObject", "(Int) -> Int", "some Hashable", "any Error"] {
            #expect(resolver.classify(typeText: shape) == .notEquatable, "expected \(shape) → .notEquatable")
        }
    }

    @Test("Multi-file corpus lifts struct-declared : Equatable to .equatable")
    func multiFileCorpusLiftsStructEquatable() throws {
        let directory = try writeFixture(named: "MultiFileEq", files: [
            "Money.swift": """
            struct Money: Equatable {
                let amount: Int
            }
            """,
            "Order.swift": """
            struct Order {
                let lines: Int
            }
            """
        ])
        defer { try? FileManager.default.removeItem(at: directory) }
        let corpus = try FunctionScanner.scanCorpus(directory: directory)
        let resolver = EquatableResolver(typeDecls: corpus.typeDecls)
        #expect(resolver.classify(typeText: "Money") == .equatable)
        #expect(resolver.classify(typeText: "Order") == .unknown)
    }

    @Test("Cross-file extension-only Equatable conformance lifts the primary type")
    func crossFileExtensionLiftsPrimaryType() throws {
        // Open decision #2's mergeable-multimap shape: the primary
        // `struct Foo` is declared in one file and the
        // `extension Foo: Equatable` lives in another. Resolver folds
        // both `TypeDecl` records keyed by `Foo` and lifts to .equatable.
        let directory = try writeFixture(named: "CrossFileExtension", files: [
            "Foo.swift": """
            struct Foo {
                let raw: Int
            }
            """,
            "Foo+Equatable.swift": """
            extension Foo: Equatable {}
            """
        ])
        defer { try? FileManager.default.removeItem(at: directory) }
        let corpus = try FunctionScanner.scanCorpus(directory: directory)
        let resolver = EquatableResolver(typeDecls: corpus.typeDecls)
        #expect(resolver.classify(typeText: "Foo") == .equatable)
    }

    @Test("Hashable / Comparable conformance lifts via KnownEquatableConformance")
    func hashableAndComparableConformanceImpliesEquatable() throws {
        let directory = try writeFixture(named: "HashableComparableLift", files: [
            "Token.swift": """
            struct Token: Hashable {
                let raw: String
            }
            """,
            "Version.swift": """
            struct Version: Comparable {
                let major: Int
                static func < (lhs: Version, rhs: Version) -> Bool { lhs.major < rhs.major }
            }
            """
        ])
        defer { try? FileManager.default.removeItem(at: directory) }
        let corpus = try FunctionScanner.scanCorpus(directory: directory)
        let resolver = EquatableResolver(typeDecls: corpus.typeDecls)
        #expect(resolver.classify(typeText: "Token") == .equatable)
        #expect(resolver.classify(typeText: "Version") == .equatable)
    }

    @Test("Mixed corpus exercises all three classification states simultaneously")
    func mixedCorpusExercisesAllThreeStates() throws {
        // One file with all three shapes side by side. Asserts the
        // resolver's resolution order: curated non-Equatable shape >
        // curated stdlib > corpus-derived > .unknown fallback.
        let directory = try writeFixture(named: "MixedThreeStates", files: [
            "Mixed.swift": """
            struct Equ: Equatable {}
            struct Plain {
                let n: Int
            }
            extension Logger: Equatable {}
            """
        ])
        defer { try? FileManager.default.removeItem(at: directory) }
        let corpus = try FunctionScanner.scanCorpus(directory: directory)
        let resolver = EquatableResolver(typeDecls: corpus.typeDecls)
        // Corpus-derived .equatable
        #expect(resolver.classify(typeText: "Equ") == .equatable)
        // Curated stdlib .equatable
        #expect(resolver.classify(typeText: "Int") == .equatable)
        // Extension-lifted .equatable for a type not declared in the corpus
        #expect(resolver.classify(typeText: "Logger") == .equatable)
        // Corpus type with no Equatable evidence
        #expect(resolver.classify(typeText: "Plain") == .unknown)
        // Curated non-Equatable shape — wins over .unknown
        #expect(resolver.classify(typeText: "(Int) -> Int") == .notEquatable)
        // Genuinely unknown — type name doesn't appear anywhere
        #expect(resolver.classify(typeText: "Mystery") == .unknown)
    }

    // MARK: - Helpers

    private func writeFixture(named name: String, files: [String: String]) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftInferEqResolverIT-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        for (filename, contents) in files {
            try contents.write(
                to: base.appendingPathComponent(filename),
                atomically: true,
                encoding: .utf8
            )
        }
        return base
    }
}
