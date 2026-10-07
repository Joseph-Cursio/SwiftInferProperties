import Foundation
import SwiftEffectInference
import Testing

@testable import SwiftInferCore

private typealias Wiring = ConstructionPurityWiringTests
private typealias Nested = ConstructionUniverseNestedPackageTests

/// **Where a `.package(path:)` leads** — the shared spec's amendment H: the literal's value is
/// resolved against its manifest's directory, standardised, and then resolved through symlinks, and
/// compared with the nested packages by RESOLVED path. Lexical comparison missed a compiled package
/// whenever the literal and the root were spelled differently — the under-refuting direction.
@Suite("Construction universe — where a dependency path leads")
struct ConstructionUniverseDependencyPathTests {

    static let token = "import Foundation\npublic struct Token { public let id = UUID() }"
    static let mint = "public func mint() -> Token { Token() }"

    /// Whether the volume holding the temporary directory folds letter case, as APFS does by default.
    static var temporaryVolumeIgnoresCase: Bool {
        let values = try? URL(fileURLWithPath: NSTemporaryDirectory())
            .resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        return values?.volumeSupportsCaseSensitiveNames == false
    }

    /// A root whose manifest depends on the literal `spell(root)` returns, beside a `Packages/Q`
    /// whose `Token` mints a `UUID`, and a `Sources/Lib` whose `mint()` constructs one.
    static func package(
        dependingOn spell: (URL) -> String,
        prepare: (URL) throws -> Void = { _ in /* nothing to add */ }
    ) throws -> URL {
        let root = try Wiring.makePackage([
            "Packages/Q/Package.swift": Nested.demoManifest,
            "Packages/Q/Sources/Q/Token.swift": Self.token,
            "Sources/Lib/Mint.swift": Self.mint
        ])
        try Nested.manifest(dependingOn: spell(root)).write(
            to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8
        )
        try prepare(root)
        return root
    }

    /// Whether a scan of `Sources/Lib` takes `Q`, checked against its verdict.
    static func takesQ(_ root: URL) throws -> Bool {
        let lib = root.appendingPathComponent("Sources/Lib")
        let paths = ConstructionUniverse.files(forScanOf: lib).map(\.relativePath)
        let inUniverse = paths.contains("Packages/Q/Sources/Q/Token.swift")
        let refuted = try Nested.verdict("mint", scanning: lib) == .refuted
        #expect(inUniverse == refuted, "the universe and the verdict disagree about Q")
        return inUniverse
    }

    /// The review's `sip#3` / `agreement#2`: `$PWD` and `getcwd` spell a temporary root
    /// `/private/var/…`, and Foundation's resolution spells it `/var/…` — so the absolute literal a
    /// user pastes from either named a directory "outside the root", and `mint()` read pure.
    @Test("an absolute path is compared resolved, whichever way /var or /tmp is spelled")
    func absolutePathIsComparedResolved() throws {
        let spellings: [(String, (URL) -> String)] = [
            ("as created", { $0.path + "/Packages/Q" }),
            ("through /private", { root in
                let path = root.path
                return (path.hasPrefix("/private/") ? path : "/private" + path) + "/Packages/Q"
            }),
            ("resolved", { $0.resolvingSymlinksInPath().path + "/Packages/Q" })
        ]
        for (label, spell) in spellings {
            let root = try Self.package(dependingOn: spell)
            defer { try? FileManager.default.removeItem(at: root) }
            #expect(try Self.takesQ(root), "\(label): the compiled package was ignored")
        }
    }

