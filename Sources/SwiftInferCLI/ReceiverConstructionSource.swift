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
    private let packageRoot: URL?
    /// The modules a generated file in this package can import, read from the manifest once.
    private lazy var buildModules: Set<String> = packageRoot.flatMap {
        TestTargetScope.buildModules(packageRoot: $0)
    } ?? []
    private lazy var constructions = ReceiverConstructionHarvester.harvestWithImports(roots: testRoots, wanted: wanted)

    init(packageRoot: URL, wanted: Set<String>) {
        self.testRoots = SyntaxCorpusSource.testDirectories(of: packageRoot)
            + (SyntaxCorpusSource.outermostPackageRoot(from: packageRoot).map(SyntaxCorpusSource.testDirectories) ?? [])
        self.wanted = wanted
        self.packageRoot = packageRoot
    }

    /// Test seam: constructions supplied directly.
    init(constructions: [String: String], imports: [String] = []) {
        self.testRoots = []
        self.wanted = []
        self.packageRoot = nil
        self.constructions = constructions.mapValues {
            ReceiverConstructionHarvester.Harvested(expression: $0, imports: imports)
        }
    }

    /// The construction expression for `typeName`, or `nil` when no test constructs it usably.
    func expression(for typeName: String) -> String? {
        harvested(for: typeName)?.expression
    }

    /// Every harvested construction, harvesting on first use, each keeping only the imports this
    /// package can resolve — see `TestTargetScope.buildModules` for why a test file's other imports
    /// must never reach a generated one. No manifest, no imports: the behaviour before any were carried.
    var allHarvested: [ReceiverConstructionHarvester.Harvested] {
        let resolvable = buildModules
        return constructions.values.map { Self.keepingResolvable($0, in: resolvable) }
    }

    /// `harvested` with only the imports whose module is in `resolvable`.
    static func keepingResolvable(
        _ harvested: ReceiverConstructionHarvester.Harvested,
        in resolvable: Set<String>
    ) -> ReceiverConstructionHarvester.Harvested {
        ReceiverConstructionHarvester.Harvested(
            expression: harvested.expression,
            imports: harvested.imports.filter { line in
                InteractiveTriage.importedModule(in: line).map(resolvable.contains) ?? false
            }
        )
    }

    private func harvested(for typeName: String) -> ReceiverConstructionHarvester.Harvested? {
        constructions[typeName] ?? constructions[typeName.components(separatedBy: ".").last ?? typeName]
    }
}
