import CryptoKit
import Foundation

/// Deterministic sampling-seed derivation per PRD v0.4 §16 #6. Each
/// suggestion's lifted property test (M5+) seeds its property-based
/// runner from `SamplingSeed.derive(from: suggestion.identity)` so
/// re-running the test under fixed source produces identical pass /
/// counterexample output across machines.
///
/// **Spec (PRD v0.4 §16 #6):** all 256 bits of
/// `SHA256(suggestion-identity-hash || "|sampling")` packed as four
/// big-endian `UInt64`s for the `Xoshiro256**` state. The v0.3 spec
/// read "low 64 bits of SHA256(...)"; v0.4 widened to 256 bits because
/// that's the upstream `Xoshiro256**` state-space size, and the
/// K-prep-M2 audit on the SwiftProtocolLaws side surfaced the API
/// mismatch (`ProtocolLawKit.Seed(stateA:stateB:stateC:stateD:)` takes
/// four `UInt64`s).
///
/// The `|` separator between the identity hash and the literal
/// `"sampling"` makes the input unambiguous and matches the
/// `|`-separated convention `SuggestionIdentity.canonicalInput` uses.
///
/// Returned type is `SamplingSeed.Value` (this enum's nested
/// 4-`UInt64` value type) rather than `ProtocolLawKit.Seed` directly
/// — `ProtocolLawKit` transitively pulls `Testing.framework`, which
/// the SwiftInfer runtime targets explicitly exclude (see
/// `Package.swift:35-38`). Downstream consumers
/// (M5.2's `@CheckProperty` macro expansion, anywhere that wants to
/// hand the seed to `SwiftPropertyBasedBackend.check(seed:)`)
/// translate `Value` to `Seed` at the test-emission site, where
/// `import ProtocolLawKit` is appropriate.
///
/// `--seed-override` (PRD §16 #6 debugging-only override) is *not*
/// modelled here. Per the PRD v0.4 it is v1.1+ — no v1 milestone owner.
public enum SamplingSeed {

    /// 256-bit Xoshiro state, four `UInt64`s. Matches the layout of
    /// `ProtocolLawKit.Seed` 1:1 so a downstream test target can
    /// construct `Seed(stateA:stateB:stateC:stateD:)` field-for-field.
    /// Equatable + Sendable + Hashable so it composes cleanly into
    /// suggestion-rendering equality checks.
    public struct Value: Sendable, Equatable, Hashable {
        public let stateA: UInt64
        public let stateB: UInt64
        public let stateC: UInt64
        public let stateD: UInt64

        public init(stateA: UInt64, stateB: UInt64, stateC: UInt64, stateD: UInt64) {
            self.stateA = stateA
            self.stateB = stateB
            self.stateC = stateC
            self.stateD = stateD
        }
    }

    /// Derive the sampling seed for `identity`. Pure, deterministic,
    /// allocation-bounded.
    public static func derive(from identity: SuggestionIdentity) -> Value {
        derive(fromIdentityHash: identity.normalized)
    }

    /// Derive directly from a normalized hash string. Exposed for
    /// callers that have only the textual hash (e.g. when re-deriving
    /// from a `// swiftinfer: skip` marker for cross-validation
    /// against the lifted test's recorded seed).
    public static func derive(fromIdentityHash normalized: String) -> Value {
        let input = normalized + "|sampling"
        let digest = SHA256.hash(data: Data(input.utf8))
        let bytes = Array(digest)
        // SHA256 outputs 32 bytes; pack as four big-endian UInt64s in
        // source order so the "first 64 bits" of the digest land in
        // `stateA` (matches the standard cryptographic reading of a
        // 256-bit digest as a big-endian 256-bit integer).
        return Value(
            stateA: packUInt64(bytes, offset: 0),
            stateB: packUInt64(bytes, offset: 8),
            stateC: packUInt64(bytes, offset: 16),
            stateD: packUInt64(bytes, offset: 24)
        )
    }

    /// Render `seed` as `0x` + 64 uppercase hex characters
    /// (`stateA stateB stateC stateD`, each 16 hex chars, packed
    /// continuously). The canonical form rendered in
    /// `SuggestionRenderer`'s sampling line and consumed by the M5+
    /// lifted-test stub when it parses the seed back.
    public static func renderHex(_ seed: Value) -> String {
        let parts = [seed.stateA, seed.stateB, seed.stateC, seed.stateD].map { renderState($0) }
        return "0x" + parts.joined()
    }

    private static func packUInt64(_ bytes: [UInt8], offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value = (value << 8) | UInt64(bytes[offset + index])
        }
        return value
    }

    private static func renderState(_ state: UInt64) -> String {
        let raw = String(state, radix: 16, uppercase: true)
        return String(repeating: "0", count: 16 - raw.count) + raw
    }
}
