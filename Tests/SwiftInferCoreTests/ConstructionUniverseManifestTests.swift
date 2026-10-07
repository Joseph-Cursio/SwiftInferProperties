import Foundation
import SwiftEffectInference
import Testing

@testable import SwiftInferCore

private typealias Wiring = ConstructionPurityWiringTests
private typealias Nested = ConstructionUniverseNestedPackageTests

/// **What a manifest is** — the shared spec's amendment F. A directory holds one iff it contains a
/// regular file (symlinks followed) named `Package.swift` whose first line is a tools-version
/// comment; one that exists and cannot be read is a manifest AND doubt. Each on-disk case is the
/// joint review's reproduction, scanned end to end.
@Suite("Construction universe — what a manifest is")
struct ConstructionUniverseManifestTests {

    @Test("the first line decides", arguments: [
        ("// swift-tools-version:5.9\nimport PackageDescription", true),
        ("// swift-tools-version: 6.0", true),
        ("  \t//   swift-tools-version:5.9", true),
        ("\u{FEFF}// swift-tools-version:5.9", true),
        ("// swift-tools-version:5.9\r\nimport PackageDescription", true),
        ("//swift-tools-version:5.7", true),
        ("import PackageDescription\n// swift-tools-version:5.9", false),
        ("\n// swift-tools-version:5.9", false),
        ("struct Package: Equatable { let name: String }", false),
        ("/* swift-tools-version:5.9 */", false),
        ("// tools-version:5.9", false),
        ("", false)
    ])
    func firstLineDecides(text: String, isManifest: Bool) {
        #expect(ConstructionUniverse.isManifest(text) == isManifest)
    }

