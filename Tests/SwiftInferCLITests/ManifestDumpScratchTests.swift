import Foundation
@testable import SwiftInferCLI
import Testing

/// Reading a manifest must not write to the package being read.
///
/// `swift package dump-package` drops `.build/CACHEDIR.TAG`, `.build/.lock` and
/// `.build/.buildSystem_debug` into whatever package it is pointed at. That is outside the
/// PRD §16 #1 writeout allowlist, and it is not a writeout at all — it is the cost of asking
/// SwiftPM a question. `HardGuaranteeAllowlistTests` catches it end to end in three arms;
/// this names the cause directly, so a future caller that builds its own `dump-package` argv
/// instead of going through `ManifestDumpCommand` fails here with the reason attached.
@Suite("Manifest reads leave the package alone")
struct ManifestDumpScratchTests {

    @Test("dumping a manifest creates no .build/ in the package")
    func manifestDumpLeavesNoBuildDirectory() throws {
        let root = try PackageFixture.make(
            name: "Demo",
            sourcePath: "Sources/Demo",
            testTargets: [("DemoTests", "Tests/DemoTests")]
        )
        defer { PackageFixture.remove(root) }

        // Any consumer of the shared argv will do; this one is the #414 path.
        _ = TestTargetScope.testTargetLocations(exercising: "Demo", packageRoot: root)

        let buildDirectory = root.appendingPathComponent(".build")
        #expect(
            !FileManager.default.fileExists(atPath: buildDirectory.path),
            "reading the manifest created \(buildDirectory.path) in the user's package"
        )
    }

    @Test("the argv sends SwiftPM's scratch somewhere other than the package")
    func argvCarriesAScratchPathOutsideThePackage() {
        let root = URL(fileURLWithPath: "/tmp/some-package")
        let argv = ManifestDumpCommand.argv(packageRoot: root)

        #expect(argv.contains("--scratch-path"))
        guard let index = argv.firstIndex(of: "--scratch-path"), index + 1 < argv.count else {
            Issue.record("argv carries no scratch path: \(argv)")
            return
        }
        #expect(!argv[index + 1].hasPrefix(root.path))
    }
}
