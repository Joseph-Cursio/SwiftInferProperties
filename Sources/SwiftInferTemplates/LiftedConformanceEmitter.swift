import SwiftInferCore

/// Pure-function emit of a Swift `extension TypeName: Protocol {}`
/// source string for SwiftInfer's RefactorBridge (PRD v0.4 §6 +
/// M7.4 plan row). Parallel to `LiftedTestEmitter` but operates on
/// type + protocol inputs instead of function + property.
///
/// The emitted file is consumed by:
///
/// - `SwiftInferCLI.RefactorBridgeOrchestrator` (M7.5) — wraps the
///   returned string with the M6.4-style provenance header and writes
///   to `Tests/Generated/SwiftInferRefactors/<TypeName>/<ProtocolName>.swift`
///   per PRD §16 #1's allowlist extension.
/// - the user, who reads the writeout, decides whether the conformance
///   makes sense, and either applies it directly or edits the
///   suggestion.
///
/// Output is column-0 (no leading indent) and includes one leading
/// newline so the emitted block reads as a standalone declaration when
/// concatenated with file-level imports. The §4.5 explainability
/// "why suggested / why this might be wrong" block renders as a
/// comment header above the extension so the developer reading the
/// writeout sees the same justification the CLI rendered.
public enum LiftedConformanceEmitter {

    /// Emit a `Semigroup` conformance extension for `typeName`.
    /// `Semigroup`'s only law is associativity (`(a • b) • c == a • (b • c)`);
    /// the conformance asserts that the user's type satisfies it under
    /// some user-supplied binary op. The actual op witness is supplied
    /// by the user's existing type definition — this emitter only
    /// declares the conformance.
    public static func semigroup(
        typeName: String,
        explainability: ExplainabilityBlock
    ) -> String {
        makeExtension(
            typeName: typeName,
            protocolName: "Semigroup",
            explainability: explainability
        )
    }

    /// Emit a `Monoid` conformance extension for `typeName`. `Monoid`
    /// extends `Semigroup` with an identity element witness (`a • id ==
    /// a == id • a`). As with `semigroup`, the actual witnesses are
    /// supplied by the user's existing type definition.
    public static func monoid(
        typeName: String,
        explainability: ExplainabilityBlock
    ) -> String {
        makeExtension(
            typeName: typeName,
            protocolName: "Monoid",
            explainability: explainability
        )
    }

    /// Path convention for RefactorBridge writeouts per PRD §16 #1's
    /// allowlist extension. M7.5's orchestrator composes the relative
    /// path as `<root>/<TypeName>/<ProtocolName>.swift`; M7.6's hard-
    /// guarantee tests assert no writeout escapes this prefix.
    public static let writeoutPathPrefix = "Tests/Generated/SwiftInferRefactors"

    /// Compose the relative path a writeout for `(typeName, protocolName)`
    /// should land at, under the `writeoutPathPrefix`. Returned as a
    /// forward-slash POSIX-shaped string; M7.5 converts to a `URL` via
    /// `appendingPathComponent` so the path operator's separator
    /// matches the host filesystem.
    public static func relativePath(typeName: String, protocolName: String) -> String {
        "\(writeoutPathPrefix)/\(typeName)/\(protocolName).swift"
    }

    // MARK: - Shared extension shape

    /// One template covers both arms — semigroup and monoid share the
    /// extension scaffold and only differ in the protocol name. Keeping
    /// the template centralised means future protocol arms (M8's
    /// CommutativeMonoid / Group / Semilattice / Ring) plug in without
    /// touching the comment-header rendering.
    private static func makeExtension(
        typeName: String,
        protocolName: String,
        explainability: ExplainabilityBlock
    ) -> String {
        let header = renderExplainabilityHeader(
            typeName: typeName,
            protocolName: protocolName,
            explainability: explainability
        )
        return """

        \(header)
        extension \(typeName): \(protocolName) {}
        """
    }

    /// Render the §4.5 explainability block as a Swift comment header.
    /// Empty arrays render an explicit "no entries" line so the reader
    /// can distinguish "no caveats apply" from "the emitter forgot to
    /// populate them."
    private static func renderExplainabilityHeader(
        typeName: String,
        protocolName: String,
        explainability: ExplainabilityBlock
    ) -> String {
        var lines: [String] = []
        lines.append("// SwiftInfer RefactorBridge — \(typeName): \(protocolName)")
        lines.append("//")
        lines.append("// Why suggested:")
        if explainability.whySuggested.isEmpty {
            lines.append("//   (no signals recorded)")
        } else {
            for entry in explainability.whySuggested {
                lines.append("//   - \(entry)")
            }
        }
        lines.append("//")
        lines.append("// Why this might be wrong:")
        if explainability.whyMightBeWrong.isEmpty {
            lines.append("//   (no caveats recorded)")
        } else {
            for entry in explainability.whyMightBeWrong {
                lines.append("//   - \(entry)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
