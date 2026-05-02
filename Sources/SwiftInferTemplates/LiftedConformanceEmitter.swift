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

    /// Emit a `Semigroup` conformance extension for `typeName`,
    /// aliasing the user's existing binary op (`combineWitness`) into
    /// the kit's required `static func combine(_:_:)` static. When the
    /// user's op is already named `combine`, the witness is omitted —
    /// the bare extension body satisfies the conformance via the
    /// existing static and avoids infinite-recursion on `Self.combine`.
    ///
    /// `combineWitness` is the bare function name (no parens), e.g.
    /// `"merge"` from an `Evidence.displayName` of `"merge(_:_:)"`.
    /// The witness is called as `Self.\(combineWitness)(lhs, rhs)` —
    /// resolves correctly when the user's op is a static method on the
    /// type. Free-function or instance-method ops produce a compile
    /// error in the user's project; same posture as the LiftedTestEmitter
    /// arms (the test stub doesn't compile if the user's op isn't
    /// static-shaped).
    public static func semigroup(
        typeName: String,
        combineWitness: String,
        explainability: ExplainabilityBlock
    ) -> String {
        let body = aliasingCombineBody(typeName: typeName, witness: combineWitness)
        return makeExtension(
            typeName: typeName,
            protocolName: "Semigroup",
            body: body,
            explainability: explainability
        )
    }

    /// Emit a `Monoid` conformance extension for `typeName`. `Monoid`
    /// extends `Semigroup` with an identity element witness (`a • id ==
    /// a == id • a`). Aliases both `combineWitness` (binary op) and
    /// `identityWitness` (static element name) into the kit's required
    /// `static func combine(_:_:)` and `static var identity`.
    /// Witness names matching `"combine"` / `"identity"` skip the
    /// aliasing for that arm.
    ///
    /// Example: `monoid(typeName: "Tally", combineWitness: "merge",
    /// identityWitness: "empty", ...)` produces:
    ///
    /// ```swift
    /// extension Tally: Monoid {
    ///     public static func combine(_ lhs: Tally, _ rhs: Tally) -> Tally {
    ///         Self.merge(lhs, rhs)
    ///     }
    ///     public static var identity: Tally { Self.empty }
    /// }
    /// ```
    public static func monoid(
        typeName: String,
        combineWitness: String,
        identityWitness: String,
        explainability: ExplainabilityBlock
    ) -> String {
        var bodyParts: [String] = []
        if let combine = aliasingCombineBody(typeName: typeName, witness: combineWitness) {
            bodyParts.append(combine)
        }
        if let identity = aliasingIdentityBody(typeName: typeName, witness: identityWitness) {
            bodyParts.append(identity)
        }
        let body = bodyParts.isEmpty ? nil : bodyParts.joined(separator: "\n")
        return makeExtension(
            typeName: typeName,
            protocolName: "Monoid",
            body: body,
            explainability: explainability
        )
    }

    /// Emit a `CommutativeMonoid` conformance extension for `typeName`.
    /// `CommutativeMonoid` is a kit v1.9.0 protocol that extends `Monoid`
    /// with the `combineCommutativity` Strict law — no new requirements
    /// beyond Monoid's `combine` + `identity`. M8.5 — first of the three
    /// new kit-arm conformance writeouts.
    ///
    /// Same body shape as `monoid(...)` since `CommutativeMonoid: Monoid`
    /// and the additional commutativity law doesn't introduce a new
    /// witness — the kit verifies it via sampling at law-check time. The
    /// per-protocol caveats in the §4.5 explainability block (added by
    /// M8.4.a's orchestrator) tell the user the new law is active.
    public static func commutativeMonoid(
        typeName: String,
        combineWitness: String,
        identityWitness: String,
        explainability: ExplainabilityBlock
    ) -> String {
        var bodyParts: [String] = []
        if let combine = aliasingCombineBody(typeName: typeName, witness: combineWitness) {
            bodyParts.append(combine)
        }
        if let identity = aliasingIdentityBody(typeName: typeName, witness: identityWitness) {
            bodyParts.append(identity)
        }
        let body = bodyParts.isEmpty ? nil : bodyParts.joined(separator: "\n")
        return makeExtension(
            typeName: typeName,
            protocolName: "CommutativeMonoid",
            body: body,
            explainability: explainability
        )
    }

    /// Emit a `Group` conformance extension for `typeName`. `Group` is a
    /// kit v1.9.0 protocol that extends `Monoid` with a `static func
    /// inverse(_ value: Self) -> Self` requirement — verified via the
    /// `combineLeftInverse` / `combineRightInverse` Strict laws.
    ///
    /// Aliases all three witnesses (`combineWitness`, `identityWitness`,
    /// `inverseWitness`) into the kit's required statics. Witness names
    /// matching `"combine"` / `"identity"` / `"inverse"` skip the
    /// aliasing for that arm — same self-recursion concern as the
    /// existing arms.
    ///
    /// Example: `group(typeName: "AdditiveInt", combineWitness: "plus",
    /// identityWitness: "zero", inverseWitness: "negate", ...)` produces:
    ///
    /// ```swift
    /// extension AdditiveInt: Group {
    ///     public static func combine(_ lhs: AdditiveInt, _ rhs: AdditiveInt) -> AdditiveInt {
    ///         Self.plus(lhs, rhs)
    ///     }
    ///     public static var identity: AdditiveInt { Self.zero }
    ///     public static func inverse(_ value: AdditiveInt) -> AdditiveInt {
    ///         Self.negate(value)
    ///     }
    /// }
    /// ```
    public static func group(
        typeName: String,
        combineWitness: String,
        identityWitness: String,
        inverseWitness: String,
        explainability: ExplainabilityBlock
    ) -> String {
        var bodyParts: [String] = []
        if let combine = aliasingCombineBody(typeName: typeName, witness: combineWitness) {
            bodyParts.append(combine)
        }
        if let identity = aliasingIdentityBody(typeName: typeName, witness: identityWitness) {
            bodyParts.append(identity)
        }
        if let inverse = aliasingInverseBody(typeName: typeName, witness: inverseWitness) {
            bodyParts.append(inverse)
        }
        let body = bodyParts.isEmpty ? nil : bodyParts.joined(separator: "\n")
        return makeExtension(
            typeName: typeName,
            protocolName: "Group",
            body: body,
            explainability: explainability
        )
    }

    /// Emit a `Semilattice` conformance extension for `typeName`.
    /// `Semilattice` is a kit v1.9.0 protocol that extends
    /// `CommutativeMonoid` with the `combineIdempotence` Strict law —
    /// no new requirements beyond the inherited `combine` + `identity`.
    /// Same body shape as `monoid(...)` and `commutativeMonoid(...)`.
    ///
    /// Bounded join-semilattices (`(Set<T>, ∪, ∅)`, `(Int, max, .min)`)
    /// and bounded meet-semilattices (`(Bool, &&, true)`, `(Int, min,
    /// .max)`) share this conformance — the law is symmetric.
    public static func semilattice(
        typeName: String,
        combineWitness: String,
        identityWitness: String,
        explainability: ExplainabilityBlock
    ) -> String {
        var bodyParts: [String] = []
        if let combine = aliasingCombineBody(typeName: typeName, witness: combineWitness) {
            bodyParts.append(combine)
        }
        if let identity = aliasingIdentityBody(typeName: typeName, witness: identityWitness) {
            bodyParts.append(identity)
        }
        let body = bodyParts.isEmpty ? nil : bodyParts.joined(separator: "\n")
        return makeExtension(
            typeName: typeName,
            protocolName: "Semilattice",
            body: body,
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
    /// extension scaffold and only differ in the protocol name + the
    /// per-arm witness body. Keeping the template centralised means
    /// future protocol arms (M8's CommutativeMonoid / Group /
    /// Semilattice / Ring) plug in without touching the comment-header
    /// rendering.
    ///
    /// `body` is `nil` when the user's existing surface already
    /// satisfies the protocol's requirements (witness names exactly
    /// match the protocol's required identifiers); the extension
    /// renders as `extension TypeName: Protocol {}` (bare, no body).
    /// Otherwise, the body is rendered between the `{` and `}` with
    /// the §4.5 explainability block above the `extension` line.
    private static func makeExtension(
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
    private static func aliasingCombineBody(typeName: String, witness: String) -> String? {
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
    private static func aliasingIdentityBody(typeName: String, witness: String) -> String? {
        guard witness != "identity" else { return nil }
        return """
            public static var identity: \(typeName) { Self.\(witness) }
        """
    }

    /// Render the body of a `static func inverse(_:)` aliasing the
    /// user's unary inverse function (M8.5 — Group arm). Kit v1.9.0's
    /// `Group.inverse(_ value: Self) -> Self` parameter label `value`
    /// is used here so the emitted extension matches the protocol
    /// declaration exactly. Returns `nil` when the user's static is
    /// already named `inverse` — same self-recursion concern as
    /// `aliasingCombineBody` / `aliasingIdentityBody`.
    private static func aliasingInverseBody(typeName: String, witness: String) -> String? {
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
