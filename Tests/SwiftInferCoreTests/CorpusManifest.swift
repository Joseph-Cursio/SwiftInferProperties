import Foundation

@testable import SwiftInferCore

/// **The measurement corpora, read from `fixtures/corpora/manifest.json`.**
///
/// ## Why this exists
///
/// Every census on 2026-08-19 used `PartialPurityConsumerMeasuredTests.corpora` — **three**
/// corpora — while the manifest listed **22** and eighteen resolved on the machine the
/// measurements ran on. Two declines were argued from that trio, one of them explicitly on
/// the grounds that a shape was *"self-only"*, and neither had looked at swift-format,
/// GRDB, NIO, the Swift stdlib or SwiftProjectLint.
///
/// Item 34's trio is **right for one thing**: reusing it keeps an `isThrows` control
/// comparable to the `+2` that census measured. It is **wrong as the universe for a
/// generality question**, and the difference was never stated, so it was carried forward
/// nine times.
///
/// ## The `~` trap, which is why the expansion lives here
///
/// The manifest stores paths as written — `~/GitHub_projects/swift-format`. A check that
/// compares that string to the filesystem without expanding `~` reports **every** such
/// corpus absent, which is how a first pass concluded that thirteen third-party subjects
/// were missing when twenty of twenty-two were present. Expansion happens once, here.
///
/// ## A resolved root with no files is DROPPED, loudly
///
/// Two manifest entries resolve to a directory containing no `.swift` file. A corpus that
/// scans nothing contributes a zero indistinguishable from a corpus with no findings —
/// this repo's confident zero, in the loader that decides what a census can see. Such
/// entries are excluded from ``available`` and listed in ``emptyRoots`` so a census can
/// say what it did not look at.
enum CorpusManifest {

    struct Corpus {
        let id: String
        let kind: String
        /// The directories to scan. Several manifest entries name more than one.
        let roots: [URL]
        let swiftFileCount: Int

        /// The single root a census scans. Multi-root corpora use the largest, and say so
        /// rather than silently merging populations from different modules.
        var primaryRoot: URL { roots[0] }
    }

    static let packageRoot = PurityRefutationCensusMeasuredTests.packageRoot

    /// Corpora that resolved to at least one directory holding at least one `.swift` file.
    static let available: [Corpus] = load().available

    /// Manifest ids whose `localPath` is not on this machine — a third state, neither
    /// present nor empty. `fixtures/corpora/manifest.json` pins a `remote` and a revision
    /// for each, so these are re-creatable rather than lost.
    static let absent: [String] = load().absent

    /// Ids that resolved to a real directory containing no Swift file. Reported because
    /// including one would add a silent zero.
    static let emptyRoots: [String] = load().empty

    // MARK: - Loading

    private struct Loaded {
        let available: [Corpus]
        let absent: [String]
        let empty: [String]
    }

    private static func load() -> Loaded {
        let url = packageRoot.appendingPathComponent("fixtures/corpora/manifest.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["corpora"] as? [[String: Any]] else {
            return Loaded(available: [], absent: [], empty: [])
        }

        var available: [Corpus] = []
        var absent: [String] = []
        var empty: [String] = []
        for entry in entries {
            guard let id = entry["id"] as? String else { continue }
            let roots = resolveRoots(entry)
            guard !roots.isEmpty else { absent.append(id); continue }
            let counted = roots
                .map { ($0, swiftFiles(under: $0)) }
                .filter { $0.1 > 0 }
                .sorted { $0.1 > $1.1 }
            guard let biggest = counted.first else { empty.append(id); continue }
            available.append(
                Corpus(
                    id: id,
                    kind: entry["kind"] as? String ?? "?",
                    roots: counted.map(\.0),
                    swiftFileCount: biggest.1
                )
            )
        }
        return Loaded(
            available: available.sorted { $0.id < $1.id },
            absent: absent.sorted(),
            empty: empty.sorted()
        )
    }

    /// `sources` when the manifest names it, else `Sources/<target>`. Both spellings occur
    /// and neither is a default — `swiftlang-swift` has no target and lives under
    /// `stdlib/public/core`, while `swift-format` names a target and no sources.
    private static func resolveRoots(_ entry: [String: Any]) -> [URL] {
        let raw = (entry["localPath"] as? String) ?? ""
        guard !raw.isEmpty else { return [] }
        // `~` is expanded HERE and nowhere else. A comparison against the raw manifest
        // string reports every tilde path absent, which is how a first pass concluded
        // thirteen third-party corpora were missing when twenty of twenty-two were present.
        let base = raw.hasPrefix("~")
            ? URL(fileURLWithPath: NSHomeDirectory() + String(raw.dropFirst()))
            : packageRoot.appendingPathComponent(raw)

        let candidates: [URL]
        if let sources = entry["sources"] as? [String], !sources.isEmpty {
            candidates = sources.map { base.appendingPathComponent($0) }
        } else if let target = entry["target"] as? String {
            candidates = [base.appendingPathComponent("Sources/\(target)")]
        } else {
            candidates = []
        }
        return candidates.filter {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory)
            return exists && isDirectory.boolValue
        }
    }

    private static func swiftFiles(under root: URL) -> Int {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return 0 }
        var count = 0
        for case let url as URL in walker
        where url.pathExtension == "swift" && !url.path.contains("/.build/") {
            count += 1
        }
        return count
    }
}
