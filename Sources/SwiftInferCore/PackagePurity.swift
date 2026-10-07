import Foundation
import SwiftEffectInference
import SwiftParser
import SwiftSyntax

/// One project's purity oracle, built once and handed to everything that judges purity in it.
///
/// SEI's `PurityInferrer` judges one declaration at a time; `ConstructionFacts` is what a
/// declaration cannot see from where it stands — what constructing each of the project's types
/// runs. SEI's doc is explicit that one table goes to **every** inferrer in a run, because one left
/// at `.empty` silently disagrees with the configured ones. This value is how that holds here: the
/// scanner's directory path builds one (`FunctionScanner.scanCorpus(directory:)`), and every file
/// the scan judges is judged by its `oracle`.
///
/// ## It owns the trees, and that is not an optimisation
///
/// The scan must judge the very trees the facts were built from. SEI types an assignment's target
/// by **node identity** (`ConstructionChecker.assignmentTargets`), so a re-parse of the same text
/// answers more refutingly than the original — `scanJudgesOnTheFactsOwnNodes` pins it. So a file in
/// the universe is parsed exactly once, here, and `FunctionScanner` looks its tree up rather than
/// reading the file again. The trees live as long as this value does; `ScannedCorpus` does not keep
/// one, so a scan's trees die when the scan returns.
///
/// ## Which universe
///
/// `ConstructionUniverse` — the cross-repo rule shared with SwiftProjectLint. Parsed in parallel,
/// each tree written to its own slot, so the build sees the universe's fixed order whatever order
/// the parses finish in.
public struct PackagePurity: Sendable {

    /// The root the universe was taken from; `nil` for a self-contained or unconfigured value,
    /// which covers no directory.
    public let root: URL?
    /// Root-relative paths that fed `ConstructionFacts.build(from:)`, in the order they fed it.
    public let universe: [String]
    /// Every member of the universe, readable or not — what `covers(_:)` compares, since two
    /// scans under one root can take different nested packages (amendment J).
    let members: [String]
    /// The directory this value was built for, and what `covers(_:)` has answered since.
    let coverage: Coverage
    /// The meet of `ReducerPurityAnalyzer` and a facts-configured `PurityInferrer`.
    public let oracle: SoundPurity
    /// Every parsed universe tree, by resolved absolute path.
    let trees: [String: SourceFileSyntax]

    /// The table `oracle` consults.
    public var constructionFacts: ConstructionFacts { oracle.constructionFacts }

    /// The project a scan of `directory` belongs to, parsed and its table built — **when the scan
    /// will judge something**, and `nil` when `directory` holds no `.swift` file.
    ///
    /// The entry point every production caller uses. A purity answers questions about judged
    /// files, and an empty judged set asks none: building one anyway parses the whole universe for
    /// nothing — measured on `discover-reducers --sources <empty folder in a swift-syntax copy>`,
    /// 0.03 s / 12 MB on main against 1.30 s / 379 MB with the build unguarded.
    /// `PurityConfigurationInventoryTests` holds production to this entry.
    public static func forJudging(directory: URL) -> Self? {
        SwiftSourceFiles.sorted(in: directory).isEmpty ? nil : forScan(of: directory)
    }

    /// The project a scan of `directory` belongs to, parsed and its table built, whatever the scan
    /// judges. Production goes through `forJudging(directory:)`; this is the unguarded build, for
    /// tests and for the guard itself.
    public static func forScan(of directory: URL) -> Self {
        forScan(of: directory) { parseInParallel($0) }
    }

    /// `forScan(of:)` with the parse injected, so a test can make the parses complete out of
    /// order and check the build order does not follow them.
    static func forScan(of directory: URL, parse: ([URL]) -> [SourceFileSyntax?]) -> Self {
        let universe = ConstructionUniverse.universe(forScanOf: directory)
        let members = universe.members
        let parsed = parse(members.map(\.url))
        var trees: [String: SourceFileSyntax] = [:]
        var ordered: [SourceFileSyntax] = []
        var used: [String] = []
        for (member, tree) in zip(members, parsed) {
            // A universe file that cannot be read as strict UTF-8 cannot compile either, so it
            // declares no production type (the shared spec's amendment C); skipping it is not a
            // confident zero. A JUDGED file that cannot be read still throws — `FunctionScanner`
            // reads it again and reports the failure.
            guard let tree else { continue }
            trees[member.key] = tree
            ordered.append(tree)
            used.append(member.relativePath)
        }
        // In `members`' order, which is `ConstructionUniverse.buildOrder` — the shared order. The
        // build walks every tree, so it gets the parse's stack (`LargeStackWorkers`).
        let facts = LargeStackWorkers.run { [ordered] in ConstructionFacts.build(from: ordered) }
        return Self(
            root: universe.root,
            universe: used,
            members: members.map(\.relativePath),
            coverage: Coverage(builtFor: directory),
            oracle: SoundPurity(constructionFacts: facts),
            trees: trees
        )
    }

    /// One source that is its own package — what a single-file scan is.
    public static func selfContained(_ tree: SourceFileSyntax) -> Self {
        let oracle = SoundPurity(constructionFacts: .build(from: [tree]))
        return Self(root: nil, universe: [], members: [], coverage: Coverage(builtFor: nil), oracle: oracle, trees: [:])
    }