    /// A dependency through a symlinked directory inside the root names the directory the link
    /// points to — which the walk found as a nested package under its real name.
    @Test("a dependency through a symlinked directory names the package the link points to")
    func dependencyThroughASymlinkIsResolved() throws {
        let root = try Self.package(dependingOn: { _ in "Links/Q" }, prepare: { root in
            try FileManager.default.createSymbolicLink(
                atPath: root.appendingPathComponent("Links").path, withDestinationPath: "Packages"
            )
        })
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try Self.takesQ(root))
    }

    /// A link that leaves the root leaves the universe with it: the resolved path decides.
    @Test("a dependency whose link leads outside the root is ignored")
    func dependencyLinkedOutsideTheRootIsIgnored() throws {
        let outside = try Wiring.makePackage([
            "Q/Package.swift": Nested.demoManifest,
            "Q/Sources/Q/Token.swift": Self.token
        ], manifest: false)
        defer { try? FileManager.default.removeItem(at: outside) }
        let root = try Self.package(dependingOn: { _ in "External/Q" }, prepare: { root in
            try FileManager.default.createSymbolicLink(
                atPath: root.appendingPathComponent("External").path, withDestinationPath: outside.path
            )
        })
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try !Self.takesQ(root))
        let lib = root.appendingPathComponent("Sources/Lib")
        #expect(ConstructionUniverse.files(forScanOf: lib).map(\.relativePath) == ["Sources/Lib/Mint.swift"])
    }

    /// On a volume that folds case, `packages/q` is the directory `Packages/Q`, and the compiler
    /// opens it. Comparing the literal's spelling missed it.
    @Test(
        "a dependency spelled in another letter case names the package on disk",
        .enabled(if: Self.temporaryVolumeIgnoresCase)
    )
    func dependencyInAnotherCaseIsResolved() throws {
        let root = try Self.package { _ in "packages/q" }
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(try Self.takesQ(root))
    }

    // MARK: - I: the closure reads manifests by path

    /// The review's `agreement#0` / `tests#0` / `sip#4`: the root depends on a package the walk
    /// never enters — under `Tests/`, a `*Tests` folder, a hidden or a pruned directory — and that
    /// package depends on one the walk does find. The walk pruned the middle package, so the
    /// closure stopped at it: `Shared`'s `Token` left the universe, `mint()` read pure, and
    /// SwiftProjectLint, whose walk enters `Tests/`, built a different table from the same root.
    @Test("the closure passes through a package the walk never enters", arguments: [
        "Tests/Support", "SnapshotTests", ".support", "Pods/Support"
    ])
    func closurePassesThroughAnUnwalkedPackage(middle: String) throws {
        let climb = String(repeating: "../", count: middle.split(separator: "/").count)
        let root = try Wiring.makePackage([
            "Package.swift": Nested.manifest(dependingOn: middle),
            "\(middle)/Package.swift": Nested.manifest(dependingOn: climb + "Shared"),
            "\(middle)/Sources/Support/Support.swift": "public struct Support { public let id = UUID() }",
            "Shared/Package.swift": Nested.demoManifest,
            "Shared/Sources/Shared/Token.swift": Self.token,
            "Sources/Lib/Mint.swift": Self.mint
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let universe = ConstructionUniverse.universe(forScanOf: root.appendingPathComponent("Sources/Lib"))
        // The middle package's own files stay out: the predicate still decides what is production.
        #expect(universe.members.map(\.relativePath) == ["Shared/Sources/Shared/Token.swift", "Sources/Lib/Mint.swift"])
        #expect(try Nested.verdict("mint", scanning: root.appendingPathComponent("Sources/Lib")) == .refuted)
        // Its manifest decides the bound, so it is watched like any other.
        let watched = universe.manifests.map { $0.path.dropFirst(universe.root.path.count + 1) }
        #expect(watched.contains("\(middle)/Package.swift"[...]), "\(watched)")
    }

    /// The review's `f10b`: doubt in a manifest the walk never enters is still doubt — every
    /// nested package is in, and an unrelated `Demo/`'s `Row` refutes the root's.
    @Test("doubt in a package the walk never enters includes every nested package")
    func doubtInAnUnwalkedPackageIncludesEveryNestedPackage() throws {
        let root = try Wiring.makePackage([
            "Package.swift": Nested.manifest(dependingOn: "IntegrationTests"),
            "IntegrationTests/Package.swift": """
            // swift-tools-version:5.9
            let shared = "../Shared"
            let package = Package(name: "IntegrationTests", dependencies: [.package(path: shared)])
            """,
            "Sources/Lib/Row.swift": Nested.row,
            "Demo/Package.swift": Nested.demoManifest,
            "Demo/Sources/Demo/main.swift": Nested.mintingRow
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let lib = root.appendingPathComponent("Sources/Lib")
        #expect(ConstructionUniverse.files(forScanOf: lib).map(\.relativePath).contains("Demo/Sources/Demo/main.swift"))
        #expect(try Nested.verdict("make", scanning: lib) == .refuted)
    }
}
