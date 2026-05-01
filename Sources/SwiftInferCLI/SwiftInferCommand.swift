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
            inversion: .prefixedNo,
            help: """
            Include `Possible` tier suggestions (score 20–39). Hidden by \
            default per PRD §4.2. Pass --include-possible / \
            --no-include-possible to override the project's \
            .swiftinfer/config.toml setting.
            """
        )
        public var includePossible: Bool?

        @Option(
            name: .long,
            help: """
            Path to a vocabulary file (PRD §4.5). When omitted, swift-infer \
            falls back to the path in .swiftinfer/config.toml's \
            [discover].vocabularyPath, then to the conventional \
            .swiftinfer/vocabulary.json next to Package.swift.
            """
        )
        public var vocabulary: String?

        @Option(
            name: .long,
            help: """
            Path to a config file. When omitted, swift-infer walks up \
            from the target directory to the package root and looks for \
            .swiftinfer/config.toml.
            """
        )
        public var config: String?

        public init() {}

        public func run() async throws {
            let directory = URL(fileURLWithPath: "Sources").appendingPathComponent(target)
            let explicitVocabularyPath = vocabulary.map { URL(fileURLWithPath: $0) }
            let explicitConfigPath = config.map { URL(fileURLWithPath: $0) }
            try Self.run(
                directory: directory,
                includePossible: includePossible,
                explicitVocabularyPath: explicitVocabularyPath,
                explicitConfigPath: explicitConfigPath,
                output: PrintOutput(),
                diagnostics: PrintDiagnosticOutput()
            )
        }

        /// Pure pipeline — exposed at the type level so tests exercise
        /// discovery without going through ArgumentParser or stdout.
        ///
        /// Precedence per the M2 plan: CLI > config > defaults. A `nil`
        /// `includePossible` means "no CLI flag passed; let config (or
        /// the default) decide". A non-nil value wins over both. Same
        /// shape for `explicitVocabularyPath`: when nil, the CLI looks
        /// at `[discover].vocabularyPath` in config; when also unset
        /// there, falls back to the conventional walk-up location.
        public static func run(
            directory: URL,
            includePossible: Bool? = nil,
            explicitVocabularyPath: URL? = nil,
            explicitConfigPath: URL? = nil,
            output: any DiscoverOutput,
            diagnostics: any DiagnosticOutput = PrintDiagnosticOutput()
        ) throws {
            let configResult = ConfigLoader.load(
                startingFrom: directory,
                explicitPath: explicitConfigPath
            )
            for warning in configResult.warnings {
                diagnostics.writeDiagnostic("warning: \(warning)")
            }
            let effectiveIncludePossible =
                includePossible ?? configResult.config.includePossible
            let effectiveVocabularyPath = resolveVocabularyPath(
                cliOverride: explicitVocabularyPath,
                configValue: configResult.config.vocabularyPath,
                packageRoot: configResult.packageRoot
            )

            let vocabResult = VocabularyLoader.load(
                startingFrom: directory,
                explicitPath: effectiveVocabularyPath
            )
            for warning in vocabResult.warnings {
                diagnostics.writeDiagnostic("warning: \(warning)")
            }
            let all = try TemplateRegistry.discover(
                in: directory,
                vocabulary: vocabResult.vocabulary,
                diagnostic: { diagnostics.writeDiagnostic($0) }
            )
            let visible = all.filter { suggestion in
                effectiveIncludePossible || suggestion.score.tier.isVisibleByDefault
            }
            let rendered = SuggestionRenderer.render(visible)
            output.write(rendered)
        }

        /// Resolve the vocabulary path with CLI > config > implicit-walk-up
        /// precedence. Relative paths in config are resolved against the
        /// package root the config loader walked up to; absolute paths
        /// pass through unchanged. Absoluteness is checked on the raw
        /// string — `URL(fileURLWithPath:)` would otherwise re-anchor a
        /// relative path against the current working directory before we
        /// got the chance to join it with the package root.
        private static func resolveVocabularyPath(
            cliOverride: URL?,
            configValue: String?,
            packageRoot: URL?
        ) -> URL? {
            if let cliOverride {
                return cliOverride
            }
            guard let raw = configValue else {
                return nil
            }
            if raw.hasPrefix("/") {
                return URL(fileURLWithPath: raw)
            }
            if let packageRoot {
                return packageRoot.appendingPathComponent(raw)
            }
            return URL(fileURLWithPath: raw)
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

/// Sink for diagnostic warnings (vocabulary load failures, etc.). Kept
/// separate from `DiscoverOutput` so warnings reach stderr without
/// disturbing the byte-stable suggestion stream on stdout — PRD §16's
/// reproducibility guarantee depends on stdout being a function of
/// (target sources, vocabulary, config) only.
public protocol DiagnosticOutput {
    func writeDiagnostic(_ text: String)
}

public struct PrintDiagnosticOutput: DiagnosticOutput {
    public init() {}
    public func writeDiagnostic(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}
