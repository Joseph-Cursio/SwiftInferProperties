import SwiftInferCore

/// Pure rendering helpers for `LiftedConformanceEmitter`. Internal
/// namespace within `SwiftInferTemplates` — the public emitter arms
/// dispatch into these for the shared extension-scaffold + witness-
/// aliasing + §4.5 header rendering.
enum LiftedConformanceTemplate {

    /// One template covers every arm — they share the extension
    /// scaffold and only differ in the protocol name + the per-arm
    /// witness body. Keeping the template centralised means future
    /// protocol arms plug in without touching the comment-header
    /// rendering.
    ///
    /// `body` is `nil` when the user's existing surface already
    /// satisfies the protocol's requirements (witness names exactly
    /// match the protocol's required identifiers); the extension
    /// renders as `extension TypeName: Protocol {}` (bare, no body).
    /// Otherwise, the body is rendered between the `{` and `}` with
    /// the §4.5 explainability block above the `extension` line.
    static func makeExtension(
        typeName: String,
        protocolName: String,
        body: String?,
        explainability: ExplainabilityBlock
    ) -> String {
        let header = renderExplainabilityHeader(
            typeName: typeName,
            protocolName: protocolName,
            explainability: explainability
        )
        guard let body, !body.isEmpty else {
            return """

            \(header)
            extension \(typeName): \(protocolName) {}
            """
        }
        return """

        \(header)
        extension \(typeName): \(protocolName) {
        \(body)
        }
        """
    }

    /// Render the body of a `static func combine(_:_:)` aliasing the
    /// user's binary op. Returns `nil` when the user's op is already
    /// named `combine` — the existing static satisfies the requirement
    /// directly, and emitting an aliasing `Self.combine(lhs, rhs)`
    /// would recurse infinitely at runtime.
    static func aliasingCombineBody(typeName: String, witness: String) -> String? {
        guard witness != "combine" else { return nil }
        return """
            public static func combine(_ lhs: \(typeName), _ rhs: \(typeName)) -> \(typeName) {
                Self.\(witness)(lhs, rhs)
            }
        """
    }

    /// Render the body of a `static var identity` aliasing the user's
    /// identity element. Returns `nil` when the user's static is
    /// already named `identity` — same self-recursion concern as
    /// `aliasingCombineBody`.
    static func aliasingIdentityBody(typeName: String, witness: String) -> String? {
        guard witness != "identity" else { return nil }
        return """
            public static var identity: \(typeName) { Self.\(witness) }
        """
    }

    /// Render the body of a `static func inverse(_:)` aliasing the
    /// user's unary inverse function (M8.5 — Group arm). Kit v1.9.0's
    /// `Group.inverse(_ value: Self) -> Self` parameter label `value`
    /// is used here so the emitted extension matches the protocol
    /// declaration exactly.
    static func aliasingInverseBody(typeName: String, witness: String) -> String? {
        guard witness != "inverse" else { return nil }
        return """
            public static func inverse(_ value: \(typeName)) -> \(typeName) {
                Self.\(witness)(value)
            }
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
