import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

/// V1.42.C.1 — VerifyHarness lookup tests.
///
/// Covers hash-prefix matching against an in-memory `IndexStore.Index`
/// (the lookup core) and on-disk `resolveIndex(...)` against synthesized
/// temp directories (the staleness probe + missing-file behavior).
@Suite("VerifyHarness — V1.42.C.1 lookup")
struct VerifyHarnessTests {

    // MARK: - Fixtures

    private static func entry(_ hash: String, template: String = "round-trip") -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: hash,
            templateName: template,
            typeName: "Complex<Double>",
            score: 50,
            tier: "Strong",
            primaryFunctionName: "exp(_:)",
            location: "/Module.swift:1",
            firstSeenAt: "2026-05-11T00:00:00Z",
            lastSeenAt: "2026-05-11T00:00:00Z"
        )
    }

    private static func index(with entries: [SemanticIndexEntry]) -> IndexStore.Index {
        IndexStore.Index(updatedAt: "2026-05-11T00:00:00Z", entries: entries)
    }

    // MARK: - lookupSuggestion(...)

    @Test("exact full-hash match returns the entry")
    func exactMatchReturnsEntry() throws {
        let target = Self.entry("0xBC43359C0574816B")
        let other = Self.entry("0xAA11223344556677")
        let result = try VerifyHarness.lookupSuggestion(
            hashPrefix: "0xBC43359C0574816B",
            in: Self.index(with: [target, other])
        )
        #expect(result.entry == target)
    }

    @Test("unique prefix match returns the single matching entry")
    func uniquePrefixMatchReturnsEntry() throws {
        let target = Self.entry("0xBC43359C0574816B")
        let other = Self.entry("0xAA11223344556677")
        let result = try VerifyHarness.lookupSuggestion(
            hashPrefix: "0xBC43",
            in: Self.index(with: [target, other])
        )
        #expect(result.entry == target)
    }

    @Test("prefix match without 0x prefix still resolves")
    func bareHexPrefixMatches() throws {
        let target = Self.entry("0xBC43359C0574816B")
        let result = try VerifyHarness.lookupSuggestion(
            hashPrefix: "BC43",
            in: Self.index(with: [target])
        )
        #expect(result.entry == target)
    }

    @Test("prefix match is case-insensitive")
    func prefixMatchIsCaseInsensitive() throws {
        let target = Self.entry("0xBC43359C0574816B")
        let result = try VerifyHarness.lookupSuggestion(
            hashPrefix: "0xbc43",
            in: Self.index(with: [target])
        )
        #expect(result.entry == target)
    }

    @Test("ambiguous prefix raises .ambiguousPrefix naming the matches")
    func ambiguousPrefixThrows() throws {
        let first = Self.entry("0xBC43359C0574816B")
        let second = Self.entry("0xBC43DEADBEEFCAFE")
        let other = Self.entry("0xAA11223344556677")
        #expect(throws: VerifyError.self) {
            _ = try VerifyHarness.lookupSuggestion(
                hashPrefix: "0xBC43",
                in: Self.index(with: [first, second, other])
            )
        }
        // Inspect the thrown value's case + payload.
        do {
            _ = try VerifyHarness.lookupSuggestion(
                hashPrefix: "0xBC43",
                in: Self.index(with: [first, second, other])
            )
            Issue.record("expected .ambiguousPrefix to be thrown")
        } catch let error as VerifyError {
            switch error {
            case let .ambiguousPrefix(prefix, matches):
                #expect(prefix == "0xBC43")
                #expect(matches.contains(first.identityHash))
                #expect(matches.contains(second.identityHash))

            default:
                Issue.record("expected .ambiguousPrefix; got \(error)")
            }
        }
    }

    @Test("no match raises .suggestionNotFound with closest entries")
    func noMatchThrowsSuggestionNotFound() throws {
        let entries = [
            Self.entry("0xBC43359C0574816B"),
            Self.entry("0xBC43DEADBEEFCAFE"),
            Self.entry("0xAA11223344556677")
        ]
        do {
            _ = try VerifyHarness.lookupSuggestion(
                hashPrefix: "0xFFFF",
                in: Self.index(with: entries)
            )
            Issue.record("expected .suggestionNotFound")
        } catch let error as VerifyError {
            switch error {
            case let .suggestionNotFound(prefix, closest):
                #expect(prefix == "0xFFFF")
                #expect(!closest.isEmpty)
                #expect(closest.count <= 3)

            default:
                Issue.record("expected .suggestionNotFound; got \(error)")
            }
        }
    }

    @Test("empty index raises .indexEmpty")
    func emptyIndexThrows() throws {
        do {
            _ = try VerifyHarness.lookupSuggestion(
                hashPrefix: "0xBC43",
                in: Self.index(with: [])
            )
            Issue.record("expected .indexEmpty")
        } catch let error as VerifyError {
            switch error {
            case .indexEmpty:
                break

            default:
                Issue.record("expected .indexEmpty; got \(error)")
            }
        }
    }

    @Test("staleWarnings are surfaced on a successful lookup")
    func staleWarningsSurface() throws {
        let target = Self.entry("0xBC43359C0574816B")
        let result = try VerifyHarness.lookupSuggestion(
            hashPrefix: "0xBC43",
            in: Self.index(with: [target]),
            staleWarnings: ["stale-index warning"]
        )
        #expect(result.warnings == ["stale-index warning"])
    }

    // MARK: - resolveIndex(...)

    @Test("missing index file raises .indexMissing")
    func missingIndexFileThrows() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            _ = try VerifyHarness.resolveIndex(
                packageRoot: temp,
                explicitIndexPath: nil,
                now: "2026-05-11T00:00:00Z"
            )
            Issue.record("expected .indexMissing")
        } catch let error as VerifyError {
            switch error {
            case let .indexMissing(path):
                #expect(path.path.hasSuffix(".swiftinfer/index.json"))

            default:
                Issue.record("expected .indexMissing; got \(error)")
            }
        }
    }

    @Test("on-disk lookup returns an entry from a fresh index")
    func onDiskLookupReturnsEntry() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let target = Self.entry("0xBC43359C0574816B")
        let indexValue = Self.index(with: [target])
        let path = IndexStore.defaultPath(for: temp)
        try IndexStore.save(indexValue, to: path)
        let resolved = try VerifyHarness.resolveIndex(
            packageRoot: temp,
            explicitIndexPath: nil,
            now: "2026-05-11T00:00:00Z"
        )
        #expect(resolved.index.entries.count == 1)
        #expect(resolved.path == path)
    }

    @Test("explicit index path overrides the conventional location")
    func explicitIndexPathHonored() throws {
        let temp = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let customPath = temp.appendingPathComponent("custom-index.json")
        let target = Self.entry("0xBC43359C0574816B")
        try IndexStore.save(Self.index(with: [target]), to: customPath)
        let resolved = try VerifyHarness.resolveIndex(
            packageRoot: temp,
            explicitIndexPath: customPath,
            now: "2026-05-11T00:00:00Z"
        )
        #expect(resolved.path == customPath)
        #expect(resolved.warnings.isEmpty)
    }

    // MARK: - Helpers

    private func makeTempDirectory() throws -> URL {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("verify-harness-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }
}
