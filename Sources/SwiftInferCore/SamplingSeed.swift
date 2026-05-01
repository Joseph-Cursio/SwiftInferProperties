import CryptoKit
import Foundation

/// Deterministic sampling-seed derivation per PRD v0.3 §16 #6. Each
/// suggestion's lifted property test (M5+) seeds its property-based
/// runner from `SamplingSeed.derive(from: suggestion.identity)` so
/// re-running the test under fixed source produces identical pass /
/// counterexample output across machines.
///
/// Specifically: `low 64 bits of SHA256(suggestion-identity-hash || "sampling")`.
/// We adopt the M4 plan's slight tightening: a `|` separator between
/// the identity hash and the literal `"sampling"` makes the input
/// unambiguous and matches the `|`-separated convention used elsewhere
/// (e.g. `SuggestionIdentity.canonicalInput`'s `"template|signature"`
/// form). Identity hashes are fixed-length (16 hex characters, see
/// `SuggestionIdentity.normalized`) so the separator is decorative
/// rather than load-bearing.
///
/// "Low 64 bits" is the LAST 8 bytes of the digest interpreted as a
/// big-endian integer — the standard cryptographic reading of a
/// 256-bit hash as a 256-bit integer makes the LSBs the trailing bytes.
/// This is intentionally a different selection from
/// `SuggestionIdentity` (which takes the FIRST 8 bytes for its hash):
/// the two SHA256 inputs are different anyway, but using
/// non-overlapping byte positions in the *output* makes accidental
/// confusion between the two impossible.
///
/// `--seed-override` (PRD §16 #6 debugging-only override) is *not*
/// modelled here. Per the PRD it is never persisted, so it lives on
/// the CLI command surface (M4.x or later) rather than in the
/// suggestion's data model.
public enum SamplingSeed {

    /// Derive the sampling seed for `identity`. Pure, deterministic,
    /// allocation-bounded.
    public static func derive(from identity: SuggestionIdentity) -> UInt64 {
        derive(fromIdentityHash: identity.normalized)
    }

    /// Derive directly from a normalized hash string. Exposed for
    /// callers that have only the textual hash (e.g. when re-deriving
    /// from a `// swiftinfer: skip` marker for cross-validation
    /// against the lifted test's recorded seed).
    public static func derive(fromIdentityHash normalized: String) -> UInt64 {
        let input = normalized + "|sampling"
        let digest = SHA256.hash(data: Data(input.utf8))
        // Take the last 8 bytes (low 64 bits, big-endian reading).
        let bytes = Array(digest).suffix(8)
        var seed: UInt64 = 0
        for byte in bytes {
            seed = (seed << 8) | UInt64(byte)
        }
        return seed
    }

    /// Render `seed` as `0x` + 16 uppercase hex characters — the
    /// canonical form rendered in `SuggestionRenderer`'s sampling line
    /// and consumed by the M5+ lifted-test stub.
    public static func renderHex(_ seed: UInt64) -> String {
        let raw = String(seed, radix: 16, uppercase: true)
        let padded = String(repeating: "0", count: 16 - raw.count) + raw
        return "0x" + padded
    }
}
