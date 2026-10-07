import Foundation
import SwiftEffectInference
import Testing

@testable import SwiftInferCore

private typealias Wiring = ConstructionPurityWiringTests
private typealias Nested = ConstructionUniverseNestedPackageTests

/// **A package the scan judges is in its universe** — the shared spec's amendment J. A nested
/// package holding a judged file is in, with its own local-dependency closure, whether or not the
/// root compiles it: a function is judged with its own package's types.
@Suite("Construction universe — the packages a scan judges")
struct ConstructionUniverseJudgedPackageTests {

    static let item = """
    import Foundation
    public struct Item: Equatable { public let id = UUID(); public let n: Int; public init(n: Int) { self.n = n } }
    """
    static let callers = """
    public func normalized(_ item: Item) -> Item { Item(n: abs(item.n)) }
    public func clamp(_ value: Int) -> Int { min(max(value, 0), 10) }
    """

    /// The review's `robustness#1` (`fx/sip-inc-nested`): the root compiles only `App`, and
    /// `Examples/Demo` is a package of its own. `discover --sources Examples` judges Demo's
    /// `normalized`, which builds a UUID-minting `Item` — and the bound took Demo's files out of the
    /// table, so `normalized` read pure and an idempotence law was proposed over it.
    @Test("a scan over an uncompiled nested package judges it with its own types")
    func judgedNestedPackageIsInItsUniverse() throws {
        let root = try Wiring.makePackage([
            "Examples/Demo/Package.swift": Nested.demoManifest,
            "Examples/Demo/Sources/Demo/Item.swift": Self.item,
            "Examples/Demo/Sources/Demo/Callers.swift": Self.callers,
            "Sources/App/Plain.swift": "public func appPlain(_ n: Int) -> Int { n * 2 }"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let examples = root.appendingPathComponent("Examples")
        #expect(ConstructionUniverse.files(forScanOf: examples).map(\.relativePath) == [
            "Examples/Demo/Sources/Demo/Callers.swift", "Examples/Demo/Sources/Demo/Item.swift",
            "Sources/App/Plain.swift"
        ])
        #expect(try Nested.verdict("normalized", scanning: examples) == .refuted)
        #expect(try Nested.verdict("clamp", scanning: examples) == .pure, "control: the table refutes only the builder")
        // A scan that judges only the root's own files leaves Demo out, as before.
        let app = root.appendingPathComponent("Sources/App")
        #expect(ConstructionUniverse.files(forScanOf: app).map(\.relativePath) == ["Sources/App/Plain.swift"])
    }

    /// The judged package brings its own closure: Demo depends on `../../Shared`, where `Item` lives,
    /// and no file under the scanned `Examples/` is Shared's.
    @Test("a judged nested package brings its own local dependencies")
    func judgedPackageBringsItsClosure() throws {
        let root = try Wiring.makePackage([
            "Examples/Demo/Package.swift": Nested.manifest(dependingOn: "../../Shared"),
            "Examples/Demo/Sources/Demo/Callers.swift": Self.callers,
            "Shared/Package.swift": Nested.demoManifest,
            "Shared/Sources/Shared/Item.swift": Self.item,
            "Sources/App/Plain.swift": "public func appPlain(_ n: Int) -> Int { n * 2 }"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let examples = root.appendingPathComponent("Examples")
        let paths = ConstructionUniverse.files(forScanOf: examples).map(\.relativePath)
        #expect(paths.contains("Shared/Sources/Shared/Item.swift"), "\(paths)")
        #expect(try Nested.verdict("normalized", scanning: examples) == .refuted)
    }

    /// The accepted cost, in the sound direction: a scan of the whole root judges Demo's files, so
    /// Demo is in, and its `Row` refutes the root's namesake again — only when Demo is judged too.
    @Test("a scan that judges the namesake's package takes it, and the namesake refutes")
    func judgingTheNamesakePackageTakesIt() throws {
        let root = try Wiring.makePackage([
            "Sources/Lib/Row.swift": Nested.row,
            "Demo/Package.swift": Nested.demoManifest,
            "Demo/Sources/Demo/main.swift": Nested.mintingRow
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try Nested.verdict("make", scanning: root) == .refuted)
        #expect(try Nested.verdict("make", scanning: root.appendingPathComponent("Sources/Lib")) == .pure)
    }

    /// Two scans under one root can now build different tables, so a value built for one must not
    /// judge the other — the root alone no longer says it covers.
    @Test("a purity built for one scan does not cover a scan that takes another package")
    func purityCoversOnlyItsOwnUniverse() throws {
        let root = try Wiring.makePackage([
            "Examples/Demo/Package.swift": Nested.demoManifest,
            "Examples/Demo/Sources/Demo/Item.swift": Self.item,
            "Examples/Demo/Sources/Demo/Callers.swift": Self.callers,
            "Sources/App/Plain.swift": "public func appPlain(_ n: Int) -> Int { n * 2 }"
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let app = PackagePurity.forScan(of: root.appendingPathComponent("Sources/App"))
        let examples = root.appendingPathComponent("Examples")
        #expect(!app.covers(examples))
        #expect(throws: FunctionScanner.ScanError.self) {
            try FunctionScanner.scanCorpus(directory: examples, purity: app)
        }
        #expect(PackagePurity.forScan(of: examples).covers(examples))
        #expect(app.covers(root.appendingPathComponent("Sources")), "the same universe from a sibling is not foreign")
    }
}
