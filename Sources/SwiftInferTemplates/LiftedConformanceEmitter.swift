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
///
/// Stdlib arms (`setAlgebra`, `numeric`) live in
/// `LiftedConformanceEmitter+Stdlib.swift`; the shared rendering
/// helpers (extension scaffold + witness aliasing + §4.5 header
/// rendering) live in `LiftedConformanceTemplate.swift`.
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
    /// arms.
    public static func semigroup(
        typeName: String,
        combineWitness: String,
        explainability: ExplainabilityBlock
    ) -> String {
        let body = LiftedConformanceTemplate.aliasingCombineBody(
            typeName: typeName,
            witness: combineWitness
        )
        return LiftedConformanceTemplate.makeExtension(
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
        let body = makeMonoidBody(
            typeName: typeName,
            combineWitness: combineWitness,
            identityWitness: identityWitness
        )
        return LiftedConformanceTemplate.makeExtension(
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
    /// witness — the kit verifies it via sampling at law-check time.
    public static func commutativeMonoid(
        typeName: String,
        combineWitness: String,
        identityWitness: String,
        explainability: ExplainabilityBlock
    ) -> String {
        let body = makeMonoidBody(
            typeName: typeName,
            combineWitness: combineWitness,
            identityWitness: identityWitness
        )
        return LiftedConformanceTemplate.makeExtension(
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
    /// aliasing for that arm.
    public static func group(
        typeName: String,
        combineWitness: String,
        identityWitness: String,
        inverseWitness: String,
        explainability: ExplainabilityBlock
    ) -> String {
        var bodyParts: [String] = []
        if let combine = LiftedConformanceTemplate.aliasingCombineBody(
            typeName: typeName, witness: combineWitness
        ) {
            bodyParts.append(combine)
        }
        if let identity = LiftedConformanceTemplate.aliasingIdentityBody(
            typeName: typeName, witness: identityWitness
        ) {
            bodyParts.append(identity)
        }
        if let inverse = LiftedConformanceTemplate.aliasingInverseBody(
            typeName: typeName, witness: inverseWitness
        ) {
            bodyParts.append(inverse)
        }
        let body = bodyParts.isEmpty ? nil : bodyParts.joined(separator: "\n")
        return LiftedConformanceTemplate.makeExtension(
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
    /// .max)`) share this conformance.
    public static func semilattice(
        typeName: String,
        combineWitness: String,
        identityWitness: String,
        explainability: ExplainabilityBlock
    ) -> String {
        let body = makeMonoidBody(
            typeName: typeName,
            combineWitness: combineWitness,
            identityWitness: identityWitness
        )
        return LiftedConformanceTemplate.makeExtension(
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
    /// should land at, under the `writeoutPathPrefix`.
    public static func relativePath(typeName: String, protocolName: String) -> String {
        "\(writeoutPathPrefix)/\(typeName)/\(protocolName).swift"
    }

    /// Shared body composition for Monoid / CommutativeMonoid /
    /// Semilattice — all three protocols extend Monoid with no new
    /// witnesses, so the body is identical (combine + identity
    /// aliases). Group adds a third arm and lives separately.
    private static func makeMonoidBody(
        typeName: String,
        combineWitness: String,
        identityWitness: String
    ) -> String? {
        var bodyParts: [String] = []
        if let combine = LiftedConformanceTemplate.aliasingCombineBody(
            typeName: typeName, witness: combineWitness
        ) {
            bodyParts.append(combine)
        }
        if let identity = LiftedConformanceTemplate.aliasingIdentityBody(
            typeName: typeName, witness: identityWitness
        ) {
            bodyParts.append(identity)
        }
        return bodyParts.isEmpty ? nil : bodyParts.joined(separator: "\n")
    }
}
