import Foundation
import SwiftInferCore

/// Generators for a class receiver, built the way the package's own tests build it.
///
/// One per `discover --interactive` run, harvested on first use. See
/// `ReceiverConstructionHarvester` for what makes an expression usable outside the test that
/// wrote it.
///
/// ⚠ **A fresh instance per draw, never a shared one.** These receivers are visitors and other
/// accumulating objects: `Gen.always(Visitor(…))` evaluates once and hands every trial the same
/// object, so trial 2 would see trial 1's state. The draw is mapped instead, which re-evaluates
/// the expression each time.
final class ReceiverConstructionSource {

    private let testRoots: [URL]
    private let wanted: Set<String>
    private lazy var constructions = ReceiverConstructionHarvester.harvest(roots: testRoots, wanted: wanted)

    init(packageRoot: URL, wanted: Set<String>) {
        self.testRoots = SyntaxCorpusSource.testDirectories(of: packageRoot)
            + (SyntaxCorpusSource.outermostPackageRoot(from: packageRoot).map(SyntaxCorpusSource.testDirectories) ?? [])
        self.wanted = wanted
    }

    /// Test seam: constructions supplied directly.
    init(constructions: [String: String]) {
        self.testRoots = []
        self.wanted = []
        self.constructions = constructions
    }

    /// The construction expression for `typeName`, or `nil` when no test constructs it usably.
    func expression(for typeName: String) -> String? {
        constructions[typeName] ?? constructions[typeName.components(separatedBy: ".").last ?? typeName]
    }
}
