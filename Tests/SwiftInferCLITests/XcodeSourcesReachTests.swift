import ArgumentParser
import Foundation
@testable import SwiftInferCLI
import Testing

/// **`--sources` on the commands built for app code.**
///
/// `discover` gained the Xcode escape hatch and `TargetDirectory`'s own doc argued for it:
/// *"`--target` resolves under `Sources/`, so this is how every user of an Xcode project meets
/// the tool — an app has no `Sources/` directory, so the first thing they are told is that their
/// code has no properties, by a tool that never opened a file."*
///
/// That argument was applied to exactly one command — the **algebraic** surface, the one aimed
/// at libraries. The five that lacked it included every command built for **app** code, and the
/// interaction families are aimed squarely at SwiftUI MVVM, which is overwhelmingly Xcode
/// projects. So the one surface designed for apps was the one that could not open one.
///
/// Measured on `MacCloud_client_iOS` (2026-08-01): `discover-interaction --target` exited with an
/// argument error, and the same 22 files staged into a `Sources/<target>/` shim produced **4**
/// suggestions on an `@Observable` view model — 2 idempotence, 1 referential-integrity, 1
/// cardinality. The gate never rejected the code; the command could not reach it.
///
/// `verify-interaction` deliberately does NOT gain the flag — see `verifyInteractionExplainsWhy`.
@Suite("Xcode reach — --sources on the app-facing commands")
struct XcodeSourcesReachTests {

    /// A directory laid out like an Xcode project: `.swift` files, no `Sources/<target>/`.
    private func withXcodeShapedProject<T>(_ body: (URL) throws -> T) rethrows -> T {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xcode-reach-\(UUID().uuidString)")
        let viewModels = root.appendingPathComponent("ViewModels")
        try? FileManager.default.createDirectory(at: viewModels, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try? """
        import Observation

        @Observable
        final class InboxViewModel {
            var showingComposeSheet: Bool = false
            var showingSettingsSheet: Bool = false
            var errorMessage: String?

            func showError(_ message: String) { errorMessage = message }
            func dismissError() { errorMessage = nil }
        }
        """.write(
            to: viewModels.appendingPathComponent("InboxViewModel.swift"),
            atomically: true,
            encoding: .utf8
        )
        return try body(root)
    }

    // MARK: - The resolver

    @Test("--sources resolves a directory with no Sources/<target>/ layout")
    func sourcesResolvesXcodeShapedDirectory() throws {
        try withXcodeShapedProject { root in
            let resolved = try TargetDirectory.resolveScan(target: nil, sources: root.path)
            #expect(resolved.standardizedFileURL.path == root.standardizedFileURL.path)
        }
    }

    @Test("passing both, or neither, is a loud error rather than a silent default")
    func mutualExclusionIsEnforced() {
        #expect(throws: ValidationError.self) {
            try TargetDirectory.resolveScan(target: nil, sources: nil)
        }
        #expect(throws: ValidationError.self) {
            try TargetDirectory.resolveScan(target: "Foo", sources: "/tmp")
        }
    }

    /// The label is what multi-module tagging and `--reducer` pins key on. `--target` has a
    /// module name; `--sources` has only a directory, so it takes the last path component.
    @Test("a --sources root is labelled by its directory name")
    func sourcesRootTakesDirectoryName() throws {
        try withXcodeShapedProject { root in
            let roots = try TargetDirectory.resolveScanRoots(targets: [], sources: [root.path])
            #expect(roots.count == 1)
            #expect(roots.first?.label == root.standardizedFileURL.lastPathComponent)
        }
    }

    /// A workspace can hold a package AND an app; a survey should not have to choose.
    @Test("targets and sources mix, targets first so single-target runs are unchanged")
    func rootsMixInStableOrder() throws {
        try withXcodeShapedProject { root in
            let roots = try TargetDirectory.resolveScanRoots(
                targets: ["SwiftInferCore"], sources: [root.path]
            )
            #expect(roots.count == 2)
            #expect(roots.first?.label == "SwiftInferCore")
        }
    }

    @Test("neither targets nor sources is an error, not an empty survey")
    func emptyRootsRejected() {
        #expect(throws: ValidationError.self) {
            try TargetDirectory.resolveScanRoots(targets: [], sources: [])
        }
    }

    // MARK: - The families actually reached

    /// The regression this whole change exists for: an `@Observable` view model in an
    /// Xcode-shaped directory must produce interaction suggestions.
    @Test("interaction families reach an @Observable view model via --sources")
    func interactionFamiliesReachXcodeProject() throws {
        try withXcodeShapedProject { root in
            let suggestions = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
                roots: [TargetDirectory.ScanRoot(label: "App", directory: root)]
            )
            #expect(!suggestions.isEmpty, "an @Observable view model must be reachable")
        }
    }

    /// `--sources` must not change what `--target` did. The forwarding path builds the same
    /// `Sources/<target>/` URL the old inline code did.
    @Test("the target path still resolves to Sources/<target>/")
    func targetPathUnchanged() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let roots = try TargetDirectory.resolveScanRoots(
            targets: ["SwiftInferCore"], sources: [], relativeTo: root
        )
        #expect(
            roots.first?.directory.standardizedFileURL.path
                == root.appendingPathComponent("Sources/SwiftInferCore").standardizedFileURL.path
        )
    }

    // MARK: - The one that deliberately does NOT get the flag

    /// `verify-interaction` synthesizes a verifier that does `import <module>` and builds it
    /// against the package. An Xcode project exposes no importable SwiftPM module, so `--sources`
    /// would reach the sources and then fail at link time — later, and saying less. The error
    /// says so and names the reachable alternative instead.
    @Test("verify-interaction explains why it has no --sources, and what to use")
    func verifyInteractionExplainsWhy() {
        var command = SwiftInferCommand.VerifyInteraction()
        command.target = []
        do {
            try command.validate()
            Issue.record("expected a ValidationError")
        } catch {
            let message = "\(error)"
            #expect(message.contains("import <module>"))
            #expect(message.contains("discover-interaction --sources"))
        }
    }
}
