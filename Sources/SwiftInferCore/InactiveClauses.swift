import Foundation
import SwiftIfConfig
import SwiftSyntax

/// The `#if` clauses of one file that the build does not compile, whatever the unknowns turn out to be.
///
/// `open-threads.md` row 74: `FunctionScanner` walked every branch `.sourceAccurate`, so a declaration in
/// an inactive branch was scanned as live — 138 whole-file rows in `inactive-if-config-census.md`, and
/// two false generator declines in `precondition-helper-hop.md`. `configuredRegions(in:)` answers a
/// condition the configuration cannot decide as `false`, which would DROP code on an unknown; so each file
/// is evaluated twice, once with every unknown answered `true` and once `false`, and a clause is skipped
/// only when it is inactive in BOTH. `#if canImport(X) … #else …` keeps both branches; `#if os(Linux)`
/// drops its body on this host. Plan: `docs/plans/inactive-if-config-scope.md`.
enum InactiveClauses {

    static func of(_ tree: SourceFileSyntax, conditions: ManifestConditions?) -> Set<SyntaxIdentifier> {
        // A file with no `#if` pays for nothing.
        guard tree.description.contains("#if") else { return [] }
        let optimistic = inactive(in: tree.configuredRegions(in: HostBuildConfiguration(conditions, unknown: true)))
        guard !optimistic.isEmpty else { return [] }
        let pessimistic = inactive(in: tree.configuredRegions(in: HostBuildConfiguration(conditions, unknown: false)))
        return optimistic.intersection(pessimistic)
    }

    private static func inactive(in regions: ConfiguredRegions) -> Set<SyntaxIdentifier> {
        Set(regions.filter { $0.state != .active }.map(\.ifClause.id))
    }

    /// The nearest `Package.swift` above an on-disk `file`, read once per manifest. `nil` when `file` is
    /// not on disk — an in-memory fixture's label must never pick up whatever package the process runs in.
    static func conditions(forFile file: String) -> ManifestConditions? {
        guard file.hasPrefix("/"), FileManager.default.fileExists(atPath: file) else { return nil }
        var directory = URL(fileURLWithPath: file).deletingLastPathComponent()
        while directory.path != "/" {
            let manifest = directory.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: manifest.path) {
                return ManifestCache.shared.conditions(at: manifest.path)
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }
}

private final class ManifestCache: @unchecked Sendable {
    static let shared = ManifestCache()
    private let lock = NSLock()
    private var byPath: [String: ManifestConditions?] = [:]

    func conditions(at path: String) -> ManifestConditions? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = byPath[path] { return cached }
        let read = (try? String(contentsOfFile: path, encoding: .utf8)).map(ManifestConditions.read(manifest:))
        byPath[path] = read
        return read
    }
}

/// A macOS arm64 debug build: what the tool verifies on. Custom conditions come from the manifest; the
/// questions nothing here can decide (`canImport`, `hasFeature`, `hasAttribute`, a custom condition with no
/// manifest) are answered `unknown`, and the caller evaluates both answers.
struct HostBuildConfiguration: BuildConfiguration {
    let conditions: ManifestConditions?
    let unknown: Bool

    init(_ conditions: ManifestConditions?, unknown: Bool) {
        self.conditions = conditions
        self.unknown = unknown
    }

    func isCustomConditionSet(name: String) -> Bool {
        if name == "DEBUG" { return true }
        return conditions?.isSet(name) ?? unknown
    }

    func hasFeature(name _: String) -> Bool { unknown }
    func hasAttribute(name _: String) -> Bool { unknown }
    func canImport(importPath _: [(TokenSyntax, String)], version _: CanImportVersion) -> Bool { unknown }
    func isActiveTargetOS(name: String) -> Bool { name == "macOS" }
    func isActiveTargetArchitecture(name: String) -> Bool { name == "arm64" }
    func isActiveTargetEnvironment(name _: String) -> Bool { false }
    func isActiveTargetRuntime(name: String) -> Bool { name == "_ObjC" || name == "_multithreaded" }
    func isActiveTargetPointerAuthentication(name _: String) -> Bool { false }

    var targetPointerBitWidth: Int { 64 }
    var targetAtomicBitWidths: [Int] { [8, 16, 32, 64, 128] }
    var endianness: Endianness { .little }
    var languageVersion: VersionTuple { VersionTuple(6, 3) }
    var compilerVersion: VersionTuple { VersionTuple(6, 3) }
}
