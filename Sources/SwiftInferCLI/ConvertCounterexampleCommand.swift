import ArgumentParser
import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// `swift-infer convert-counterexample` — TestLifter M8.1.
///
/// Closes the discovery loop (PRD §3.6 step 6 + §7.9 row M8). When a
/// property test accepted via `swift-infer discover --interactive`
/// fails, the user runs this subcommand with the failing trial's
/// counterexample as `--counterexample <swift-source>`, and the
/// subcommand emits a deterministic single-trial regression test
/// pinning that exact input alongside the original property test.
///
/// Output path: `<package-root>/Tests/Generated/SwiftInfer/<template>/
/// <callee>_regression_<hash>.swift` (per OD #1 / #2 — `_regression_`
/// infix + 8-hex-char SHA256 of the counterexample source).
///
/// The pure-function engine lives in `ConvertCounterexampleEngine`;
/// this struct is just the AsyncParsableCommand shell that reads
/// `@Option` values and forwards them.
extension SwiftInferCommand {

    public struct ConvertCounterexample: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "convert-counterexample",
            abstract:
                "Convert a property-test counterexample into a focused regression test."
        )

        @Option(name: .long, help: "Property template name (idempotence / round-trip / etc.).")
        public var template: String

        @Option(name: .long, help: "Function being tested (the callee from the original property test).")
        public var callee: String

        @Option(name: .long, help: "Type of the counterexample value (e.g. String / Int / [Int] / Doc).")
        public var type: String

        @Option(name: .long, help: "The counterexample expression as a Swift source string.")
        public var counterexample: String

        @Option(
            name: .long,
            help: "Reverse callee for round-trip / inverse-pair templates (e.g. decode for encode/decode)."
        )
        public var reverseCallee: String?

        @Option(
            name: .long,
            help: "Identity element source for identity-element template (e.g. 'IntSet.empty')."
        )
        public var identityElement: String?

        @Option(
            name: .long,
            help: "Seed source for reduce-equivalence template (e.g. '0' or '.zero')."
        )
        public var seedSource: String?

        @Option(
            name: .long,
            help: "Element type for reduce-equivalence / count-invariance templates (e.g. 'Int')."
        )
        public var reduceElementType: String?

        @Option(
            name: .long,
            help: "Invariant keypath for invariant-preservation template (e.g. '\\.isValid')."
        )
        public var invariantKeypath: String?

        @Option(
            name: .long,
            help: "Override the package root (defaults to walk-up from CWD looking for Package.swift)."
        )
        public var packageRoot: String?

        public init() {}

        public func run() async throws {
            let args = ConvertCounterexampleEngine.Args(
                template: template,
                callee: callee,
                type: type,
                counterexample: counterexample,
                reverseCallee: reverseCallee,
                identityElement: identityElement,
                seedSource: seedSource,
                reduceElementType: reduceElementType,
                invariantKeypath: invariantKeypath
            )
            let resolvedRoot = try ConvertCounterexampleEngine.resolvePackageRoot(
                explicit: packageRoot
            )
            let stub = try ConvertCounterexampleEngine.renderRegressionStub(args: args)
            let path = try ConvertCounterexampleEngine.writeRegressionStub(
                args: args,
                stub: stub,
                packageRoot: resolvedRoot
            )
            print("Wrote \(path.path)")
        }
    }
}
