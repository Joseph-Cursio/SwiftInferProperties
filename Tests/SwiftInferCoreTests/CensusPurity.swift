import Foundation
import SwiftEffectInference
import SwiftParser
import SwiftSyntax

@testable import SwiftInferCore

/// The purity every census over this repo judges under: the one production builds for
/// `swift-infer discover` run on this package, and — through `purity(forScanOf:)` — the one it
/// builds for any corpus root.
///
/// A census that judged under `.unconfigured` while the scan judges under construction facts would
/// be measuring an oracle nothing ships — the drift `verdictAgreesWithSoundPurity` exists to catch,
/// arriving through a parameter instead of a marker set. So no census builds its own oracle; each
/// asks here.
enum CensusPurity {

    static let packageRoot = URL(fileURLWithPath: #filePath, isDirectory: false)
        .deletingLastPathComponent()   // SwiftInferCoreTests/
        .deletingLastPathComponent()   // Tests/
        .deletingLastPathComponent()   // SwiftInferProperties/

    static let sourcesRoot = packageRoot.appendingPathComponent("Sources")

    /// What `PackagePurity.forScan(of: Sources/<any target>)` builds for this repo.
    static var ownPackage: PackagePurity { purity(forScanOf: sourcesRoot) }

    /// The configured oracle for this repo's own sources.
    static var oracle: SoundPurity { ownPackage.oracle }

    /// A `PurityInferrer` holding the same table — for the census replica, which consults SEI's
    /// first witness. A value type, so it answers exactly as the one inside `oracle` does.
    static var inferrer: PurityInferrer { PurityInferrer(constructionFacts: ownPackage.constructionFacts) }

    /// The tree `purity` parsed for `file`, or a fresh parse when `file` is outside its universe
    /// (a test file, a judged file the predicate drops). A census judges the very nodes
    /// production does, which matters: SEI types assignments by node identity.
    static func tree(for file: URL, in purity: PackagePurity = ownPackage) -> SourceFileSyntax? {
        if let shared = purity.tree(for: file) { return shared }
        guard let source = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return Parser.parse(source: source)
    }

    /// A snippet is its own package, exactly as `FunctionScanner.scanCorpus(source:file:)` treats
    /// one: its facts are its own tree's.
    static func snippetOracle(_ tree: SourceFileSyntax) -> SoundPurity {
        PackagePurity.selfContained(tree).oracle
    }

    // MARK: - The memo

    /// One value per universe root for the whole test process, shared by every census helper
    /// that asks — a root is parsed once however many suites, arms or scan paths reach it.
    static func purity(forScanOf directory: URL) -> PackagePurity {
        let key = ConstructionUniverse.root(forScanOf: directory).path
        return memo.value(for: key) { PackagePurity.forScan(of: directory) }
    }

    private static let memo = Memo()

    /// Lock-guarded, and the build runs under the lock: two suites racing for one root must not
    /// both parse it, and a second value for the same root would hold different tree nodes.
    private final class Memo: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: PackagePurity] = [:]

        func value(for key: String, build: () -> PackagePurity) -> PackagePurity {
            lock.lock()
            defer { lock.unlock() }
            if let built = values[key] { return built }
            let built = build()
            values[key] = built
            return built
        }
    }
}
