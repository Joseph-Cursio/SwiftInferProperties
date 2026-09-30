import Foundation
@testable import SwiftInferCore
import Testing

/// Row 74: a declaration in an `#if` branch the build does not compile is not scanned — and one whose
/// condition cannot be decided is. `docs/plans/inactive-if-config-scope.md`.
@Suite("Inactive #if clauses are not scanned")
struct InactiveClausesTests {

    // MARK: - The manifest reader

    @Test("a top-level define is set; a commented-out one and an unnamed one are not")
    func topLevelDefines() {
        let conditions = ManifestConditions.read(manifest: """
            let settings: [SwiftSetting] = [
                .define("SQLITE_ENABLE_FTS5"),
            //  .define("COLLECTIONS_INTERNAL_CHECKS"),
                .unsafeFlags(["-DFROM_FLAG"]),
            ]
            """)
        #expect(conditions.isSet("SQLITE_ENABLE_FTS5") == true)
        #expect(conditions.isSet("FROM_FLAG") == true)
        #expect(conditions.isSet("COLLECTIONS_INTERNAL_CHECKS") == false)
        #expect(conditions.isSet("FOUNDATION_FRAMEWORK") == false)
    }

    @Test("platform, configuration and branch gates on a define")
    func gatedDefines() {
        let conditions = ManifestConditions.read(manifest: """
            let a: [SwiftSetting] = [
                .define("DATA_LEGACY_ABI", .when(platforms: [.macOS, .iOS])),
                .define("_GNU_SOURCE", .when(platforms: [.linux, .wasi])),
                .define("RELEASE_ONLY", .when(configuration: .release)),
            ]
            if ProcessInfo.processInfo.environment["X"] != nil {
                swiftSettings.append(.define("SQLITE_ENABLE_PREUPDATE_HOOK"))
            }
            """)
        #expect(conditions.isSet("DATA_LEGACY_ABI") == true)
        #expect(conditions.isSet("_GNU_SOURCE") == false)
        #expect(conditions.isSet("RELEASE_ONLY") == false)
        #expect(conditions.isSet("SQLITE_ENABLE_PREUPDATE_HOOK") == nil)
    }

    @Test("default traits are set, closed over their own enabledTraits; other traits are not")
    func traits() {
        let conditions = ManifestConditions.read(manifest: """
            let traits: Set<Trait> = [
                .default(enabledTraits: [
                    "Base",
            //      "UnstableSortedCollections",
                ]),
                .trait(name: "Base", enabledTraits: ["Implied"]),
                .trait(name: "Implied"),
                .trait(name: "UnstableSortedCollections"),
            ]
            """)
        #expect(conditions.isSet("Base") == true)
        #expect(conditions.isSet("Implied") == true)
        #expect(conditions.isSet("UnstableSortedCollections") == false)
    }

    // MARK: - Scanning

    private static let source = """
        #if UnstableSortedCollections
        public func sortedOnly(_ value: Int) -> Int { value }
        #endif
        #if os(Linux)
        public func linuxOnly(_ value: Int) -> Int { value }
        #else
        public func hostOnly(_ value: Int) -> Int { value }
        #endif
        #if canImport(Glibc)
        public func maybeGlibc(_ value: Int) -> Int { value }
        #else
        public func maybeNotGlibc(_ value: Int) -> Int { value }
        #endif
        public struct Heap {
            #if COLLECTIONS_INTERNAL_CHECKS
            func checkInvariants() { precondition(false) }
            #else
            func checkInvariants() {}
            #endif
        }
        """

    private func scannedNames(file: String) -> Set<String> {
        let corpus = FunctionScanner.scanCorpus(source: Self.source, file: file)
        return Set(corpus.summaries.map(\.name))
    }

    @Test("an in-memory fixture: host conditions decide, custom conditions stay unknown")
    func withoutManifest() {
        let names = scannedNames(file: "Fixture.swift")
        #expect(!names.contains("linuxOnly"))
        #expect(names.isSuperset(of: ["hostOnly", "maybeGlibc", "maybeNotGlibc", "sortedOnly"]))
    }

    @Test("on disk under a manifest: undefined custom conditions drop their branch, and so does the trap")
    func withManifest() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InactiveClausesTests-\(UUID().uuidString)")
        let sources = root.appendingPathComponent("Sources/Target")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try """
            // swift-tools-version:6.1
            import PackageDescription
            let package = Package(name: "P", traits: [.default(enabledTraits: [])], targets: [.target(name: "Target")])
            """.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let file = sources.appendingPathComponent("File.swift")
        try Self.source.write(to: file, atomically: true, encoding: .utf8)

        let corpus = try FunctionScanner.scanCorpus(file: file)
        let names = Set(corpus.summaries.map(\.name))
        #expect(!names.contains("sortedOnly"))
        #expect(names.isSuperset(of: ["hostOnly", "maybeGlibc", "maybeNotGlibc"]))
        #expect(!corpus.trappingFunctions.contains("Heap.checkInvariants"))
    }
}
