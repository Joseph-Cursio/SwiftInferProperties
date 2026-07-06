import SwiftInferCore

/// The outcome of verifying one value-semantics candidate. Polarity-correct for
/// value semantics: a **confirmed leak** is the payoff (a real bug found), not a
/// suppression — the inverse of the interaction families, where a measured
/// failure means the suggestion was wrong.
public struct ValueSemanticVerifyResult: Equatable, Sendable {

    public let typeName: String
    public let location: SourceLocation
    public let status: Status

    public enum Status: Equatable, Sendable {
        /// Measured `defaultFails` — the type leaks. `repro` is the kit's
        /// already-shrunk minimal reproduction (from `VERIFY_DEFAULT_INPUT`).
        case confirmedLeak(repro: String)
        /// Measured `bothPass` — the copy-mutate-compare law holds.
        case verifiedSafe
        /// Recognized but not verify-ready (gated before building): non-`Equatable`
        /// or no payload-free mutation method.
        case notVerifiable(reason: String)
        /// The verifier didn't compile — commonly the self-contained-packaging
        /// limitation (non-`public` types / external dependencies).
        case buildFailed(detail: String)
        /// A runtime or parse error while verifying.
        case error(reason: String)
    }

    public init(typeName: String, location: SourceLocation, status: Status) {
        self.typeName = typeName
        self.location = location
        self.status = status
    }

    /// `true` for a confirmed leak — used by the `--fail-on-leak` CI gate.
    public var isConfirmedLeak: Bool {
        if case .confirmedLeak = status { return true }
        return false
    }
}
