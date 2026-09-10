import Foundation
import PropertyBased
@testable import SwiftInferCore
import Testing

/// Laws over `DirectoryAncestors.chain(from:)`, quantified rather than exemplified.
///
/// This is the first extraction in this package driven by SwiftProjectLint's
/// `extractable-total-kernel`, and the point of it is that the function is now **total**, so a
/// generator can quantify over it. Six copies of this walk lived in `SwiftInferCLI` and a seventh in
/// `KitEvidenceStore`, each welded to a `FileManager.fileExists` probe, so none of them could be
/// asked anything without a real directory tree.
///
/// **The law that matters is the first one**, and it fails against every copy that existed before:
/// each was `while true`, stopping only at a `deletingLastPathComponent()` fixpoint, and a relative
/// URL with no scheme never reaches one.
@Suite("DirectoryAncestors — the ancestor chain is a total function")
struct DirectoryAncestorsLawTests {

    // MARK: - Generators

    /// A path segment that is awkward but legal: spaces, dots, unicode, and the empty string, which
    /// is where `URL` normalisation gets interesting.
    private static func segment() -> Generator<String, some SendableSequenceType> {
        Gen<Int>.int(in: 0 ..< 8).map { choice in
            ["a", "b c", ".", "..", "", "é", "📁", "Package.swift"][choice]
        }
    }

    /// Absolute file URLs — what every call site actually passes.
    private static func absoluteDirectory() -> Generator<URL, some SendableSequenceType> {
        segment().array(of: 0 ... 6).map { segments in
            URL(fileURLWithPath: "/" + segments.joined(separator: "/"), isDirectory: true)
        }
    }

    /// The shapes the old loop hung on: a relative URL with no scheme, where
    /// `deletingLastPathComponent()` *lengthens* the path forever.
    private static func relativeURL() -> Generator<URL, some SendableSequenceType> {
        segment().array(of: 1 ... 4).map { segments in
            URL(string: segments.joined(separator: "/")) ?? URL(fileURLWithPath: "/")
        }
    }

    // MARK: - Totality

    /// **The defect the extraction found.** Every one of the seven copies looped forever on a
    /// relative URL: `URL(string: "foo")` goes `foo`, `../`, `../../`, without end, so the fixpoint
    /// check never fires. Measured at 500 iterations with the path still growing.
    ///
    /// Totality is what makes the rest of this suite possible, which is the whole argument for
    /// naming a kernel: an infinite loop cannot be quantified over.
    @Test("chain terminates for every URL, relative ones included")
    func chainIsTotal() async {
        await propertyCheck(input: Self.relativeURL()) { url in
            let chain = DirectoryAncestors.chain(from: url)
            #expect(!chain.isEmpty)
        }
        await propertyCheck(input: Self.absoluteDirectory()) { url in
            #expect(!DirectoryAncestors.chain(from: url).isEmpty)
        }
    }

    /// **The old loop, pinned as non-terminating.** Every one of the seven copies was exactly this,
    /// without the step cap — so this is a regression test for the defect rather than a claim about
    /// it. The cap is what lets the test report instead of hanging; without it this function does
    /// not return.
    ///
    /// If a future change makes the repair unnecessary, this test fails and says so.
    @Test("the walk the seven copies used does not terminate on a relative URL")
    func theOldLoopDoesNotConverge() throws {
        func oldWalk(from directory: URL, cap: Int) -> (steps: Int, converged: Bool) {
            var current = directory.standardizedFileURL
            for step in 0 ..< cap {
                let parent = current.deletingLastPathComponent().standardizedFileURL
                if parent == current { return (step, true) }
                current = parent
            }
            return (cap, false)
        }

        // Absolute paths converge, which is why nobody noticed.
        #expect(oldWalk(from: URL(fileURLWithPath: "/a/b/c"), cap: 500).converged)

        // Relative URLs with no scheme do not: `deletingLastPathComponent()` prepends `../` and the
        // path grows without bound.
        for spelling in ["foo", "a/b", "."] {
            let url = try #require(URL(string: spelling))
            #expect(!oldWalk(from: url, cap: 500).converged, "\(spelling) unexpectedly converged")
            // And the replacement is total on the same input.
            #expect(!DirectoryAncestors.chain(from: url).isEmpty)
        }
    }