    /// No facts and no trees. **`internal`**: tests reach it through `@testable import`, and no
    /// production file names it (`PurityConfigurationInventoryTests`).
    static let unconfigured = Self(
        root: nil, universe: [], members: [], coverage: Coverage(builtFor: nil), oracle: .unconfigured, trees: [:]
    )

    /// The same root and the same trees, judged with no facts — the A/B arm a census needs to say
    /// what the table moved on IDENTICAL input. `internal` for the same reason as `unconfigured`.
    var withoutConstructionFacts: Self {
        Self(root: root, universe: universe, members: members, coverage: coverage, oracle: .unconfigured, trees: trees)
    }

    /// The tree this value parsed for `url`, when `url` is in the universe.
    public func tree(for url: URL) -> SourceFileSyntax? {
        trees[ConstructionUniverse.resolved(url).path]
    }

    /// Whether this value is the one a scan of `directory` would build its table from — the same
    /// root AND the same members. A value built for another project is FOREIGN, and judging with
    /// it would be the silent disagreement this type exists to prevent.
    ///
    /// The root alone stopped being enough with the shared spec's amendment J: a scan judging an
    /// uncompiled `Examples/Demo` takes Demo into its universe, and a scan of `Sources/Lib` under
    /// the same root does not, so a value built for one would judge the other under the wrong
    /// table. Equal members under one root mean equal keys and equal trees, so the comparison is
    /// sound; it is not cheap — another directory's universe walks the root, `Tests/` included, and
    /// parses every manifest its closure reaches. Asking it on every call took `covers` from
    /// ~0.05 ms to 54–699 ms, and `discover-reducers`, which asks three times, from 0.9 s to 1.8 s
    /// on swift-package-manager's `Basics`. So, in order:
    ///
    /// 1. **The directory the value was built for** is covered by construction, answered from the
    ///    record, without touching the disk.
    /// 2. **Another root** is another universe — `root(forScanOf:)` alone says so, without a walk.
    /// 3. **Any other directory under the same root** is compared in full, once: the answer is
    ///    remembered, for this value and every copy of it.
    ///
    /// Like the value itself, the answers describe the tree when it was read; an edit since then is
    /// what a new value is for.
    public func covers(_ directory: URL) -> Bool {
        guard let root else { return false }
        return coverage.answer(for: directory) {
            guard ConstructionUniverse.root(forScanOf: directory).path == root.path else { return false }
            return members == ConstructionUniverse.universe(forScanOf: directory).members.map(\.relativePath)
        }
    }

    /// The directory a value was built for, and what `covers(_:)` has answered for any other —
    /// one record shared by every copy of the value (`withoutConstructionFacts` covers what the
    /// value covers: the same root, the same members).
    final class Coverage: @unchecked Sendable {
        /// The standardised path of the directory the universe was computed for, or `nil`.
        private let builtFor: String?
        private let lock = NSLock()
        private var answers: [String: Bool] = [:]

        init(builtFor directory: URL?) {
            builtFor = directory?.standardizedFileURL.path
        }

        /// `true` for the directory the value was built for; else the remembered answer, or
        /// `compute()`'s, remembered.
        func answer(for directory: URL, _ compute: () -> Bool) -> Bool {
            let path = directory.standardizedFileURL.path
            if path == builtFor { return true }
            lock.lock()
            let known = answers[path]
            lock.unlock()
            if let known { return known }
            let computed = compute()
            lock.lock()
            answers[path] = computed
            lock.unlock()
            return computed
        }
    }

    /// Every refuted type with its witness — a structural digest, because `ConstructionFacts ==`
    /// compares node identity and two parses of one package are never equal. The same form
    /// SwiftProjectLint computes, so the two can be compared as text.
    public var refutedTypes: [String] {
        constructionFacts.refutedTypeNames.map { name in
            "\(name): \(constructionFacts.refutation(constructing: name)?.description ?? "?")"
        }
    }

    // MARK: - Parsing

    /// One slot per file, written once each by a parsing worker.
    private final class Slots: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [SourceFileSyntax?]

        init(count: Int) { values = Array(repeating: nil, count: count) }

        func set(_ index: Int, _ tree: SourceFileSyntax?) {
            lock.lock()
            values[index] = tree
            lock.unlock()
        }

        var all: [SourceFileSyntax?] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    /// Parses every file, in parallel, into slots indexed by input position — so the result is in
    /// input order whatever order the parses complete in. Measured necessary: a serial parse of a
    /// 600-file universe in a debug build costs seconds, and the §13 DequeModule row pays it.
    ///
    /// On `LargeStackWorkers`, never on GCD: a parse recurses as deep as the source nests, and a
    /// 512 KB worker stack `SIGBUS`es on ordinary deep Swift — measured, on this very call.
    ///
    /// `beforeParsing` runs on the worker before slot `index` is parsed — a test hook for making
    /// completions arrive out of order; production passes nothing.
    static func parseInParallel(
        _ urls: [URL],
        beforeParsing: @escaping @Sendable (Int) -> Void = { _ in /* no hook */ }
    ) -> [SourceFileSyntax?] {
        let slots = Slots(count: urls.count)
        LargeStackWorkers.forEach(urls.count) { index in
            beforeParsing(index)
            let tree = (try? String(contentsOf: urls[index], encoding: .utf8)).map { Parser.parse(source: $0) }
            slots.set(index, tree)
        }
        return slots.all
    }
}
