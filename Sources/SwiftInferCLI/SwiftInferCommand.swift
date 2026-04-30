import ArgumentParser

/// Root command for the `swift-infer` executable. Subcommand surface mirrors
/// the developer workflow described in PRD v0.3 §3.6:
///
/// - `discover`              — M1.1 stub; M1 wires it through TemplateEngine.
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
    /// candidates. M1.1 stub; M1.3 wires the idempotence template, M1.4 wires
    /// round-trip + cross-function pairing.
    public struct Discover: AsyncParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "discover",
            abstract: "Scan a target for inferred property candidates."
        )

        @Option(
            name: .long,
            help: "Name of the SwiftPM target to scan."
        )
        public var target: String

        public init() {}

        public func run() async throws {
            print("no suggestions yet (M1.1 scaffold)")
            print("scanned target: \(target)")
        }
    }
}