    // MARK: - The chain's shape

    /// Strictly decreasing in path components. This is the invariant the old loop *assumed* —
    /// walking up shortens the path — and it is the one the termination guard now enforces, so
    /// stating it here is stating the repair rather than restating the implementation.
    @Test("each step is a proper ancestor of the one before")
    func chainStrictlyDecreases() async {
        await propertyCheck(input: Self.absoluteDirectory()) { url in
            let chain = DirectoryAncestors.chain(from: url)
            for (child, parent) in zip(chain, chain.dropFirst()) {
                #expect(parent.pathComponents.count < child.pathComponents.count)
            }
        }
    }

    /// The first element is the directory itself, standardized. A caller searching the chain for a
    /// manifest has to consider the directory it asked about — every one of the seven copies started
    /// there, and a chain that skipped it would silently stop finding a `Package.swift` beside the
    /// file being scanned.
    @Test("the chain starts at the directory it was asked about")
    func chainStartsAtItsInput() async {
        await propertyCheck(input: Self.absoluteDirectory()) { url in
            #expect(DirectoryAncestors.chain(from: url).first == url.standardizedFileURL)
        }
    }

    /// Every element is a prefix of the original, so nothing outside the input's own lineage is ever
    /// probed for a manifest.
    @Test("every ancestor is a path prefix of the input")
    func everyAncestorIsAPrefix() async {
        await propertyCheck(input: Self.absoluteDirectory()) { url in
            let chain = DirectoryAncestors.chain(from: url)
            let components = url.standardizedFileURL.pathComponents
            for ancestor in chain {
                #expect(Array(components.prefix(ancestor.pathComponents.count)) == ancestor.pathComponents)
            }
        }
    }

    /// Idempotent under re-entry: asking about the head of a chain gives that chain back. This is
    /// the round-trip the rule's message asks for, and it is what makes the search well-defined —
    /// resuming a walk from any point it visited sees the same remaining ancestors.
    @Test("chaining from the head of a chain reproduces it")
    func chainIsIdempotentAtItsHead() async {
        await propertyCheck(input: Self.absoluteDirectory()) { url in
            let chain = DirectoryAncestors.chain(from: url)
            let head = try #require(chain.first)
            #expect(DirectoryAncestors.chain(from: head) == chain)
        }
    }

    /// Dropping the first element gives exactly the chain of the second — the recursive structure
    /// the hand-rolled loops implemented by mutation.
    @Test("the tail of a chain is the chain of its second element")
    func theTailIsTheParentsChain() async {
        await propertyCheck(input: Self.absoluteDirectory()) { url in
            let chain = DirectoryAncestors.chain(from: url)
            guard chain.count > 1 else { return }
            #expect(DirectoryAncestors.chain(from: chain[1]) == Array(chain.dropFirst()))
        }
    }

    // MARK: - The search built on it

    /// `nearest` returns the *nearest* match, not merely a match: no earlier element satisfies the
    /// predicate. Every one of the seven copies returned on the first hit walking up, and nothing
    /// said so.
    @Test("nearest returns the closest satisfying ancestor")
    func nearestIsNearest() async {
        await propertyCheck(input: Self.absoluteDirectory()) { url in
            let chain = DirectoryAncestors.chain(from: url)
            // A predicate with a deterministic, generated-input-dependent answer: match any
            // ancestor whose component count is even.
            let predicate: (URL) -> Bool = { $0.pathComponents.count % 2 == 0 }
            let found = DirectoryAncestors.nearest(from: url, where: predicate)
            if let found {
                let index = try #require(chain.firstIndex(of: found))
                #expect(!chain.prefix(index).contains(where: predicate))
            } else {
                #expect(!chain.contains(where: predicate))
            }
        }
    }
}
