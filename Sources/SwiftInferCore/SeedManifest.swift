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
    ///
    /// **v2 added `kind`** — see `SeedKind`. The field is what distinguishes a seed naming a
    /// function to *analyse* from one naming a place where a human must *refactor first*.
    public static let supportedVersion = 2

    public let version: Int
    public let seeds: [Seed]

    public init(version: Int = Self.supportedVersion, seeds: [Seed]) {
        self.version = version
        self.seeds = seeds
    }

    /// Seeds this tool may narrow discovery to.
    public var analysableSeeds: [Seed] {
        seeds.filter(\.kind.isAnalysable)
    }

    /// Seeds naming work a human must do before any tool can help — pure logic that exists but has
    /// no name yet.
    public var refactorPendingSeeds: [Seed] {
        seeds.filter { !$0.kind.isAnalysable }
    }

    /// One seeded location: enough to find it, and — via `kind` — enough to know what may be done
    /// with it.
    public struct Seed: Codable, Sendable, Equatable {
        public let file: String
        public let line: Int
        public let symbol: String
        public let rule: String?
        public let kind: SeedKind

        public init(
            file: String,
            line: Int,
            symbol: String,
            rule: String? = nil,
            kind: SeedKind = .pureFunction
        ) {
            self.file = file
            self.line = line
            self.symbol = symbol
            self.rule = rule
            self.kind = kind
        }

        /// A v1 manifest has no `kind`. Every seed in one was a function to analyse, so that is what
        /// a missing `kind` means.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.file = try container.decode(String.self, forKey: .file)
            self.line = try container.decode(Int.self, forKey: .line)
            self.symbol = try container.decode(String.self, forKey: .symbol)
            self.rule = try container.decodeIfPresent(String.self, forKey: .rule)
            self.kind = try container.decodeIfPresent(SeedKind.self, forKey: .kind) ?? .pureFunction
        }
    }
}

/// What a seed *is*, which decides what may be done with it.
///
/// A seed is not always a symbol to analyse. Some name a place where pure logic **exists but has no
/// name yet** — an extractable kernel inlined in an impure method. There is nothing to index there:
/// nothing to call, nothing to generate inputs for, no signature to satisfy. The symbol names the
/// *enclosing* function, which is a **location**, not a subject.
///
/// **Narrowing discovery to such a seed produces a confident zero.** Focus on
/// `uploadRemainingChunks` and this tool must refuse it — `private async throws` refutes purity —
/// and then report `kept 0` for a codebase that demonstrably has property-testable logic in it. That
/// is the exact failure the empty-manifest guard exists to prevent, arriving by a new route: a tool
/// telling the reader "there is nothing here" when there is. So a non-analysable seed is *reported*
/// to the reader as work to do, and never focused on.
public enum SeedKind: Sendable, Equatable {
    /// A pure, total function. Index it, propose laws, run them.
    case pureFunction

    /// A function claiming idempotence that calls non-idempotent work — it arrives with a
    /// ready-made property.
    case idempotency

    /// Pure logic trapped inside an impure method. Real, valuable, **not yet callable**.
    case extractableKernel

    /// A kind emitted by a newer producer than this build knows.
    ///
    /// **Treated as not-analysable, deliberately.** The two ways to be wrong here are not
    /// symmetric. Guess "analysable" and a future refactor-pending kind (a pure closure, say) gets
    /// focused on, refused, and reported as a zero — silently. Guess "not analysable" and the seed
    /// is merely skipped, *and said out loud*. Never silently narrow to a symbol you do not
    /// understand.
    case unrecognised(String)

    public var isAnalysable: Bool {
        switch self {
        case .pureFunction, .idempotency:
            return true

        case .extractableKernel, .unrecognised:
            return false
        }
    }

    public var rawValue: String {
        switch self {
        case .pureFunction:
            return "pure-function"

        case .idempotency:
            return "idempotency"

        case .extractableKernel:
            return "extractable-kernel"

        case .unrecognised(let raw):
            return raw
        }
    }
}

extension SeedKind: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "pure-function":
            self = .pureFunction

        case "idempotency":
            self = .idempotency

        case "extractable-kernel":
            self = .extractableKernel

        default:
            self = .unrecognised(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
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
    /// **Only *analysable* seeds focus.** A kernel seed's symbol names the impure method the kernel
    /// is trapped inside, so joining on it would narrow the run to a function this tool must then
    /// refuse — a confident zero by a new route. Those seeds are reported to the reader instead; see
    /// `SeedKind`.
    public static func filter(_ suggestions: [Suggestion], to manifest: SeedManifest) -> [Suggestion] {
        let focusing = manifest.analysableSeeds
        guard !focusing.isEmpty else { return suggestions }

        let keys = Set(focusing.map { key(file: $0.file, symbol: $0.symbol) })
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
