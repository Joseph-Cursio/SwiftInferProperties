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
    /// The outermost package's source files, read once for both indexes below.
    private lazy var sourceFiles: [(module: String, text: String)] = packageRoot.map { root in
        DeclaringModuleIndex.sourceFiles(under: SyntaxCorpusSource.outermostPackageRoot(from: root) ?? root)
    } ?? []
    /// The module declaring each type name anywhere in the outermost package's sources.
    private lazy var declaringModules: [String: Set<String>] = sourceFiles.reduce(into: [:]) { index, file in
        for name in DeclaringModuleIndex.declaredNames(in: file.text) {
            index[name, default: []].insert(file.module)
        }
    }
    /// Every class the sources declare, for `TrivialConstruction`.
    private lazy var classes = TrivialConstruction.classes(in: sourceFiles.map(\.text))
    /// Receivers built by `TrivialConstruction`, cached so `allHarvested` carries their imports.
    private var trivial: [String: ReceiverConstructionHarvester.Harvested] = [:]

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
        let declaring = declaringModules
        return (Array(constructions.values) + trivial.values).map { harvested in
            let widened = Self.addingDeclaringImports(harvested, declaring: declaring, in: resolvable)
            return Self.keepingResolvable(widened, in: resolvable)
        }
    }

    /// `harvested` with an `import` for each type it names whose single declaring module this
    /// package can import — the module the test file reached through an import the stub cannot
    /// make (`DeclaringModuleIndex`). A name declared in two modules is left alone.
    static func addingDeclaringImports(
        _ harvested: ReceiverConstructionHarvester.Harvested,
        declaring: [String: Set<String>],
        in resolvable: Set<String>
    ) -> ReceiverConstructionHarvester.Harvested {
        let present = Set(harvested.imports.compactMap(InteractiveTriage.importedModule(in:)))
        let added = DeclaringModuleIndex.typeNames(in: harvested.expression)
            .compactMap { declaring[$0].flatMap { $0.count == 1 ? $0.first : nil } }
            .filter { resolvable.contains($0) && !present.contains($0) }
        let lines = Set(added).sorted().map { "import \($0)" }
        return ReceiverConstructionHarvester.Harvested(
            expression: harvested.expression, imports: harvested.imports + lines
        )
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

    /// A construction a test wrote, else one `TrivialConstruction` can build from an initializer
    /// whose arguments all have an obvious empty value — never the other way round, since a test's
    /// receiver holds the state the tests exercise.
    private func harvested(for typeName: String) -> ReceiverConstructionHarvester.Harvested? {
        let bare = typeName.components(separatedBy: ".").last ?? typeName
        if let written = constructions[typeName] ?? constructions[bare] { return written }
        if let cached = trivial[typeName] { return cached }
        guard packageRoot != nil, let (expression, needsSyntax) = TrivialConstruction.expression(
            for: typeName, classes: classes
        ) else { return nil }
        let built = ReceiverConstructionHarvester.Harvested(
            expression: expression, imports: needsSyntax ? ["import SwiftSyntax"] : []
        )
        trivial[typeName] = built
        return built
    }
}
