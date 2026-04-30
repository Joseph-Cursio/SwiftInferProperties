import Foundation
import Testing
@testable import SwiftInferCore

@Suite("FunctionScanner.scanCorpus — identity candidate detection")
struct IdentityCandidateScannerTests {

    // MARK: Curated names + explicit type

    @Test
    func capturesStaticEmptyConstantOnStruct() throws {
        let source = """
        struct IntSet {
            static let empty: IntSet = IntSet()
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let identity = try #require(corpus.identities.first)
        #expect(identity.name == "empty")
        #expect(identity.typeText == "IntSet")
        #expect(identity.containingTypeName == "IntSet")
    }

    @Test
    func detectsAllCuratedIdentityNames() throws {
        // PRD v0.3 §5.2 priority-1 list: zero, empty, identity, none, default.
        let source = """
        enum Group {
            static let zero: Group = .init()
            static let empty: Group = .init()
            static let identity: Group = .init()
            static let none: Group = .init()
            static let `default`: Group = .init()
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let names = corpus.identities.map(\.name).sorted()
        #expect(names == ["default", "empty", "identity", "none", "zero"])
    }

    @Test
    func ignoresInstanceLevelDeclarations() {
        // No `static` modifier — not an identity-element candidate.
        let source = """
        struct IntSet {
            let empty: IntSet = IntSet()
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        #expect(corpus.identities.isEmpty)
    }

    @Test
    func ignoresUntypedStaticDeclarations() {
        // Type is inferred from the initializer — M2.5 conservative scope
        // requires an explicit annotation so the pairer can match by text.
        let source = """
        struct IntSet {
            static let empty = IntSet()
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        #expect(corpus.identities.isEmpty)
    }

    @Test
    func ignoresStaticConstantsWithUncuratedNames() {
        let source = """
        struct Sentinel {
            static let placeholder: Sentinel = Sentinel()
            static let unknown: Sentinel = Sentinel()
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        #expect(corpus.identities.isEmpty)
    }

    @Test
    func capturesTopLevelStaticOnExtensionAndPreservesType() throws {
        let source = """
        extension Logger {
            static let none: Logger = Logger.silent
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let identity = try #require(corpus.identities.first)
        #expect(identity.name == "none")
        #expect(identity.typeText == "Logger")
        #expect(identity.containingTypeName == "Logger")
    }

    @Test
    func staticVarWithCuratedNameAndExplicitTypeAlsoCounts() throws {
        // `static var` is rare for identities but syntactically valid.
        let source = """
        enum Frame {
            static var empty: Frame = Frame()
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let identity = try #require(corpus.identities.first)
        #expect(identity.name == "empty")
        #expect(identity.containingTypeName == "Frame")
    }

    @Test
    func multipleBindingsInOneDeclEachCounted() throws {
        // `static let zero, empty: IntSet = .init()` — both names emit.
        let source = """
        struct IntSet {
            static let zero, empty: IntSet = IntSet()
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let names = corpus.identities.map(\.name).sorted()
        #expect(names == ["empty", "zero"])
    }

    // MARK: Body-scoped vars are NOT identity candidates

    @Test
    func varInsideFunctionBodyIsNotEmittedAsIdentity() {
        let source = """
        func work() -> Int {
            let empty = 0
            return empty
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        #expect(corpus.identities.isEmpty)
    }

    // MARK: Reducer-op seed classification (PRD §5.3 empty-seed signal)

    @Test
    func zeroSeedClassifiedAsIdentity() throws {
        let source = """
        func driver(_ xs: [Int]) -> Int {
            return xs.reduce(0, add)
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.bodySignals.reducerOpsWithIdentitySeed == ["add"])
    }

    @Test
    func emptyStringSeedClassifiedAsIdentity() throws {
        let source = """
        func driver(_ xs: [String]) -> String {
            return xs.reduce("", concat)
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.bodySignals.reducerOpsWithIdentitySeed == ["concat"])
    }

    @Test
    func emptyArraySeedClassifiedAsIdentity() throws {
        let source = """
        func driver(_ xss: [[Int]]) -> [Int] {
            return xss.reduce([], merge)
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.bodySignals.reducerOpsWithIdentitySeed == ["merge"])
    }

    @Test
    func emptyDictionarySeedClassifiedAsIdentity() throws {
        let source = """
        func driver(_ xs: [[String: Int]]) -> [String: Int] {
            return xs.reduce([:], merge)
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.bodySignals.reducerOpsWithIdentitySeed == ["merge"])
    }

    @Test
    func nilSeedClassifiedAsIdentity() throws {
        let source = """
        func driver(_ xs: [Int?]) -> Int? {
            return xs.reduce(nil, takeFirst)
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.bodySignals.reducerOpsWithIdentitySeed == ["takeFirst"])
    }

    @Test
    func memberAccessEmptySeedClassifiedAsIdentity() throws {
        let source = """
        func driver(_ xs: [IntSet]) -> IntSet {
            return xs.reduce(.empty, merge)
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.bodySignals.reducerOpsWithIdentitySeed == ["merge"])
    }

    @Test
    func nonZeroLiteralSeedNotClassifiedAsIdentity() throws {
        let source = """
        func driver(_ xs: [Int]) -> Int {
            return xs.reduce(1, add)
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        // Reducer-op still recorded, but NOT marked identity-seeded.
        #expect(summary.bodySignals.reducerOpsReferenced == ["add"])
        #expect(summary.bodySignals.reducerOpsWithIdentitySeed.isEmpty)
    }

    @Test
    func uncuratedMemberAccessSeedNotClassifiedAsIdentity() throws {
        let source = """
        func driver(_ xs: [IntSet]) -> IntSet {
            return xs.reduce(.singleton, merge)
        }
        """
        let summary = try #require(
            FunctionScanner.scan(source: source, file: "Test.swift").first
        )
        #expect(summary.bodySignals.reducerOpsReferenced == ["merge"])
        #expect(summary.bodySignals.reducerOpsWithIdentitySeed.isEmpty)
    }

    // MARK: scanCorpus — directory pass

    @Test
    func directoryScanCorpusEmitsBothSummariesAndIdentities() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanCorpusTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        try """
        struct IntSet {
            static let empty: IntSet = IntSet()
            func merge(_ a: IntSet, _ b: IntSet) -> IntSet { return a }
        }
        """.write(
            to: temp.appendingPathComponent("IntSet.swift"),
            atomically: true,
            encoding: .utf8
        )

        let corpus = try FunctionScanner.scanCorpus(directory: temp)
        #expect(corpus.summaries.map(\.name) == ["merge"])
        #expect(corpus.identities.map(\.name) == ["empty"])
    }
}
