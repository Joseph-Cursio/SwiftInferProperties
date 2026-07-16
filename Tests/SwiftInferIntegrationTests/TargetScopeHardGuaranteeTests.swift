import ArgumentParser
import Foundation
import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// PRD §16 #5 hard guarantee — "SwiftInfer never operates
/// outside the configured target. `--target` is required for
/// `discover`; the tool refuses to scan files outside the named
/// target's source roots." The contract had no explicit release-gate
/// test before R1.1.g.
///
/// Two assertions, matching the two halves of the PRD line:
/// 1. `discover` refuses to scan with **no explicit scope**. Since `--sources` (C1) became an
///    alternative to `--target`, the requirement is no longer "parse fails without `--target`" —
///    both flags are optional at the type level, and exactly one must be given. The guarantee moved
///    from parse time to `resolveScanDirectory`, which is a **hard error** when neither is passed, so
///    the tool never scans without an explicitly configured scope.
/// 2. When `--target Foo` is set, files in sibling targets (`Bar/`)
///    or above the `Sources/` tree (`Helpers.swift` next to
///    `Package.swift`) are not scanned.
///
/// R1.1.g — closes the §16 #5 gap before the v0.1.0 cut.
@Suite("Discover — PRD §16 #5 target scope (R1.1.g)")
struct TargetScopeHardGuaranteeTests {

    @Test("discover refuses to scan with no explicit scope — neither --target nor --sources (PRD §16 #5)")
    func discoverRequiresAnExplicitScope() {
        // §16 #5 — "never operates outside the configured target." `--target` used to be required at
        // parse time; now that `--sources` is a peer way to name the scope, both are optional and the
        // requirement is enforced at resolve time: passing NEITHER throws, so a default-scope scan is
        // impossible. Passing exactly one is the only way through, which is what the other resolver
        // tests cover.
        do {
            _ = try SwiftInferCommand.Discover.resolveScanDirectory(target: nil, sources: nil)
            Issue.record("resolveScanDirectory succeeded with no scope — §16 #5 was bypassed")
        } catch {
            let message = "\(error)"
            #expect(
                message.contains("--target") && message.contains("--sources"),
                "The no-scope error did not name the two ways to configure a scope:\n\(message)"
            )
        }
    }

    @Test("discover scopes scan to the named target's source root only (PRD §16 #5)")
    func discoverDoesNotScanOutsideNamedTarget() throws {
        let packageRoot = try makePackageRoot()
        defer { try? FileManager.default.removeItem(at: packageRoot) }

        // Three locations a hypothetical leaky scan would hit:
        // (a) the named target Sources/Foo/ — should be scanned
        // (b) the sibling target Sources/Bar/ — must be skipped
        // (c) above Sources/ next to Package.swift — must be skipped
        let fooTarget = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("Foo")
        try writeContainerFile(at: fooTarget, fileNameStem: "FooContainer")

        let barTarget = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("Bar")
        try writeContainerFile(at: barTarget, fileNameStem: "BarContainer")

        let strayPath = packageRoot.appendingPathComponent("StrayHelpers.swift")
        try strayContainerSource()
            .write(to: strayPath, atomically: true, encoding: .utf8)

        // Drive discover through the same code path the CLI uses
        // after path resolution — `directory: Sources/Foo` is exactly
        // what `URL(fileURLWithPath: "Sources").appendingPathComponent("Foo")`
        // yields when `--target Foo` is parsed.
        let suggestions = try TemplateRegistry.discover(in: fooTarget)

        // Every suggestion's evidence must reference a file under
        // Sources/Foo/. The Bar/ and stray paths are out of scope.
        for suggestion in suggestions {
            for evidence in suggestion.evidence {
                let path = evidence.location.file
                #expect(
                    path.contains("/Sources/Foo/"),
                    "Suggestion evidence references a file outside the named --target Foo: \(path)"
                )
                #expect(
                    !path.contains("/Sources/Bar/"),
                    "Suggestion leaked from sibling target Bar: \(path)"
                )
                #expect(
                    !path.hasSuffix("/StrayHelpers.swift"),
                    "Suggestion leaked from above-Sources/ stray file: \(path)"
                )
            }
        }

        // Sanity: discover should produce at least one suggestion from
        // Foo/ (otherwise the absence-of-leakage above is vacuous).
        #expect(
            !suggestions.isEmpty,
            "Foo/ produced no suggestions — the §16 #5 leakage assertion is vacuous"
        )
    }

    // MARK: - Fixture

    private func makePackageRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftInferTargetScope-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 6.1\n".utf8).write(
            to: root.appendingPathComponent("Package.swift")
        )
        return root
    }

    private func writeContainerFile(at directory: URL, fileNameStem: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        struct \(fileNameStem) {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """.write(
            to: directory.appendingPathComponent("\(fileNameStem).swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func strayContainerSource() -> String {
        """
        struct StrayContainer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """
    }
}
