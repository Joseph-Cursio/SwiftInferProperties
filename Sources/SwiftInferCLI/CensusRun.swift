import Foundation

/// One catalog-health census, with its denominator recorded **by the run that took it**.
///
/// ## The problem this exists for
///
/// A census counts rows per template across N corpora and concludes things like *"6 of 39
/// templates never fire"*. That conclusion is **only as wide as N**, and N was written down
/// afterwards, in prose, by hand. Two consequences arrived within a fortnight of each other:
///
/// - `involution` was filed as never-firing while a witness sat in a ninth corpus this project
///   had already measured. Nothing was wrong with the count; the denominator was not the world.
/// - Four registry entries claimed membership in the eight-corpus sweep and only one was in it,
///   while an actual member had no entry at all. Two prose records of the same denominator
///   disagreed about half its contents, and settling it took reading an A/B table row by row.
///
/// Both are the same failure: **a zero is a claim about a corpus list, and the list was not part
/// of the artifact.** So this type makes the list the first thing the run writes down.
///
/// ## Why by REGISTRY ID and not by path
///
/// A path is what the four earlier retained runs recorded, and every one of them names a
/// scratchpad directory belonging to a session that ended — `fixtures/corpora/README.md` opens
/// with that finding. An id resolves through the manifest to a remote and a revision, so the
/// corpus stays findable after the machine that ran it is gone.
///
/// The revision is captured here **as read from the checkout at run time**, which is the fact
/// the manifest could not supply: a manifest revision records what some earlier measurement
/// used, and this one records what *this* census actually stood on. That is the distinction five
/// registry entries got wrong by recording whatever was checked out when the registry was
/// written.
struct CensusRun: Codable, Sendable {

    static let currentSchemaVersion = 1

    let schemaVersion: Int

    /// What this census was for, in a line. Free text, and the only free text here.
    let label: String

    let capturedAt: Date

    /// The flags the pipeline ran under, rendered as typed.
    ///
    /// **Recorded because a remembered count carries no record of them.** This project has
    /// already published a drift finding that was entirely `--include-possible`: 96 against 80,
    /// one binary, one afternoon, one corpus. Tier visibility moves the headline by 20%, so a
    /// census without its flags is not comparable with anything, including itself.
    let flags: String

    let swiftInferVersion: String

    /// **The denominator.** One entry per corpus, in the order surveyed.
    let corpora: [Member]

    /// One surveyed corpus.
    struct Member: Codable, Sendable {

        /// The registry id — the thing that makes this resolvable later.
        let id: String

        /// Read from the checkout at run time, or `nil` when it is not a git tree.
        ///
        /// Not defaulted to the manifest's pin: the manifest records what an *earlier*
        /// measurement used, and silently substituting it would reproduce, inside the artifact
        /// meant to prevent it, the exact error of recording a revision nobody measured against.
        let revision: String?

        /// A dirty tree means the rows below count uncommitted work and the revision does not
        /// fully name what was surveyed.
        let dirty: Bool

        /// Whether the checkout stood where its baseline was taken, as `CorpusPin` renders it.
        let pin: String

        /// Which directories were scanned, checkout-relative.
        ///
        /// **Recorded because the scan path is not a filter over one fixed answer — it decides
        /// what the answer can be.** Cross-function pairing spans whatever is in scope at once,
        /// so widening a path does not merely add rows from more files: it creates pairs no
        /// narrower scan can see. Measured on `SwiftProjectLint`, whose code is split across two
        /// trees — `Sources` gives 9 rows and `Packages` 390, while the enclosing root gives
        /// **776**, and 365 of the difference is a single template (`inverse-pair`) absent from
        /// both sub-scans.
        ///
        /// So two censuses of the same corpus at the same revision can differ by a factor of
        /// two on the scan path alone. Without this field that difference is invisible, and the
        /// artifact would present it as a change in the catalog.
        let scanPaths: [String]

        /// Rows per `templateName`. **Templates that fired zero times are absent**, which is why
        /// `CensusRun.zeroRowTemplates(against:)` takes the catalog as an argument: a zero is a
        /// fact about a template *and* this corpus list, and it cannot be read off the counts.
        let rowsByTemplate: [String: Int]

        var total: Int { rowsByTemplate.values.reduce(0, +) }
    }

    /// Rows per template summed across every member.
    var rowsByTemplate: [String: Int] {
        corpora.reduce(into: [:]) { total, member in
            for (template, rows) in member.rowsByTemplate { total[template, default: 0] += rows }
        }
    }

    var total: Int { corpora.reduce(0) { $0 + $1.total } }

    /// The templates that fired nowhere in this census — **the answer this artifact exists for.**
    ///
    /// It takes the catalog rather than deriving it, because the interesting set is the one that
    /// is *absent* from the counts, and absence is not in the data. Returning it beside
    /// `corpora` is what keeps the zero attached to the list that produced it.
    func zeroRowTemplates(against catalog: [String]) -> [String] {
        let fired = Set(rowsByTemplate.keys)
        return catalog.filter { !fired.contains($0) }.sorted()
    }

    static func write(_ run: Self, to url: URL) throws {
        let coder = JSONEncoder()
        coder.outputFormatting = [.prettyPrinted, .sortedKeys]
        coder.dateEncodingStrategy = .iso8601
        try coder.encode(run).write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> Self {
        let coder = JSONDecoder()
        coder.dateDecodingStrategy = .iso8601
        return try coder.decode(Self.self, from: try Data(contentsOf: url))
    }
}
