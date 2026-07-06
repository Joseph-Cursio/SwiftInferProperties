import ArgumentParser
import Foundation
import SwiftInferCore

extension SwiftInferCommand {

    /// `swift-infer verify-value-semantics` — discover value-semantics
    /// candidates under `Sources/<target>/` and verify each against the kit's
    /// copy-mutate-compare law, reporting **confirmed leaks with a minimal
    /// reproduction**. Slice 5a (self-contained packaging); see
    /// `docs/valuesemantic-build-plan.md` §11.
    public struct VerifyValueSemantics: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "verify-value-semantics",
            abstract: "Verify value-semantics candidates under Sources/<target>/ "
                + "and report confirmed leaks (copy-mutate-compare). Opt-in; "
                + "spawns real builds, so it is slower than static discovery."
        )

        @Option(
            name: .long,
            help: """
            Name of the SwiftPM target to verify. Resolved to Sources/<target>/ \
            relative to the working directory — mirrors `swift-infer discover --target`.
            """
        )
        public var target: String

        @Flag(
            name: .long,
            help: """
            Exit non-zero when any leak is confirmed (CI gate). Off by default \
            — the tool's advisory, human-reviewed posture.
            """
        )
        public var failOnLeak: Bool = false

        public init() { /* no-op */ }

        public func run() async throws {
            let directory = URL(fileURLWithPath: "Sources").appendingPathComponent(target)
            let workParent = FileManager.default.temporaryDirectory
                .appendingPathComponent("vs-verify-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workParent, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: workParent) }

            let results = try ValueSemanticVerifier.verify(
                targetDirectory: directory,
                moduleName: target,
                workParent: workParent
            )
            print(ValueSemanticVerifyReport.render(results: results, moduleName: target), terminator: "")

            if failOnLeak, ValueSemanticVerifyReport.leaksFound(in: results) {
                throw ExitCode.failure
            }
        }
    }
}