    /// A regular file that is not UTF-8 text cannot say what it is: a manifest, and doubt.
    @Test("a Package.swift that is not UTF-8 text is a manifest that cannot be read")
    func nonUTF8ManifestIsUnreadable() throws {
        let directory = try Wiring.makePackage([:], manifest: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Package.swift")
        try (Data("// swift-tools-version:5.9\n".utf8) + Data([0xFF, 0xFE, 0x00])).write(to: file)
        #expect(ConstructionUniverse.manifest(inDirectory: directory) == .unreadable)
        #expect(ConstructionUniverse.holdsManifest(directory))
    }

    static func countOf() -> String { "func countOf(_ title: String) -> Int { Item(title: title).title.count }" }

    /// The review's `spl#1`: a `struct Package` in `Sources/App/Models/Package.swift` is a source
    /// file SwiftPM compiles into `App`. Read as a manifest it made `Models/` a nested package the
    /// root never names, and the bound dropped `Models/Item.swift` with it — `countOf` read pure.
    @Test("a source file named Package.swift makes no package boundary")
    func sourceFileNamedPackageIsNotAManifest() throws {
        let root = try Wiring.makePackage([
            "Sources/App/Models/Package.swift": "struct Package: Equatable { let name: String }",
            "Sources/App/Models/Item.swift": Wiring.item,
            "Sources/App/Count.swift": Self.countOf()
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Sources/App")
        #expect(ConstructionUniverse.files(forScanOf: app).map(\.relativePath) == [
            "Sources/App/Count.swift", "Sources/App/Models/Item.swift"
        ])
        #expect(try Nested.verdict("countOf", scanning: app) == .refuted)
        // Nor is it a root: a scan of `Models/` belongs to the package above it.
        let models = app.appendingPathComponent("Models")
        #expect(ConstructionUniverse.root(forScanOf: models).path == ConstructionUniverse.resolved(root).path)
    }

    /// The review's `agreement#4`, `f18`: a dangling `Ghost/Package.swift` is not a manifest, so
    /// `Ghost/` is the root's own directory and the root's dependency on it reads nothing. Read as
    /// an unreadable manifest it was doubt, which let an unrelated `Demo/` refute the root's `Row`.
    @Test("a dangling Package.swift link is not a manifest, and not doubt")
    func danglingManifestLinkIsNotAManifest() throws {
        let root = try Wiring.makePackage([
            "Package.swift": Nested.manifest(dependingOn: "Ghost"),
            "Ghost/Sources/Ghost/Ghost.swift": "struct Ghost { let id = UUID() }",
            "Sources/Lib/Row.swift": Nested.row,
            "Demo/Package.swift": Nested.demoManifest,
            "Demo/Sources/Demo/main.swift": Nested.mintingRow
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        try ConstructionUniverseSymlinkTests.link("Ghost/Package.swift", in: root, to: "/nonexistent/Package.swift")
        let lib = root.appendingPathComponent("Sources/Lib")
        #expect(ConstructionUniverse.files(forScanOf: lib).map(\.relativePath) == [
            "Ghost/Sources/Ghost/Ghost.swift", "Sources/Lib/Row.swift"
        ])
        #expect(try Nested.verdict("make", scanning: lib) == .pure, "the dangling link was read as doubt")
    }

    /// The review's `g31`: a DIRECTORY named `Package.swift` is not a manifest either — so `Odd/`
    /// is neither a nested package nor a root.
    @Test("a directory named Package.swift is not a manifest")
    func directoryNamedPackageIsNotAManifest() throws {
        let root = try Wiring.makePackage([
            "Odd/Package.swift/Readme.md": "not a manifest",
            "Odd/Sources/Odd/Item.swift": Wiring.item,
            "Sources/Lib/Make.swift": Wiring.make
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let odd = root.appendingPathComponent("Odd/Sources/Odd")
        #expect(ConstructionUniverse.root(forScanOf: odd).path == ConstructionUniverse.resolved(root).path)
        let lib = root.appendingPathComponent("Sources/Lib")
        #expect(ConstructionUniverse.files(forScanOf: lib).map(\.relativePath) == [
            "Odd/Sources/Odd/Item.swift", "Sources/Lib/Make.swift"
        ])
        #expect(try Nested.verdict("make", scanning: lib) == .refuted)
    }

    /// An existing manifest that cannot be read is a manifest AND doubt: nothing says what it
    /// depends on, so once the closure reaches it every nested package is in. One it never
    /// reaches still bounds its own files out.
    @Test("an unreadable manifest is a package, and doubt where the closure reaches it")
    func unreadableManifestIsDoubt() throws {
        let files = [
            "Packages/Locked/Package.swift": Nested.demoManifest,
            "Packages/Locked/Sources/Locked/Locked.swift": "public struct Locked {}",
            "Sources/Lib/Row.swift": Nested.row,
            "Demo/Package.swift": Nested.demoManifest,
            "Demo/Sources/Demo/main.swift": Nested.mintingRow
        ]
        for (dependency, demoIsIn) in [("Packages/Locked", true), ("Packages/Elsewhere", false)] {
            var package = files
            package["Package.swift"] = Nested.manifest(dependingOn: dependency)
            let root = try Wiring.makePackage(package)
            defer { try? FileManager.default.removeItem(at: root) }
            let locked = root.appendingPathComponent("Packages/Locked/Package.swift")
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
            guard FileManager.default.contents(atPath: locked.path) == nil else {
                Issue.record("a mode-000 file was readable — running as root? The case cannot be built")
                return
            }
            let lib = root.appendingPathComponent("Sources/Lib")
            let paths = ConstructionUniverse.files(forScanOf: lib).map(\.relativePath)
            #expect(paths.contains("Demo/Sources/Demo/main.swift") == demoIsIn, "\(dependency): \(paths)")
            let lockedIsIn = paths.contains("Packages/Locked/Sources/Locked/Locked.swift")
            #expect(lockedIsIn == demoIsIn, "\(dependency): \(paths)")
            #expect(try Nested.verdict("make", scanning: lib) == (demoIsIn ? .refuted : .pure), "\(dependency)")
        }
    }

    // MARK: - G: an Xcode project beside the manifest

    /// The review's `spl#2`: a CLI-tool `Package.swift` beside `App.xcodeproj`, whose app target
    /// links `LocalPackages/Feature` — a package the manifest never names. Bounded by the manifest,
    /// `Feature`'s UUID-minting `Item` left the universe and `countOf` read pure.
    @Test("an Xcode project or workspace beside the root manifest takes every nested package", arguments: [
        ("App.xcodeproj/project.pbxproj", true),
        ("App.xcworkspace/contents.xcworkspacedata", true),
        ("Apps/iOS/App.xcodeproj/project.pbxproj", false),
        // Any entry so named, as SwiftProjectLint reads it — a dot-prefixed one too.
        (".Hidden.xcodeproj/project.pbxproj", true)
    ])
    func xcodeProjectBesideTheManifestTakesEveryNestedPackage(project: String, takesEvery: Bool) throws {
        let root = try Wiring.makePackage([
            project: "// !$*UTF8*$!",
            "LocalPackages/Feature/Package.swift": Nested.demoManifest,
            "LocalPackages/Feature/Sources/Feature/Item.swift": Wiring.item,
            "App/Count.swift": Self.countOf()
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("App")
        let paths = ConstructionUniverse.files(forScanOf: app).map(\.relativePath)
        let featureIsIn = paths.contains("LocalPackages/Feature/Sources/Feature/Item.swift")
        #expect(featureIsIn == takesEvery, "\(project): \(paths)")
        #expect(try Nested.verdict("countOf", scanning: app) == (takesEvery ? .refuted : .pure), "\(project)")
    }
}
