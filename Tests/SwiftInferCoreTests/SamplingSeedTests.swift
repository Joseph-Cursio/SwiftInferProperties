import CryptoKit
import Foundation
import Testing
@testable import SwiftInferCore

@Suite("SamplingSeed — PRD §16 #6 deterministic seed derivation (M4.3)")
struct SamplingSeedTests {

    // MARK: - Determinism + reproducibility

    @Test
    func sameIdentityProducesSameSeed() {
        let identity = SuggestionIdentity(canonicalInput: "idempotence|Foo.normalize(_:)|(String)->String")
        let first = SamplingSeed.derive(from: identity)
        let second = SamplingSeed.derive(from: identity)
        #expect(first == second)
    }

    @Test
    func reDerivingFromTheNormalizedHashMatchesIdentityDerivation() {
        // §16 #6 reproducibility: callers that have only the
        // normalized hash text (e.g. when re-running sampling against
        // a `// swiftinfer: skip` marker's recorded hash) must get
        // exactly the same seed as callers that have the full
        // SuggestionIdentity value.
        let identity = SuggestionIdentity(canonicalInput: "round-trip|encode|decode")
        let viaIdentity = SamplingSeed.derive(from: identity)
        let viaHash = SamplingSeed.derive(fromIdentityHash: identity.normalized)
        #expect(viaIdentity == viaHash)
    }

    // MARK: - Independence

    @Test
    func differentIdentitiesProduceDifferentSeeds() {
        let alpha = SuggestionIdentity(canonicalInput: "idempotence|alpha")
        let beta = SuggestionIdentity(canonicalInput: "idempotence|beta")
        #expect(SamplingSeed.derive(from: alpha) != SamplingSeed.derive(from: beta))
    }

    @Test
    func samplingSeedIsIndependentOfTheIdentityFirst8Bytes() {
        // SuggestionIdentity uses the FIRST 8 bytes of its SHA256;
        // SamplingSeed uses the LAST 8 bytes of a DIFFERENT SHA256
        // (with "|sampling" appended). The two values must NOT match
        // — that decoupling is what makes the seed independent
        // entropy from the identity hash itself.
        let identity = SuggestionIdentity(canonicalInput: "idempotence|Sample.run(_:)|(Int)->Int")
        let identityAsUInt64 = UInt64(identity.normalized, radix: 16) ?? 0
        let seed = SamplingSeed.derive(from: identity)
        #expect(seed != identityAsUInt64)
    }

    // MARK: - Hex rendering

    @Test
    func renderHexIsAlwaysSixteenUppercaseHexCharsWithPrefix() {
        let identity = SuggestionIdentity(canonicalInput: "idempotence|hex-test")
        let seed = SamplingSeed.derive(from: identity)
        let hex = SamplingSeed.renderHex(seed)
        #expect(hex.hasPrefix("0x"))
        #expect(hex.count == 18) // "0x" + 16 hex chars
        let bare = String(hex.dropFirst(2))
        #expect(bare.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isUppercase) })
    }

    @Test
    func renderHexZeroPadsSmallSeeds() {
        // A small seed (e.g. 0x42) must render with leading zeros so
        // the hex form is always exactly 16 chars after `0x`. The
        // M5+ lifted-test stub may parse this back; truncating to a
        // shorter form would produce a different UInt64 on round-trip.
        #expect(SamplingSeed.renderHex(0x42) == "0x0000000000000042")
        #expect(SamplingSeed.renderHex(0) == "0x0000000000000000")
        #expect(SamplingSeed.renderHex(.max) == "0xFFFFFFFFFFFFFFFF")
    }

    // MARK: - Spec — the literal §16 #6 input shape

    @Test
    func derivationInputIsTheNormalizedHashPlusPipeSampling() {
        // Pin the exact input convention the M4 plan specifies so a
        // future contributor doesn't accidentally drop the `|`
        // separator (which would shift every seed in lockstep but
        // still be deterministic — silent breakage). Re-derive
        // manually here; if the SamplingSeed implementation diverges
        // from the spec, this test catches it.
        let identity = SuggestionIdentity(canonicalInput: "idempotence|spec-anchor")
        let manualInput = identity.normalized + "|sampling"
        let manualSeed = referenceLow64BitsSHA256(manualInput)
        #expect(SamplingSeed.derive(from: identity) == manualSeed)
    }

    /// Recompute the §16 #6 derivation independently — same SHA256
    /// hash, last-8-bytes-as-big-endian-UInt64. Used to pin the spec
    /// against accidental drift in `SamplingSeed.derive`.
    private func referenceLow64BitsSHA256(_ input: String) -> UInt64 {
        // Defer to the same CryptoKit primitive the production code
        // uses; the point of this helper is to exercise the
        // *concatenation* convention, not to re-implement SHA256.
        let digest = SHA256.hash(data: Data(input.utf8))
        let bytes = Array(digest).suffix(8)
        var result: UInt64 = 0
        for byte in bytes {
            result = (result << 8) | UInt64(byte)
        }
        return result
    }
}
