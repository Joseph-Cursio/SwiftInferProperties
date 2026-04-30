import ArgumentParser
import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// Root command for the `swift-infer` executable. Subcommand surface mirrors
/// the developer workflow described in PRD v0.3 §3.6:
///
/// - `discover`              — M1.3 wires it through TemplateEngine
///                             (idempotence). M1.4 adds round-trip pairing.
/// - `drift`                 — landing in M-post, see §9.
/// - `convert-counterexample` — landing in TestLifter M8, see §7.9.
/// - `metrics`               — landing alongside §17 adoption tracking.
/// - `apply`                 — v1.1+ ergonomics; see §20.6.
public struct SwiftInferCommand: AsyncParsableCommand {

    public static let configuration = CommandConfiguration(
        commandName: "swift-infer",
        abstract: "Type-directed property inference for Swift.",
        discussion: """
        Surfaces idempotence, round-trip, and algebraic-structure candidates \
        from function signatures, cross-function pairs, and existing tests. \
        All output is suggestions for human review; nothing auto-executes. \
        See `docs/SwiftInferProperties PRD v0.3.md` for the full design.
        """,
        version: "0.0.0-scaffold",
        subcommands: [Discover.self],
        defaultSubcommand: Discover.self
    )

    public init() {}
}

extension SwiftInferCommand {

    /// `swift-infer discover` — scan a target for inferred property
    /// candidates. M1.3 wires the idempotence template; M1.4 wires
    /// round-trip + cross-function pairing.
    public struct Discover: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "discover",
            abstract: "Scan a target for inferred property candidates."
        )

        @Option(
            name: .long,
            help: "Name of the SwiftPM target to scan. Resolved to Sources/<target>/ relative to the working directory."
        )
        public var target: String

        @Flag(
            name: .long,
            help: "Include `Possible` tier suggestions (score 20–39). Hidden by default per PRD §4.2."
        )
        public var includePossible: Bool = false

        public init() {}

        public func run() async throws {
            let directory = URL(fileURLWithPath: "Sources").appendingPathComponent(target)
            try Self.run(
                directory: directory,
                includePossible: includePossible,
                output: PrintOutput()
            )
        }

        /// Pure pipeline — exposed at the type level so tests exercise
        /// discovery without going through ArgumentParser or stdout.
        /// Caller passes the directory to scan, the visibility flag, and a
        /// sink for rendered output.
        public static func run(
            directory: URL,
            includePossible: Bool,
            output: any DiscoverOutput
        ) throws {
            let all = try TemplateRegistry.discover(in: directory)
            let visible = all.filter { suggestion in
                includePossible || suggestion.score.tier.isVisibleByDefault
            }
            let rendered = SuggestionRenderer.render(visible)
            output.write(rendered)
        }
    }
}

/// Sink for `Discover.run(directory:output:)`. Production code uses
/// `PrintOutput`; tests use a recording sink so they can match the rendered
/// text byte-for-byte.
public protocol DiscoverOutput {
    func write(_ text: String)
}

public struct PrintOutput: DiscoverOutput {
    public init() {}
    public func write(_ text: String) {
        print(text)
    }
}
