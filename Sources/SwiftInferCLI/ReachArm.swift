import Foundation

/// Which #684 arm this process writes stubs for — a **measurement switch, removed once the decision
/// is taken** (`docs/plans/predicate-reach-at-source-scope.md` §3, §6).
///
/// One binary serves every arm, so the A/B differs in nothing but this value. Unset, or `baseline`,
/// is today's behaviour byte for byte (§5 V1).
///
/// Spellings: `baseline`, `uncapped`, `seeded`, each optionally followed by `+paired`.
struct ReachArm: Equatable, Sendable {

    /// Lever 1: which syntax-corpus snippets a stub draws from.
    enum Corpus: String, Sendable {
        /// The first 300 harvested snippets, drawn uniformly.
        case baseline
        /// Every harvested snippet, drawn with the seed bias.
        case uncapped
        /// The first 300, plus up to 8 seed-matching snippets per stub from past the cap, drawn with
        /// the seed bias.
        case seeded
    }

    let corpus: Corpus
    /// Lever 2: relational pairing of drawn arguments.
    let paired: Bool

    static let baseline = Self(corpus: .baseline, paired: false)
    static let environmentKey = "SWIFT_INFER_REACH_ARM"

    /// The arm the environment names. An unknown spelling stops the process: a mislabelled arm would
    /// measure one thing and record another.
    static let current: Self = {
        let raw = ProcessInfo.processInfo.environment[environmentKey]
        guard let arm = parse(raw) else {
            FileHandle.standardError.write(Data("error: \(environmentKey)=\(raw ?? "") is not an arm\n".utf8))
            exit(64)
        }
        return arm
    }()

    /// `nil` for a spelling that names no arm; `baseline` for `nil` or an empty value.
    static func parse(_ raw: String?) -> Self? {
        let value = (raw ?? "").trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return .baseline }
        let parts = value.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard (1 ... 2).contains(parts.count), let lever = Corpus(rawValue: parts[0]) else { return nil }
        if parts.count == 2, parts[1] != "paired" { return nil }
        return Self(corpus: lever, paired: parts.count == 2)
    }

    /// Whether the emitted corpus needs the reach machinery (`gen(_:preferring:kinds:)`,
    /// `name(near:using:)`). Only the pure baseline omits it, so its file stays byte-identical.
    var needsReachMachinery: Bool { self != .baseline }
}
