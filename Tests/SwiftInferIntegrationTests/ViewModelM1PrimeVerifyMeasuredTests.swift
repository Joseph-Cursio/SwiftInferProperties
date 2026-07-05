import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// PROTOTYPE — end-to-end measured proof of the **M1′ multi-step** ViewModel
/// interaction verify path (Observable Carrier milestone, Slice 3). Unlike the
/// single-pass `ViewModelRefintVerifyCorpusMeasuredTests`, this drives *random
/// action sequences* over a synthetic `Action` enum via the kit's
/// `ActionSequenceFactory`, in a fresh live probe per trial:
///
///   - `SafeCatalogModel` (guards membership) → `.ran(.bothPass)`
///   - `CatalogModel.toggle(Int)` (inserts an arbitrary id) → `.ran(.defaultFails)`
///
/// `toggle` carries an `Int` payload — a `RawType` — so M1′ generates it
/// (`Gen<Int>.int()`), reaching `toggle(0)` with `0 ∉ items`. Spawns real
/// `swift build`s against the kit; tagged `.subprocess`.
@Suite("ViewModel M1′ interaction verify — measured (prototype)", .tags(.subprocess))
struct ViewModelM1PrimeVerifyMeasuredTests {

    @Test("clean model → bothPass; refint-breaking model → defaultFails, multi-step")
    func measuredM1Prime() throws {
        let candidates = try ViewModelDiscoverer.discover(directory: Self.corpusDirectory)
        let safe = try #require(candidates.first { $0.typeName == "SafeCatalogModel" })
        let buggy = try #require(candidates.first { $0.typeName == "CatalogModel" })

        // All corpus models compiled INTO the verifier target (same-target
        // inlining — no user-module import).
        let sources = try CorpusPackager.readSwiftSources(in: Self.corpusDirectory)
        let runner = ViewModelVerifyInteractionPipeline.liveRunner()

        let workdir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-m1prime-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workdir) }

        func verify(_ candidate: ViewModelCandidate)
            throws -> ViewModelVerifyInteractionPipeline.StepResult {
            let resolved = try #require(
                ViewModelRefintResolver.resolve(candidate),
                "expected a verifiable refint pairing on \(candidate.typeName)"
            )
            return ViewModelVerifyInteractionPipeline.verify(
                candidate: candidate,
                predicate: resolved.predicate,
                sourceFiles: sources,
                workdir: workdir,
                runner: runner
            )
        }

        guard case .ran(.bothPass) = try verify(safe) else {
            Issue.record("SafeCatalogModel expected .ran(.bothPass)")
            return
        }
        guard case .ran(.defaultFails) = try verify(buggy) else {
            Issue.record("CatalogModel expected .ran(.defaultFails)")
            return
        }
    }

    static let corpusDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("viewmodel-refint-corpus")
    }()
}
