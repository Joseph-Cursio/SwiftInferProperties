import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// A seed naming an access-restricted function is a request, not a mistake.
///
/// The scanner sets `private` / `fileprivate` / SPI / nested-local functions aside, and it is
/// right to: an external verifier compiles its test in another module, so it genuinely cannot call
/// them. Surfacing them unsolicited would be noise, and the access rules were calibrated for
/// exactly that — against swift-numerics, swift-collections, swift-algorithms.
///
/// The calibration was measured on **libraries**, and it inverts on an **app**. A library's
/// interesting surface is its public API and `private` really is an implementation detail. An app
/// has no public API at all: its pure logic lives almost entirely in `private` helpers inside views
/// and view models — `private func isValidFolderName`, `private func getFileIcon` — which are its
/// *best* property candidates and precisely what this drops. The precision lever tuned on libraries
/// is the thing that hides the properties in an app.
///
/// So a seed rescues them. The producer has already looked at the function and asked for it, and
/// silently overruling an explicit request is not precision — it is a confident zero, the same
/// defect as an empty manifest focusing to nothing. The law is surfaced with the access caveat
/// leading, naming the one refactor that unlocks it, rather than leaving the reader to find out at
/// verify time that their best candidate was never considered.
@Suite("Discover pipeline — a seed rescues an access-restricted function")
struct SeededPrivateFunctionTests {

    private static let privateHelper = """
    struct FolderNamer {
        private func isValidFolderName(_ name: String) -> Bool {
            !name.isEmpty
        }
    }
    """

    @Test("a private function is not surfaced without a seed")
    func privateFunctionStaysHiddenWhenUnseeded() throws {
        let directory = try writeDPFixture(name: "PrivateUnseeded", contents: Self.privateHelper)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(directory: directory, includePossible: true, output: recording)

        // Unseeded discovery is unchanged: the precision the access rules bought is intact.
        #expect(recording.text.contains("isValidFolderName") == false)
    }

    @Test("a seeded private function earns its law")
    func seededPrivateFunctionIsRescued() throws {
        let directory = try writeDPFixture(name: "PrivateSeeded", contents: Self.privateHelper)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = SeedManifest(seeds: [
            .init(file: "Source.swift", line: 2, symbol: "isValidFolderName")
        ])
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: manifest,
            output: recording,
            diagnostics: diagnostics
        )

        #expect(recording.text.contains("Template: determinism"))
        #expect(recording.text.contains("isValidFolderName"))
    }

    @Test("the rescued law leads with the refactor that would let it run")
    func rescuedLawCarriesTheRemedy() throws {
        let directory = try writeDPFixture(name: "PrivateRemedy", contents: Self.privateHelper)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = SeedManifest(seeds: [
            .init(file: "Source.swift", line: 2, symbol: "isValidFolderName")
        ])
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: manifest,
            output: recording,
            diagnostics: diagnostics
        )

        // Stating the law without saying it cannot be run would be a different kind of lie.
        #expect(recording.text.contains("No test can run this law as written"))
        #expect(recording.text.contains("Widen it to `internal`"))
        #expect(diagnostics.joined.contains("not reachable from a test as written"))
    }

    @Test("an unseeded private function is still absent even when another is seeded")
    func rescueIsScopedToTheSeed() throws {
        let source = """
        struct Namer {
            private func seeded(_ name: String) -> Bool { !name.isEmpty }
            private func unseeded(_ name: String) -> Bool { name.isEmpty }
        }
        """
        let directory = try writeDPFixture(name: "PrivateScoped", contents: source)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = SeedManifest(seeds: [.init(file: "Source.swift", line: 2, symbol: "seeded")])
        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: manifest,
            output: recording,
            diagnostics: diagnostics
        )

        // The rescue is a response to a request, not a general amnesty.
        #expect(recording.text.contains("seeded(_:)"))
        #expect(recording.text.contains("unseeded") == false)
    }
}
