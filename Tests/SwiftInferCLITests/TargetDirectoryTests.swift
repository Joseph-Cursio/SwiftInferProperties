import ArgumentParser
import Foundation
@testable import SwiftInferCLI
import Testing

/// A target that is not there must be an error, not a zero.
///
/// Every command resolved `--target` inline — `URL(fileURLWithPath: "Sources").appendingPathComponent(target)`
/// — with nothing checking that anything existed at the other end. The scanner returns `[]` for a
/// directory it cannot enumerate, so a target that did not exist scanned nothing, found nothing,
/// printed `0 suggestions.` and **exited 0**.
///
/// A confident, successful-looking zero is the worst answer a tool can give, because the reader
/// believes it. And this was not an exotic case: `--target` resolves under `Sources/`, so it is how
/// *every user of an Xcode project* met the tool. An app has no `Sources/` directory, so the first
/// thing it told them was that their code had no properties — having never opened a file.
@Suite("--target resolution fails loudly")
struct TargetDirectoryTests {

    /// A fresh temporary package root containing `Sources/<target>/` for each name.
    ///
    /// Passed to `resolve(_:relativeTo:)` explicitly rather than installed as the process working
    /// directory. `chdir` is process-global and Swift Testing runs suites in parallel, so two tests
    /// that each set it resolve against each other's package — which is exactly what happened when
    /// this suite was first written, and is a small lesson in why the resolver takes its root as a
    /// parameter rather than reading it out of global state.
    private func makePackage(targets: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-infer-target-\(UUID().uuidString)")
        let sources = root.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        for target in targets {
            try FileManager.default.createDirectory(
                at: sources.appendingPathComponent(target),
                withIntermediateDirectories: true
            )
        }
        return root
    }

    /// A directory with no `Sources/` at all — an Xcode project, from the tool's point of view.
    private func makeBareDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-infer-bare-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("an existing target resolves")
    func existingTargetResolves() throws {
        let root = try makePackage(targets: ["MyLib"])
        defer { try? FileManager.default.removeItem(at: root) }

        let resolved = try TargetDirectory.resolve("MyLib", relativeTo: root)
        #expect(resolved.lastPathComponent == "MyLib")
    }

    @Test("a target that does not exist throws, naming the path it looked for")
    func missingTargetThrows() throws {
        let root = try makePackage(targets: ["MyLib"])
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            _ = try TargetDirectory.resolve("Nonsense", relativeTo: root)
            Issue.record("expected a ValidationError for a target that does not exist")
        } catch {
            let message = "\(error)"
            #expect(message.contains("Nonsense"))
            #expect(message.contains("Sources/Nonsense"))
        }
    }

    @Test("the error lists the targets that do exist")
    func missingTargetListsAlternatives() throws {
        // A reader who mistypes a target, or is standing in the wrong directory, usually sees the
        // answer the moment they see the list.
        let root = try makePackage(targets: ["Alpha", "Beta"])
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            _ = try TargetDirectory.resolve("Alfa", relativeTo: root)
            Issue.record("expected a ValidationError")
        } catch {
            let message = "\(error)"
            #expect(message.contains("Alpha"))
            #expect(message.contains("Beta"))
        }
    }

    @Test("no Sources/ at all says so, and names the Xcode case")
    func missingSourcesDirectoryThrows() throws {
        // The road-test scenario: an Xcode app has no `Sources/`, and used to be told — with a clean
        // exit 0 — that its code had no properties.
        let root = try makeBareDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        do {
            _ = try TargetDirectory.resolve("MyApp", relativeTo: root)
            Issue.record("expected a ValidationError when there is no Sources/ directory")
        } catch {
            let message = "\(error)"
            #expect(message.contains("no `Sources/` directory"))
            #expect(message.contains("Xcode project"))
        }
    }

    @Test("a target directory holding no Swift files warns rather than reporting a bare zero")
    func emptyTargetWarns() throws {
        let root = try makePackage(targets: ["Hollow"])
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = try TargetDirectory.resolve("Hollow", relativeTo: root)
        let diagnostics = DPRecordingDiagnosticOutput()
        TargetDirectory.warnIfEmpty(directory, to: diagnostics)

        #expect(diagnostics.joined.contains("warning"))
        #expect(diagnostics.joined.contains("scanned 0 Swift files"))
    }

    @Test("a populated target says nothing, keeping stderr byte-stable")
    func populatedTargetIsSilent() throws {
        let root = try makePackage(targets: ["Filled"])
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = try TargetDirectory.resolve("Filled", relativeTo: root)
        try "func add(_ a: Int, _ b: Int) -> Int { a + b }".write(
            to: directory.appendingPathComponent("Math.swift"),
            atomically: true,
            encoding: .utf8
        )

        let diagnostics = DPRecordingDiagnosticOutput()
        TargetDirectory.warnIfEmpty(directory, to: diagnostics)

        // A `scanned N file(s) in <path>` line on every run was the obvious thing to add, and it is
        // wrong: stderr is a byte-stable contract (PRD §16 #6) and an absolute path differs from
        // machine to machine, so identical inputs would produce different output. The silence is
        // safe because the two ways a zero could lie are both closed — a missing target errors, an
        // empty one warns — so what is left is a zero worth believing.
        #expect(diagnostics.lines.isEmpty)
    }
}
