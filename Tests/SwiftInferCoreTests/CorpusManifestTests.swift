import Foundation
import Testing

@testable import SwiftInferCore

/// **The guard for the failure that produced this loader.**
///
/// On 2026-08-19 nine censuses ran against **three** corpora while the manifest listed
/// **22**. Two declines were argued from that trio — one explicitly on the grounds that a
/// shape was *"self-only"* — without ever looking at swift-format, GRDB, NIO or the Swift
/// stdlib, all of which were on the machine.
///
/// **A census that silently sees one corpus concludes "self-only" exactly like a census
/// that saw twenty.** That is this repo's confident zero, one level up: not a scan that
/// reaches nothing, but a *corpus list* that reaches almost nothing. The floor below is
/// what makes the difference visible.
@Suite("Corpus manifest — the census universe is the manifest, not a hardcoded trio")
struct CorpusManifestTests {

    /// **The floor is a smoke alarm, not a metric.** 18 resolved when this was written; it
    /// fails at 8, which is far enough below to survive a machine with fewer checkouts and
    /// far enough above to catch a loader returning almost nothing.
    @Test("the manifest resolves a plausible number of corpora")
    func theManifestResolves() {
        #expect(CorpusManifest.available.count >= 8, """
        Only \(CorpusManifest.available.count) corpora resolved. A census run against this \
        list would report "self-only" for a shape it never looked for elsewhere, which is \
        the failure this loader exists to prevent. Absent: \
        \(CorpusManifest.absent.joined(separator: ", ")).
        """)
    }

    /// **The `~` expansion, asserted directly.** The manifest stores `~/GitHub_projects/…`;
    /// a check that compares that string to the filesystem unexpanded reports every such
    /// corpus absent. That is precisely the mistake that hid thirteen subjects.
    @Test("tilde paths are expanded, not compared raw")
    func tildePathsResolve() {
        let tildeBacked = ["swift-format", "swift-nio", "swift-syntax", "swift-foundation"]
        let resolved = Set(CorpusManifest.available.map(\.id))
        #expect(tildeBacked.contains { resolved.contains($0) }, """
        No `~`-rooted corpus resolved. Either this machine has none of them, or `~` is \
        being compared literally — and those two look identical from the count alone.
        """)
    }

    /// A corpus that scans nothing contributes a zero indistinguishable from a corpus with
    /// no findings, so it must not be in the list a census iterates.
    @Test("no available corpus resolves to an empty directory")
    func noEmptyCorpusIsOffered() {
        for corpus in CorpusManifest.available {
            #expect(corpus.swiftFileCount > 0, "\(corpus.id) resolved to a root with no Swift files")
        }
    }

    @Test("census — what the manifest actually offers")
    func census() {
        print("CORPUS MANIFEST — \(CorpusManifest.available.count) available")
        for corpus in CorpusManifest.available {
            print("  \(corpus.id.padding(toLength: 26, withPad: " ", startingAt: 0))"
                + "\(corpus.kind.padding(toLength: 10, withPad: " ", startingAt: 0))"
                + "\(corpus.swiftFileCount) files")
        }
        print("  absent (checkout not on this machine): \(CorpusManifest.absent.joined(separator: ", "))")
        print("  resolved but empty:                    \(CorpusManifest.emptyRoots.joined(separator: ", "))")
    }
}
