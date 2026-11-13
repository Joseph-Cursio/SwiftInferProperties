import Foundation
@testable import SwiftInferCore
import SwiftParser
import SwiftSyntax
import Testing

/// **In a package with no sign of TCA, `Effect` is the package's own name.** `ReducerPurityAnalyzer`
/// refutes on `Effect`, `EffectOf` and `EffectTask` by name, which is right for routing — a false
/// positive there costs a subprocess — and wrong for `SoundPurity`, where it becomes `.refuted` and
/// the impure-subject veto withholds the law. Found 2026-11-12: SEI's own lattice enum is named
/// `Effect`, and three of its pure functions lost their laws to it.
///
/// **`.run` is deliberately NOT narrowed**, though most of its hits were collisions too: it also
/// spells `Process.run()`, and the `.run` collisions were often impure through calls nothing else
/// follows. `runStillRefutes` pins that decision.
@Suite("ReducerPurityAnalyzer — TCA's type names are TCA's only where TCA is")
struct ReducerPurityNameTokenTests {

    private static func function(_ source: String, named name: String) throws -> FunctionDeclSyntax {
        final class Finder: SyntaxVisitor {
            let name: String
            var found: FunctionDeclSyntax?

            init(_ name: String) {
                self.name = name
                super.init(viewMode: .sourceAccurate)
            }

            override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
                if found == nil, node.name.text == name { found = node }
                return .visitChildren
            }
        }
        let finder = Finder(name)
        finder.walk(Parser.parse(source: source))
        return try #require(finder.found)
    }

    /// The first function in `source`: `func combine(…` → `combine`.
    private static func subject(_ source: String) throws -> FunctionDeclSyntax {
        let afterKeyword = try #require(source.components(separatedBy: "func ").dropFirst().first)
        return try function(source, named: String(afterKeyword.prefix { $0 != "(" }))
    }

    private static func purity(_ function: FunctionDeclSyntax, tca: Bool) -> ReducerPurity {
        ReducerPurityAnalyzer.analyzeForPurity(function, readingTCANames: tca)
    }

    private static let lattice = "enum Effect: Hashable { case pure, impure }\n"

    private static func scratchDirectory(_ label: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(label)-\(UUID().uuidString)")
    }

    // MARK: - The analyzer

    @Test("a package's own type named Effect does not refute where TCA is absent", arguments: [
        // SEI's `combine`: a static call on its own `Effect` enum.
        "func combine(_ effects: [Effect]) -> Effect? { Effect.lub(of: effects) }",
        // SEI's `nameGatedInference`: the name only as a type annotation.
        "func gate(_ name: String) -> Bool { let effect: Effect = name.isEmpty ? .pure : .impure; return true }",
        // A local set of the lattice type.
        "func one(_ names: [String]) -> Int { var matched: Set<Effect> = []; matched.insert(.pure); return 1 }",
        "func two() -> Bool { let first: EffectOf<Int>? = nil; let second: EffectTask<Int>? = nil; return true }",
    ])
    func ownEffectTypeIsPure(_ body: String) throws {
        let subject = try Self.subject(Self.lattice + body)
        #expect(Self.purity(subject, tca: false) == .pure)
        #expect(Self.purity(subject, tca: true) == .effectBearing, "where TCA is, the name is TCA's")
        #expect(ReducerPurityAnalyzer.analyze(subject) == .effectBearing, "routing is unchanged")
    }

    @Test("`.run` refutes on any base, TCA or not — `Process.run()` included", arguments: [
        "func launch(_ process: Process) -> Bool { (try? process.run()) != nil }",
        "func extract(_ source: String) -> Int { ParsingStack.run { source.count } }",
        "func draw(_ rng: inout Rng) -> Int { generator.run(using: &rng) }",
        "func make() -> Thing { .run { _ in } }",
    ])
    func runStillRefutes(_ body: String) throws {
        #expect(Self.purity(try Self.subject(body), tca: false) == .effectBearing)
    }

    @Test("Swift's own concurrency names and TCA's calls still refute where TCA is absent", arguments: [
        "func go() { Task { work() } }",
        "func go() -> Int { let token: AnyCancellable? = nil; return token == nil ? 0 : 1 }",
        "func go() { store.send(.tapped) }",
        "func go() -> String? { try? Request.customRequest(request: request).send() }",
        "func go() { cancellable.cancel() }",
        "func go() { effect.fireAndForget() }",
        "func go() async -> Int { await fetch() }",
    ])
    func realEffectTokensRefute(_ body: String) throws {
        #expect(Self.purity(try Self.subject(body), tca: false) == .effectBearing)
    }

    @Test("a static write is still hidden mutability where TCA is absent")
    func staticWriteStillRefutes() throws {
        let subject = try Self.subject("func bump() -> Int { Self.counter += 1; return 0 }")
        #expect(Self.purity(subject, tca: false) == .hiddenMutability)
    }

    // MARK: - TCAPresence: one sign anywhere in the package

    @Test("an import of ComposableArchitecture is a sign, however it is spelled", arguments: [
        "import ComposableArchitecture",
        "@_exported import ComposableArchitecture",
        "@preconcurrency import ComposableArchitecture",
        "import struct ComposableArchitecture.Effect",
        "#if canImport(ComposableArchitecture)\nimport ComposableArchitecture\n#endif",
        "#if os(iOS)\n#else\n#if DEBUG\nimport ComposableArchitecture\n#endif\n#endif",
    ])
    func importSpellings(_ header: String) {
        #expect(TCAPresence.shows(in: [Parser.parse(source: "\(header)\nfunc f() {}")], root: nil))
    }

    @Test("no import of ComposableArchitecture and no manifest is no sign")
    func noSign() {
        let tree = Parser.parse(source: "import Foundation\nimport ComposableArchitectureHelpers\n\(Self.lattice)")
        #expect(!TCAPresence.shows(in: [tree], root: nil))
    }

    @Test("a manifest naming TCA is a sign, so a kit that re-exports TCA is still seen", arguments: [
        "Package.swift",
        "Package.resolved",
        "App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
    ])
    func manifestSign(_ relativePath: String) throws {
        let root = Self.scratchDirectory("tca-presence")
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try "https://github.com/pointfreeco/swift-composable-architecture"
            .write(to: manifest, atomically: true, encoding: .utf8)
        #expect(TCAPresence.shows(in: [], root: root))
        #expect(!TCAPresence.shows(in: [], root: root.appendingPathComponent("elsewhere")), "control: no manifest")
    }

    // MARK: - SoundPurity and PackagePurity carry the package's answer

    @Test("a package whose OTHER file re-exports TCA reads Effect as TCA's in every file")
    func packageWideSign() throws {
        let root = Self.scratchDirectory("tca-package")
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = root.appendingPathComponent("Sources/Feature")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let manifest = """
        // swift-tools-version:5.9
        import PackageDescription
        let package = Package(name: "Feature", targets: [.target(name: "Feature")])
        """
        try manifest.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let feature = "func persist(_ count: Int) -> Effect<Int> { Effect.none }\n"
        try feature.write(to: sources.appendingPathComponent("Feature.swift"), atomically: true, encoding: .utf8)

        let without = PackagePurity.forScan(of: sources)
        #expect(!without.oracle.tcaNamesAreTCAs, "control: nothing names TCA yet")

        try "@_exported import ComposableArchitecture\n"
            .write(to: sources.appendingPathComponent("Exports.swift"), atomically: true, encoding: .utf8)
        let with = PackagePurity.forScan(of: sources)
        #expect(with.oracle.tcaNamesAreTCAs)
        #expect(with.oracle.verdict(for: try Self.subject(feature)) == .refuted)
        #expect(with.withoutConstructionFacts.oracle.tcaNamesAreTCAs, "the facts-free arm keeps the package's reading")
    }

    @Test("a single file is its own package, and its own import decides")
    func selfContainedReadsItsOwnFile() {
        #expect(!PackagePurity.selfContained(Parser.parse(source: Self.lattice)).oracle.tcaNamesAreTCAs)
        let importing = Parser.parse(source: "import ComposableArchitecture")
        #expect(PackagePurity.selfContained(importing).oracle.tcaNamesAreTCAs)
    }

    @Test("SoundPurity judges a lattice function pure only when told TCA is absent, and defaults to TCA")
    func soundPurityVerdicts() throws {
        let strongest = try Self.subject(Self.lattice + """
        func strongest(_ effects: [Effect]) -> Effect { effects.contains(.impure) ? Effect.impure : Effect.pure }
        """)
        let absent = SoundPurity(constructionFacts: .empty, tcaNamesAreTCAs: false)
        #expect(absent.verdict(for: strongest) == .pure)
        #expect(absent.inferredEffect(for: strongest) == .pure)
        let unsaid = SoundPurity(constructionFacts: .empty)
        #expect(unsaid.verdict(for: strongest) == .refuted, "the default is conservative")
        #expect(SoundPurity.unconfigured.verdict(for: strongest) == .refuted)
    }

    @Test("a getter's verdict reads the package's answer too")
    func getterReadsThePackageAnswer() throws {
        let tree = Parser.parse(source: Self.lattice + """
        struct Report {
            let effects: [Effect]
            var strongest: Effect { effects.contains(.impure) ? Effect.impure : Effect.pure }
        }
        """)
        let report = try #require(tree.statements.lazy.compactMap { $0.item.as(StructDeclSyntax.self) }.first)
        let getters = report.memberBlock.members.compactMap {
            $0.decl.as(VariableDeclSyntax.self)?.bindings.first?.accessorBlock
        }
        let getter = try #require(getters.first)
        let absent = SoundPurity(constructionFacts: .empty, tcaNamesAreTCAs: false)
        #expect(absent.verdict(forGetter: getter) == .pure)
        #expect(SoundPurity(constructionFacts: .empty).verdict(forGetter: getter) == .refuted)
    }
}
