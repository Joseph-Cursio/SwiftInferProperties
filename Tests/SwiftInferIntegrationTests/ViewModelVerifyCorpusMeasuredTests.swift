import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// PROTOTYPE — end-to-end measured proof of ViewModel idempotence
/// verification. Recognises the `viewmodel-verify-corpus` view models,
/// applies the constructibility gate, emits an idempotence verifier per
/// no-arg candidate action, co-compiles it with the corpus in a minimal
/// (dependency-free) SwiftPM package, and runs it:
///
///   - `SelectionModel.selectAll` / `.reset` (idempotent) → bothPass
///   - `SelectionModel.selectNext` (advances the cursor — the deliberate
///     false positive matching the `select*` vocabulary) → defaultFails
///   - `ConfiguredModel` (a required `endpoint` dependency) → gated by
///     constructibility; verify skips it.
///
/// Spawns real `swift build`s; tagged `.subprocess`.
@Suite("ViewModel verify corpus — measured idempotence (prototype)", .tags(.subprocess))
struct ViewModelVerifyCorpusMeasuredTests {

    @Test("idempotent actions bothPass, the advancing action defaultFails, dep-VM gated")
    func measuredViewModelIdempotence() throws {
        let candidates = try ViewModelDiscoverer.discover(directory: Self.corpusDirectory)
        let selection = try #require(candidates.first { $0.typeName == "SelectionModel" })
        let configured = try #require(candidates.first { $0.typeName == "ConfiguredModel" })

        // The dependency-requiring view model is gated out of verify.
        #expect(configured.constructibility == .requiresArguments(["endpoint"]))
        #expect(selection.isZeroArgConstructible)

        // The idempotence candidate actions — no-arg + single-arg.
        let idempotenceSignatures = Set(
            ViewModelInteractionAnalyzer.analyze(selection)
                .filter { $0.family == .idempotence }
                .compactMap(\.subjects.first)
        )
        let idempotenceActions = selection.actions
            .filter { idempotenceSignatures.contains($0.signature) }
            .sorted { $0.name < $1.name }
        #expect(idempotenceActions.map(\.name)
            == ["reset", "selectAll", "selectNext", "setActive", "setStep"])

        let workdir = try Self.makeWorkdir(corpus: Self.corpusDirectory)
        defer { try? FileManager.default.removeItem(at: workdir) }
        // `main.swift` (not `Verifier.swift`): the stub uses top-level
        // statements, which are only allowed in `main.swift` when the
        // target has multiple files (the co-compiled corpus). The corpus
        // declares no `@main`, so there's no conflict.
        let verifierFile = workdir
            .appendingPathComponent("Sources/SwiftInferVerifier/main.swift")
        let fieldNames = selection.stateFields.map(\.name)

        var outcomes: [String: VerifyOutcome] = [:]
        for action in idempotenceActions {
            guard let inputs = Self.makeInputs(action: action, stateFields: fieldNames) else {
                Issue.record("expected \(action.name) to be verifiable (no-arg or generatable single-arg)")
                continue
            }
            let stub = ViewModelIdempotenceStubEmitter.emit(inputs)
            try stub.write(to: verifierFile, atomically: true, encoding: .utf8)
            let build = try VerifierSubprocess.runSwiftBuild(workdir: workdir)
            guard build.exitCode == 0 else {
                Issue.record("build failed for \(action.name): \(build.stderr)")
                continue
            }
            let run = try VerifierSubprocess.runVerifierBinary(workdir: workdir)
            outcomes[action.name] = VerifyResultParser.parse(run)
        }

        // No-arg + single-arg idempotent → bothPass.
        expectBothPass(outcomes["selectAll"], "selectAll")
        expectBothPass(outcomes["reset"], "reset")
        expectBothPass(outcomes["setActive"], "setActive")    // x-curried over Bool
        // Advancing actions → defaultFails (execution disproves the candidate).
        expectDefaultFails(outcomes["selectNext"], "selectNext")
        expectDefaultFails(outcomes["setStep"], "setStep")    // x-curried fails at n=1
    }

    /// Build verifier inputs for a no-arg or single-arg-generatable action;
    /// `nil` (gated) for multi-arg or non-generatable-payload actions.
    static func makeInputs(
        action: ViewModelAction,
        stateFields: [String]
    ) -> ViewModelIdempotenceStubEmitter.Inputs? {
        switch action.parameterTypes.count {
        case 0:
            return .init(typeName: "SelectionModel", actionName: action.name, stateFieldNames: stateFields)

        case 1:
            guard let values = ViewModelArgumentGenerator
                .candidateValuesExpression(for: action.parameterTypes[0]) else {
                return nil
            }
            return .init(
                typeName: "SelectionModel",
                actionName: action.name,
                stateFieldNames: stateFields,
                argument: .init(
                    typeText: action.parameterTypes[0],
                    label: action.firstParameterLabel,
                    valuesExpression: values
                )
            )

        default:
            return nil
        }
    }

    private func expectDefaultFails(_ outcome: VerifyOutcome?, _ label: String) {
        if case .defaultFails = outcome {
            return
        }
        Issue.record("\(label) expected defaultFails; got \(String(describing: outcome))")
    }

    private func expectBothPass(_ outcome: VerifyOutcome?, _ label: String) {
        if case .bothPass = outcome {
            return
        }
        Issue.record("\(label) expected bothPass; got \(String(describing: outcome))")
    }

    // MARK: - Fixtures + workdir

    static let corpusDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("viewmodel-verify-corpus")
    }()

    /// Stage a minimal, dependency-free SwiftPM package with the corpus
    /// co-compiled into the `SwiftInferVerifier` executable target.
    static func makeWorkdir(corpus: URL) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-verify-\(UUID().uuidString)")
        let sources = root.appendingPathComponent("Sources/SwiftInferVerifier")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let packageManifest = """
        // swift-tools-version: 6.1
        import PackageDescription
        let package = Package(
            name: "SwiftInferVerifier",
            platforms: [.macOS(.v14)],
            targets: [.executableTarget(name: "SwiftInferVerifier")]
        )
        """
        try packageManifest.write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        // Inline every corpus .swift file alongside the verifier stub.
        let corpusFiles = try FileManager.default
            .contentsOfDirectory(at: corpus, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        for file in corpusFiles {
            try FileManager.default.copyItem(
                at: file,
                to: sources.appendingPathComponent(file.lastPathComponent)
            )
        }
        return root
    }
}
