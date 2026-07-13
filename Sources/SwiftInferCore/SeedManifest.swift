import Foundation

/// A property-test *seed manifest* produced by an external linter and consumed
/// by `swift-infer discover --seeds`.
///
/// SwiftProjectLint's `--format pbt-seeds` emits this document: each seed names
/// a function the linter judged a good property-based-test candidate (pure,
/// total, takes inputs, returns a value). `discover --seeds` uses it to *focus*
/// inference output on exactly those functions — the keystone of the
/// lint → infer → verify pipeline.
///
/// The schema mirrors the producer's:
/// ```json
/// { "version": 1, "seeds": [ { "file": "Math.swift", "line": 3,
///                              "symbol": "add", "rule": "Pure Function …" } ] }
/// ```
/// `rule` is decoded leniently (optional) so a producer that drops or renames
/// it doesn't break consumption; `file`/`line`/`symbol` are the load-bearing
/// fields.
public struct SeedManifest: Codable, Sendable, Equatable {

    /// The schema version this build understands. A manifest with a different
    /// version is still consumed best-effort, but the CLI warns.
    public static let supportedVersion = 1

    public let version: Int
    public let seeds: [Seed]

    public init(version: Int = Self.supportedVersion, seeds: [Seed]) {
        self.version = version
        self.seeds = seeds
    }

    /// One seeded function: enough to locate it and match it against
    /// discovered evidence.
    public struct Seed: Codable, Sendable, Equatable {
        public let file: String
        public let line: Int
        public let symbol: String
        public let rule: String?

        public init(file: String, line: Int, symbol: String, rule: String? = nil) {
            self.file = file
            self.line = line
            self.symbol = symbol
            self.rule = rule
        }
    }
}

/// Filters discovered suggestions down to those that touch a seeded function.
public enum SeedFocus {

    /// Keep only suggestions whose evidence references a seeded function.
    ///
    /// The join key is `(file basename, function base name)`. The linter and
    /// `swift-infer` scan the same files but may spell paths differently
    /// (a linter often reports a relative path or bare filename, while the
    /// scanner records an absolute path), so the **basename** is the reliable
    /// common denominator. The **function base name** strips parameter labels
    /// from the evidence display name — `add(_:_:)` → `add` — to match the
    /// bare symbol the linter emits.
    ///
    /// A pair suggestion (e.g. round-trip) is kept when *either* half is
    /// seeded: a property over a seeded function is relevant even if its
    /// partner wasn't independently flagged.
    ///
    /// **An empty manifest does not focus.** It used to: "focus on these zero functions" was read
    /// as "keep zero suggestions". That is defensible in isolation and ruinous in a pipeline,
    /// because the manifest is not authored by hand — it is whatever the linter happened to find.
    /// A linter with a blind spot emits an empty manifest, the filter throws away every genuine
    /// suggestion, and the reader is told "0 suggestions" by a tool that found several. Running
    /// the documented `lint → infer` pipeline was then *strictly worse* than running `swift-infer`
    /// alone. Focusing on nothing is not a request anyone makes; it is what a producer that found
    /// nothing looks like, and the honest response is to say so and not filter.
    public static func filter(_ suggestions: [Suggestion], to manifest: SeedManifest) -> [Suggestion] {
        guard !manifest.seeds.isEmpty else { return suggestions }

        let keys = Set(manifest.seeds.map { key(file: $0.file, symbol: $0.symbol) })
        return suggestions.filter { suggestion in
            suggestion.evidence.contains { evidence in
                keys.contains(key(file: evidence.location.file, symbol: functionBaseName(evidence.displayName)))
            }
        }
    }

    /// The bare function name from an evidence display name: everything before
    /// the first `(`. `add(_:_:)` → `add`; a name with no parens is returned
    /// unchanged.
    static func functionBaseName(_ displayName: String) -> String {
        guard let paren = displayName.firstIndex(of: "(") else { return displayName }
        return String(displayName[..<paren])
    }

    private static func key(file: String, symbol: String) -> String {
        let base = URL(fileURLWithPath: file).lastPathComponent
        return "\(base)::\(symbol)"
    }
}
